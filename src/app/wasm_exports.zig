const std = @import("std");

const m = @import("zigkm-common-math");

const defs = @import("defs.zig");
const input = @import("input.zig");

const wasm_bindings = @import("wasm_bindings.zig");

const MemoryPtrType = ?*anyopaque;

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype) void
{
    _ = scope;

    var buf: [2048]u8 = undefined;
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

fn castAppType(memory: MemoryPtrType) *defs.App
{
    return @ptrCast(*defs.App, @alignCast(@alignOf(defs.App), memory));
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

export fn onInit(width: c_uint, height: c_uint) MemoryPtrType
{
    const alignment = 8;
    var memory = std.heap.page_allocator.alignedAlloc(u8, alignment, defs.MEMORY_FOOTPRINT) catch |err| {
        std.log.err("Failed to allocate WASM memory, error {}", .{err});
        return null;
    };
    std.mem.set(u8, memory, 0);

    var app = @ptrCast(*defs.App, memory.ptr);
    const screenSize = m.Vec2usize.init(width, height);
    const scale = 1.0;
    app.load(memory, screenSize, scale) catch |err| {
        std.log.err("app load failed, err {}", .{err});
        return null;
    };

    return @ptrCast(MemoryPtrType, memory.ptr);
}

export fn onAnimationFrame(memory: MemoryPtrType, width: c_uint, height: c_uint, scrollY: c_int, timestampMs: c_int) c_uint
{
    var app = castAppType(memory);
    const screenSize = m.Vec2usize.init(width, height);
    const shouldDraw = app.updateAndRender(screenSize, @intCast(i32, scrollY), @intCast(u64, timestampMs));
    return @boolToInt(shouldDraw);
}

export fn onMouseMove(memory: MemoryPtrType, x: c_int, y: c_int) void
{
    var app = castAppType(memory);
    app.inputState.mouseState.pos = m.Vec2i.init(x, y);
}

export fn onMouseDown(memory: MemoryPtrType, button: c_int, x: c_int, y: c_int) void
{
    var app = castAppType(memory);
    app.inputState.mouseState.addClickEvent(m.Vec2i.init(x, y), buttonToClickType(button), true);
}

export fn onMouseUp(memory: MemoryPtrType, button: c_int, x: c_int, y: c_int) void
{
    var app = castAppType(memory);
    app.inputState.mouseState.addClickEvent(m.Vec2i.init(x, y), buttonToClickType(button), false);
}

export fn onKeyDown(memory: MemoryPtrType, keyCode: c_int) void
{
    var app = castAppType(memory);
    app.inputState.keyboardState.addKeyEvent(keyCode, true);
}

export fn onDeviceOrientation(memory: MemoryPtrType, alpha: f32, beta: f32, gamma: f32) void
{
    var app = castAppType(memory);
    app.inputState.deviceState.angles.x = alpha;
    app.inputState.deviceState.angles.y = beta;
    app.inputState.deviceState.angles.z = gamma;
}

export fn onTextureLoaded(memory: MemoryPtrType, id: c_uint, texId: c_uint, width: c_uint, height: c_uint) void
{
    var app = castAppType(memory);
    const size = m.Vec2usize.init(width, height);
    std.log.info("onTextureLoaded id={} texId={} size={}", .{id, texId, size});

    app.assets.onLoadedTexture(id, texId, size);
}

export fn onFontLoaded(memory: MemoryPtrType, atlasTextureId: c_uint, fontDataLen: c_uint) void
{
    _ = memory;
    _ = atlasTextureId;
    _ = fontDataLen;
    // var transientAllocator = memory.getTransientAllocator();
    // const allocator = transientAllocator.allocator();

    // _ = allocator;
    // _ = atlasTextureId;
    // _ = fontDataLen;

    // const alignment = @alignOf(wasm_asset.FontLoadData);
    // var fontDataBuf = allocator.allocWithOptions(u8, fontDataLen, alignment, null) catch {
    //     std.log.err("Failed to allocate fontDataBuf", .{});
    //     return;
    // };
    // if (wasm_bindings.fillDataBuffer(&fontDataBuf[0], fontDataBuf.len) != 1) {
    //     std.log.err("fillDataBuffer failed", .{});
    //     return;
    // }
    // if (fontDataBuf.len != @sizeOf(wasm_asset.FontLoadData)) {
    //     std.log.err("FontLoadData size mismatch", .{});
    //     return;
    // }
    // const fontData = @ptrCast(*wasm_asset.FontLoadData, fontDataBuf.ptr);

    // var state = memory.castPersistent(AppType);
    // state.assets.onFontLoaded(atlasTextureId, fontData) catch |err| {
    //     std.log.err("onFontLoaded error {}", .{err});
    // };
}
