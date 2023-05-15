const builtin = @import("builtin");
const std = @import("std");

const defs = @import("defs.zig");

const exports = switch (defs.platform) {
    .web => @import("wasm_exports.zig"),
    else => unreachable,
};

pub usingnamespace exports;
