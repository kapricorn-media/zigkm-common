const std = @import("std");

test "HTTP client"
{
    const allocator = std.testing.allocator;

    var headers = std.http.Headers {
        .allocator = allocator,
    };
    defer headers.deinit();

    var client = std.http.Client {
        .allocator = allocator,
    };
    defer client.deinit();

    const uri = try std.Uri.parse("https://www.google.com");
    var req = try client.request(.GET, uri, headers, .{});
    defer req.deinit();
    try req.start();
    try req.finish();
    try req.wait();

    std.debug.print("\n", .{});
    std.debug.print("{}\n", .{req.response.status});

    var buf: [4096]u8 = undefined;
    var n: usize = 0;
    while (true) {
        const bytes = try req.read(&buf);
        if (bytes == 0) break;

        n += bytes;
    }
    std.debug.print("{}\n", .{n});
}
