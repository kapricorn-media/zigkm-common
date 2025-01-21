const std = @import("std");
const A = std.mem.Allocator;

const m = @import("zigkm-math");
const zigimg = @import("zigimg");

const ANDROID_API_MIN = 21;

const c = @cImport({
    @cDefine("__ANDROID_API__", std.fmt.comptimePrint("{}", .{ANDROID_API_MIN}));
    @cInclude("jni.h");
    @cInclude("android/asset_manager_jni.h");
    @cInclude("android/configuration.h");
    @cInclude("android/log.h");
    @cInclude("android/looper.h");
    @cInclude("android/native_activity.h");
    @cInclude("android/native_window.h");
    @cInclude("android/sensor.h");

    @cInclude("EGL/egl.h");
    @cInclude("GLES/gl.h");
    // @cInclude("GLES2/gl2.h");
    @cInclude("GLES3/gl3.h");
});

pub usingnamespace c;

const asset_data = @import("asset_data.zig");

var _state = &@import("android_exports.zig")._state;

pub fn loadEntireFile(path: [:0]const u8, assetManager: *c.AAssetManager, a: A) ![]const u8
{
    const asset = c.AAssetManager_open(assetManager, path, c.AASSET_MODE_BUFFER);
    if (asset == null) {
        return error.AAssetManager_open;
    }
    defer c.AAsset_close(asset);

    const size: usize = @intCast(c.AAsset_getLength64(asset));
    var buf = try a.alloc(u8, size);
    const result = c.AAsset_read(asset, &buf[0], size);
    if (result != size) {
        std.log.err("AAsset_read failed, {} expected {}", .{result, size});
        return error.AAsset_read;
    }

    return buf;
}

pub fn compileShaders(vertFile: [:0]const u8, fragFile: [:0]const u8, assetManager: *c.AAssetManager, a: A) !c.GLuint
{
    const vertSource = try loadEntireFile(vertFile, assetManager, a);
    const vertId = try compileShader(vertSource, c.GL_VERTEX_SHADER);
    const fragSource = try loadEntireFile(fragFile, assetManager, a);
    const fragId = try compileShader(fragSource, c.GL_FRAGMENT_SHADER);

    const programId = c.glCreateProgram();
    errdefer c.glDeleteProgram(programId);
    c.glAttachShader(programId, vertId);
    c.glAttachShader(programId, fragId);
    c.glLinkProgram(programId);
    var status: c.GLint = undefined;
    c.glGetProgramiv(programId, c.GL_LINK_STATUS, &status);
    if (status != c.GL_TRUE) {
        return error.glLinkProgram;
    }

    return programId;
}

fn compileShader(source: []const u8, shaderType: c.GLenum) !c.GLuint
{
    const shaderId = c.glCreateShader(shaderType);
    if (shaderId == 0) {
        return error.glCreateShader;
    }
    const sourceLen: c.GLint = @intCast(source.len);
    c.glShaderSource(shaderId, 1, &source.ptr, &sourceLen);
    c.glCompileShader(shaderId);
    var status: c.GLint = undefined;
    c.glGetShaderiv(shaderId, c.GL_COMPILE_STATUS, &status);
    if (status != c.GL_TRUE) {
        var logBuf: [1024]u8 = undefined;
        var logBufLength: c.GLsizei = undefined;
        c.glGetShaderInfoLog(shaderId, logBuf.len, &logBufLength, &logBuf[0]);
        std.log.err("Error when compiling shader:\n{s}", .{logBuf[0..@intCast(logBufLength)]});
        return error.glCompileShader;
    }
    return shaderId;
}

pub fn getAttributeLocation(programId: c.GLuint, attributeName: [:0]const u8) !c.GLuint
{
    const loc = c.glGetAttribLocation(programId, attributeName.ptr);
    if (loc == -1) {
        std.log.err("getAttributeLocation failed for {s}", .{attributeName});
        return error.glGetAttribLocation;
    }
    return @intCast(loc);
}

pub fn getUniformLocation(programId: c.GLuint, uniformName: [:0]const u8) !c.GLint
{
    const loc = c.glGetUniformLocation(programId, uniformName.ptr);
    if (loc == -1) {
        std.log.err("getUniformLocation failed for {s}", .{uniformName});
        return error.glGetUniformLocation;
    }
    return loc;
}

