const builtin = @import("builtin");
const std = @import("std");

const defs = @import("defs.zig");

const exports = switch (defs.platform) {
    .ios => @import("ios_exports.zig"),
    .web => @import("wasm_exports.zig"),
};

pub usingnamespace exports;
