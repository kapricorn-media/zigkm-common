const std = @import("std");

const m = @import("zigkm-math");

const asset_data = @import("asset_data.zig");

pub const AssetLoadState = enum {
    free,
    loading,
    loaded,
};

pub fn AssetsWithIds(comptime FontEnum: type, comptime TextureEnum: type, comptime maxDynamicTextures: usize) type
{
    const maxFonts = @typeInfo(FontEnum).Enum.fields.len;
    const maxTextures = @typeInfo(TextureEnum).Enum.fields.len + maxDynamicTextures;

    const FontId = FontEnum;
    const TextureIdType = enum {
        static,
        dynamic,
    };
    const TextureId = union(TextureIdType) {
        static: TextureEnum,
        dynamic: []const u8,
    };

    const T = struct {
        allocator: std.mem.Allocator,
        assets: Assets(maxFonts, maxTextures),
        textureIdMap: std.StringHashMapUnmanaged(u64),

        const Self = @This();

        pub fn load(self: *Self, allocator: std.mem.Allocator) !void
        {
            self.allocator = allocator;
            self.assets.load();
            try self.textureIdMap.ensureTotalCapacity(allocator, maxDynamicTextures);
            self.textureIdMap.clearRetainingCapacity();
        }

        pub fn getFontData(self: *const Self, id: FontId) ?*const asset_data.FontData
        {
            return self.assets.getFontData(getFontId(id));
        }

        pub fn getFontLoadState(self: *const Self, id: FontId) AssetLoadState
        {
            return self.assets.getFontLoadState(getFontId(id));
        }

        pub fn getTextureData(self: *const Self, id: TextureId) ?*const asset_data.TextureData
        {
            const theId = self.getTextureId(id) orelse return null;
            return self.assets.getTextureData(theId);
        }

        pub fn getTextureLoadState(self: *const Self, id: TextureId) AssetLoadState
        {
            const theId = self.getTextureId(id) orelse return .free;
            return self.assets.getTextureLoadState(theId);
        }

        pub fn loadFont(self: *Self, id: FontId, request: *const asset_data.FontLoadRequest) !void
        {
            const theId = getFontId(id);
            const newId = try self.assets.loadFont(theId, request);
            std.debug.assert(theId == newId);
        }

        pub fn onLoadedFont(self: *Self, id: u64, response: *const asset_data.FontLoadResponse) void
        {
            self.assets.onLoadedFont(id, response);
        }

        pub fn loadTexture(self: *Self, id: TextureId, request: *const asset_data.TextureLoadRequest) !void
        {
            return self.loadTexturePriority(id, request, 0);
        }

        pub fn loadTexturePriority(self: *Self, id: TextureId, request: *const asset_data.TextureLoadRequest, priority: u32) !void
        {
            const requestedId = switch (id) {
                .static => |e| getTextureStaticId(e),
                .dynamic => null,
            };
            const newId = try self.assets.loadTexturePriority(requestedId, request, priority);
            if (requestedId) |rid| {
                std.debug.assert(rid == newId);
            }
            switch (id) {
                .static => {},
                .dynamic => |str| {
                    const strCopy = try self.allocator.dupe(u8, str);
                    self.textureIdMap.putAssumeCapacity(strCopy, newId);
                },
            }
        }

        pub fn onLoadedTexture(self: *Self, id: u64, response: *const asset_data.TextureLoadResponse) void
        {
            self.assets.onLoadedTexture(id, response);
        }

        pub fn loadQueued(self: *Self, maxInflight: usize) void
        {
            self.assets.loadQueued(maxInflight);
        }

        pub fn clearLoadQueue(self: *Self) void
        {
            self.assets.clearLoadQueue();
        }

        fn getFontId(id: FontId) u64
        {
            return @enumToInt(id);
        }

        fn getTextureId(self: *const Self, id: TextureId) ?u64
        {
            switch (id) {
                .static => |e| {
                    return getTextureStaticId(e);
                },
                .dynamic => |str| {
                    return self.textureIdMap.get(str);
                },
            }
        }

        fn getTextureStaticId(e: TextureEnum) u64
        {
            return @enumToInt(e);
        }
    };

    return T;
}

