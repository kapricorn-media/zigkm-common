const std = @import("std");

const bm = @import("bitmap.zig");
pub const ios = @cImport(@cInclude("ios/bindings.h"));

const zigimg = @import("zigimg");

pub const Context = opaque {};

pub const Buffer = opaque {};
pub const Texture = opaque {};
pub const RenderState = opaque {};
pub const RenderState2 = opaque {};

pub fn log(string: [:0]const u8) void
{
    ios.iosLog(@ptrCast([*c]const u8, string));
}

pub fn getResourcePath() ?[]const u8
{
    const slice = ios.getResourcePath();
    if (slice.size == 0) {
        return null;
    }
    return slice.data[0..slice.size];
}

pub fn createBuffer(context: *Context, length: u64) !*Buffer
{
    const buffer = ios.createBuffer(context, length);
    if (buffer == null) {
        return error.createBuffer;
    }
    return @ptrCast(*Buffer, buffer);
}

pub fn createAndLoadTexture(context: *Context, image: zigimg.Image) !*Texture
{
    var pixelBytes: []const u8 = undefined;
    var format: ios.TextureFormat = undefined;
    switch (image.pixels) {
        .grayscale8 => |r8| {
            pixelBytes = std.mem.sliceAsBytes(r8);
            format = ios.R8;
        },
        .rgba32 => |rgba32| {
            pixelBytes = std.mem.sliceAsBytes(rgba32);
            format = ios.RGBA8;
        },
        .bgra32 => |bgra32| {
            pixelBytes = std.mem.sliceAsBytes(bgra32);
            format = ios.BGRA8;
        },
        else => {
            std.log.err("Unsupported format: {}", .{std.meta.activeTag(image.pixels)});
            return error.UnsupportedFormat;
        },
    }
    const texture = ios.createAndLoadTexture(
        context, @intCast(u32, image.width), @intCast(u32, image.height), format, pixelBytes.ptr
    ) orelse {
        return error.createAndLoadTexture;
    };
    return @ptrCast(*Texture, texture);
}

pub fn createAndLoadTextureR8(context: *Context, bitmap: bm.Bitmap) !*Texture
{
    // TODO hmm, check bitmap format...
    if (bitmap.channels != 1) {
        return error.badBitmapR8;
    }
    const texture = ios.createAndLoadTextureR8(context, bitmap.w, bitmap.h, &bitmap.data[0]);
    if (texture == null) {
        return error.createAndLoadTextureR8;
    }
    return @ptrCast(*Texture, texture);
}

pub fn createAndLoadTextureBGRA8(context: *Context, bitmap: bm.Bitmap) !*Texture
{
    // TODO hmm, check bitmap format...
    if (bitmap.channels != 4) {
        return error.badBitmapBGRA8;
    }
    const texture = ios.createAndLoadTextureBGRA8(context, bitmap.w, bitmap.h, &bitmap.data[0]);
    if (texture == null) {
        return error.createAndLoadTextureBGRA8;
    }
    return @ptrCast(*Texture, texture);
}

pub fn createRenderState(context: *Context) !*RenderState2
{
    const renderState = ios.createRenderState(context) orelse return error.createRenderState;
    return @ptrCast(*RenderState2, renderState);
}

pub fn renderQuads(context: *Context, renderState: *const RenderState2, instances: usize, bufferData: []const u8, screenWidth: f32, screenHeight: f32) void
{
    const renderStateC = @ptrCast(*const ios.RenderState2, renderState);
    return ios.renderQuads(context, renderStateC, instances, bufferData.len, bufferData.ptr, screenWidth, screenHeight);
}

pub fn renderTexQuads(context: *Context, renderState: *const RenderState2, bufferData: []const u8, textures: []*const Texture, screenWidth: f32, screenHeight: f32) void
{
    const renderStateC = @ptrCast(*const ios.RenderState2, renderState);
    const texturesC = @ptrCast([*c]?*const ios.Texture, textures.ptr);
    return ios.renderTexQuads(context, renderStateC, textures.len, bufferData.len, bufferData.ptr, texturesC, screenWidth, screenHeight);
}

pub fn renderText(context: *Context, renderState: *const RenderState2, instances: usize, bufferData: []const u8, atlases: []*const Texture, uniforms: *const ios.TextUniforms) void
{
    const renderStateC = @ptrCast(*const ios.RenderState2, renderState);
    const atlasesC = @ptrCast([*c]?*const ios.Texture, atlases.ptr);
    return ios.renderText(context, renderStateC, instances, bufferData.len, bufferData.ptr, atlases.len, atlasesC, uniforms);
}

pub fn setKeyboardVisible(context: *Context, visible: bool) void
{
    ios.setKeyboardVisible(context, @boolToInt(visible));
}
