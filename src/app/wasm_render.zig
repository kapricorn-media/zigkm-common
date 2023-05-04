const std = @import("std");

const m = @import("zigkm-common-math");

const w = @import("wasm_bindings.zig");

pub const MAX_QUADS = 1024;
pub const MAX_TEX_QUADS = 1024;

const RenderQueue = @import("render.zig").RenderQueue;

pub const RenderState = struct {
    quadState: QuadState,
    quadTextureState: QuadTextureState,

    const Self = @This();

    pub fn load(self: *Self) !void
    {
        try self.quadState.load();
        try self.quadTextureState.load();
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

    for (renderQueue.texQuads.slice()) |texQuad| {
        const quadTextureState = &renderState.quadTextureState;
        w.glUseProgram(quadTextureState.programId);

        w.glEnableVertexAttribArray(@intCast(c_uint, quadTextureState.positionAttrLoc));
        w.glBindBuffer(w.GL_ARRAY_BUFFER, quadTextureState.positionBuffer);
        w.glVertexAttribPointer(@intCast(c_uint, quadTextureState.positionAttrLoc), 2, w.GL_f32, 0, 0, 0);

        w.glUniform3fv(quadTextureState.posPixelsDepthUniLoc, texQuad.bottomLeft.x, texQuad.bottomLeft.y, texQuad.depth);
        w.glUniform2fv(quadTextureState.sizePixelsUniLoc, texQuad.size.x, texQuad.size.y);
        w.glUniform2fv(quadTextureState.screenSizeUniLoc, screenSize.x, screenSize.y);
        w.glUniform2fv(quadTextureState.offsetUvUniLoc, texQuad.uvBottomLeft.x, texQuad.uvBottomLeft.y);
        w.glUniform2fv(quadTextureState.scaleUvUniLoc, texQuad.uvSize.x, texQuad.uvSize.y);
        w.glUniform4fv(quadTextureState.colorUniLoc, texQuad.colors[0].x, texQuad.colors[0].y, texQuad.colors[0].z, texQuad.colors[0].w);
        w.glUniform1fv(quadTextureState.cornerRadiusUniLoc, texQuad.cornerRadius);

        w.glActiveTexture(w.GL_TEXTURE0);
        w.glBindTexture(w.GL_TEXTURE_2D, @intCast(c_uint, texQuad.textureData.texId));
        w.glUniform1i(quadTextureState.samplerUniLoc, 0);

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
};

const QuadTextureState = struct {
    positionBuffer: c_uint,

    programId: c_uint,

    positionAttrLoc: c_int,

    posPixelsDepthUniLoc: c_int,
    sizePixelsUniLoc: c_int,
    screenSizeUniLoc: c_int,
    offsetUvUniLoc: c_int,
    scaleUvUniLoc: c_int,
    samplerUniLoc: c_int,
    colorUniLoc: c_int,
    cornerRadiusUniLoc: c_int,

    const vert = @embedFile("shaders/wasm_quadtex.vert");
    const frag = @embedFile("shaders/wasm_quadtex.frag");

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
            .offsetUvUniLoc = try getUniformLocation(programId, "u_offsetUv"),
            .scaleUvUniLoc = try getUniformLocation(programId, "u_scaleUv"),
            .samplerUniLoc = try getUniformLocation(programId, "u_sampler"),
            .colorUniLoc = try getUniformLocation(programId, "u_color"),
            .cornerRadiusUniLoc = try getUniformLocation(programId, "u_cornerRadius"),
        };
    }
};