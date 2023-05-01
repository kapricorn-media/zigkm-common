const std = @import("std");

const m = @import("zigkm-common-math");

const w = @import("wasm_bindings.zig");

pub const MAX_QUADS = 1024;
pub const MAX_TEX_QUADS = 1024;

const RenderQueue = @import("render.zig").RenderQueue;

pub const RenderState = struct {
    quadState: QuadState,

    const Self = @This();

    pub fn load(self: *Self) !void
    {
        try self.quadState.load();
    }
};

pub fn render(
    renderQueue: *const RenderQueue,
    renderState: *const RenderState,
    screenSize: m.Vec2,
    allocator: std.mem.Allocator) void
{
    var tempArena = std.heap.ArenaAllocator.init(allocator);
    defer tempArena.deinit();
    const tempAllocator = tempArena.allocator();
    _ = tempAllocator;

    for (renderQueue.quads.slice()) |quad| {
        const quadState = &renderState.quadState;
        w.glUseProgram(quadState.programId);

        w.glEnableVertexAttribArray(@intCast(c_uint, quadState.positionAttrLoc));
        w.glBindBuffer(w.GL_ARRAY_BUFFER, quadState.positionBuffer);
        w.glVertexAttribPointer(@intCast(c_uint, quadState.positionAttrLoc), 2, w.GL_f32, 0, 0, 0);

        w.glUniform3fv(quadState.posPixelsDepthUniLoc, quad.bottomLeft.x, quad.bottomLeft.y, quad.depth);
        w.glUniform2fv(quadState.sizePixelsUniLoc, quad.size.x, quad.size.y);
        w.glUniform2fv(quadState.screenSizeUniLoc, screenSize.x, screenSize.y);
        w.glUniform4fv(quadState.colorBLUniLoc,
            quad.colors[0].x, quad.colors[0].y, quad.colors[0].z, quad.colors[0].w
        );
        w.glUniform4fv(quadState.colorBRUniLoc,
            quad.colors[1].x, quad.colors[1].y, quad.colors[1].z, quad.colors[1].w
        );
        w.glUniform4fv(quadState.colorTRUniLoc,
            quad.colors[2].x, quad.colors[2].y, quad.colors[2].z, quad.colors[2].w
        );
        w.glUniform4fv(quadState.colorTLUniLoc,
            quad.colors[3].x, quad.colors[3].y, quad.colors[3].z, quad.colors[3].w
        );
        w.glUniform1fv(quadState.cornerRadiusUniLoc, quad.cornerRadius);

        w.glDrawArrays(w.GL_TRIANGLES, 0, POS_UNIT_SQUARE.len);
    }
}

const POS_UNIT_SQUARE: [6]m.Vec2 align(4) = [6]m.Vec2 {
    m.Vec2.init(0.0, 0.0),
    m.Vec2.init(0.0, 1.0),
    m.Vec2.init(1.0, 1.0),
    m.Vec2.init(1.0, 1.0),
    m.Vec2.init(1.0, 0.0),
    m.Vec2.init(0.0, 0.0),
};

fn getAttributeLocation(programId: c_uint, attributeName: []const u8) !c_int
{
    const loc = w.glGetAttribLocation(programId, &attributeName[0], attributeName.len);
    return if (loc == -1) error.MissingAttributeLoc else loc;
}

fn getUniformLocation(programId: c_uint, uniformName: []const u8) !c_int
{
    const loc = w.glGetUniformLocation(programId, &uniformName[0], uniformName.len);
    return if (loc == -1) error.MissingUniformLoc else loc;
}

