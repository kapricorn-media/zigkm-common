const std = @import("std");
const builtin = @import("builtin");

const m = @import("zigkm-math");

const defs = @import("defs.zig");
const hooks = @import("hooks.zig");
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
    const memory = std.heap.page_allocator.alignedAlloc(u8, alignment, defs.MEMORY_FOOTPRINT) catch |err| {
        std.log.err("Failed to allocate WASM memory, error {}", .{err});
        return null;
    };
    @memset(memory, 0);

    const app = @as(*defs.App, @ptrCast(memory.ptr));
    const screenSize = m.Vec2usize.init(width, height);
    hooks.load(app, memory, screenSize, @floatCast(scale)) catch |err| {
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

    const app = castAppType(data);
    _ = app;
}

export fn onTouchEvents(data: MemoryPtrType, length: u32, touchEvents: [*]const ios.TouchEvent) void
{
    if (data == null) {
        return;
    }
    var app = castAppType(data);

    for (touchEvents[0..length]) |touchEvent| {
        app.inputState.addTouchEvent(.{
            .id = touchEvent.id,
            .pos = m.Vec2i.init(@intCast(touchEvent.x), @intCast(touchEvent.y)),
            .tapCount = touchEvent.tapCount,
            .phase = switch (touchEvent.phase) {
                ios.TOUCH_PHASE_UNKNOWN, ios.TOUCH_PHASE_UNSUPPORTED => {
                    std.log.err("bad touch phase", .{});
                    continue;
                },
                ios.TOUCH_PHASE_BEGIN => .Begin,
                ios.TOUCH_PHASE_STATIONARY => .Still,
                ios.TOUCH_PHASE_MOVE => .Move,
                ios.TOUCH_PHASE_END => .End,
                ios.TOUCH_PHASE_CANCEL => .Cancel,
                else => {
                    std.log.err("unknown touch phase", .{});
                    continue;
                },
            }
        });
    }
}

export fn onTextUtf32(data: MemoryPtrType, length: u32, utf32: [*]const u32) void
{
    if (data == null) {
        return;
    }
    var app = castAppType(data);
    for (utf32[0..length]) |codepoint| {
        app.inputState.keyboardState.utf32.append(codepoint) catch break;
    }
}

export fn onHttp(data: MemoryPtrType, code: c_uint, method: ios.HttpMethod, url: ios.Slice, responseBody: ios.Slice) void
{
    if (data == null) {
        return;
    }
    var app = castAppType(data);
    var tempBufferAllocator = app.memory.tempBufferAllocator();
    const tempAllocator = tempBufferAllocator.allocator();

    const methodZ = bindings.fromHttpMethod(method);
    const urlZ = bindings.fromCSlice(url);
    const responseBodyZ = bindings.fromCSlice(responseBody);
    app.onHttp(methodZ, code, urlZ, responseBodyZ, tempAllocator);
}

export fn updateAndRender(contextVoidPtr: ?*anyopaque, data: MemoryPtrType, width: u32, height: u32) c_int
{
    const context = @as(*bindings.Context, @ptrCast(contextVoidPtr orelse return 0));
    _ = context;

    if (data == null) {
        return 0;
    }
    const app = castAppType(data);
    const screenSize = m.Vec2usize.init(width, height);
    const timestampUs = std.time.microTimestamp();
    return @intFromBool(hooks.updateAndRender(app, screenSize, timestampUs));
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn
{
    _ = error_return_trace;
    _ = ret_addr;

    std.log.err("PANIC!", .{});
    std.log.err("{s}", .{msg});
    std.os.abort();

    // const stderr = std.io.getStdErr().writer();
    // if (stackTrace) |trace| {
    //     trace.format("", .{}, stderr) catch |err| {
    //         std.log.err("panic - failed to print stack trace: {}", .{err});
    //     };
    // }
    // std.builtin.default_panic(message, stackTrace, v);
}

pub const std_options = struct {
    pub const log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .info,
        .ReleaseFast => .info,
        .ReleaseSmall => .info,
    };
    pub const logFn = myLogFn;
};

fn myLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void
{
    // TODO risky? too much stack space?
    var logBuffer: [2048]u8 = undefined;
    const scopeStr = if (scope == .default) "[ ] " else "[" ++ @tagName(scope) ++ "] ";
    const fullFormat = "ZIG." ++ @tagName(level) ++ ": " ++ scopeStr ++ format;
    const str = std.fmt.bufPrintZ(&logBuffer, fullFormat, args) catch {
        bindings.log("ZIG.error: log overflow, failed to print");
        return;
    };
    bindings.log(str);
}
