const std = @import("std");

const google = @import("zigkm-google");

pub fn main() !void
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit()) {
            std.log.err("GPA detected leaks", .{});
        }
    }
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);
    if (args.len != 3) {
        std.log.err("Expected arguments: <api-key> <folder-id>", .{});
        return error.BadArgs;
    }

    const authData = google.auth.AuthData {.apiKey = args[1]};
    const publicFolderId = args[2];

    var result = try google.drive.listFiles(publicFolderId, authData, allocator);
    defer result.deinit();
    for (result.files) |f| {
        if (f.typeData == .folder) {
            var resultInner = try google.drive.listFiles(f.id, authData, allocator);
            defer resultInner.deinit();
            std.log.info("folder: {s}", .{f.name});
            for (resultInner.files) |fIn, i| {
                if (fIn.typeData == .file) {
                    std.log.info("    {s}", .{fIn.name});
                    if (i == 0) {
                        const pngResponse = try google.drive.downloadFile(fIn.id, authData, allocator);
                        defer pngResponse.deinit();
                        std.log.info("    (downloaded {} bytes)", .{pngResponse.body.len});
                    }
                }
            }
        }
    }
}