const std = @import("std");

const m = @import("zigkm-math");

const w = @import("wasm_bindings.zig");

pub const MAX_QUADS = 32 * 1024;
pub const MAX_TEXTURES = 16;

const RenderQueue = @import("render.zig").RenderQueue;

pub const RenderState = struct
{
    quadState: QuadState,

    pub fn load(self: *RenderState) !void
    {
        try self.quadState.load();
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
    _ = allocator;

    if (renderQueue.quads.len > 0) {
        const quadState = &renderState.quadState;
        w.glUseProgram(quadState.programId);
        w.glBindVertexArray(quadState.vao);

        for (renderQueue.textureIds.slice(), 0..) |id, i| {
            w.glActiveTexture(w.GL_TEXTURE0 + i);
            w.glBindTexture(w.GL_TEXTURE_2D, @intCast(id));
        }
        const values = &[_]c_int {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15};
        w.glUniform1iv(quadState.texturesLoc, @ptrCast(values.ptr), values.len);

        w.glBindBuffer(w.GL_ARRAY_BUFFER, quadState.instanceBuffer);
        const instanceBufferBytes = std.mem.sliceAsBytes(renderQueue.quads.slice());
        w.glBufferSubData(w.GL_ARRAY_BUFFER, 0, @ptrCast(instanceBufferBytes.ptr), instanceBufferBytes.len);

        w.glUniform2fv(quadState.screenSizeLoc, screenSize.x, screenSize.y);

        w.glDrawArraysInstanced(w.GL_TRIANGLES, 0, 6, renderQueue.quads.len);
    }
}

const QuadState = struct {
    programId: c_uint,
    vao: c_uint,
    instanceBuffer: c_uint,
    screenSizeLoc: c_uint,
    texturesLoc: c_uint,

    const vert = @embedFile("wasm/quad.vert");
    const frag = @embedFile("wasm/quad.frag");

    pub fn load(self: *QuadState) !void
    {
        const Entry = RenderQueue.EntryQuad;
        const entrySize = @sizeOf(Entry);

        // TODO error check all these
        const vertQuadId = w.compileShader(&vert[0], vert.len, w.GL_VERTEX_SHADER);
        const fragQuadId = w.compileShader(&frag[0], frag.len, w.GL_FRAGMENT_SHADER);

        const programId = w.linkShaderProgram(vertQuadId, fragQuadId);

        const instanceBuffer = w.glCreateBuffer();
        w.glBindBuffer(w.GL_ARRAY_BUFFER, instanceBuffer);
        w.glBufferDataSize(w.GL_ARRAY_BUFFER, entrySize * MAX_QUADS, w.GL_DYNAMIC_DRAW);

        const vao = w.glCreateVertexArray();
        w.glBindVertexArray(vao);

        const AttribData = struct {
            name: []const u8,
            size: c_uint,
            type: c_uint,
            offset: c_uint,
        };
        const instanceAttribs = [_]AttribData {
            .{
                .name = "vi_colorBL",
                .size = 4,
                .type = w.GL_FLOAT,
                .offset = 0,
            },
            .{
                .name = "vi_colorBR",
                .size = 4,
                .type = w.GL_FLOAT,
                .offset = @sizeOf(m.Vec4),
            },
            .{
                .name = "vi_colorTL",
                .size = 4,
                .type = w.GL_FLOAT,
                .offset = @sizeOf(m.Vec4) * 2,
            },
            .{
                .name = "vi_colorTR",
                .size = 4,
                .type = w.GL_FLOAT,
                .offset = @sizeOf(m.Vec4) * 3,
            },
            .{
                .name = "vi_bottomLeftSize",
                .size = 4,
                .type = w.GL_FLOAT,
                .offset = @bitOffsetOf(Entry, "bottomLeft") / 8,
            },
            .{
                .name = "vi_uvBottomLeftSize",
                .size = 4,
                .type = w.GL_FLOAT,
                .offset = @bitOffsetOf(Entry, "uvBottomLeft") / 8,
            },
            .{
                .name = "vi_depthCornerRadius",
                .size = 2,
                .type = w.GL_FLOAT,
                .offset = @bitOffsetOf(Entry, "depth") / 8,
            },
            .{
                .name = "vi_textureIndexMode",
                .size = 2,
                .type = w.GL_UNSIGNED_INT,
                .offset = @bitOffsetOf(Entry, "textureIndex") / 8,
            },
        };

        for (instanceAttribs) |a| {
            const attribLoc = try getAttributeLocation(programId, a.name);
            w.glEnableVertexAttribArray(attribLoc);
            if (a.type == w.GL_FLOAT) {
                const normalized = 0;
                w.glVertexAttribPointer(attribLoc, a.size, a.type, normalized, entrySize, a.offset);
            } else {
                w.glVertexAttribIPointer(attribLoc, a.size, a.type, entrySize, a.offset);
            }
            w.glVertexAttribDivisor(attribLoc, 1);
        }

        self.* = .{
            .programId = programId,
            .vao = vao,
            .instanceBuffer = instanceBuffer,
            .screenSizeLoc = try getUniformLocation(programId, "u_screenSize"),
            .texturesLoc = try getUniformLocation(programId, "u_textures"),
        };
    }
};

fn getAttributeLocation(programId: c_uint, attributeName: []const u8) !c_uint
{
    const loc = w.glGetAttribLocation(programId, &attributeName[0], attributeName.len);
    if (loc == -1) {
        std.log.err("getAttributeLocation failed for {s}", .{attributeName});
        return error.MissingAttributeLoc;
    } else {
        return @intCast(loc);
    }
}

fn getUniformLocation(programId: c_uint, uniformName: []const u8) !c_uint
{
    const loc = w.glGetUniformLocation(programId, &uniformName[0], uniformName.len);
    if (loc == -1) {
        std.log.err("getUniformLocation failed for {s}", .{uniformName});
        return error.MissingUniformLoc;
    } else {
        return @intCast(loc);
    }
}
