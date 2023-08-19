const builtin = @import("builtin");
const std = @import("std");

const m = @import("zigkm-math");

const defs = @import("defs.zig");
const bindings = @import("ios_bindings.zig");
const ios = bindings.ios;

pub var _contextPtr: *bindings.Context = undefined;

const MemoryPtrType = ?*anyopaque;

fn castAppType(memory: MemoryPtrType) *defs.App
{
    return @ptrCast(@alignCast(memory));
}

export fn onStart(contextVoidPtr: ?*anyopaque, width: u32, height: u32, scale: f64) ?*anyopaque
{
    const context = @as(*bindings.Context, @ptrCast(contextVoidPtr orelse return null));
    _contextPtr = context;

    const alignment = 8;
    var memory = std.heap.page_allocator.alignedAlloc(u8, alignment, defs.MEMORY_FOOTPRINT) catch |err| {
        std.log.err("Failed to allocate WASM memory, error {}", .{err});
        return null;
    };
    @memset(memory, 0);

    var app = @as(*defs.App, @ptrCast(memory.ptr));
    // TODO create App wrapper to share these common setups between platforms
    // auto-init memory, inputState, renderState, assets, etc if they are defined in App.
    app.inputState.clear();
    const screenSize = m.Vec2usize.init(width, height);
    app.load(memory, screenSize, @floatCast(scale)) catch |err| {
        std.log.err("app load failed, err {}", .{err});
        return null;
    };

    return @ptrCast(memory.ptr);
}

export fn onExit(contextVoidPtr: ?*anyopaque, data: MemoryPtrType) void
{
    std.log.info("onExit", .{});

    const context = @as(*bindings.Context, @ptrCast(contextVoidPtr orelse return));
    _ = context;

    var app = castAppType(data);
    _ = app;
}

export fn onTouchEvents(data: MemoryPtrType, length: u32, touchEvents: [*]const ios.TouchEvent) void
{
    var app = castAppType(data);
    var touchState = &app.inputState.touchState;

    for (touchEvents[0..length]) |touchEvent| {
        if (touchState.numTouchEvents >= touchState.touchEvents.len) {
            std.debug.panic("full touch events", .{});
        }

        const t = &touchState.touchEvents[touchState.numTouchEvents];
        // touchState.touchEvents[touchState.numTouchEvents] = touchEvent;
        t.id = touchEvent.id;
        t.pos = m.Vec2i {
            .x = @intCast(touchEvent.x),
            .y = @intCast(touchEvent.y),
        };
        t.tapCount = touchEvent.tapCount;
        switch (touchEvent.phase) {
            ios.TOUCH_PHASE_UNKNOWN, ios.TOUCH_PHASE_UNSUPPORTED => {
                std.debug.panic("bad touch phase", .{});
            },
            ios.TOUCH_PHASE_BEGIN => {
                t.phase = .Begin;
            },
            ios.TOUCH_PHASE_STATIONARY => {
                t.phase = .Still;
            },
            ios.TOUCH_PHASE_MOVE => {
                t.phase = .Move;
            },
            ios.TOUCH_PHASE_END => {
                t.phase = .End;
            },
            ios.TOUCH_PHASE_CANCEL => {
                t.phase = .Cancel;
            },
            else => {
                std.debug.panic("unknown touch phase", .{});
            },
        }
        touchState.numTouchEvents += 1;
    }
}

export fn onTextUtf32(data: MemoryPtrType, length: u32, utf32: [*]const u32) void
{
    var app = castAppType(data);
    var keyboardState = &app.inputState.keyboardState;

    const slice = utf32[0..length];
    for (slice) |codepoint| {
        if (keyboardState.numUtf32 >= keyboardState.utf32.len) {
            break;
        }

        keyboardState.utf32[keyboardState.numUtf32] = codepoint;
        keyboardState.numUtf32 += 1;
    }
}

export fn updateAndRender(contextVoidPtr: ?*anyopaque, data: MemoryPtrType, width: u32, height: u32) c_int
{
    const context = @as(*bindings.Context, @ptrCast(contextVoidPtr orelse return 0));
    _ = context;

    var app = castAppType(data);
    app.inputState.updateStart();
    defer app.inputState.updateEnd();

    const screenSize = m.Vec2usize.init(width, height);
    const scrollY = 0;
    const timestampMs = 0;
    const h = app.updateAndRender(screenSize, scrollY, timestampMs);

    // TODO not quite right. This returns the height, but iOS only cares about draw/nodraw.
    return h;
}

// pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn
// {
//     _ = msg;
//     _ = error_return_trace;
//     _ = ret_addr;

//     // std.log.err("panic - {s}", .{message});
//     // const stderr = std.io.getStdErr().writer();
//     // if (stackTrace) |trace| {
//     //     trace.format("", .{}, stderr) catch |err| {
//     //         std.log.err("panic - failed to print stack trace: {}", .{err});
//     //     };
//     // }
//     // std.builtin.default_panic(message, stackTrace, v);
//     std.os.abort();
// }

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void
{
    // TODO risky? too much stack space?
    var logBuffer: [1024]u8 = undefined;
    const scopeStr = if (scope == .default) "[ ] " else "[" ++ @tagName(scope) ++ "] ";
    const fullFormat = "ZIG." ++ @tagName(level) ++ ": " ++ scopeStr ++ format;
    const str = std.fmt.bufPrintZ(&logBuffer, fullFormat, args) catch {
        bindings.log("ZIG.error: log overflow, failed to print");
        return;
    };
    bindings.log(str);
}

pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .info,
    .ReleaseFast => .err,
    .ReleaseSmall => .err,
};
