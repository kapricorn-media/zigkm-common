const std = @import("std");

const m = @import("zigkm-common-math");

const asset_data = @import("asset_data.zig");
const w = @import("wasm_bindings.zig");

// idk... sigh
pub const AssetLoader = struct {
    const Self = @This();

    pub fn load(self: *Self) void
    {
        _ = self;
    }

    pub fn loadFontStart(self: *Self, id: u64, font: *asset_data.FontData, request: *const asset_data.FontLoadRequest) void
    {
        _ = self;
        _ = id;
        font.atlasData.texId = w.loadFontDataJs(&request.path[0], request.path.len, request.size, request.scale, @intCast(c_uint, request.atlasSize));
        font.size = request.size;
        font.scale = request.scale;
        font.kerning = request.kerning;
        font.lineHeight = request.lineHeight;
    }

    pub fn loadFontEnd(self: *Self, id: u64, font: *asset_data.FontData, response: *const asset_data.FontLoadResponse) void
    {
        _ = self;
        _ = id;
        _ = font;
        _ = response;
    }

    pub fn loadTextureStart(self: *Self, id: u64, texture: *asset_data.TextureData, request: *const asset_data.TextureLoadRequest) void
    {
        _ = self;
        _ = texture;
        const texId = w.glCreateTexture();
        w.loadTexture(@intCast(c_uint, id), texId, &request.path[0], request.path.len, w.GL_CLAMP_TO_EDGE, w.GL_NEAREST);
    }

    pub fn loadTextureEnd(self: *Self, id: u64, texture: *asset_data.TextureData, response: *const asset_data.TextureLoadResponse) void
    {
        _ = self;
        _ = id;
        texture.texId = response.texId;
        texture.size = response.size;
    }
};