pub fn loadTexture(image: zigimg.Image, wrap: asset_data.TextureWrapMode, filter: asset_data.TextureFilter) !c.GLuint
{
    var textureId: c.GLuint = undefined;
    c.glGenTextures(1, &textureId);
    c.glBindTexture(c.GL_TEXTURE_2D, textureId);
    var pixelBytes: []const u8 = undefined;
    var internalFormat: c.GLint = undefined;
    var format: c.GLuint = undefined;
    switch (image.pixels) {
        .grayscale8 => |r8| {
            pixelBytes = std.mem.sliceAsBytes(r8);
            internalFormat = c.GL_R8;
            format = c.GL_RED;
        },
        .rgba32 => |rgba32| {
            pixelBytes = std.mem.sliceAsBytes(rgba32);
            internalFormat = c.GL_RGBA8;
            format = c.GL_RGBA;
        },
        else => {
            std.log.err("Unsupported image format {}", .{std.meta.activeTag(image.pixels)});
            return error.UnsupportedImageFormat;
        },
    }
    c.glTexImage2D(c.GL_TEXTURE_2D, 0, internalFormat, @intCast(image.width), @intCast(image.height), 0, format, c.GL_UNSIGNED_BYTE, pixelBytes.ptr);
    const wrapGl = switch (wrap) {
        .clampToEdge => c.GL_CLAMP_TO_EDGE,
        .repeat => c.GL_REPEAT,
    };
    const filterGl = switch (filter) {
        .linear => c.GL_LINEAR,
        .nearest => c.GL_NEAREST,
    };
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, wrapGl);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, wrapGl);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, filterGl);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, filterGl);

    return textureId;
}

pub fn displayKeyboard(show: bool) void
{
    const activity = _state.*.activity;

    // Attaches the current thread to the JVM
    const lJavaVM = activity.vm;
    var lJNIEnv = activity.env;

    var lJavaVMAttachArgs: c.JavaVMAttachArgs = undefined;
    lJavaVMAttachArgs.version = c.JNI_VERSION_1_6;
    lJavaVMAttachArgs.name = "NativeThread";
    lJavaVMAttachArgs.group = c.NULL;

    const result1 = lJavaVM.*.*.AttachCurrentThread.?(lJavaVM, &lJNIEnv, &lJavaVMAttachArgs);
    if (result1 == c.JNI_ERR) {
        return;
    }
    defer {
        const result2 = lJavaVM.*.*.DetachCurrentThread.?(lJavaVM);
        _ = result2; // TODO ??
    }

    // Retrieves NativeActivity instance.
    const lNativeActivity = activity.clazz;
    const classNativeActivity = lJNIEnv.*.*.GetObjectClass.?(lJNIEnv, lNativeActivity);

    // Calls NativeActivity method showKeyboard(show)
    const methodTest = lJNIEnv.*.*.GetMethodID.?(lJNIEnv, classNativeActivity, "showKeyboard", "(Z)V");
    lJNIEnv.*.*.CallVoidMethod.?(lJNIEnv, lNativeActivity, methodTest, show);
}

pub fn jniToZigString(env: *c.JNIEnv, str: c.jstring, a: A) ![]const u8
{
    const length = env.*.*.GetStringLength.?(env, str);
    const chars = env.*.*.GetStringChars.?(env, str, null);
    defer env.*.*.ReleaseStringChars.?(env, str, chars);

    const u16Ptr: [*]const u16 = chars;
    const u16Slice: []const u16 = u16Ptr[0..@intCast(length)];
    return std.unicode.utf16LeToUtf8Alloc(a, u16Slice);
}

pub fn zigToJniString(env: *c.JNIEnv, str: []const u8, a: A) !c.jstring
{
    const strZ = try a.dupeZ(u8, str);
    return env.*.*.NewStringUTF.?(env, strZ);
}

pub fn jniToZigByteArray(env: *c.JNIEnv, array: c.jbyteArray, a: A) ![]const u8
{
    const length = env.*.*.GetArrayLength.?(env, array);
    const bytes = env.*.*.GetByteArrayElements.?(env, array, null);
    defer env.*.*.ReleaseByteArrayElements.?(env, array, bytes, 0);

    const bytesSlice: []const u8 = @ptrCast(bytes[0..@intCast(length)]);
    const slice = try a.alloc(u8, @intCast(length));
    @memcpy(slice, bytesSlice);
    return slice;
}

