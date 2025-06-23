const std = @import("std");

const m = @import("zigkm-math");
const zigimg = @import("zigimg");

const asset_data = @import("asset_data.zig");
const c = @import("android_c.zig");
const memory = @import("memory.zig");

var _state = &@import("android_exports.zig")._state;

pub fn AssetLoader(comptime AssetsType: type) type
{
    const Loader = struct {
        assetsPtr: *AssetsType,

        const Self = @This();

        pub fn load(self: *Self, assetsPtr: *AssetsType) void
        {
            std.log.info("AssetLoader load", .{});
            self.assetsPtr = assetsPtr;
        }

        pub fn loadFontStart(self: *Self, id: u64, font: *asset_data.FontData, request: *const asset_data.FontLoadRequest) !void
        {
            var ta = memory.getTempArena(null);
            defer ta.reset();
            const a = ta.allocator();

            const pathZ = try a.dupeZ(u8, request.path);
            const assetManager = _state.*.activity.assetManager orelse return error.assetManager;
            const fontFileData = try c.loadEntireFile(pathZ, assetManager, a);

            var fontLoadData = try a.create(asset_data.FontLoadData);
            const grayscaleBitmap = try fontLoadData.load(request.atlasSize, fontFileData, request.size, request.scale, a);
            var image = zigimg.Image {
                .allocator = a, // shouldn't be needed
                .width = request.atlasSize,
                .height = request.atlasSize,
                .pixels = .{
                    .grayscale8 = @ptrCast(grayscaleBitmap)
                },
            };
            asset_data.verticalFlip(&image);

            font.atlasData = .{
                .texId = try c.loadTexture(image, .repeat, .linear),
                .size = m.Vec2usize.init(request.atlasSize, request.atlasSize),
                .canvasSize = undefined,
                .topLeft = undefined,
            };
            font.size = request.size;
            font.scale = request.scale;
            font.ascent = fontLoadData.ascent;
            font.descent = fontLoadData.descent;
            font.lineGap = fontLoadData.lineGap;
            font.lineHeight = request.lineHeight;
            font.kerning = request.kerning;

            std.mem.copyForwards(asset_data.FontCharData, &font.charData, &fontLoadData.charData);

            // Just so the font is marked as loaded
            self.assetsPtr.onLoadedFont(id, &.{
                .fontData = undefined,
            }, a);
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
            _ = priority;
            var ta = memory.getTempArena(null);
            defer ta.reset();
            const a = ta.allocator();

            const pathZ = try a.dupeZ(u8, request.path);
            const assetManager = _state.*.activity.assetManager orelse return error.assetManager;
            const imageFileData = try c.loadEntireFile(pathZ, assetManager, a);
            var image = try zigimg.Image.fromMemory(a, imageFileData);
            asset_data.verticalFlip(&image);

            texture.* = .{
                .texId = try c.loadTexture(image, .repeat, .linear),
                .size = m.Vec2usize.init(image.width, image.height),
                .canvasSize = undefined,
                .topLeft = undefined,
            };

            // So the texture is marked as loaded
            self.assetsPtr.onLoadedTexture(id, &.{
                .texId = id,
                .size = texture.size,
                .canvasSize = undefined,
                .topLeft = undefined,
            });
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

    return Loader;
}
