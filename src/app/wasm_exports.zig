const std = @import("std");
const builtin = @import("builtin");

const m = @import("zigkm-math");

const asset_data = @import("asset_data.zig");
const defs = @import("defs.zig");
const hooks = @import("hooks.zig");
const input = @import("input.zig");

const wasm_bindings = @import("wasm_bindings.zig");

const MemoryPtrType = ?*anyopaque;

fn castAppType(memory: MemoryPtrType) *defs.App
{
    return @ptrCast(@alignCast(memory));
}

pub const std_options = struct {
    pub const log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .info,
        .ReleaseFast => .info,
        .ReleaseSmall => .info,
    };
    pub const logFn = wasmLog;
};

pub fn wasmLog(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype) void
{
    _ = scope;

    var buf: [4096]u8 = undefined;
    const message = std.fmt.bufPrint(&buf, format, args) catch {
        const errMsg = "bufPrint failed for format: " ++ format;
        wasm_bindings.consoleMessage(true, &errMsg[0], errMsg.len);
        return;
    };

    const isError = switch (message_level) {
        .err, .warn => true, 
        .info, .debug => false,
    };
    wasm_bindings.consoleMessage(isError, &message[0], message.len);
}

fn buttonToClickType(button: c_int) input.ClickType
{
    return switch (button) {
        0 => input.ClickType.Left,
        1 => input.ClickType.Middle,
        2 => input.ClickType.Right,
        else => input.ClickType.Other,
    };
}

// App exports

export fn onInit(width: c_uint, height: c_uint) MemoryPtrType
{
    wasm_bindings.glClearColor(0.0, 0.0, 0.0, 0.0);
    wasm_bindings.glEnable(wasm_bindings.GL_DEPTH_TEST);
    wasm_bindings.glDepthFunc(wasm_bindings.GL_LEQUAL);

    wasm_bindings.glEnable(wasm_bindings.GL_BLEND);
    wasm_bindings.glBlendFuncSeparate(
        wasm_bindings.GL_SRC_ALPHA, wasm_bindings.GL_ONE_MINUS_SRC_ALPHA,
        wasm_bindings.GL_ONE, wasm_bindings.GL_ONE
    );

    const alignment = 8;
    const memory = std.heap.page_allocator.alignedAlloc(u8, alignment, defs.MEMORY_FOOTPRINT) catch |err| {
        std.log.err("Failed to allocate WASM memory, error {}", .{err});
        return null;
    };
    @memset(memory, 0);

    const app = @as(*defs.App, @ptrCast(memory.ptr));
    const screenSize = m.Vec2usize.init(width, height);
    const scale = 1.0;
    hooks.load(app, memory, screenSize, scale) catch |err| {
        std.log.err("app load failed, err {}", .{err});
        return null;
    };

    return @ptrCast(memory.ptr);
}

export fn onAnimationFrame(memory: MemoryPtrType, width: c_uint, height: c_uint, scrollY: c_int, timestampUs: c_int) c_int
{
    wasm_bindings.bindNullFramebuffer();
    wasm_bindings.glClear(wasm_bindings.GL_COLOR_BUFFER_BIT | wasm_bindings.GL_DEPTH_BUFFER_BIT);

    const app = castAppType(memory);
    const screenSize = m.Vec2usize.init(width, height);
    return hooks.updateAndRender(app, screenSize, @intCast(timestampUs), scrollY);
}

export fn onMouseMove(memory: MemoryPtrType, x: c_int, y: c_int) void
{
    var app = castAppType(memory);
    app.inputState.mouseState.pos = m.Vec2i.init(x, y);
}

export fn onMouseDown(memory: MemoryPtrType, button: c_int, x: c_int, y: c_int) void
{
    var app = castAppType(memory);
    app.inputState.addClickEvent(.{
        .pos = m.Vec2i.init(x, y),
        .clickType = buttonToClickType(button),
        .down = true,
    });
}

