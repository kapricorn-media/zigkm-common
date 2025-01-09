const std = @import("std");

const m = @import("zigkm-math");

const asset = @import("asset.zig");
const bindings = @import("ios_bindings.zig");
const ios = bindings.ios;
const ios_exports = @import("ios_exports.zig");
const render_text = @import("render_text.zig");

pub const MAX_QUADS = ios.MAX_QUADS;
pub const MAX_TEXTURES = ios.MAX_TEXTURES;

const RenderQueue = @import("render.zig").RenderQueue;

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
    screenSize: m.Vec2,
    allocator: std.mem.Allocator) void
{
    _ = allocator;

    if (renderQueue.quads.len > 0) {
        comptime {
            const TypeCpu = RenderQueue.EntryQuad;
            const TypeGpu = ios.QuadInstanceData;

            const sizeCpu = @sizeOf(TypeCpu);
            const sizeGpu = @sizeOf(TypeGpu);
            if (sizeCpu != sizeGpu) {
                @compileLog(sizeCpu, sizeGpu);
                unreachable;
            }
        }

        const instanceBufferBytes = std.mem.sliceAsBytes(renderQueue.quads.slice());
        bindings.renderQuads(
            ios_exports._contextPtr, renderState.renderState,
            renderQueue.quads.len, instanceBufferBytes,
            renderQueue.textureIds.slice(),
            screenSize.x, screenSize.y
        );
    }
}
