const std = @import("std");

const m = @import("zigkm-math");

const asset_data = @import("asset_data.zig");
const w = @import("wasm_bindings.zig");

const TextureLoadEntry = struct {
    id: u64,
    request: asset_data.TextureLoadRequest,
    priority: u32,
};

pub fn AssetLoader(comptime AssetsType: type) type
{
    const Loader = struct {
        textureLoadEntries: std.BoundedArray(TextureLoadEntry, 1024),
        textureLoadsInflight: usize,

        const Self = @This();

        pub fn load(self: *Self, assetsPtr: *AssetsType) void
        {
            _ = assetsPtr;
            self.textureLoadEntries.len = 0;
            self.textureLoadsInflight = 0;
        }

        pub fn loadFontStart(self: *Self, id: u64, font: *asset_data.FontData, request: *const asset_data.FontLoadRequest, allocator: std.mem.Allocator) !void
        {
            _ = self;
            _ = allocator;

            font.atlasData = .{
                .texId = w.loadFontDataJs(@intCast(id), &request.path[0], request.path.len, request.size, request.scale, @intCast(request.atlasSize)),
                .size = m.Vec2usize.init(request.atlasSize, request.atlasSize),
            };
            font.size = request.size;
            font.scale = request.scale;
            font.kerning = request.kerning;
            font.lineHeight = request.lineHeight;
        }

        pub fn loadFontEnd(self: *Self, id: u64, font: *asset_data.FontData, response: *const asset_data.FontLoadResponse) void
        {
            _ = self;
            _ = id;

            std.debug.assert(font.size == response.fontData.size);
            std.mem.copy(asset_data.FontCharData, &font.charData, &response.fontData.charData);
            font.ascent = response.fontData.ascent;
            font.descent = response.fontData.descent;
            font.lineGap = response.fontData.lineGap;
        }

        pub fn loadTextureStart(self: *Self, id: u64, texture: *asset_data.TextureData, request: *const asset_data.TextureLoadRequest, priority: u32, allocator: std.mem.Allocator) !void
        {
            _ = texture;
            _ = allocator;
            var loadEntry = try self.textureLoadEntries.addOne();
            loadEntry.* = .{
                .id = id,
                .request = request.*,
                .priority = priority,
            };
        }

        pub fn loadTextureEnd(self: *Self, id: u64, texture: *asset_data.TextureData, response: *const asset_data.TextureLoadResponse) void
        {
            _ = id;
            texture.texId = response.texId;
            texture.size = response.size;
            std.debug.assert(self.textureLoadsInflight > 0);
            self.textureLoadsInflight -= 1;
        }

        pub fn loadQueued(self: *Self, maxInflight: usize) void
        {
            const maxToLoad = if (maxInflight > self.textureLoadsInflight) maxInflight - self.textureLoadsInflight else 0;
            const numToLoad = @min(maxToLoad, self.textureLoadEntries.len);

            var i: usize = 0;
            while (i < numToLoad) : (i += 1) {
                // Choose highest-priority entry to load
                var entryIndex: usize = 0;
                const loadEntries = self.textureLoadEntries.slice();
                for (loadEntries, 0..) |entry, j| {
                    if (entry.priority < loadEntries[entryIndex].priority) {
                        entryIndex = j;
                    }
                }

                // Load chosen highest-priority entry and remove from the array
                const entry = self.textureLoadEntries.orderedRemove(entryIndex);
                const texId = w.glCreateTexture();
                w.loadTexture(
                    @intCast(entry.id), texId,
                    &entry.request.path[0], entry.request.path.len,
                    textureWrapModeToWebgl(entry.request.wrapMode),
                    textureFilterToWebgl(entry.request.filter)
                );
                self.textureLoadsInflight += 1;
            }
        }

        pub fn clearLoadQueue(self: *Self) void
        {
            self.textureLoadEntries.len = 0;
        }
    };

    return Loader;
}

fn textureFilterToWebgl(filter: asset_data.TextureFilter) c_uint
{
    return switch (filter) {
        .linear => w.GL_LINEAR,
        .nearest => w.GL_NEAREST,
    };
}

fn textureWrapModeToWebgl(wrapMode: asset_data.TextureWrapMode) c_uint
{
    return switch (wrapMode) {
        .clampToEdge => w.GL_CLAMP_TO_EDGE,
        .repeat => w.GL_REPEAT,
    };
}
