const std = @import("std");

pub fn setCursorZ(cursor: []const u8) void
{
    setCursor(&cursor[0], cursor.len);
}

pub fn getUriZ(outUri: []u8) usize
{
    return getUri(&outUri[0], outUri.len);
}

pub fn getUriAlloc(allocator: std.mem.Allocator) ![]const u8
{
    const len = getUriLen();
    var buf = try allocator.alloc(u8, len);
    const n = getUri(&buf[0], len);
    std.debug.assert(len == n);
    return buf;
}

pub fn setUriZ(uri: []const u8) void
{
    setUri(&uri[0], uri.len);
}

pub fn pushStateZ(uri: []const u8) void
{
    pushState(&uri[0], uri.len);
}

pub fn httpGetZ(uri: []const u8) void
{
    httpGet(&uri[0], uri.len);
}

// Debug
pub extern fn consoleMessage(isError: bool, messagePtr: *const u8, messageLen: c_uint) void;

// Custom
pub extern fn fillDataBuffer(buf: *const u8, len: c_uint) c_int; // 1 success, 0 error
pub extern fn addReturnValueFloat(value: f32) c_int;
pub extern fn addReturnValueInt(value: c_int) c_int;
pub extern fn addReturnValueBuf(ptr: *const u8, len: c_uint) c_int;
pub extern fn loadFontDataJs(id: c_uint, fontUrlPtr: *const u8, fontUrlLen: c_uint, fontSize: f32, scale: f32, atlasSize: c_uint) c_uint;

// browser / DOM
pub extern fn clearAllEmbeds() void;
pub extern fn addYoutubeEmbed(left: c_int, top: c_int, width: c_int, height: c_int, youtubeIdPtr: *const u8, youtubeIdLen: c_uint) void;

pub extern fn setCursor(cursorPtr: *const u8, cursorLen: c_uint) void;
pub extern fn setScrollY(y: c_uint) void;
pub extern fn getUriLen() c_uint;
pub extern fn getUri(outUriPtr: *u8, outUriLen: c_uint) c_uint;
pub extern fn setUri(uriPtr: *const u8, uriLen: c_uint) void;
pub extern fn pushState(uriPtr: *const u8, uriLen: c_uint) void;

pub extern fn httpGet(uriPtr: *const u8, uriLen: c_uint) void;

// GL
pub extern fn compileShader(source: *const u8 , len: c_uint, type: c_uint) c_uint;
pub extern fn linkShaderProgram(vertexShaderId: c_uint, fragmentShaderId: c_uint) c_uint;
pub extern fn createTexture(width: c_int, height: c_int, wrapMode: c_uint, filter: c_uint) c_uint;
pub extern fn createTextureWithData(width: c_int, height: c_int, channels: c_int, dataPtr: *u8, dataLen: c_uint, wrapMode: c_uint, filter: c_uint) c_uint;
pub extern fn loadTexture(id: c_uint, textureId: c_uint, imgUrlPtr: *const u8, imgUrlLen: c_uint, wrapMode: c_uint, filter: c_uint) void;
pub extern fn bindNullFramebuffer() void;
pub extern fn vertexAttribDivisorANGLE(_: c_int, _: c_uint) void;
pub extern fn drawArraysInstancedANGLE(_: c_uint, _: c_int, _: c_uint, _: c_uint) void;

pub extern fn glClear(_: c_uint) void;
pub extern fn glClearColor(_: f32, _: f32, _: f32, _: f32) void;

pub extern fn glEnable(_: c_uint) void;

pub extern fn glBlendFunc(_: c_uint, _: c_uint) void;
pub extern fn glBlendFuncSeparate(_: c_uint, _: c_uint, _: c_uint, _: c_uint) void;
pub extern fn glDepthFunc(_: c_uint) void;

pub extern fn glGetAttribLocation(_: c_uint, _: *const u8, _: c_uint) c_int;
pub extern fn glGetUniformLocation(_: c_uint, _: *const u8, _: c_uint) c_int;

