const std = @import("std");

const httpz = @import("httpz");

const bigdata = @import("bigdata.zig");

pub fn responded(res: *const httpz.Response) bool
{
    // WARN(patio): This is very httpz-implementation-dependent.
    return res.status != 200 or res.pos > 0;
}

pub fn writeFileResponse(res: *httpz.Response, relativePath: []const u8, final: bool) !void
{
    const cwd = std.fs.cwd();
    const file = cwd.openFile(relativePath, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            if (final) {
                return err;
            } else {
                return;
            }
        },
        else => return err,
    };
    defer file.close();
    const fileData = try file.readToEndAlloc(res.arena, 1024 * 1024 * 1024);

    res.status = 200;
    res.content_type = httpz.ContentType.forFile(relativePath);
    const writer = res.writer();
    try writer.writeAll(fileData);
    try res.write();
}

fn uriHasFileExtension(uri: []const u8) bool
{
    var dotAfterSlash = false;
    for (uri) |c| {
        if (c == '.') {
            dotAfterSlash = true;
        }
        else if (c == '/') {
            dotAfterSlash = false;
        }
    }
    return dotAfterSlash;
}

pub fn serveStatic(res: *httpz.Response, uri: []const u8, comptime dir: []const u8, final: bool) !void
{
    if (uri.len == 0) {
        return error.BadUri;
    }
    if (uri.len > 1 and uri[1] == '/') {
        return error.BadUri;
    }

    var prevWasDot = false;
    for (uri) |c| {
        if (c == '.') {
            if (prevWasDot) {
                return error.BadUri;
            }
            prevWasDot = true;
        } else {
            prevWasDot = false;
        }
    }

    const suffix = blk: {
        if (uri[uri.len - 1] == '/') {
            break :blk "index.html";
        } else if (!uriHasFileExtension(uri)) {
            break :blk "/index.html";
        } else {
            break :blk "";
        }
    };

    const path = try std.fmt.allocPrint(res.arena, dir ++ "/{s}{s}", .{uri[1..], suffix});
    try writeFileResponse(res, path, final);
}

pub fn serverAppEndpoints(req: *httpz.Request, res: *httpz.Response, data: *const bigdata.Data, wasmPath: []const u8, final: bool, comptime debug: bool) !void
{
    if (req.method == .GET) {
        if (std.mem.eql(u8, req.url.path, "/main.wasm")) {
            try writeFileResponse(res, wasmPath, final);
        } else {
            const path = blk: {
                const extension = std.fs.path.extension(req.url.path);
                if (extension.len == 0 or std.mem.eql(u8, req.url.path, "/wasm.html")) {
                    break :blk "/wasm.html";
                } else {
                    break :blk req.url.path;
                }
            };
            if (debug) {
                // For faster iteration
                serveStatic(res, path, "zig-out/server-temp/static", final) catch |err| switch (err) {
                    error.FileNotFound => {},
                    else => return,
                };
            }
            const content = data.map.get(path) orelse {
                if (final) {
                    res.status = 404;
                }
                return;
            };

            res.content_type = httpz.ContentType.forFile(path);
            try res.writer().writeAll(content);
        }
    } else if (req.method == .POST) {
        // ...
    }
}