pub fn Assets(comptime maxFonts: usize, comptime maxTextures: usize) type
{
    std.debug.assert(maxFonts <= std.math.maxInt(u64));
    std.debug.assert(maxTextures <= std.math.maxInt(u64));

    const T = struct {
        loader: asset_data.AssetLoader,
        fonts: [maxFonts]AssetWrapper(asset_data.FontData),
        textures: [maxTextures]AssetWrapper(asset_data.TextureData),

        const Self = @This();

        pub fn load(self: *Self) void
        {
            self.loader.load();
            for (self.fonts) |*f| {
                f.state = .free;
            }
            for (self.textures) |*t| {
                t.state = .free;
            }
        }

        pub fn getFontData(self: *const Self, id: u64) ?*const asset_data.FontData
        {
            const wrapper = getDataWrapper(asset_data.FontData, &self.fonts, id);
            if (wrapper.state != .loaded) {
                return null;
            }
            return &wrapper.t;
        }

        pub fn getFontLoadState(self: *const Self, id: u64) AssetLoadState
        {
            const wrapper = getDataWrapper(asset_data.FontData, &self.fonts, id);
            return wrapper.state;
        }

        pub fn getTextureData(self: *const Self, id: u64) ?*const asset_data.TextureData
        {
            const wrapper = getDataWrapper(asset_data.TextureData, &self.textures, id);
            if (wrapper.state != .loaded) {
                return null;
            }
            return &wrapper.t;
        }

        pub fn getTextureLoadState(self: *const Self, id: u64) AssetLoadState
        {
            const wrapper = getDataWrapper(asset_data.TextureData, &self.textures, id);
            return wrapper.state;
        }

        pub fn loadFont(self: *Self, id: ?u64, request: *const asset_data.FontLoadRequest) !u64
        {
            const newId = id orelse getUnusedId(asset_data.FontData, &self.fonts) orelse return error.FontsFull;
            const newIndex = @intCast(usize, newId);
            self.fonts[newIndex].state = .loading;
            self.loader.loadFontStart(newId, &self.fonts[newIndex].t, request);
            return newId;
        }

        pub fn onLoadedFont(self: *Self, id: u64, response: *const asset_data.FontLoadResponse) void
        {
            const index = @intCast(usize, id);
            std.debug.assert(index < self.fonts.len);
            std.debug.assert(self.fonts[index].state == .loading);
            self.loader.loadFontEnd(id, &self.fonts[index].t, response);
            self.fonts[index].state = .loaded;
        }

        // Loads on the requested id's slot if not null (replaces existing texture).
        // Otherwise gets the next free id, starting from the end of the texture list.
        pub fn loadTexturePriority(self: *Self, id: ?u64, request: *const asset_data.TextureLoadRequest, priority: u32) !u64
        {
            const newId = id orelse getUnusedId(asset_data.TextureData, &self.textures) orelse return error.TexturesFull;
            const newIndex = @intCast(usize, newId);
            self.textures[newIndex].state = .loading;
            try self.loader.loadTextureStart(newId, &self.textures[newIndex].t, request, priority);
            return newId;
        }

        pub fn onLoadedTexture(self: *Self, id: u64, response: *const asset_data.TextureLoadResponse) void
        {
            const index = @intCast(usize, id);
            std.debug.assert(index < self.textures.len);
            std.debug.assert(self.textures[index].state == .loading);

            if (response.size.x != 0 and response.size.y != 0) {
                self.loader.loadTextureEnd(id, &self.textures[index].t, response);
                self.textures[index].state = .loaded;
            }
        }

        pub fn loadQueued(self: *Self, maxInflight: usize) void
        {
            self.loader.loadQueued(maxInflight);
        }

        pub fn clearLoadQueue(self: *Self) void
        {
            self.loader.clearLoadQueue();
        }
    };

    return T;
}

fn AssetWrapper(comptime T: type) type
{
    const Wrapper = struct {
        t: T,
        state: AssetLoadState,
    };
    return Wrapper;
}

fn getUnusedId(comptime T: type, values: []const AssetWrapper(T)) ?u64
{
    var n: usize = values.len;
    while (n != 0) : (n -= 1) {
        const ind = n - 1;
        if (values[ind].state == .free) {
            return ind;
        }
    }
    return null;
}

fn getDataWrapper(comptime T: type, values: []const AssetWrapper(T), id: u64) *const AssetWrapper(T)
{
    const index = @intCast(usize, id);
    std.debug.assert(index < values.len);
    return &values[index];
}
