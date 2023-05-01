const std = @import("std");

const m = @import("zigkm-common-math");

const asset_data = @import("asset_data.zig");
const defs = @import("defs.zig");
const platform_render = switch (defs.platform) {
    .ios => @import("ios_render.zig"),
    .web => @import("wasm_render.zig"),
};

pub const RenderState = platform_render.RenderState;

pub fn textRect(text: []const u8, fontData: *const asset_data.FontData) ?m.Rect
{
    var pos = m.Vec2.zero;
    var min = m.Vec2.zero;
    var max = m.Vec2.zero;
    for (text) |c| {
        if (c == '\n') {
            pos.y -= fontData.lineHeight;
            pos.x = 0.0;

            min.y = std.math.min(min.y, pos.y);
            max.y = std.math.max(max.y, pos.y);
        } else {
            const charData = fontData.charData[c];
            pos.x += charData.advanceX + fontData.kerning;

            min.x = std.math.min(min.x, pos.x);
            max.x = std.math.max(max.x, pos.x + charData.size.x);
            min.y = std.math.min(min.y, pos.y);
            max.y = std.math.max(max.y, pos.y + charData.size.y);

            const offsetPos = m.Vec2.add(pos, charData.offset);
            min.x = std.math.min(min.x, offsetPos.x);
            max.x = std.math.max(max.x, offsetPos.x + charData.size.x);
            min.y = std.math.min(min.y, offsetPos.y);
            max.y = std.math.max(max.y, offsetPos.y + charData.size.y);
        }
    }

    return m.Rect.init(min, max);
}

pub const RenderQueue = struct {
    quads: std.BoundedArray(RenderEntryQuad, platform_render.MAX_QUADS),
    texQuads: std.BoundedArray(RenderEntryTexQuad, platform_render.MAX_TEX_QUADS),
    texts: std.BoundedArray(RenderEntryText, 1024),

    const Self = @This();

    pub fn load(self: *Self) void
    {
        self.quads.len = 0;
        self.texQuads.len = 0;
        self.texts.len = 0;
    }

    pub fn quad(
        self: *Self,
        bottomLeft: m.Vec2,
        depth: f32,
        size: m.Vec2,
        cornerRadius: f32,
        color: m.Vec4) void
    {
        self.quadGradient(
            bottomLeft,
            depth,
            size,
            cornerRadius,
            [4]m.Vec4 {color, color, color, color}
        );
    }

    pub fn quadGradient(
        self: *Self,
        bottomLeft: m.Vec2,
        depth: f32,
        size: m.Vec2,
        cornerRadius: f32,
        colors: [4]m.Vec4) void
    {
        var entry = self.quads.addOne() catch {
            std.log.warn("quads at max capacity, skipping", .{});
            return;
        };
        entry.* = .{
            .bottomLeft = bottomLeft,
            .size = size,
            .depth = depth,
            .cornerRadius = cornerRadius,
            .colors = colors,
            ._pad = undefined,
        };
    }

    pub fn texQuad(
        self: *Self,
        bottomLeft: m.Vec2,
        depth: f32,
        size: m.Vec2,
        cornerRadius: f32,
        textureData: *const asset_data.TextureData) void
    {
        self.texQuadColor(bottomLeft, depth, size, cornerRadius, textureData, m.Vec4.white);
    }

    pub fn texQuadColor(
        self: *Self,
        bottomLeft: m.Vec2,
        depth: f32,
        size: m.Vec2,
        cornerRadius: f32,
        textureData: *const asset_data.TextureData,
        color: m.Vec4) void
    {
        self.texQuadColorUvOffset(bottomLeft, depth, size, cornerRadius, textureData, color, m.Vec2.zero, m.Vec2.one);
    }

    pub fn texQuadColorUvOffset(
        self: *Self,
        bottomLeft: m.Vec2,
        depth: f32,
        size: m.Vec2,
        cornerRadius: f32,
        textureData: *const asset_data.TextureData,
        color: m.Vec4,
        uvBottomLeft: m.Vec2,
        uvSize: m.Vec2) void
    {
        var entry = self.texQuads.addOne() catch {
            std.log.warn("tex quads at max capacity, skipping", .{});
            return;
        };
        entry.* = .{
            .bottomLeft = bottomLeft,
            .size = size,
            .depth = depth,
            .cornerRadius = cornerRadius,
            .colors = [4]m.Vec4 {color, color, color, color},
            .uvBottomLeft = uvBottomLeft,
            .uvSize = uvSize,
            .textureData = textureData,
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
        var entry = self.texts.addOne() catch {
            std.log.warn("texts at max capacity, skipping", .{});
            return;
        };
        entry.* = .{
            .text = str,
            .baselineLeft = baselineLeft,
            .depth = depth,
            .fontData = fontData,
            .color = color,
        };
    }

    pub fn render(
        self: *const Self,
        renderState: *const RenderState,
        screenSize: m.Vec2,
        allocator: std.mem.Allocator) void
    {
        platform_render.render(self, renderState, screenSize, allocator);
    }
};

// Positions & sizes in pixels, depth in range [0, 1]
const RenderEntryQuad = extern struct {
    colors: [4]m.Vec4, // corner colors: 0,0 | 1,0 | 1,1 | 0,1
    bottomLeft: m.Vec2,
    size: m.Vec2,
    depth: f32,
    cornerRadius: f32,
    _pad: m.Vec2,
};

const RenderEntryTexQuad = struct {
    colors: [4]m.Vec4, // corner colors: 0,0 | 1,0 | 1,1 | 0,1
    bottomLeft: m.Vec2,
    size: m.Vec2,
    depth: f32,
    cornerRadius: f32,
    uvBottomLeft: m.Vec2,
    uvSize: m.Vec2,
    textureData: *const asset_data.TextureData,
};

const RenderEntryText = struct {
    text: []const u8,
    baselineLeft: m.Vec2,
    depth: f32,
    fontData: *const asset_data.FontData,
    color: m.Vec4,
};
