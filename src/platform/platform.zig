const builtin = @import("builtin");
const std = @import("std");

pub const net = @import("net.zig");

pub const SESSION_ID_COOKIE = "zigkm_sessionid";

pub const Platform = enum {
    ios,
    web,
    other,
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
        return .other;
    }
}