pub fn zigToJniByteArray(env: *c.JNIEnv, array: []const u8) c.jbyteArray
{
    const byteArray = env.*.*.NewByteArray.?(env, @intCast(array.len));
    const bytes = env.*.*.GetByteArrayElements.?(env, byteArray, null);
    const bytesSlice: []u8 = @ptrCast(bytes[0..array.len]);
    @memcpy(bytesSlice, array);
    env.*.*.ReleaseByteArrayElements.?(env, byteArray, bytes, 0);
    return byteArray;
}

pub fn httpRequest(method: std.http.Method, url: []const u8, h1: []const u8, v1: []const u8, body: []const u8, a: A) void
{
    const activity = _state.*.activity;

    // Attaches the current thread to the JVM
    const lJavaVM = activity.vm;
    var lJNIEnv = activity.env;

    var lJavaVMAttachArgs: c.JavaVMAttachArgs = undefined;
    lJavaVMAttachArgs.version = c.JNI_VERSION_1_6;
    lJavaVMAttachArgs.name = "NativeThread";
    lJavaVMAttachArgs.group = c.NULL;

    const result1 = lJavaVM.*.*.AttachCurrentThread.?(lJavaVM, &lJNIEnv, &lJavaVMAttachArgs);
    if (result1 == c.JNI_ERR) {
        return;
    }
    defer {
        const result2 = lJavaVM.*.*.DetachCurrentThread.?(lJavaVM);
        _ = result2; // TODO ??
    }

    // Retrieves NativeActivity instance.
    const lNativeActivity = activity.clazz;
    const classNativeActivity = lJNIEnv.*.*.GetObjectClass.?(lJNIEnv, lNativeActivity);

    // Calls NativeActivity method httpRequest
    const methodTest = lJNIEnv.*.*.GetMethodID.?(lJNIEnv, classNativeActivity, "httpRequest", "(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;[B)[B");
    const methodInt: i32 = switch (method) {
        .GET => 0,
        .POST => 1,
        else => 2,
    };
    const urlString = zigToJniString(lJNIEnv, url, a) catch return; // TODO
    const h1String = zigToJniString(lJNIEnv, h1, a) catch return; // TODO
    const v1String = zigToJniString(lJNIEnv, v1, a) catch return; // TODO
    const bodyByteArray = zigToJniByteArray(lJNIEnv, body);
    const result = lJNIEnv.*.*.CallObjectMethod.?(lJNIEnv, lNativeActivity, methodTest, methodInt, urlString, h1String, v1String, bodyByteArray);

    const bytes = jniToZigByteArray(lJNIEnv, result, a) catch return;
    if (bytes.len == 0) {
        std.log.err("ERROR", .{});
    } else if (bytes.len < 2) {
        std.log.err("ERROR, expected 0 or at least 2 bytes in HTTP result {}", .{bytes.len});
    } else {
        const code: u16 = bytes[0] + (@as(u16, bytes[1]) << 8);
        const responseBody = bytes[2..];
        const app = _state.*.getApp();
        app.onHttp(method, url, code, responseBody, a);
    }
}

pub fn getStatusBarHeight() u32
{
    const activity = _state.*.activity;

    // Attaches the current thread to the JVM
    const lJavaVM = activity.vm;
    var lJNIEnv = activity.env;

    var lJavaVMAttachArgs: c.JavaVMAttachArgs = undefined;
    lJavaVMAttachArgs.version = c.JNI_VERSION_1_6;
    lJavaVMAttachArgs.name = "NativeThread";
    lJavaVMAttachArgs.group = c.NULL;

    const result1 = lJavaVM.*.*.AttachCurrentThread.?(lJavaVM, &lJNIEnv, &lJavaVMAttachArgs);
    if (result1 == c.JNI_ERR) {
        return 0;
    }
    defer {
        const result2 = lJavaVM.*.*.DetachCurrentThread.?(lJavaVM);
        _ = result2; // TODO ??
    }

    // Retrieves NativeActivity instance.
    const lNativeActivity = activity.clazz;
    const classNativeActivity = lJNIEnv.*.*.GetObjectClass.?(lJNIEnv, lNativeActivity);

    const methodTest = lJNIEnv.*.*.GetMethodID.?(lJNIEnv, classNativeActivity, "getStatusBarHeight", "()I");
    const height = lJNIEnv.*.*.CallIntMethod.?(lJNIEnv, lNativeActivity, methodTest);
    return @intCast(height);
}