export fn onMouseUp(memory: MemoryPtrType, button: c_int, x: c_int, y: c_int) void
{
    var app = castAppType(memory);
    app.inputState.addClickEvent(.{
        .pos = m.Vec2i.init(x, y),
        .clickType = buttonToClickType(button),
        .down = false,
    });
}

export fn onMouseWheel(memory: MemoryPtrType, deltaX: c_int, deltaY: c_int) void
{
    var app = castAppType(memory);
    app.inputState.addWheelDelta(m.Vec2i.init(deltaX, deltaY));
}

export fn onKeyDown(memory: MemoryPtrType, keyCode: c_int, keyUtf32: c_uint) void
{
    var app = castAppType(memory);
    app.inputState.addKeyEvent(.{
        .keyCode = keyCode,
        .down = true,
    });
    if (keyUtf32 != 0) {
        const utf32 = [1]u32 {keyUtf32};
        app.inputState.addUtf32(&utf32);
    } else {
        switch (keyCode) {
            8, 9, 10, 13 => {
                const utf32 = [1]u32 {@intCast(keyCode)};
                app.inputState.addUtf32(&utf32);
            },
            else => {},
        }
    }
}

export fn onTouchStart(memory: MemoryPtrType, id: c_int, x: c_int, y: c_int, force: f32, radiusX: c_int, radiusY: c_int) void
{
    _ = force;
    _ = radiusX; _ = radiusY;

    var app = castAppType(memory);
    app.inputState.addTouchEvent(.{
        .id = @intCast(id),
        .pos = m.Vec2i.init(x, y),
        .tapCount = 1,
        .phase = .Begin,
    });
}

export fn onTouchMove(memory: MemoryPtrType, id: c_int, x: c_int, y: c_int, force: f32, radiusX: c_int, radiusY: c_int) void
{
    _ = force;
    _ = radiusX; _ = radiusY;

    var app = castAppType(memory);
    app.inputState.addTouchEvent(.{
        .id = @intCast(id),
        .pos = m.Vec2i.init(x, y),
        .tapCount = 1,
        .phase = .Move,
    });
}

export fn onTouchEnd(memory: MemoryPtrType, id: c_int, x: c_int, y: c_int, force: f32, radiusX: c_int, radiusY: c_int) void
{
    _ = force;
    _ = radiusX; _ = radiusY;

    var app = castAppType(memory);
    app.inputState.addTouchEvent(.{
        .id = @intCast(id),
        .pos = m.Vec2i.init(x, y),
        .tapCount = 1,
        .phase = .End,
    });
}

export fn onTouchCancel(memory: MemoryPtrType, id: c_int, x: c_int, y: c_int, force: f32, radiusX: c_int, radiusY: c_int) void
{
    _ = force;
    _ = radiusX; _ = radiusY;

    var app = castAppType(memory);
    app.inputState.addTouchEvent(.{
        .id = @intCast(id),
        .pos = m.Vec2i.init(x, y),
        .tapCount = 1,
        .phase = .Cancel,
    });
}

export fn onPopState(memory: MemoryPtrType, width: c_uint, height: c_uint) void
{
    var app = castAppType(memory);
    const screenSize = m.Vec2usize.init(width, height);
    app.onPopState(screenSize);
}

export fn onDeviceOrientation(memory: MemoryPtrType, alpha: f32, beta: f32, gamma: f32) void
{
    var app = castAppType(memory);
    app.inputState.deviceState.angles.x = alpha;
    app.inputState.deviceState.angles.y = beta;
    app.inputState.deviceState.angles.z = gamma;
}

