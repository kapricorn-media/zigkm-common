const std = @import("std");

// stb dependencies

fn allocatorCast(ptr: ?*anyopaque) *std.mem.Allocator
{
    return @ptrCast(*std.mem.Allocator, @alignCast(@alignOf(*std.mem.Allocator), ptr));
}

export fn stb_zig_assert(expression: c_int) void
{
    std.debug.assert(expression != 0);
}

export fn stb_zig_strlen(str: [*c]const i8) usize
{
    return std.mem.len(str);
}

export fn stb_zig_memcpy(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque
{
    if (dest) |d| {
        if (src) |s| {
            const dSlice = (@ptrCast([*]u8, d))[0..n];
            const sSlice = (@ptrCast([*]const u8, s))[0..n];
            std.mem.copy(u8, dSlice, sSlice);
        }
    }
    return dest;
}

export fn stb_zig_memset(str: ?*anyopaque, c: c_int, n: usize) ?*anyopaque
{
    if (str) |s| {
        const sSlice = (@ptrCast([*]u8, s))[0..n];
        std.mem.set(u8, sSlice, @intCast(u8, c));
    }
    return str;
}

export fn stb_zig_ifloor(x: f64) c_int
{
    return @floatToInt(c_int, std.math.floor(x));
}

export fn stb_zig_iceil(x: f64) c_int
{
    return @floatToInt(c_int, std.math.ceil(x));
}

export fn stb_zig_sqrt(x: f64) f64
{
    return std.math.sqrt(x);
}

export fn stb_zig_pow(x: f64, y: f64) f64
{
    return std.math.pow(f64, x, y);
}

export fn stb_zig_fmod(x: f64, y: f64) f64
{
    return @mod(x, y);
}

export fn stb_zig_cos(x: f64) f64
{
    return std.math.cos(x);
}

export fn stb_zig_acos(x: f64) f64
{
    return std.math.acos(x);
}

export fn stb_zig_fabs(x: f64) f64
{
    return std.math.fabs(x);
}

export fn stb_zig_malloc(size: usize, userData: ?*anyopaque) ?*anyopaque
{
    const alignment = 8; // does malloc always align to 4 or 8 bytes? I didn't know this...
    var allocator = allocatorCast(userData);
    const result = allocator.alignedAlloc(u8, alignment, size) catch |err| {
        std.log.err("stb_zig_malloc failed with err={} for size={}", .{err, size});
        return null;
    };
    return &result[0];
}

export fn stb_zig_free(ptr: ?*anyopaque, userData: ?*anyopaque) void
{
    var allocator = allocatorCast(userData);
    _ = allocator;
    _ = ptr;
    // TODO can't free with Zig Allocator without size, so no free. YOLO!
}

export fn stb_zig_sort(base: ?*anyopaque, n: usize, size: usize, compare: ?*anyopaque) void
{
    // TODO
    _ = base;
    _ = n;
    _ = size;
    _ = compare;
}
