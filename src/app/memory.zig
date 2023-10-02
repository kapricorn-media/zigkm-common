const std = @import("std");

pub const Memory = struct
{
    memory: []u8,
    permanentSize: usize,
    permanent: std.heap.FixedBufferAllocator,

    const Self = @This();

    pub fn init(memory: []u8, permanentSize: usize, permanentOffset: usize) Memory
    {
        std.debug.assert(permanentOffset <= permanentSize);
        std.debug.assert(permanentSize <= memory.len);

        const permanent = memory[permanentOffset..permanentSize];
        return Self {
            .memory = memory,
            .permanentSize = permanentSize,
            .permanent = std.heap.FixedBufferAllocator.init(permanent),
        };
    }

    pub fn permanentAllocator(self: *Self) std.mem.Allocator
    {
        return self.permanent.allocator();
    }

    pub fn tempBufferAllocator(self: *Self) std.heap.FixedBufferAllocator
    {
        const transient = self.memory[self.permanentSize..];
        return std.heap.FixedBufferAllocator.init(transient);
    }
};
