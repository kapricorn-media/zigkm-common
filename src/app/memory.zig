const std = @import("std");
const A = std.mem.Allocator;

const root = @import("root");
const platform = @import("zigkm-platform");

pub const MEMORY_TEMP = if (@hasDecl(root, "MEMORY_TEMP")) root.MEMORY_TEMP else @compileError("Missing MEMORY_TEMP in root");

const TempArena = struct {
    fbaPtr: *std.heap.FixedBufferAllocator,
    index: usize,

    fn init(fbaPtr: *std.heap.FixedBufferAllocator) TempArena
    {
        return .{
            .fbaPtr = fbaPtr,
            .index = fbaPtr.end_index,
        };
    }

    pub fn reset(self: *TempArena) void
    {
        self.fbaPtr.end_index = self.index;
    }

    pub fn allocator(self: *TempArena) A
    {
        return self.fbaPtr.allocator();
    }
};

threadlocal var tlBuf1 = std.heap.FixedBufferAllocator.init(&.{});
threadlocal var tlBuf2 = std.heap.FixedBufferAllocator.init(&.{});
// Android can't use threadlocal because of a compiler bug.
var plainBuf1 = std.heap.FixedBufferAllocator.init(&.{});
var plainBuf2 = std.heap.FixedBufferAllocator.init(&.{});

pub fn getTempArena(alias: ?TempArena) TempArena
{
    const tb1 = switch (platform.platform) {
        .android => &plainBuf1,
        else => &tlBuf1,
    };
    const tb2 = switch (platform.platform) {
        .android => &plainBuf2,
        else => &tlBuf2,
    };

    if (tb1.buffer.len == 0) {
        const alignment = 32;
        const buf1 = std.heap.page_allocator.alignedAlloc(u8, alignment, MEMORY_TEMP) catch |err| {
            std.log.err("Failed to allocate memory, error {}", .{err});
            unreachable; // TODO
        };
        const buf2 = std.heap.page_allocator.alignedAlloc(u8, alignment, MEMORY_TEMP) catch |err| {
            std.log.err("Failed to allocate memory, error {}", .{err});
            unreachable; // TODO
        };
        tb1.* = std.heap.FixedBufferAllocator.init(buf1);
        tb2.* = std.heap.FixedBufferAllocator.init(buf2);
    }
    if (alias) |al| {
        if (al.fbaPtr == tb1) {
            return TempArena.init(tb2);
        } else {
            return TempArena.init(tb1);
        }
    } else {
        return TempArena.init(tb1);
    }
}

pub const Memory = struct
{
    memory: []u8,
    remaining: std.heap.FixedBufferAllocator,

    const Self = @This();

    pub fn init(memory: []u8, usedOffset: usize) Memory
    {
        std.debug.assert(usedOffset <= memory.len);
        return Self {
            .memory = memory,
            .remaining = std.heap.FixedBufferAllocator.init(memory[usedOffset..]),
        };
    }

    pub fn permanentAllocator(self: *Self) A
    {
        return self.remaining.allocator();
    }
};