export fn onHttp(memory: MemoryPtrType, method: c_uint, code: c_uint, uriLen: c_uint, dataLen: c_int) void
{
    var app = castAppType(memory);
    var tempBufferAllocator = app.memory.tempBufferAllocator();
    const tempAllocator = tempBufferAllocator.allocator();

    const methodZ = wasm_bindings.intToHttpMethod(method);

    var uri = tempAllocator.alloc(u8, uriLen) catch {
        std.log.err("Failed to allocate uri", .{});
        return;
    };
    if (wasm_bindings.fillDataBuffer(&uri[0], uri.len) != 1) {
        std.log.err("fillDataBuffer failed for uri", .{});
        return;
    }

    const data = tempAllocator.alloc(u8, @intCast(dataLen)) catch {
        std.log.err("Failed to allocate data", .{});
        return;
    };
    if (wasm_bindings.fillDataBuffer(data.ptr, data.len) != 1) {
        std.log.err("fillDataBuffer failed for data", .{});
        return;
    }

    app.onHttp(methodZ, code, uri, data, tempAllocator);
}

export fn onLoadedFont(memory: MemoryPtrType, id: c_uint, fontDataLen: c_uint) void
{
    var app = castAppType(memory);
    var tempBufferAllocator = app.memory.tempBufferAllocator();
    const tempAllocator = tempBufferAllocator.allocator();

    const alignment = @alignOf(asset_data.FontLoadData);
    var fontDataBuf = tempAllocator.allocWithOptions(u8, fontDataLen, alignment, null) catch {
        std.log.err("Failed to allocate fontDataBuf", .{});
        return;
    };
    if (wasm_bindings.fillDataBuffer(&fontDataBuf[0], fontDataBuf.len) != 1) {
        std.log.err("fillDataBuffer failed", .{});
        return;
    }
    if (fontDataBuf.len != @sizeOf(asset_data.FontLoadData)) {
        std.log.err("FontLoadData size mismatch", .{});
        return;
    }
    const fontData = @as(*const asset_data.FontLoadData, @ptrCast(fontDataBuf.ptr));

    app.assets.onLoadedFont(id, &.{.fontData = fontData}, tempAllocator);
}

export fn onLoadedTexture(memory: MemoryPtrType, id: c_uint, texId: c_uint, width: c_uint, height: c_uint, canvasWidth: c_uint, canvasHeight: c_uint, topLeftX: c_int, topLeftY: c_int) void
{
    var app = castAppType(memory);
    const size = m.Vec2usize.init(width, height);
    const canvasSize = m.Vec2usize.init(canvasWidth, canvasHeight);
    const topLeft = m.Vec2i.init(topLeftX, topLeftY);

    app.assets.onLoadedTexture(id, &.{.texId = texId, .size = size, .canvasSize = canvasSize, .topLeft = topLeft});
}

// non-App exports

fn loadFontDataInternal(atlasSize: c_int, fontDataLen: c_uint, fontSize: f32, scale: f32) !void
{
    std.log.info("loadFontData atlasSize={} fontSize={} scale={}", .{atlasSize, fontSize, scale});

    var arenaAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arenaAllocator.allocator();

    var fontDataBuf = try allocator.alloc(u8, fontDataLen);
    if (wasm_bindings.fillDataBuffer(&fontDataBuf[0], fontDataBuf.len) != 1) {
        return error.FillDataBuffer;
    }

    var fontData = try allocator.create(asset_data.FontLoadData);
    const pixelBytes = try fontData.load(@intCast(atlasSize), fontDataBuf, fontSize, scale, allocator);

    if (wasm_bindings.addReturnValueBuf(&pixelBytes[0], pixelBytes.len) != 1) {
        return error.AddReturnValue;
    }
    const fontDataBytes = std.mem.asBytes(fontData);
    if (wasm_bindings.addReturnValueBuf(&fontDataBytes[0], fontDataBytes.len) != 1) {
        return error.AddReturnValue;
    }
}

// Returns 1 on success, 0 on failure
export fn loadFontData(atlasSize: c_int, fontDataLen: c_uint, fontSize: f32, scale: f32) c_int
{
    loadFontDataInternal(atlasSize, fontDataLen, fontSize, scale) catch |err| {
        std.log.err("loadFontData failed err={}", .{err});
        return 0;
    };
    return 1;
}