pub extern fn glUniform1i(_: c_int, _: c_int) void;
pub extern fn glUniform1fv(_: c_int, _: f32) void;
pub extern fn glUniform2fv(_: c_int, _: f32, _: f32) void;
pub extern fn glUniform3fv(_: c_int, _: f32, _: f32, _: f32) void;
pub extern fn glUniform4fv(_: c_int, _: f32, _: f32, _: f32, _: f32) void;

pub extern fn glCreateFramebuffer() c_uint;
pub extern fn glBindFramebuffer(_: c_uint, _: c_uint) void;
pub extern fn glFramebufferTexture2D(_: c_uint, _: c_uint, _: c_uint, _: c_uint, _: c_uint) void;
pub extern fn glFramebufferRenderbuffer(_: c_uint, _: c_uint, _: c_uint, _: c_uint) void;

pub extern fn glCreateRenderbuffer() c_uint;
pub extern fn glBindRenderbuffer(_: c_uint, _: c_uint) void;
pub extern fn glRenderbufferStorage(_: c_uint, _: c_uint, _: c_int, _: c_int) void;

pub extern fn glCreateBuffer() c_uint;
pub extern fn glBindBuffer(_: c_uint, _: c_uint) void;
// TODO hardcoded to float buffers
pub extern fn glBufferData3(_: c_uint, _: c_uint, _: c_uint) void;
pub extern fn glBufferData(_: c_uint, _: *const f32,  _: c_uint, _: c_uint) void;
pub extern fn glBufferSubData(_: c_uint, _: c_uint, _: *const f32,  _: c_uint) void;

pub extern fn glCreateTexture() c_uint;
pub extern fn glBindTexture(_: c_uint, _: c_uint) void;
pub extern fn glActiveTexture(_: c_uint) void;
pub extern fn glDeleteTexture(_: c_uint) void;

pub extern fn glUseProgram(_: c_uint) void;

pub extern fn glEnableVertexAttribArray(_: c_uint) void;
pub extern fn glVertexAttribPointer(_: c_uint, _: c_uint, _: c_uint, _: c_uint, _: c_uint, _: c_uint) void;

pub extern fn glDrawArrays(_: c_uint, _: c_uint, _: c_uint) void;

// Identifier constants pulled from WebGLRenderingContext
pub const GL_VERTEX_SHADER: c_uint = 35633;
pub const GL_FRAGMENT_SHADER: c_uint = 35632;
pub const GL_ARRAY_BUFFER: c_uint = 34962;
pub const GL_TRIANGLES: c_uint = 4;
pub const GL_STATIC_DRAW: c_uint = 35044;
pub const GL_DYNAMIC_DRAW: c_uint = 35048;
pub const GL_f32: c_uint = 5126;

pub const GL_DEPTH_TEST: c_uint = 2929;
pub const GL_LESS: c_uint = 513;
pub const GL_LEQUAL: c_uint = 515;

pub const GL_BLEND: c_uint = 3042;
pub const GL_ZERO: c_uint = 0;
pub const GL_ONE: c_uint = 1;
pub const GL_SRC_ALPHA: c_uint = 770;
pub const GL_ONE_MINUS_SRC_ALPHA: c_uint = 771;

pub const GL_COLOR_BUFFER_BIT: c_uint = 16384;
pub const GL_DEPTH_BUFFER_BIT: c_uint = 256;

pub const GL_TEXTURE_2D: c_uint = 3553;
pub const GL_TEXTURE0: c_uint = 33984;
pub const GL_TEXTURE1: c_uint = 33985;

pub const GL_REPEAT: c_uint = 10497;
pub const GL_CLAMP_TO_EDGE: c_uint = 33071;

pub const GL_NEAREST: c_uint = 9728;
pub const GL_LINEAR: c_uint = 9729;

pub const GL_COLOR_ATTACHMENT0: c_uint = 36064;
pub const GL_DEPTH_ATTACHMENT: c_uint = 36096;

pub const GL_FRAMEBUFFER: c_uint = 36160;
pub const GL_RENDERBUFFER: c_uint = 36161;

pub const GL_DEPTH_COMPONENT16: c_uint = 33189;
