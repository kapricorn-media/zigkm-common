const std = @import("std");

// const bindings = @import("bindings.zig");
// const ios_shader_defs = @cImport(@cInclude("ios_shader_defs.h"));

// const zigimg = @import("zigimg");
// const zigkm_common_asset = @import("zigkm-common-asset");

const m = @import("zigkm-common-math");
const stb = @import("zigkm-common-stb");

const defs = @import("defs.zig");
const platform_asset_data = switch (defs.platform) {
    .ios => unreachable,
    .web => @import("wasm_asset_data.zig"),
};

pub const TextureData = struct {
    texId: u64,
    size: m.Vec2usize,

    const Self = @This();

    pub fn loadStart(self: *Self, id: u64, path: []const u8) !void
    {
        platform_asset_data.loadStartTextureData(id, self, path);
    }

    pub fn loadEnd(self: *Self, texId: u64, size: m.Vec2usize) void
    {
        self.texId = texId;
        self.size = size;
    }
};

pub const FontCharData = struct {
    offset: m.Vec2,
    size: m.Vec2,
    uvOffset: m.Vec2,
    advanceX: f32,
};

pub const FontLoadData = struct {
    size: f32,
    scale: f32,
    charData: [256]FontCharData,

    const Self = @This();

    pub fn load(self: *Self, atlasSize: usize, fontFileData: [:0]const u8, size: f32, scale: f32, allocator: std.mem.Allocator) ![]u8
    {
        var tempArena = std.heap.ArenaAllocator.init(allocator);
        defer tempArena.deinit();
        var tempAllocator = tempArena.allocator();

        self.size = size;
        self.scale = scale;

        const width = atlasSize;
        const height = atlasSize;
        var pixelBytes = try allocator.alloc(u8, width * height);
        std.mem.set(u8, pixelBytes, 0);
        var context: stb.stbtt_pack_context = undefined;
        if (stb.stbtt_PackBegin(&context, &pixelBytes[0], @intCast(c_int, width), @intCast(c_int, height), @intCast(c_int, width), 1, &tempAllocator) != 1) {
            return error.stbtt_PackBegin;
        }
        const oversampleN = 1;
        stb.stbtt_PackSetOversampling(&context, oversampleN, oversampleN);

        var charData = try tempAllocator.alloc(stb.stbtt_packedchar, self.charData.len);
        if (stb.stbtt_PackFontRange(&context, &fontFileData[0], 0, size / scale, 0, @intCast(c_int, charData.len), &charData[0]) != 1) {
            return error.stbtt_PackFontRange;
        }

        stb.stbtt_PackEnd(&context);

        for (charData) |cd, i| {
            const sizeF = m.Vec2.initFromVec2i(m.Vec2i.init(cd.x1 - cd.x0, cd.y1 - cd.y0));
            self.charData[i] = FontCharData {
                .offset = m.Vec2.init(cd.xoff, -(sizeF.y + cd.yoff)),
                .size = sizeF,
                .uvOffset = m.Vec2.init(
                    @intToFloat(f32, cd.x0) / @intToFloat(f32, width),
                    @intToFloat(f32, height - cd.y1) / @intToFloat(f32, height), // TODO should do -1 ?
                ),
                .advanceX = cd.xadvance,
            };
        }

        return pixelBytes;
    }
};

pub const FontData = struct {
    atlasData: TextureData,
    size: f32,
    scale: f32,
    lineHeight: f32,
    kerning: f32,
    charData: [256]FontCharData,

    const Self = @This();

    pub fn load(self: *Self, fontLoadData: *const FontLoadData, lineHeight: f32, kerning: f32, textureIndex: usize) void
    {
        self.* = .{
            .textureIndex = textureIndex,
            .size = fontLoadData.size,
            .scale = fontLoadData.scale,
            .lineHeight = lineHeight,
            .kerning = kerning,
        };
        std.mem.copy(FontCharData, &self.charData, &fontLoadData.charData);
    }
};

// Flips an image vertically. Only works for grayscale8 images.
// fn verticalFlip(img: *zigimg.Image) void
// {
//     std.debug.assert(img.pixels == .grayscale8);

//     const halfY = img.height / 2;
//     var y: usize = 0;
//     while (y < halfY) : (y += 1) {
//         var yMirror = img.height - y - 1;
//         var x: usize = 0;
//         while (x < img.width) : (x += 1) {
//             const index = y * img.width + x;
//             const indexMirror = yMirror * img.width + x;
//             const tmp = img.pixels.grayscale8[index];
//             img.pixels.grayscale8[index] = img.pixels.grayscale8[indexMirror];
//             img.pixels.grayscale8[indexMirror] = tmp;
//         }
//     }
// }

// fn getFullPath(path: []const u8, allocator: std.mem.Allocator) ![]const u8
// {
//     const resourcePath = bindings.getResourcePath() orelse return error.NoResourcePath;
//     return try std.fs.path.join(allocator, &[_][]const u8 { resourcePath, path });
// }

// pub fn Assets(comptime StaticFontEnum: type, comptime StaticTextureEnum: type, comptime maxDynamicTextures: usize) type
// {
//     const TextureIdType = enum {
//         Static,
//         Index,
//         Name,
//     };
//     const TextureId = union(TextureIdType) {
//         Static: StaticTextureEnum,
//         Index: usize,
//         Name: []const u8,
//     };

