const std = @import("std");

const m = @import("zigkm-math");

const defs = @import("defs.zig");
const memory = @import("memory.zig");

// TODO there could be a wrapper class for defs.App defined here, maybe...

pub fn load(app: *defs.App, buf: []u8, screenSize: m.Vec2usize, scale: f32) !void
{
    std.log.info("app load ({}x{}, {}) ({} MB)", .{screenSize.x, screenSize.y, scale, buf.len / 1024 / 1024});

    // Default-initialize all custom user fields
    app.* = .{
        .memory = undefined,
        .inputState = undefined,
        .renderState = undefined,
        .assets = undefined,
    };

    app.memory = memory.Memory.init(buf, defs.MEMORY_PERMANENT, @sizeOf(defs.App));
    app.inputState.clear();
    try app.renderState.load();
    const permanentAllocator = app.memory.permanentAllocator();
    try app.assets.load(permanentAllocator);

    try app.load(screenSize, scale);
}

pub fn updateAndRender(app: *defs.App, screenSize: m.Vec2usize, timestampUs: i64) bool
{
    app.inputState.updateStart();
    defer app.inputState.updateEnd();

    const maxInflight = 8;
    app.assets.loadQueued(maxInflight);

    return app.updateAndRender(screenSize, timestampUs);
}

// TODO hooks for everything else? input stuff, assets, network, idk...
