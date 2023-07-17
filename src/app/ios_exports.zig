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
    return @ptrCast(*defs.App, @alignCast(@alignOf(defs.App), memory));
}

export fn onStart(contextVoidPtr: ?*anyopaque, width: u32, height: u32, scale: f64) ?*anyopaque
{
    const context = @ptrCast(*bindings.Context, contextVoidPtr orelse return null);
    _contextPtr = context;

    const alignment = 8;
    var memory = std.heap.page_allocator.alignedAlloc(u8, alignment, defs.MEMORY_FOOTPRINT) catch |err| {
        std.log.err("Failed to allocate WASM memory, error {}", .{err});
        return null;
    };
    std.mem.set(u8, memory, 0);

    var app = @ptrCast(*defs.App, memory.ptr);
    const screenSize = m.Vec2usize.init(width, height);
    app.load(memory, screenSize, @floatCast(f32, scale)) catch |err| {
        std.log.err("app load failed, err {}", .{err});
        return null;
    };

    return @ptrCast(MemoryPtrType, memory.ptr);
}

export fn onExit(contextVoidPtr: ?*anyopaque, data: MemoryPtrType) void
{
    std.log.info("onExit", .{});

    const context = @ptrCast(*bindings.Context, contextVoidPtr orelse return);
    _ = context;

    // var appData = @ptrCast(*AppData, @alignCast(@alignOf(*AppData), data orelse return));
    // _ = appData;
    _ = data;
}

export fn onTouchEvents(
    data: ?*anyopaque,
    length: u32,
    touchEvents: [*]const ios.TouchEvent) void
{
    _ = data;
    _ = length;
    _ = touchEvents;
    // var appData = @ptrCast(*AppData, @alignCast(@alignOf(*AppData), data orelse return));
    // var appInput = &appData.input;

    // const slice = touchEvents[0..length];
    // for (slice) |touchEvent| {
    //     if (appInput.numTouchEvents >= appInput.touchEvents.len) {
    //         std.debug.panic("full touch events", .{});
    //     }

    //     const t = &appInput.touchEvents[appInput.numTouchEvents];
    //     // appInput.touchEvents[appInput.numTouchEvents] = touchEvent;
    //     t.id = touchEvent.id;
    //     t.pos = m.Vec2i {
    //         .x = @intCast(i32, touchEvent.x),
    //         .y = @intCast(i32, touchEvent.y),
    //     };
    //     t.tapCount = touchEvent.tapCount;
    //     switch (touchEvent.phase) {
    //         ios.TOUCH_PHASE_UNKNOWN, ios.TOUCH_PHASE_UNSUPPORTED => {
    //             std.debug.panic("bad touch phase", .{});
    //         },
    //         ios.TOUCH_PHASE_BEGIN => {
    //             t.phase = .Begin;
    //         },
    //         ios.TOUCH_PHASE_STATIONARY => {
    //             t.phase = .Still;
    //         },
    //         ios.TOUCH_PHASE_MOVE => {
    //             t.phase = .Move;
    //         },
    //         ios.TOUCH_PHASE_END => {
    //             t.phase = .End;
    //         },
    //         ios.TOUCH_PHASE_CANCEL => {
    //             t.phase = .Cancel;
    //         },
    //         else => {
    //             std.debug.panic("unknown touch phase", .{});
    //         },
    //     }
    //     appInput.numTouchEvents += 1;
    // }
}

export fn onTextUtf32(
    data: ?*anyopaque,
    length: u32,
    utf32: [*]const u32) void
{
    _ = data;
    _ = length;
    _ = utf32;
    // var appData = @ptrCast(*AppData, @alignCast(@alignOf(*AppData), data orelse return));
    // var appInput = &appData.input;

    // const slice = utf32[0..length];
    // for (slice) |codepoint| {
    //     if (appInput.numUtf32 >= appInput.utf32.len) {
    //         break;
    //     }

    //     appInput.utf32[appInput.numUtf32] = codepoint;
    //     appInput.numUtf32 += 1;
    // }
}

export fn updateAndRender(contextVoidPtr: ?*anyopaque, data: MemoryPtrType, width: u32, height: u32) c_int
{
    const context = @ptrCast(*bindings.Context, contextVoidPtr orelse return 0);
    _ = context;

    var app = castAppType(data);

    const screenSize = m.Vec2usize.init(width, height);
    const scrollY = 0;
    const timestampMs = 0;
    _ = app.updateAndRender(screenSize, scrollY, timestampMs);

    return 1;
}

pub fn panic(message: []const u8, stackTrace: ?*std.builtin.StackTrace, v: ?usize) noreturn
{
    std.log.err("panic - {s}", .{message});
    const stderr = std.io.getStdErr().writer();
    if (stackTrace) |trace| {
        trace.format("", .{}, stderr) catch |err| {
            std.log.err("panic - failed to print stack trace: {}", .{err});
        };
    }
    std.builtin.default_panic(message, stackTrace, v);
}

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
