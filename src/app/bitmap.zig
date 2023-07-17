const std = @import("std");
const assert = std.debug.assert;

// const bindings = @import("ios_bindings.zig");
// const stb = @import("stb.zig");

pub const Bitmap = struct
{
    w: u32,
    h: u32,
    channels: u8,
    data: []u8,

    const Self = @This();

    pub fn initAlloc(width: u32, height: u32, channels: u8, allocator: std.mem.Allocator) !Self
    {
        return Self {
            .w = width, .h = height, .channels = channels,
            .data = try allocator.alloc(u8, width * height)
        };
    }

    pub fn initAllocPng(pngData: []const u8, channels: u8, allocator: std.mem.Allocator) !Self
    {
        _ = pngData;
        _ = channels;
        _ = allocator; // TODO "pass" allocator to stb
        return error.Decommissioned;

        // var width: c_int = undefined;
        // var height: c_int = undefined;
        // var actualChannels: c_int = undefined;
        // stb.stbi_set_flip_vertically_on_load(1);
        // const result = stb.stbi_load_from_memory(
        //     pngData.ptr, @intCast(c_int, pngData.len),
        //     &width, &height, &actualChannels,
        //     channels);
        // if (result == null) {
        //     return error.stbi_load_from_memory;
        // }
        // if (actualChannels != channels) {
        //     return error.mismatchedChannels;
        // }

        // const bytes = @intCast(usize, width * height * channels);
        // return Self {
        //     .w = @intCast(u32, width), .h = @intCast(u32, height), .channels = channels,
        //     .data = result[0..bytes]
        // };
    }

    pub fn initWithDataR8(width: u32, height: u32, data: []u8) Self
    {
        return Self {
            .w = width, .h = height, .channels = 1, .data = data
        };
    }

    pub fn initWithDataBGRA8(width: u32, height: u32, data: []u8) Self
    {
        return Self {
            .w = width, .h = height, .channels = 4, .data = data
        };
    }

    pub fn free(self: *Self, allocator: std.mem.Allocator) void
    {
        allocator.free(self.data);
    }

    pub fn zero(self: *Self) void
    {
        std.mem.set(u8, self.data, 0);
    }

    pub fn insertBitmapAt(self: *Self, bitmap: Self, xStart: u32, yStart: u32) void
    {
        assert(self.channels == bitmap.channels);
        assert(xStart + bitmap.w <= self.w);
        assert(yStart + bitmap.h <= self.h);
        var y: u32 = 0;
        while (y < bitmap.h) : (y += 1) {
            var x: u32 = 0;
            while (x < bitmap.w) : (x += 1) {
                const srcPixInd = y * bitmap.w + x;
                const dstPixInd = (y + yStart) * self.w + (x + xStart);
                var c: u32 = 0;
                while (c < self.channels) : (c += 1) {
                    const srcInd = srcPixInd * self.channels + c;
                    const dstInd = dstPixInd * self.channels + c;
                    self.data[dstInd] = bitmap.data[srcInd];
                }
            }
        }
    }
};
