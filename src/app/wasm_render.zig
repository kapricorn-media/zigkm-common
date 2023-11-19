const std = @import("std");

const m = @import("zigkm-math");

const w = @import("wasm_bindings.zig");

pub const MAX_QUADS = 32 * 1024;
pub const MAX_TEXTURES = 32;

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

        const colorLoc = try getAttributeLocation(programId, "vi_color");
        w.glEnableVertexAttribArray(colorLoc);
        w.glVertexAttribPointer(colorLoc, 4, w.GL_FLOAT, 0, entrySize, 0);
        w.glVertexAttribDivisor(colorLoc, 1);

        const bottomLeftSizeLoc = try getAttributeLocation(programId, "vi_bottomLeftSize");
        w.glEnableVertexAttribArray(bottomLeftSizeLoc);
        w.glVertexAttribPointer(bottomLeftSizeLoc, 4, w.GL_FLOAT, 0, entrySize, @bitOffsetOf(Entry, "bottomLeft") / 8);
        w.glVertexAttribDivisor(bottomLeftSizeLoc, 1);

        self.* = .{
            .programId = programId,
            .vao = vao,
            .instanceBuffer = instanceBuffer,
            .screenSizeLoc = try getUniformLocation(programId, "u_screenSize"),
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
