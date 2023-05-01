const builtin = @import("builtin");
const std = @import("std");

const defs = @import("defs.zig");

const exports = switch (defs.platform) {
    .web => @import("wasm_exports.zig"),
    else => unreachable,
};

pub usingnamespace exports;

// for stb library link

// export fn stb_zig_malloc(size: usize, userData: ?*anyopaque) ?*anyopaque
// {
//     const alignment = 8; // does malloc always align to 4 or 8 bytes? I didn't know this...
//     var allocator = @ptrCast(*std.mem.Allocator, @alignCast(@alignOf(*std.mem.Allocator), userData));
//     const result = allocator.alignedAlloc(u8, alignment, size) catch |err| {
//         std.log.err("stb_zig_malloc failed with err={} for size={}", .{err, size});
//         return null;
//     };
//     return &result[0];
// }

// export fn stb_zig_free(ptr: ?*anyopaque, userData: ?*anyopaque) void
// {
//     _ = ptr; _ = userData;
//     // no free, yolo!
// }

// export fn stb_zig_assert(expression: c_int) void
// {
//     std.debug.assert(expression != 0);
// }

// export fn stb_zig_strlen(str: [*c]const i8) usize
// {
//     return std.mem.len(str);
// }

// export fn stb_zig_memcpy(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque
// {
//     if (dest) |d| {
//         if (src) |s| {
//             const dSlice = (@ptrCast([*]u8, d))[0..n];
//             const sSlice = (@ptrCast([*]const u8, s))[0..n];
//             std.mem.copy(u8, dSlice, sSlice);
//         }
//     }
//     return dest;
// }

// export fn stb_zig_memset(str: ?*anyopaque, c: c_int, n: usize) ?*anyopaque
// {
//     if (str) |s| {
//         const sSlice = (@ptrCast([*]u8, s))[0..n];
//         std.mem.set(u8, sSlice, @intCast(u8, c));
//     }
//     return str;
// }

