const std = @import("std");

const asset = @import("asset.zig");
const bindings = @import("ios_bindings.zig");
const ios = bindings.ios;
const ios_exports = @import("ios_exports.zig");

const m = @import("zigkm-math");

pub const MAX_QUADS = 1024;
pub const MAX_TEX_QUADS = 1024;
pub const MAX_ROUNDED_FRAMES = 32;

const RenderQueue = @import("render.zig").RenderQueue;

fn toFloat2(v: m.Vec2) ios.float2
{
    return .{
        .x = v.x,
        .y = v.y,
    };
}

fn toFloat4(v: m.Vec4) ios.float4
{
    return .{
        .x = v.x,
        .y = v.y,
        .z = v.z,
        .w = v.w,
    };
}

pub fn textRect(assets: anytype, text: []const u8, font: asset.Font) ?m.Rect
{
    const fontData = assets.getStaticFontData(font) orelse return null;

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

pub const RenderState = struct
{
    renderState: *bindings.RenderState2,

    const Self = @This();

    pub fn load(self: *Self) !void
    {
        self.* = RenderState {
            .renderState = try bindings.createRenderState(ios_exports._contextPtr),
        };
    }
};

pub fn render(
    renderQueue: *const RenderQueue,
    renderState: *const RenderState,
    offset: m.Vec2,
    scale: m.Vec2,
    anchor: m.Vec2,
    screenSize: m.Vec2,
    allocator: std.mem.Allocator) void
{
    _ = offset;
    _ = scale;
    _ = anchor;
    const context = ios_exports._contextPtr;

    var tempArena = std.heap.ArenaAllocator.init(allocator);
    defer tempArena.deinit();
    const tempAllocator = tempArena.allocator();
    _ = tempAllocator;

    if (renderQueue.quads.len > 0) {
        // TODO comptime check if render queue format changes
        const instanceBufferBytes = std.mem.sliceAsBytes(renderQueue.quads.slice());
        bindings.renderQuads(
            context, renderState.renderState, renderQueue.quads.len, instanceBufferBytes, screenSize.x, screenSize.y
        );
    }

    // if (renderQueue.texQuads.len > 0) {
    //     var texQuadInstances = tempAllocator.alloc(ios.TexQuadInstanceData, renderQueue.texQuads.len) catch {
    //         std.log.warn("Failed to allocate textured quad instances, skipping", .{});
    //         return;
    //     };
    //     var textures = tempAllocator.alloc(*bindings.Texture, renderQueue.texQuads.len) catch {
    //         std.log.warn("Failed to allocate textured quad Textures, skipping", .{});
    //         return;
    //     };
    //     for (renderQueue.texQuads.slice()) |texQuad, i| {
    //         texQuadInstances[i] = .{
    //             .quad = .{
    //                 .colors = .{
    //                     toFloat4(texQuad.colors[0]),
    //                     toFloat4(texQuad.colors[1]),
    //                     toFloat4(texQuad.colors[2]),
    //                     toFloat4(texQuad.colors[3]),
    //                 },
    //                 .bottomLeft = toFloat2(texQuad.bottomLeft),
    //                 .size = toFloat2(texQuad.size),
    //                 .depth = texQuad.depth,
    //                 .cornerRadius = texQuad.cornerRadius,
    //                 ._pad = undefined,
    //             },
    //             .uvBottomLeft = toFloat2(texQuad.uvBottomLeft),
    //             .uvSize = toFloat2(texQuad.uvSize),
    //         };
    //         textures[i] = texQuad.texture;
    //     }
    //     const instanceBufferBytes = std.mem.sliceAsBytes(texQuadInstances);
    //     bindings.renderTexQuads(context, renderState.renderState, instanceBufferBytes, textures, screenSize.x, screenSize.y);
    // }

    // if (renderQueue.texts.len > 0) {
    //     var textInstances = tempAllocator.create(std.BoundedArray(ios.TextInstanceData, ios.MAX_TEXT_INSTANCES)) catch {
    //         std.log.warn("Failed to allocate text instances, skipping", .{});
    //         return;
    //     };
    //     textInstances.len = 0;

    //     var atlases = tempAllocator.create(std.BoundedArray(*bindings.Texture, ios.MAX_ATLASES)) catch {
    //         std.log.warn("Failed to allocate text atlases, skipping", .{});
    //         return;
    //     };
    //     atlases.len = 0;

    //     // TODO: n^2 alert
    //     for (renderQueue.texts.slice()) |t| {
    //         const fontData = assets.getFontData(t.font) orelse continue;
    //         const atlasTextureData = assets.getTextureData(.{ .Index = fontData.textureIndex }) orelse continue;
    //         if (std.mem.indexOfScalar(*bindings.Texture, atlases.slice(), atlasTextureData.texture) == null) {
    //             atlases.append(atlasTextureData.texture) catch break;
    //         }
    //     }

    //     for (renderQueue.texts.slice()) |t| {
    //         const fontData = assets.getFontData(t.font) orelse continue;
    //         const atlasTextureData = assets.getTextureData(.{ .Index = fontData.textureIndex }) orelse continue;
    //         const atlasIndex = @intCast(u32, std.mem.indexOfScalar(*bindings.Texture, atlases.slice(), atlasTextureData.texture) orelse continue);

    //         var pos = m.Vec2.init(t.baselineLeft.x, t.baselineLeft.y);
    //         for (t.text) |c| {
    //             if (c == '\n') {
    //                 textInstances.append(.{
    //                     .color = toFloat4(t.color),
    //                     .bottomLeft = toFloat2(m.Vec2.zero),
    //                     .size = toFloat2(m.Vec2.zero),
    //                     .uvBottomLeft = toFloat2(m.Vec2.zero),
    //                     .atlasIndex = atlasIndex,
    //                     .depth = t.depth,
    //                     .atlasScale = fontData.scale,
    //                     ._pad = undefined,
    //                 }) catch break;
    //                 pos.y -= fontData.lineHeight;
    //                 pos.x = t.baselineLeft.x;
    //             } else {
    //                 const charData = fontData.charData[c];
    //                 textInstances.append(.{
    //                     .color = toFloat4(t.color),
    //                     .bottomLeft = toFloat2((m.add(pos, m.multScalar(charData.offset, fontData.scale)))),
    //                     .size = toFloat2(m.multScalar(charData.size, fontData.scale)),
    //                     .uvBottomLeft = toFloat2(charData.uvOffset),
    //                     .atlasIndex = atlasIndex,
    //                     .depth = t.depth,
    //                     .atlasScale = fontData.scale,
    //                     ._pad = undefined,
    //                 }) catch break;
    //                 pos.x += charData.advanceX * fontData.scale + fontData.kerning;
    //             }
    //         }
    //     }

    //     const uniforms = ios.TextUniforms {
    //         .screenSize = toFloat2(screenSize),
    //     };
    //     const instances = textInstances.slice();
    //     const instanceBufferBytes = std.mem.sliceAsBytes(instances);
    //     bindings.renderText(context, renderState.renderState, instances.len, instanceBufferBytes, atlases.slice(), &uniforms);
    // }
}

// Positions & sizes in pixels, depth in range [0, 1]
// const RenderEntryQuad = extern struct {
//     colors: [4]m.Vec4, // corner colors: 0,0 | 1,0 | 1,1 | 0,1
//     bottomLeft: m.Vec2,
//     size: m.Vec2,
//     depth: f32,
//     cornerRadius: f32,
//     _pad: m.Vec2,
// };

// const RenderEntryTexQuad = struct {
//     colors: [4]m.Vec4, // corner colors: 0,0 | 1,0 | 1,1 | 0,1
//     bottomLeft: m.Vec2,
//     size: m.Vec2,
//     depth: f32,
//     cornerRadius: f32,
//     uvBottomLeft: m.Vec2,
//     uvSize: m.Vec2,
//     texture: *bindings.Texture,
// };

// const RenderEntryText = struct {
//     text: []const u8,
//     baselineLeft: m.Vec2,
//     depth: f32,
//     font: asset.Font,
//     color: m.Vec4,
// };

// comptime {
//     std.debug.assert(@sizeOf(RenderEntryQuad) == 4 * 4 * 4 + 8 + 8 + 4 + 4 + 8);
//     std.debug.assert(@sizeOf(RenderEntryQuad) == @sizeOf(ios.QuadInstanceData));
// }

// pub const RenderQueue = struct {
//     quads: std.BoundedArray(RenderEntryQuad, ios.MAX_QUADS),
//     texQuads: std.BoundedArray(RenderEntryTexQuad, ios.MAX_TEX_QUADS),
//     texts: std.BoundedArray(RenderEntryText, 1024),

//     const Self = @This();

//     pub fn load(self: *Self) void
//     {
//         self.quads.len = 0;
//         self.texQuads.len = 0;
//         self.texts.len = 0;
//     }

//     pub fn quad(
//         self: *Self,
//         bottomLeft: m.Vec2,
//         depth: f32,
//         size: m.Vec2,
//         cornerRadius: f32,
//         color: m.Vec4) void
//     {
//         self.quadGradient(
//             bottomLeft,
//             depth,
//             size,
//             cornerRadius,
//             [4]m.Vec4 {color, color, color, color}
//         );
//     }

//     pub fn quadGradient(
//         self: *Self,
//         bottomLeft: m.Vec2,
//         depth: f32,
//         size: m.Vec2,
//         cornerRadius: f32,
//         colors: [4]m.Vec4) void
//     {
//         var entry = self.quads.addOne() catch {
//             std.log.warn("quads at max capacity, skipping", .{});
//             return;
//         };
//         entry.bottomLeft = bottomLeft;
//         entry.size = size;
//         entry.depth = depth;
//         entry.cornerRadius = cornerRadius;
//         entry.colors = colors;
//     }

//     pub fn texQuad(
//         self: *Self,
//         bottomLeft: m.Vec2,
//         depth: f32,
//         size: m.Vec2,
//         cornerRadius: f32,
//         texture: *bindings.Texture) void
//     {
//         self.texQuadColor(bottomLeft, depth, size, cornerRadius, texture, m.Vec4.white);
//     }

//     pub fn texQuadColor(
//         self: *Self,
//         bottomLeft: m.Vec2,
//         depth: f32,
//         size: m.Vec2,
//         cornerRadius: f32,
//         texture: *bindings.Texture,
//         color: m.Vec4) void
//     {
//         self.texQuadColorUvOffset(bottomLeft, depth, size, cornerRadius, texture, color, m.Vec2.zero, m.Vec2.one);
//     }

//     pub fn texQuadColorUvOffset(
//         self: *Self,
//         bottomLeft: m.Vec2,
//         depth: f32,
//         size: m.Vec2,
//         cornerRadius: f32,
//         texture: *bindings.Texture,
//         color: m.Vec4,
//         uvBottomLeft: m.Vec2,
//         uvSize: m.Vec2) void
//     {
//         var entry = self.texQuads.addOne() catch {
//             std.log.warn("tex quads at max capacity, skipping", .{});
//             return;
//         };
//         entry.bottomLeft = bottomLeft;
//         entry.size = size;
//         entry.depth = depth;
//         entry.cornerRadius = cornerRadius;
//         entry.colors = [4]m.Vec4 {color, color, color, color};
//         entry.uvBottomLeft = uvBottomLeft;
//         entry.uvSize = uvSize;
//         entry.texture = texture;
//     }

//     pub fn text(
//         self: *Self,
//         str: []const u8,
//         baselineLeft: m.Vec2,
//         depth: f32,
//         font: asset.Font,
//         color: m.Vec4) void
//     {
//         var entry = self.texts.addOne() catch {
//             std.log.warn("texts at max capacity, skipping", .{});
//             return;
//         };
//         entry.text = str;
//         entry.baselineLeft = baselineLeft;
//         entry.depth = depth;
//         entry.font = font;
//         entry.color = color;
//     }
// };
