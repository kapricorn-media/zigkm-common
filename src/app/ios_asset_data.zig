const std = @import("std");

const m = @import("zigkm-math");

const asset_data = @import("asset_data.zig");
const ios_bindings = @import("ios_bindings.zig");

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
        _ = font;
        _ = request;
    }

    pub fn loadFontEnd(self: *Self, id: u64, font: *asset_data.FontData, response: *const asset_data.FontLoadResponse) void
    {
        _ = self;
        _ = id;
        _ = font;
        _ = response;
    }

    pub fn loadTextureStart(self: *Self, id: u64, texture: *asset_data.TextureData, request: *const asset_data.TextureLoadRequest, priority: u32) !void
    {
        _ = self;
        _ = id;
        _ = texture;
        _ = request;
        _ = priority;
    }

    pub fn loadTextureEnd(self: *Self, id: u64, texture: *asset_data.TextureData, response: *const asset_data.TextureLoadResponse) void
    {
        _ = self;
        _ = id;
        _ = texture;
        _ = response;
    }

    pub fn loadQueued(self: *Self, maxInflight: usize) void
    {
        _ = self;
        _ = maxInflight;
    }

    pub fn clearLoadQueue(self: *Self) void
    {
        _ = self;
    }
};
