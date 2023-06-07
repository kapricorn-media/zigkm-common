const builtin = @import("builtin");
const std = @import("std");

const app = @import("zigkm-app");
const bigdata = app.bigdata;

pub usingnamespace @import("zigkm-stb").exports;

pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .info,
    .ReleaseFast => .info,
    .ReleaseSmall => .info,
};

pub fn main() !void
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer {
    //     if (gpa.deinit()) {
    //         std.log.err("leaks!", .{});
    //     }
    // }
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 3) {
        std.log.err("Expected arguments: <path> <outfile>", .{});
        return error.BadArgs;
    }

    const dirPath = args[1];
    var data = try bigdata.doFilesystem(dirPath, allocator);
    errdefer data.deinit();

    const outFile = args[2];
    try data.saveToFile(outFile, allocator);

    std.log.info("Generated and saved \"{s}\" directory to file \"{s}\"", .{dirPath, outFile});
}
