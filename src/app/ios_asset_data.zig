const std = @import("std");

const m = @import("zigkm-math");
const zigimg = @import("zigimg");

const asset_data = @import("asset_data.zig");
const ios_bindings = @import("ios_bindings.zig");
const ios_exports = @import("ios_exports.zig");

pub fn AssetLoader(comptime AssetsType: type) type
{
    const Loader = struct {
        assetsPtr: *AssetsType,

        const Self = @This();

        pub fn load(self: *Self, assetsPtr: *AssetsType) void
        {
            self.assetsPtr = assetsPtr;
        }

        pub fn loadFontStart(self: *Self, id: u64, font: *asset_data.FontData, request: *const asset_data.FontLoadRequest, allocator: std.mem.Allocator) !void
        {
            var tempArena = std.heap.ArenaAllocator.init(allocator);
            defer tempArena.deinit();
            const tempAllocator = tempArena.allocator();

            // load font. TODO async-ify?
            const fullPath = try getFullPath(request.path, tempAllocator);

            const maxSize = 1024 * 1024 * 1024;
            const fontFileData = try std.fs.cwd().readFileAlloc(tempAllocator, fullPath, maxSize);

            var fontLoadData = try tempAllocator.create(asset_data.FontLoadData);
            var grayscaleBitmap = try fontLoadData.load(request.atlasSize, fontFileData, request.size, request.scale, tempAllocator);
            var img = zigimg.Image {
                .allocator = tempAllocator, // shouldn't be needed
                .width = request.atlasSize,
                .height = request.atlasSize,
                .pixels = .{
                    .grayscale8 = @ptrCast(grayscaleBitmap)
                },
            };
            verticalFlip(&img);

            const texturePtr = try ios_bindings.createAndLoadTexture(ios_exports._contextPtr, img);
            font.atlasData = .{
                .texId = @intFromPtr(texturePtr),
                .size = m.Vec2usize.init(request.atlasSize, request.atlasSize),
            };
            font.size = request.size;
            font.scale = request.scale;
            font.ascent = fontLoadData.ascent;
            font.descent = fontLoadData.descent;
            font.lineGap = fontLoadData.lineGap;
            font.lineHeight = request.lineHeight;
            font.kerning = request.kerning;

            std.mem.copy(asset_data.FontCharData, &font.charData, &fontLoadData.charData);

            // Just so the font is marked as loaded
            self.assetsPtr.onLoadedFont(id, &.{
                .fontData = undefined,
            });
        }

        pub fn loadFontEnd(self: *Self, id: u64, font: *asset_data.FontData, response: *const asset_data.FontLoadResponse) void
        {
            _ = self;
            _ = id;
            _ = font;
            _ = response;
        }

        pub fn loadTextureStart(self: *Self, id: u64, texture: *asset_data.TextureData, request: *const asset_data.TextureLoadRequest, priority: u32, allocator: std.mem.Allocator) !void
        {
            _ = priority;

            var tempArena = std.heap.ArenaAllocator.init(allocator);
            defer tempArena.deinit();
            const tempAllocator = tempArena.allocator();

            const fullPath = try getFullPath(request.path, tempAllocator);
            const img = try zigimg.Image.fromFilePath(tempAllocator, fullPath);

            const texturePtr = try ios_bindings.createAndLoadTexture(ios_exports._contextPtr, img);
            texture.* = .{
                .texId = @intFromPtr(texturePtr),
                .size = m.Vec2usize.init(img.width, img.height),
            };

            // Just so the texture is marked as loaded
            self.assetsPtr.onLoadedTexture(id, &.{
                .texId = id,
                .size = texture.size,
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

fn getFullPath(path: []const u8, allocator: std.mem.Allocator) ![]const u8
{
    const resourcePath = ios_bindings.getResourcePath() orelse return error.NoResourcePath;
    return try std.fs.path.join(allocator, &[_][]const u8 { resourcePath, path });
}

// Flips an image vertically. Only works for grayscale8 images.
fn verticalFlip(img: *zigimg.Image) void
{
    std.debug.assert(img.pixels == .grayscale8);

    const halfY = img.height / 2;
    var y: usize = 0;
    while (y < halfY) : (y += 1) {
        var yMirror = img.height - y - 1;
        var x: usize = 0;
        while (x < img.width) : (x += 1) {
            const index = y * img.width + x;
            const indexMirror = yMirror * img.width + x;
            const tmp = img.pixels.grayscale8[index];
            img.pixels.grayscale8[index] = img.pixels.grayscale8[indexMirror];
            img.pixels.grayscale8[indexMirror] = tmp;
        }
    }
}
