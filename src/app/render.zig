const std = @import("std");

const m = @import("zigkm-math");

const asset_data = @import("asset_data.zig");
const defs = @import("defs.zig");
const platform_render = switch (defs.platform) {
    .ios => @import("ios_render.zig"),
    .web => @import("wasm_render.zig"),
};

pub const RenderState = platform_render.RenderState;

pub const textRect = @import("render_text.zig").textRect;

pub const RenderQueue = struct {
    quads: std.BoundedArray(RenderEntryQuad, platform_render.MAX_QUADS),
    texQuads: std.BoundedArray(RenderEntryTexQuad, platform_render.MAX_TEX_QUADS),
    roundedFrames: std.BoundedArray(RenderEntryRoundedFrame, platform_render.MAX_ROUNDED_FRAMES),
    texts: std.BoundedArray(RenderEntryText, 1024),

    const Self = @This();

    pub fn clear(self: *Self) void
    {
        self.quads.len = 0;
        self.texQuads.len = 0;
        self.roundedFrames.len = 0;
        self.texts.len = 0;
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
        size: m.Vec2,
        depth: f32,
        cornerRadius: f32,
        textureData: *const asset_data.TextureData) void
    {
        self.texQuadColor(bottomLeft, size, depth, cornerRadius, textureData, m.Vec4.white);
    }

    // pub fn texQuadKeepAspect(
    //     self: *Self,
    //     bottomLeft: m.Vec2,
    //     size: m.Vec2,
    //     depth: f32,
    //     cornerRadius: f32,
    //     _: void,
    //     textureData: *const asset_data.TextureData) void
    // {
    //     self.texQuadColorUvOffset();
    // }

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

    pub fn roundedFrame(self: *Self, rf: RenderEntryRoundedFrame) void
    {
        self.roundedFrames.append(rf) catch {
            std.log.warn("rounded frames at max capacity, skipping", .{});
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
        self.textWithMaxWidth(str, baselineLeft, depth, null, fontData, color);
    }

    pub fn textWithMaxWidth(
        self: *Self,
        str: []const u8,
        baselineLeft: m.Vec2,
        depth: f32,
        width: ?f32,
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
            .width = width,
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

const RenderEntryRoundedFrame = struct {
    bottomLeft: m.Vec2,
    size: m.Vec2,
    depth: f32,
    frameBottomLeft: m.Vec2,
    frameSize: m.Vec2,
    cornerRadius: f32,
    color: m.Vec4,
};

const RenderEntryText = struct {
    text: []const u8,
    baselineLeft: m.Vec2,
    depth: f32,
    width: ?f32,
    fontData: *const asset_data.FontData,
    color: m.Vec4,
};
