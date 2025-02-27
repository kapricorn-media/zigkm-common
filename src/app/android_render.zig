const std = @import("std");

const m = @import("zigkm-math");

const c = @import("android_c.zig");

var _state = &@import("android_exports.zig")._state;

pub const MAX_QUADS = 64 * 1024;
pub const MAX_TEXTURES = 64;

// This is a limitation on the webGL shader.
pub const MAX_TEXTURES_PER_DRAW = 8;

const RenderQueue = @import("render.zig").RenderQueue;

pub const RenderState = struct
{
    quadState: QuadState,

    pub fn load(self: *RenderState, tempAllocator: std.mem.Allocator) !void
    {
        try self.quadState.load(tempAllocator);
    }
};

pub fn render(
    renderQueue: *const RenderQueue,
    renderState: *const RenderState,
    screenSize: m.Vec2,
    allocator: std.mem.Allocator) void
{
    const quads = renderQueue.quads.slice();
    if (quads.len > 0) {
        const quadState = &renderState.quadState;
        c.glUseProgram(quadState.programId);
        c.glBindVertexArray(quadState.vao);

        const values = &[MAX_TEXTURES_PER_DRAW]c.GLint {0, 1, 2, 3, 4, 5, 6, 7};
        c.glUniform1iv(quadState.uniformLocTextures, values.len, values.ptr);
        c.glUniform2f(quadState.uniformLocScreenSize, screenSize.x, screenSize.y);

        var quadInd: usize = 0;
        const quadsCopy = allocator.dupe(RenderQueue.EntryQuad, quads) catch unreachable;
        while (quadInd < quadsCopy.len) {
            var textureIds = [MAX_TEXTURES_PER_DRAW]?u64{null, null, null, null, null, null, null, null};
            var quadInd2 = quadInd;
            while (quadInd2 < quadsCopy.len) {
                const quad = &quadsCopy[quadInd2];
                if (quad.textureMode != 0) {
                    const textureId = renderQueue.textureIds.slice()[quad.textureIndex];
                    var assignedTextureId = false;
                    for (&textureIds, 0..) |*tid, i| {
                        if (tid.*) |id| {
                            if (textureId == id) {
                                quad.textureIndex = @intCast(i);
                                assignedTextureId = true;
                                break;
                            }
                        } else {
                            tid.* = textureId;
                            quad.textureIndex = @intCast(i);
                            assignedTextureId = true;
                            break;
                        }
                    }
                    if (!assignedTextureId) {
                        break;
                    }
                }
                quadInd2 += 1;
            }

            for (textureIds, 0..) |tid, i| {
                if (tid) |id| {
                    c.glActiveTexture(@intCast(c.GL_TEXTURE0 + i));
                    c.glBindTexture(c.GL_TEXTURE_2D, @intCast(id));
                }
            }

            const quadsSlice = quadsCopy[quadInd..quadInd2];
            c.glBindBuffer(c.GL_ARRAY_BUFFER, quadState.instanceBuffer);
            const instanceBufferBytes = std.mem.sliceAsBytes(quadsSlice);
            c.glBufferSubData(c.GL_ARRAY_BUFFER, 0, @intCast(instanceBufferBytes.len), instanceBufferBytes.ptr);

            c.glDrawArraysInstanced(c.GL_TRIANGLES, 0, 6, @intCast(quadsSlice.len));
            quadInd = quadInd2;
        }
    }
}

const QuadState = struct {
    programId: c.GLuint,
    vao: c.GLuint,
    instanceBuffer: c.GLuint,
    uniformLocScreenSize: c.GLint,
    uniformLocTextures: c.GLint,

    fn load(self: *QuadState, tempAllocator: std.mem.Allocator) !void
    {
        const assetManager = _state.*.activity.assetManager orelse return error.assetManager;
        const programId = try c.compileShaders("shaders/quad.vert", "shaders/quad.frag", assetManager, tempAllocator);

        const entrySize = @sizeOf(RenderQueue.EntryQuad);
        var instanceBuffer: c.GLuint = undefined;
        c.glGenBuffers(1, &instanceBuffer);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, instanceBuffer);
        c.glBufferData(c.GL_ARRAY_BUFFER, entrySize * MAX_QUADS, null, c.GL_DYNAMIC_DRAW);

        var vao: c.GLuint = undefined;
        c.glGenVertexArrays(1, &vao);
        c.glBindVertexArray(vao);
        const AttribData = struct {
            name: [:0]const u8,
            size: c.GLint,
            type: c.GLenum,
            offset: usize,
        };
        const instanceAttribs = [_]AttribData {
            .{
                .name = "vi_colorBL",
                .size = 4,
                .type = c.GL_FLOAT,
                .offset = 0,
            },
            .{
                .name = "vi_colorBR",
                .size = 4,
                .type = c.GL_FLOAT,
                .offset = @sizeOf(m.Vec4),
            },
            .{
                .name = "vi_colorTL",
                .size = 4,
                .type = c.GL_FLOAT,
                .offset = @sizeOf(m.Vec4) * 2,
            },
            .{
                .name = "vi_colorTR",
                .size = 4,
                .type = c.GL_FLOAT,
                .offset = @sizeOf(m.Vec4) * 3,
            },
            .{
                .name = "vi_bottomLeftSize",
                .size = 4,
                .type = c.GL_FLOAT,
                .offset = @bitOffsetOf(RenderQueue.EntryQuad, "bottomLeft") / 8,
            },
            .{
                .name = "vi_uvBottomLeftSize",
                .size = 4,
                .type = c.GL_FLOAT,
                .offset = @bitOffsetOf(RenderQueue.EntryQuad, "uvBottomLeft") / 8,
            },
            .{
                .name = "vi_depthCornerRadius",
                .size = 2,
                .type = c.GL_FLOAT,
                .offset = @bitOffsetOf(RenderQueue.EntryQuad, "depth") / 8,
            },
            .{
                .name = "vi_shadowSize",
                .size = 1,
                .type = c.GL_FLOAT,
                .offset = @bitOffsetOf(RenderQueue.EntryQuad, "shadowSize") / 8,
            },
            .{
                .name = "vi_shadowColor",
                .size = 4,
                .type = c.GL_FLOAT,
                .offset = @bitOffsetOf(RenderQueue.EntryQuad, "shadowColor") / 8,
            },
            .{
                .name = "vi_textureIndexMode",
                .size = 2,
                .type = c.GL_UNSIGNED_INT,
                .offset = @bitOffsetOf(RenderQueue.EntryQuad, "textureIndex") / 8,
            },
        };
        for (instanceAttribs) |a| {
            const attribLoc = try c.getAttributeLocation(programId, a.name);
            c.glEnableVertexAttribArray(attribLoc);
            if (a.type == c.GL_FLOAT) {
                c.glVertexAttribPointer(attribLoc, a.size, a.type, c.GL_FALSE, entrySize, @ptrFromInt(a.offset));
            } else {
                c.glVertexAttribIPointer(attribLoc, a.size, a.type, entrySize, @ptrFromInt(a.offset));
            }
            c.glVertexAttribDivisor(attribLoc, 1);
        }

        self.* = .{
            .programId = programId,
            .vao = vao,
            .instanceBuffer = instanceBuffer,
            .uniformLocScreenSize = try c.getUniformLocation(programId, "u_screenSize"),
            .uniformLocTextures = try c.getUniformLocation(programId, "u_textures"),
        };
    }
};