const QuadState = struct {
    positionBuffer: c_uint,

    programId: c_uint,

    positionAttrLoc: c_int,

    posPixelsDepthUniLoc: c_int,
    sizePixelsUniLoc: c_int,
    screenSizeUniLoc: c_int,
    colorTLUniLoc: c_int,
    colorTRUniLoc: c_int,
    colorBLUniLoc: c_int,
    colorBRUniLoc: c_int,
    cornerRadiusUniLoc: c_int,

    const vert = @embedFile("shaders/wasm_quad.vert");
    const frag = @embedFile("shaders/wasm_quad.frag");

    const Self = @This();

    pub fn load(self: *Self) !void
    {
        // TODO error check all these
        const vertQuadId = w.compileShader(&vert[0], vert.len, w.GL_VERTEX_SHADER);
        const fragQuadId = w.compileShader(&frag[0], frag.len, w.GL_FRAGMENT_SHADER);

        const positionBuffer = w.glCreateBuffer();
        w.glBindBuffer(w.GL_ARRAY_BUFFER, positionBuffer);
        w.glBufferData(w.GL_ARRAY_BUFFER, &POS_UNIT_SQUARE[0].x, POS_UNIT_SQUARE.len * 2, w.GL_STATIC_DRAW);

        const programId = w.linkShaderProgram(vertQuadId, fragQuadId);

        self.* = .{
            .positionBuffer = positionBuffer,

            .programId = programId,

            .positionAttrLoc = try getAttributeLocation(programId, "a_position"),

            .posPixelsDepthUniLoc = try getUniformLocation(programId, "u_posPixelsDepth"),
            .sizePixelsUniLoc = try getUniformLocation(programId, "u_sizePixels"),
            .screenSizeUniLoc = try getUniformLocation(programId, "u_screenSize"),
            .colorTLUniLoc = try getUniformLocation(programId, "u_colorTL"),
            .colorTRUniLoc = try getUniformLocation(programId, "u_colorTR"),
            .colorBLUniLoc = try getUniformLocation(programId, "u_colorBL"),
            .colorBRUniLoc = try getUniformLocation(programId, "u_colorBR"),
            .cornerRadiusUniLoc = try getUniformLocation(programId, "u_cornerRadius"),
        };
    }

    pub fn drawQuadGradient(
        self: Self,
        posPixels: m.Vec2,
        scalePixels: m.Vec2,
        depth: f32,
        cornerRadius: f32,
        colorTL: m.Vec4,
        colorTR: m.Vec4,
        colorBL: m.Vec4,
        colorBR: m.Vec4,
        screenSize: m.Vec2) void
    {
        w.glUseProgram(self.programId);

        w.glEnableVertexAttribArray(@intCast(c_uint, self.positionAttrLoc));
        w.glBindBuffer(w.GL_ARRAY_BUFFER, self.positionBuffer);
        w.glVertexAttribPointer(@intCast(c_uint, self.positionAttrLoc), 2, w.GL_f32, 0, 0, 0);

        w.glUniform3fv(self.posPixelsDepthUniLoc, posPixels.x, posPixels.y, depth);
        w.glUniform2fv(self.sizePixelsUniLoc, scalePixels.x, scalePixels.y);
        w.glUniform2fv(self.screenSizeUniLoc, screenSize.x, screenSize.y);
        w.glUniform4fv(self.colorTLUniLoc, colorTL.x, colorTL.y, colorTL.z, colorTL.w);
        w.glUniform4fv(self.colorTRUniLoc, colorTR.x, colorTR.y, colorTR.z, colorTR.w);
        w.glUniform4fv(self.colorBLUniLoc, colorBL.x, colorBL.y, colorBL.z, colorBL.w);
        w.glUniform4fv(self.colorBRUniLoc, colorBR.x, colorBR.y, colorBR.z, colorBR.w);
        w.glUniform1fv(self.cornerRadiusUniLoc, cornerRadius);

        w.glDrawArrays(w.GL_TRIANGLES, 0, POS_UNIT_SQUARE.len);
    }

    pub fn drawQuad(
        self: Self,
        posPixels: m.Vec2,
        scalePixels: m.Vec2,
        depth: f32,
        cornerRadius: f32,
        color: m.Vec4,
        screenSize: m.Vec2) void
    {
        self.drawQuadGradient(posPixels, scalePixels, depth, cornerRadius, color, color, color, color, screenSize);
    }
};
