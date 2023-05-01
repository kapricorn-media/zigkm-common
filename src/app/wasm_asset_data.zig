const std = @import("std");

const m = @import("zigkm-common-math");

const asset_data = @import("asset_data.zig");
const w = @import("wasm_bindings.zig");

pub fn loadStartTextureData(id: u64, texture: *asset_data.TextureData, path: []const u8) void
{
    _ = texture;
    const texId = w.glCreateTexture();
    w.loadTexture(@intCast(c_uint, id), texId, &path[0], path.len, w.GL_CLAMP_TO_EDGE, w.GL_NEAREST);
}
