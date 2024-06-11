const std = @import("std");

const m = @import("zigkm-math");
const stb = @import("zigkm-stb");
const platform = @import("zigkm-platform");

const platform_asset_data = switch (platform.platform) {
    .ios => @import("ios_asset_data.zig"),
    .web => @import("wasm_asset_data.zig"),
    .other => unreachable,
};

pub const AssetLoader = platform_asset_data.AssetLoader;

pub const TextureWrapMode = enum {
    clampToEdge,
    repeat,
};

pub const TextureFilter = enum {
    linear,
    nearest,
};

pub const TextureLoadRequest = struct {
    path: []const u8,
    filter: TextureFilter,
    wrapMode: TextureWrapMode,
};

pub const TextureLoadResponse = struct {
    texId: u64,
    size: m.Vec2usize,
    // Only used for .layer "images" (PSD layers).
    canvasSize: m.Vec2usize,
    topLeft: m.Vec2i,
};

pub const TextureData = struct {
    texId: u64,
    size: m.Vec2usize,
    // Only used for .layer "images" (PSD layers).
    canvasSize: m.Vec2usize,
    topLeft: m.Vec2i,
};

pub const FontLoadRequest = struct {
    path: []const u8,
    atlasSize: usize,
    size: f32,
    scale: f32,
    lineHeight: f32,
    kerning: f32,
};

pub const FontLoadResponse = struct {
    fontData: *const FontLoadData,
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
    ascent: f32,
    descent: f32,
    lineGap: f32,
    charData: [256]FontCharData,

    const Self = @This();

    pub fn load(self: *Self, atlasSize: usize, fontFileData: []const u8, size: f32, scale: f32, allocator: std.mem.Allocator) ![]u8
    {
        var tempArena = std.heap.ArenaAllocator.init(allocator);
        defer tempArena.deinit();
        var tempAllocator = tempArena.allocator();

        self.size = size;
        self.scale = scale;

        var fontInfo: stb.stbtt_fontinfo = undefined;
        if (stb.stbtt_InitFont(&fontInfo, &fontFileData[0], 0) == 0) {
            return error.stbtt_InitFont;
        }
        const stbScale = stb.stbtt_ScaleForMappingEmToPixels(&fontInfo, size / self.scale);

        var ascent: c_int = undefined;
        var descent: c_int = undefined;
        var lineGap: c_int = undefined;
        stb.stbtt_GetFontVMetrics(&fontInfo, &ascent, &descent, &lineGap);
        self.ascent = @as(f32, @floatFromInt(ascent)) * stbScale;
        self.descent = @as(f32, @floatFromInt(descent)) * stbScale;
        self.lineGap = @as(f32, @floatFromInt(lineGap)) * stbScale;

        const width = atlasSize;
        const height = atlasSize;
        var pixelBytes = try allocator.alloc(u8, width * height);
        @memset(pixelBytes, 0);
        var context: stb.stbtt_pack_context = undefined;
        if (stb.stbtt_PackBegin(&context, &pixelBytes[0], @intCast(width), @intCast(height), @intCast(width), 1, &tempAllocator) != 1) {
            return error.stbtt_PackBegin;
        }
        const oversampleN = 1;
        stb.stbtt_PackSetOversampling(&context, oversampleN, oversampleN);

        var charData = try tempAllocator.alloc(stb.stbtt_packedchar, self.charData.len);
        if (stb.stbtt_PackFontRange(&context, &fontFileData[0], 0, stb.STBTT_POINT_SIZE(size / scale), 0, @intCast(charData.len), &charData[0]) != 1) {
            return error.stbtt_PackFontRange;
        }

        stb.stbtt_PackEnd(&context);

        for (charData, 0..) |cd, i| {
            const sizeF = m.Vec2.initFromVec2i(m.Vec2i.init(cd.x1 - cd.x0, cd.y1 - cd.y0));
            self.charData[i] = FontCharData {
                .offset = m.Vec2.init(cd.xoff, -(sizeF.y + cd.yoff)),
                .size = sizeF,
                .uvOffset = m.Vec2.init(
                    @as(f32, @floatFromInt(cd.x0)) / @as(f32, @floatFromInt(width)),
                    @as(f32, @floatFromInt(height - cd.y1)) / @as(f32, @floatFromInt(height)), // TODO should do -1 ?
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
    ascent: f32,
    descent: f32,
    lineGap: f32,
    lineHeight: f32,
    kerning: f32,
    charData: [256]FontCharData,
};
