const std = @import("std");

const m = @import("zigkm-math");
const platform = @import("zigkm-platform");

const asset_data = @import("asset_data.zig");
const platform_render = switch (platform.platform) {
    .ios => @import("ios_render.zig"),
    .web => @import("wasm_render.zig"),
    else => unreachable,
};

pub const RenderState = platform_render.RenderState;

pub const GlyphIterator = @import("render_text.zig").GlyphIterator;
pub const textRect = @import("render_text.zig").textRect;

pub const RenderQueue = struct {
    pub const EntryQuad = RenderEntryQuad;

    quads: std.BoundedArray(RenderEntryQuad, platform_render.MAX_QUADS),
    textureIds: std.BoundedArray(u64, platform_render.MAX_TEXTURES),

    const Self = @This();

    pub fn clear(self: *Self) void
    {
        self.quads.len = 0;
        self.textureIds.len = 1;
        self.textureIds.buffer[0] = 0;
    }

    pub fn quad(
        self: *Self,
        bottomLeft: m.Vec2,
        size: m.Vec2,
        depth: f32,
        cornerRadius: f32,
        color: m.Vec4) void
    {
        self.quadGradient(
            bottomLeft,
            size,
            depth,
            cornerRadius,
            [4]m.Vec4 {color, color, color, color}
        );
    }

    pub fn quadGradient(
        self: *Self,
        bottomLeft: m.Vec2,
        size: m.Vec2,
        depth: f32,
        cornerRadius: f32,
        colors: [4]m.Vec4) void
    {
        self.quad2(bottomLeft, size, depth, cornerRadius, m.Vec2.zero, m.Vec2.one, null, colors);
    }

    pub fn texQuad(
        self: *Self,
        bottomLeft: m.Vec2,
        size: m.Vec2,
        depth: f32,
        cornerRadius: f32,
        textureData: *const asset_data.TextureData) void
    {
        self.texQuadColor(bottomLeft, size, depth, cornerRadius, textureData, m.Vec4.white);
    }

    pub fn texQuadColor(
        self: *Self,
        bottomLeft: m.Vec2,
        size: m.Vec2,
        depth: f32,
        cornerRadius: f32,
        textureData: *const asset_data.TextureData,
        color: m.Vec4) void
    {
        self.texQuadColorUvOffset(bottomLeft, size, depth, cornerRadius, m.Vec2.zero, m.Vec2.one, textureData, color);
    }

    pub fn texQuadColorUvOffset(
        self: *Self,
        bottomLeft: m.Vec2,
        size: m.Vec2,
        depth: f32,
        cornerRadius: f32,
        uvBottomLeft: m.Vec2,
        uvSize: m.Vec2,
        textureData: *const asset_data.TextureData,
        color: m.Vec4) void
    {
        self.quad2(bottomLeft, size, depth, cornerRadius, uvBottomLeft, uvSize, textureData.texId, .{color, color, color, color});
    }

    pub fn quad2(
        self: *Self,
        bottomLeft: m.Vec2,
        size: m.Vec2,
        depth: f32,
        cornerRadius: f32,
        uvBottomLeft: m.Vec2,
        uvSize: m.Vec2,
        textureId: ?u64,
        colors: [4]m.Vec4) void
    {
        const textureIndex = if (textureId) |id| self.getOrPushTextureIndex(id) orelse {
            std.log.warn("textures at max capacity, skipping", .{});
            return;
        } else null;
        self.quad22(bottomLeft, size, depth, cornerRadius, uvBottomLeft, uvSize, textureIndex, colors, false);
    }

    pub fn quad22(
        self: *Self,
        bottomLeft: m.Vec2,
        size: m.Vec2,
        depth: f32,
        cornerRadius: f32,
        uvBottomLeft: m.Vec2,
        uvSize: m.Vec2,
        textureIndex: ?u32,
        colors: [4]m.Vec4,
        isGrayscale: bool) void
    {
        const entry = self.quads.addOne() catch {
            std.log.warn("quads at max capacity, skipping", .{});
            return;
        };
        entry.* = .{
            .colors = colors,
            .bottomLeft = bottomLeft,
            .size = size,
            .uvBottomLeft = uvBottomLeft,
            .uvSize = uvSize,
            .depth = depth,
            .cornerRadius = cornerRadius,
            .textureIndex = if (textureIndex) |index| index else 0,
            .textureMode = if (textureIndex == null) 0 else (if (isGrayscale) 2 else 1),
        };
    }

    pub fn text(
        self: *Self,
        str: []const u8,
        baselineLeft: m.Vec2,
        depth: f32,
        fontData: *const asset_data.FontData,
        color: m.Vec4) void
    {
        self.textSize(str, baselineLeft, depth, fontData.size * fontData.scale, fontData, color);
    }

    pub fn textSize(
        self: *Self,
        str: []const u8,
        baselineLeft: m.Vec2,
        depth: f32,
        size: f32,
        fontData: *const asset_data.FontData,
        color: m.Vec4) void
    {
        self.textSizeMaxWidth(str, baselineLeft, depth, size, null, fontData, color);
    }

    pub fn textMaxWidth(
        self: *Self,
        str: []const u8,
        baselineLeft: m.Vec2,
        depth: f32,
        width: ?f32,
        fontData: *const asset_data.FontData,
        color: m.Vec4) void
    {
        self.textSizeMaxWidth(str, baselineLeft, depth, fontData.size * fontData.scale, width, fontData, color);
    }

    pub fn textSizeMaxWidth(
        self: *Self,
        str: []const u8,
        baselineLeft: m.Vec2,
        depth: f32,
        size: f32,
        width: ?f32,
        fontData: *const asset_data.FontData,
        color: m.Vec4) void
    {
        const atlasTextureIndex = self.getOrPushTextureIndex(fontData.atlasData.texId) orelse {
            std.log.warn("textures at max capacity, skipping", .{});
            return;
        };
        const scale = size / (fontData.size * fontData.scale);
        var glyphIt = GlyphIterator.init(str, fontData, width);
        while (glyphIt.next()) |g| {
            const pos = m.add(baselineLeft, g.position);
            const cornerRadius = 0;
            self.quad22(
                pos, m.multScalar(g.size, scale), depth, cornerRadius, g.uvOffset, g.uvSize,
                atlasTextureIndex, .{color, color, color, color}, true,
            );
        }
    }

    pub fn render(
        self: *const Self,
        renderState: *const RenderState,
        screenSize: m.Vec2,
        allocator: std.mem.Allocator) void
    {
        const offset = m.Vec2.zero;
        const scale = m.Vec2.one;
        const anchor = m.Vec2.zero;
        platform_render.render(self, renderState, offset, scale, anchor, screenSize, allocator);
    }

    pub fn render2(
        self: *const Self,
        renderState: *const RenderState,
        screenSize: m.Vec2,
        scrollY: f32,
        allocator: std.mem.Allocator) void
    {
        const offset = m.Vec2.init(0.0, scrollY + screenSize.y);
        const scale = m.Vec2.init(1.0, -1.0);
        const anchor = m.Vec2.init(0.0, 1.0);
        platform_render.render(self, renderState, offset, scale, anchor, screenSize, allocator);
    }

    pub fn getOrPushTextureIndex(self: *Self, id: u64) ?u32
    {
        // TODO: O(n^2) alert
        if (std.mem.indexOfScalar(u64, self.textureIds.slice(), id)) |index| {
            return @intCast(index);
        }
        self.textureIds.append(id) catch return null;
        return self.textureIds.len - 1;
    }
};

const RenderEntryQuad = extern struct {
    colors: [4]m.Vec4, // corner colors: 0,0 | 1,0 | 1,1 | 0,1
    bottomLeft: m.Vec2,
    size: m.Vec2,
    uvBottomLeft: m.Vec2,
    uvSize: m.Vec2,
    depth: f32,
    cornerRadius: f32,
    textureIndex: u32,
    textureMode: u32,
};
