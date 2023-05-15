const std = @import("std");

const c = @import("c.zig");

pub fn decode(
    pemData: []const u8,
    comptime UserDataType: type,
    userData: UserDataType,
    callback: fn(userData: UserDataType, data: []const u8) anyerror!void,
    allocator: std.mem.Allocator) !void
{
    var state = PemState {
        .success = true,
        .list = std.ArrayList(u8).init(allocator),
    };
    defer state.list.deinit();

    var context: c.br_pem_decoder_context = undefined;
    c.br_pem_decoder_init(&context);
    c.br_pem_decoder_setdest(&context, pemCallbackC, &state);

    var remaining = pemData;
    while (state.success and remaining.len > 0) {
        const n = c.br_pem_decoder_push(&context, &remaining[0], remaining.len);
        if (n == 0) {
            while (true) {
                const event = c.br_pem_decoder_event(&context);
                switch (event) {
                    0 => break,
                    c.BR_PEM_BEGIN_OBJ => {
                        state.list.clearRetainingCapacity();
                    },
                    c.BR_PEM_END_OBJ => {
                        try callback(userData, state.list.items);
                    },
                    c.BR_PEM_ERROR => {
                        return error.PemDecodeErrorEvent;
                    },
                    else => {
                        return error.PemDecodeUnexpectedEvent;
                    },
                }
            }
        } else {
            remaining = remaining[n..];
        }
    }

    if (!state.success) {
        return error.PemDecodeError;
    }

    if (state.list.items.len > 0) {
        try callback(userData, state.list.items);
    }
}

const PemState = struct {
    success: bool,
    list: std.ArrayList(u8),
};

fn pemCallbackC(userData: ?*anyopaque, data: ?*const anyopaque, len: usize) callconv(.C) void
{
    var state = @ptrCast(*PemState, @alignCast(@alignOf(*PemState), userData));
    const bytes = @ptrCast([*]const u8, data);
    const slice = bytes[0..len];
    state.list.appendSlice(slice) catch |err| {
        std.log.err("pemCallbackC error {}", .{err});
        state.success = false;
    };
}
