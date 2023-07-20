const std = @import("std");

const m = @import("zigkm-math");

const asset = @import("asset.zig");
const bindings = @import("ios_bindings.zig");
const ios = bindings.ios;
const ios_exports = @import("ios_exports.zig");
const render_text = @import("render_text.zig");

pub const MAX_QUADS = ios.MAX_QUADS;
pub const MAX_TEX_QUADS = ios.MAX_TEX_QUADS;
pub const MAX_ROUNDED_FRAMES = 32; // eh, not supported

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

    if (renderQueue.quads.len > 0) {
        // TODO comptime check if render queue format changes
        const instanceBufferBytes = std.mem.sliceAsBytes(renderQueue.quads.slice());
        bindings.renderQuads(
            context, renderState.renderState, renderQueue.quads.len, instanceBufferBytes, screenSize.x, screenSize.y
        );
    }

    if (renderQueue.texQuads.len > 0) {
        var texQuadInstances = tempAllocator.alloc(ios.TexQuadInstanceData, renderQueue.texQuads.len) catch {
            std.log.warn("Failed to allocate textured quad instances, skipping", .{});
            return;
        };
        var textures = tempAllocator.alloc(*bindings.Texture, renderQueue.texQuads.len) catch {
            std.log.warn("Failed to allocate textured quad Textures, skipping", .{});
            return;
        };
        for (renderQueue.texQuads.slice()) |texQuad, i| {
            texQuadInstances[i] = .{
                .quad = .{
                    .colors = .{
                        toFloat4(texQuad.colors[0]),
                        toFloat4(texQuad.colors[1]),
                        toFloat4(texQuad.colors[2]),
                        toFloat4(texQuad.colors[3]),
                    },
                    .bottomLeft = toFloat2(texQuad.bottomLeft),
                    .size = toFloat2(texQuad.size),
                    .depth = texQuad.depth,
                    .cornerRadius = texQuad.cornerRadius,
                    ._pad = undefined,
                },
                .uvBottomLeft = toFloat2(texQuad.uvBottomLeft),
                .uvSize = toFloat2(texQuad.uvSize),
            };
            textures[i] = @intToPtr(*bindings.Texture, texQuad.textureData.texId);
        }
        const instanceBufferBytes = std.mem.sliceAsBytes(texQuadInstances);
        bindings.renderTexQuads(context, renderState.renderState, instanceBufferBytes, textures, screenSize.x, screenSize.y);
    }

    if (renderQueue.texts.slice().len > 0) {
        var textInstances = tempAllocator.create(std.BoundedArray(ios.TextInstanceData, ios.MAX_TEXT_INSTANCES)) catch {
            std.log.warn("Failed to allocate text instances, skipping", .{});
            return;
        };
        textInstances.len = 0;

        var atlases = tempAllocator.create(std.BoundedArray(*bindings.Texture, ios.MAX_ATLASES)) catch {
            std.log.warn("Failed to allocate text atlases, skipping", .{});
            return;
        };
        atlases.len = 0;

        // TODO: n^2 alert
        for (renderQueue.texts.slice()) |e| {
            const atlasTex = @intToPtr(*bindings.Texture, e.fontData.atlasData.texId);
            if (std.mem.indexOfScalar(*bindings.Texture, atlases.slice(), atlasTex) == null) {
                atlases.append(atlasTex) catch break;
            }
        }

        var buf = render_text.TextRenderBuffer.init(ios.MAX_TEXT_INSTANCES, tempAllocator) catch {
            std.log.err("Failed to allocate TextRenderBuffer", .{});
            return;
        };
        for (renderQueue.texts.slice()) |e| {
            const atlasTex = @intToPtr(*bindings.Texture, e.fontData.atlasData.texId);
            const atlasIndex = @intCast(u32, std.mem.indexOfScalar(*bindings.Texture, atlases.slice(), atlasTex) orelse continue);

            const baselineLeft = e.baselineLeft;
            const n = buf.fill(e.text, baselineLeft, e.fontData, e.width);
            var i: usize = 0;
            while (i < n) : (i += 1) {
                textInstances.append(.{
                    .color = toFloat4(e.color),
                    .bottomLeft = toFloat2(buf.positions[i]),
                    .size = toFloat2(buf.sizes[i]),
                    .uvBottomLeft = toFloat2(buf.uvOffsets[i]),
                    .atlasIndex = atlasIndex,
                    .depth = e.depth,
                    .atlasScale = e.fontData.scale,
                    ._pad = undefined,
                }) catch break;
            }
        }

        const uniforms = ios.TextUniforms {
            .screenSize = toFloat2(screenSize),
        };
        const instances = textInstances.slice();
        const instanceBufferBytes = std.mem.sliceAsBytes(instances);
        bindings.renderText(context, renderState.renderState, instances.len, instanceBufferBytes, atlases.slice(), &uniforms);
    }
}