//     const T = struct {
//         const numStaticFonts = @typeInfo(StaticFontEnum).Enum.fields.len;
//         const numStaticTextures = @typeInfo(StaticTextureEnum).Enum.fields.len;
//         const numTotalTextures = numStaticTextures + maxDynamicTextures + numStaticFonts;

//         fonts: [numStaticFonts]FontData,
//         textures: std.BoundedArray(TextureData, numTotalTextures),

//         const Self = @This();

//         pub fn load(self: *Self) void
//         {
//             for (self.fonts) |*f| {
//                 f.loaded = false;
//             }
//             for (self.textures.buffer) |*t| {
//                 t.loaded = false;
//             }
//             self.textures.len = numStaticTextures;
//         }

//         pub fn getTextureData(self: *const Self, id: TextureId) ?*const TextureData
//         {
//             const index = self.getTextureIndex(id) orelse return null;
//             const texture = &self.textures.slice()[index];
//             return if (texture.loaded) texture else null;
//         }

//         pub fn registerStaticTexture(self: *Self, context: *bindings.Context, texture: StaticTextureEnum, textureFilePath: []const u8, allocator: std.mem.Allocator) !void
//         {
//             var tempArena = std.heap.ArenaAllocator.init(allocator);
//             defer tempArena.deinit();
//             const tempAllocator = tempArena.allocator();

//             const fullPath = try getFullPath(textureFilePath, tempAllocator);
//             const img = try zigimg.Image.fromFilePath(tempAllocator, fullPath);

//             const index = getStaticTextureIndex(texture);
//             try self.loadTexture(context, index, img);
//         }

//         pub fn getFontData(self: *const Self, font: StaticFontEnum) ?*const FontData
//         {
//             const f = &self.fonts[@enumToInt(font)];
//             return if (f.loaded) f else null;
//         }

//         pub fn registerStaticFont(self: *Self, context: *bindings.Context, font: StaticFontEnum, fontFilePath: []const u8, fontPixelSize: f32, fontScale: f32, lineHeight: f32, kerning: f32, allocator: std.mem.Allocator) !void
//         {
//             var tempArena = std.heap.ArenaAllocator.init(allocator);
//             defer tempArena.deinit();
//             const tempAllocator = tempArena.allocator();

//             // load font. TODO async-ify?
//             const fullPath = try getFullPath(fontFilePath, tempAllocator);

//             const atlasSize = ios_shader_defs.ATLAS_SIZE;
//             const maxSize = 1024 * 1024 * 1024;
//             const alignment = 8;
//             const sentinel = 0;
//             const fontFileData = try std.fs.cwd().readFileAllocOptions(tempAllocator, fullPath, maxSize, null, alignment, sentinel);

//             var fontLoadData = try tempAllocator.create(zigkm_common_asset.FontLoadData);
//             var grayscaleBitmap = try fontLoadData.load(atlasSize, fontFileData, fontPixelSize, fontScale, tempAllocator);
//             var img = zigimg.Image {
//                 .allocator = tempAllocator, // shouldn't be needed
//                 .width = atlasSize,
//                 .height = atlasSize,
//                 .pixels = .{
//                     .grayscale8 = @ptrCast([]zigimg.color.Grayscale8, grayscaleBitmap)
//                 },
//             };
//             verticalFlip(&img);
//             // const testPath = try std.fs.path.join(tempAllocator, &[_][]const u8 {
//             //     resourcePath, "testing.png"
//             // });
//             // try img.writeToFilePath(testPath, .{ .png = .{}});
//             // std.log.info("wrote test to {s}", .{testPath});
//             const textureIndex = try self.registerDynamicTexture(context, img);

//             self.fonts[@enumToInt(font)].load(fontLoadData, lineHeight, kerning, textureIndex);
//         }

//         fn registerDynamicTexture(self: *Self, context: *bindings.Context, image: zigimg.Image) !usize
//         {
//             const index = self.genNewTextureIndex() orelse return error.Overflow;
//             try self.loadTexture(context, index, image);
//             return index;
//         }

//         fn genNewTextureIndex(self: *Self) ?usize
//         {
//             _ = self.textures.addOne() catch return null;
//             return self.textures.len - 1;
//         }

//         // NOTE: replaces texture if already loaded
//         fn loadTexture(self: *Self, context: *bindings.Context, index: usize, image: zigimg.Image) !void
//         {
//             self.textures.slice()[index] = .{
//                 .loaded = true,
//                 .size = m.Vec2i.init(
//                     @intCast(i32, image.width), @intCast(i32, image.height)
//                 ),
//                 .texture = try bindings.createAndLoadTexture(context, image)
//             };
//         }

//         fn getTextureIndex(self: *const Self, id: TextureId) ?usize
//         {
//             switch (id) {
//                 .Static => |t| return getStaticTextureIndex(t),
//                 .Index => |index| {
//                     if (index >= self.textures.len) {
//                         return null;
//                     }
//                     return index;
//                 },
//                 .Name => |_| unreachable,
//             }
//         }

//         fn getStaticTextureIndex(texture: StaticTextureEnum) usize
//         {
//             return @enumToInt(texture);
//         }
//     };

//     return T;
// }
