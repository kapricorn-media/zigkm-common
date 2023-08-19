const std = @import("std");

pub const exports = @import("exports.zig");

pub usingnamespace @cImport({
    // @cInclude("stb_image.h");
    // @cInclude("stb_image_write.h");
    @cInclude("stb_rect_pack.h");
    @cInclude("stb_truetype.h");
});
