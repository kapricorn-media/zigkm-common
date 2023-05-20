const std = @import("std");

const google = @import("zigkm-google");

pub fn main() !void
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer {
    //     if (gpa.deinit()) {
    //         std.log.err("GPA detected leaks", .{});
    //     }
    // }
    const allocator = gpa.allocator();

    const authData = google.auth.AuthData {
        .apiKey = "AIzaSyA8Em8qUtjM8z4bich_qUtKugIzpicXlLI"
    };
    const publicFolderId = "1qGP8RjPHdgamDDBLQTV4yC6Qq9yGmL3w";

    const result = try google.drive.listFiles(publicFolderId, authData, allocator);
    for (result.files) |f| {
        if (f.typeData == .folder) {
            const resultInner = try google.drive.listFiles(f.id, authData, allocator);
            std.log.info("folder: {s}", .{f.name});
            for (resultInner.files) |fIn| {
                if (fIn.typeData == .file) {
                    std.log.info("    {s}", .{fIn.name});
                    if (std.mem.eql(u8, fIn.name, "1.png")) {
                        const pngResponse = try google.drive.downloadFile(fIn.id, authData, allocator);
                        defer pngResponse.deinit();
                        std.log.info("    (downloaded {} bytes)", .{pngResponse.body.len});
                    }
                }
            }
        }
    }
}