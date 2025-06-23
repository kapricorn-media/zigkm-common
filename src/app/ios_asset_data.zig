const std = @import("std");
const A = std.mem.Allocator;

const m = @import("zigkm-math");
const zigimg = @import("zigimg");

const asset_data = @import("asset_data.zig");
const ios_bindings = @import("ios_bindings.zig");
const ios_exports = @import("ios_exports.zig");
const memory = @import("memory.zig");

pub fn AssetLoader(comptime AssetsType: type) type
{
    const Loader = struct {
        assetsPtr: *AssetsType,

        const Self = @This();

        pub fn load(self: *Self, assetsPtr: *AssetsType) void
        {
            self.assetsPtr = assetsPtr;
        }

        pub fn loadFontStart(self: *Self, id: u64, font: *asset_data.FontData, request: *const asset_data.FontLoadRequest) !void
        {
            var ta = memory.getTempArena(null);
            defer ta.reset();
            const a = ta.allocator();

            // load font. TODO async-ify?
            const fullPath = try getFullPath(request.path, a);

            const maxSize = 1024 * 1024 * 1024;
            const fontFileData = try std.fs.cwd().readFileAlloc(a, fullPath, maxSize);

            var fontLoadData = try a.create(asset_data.FontLoadData);
            const grayscaleBitmap = try fontLoadData.load(request.atlasSize, fontFileData, request.size, request.scale, a);
            var img = zigimg.Image {
                .allocator = a, // shouldn't be needed
                .width = request.atlasSize,
                .height = request.atlasSize,
                .pixels = .{
                    .grayscale8 = @ptrCast(grayscaleBitmap)
                },
            };
            asset_data.verticalFlip(&img);

            const texturePtr = try ios_bindings.createAndLoadTexture(ios_exports._contextPtr, img);
            font.atlasData = .{
                .texId = @intFromPtr(texturePtr),
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

            const fullPath = try getFullPath(request.path, a);
            var img = try zigimg.Image.fromFilePath(a, fullPath);
            asset_data.verticalFlip(&img);

            const texturePtr = try ios_bindings.createAndLoadTexture(ios_exports._contextPtr, img);
            texture.* = .{
                .texId = @intFromPtr(texturePtr),
                .size = m.Vec2usize.init(img.width, img.height),
                .canvasSize = undefined,
                .topLeft = undefined,
            };

            // Just so the texture is marked as loaded
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

fn getFullPath(path: []const u8, a: A) ![]const u8
{
    const resourcePath = ios_bindings.getResourcePath() orelse return error.NoResourcePath;
    return try std.fs.path.join(a, &[_][]const u8 {resourcePath, path});
}
