const builtin = @import("builtin");
const std = @import("std");
const root = @import("root");

pub const Platform = enum {
    ios,
    web,
};

pub const platform = getPlatform(builtin.target) orelse {
    @compileLog("Unsupported target {}", .{builtin.target});
    unreachable;
};

fn getPlatform(target: std.Target) ?Platform
{
    if (target.cpu.arch == .wasm32) {
        return .web;
    } else if (target.os.tag == .ios) {
        return .ios;
    } else {
        return null;
    }
}

pub const App = if (@hasDecl(root, "App")) root.App else @compileError("Missing App in root");
pub const MEMORY_FOOTPRINT = if (@hasDecl(root, "MEMORY_FOOTPRINT")) root.MEMORY_FOOTPRINT else @compileError("Missing MEMORY_FOOTPRINT in root");

comptime {
    if (@sizeOf(App) > MEMORY_FOOTPRINT) {
        @compileLog("MEMORY_FOOTPRINT ({}) not large enough for App ({})", .{
            @sizeOf(App), MEMORY_FOOTPRINT
        });
        unreachable;
    }

    if (!@hasField(App, "inputState")) {
        @compileLog("App type missing field inputState");
        unreachable;
    }
}
