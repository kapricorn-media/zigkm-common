const builtin = @import("builtin");
const std = @import("std");

const zigkm_app = @import("zigkm-app");
const bigdata = zigkm_app.bigdata;

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
    defer {
        if (gpa.deinit()) {
            std.log.err("leaks!", .{});
        }
    }
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const argsReq = 3;
    if (args.len != argsReq) {
        std.log.err("Expected {} args, got {}", .{argsReq, args.len});
        return error.BadArgs;
    }

    // Generate data
    // const dirPath = args[1];
    // const data = try bigdata.generate(dirPath, allocator);
    // defer allocator.free(data);

    // // Verify that the data lods into the map correctly
    // var map = std.StringHashMap([]const u8).init(allocator);
    // defer map.deinit();
    // try bigdata.load(data, &map);
    // var it = map.iterator();
    // while (it.next()) |kv| {
    //     std.log.info("{s} - {}", .{kv.key_ptr.*, kv.value_ptr.len});
    // }

    // // Save generated data to file
    // const outFile = args[2];
    // var file = try std.fs.cwd().createFile(outFile, .{});
    // defer file.close();
    // try file.writeAll(data);

    // std.log.info("Generated and saved \"{s}\" directory to file \"{s}\" ({} bytes)", .{dirPath, outFile, data.len});
    return error.Maintenance;
}
