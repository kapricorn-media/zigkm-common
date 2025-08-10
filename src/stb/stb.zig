const std = @import("std");

pub usingnamespace @cImport({
    @cInclude("stb_rect_pack.h");
    @cInclude("stb_truetype.h");
});

comptime {
    _ = @import("exports.zig");
}
