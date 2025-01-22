const std = @import("std");
const builtin = @import("builtin");
const A = std.mem.Allocator;

const platform = @import("zigkm-platform");

const exports = @import("exports.zig");
const android_c = @import("android_c.zig");
const ios_bindings = @import("ios_bindings.zig");
const wasm_bindings = @import("wasm_bindings.zig");

pub fn httpRequest(method: std.http.Method, url: []const u8, body: []const u8, a: A) void
{
    httpRequestHeader(method, url, "", "", body, a);
}

/// lmao...
pub fn httpRequestHeader(method: std.http.Method, url: []const u8, h1: []const u8, v1: []const u8, body: []const u8, a: A) void
{
    switch (platform.platform) {
        .android => {
            android_c.httpRequest(method, url, h1, v1, body, a);
        },
        .ios => {
            ios_bindings.httpRequest(exports._contextPtr, method, url, h1, v1, body);
        },
        .web => {
            wasm_bindings.httpRequestZ(method, url, h1, v1, body);
        },
        else => |p| {
            @compileLog("Unsupported platform", p);
        },
    }
}
