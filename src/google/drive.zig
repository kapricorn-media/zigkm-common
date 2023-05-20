const std = @import("std");

const http_client = @import("zigkm-http-client");

const auth = @import("auth.zig");

pub const FileType = enum {
    file,
    folder,
};

pub const FileData = struct {
    md5Checksum: []const u8,
};

pub const FileTypeData = union(FileType) {
    file: FileData,
    folder: void,
};

pub const FileMetadata = struct {
    id: []const u8,
    name: []const u8,
    typeData: FileTypeData,
};

pub const ListFilesResult = struct {
    files: []FileMetadata,

    allocator: std.mem.Allocator,
    raw: Response,

    const Self = @This();

    pub fn init(json: []const u8, allocator: std.mem.Allocator) !Self
    {
        var jsonTokenStream = std.json.TokenStream.init(json);
        const parsed = try std.json.parse(Response, &jsonTokenStream, .{.allocator = allocator});
        var files = try allocator.alloc(FileMetadata, parsed.files.len);
        for (files) |_, i| {
            files[i] = try initFileMetadata(parsed.files[i]);
        }
        return .{
            .allocator = allocator,
            .raw = parsed,
            .files = files,
        };
    }

    pub fn deinit(self: *Self) void
    {
        std.json.parseFree(Response, self.raw, .{.allocator = self.allocator});
        self.allocator.free(self.files);
    }

    const ResponseFile = struct {
        id: []const u8,
        name: []const u8,
        mimeType: []const u8,
        md5Checksum: ?[]const u8 = null,
    };
    const Response = struct {
        files: []ResponseFile,
    };

    fn initFileTypeData(response: ResponseFile) !FileTypeData
    {
        if (std.mem.eql(u8, response.mimeType, "application/vnd.google-apps.folder")) {
            return .{
                .folder = {},
            };
        } else {
            if (response.md5Checksum) |checksum| {
                return .{.file = .{.md5Checksum = checksum}};
            } else {
                return error.MissingChecksum;
            }
        }
    }

    fn initFileMetadata(response: ResponseFile) !FileMetadata
    {
        return .{
            .id = response.id,
            .name = response.name,
            .typeData = try initFileTypeData(response),
        };
    }
};

pub fn downloadFile(
    id: []const u8,
    authData: auth.AuthData,
    allocator: std.mem.Allocator) !http_client.Response
{
    if (authData != .apiKey) {
        return error.UnsupportedAuth;
    }

    const hostname = "www.googleapis.com";
    const uri = try std.fmt.allocPrint(
        allocator, "/drive/v3/files/{s}?key={s}&alt=media", .{id, authData.apiKey}
    );
    defer allocator.free(uri);
    const response = http_client.httpsGet(hostname, uri, null, allocator);
    return response;
}

pub fn listFiles(
    folderId: []const u8,
    authData: auth.AuthData,
    allocator: std.mem.Allocator) !ListFilesResult
{
    if (authData != .apiKey) {
        return error.UnsupportedAuth;
    }

    const hostname = "www.googleapis.com";
    const uri = try std.fmt.allocPrint(
        allocator,
        "/drive/v3/files?key={s}&q=\"{s}\"+in+parents&fields=files(id,name,mimeType,md5Checksum)",
        .{authData.apiKey, folderId}
    );
    defer allocator.free(uri);
    const response = try http_client.httpsGet(hostname, uri, null, allocator);
    defer response.deinit();

    const result = ListFilesResult.init(response.body, allocator) catch |err| {
        std.log.info("Error {} when parsing JSON response from Google Drive API:\n{s}", .{err, response.body});
        return err;
    };
    return result;
}
