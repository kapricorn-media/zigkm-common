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
