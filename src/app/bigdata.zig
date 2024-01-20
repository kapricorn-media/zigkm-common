const std = @import("std");

const m = @import("zigkm-math");
const stb = @import("zigkm-stb");
const zigimg = @import("zigimg");

const psd = @import("psd.zig");

const CHUNK_SIZE = 512 * 1024;

fn readIntBigEndian(comptime T: type, data: []const u8) !T
{
    var stream = std.io.fixedBufferStream(data);
    var reader = stream.reader();
    return reader.readIntBig(T);
}

fn trim(image: zigimg.Image, slice: m.Rect2usize) m.Rect2usize
{
    std.debug.assert(image.pixels == .rgba32); // need alpha channel for current trim
    std.debug.assert(slice.min.x <= image.width and slice.min.y <= image.height);
    std.debug.assert(slice.max.x <= image.width and slice.max.y <= image.height);

    const sliceSize = slice.size();
    var max = slice.min;
    var min = slice.max;
    var y: usize = 0;
    while (y < sliceSize.y) : (y += 1) {
        var x: usize = 0;
        while (x < sliceSize.x) : (x += 1) {
            const pixelCoord = m.add(slice.min, m.Vec2usize.init(x, y));
            const pixelInd = pixelCoord.y * image.width + pixelCoord.x;
            const pixel = image.pixels.rgba32[pixelInd];
            if (pixel.a != 0) {
                max = m.max(max, pixelCoord);
                min = m.min(min, pixelCoord);
            }
        }
    }

    if (min.x > max.x and min.y > max.y) {
        return m.Rect2usize.zero;
    }
    return m.Rect2usize.init(m.add(slice.min, min), m.add(m.add(slice.min, max), m.Vec2usize.one));
}

fn deserializeMapValue(comptime T: type, data: []const u8, value: *T) !usize
{
    switch (@typeInfo(T)) {
        .Int => {
            const valueU64 = try readIntBigEndian(u64, data);
            value.* = @as(T, @intCast(valueU64));
            return 8;
        },
        .Pointer => |tiPtr| {
            switch (tiPtr.size) {
                .Slice => {
                    if (comptime tiPtr.child != u8) {
                        @compileLog("Unsupported slice type", tiPtr.child);
                        unreachable;
                    }
                    const len = try readIntBigEndian(u64, data);
                    if (data.len < len + 8) {
                        return error.BadData;
                    }
                    value.* = data[8..8+len];
                    return 8 + len;
                },
                else => {
                    @compileLog("Unsupported type", T);
                    unreachable;
                },
            }
        },
        .Array => |tiArray| {
            switch (tiArray.child) {
                u8 => {
                    std.mem.copy(u8, value, data[0..tiArray.len]);
                    return tiArray.len;
                },
                else => {
                    var i: usize = 0;
                    for (value) |*v| {
                        const n = try deserializeMapValue(tiArray.child, data[i..], v);
                        i += n;
                    }
                    return i;
                }
            }
        },
        .Struct => |tiStruct| {
            var i: usize = 0;
            inline for (tiStruct.fields) |f| {
                const n = try deserializeMapValue(f.type, data[i..], &@field(value, f.name));
                i += n;
            }
        },
        else => {
            @compileLog("Unsupported type", T);
            unreachable;
        },
    }

    return 0;
}

fn serializeMapValue(writer: anytype, value: anytype) !void
{
    var buf: [8]u8 = undefined;

    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .Int => {
            const valueU64 = @as(u64, @intCast(value));
            std.mem.writeIntBig(u64, &buf, valueU64);
            try writer.writeAll(&buf);
        },
        .Pointer => |tiPtr| {
            switch (tiPtr.size) {
                .Slice => {
                    if (comptime tiPtr.child != u8) {
                        @compileLog("Unsupported slice type", tiPtr.child);
                        unreachable;
                    }
                    std.mem.writeIntBig(u64, &buf, value.len);
                    try writer.writeAll(&buf);
                    try writer.writeAll(value);
                },
                else => {
                    @compileLog("Unsupported type", T);
                    unreachable;
                },
            }
        },
        .Array => |tiArray| {
            switch (tiArray.child) {
                u8 => {
                    try writer.writeAll(&value);
                },
                else => {
                    for (value) |v| {
                        try serializeMapValue(writer, v);
                    }
                }
            }
        },
        .Struct => |tiStruct| {
            inline for (tiStruct.fields) |f| {
                try serializeMapValue(writer, @field(value, f.name));
            }
        },
        else => {
            @compileLog("Unsupported type", T);
            unreachable;
        },
    }
}

pub fn deserializeMap(
    comptime ValueType: type,
    data: []const u8,
    map: *std.StringHashMap(ValueType)) !usize
{
    const numEntries = blk: {
        var stream = std.io.fixedBufferStream(data);
        var reader = stream.reader();
        break :blk try reader.readIntBig(u64);
    };

    var i: usize = 8;
    var iMax: usize = 0;
    var n: usize = 0;
    while (n < numEntries) : (n += 1) {
        const pathEnd = std.mem.indexOfScalarPos(u8, data, i, 0) orelse return error.BadData;
        const path = data[i..pathEnd];
        if (pathEnd + 1 + 16 > data.len) {
            return error.BadData;
        }
        const intBuf = data[pathEnd+1..pathEnd+1+16];
        var intStream = std.io.fixedBufferStream(intBuf);
        var intReader = intStream.reader();
        const valueIndex = try intReader.readIntBig(u64);
        const valueSize = try intReader.readIntBig(u64);
        if (valueIndex > data.len) {
            return error.BadData;
        }
        if (valueIndex + valueSize > data.len) {
            return error.BadData;
        }
        const valueEnd = valueIndex + valueSize;
        const valueBytes = data[valueIndex..valueEnd];
        iMax = @max(iMax, valueEnd);

        i = pathEnd + 1 + 16;

        var v: ValueType = undefined;
        _ = try deserializeMapValue(ValueType, valueBytes, &v);
        try map.put(path, v);
    }

    return @max(iMax, 8);
}

pub fn serializeMap(
    comptime ValueType: type,
    map: std.StringHashMap(ValueType),
    allocator: std.mem.Allocator) ![]const u8
{
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    var writer = out.writer();

    try writer.writeIntBig(u64, map.count());
    var mapIt = map.iterator();
    while (mapIt.next()) |entry| {
        try writer.writeAll(entry.key_ptr.*);
        try writer.writeByte(0);
        try writer.writeByteNTimes(0, 16); // filled later
    }
    const endOfKeys = out.items.len;

    var buf: [8]u8 = undefined;
    mapIt = map.iterator();
    var i: usize = @sizeOf(u64); // skip initial map.count()
    while (mapIt.next()) |entry| {
        const dataIndex = out.items.len;
        try serializeMapValue(writer, entry.value_ptr.*);
        const dataSize = out.items.len - dataIndex;

        i = std.mem.indexOfScalarPos(u8, out.items, i, 0) orelse return error.BadData;
        i += 1;
        if (i + 16 > out.items.len) {
            return error.BadData;
        }

        std.mem.writeIntBig(u64, &buf, dataIndex);
        std.mem.copy(u8, out.items[i..i+8], &buf);
        std.mem.writeIntBig(u64, &buf, dataSize);
        std.mem.copy(u8, out.items[i+8..i+16], &buf);
        i += 16;
        if (i > endOfKeys) {
            return error.BadData;
        }
    }

    return out.toOwnedSlice();
}

test {
    const allocator = std.testing.allocator;

    var map = std.StringHashMap(SourceEntry).init(allocator);
    defer map.deinit();

    var entry: SourceEntry = undefined;
    @memset(&entry.md5Checksum, 6);
    for (&entry.children.buffer) |*e| {
        e.len = 0;
    }
    entry.children.len = 2;
    entry.children.set(0, "hello, world");
    entry.children.set(1, "goodbye, world");

    try map.put("entry1", entry);
    try map.put("entry1234", entry);

    const bytes = try serializeMap(SourceEntry, map, allocator);
    defer allocator.free(bytes);

    var mapOut = std.StringHashMap(SourceEntry).init(allocator);
    defer mapOut.deinit();
    const n = try deserializeMap(SourceEntry, bytes, &mapOut);
    try std.testing.expectEqual(n, bytes.len);
    // var mapOut = try deserializeMap(SourceEntry, bytes, allocator);
    // defer mapOut.deinit();

    try std.testing.expectEqual(map.count(), mapOut.count());
    var mapIt = map.iterator();
    while (mapIt.next()) |e| {
        const key = e.key_ptr.*;
        const v = mapOut.get(key) orelse {
            std.log.err("Missing key {s}", .{key});
            return error.MissingKey;
        };
        const value = e.value_ptr.*;
        try std.testing.expectEqualSlices(u8, &value.md5Checksum, &v.md5Checksum);
        try std.testing.expectEqual(value.children.len, v.children.len);
        for (value.children.buffer, 0..) |_, i| {
            try std.testing.expectEqualStrings(value.children.buffer[i], v.children.buffer[i]);
        }
    }
}

pub const SourceEntry = struct {
    md5Checksum: [16]u8,
    children: std.BoundedArray([]const u8, 32),
};

pub const Data = struct {
    arenaAllocator: std.heap.ArenaAllocator,
    sourceMap: std.StringHashMap(SourceEntry),
    map: std.StringHashMap([]const u8),
    bytes: ?[]const u8,

    const Self = @This();

    pub fn load(self: *Self, allocator: std.mem.Allocator) void
    {
        self.arenaAllocator = std.heap.ArenaAllocator.init(allocator);
        self.* = .{
            .arenaAllocator = self.arenaAllocator,
            .sourceMap = std.StringHashMap(SourceEntry).init(self.arenaAllocator.allocator()),
            .map = std.StringHashMap([]const u8).init(self.arenaAllocator.allocator()),
            .bytes = null,
        };
    }

    pub fn loadFromFile(self: *Self, filePath: []const u8, allocator: std.mem.Allocator) !void
    {
        self.load(allocator);
        const selfAllocator = self.arenaAllocator.allocator();

        const cwd = std.fs.cwd();
        const file = try cwd.openFile(filePath, .{});
        defer file.close();
        const fileBytes = try file.readToEndAlloc(selfAllocator, 1024 * 1024 * 1024);

        const n1 = try deserializeMap(SourceEntry, fileBytes, &self.sourceMap);
        const n2 = try deserializeMap([]const u8, fileBytes[n1..], &self.map);
        if (n1 + n2 != fileBytes.len) {
            return error.BadData;
        }
        self.bytes = fileBytes;
    }

    pub fn saveToFile(self: *const Self, filePath: []const u8, allocator: std.mem.Allocator) !void
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const tempAllocator = arena.allocator();

        var file = try std.fs.cwd().createFile(filePath, .{});
        defer file.close();

        const sourceMapSerialized = try serializeMap(SourceEntry, self.sourceMap, tempAllocator);
        try file.writeAll(sourceMapSerialized);
        const mapSerialized = try serializeMap([]const u8, self.map, tempAllocator);
        try file.writeAll(mapSerialized);
    }

    pub fn deinit(self: *Self) void
    {
        self.arenaAllocator.deinit();
    }

    pub fn put(self: *Self, path: []const u8, data: []const u8, allocator: std.mem.Allocator) !void
    {
        const selfAllocator = self.arenaAllocator.allocator();

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const tempAllocator = arena.allocator();

        var sourceEntry: SourceEntry = undefined;
        var md5 = std.crypto.hash.Md5.init(.{});
        md5.update(data);
        md5.final(&sourceEntry.md5Checksum);
        sourceEntry.children.len = 0;
        // Important to clear all children for serialization logic
        for (&sourceEntry.children.buffer) |*e| {
            e.len = 0;
        }
        const pathDupe = try selfAllocator.dupe(u8, path);

        if (std.mem.endsWith(u8, path, ".psd")) {
            var psdFile: psd.PsdFile = undefined;
            try psdFile.load(data, tempAllocator);
            for (psdFile.layers, 0..) |l, i| {
                if (!l.visible) {
                    continue;
                }
                if (m.eql(l.size, m.Vec2usize.zero)) {
                    continue;
                }

                const layerPath = try std.fmt.allocPrint(selfAllocator, "{s}/{s}.layer", .{path, l.name});
                sourceEntry.children.buffer[sourceEntry.children.len] = layerPath;
                sourceEntry.children.len += 1;

                // TODO this is yorstory-specific stuff but whatever
                const safeAspect = 3;
                const sizeX = @as(usize, @intFromFloat(@as(f32, @floatFromInt(psdFile.canvasSize.y)) * safeAspect));
                const parallaxSize = m.Vec2usize.init(sizeX, psdFile.canvasSize.y);
                const topLeft = m.Vec2i.init(@divTrunc((@as(i32, @intCast(psdFile.canvasSize.x)) - @as(i32, @intCast(sizeX))), 2), 0);
                var layerImage = try zigimg.Image.create(tempAllocator, parallaxSize.x, parallaxSize.y, .rgba32);
                @memset(layerImage.pixels.asBytes(), 0);
                const layerDst = m.Rect2usize.init(m.Vec2usize.zero, parallaxSize);
                _ = try psdFile.layers[i].getPixelDataImage(null, topLeft, layerImage, layerDst);

                const sliceAll = m.Rect2usize.init(
                    m.Vec2usize.zero,
                    m.Vec2usize.init(layerImage.width, layerImage.height)
                );
                const sliceTrim = trim(layerImage, sliceAll);
                const slice = blk: {
                    const offsetLeftX = sliceTrim.min.x - sliceAll.min.x;
                    const offsetRightX = (sliceAll.min.x + sliceAll.size().x) - (sliceTrim.min.x + sliceTrim.size().x);
                    const offsetMin = @min(offsetLeftX, offsetRightX);
                    break :blk m.Rect2usize.initOriginSize(
                        m.Vec2usize.init(sliceAll.min.x + offsetMin, sliceAll.min.y),
                        m.Vec2usize.init(sliceAll.size().x - offsetMin * 2, sliceAll.size().y),
                    );
                };

                // TODO don't chunk, just save as a PNG
                const chunkSize = calculateChunkSize(slice.size(), CHUNK_SIZE);
                const chunked = try imageToPngChunkedFormat(layerImage, slice, chunkSize, allocator);

                try self.map.put(layerPath, try selfAllocator.dupe(u8, chunked));
                std.log.info("Inserted {s} ({}K)", .{layerPath, chunked.len / 1024});
            }
        } else {
            sourceEntry.children.len = 1;
            sourceEntry.children.set(0, pathDupe);
            try self.map.put(pathDupe, try selfAllocator.dupe(u8, data));
        }

        try self.sourceMap.put(pathDupe, sourceEntry);
    }

    pub fn fileExists(self: *const Self, path: []const u8, md5Checksum: *const [16]u8) bool
    {
        if (self.sourceMap.get(path)) |src| {
            if (std.mem.eql(u8, &src.md5Checksum, md5Checksum)) {
                return true;
            }
        }
        return false;
    }

    fn addIfNewOrUpdatedFilesystem(
        self: *Self, path: []const u8, fileData: []const u8, tempAllocator: std.mem.Allocator) !void
    {
        const md5 = calculateMd5Checksum(fileData);
        if (self.fileExists(path, &md5)) {
            std.log.info("Already in bigdata: {s}", .{path});
            return;
        }

        std.log.info("Inserting {s}", .{path});
        try self.put(path, fileData, tempAllocator);
    }

    pub fn fillFromFilesystem(self: *Self, path: []const u8, allocator: std.mem.Allocator) !void
    {
        const cwd = std.fs.cwd();
        var dir = try cwd.openDir(path, .{});
        defer dir.close();

        var dirIterable = try cwd.openIterableDir(path, .{});
        defer dirIterable.close();

        var walker = try dirIterable.walk(allocator);
        defer walker.deinit();
        while (try walker.next()) |entry| {
            if (entry.kind != .file) {
                continue;
            }

            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const tempAllocator = arena.allocator();

            const file = try dir.openFile(entry.path, .{});
            defer file.close();
            const fileData = try file.readToEndAlloc(tempAllocator, 1024 * 1024 * 1024);

            const filePath = try std.fmt.allocPrint(tempAllocator, "/{s}", .{entry.path});
            std.mem.replaceScalar(u8, filePath, '\\', '/');
            try self.addIfNewOrUpdatedFilesystem(filePath, fileData, tempAllocator);
        }
    }
};

pub fn calculateMd5Checksum(data: []const u8) [16]u8
{
    var buf: [16]u8 = undefined;
    var md5 = std.crypto.hash.Md5.init(.{});
    md5.update(data);
    md5.final(&buf);
    return buf;
}

pub fn calculateChunkSize(imageSize: m.Vec2usize, chunkSizeMax: usize) usize
{
    if (imageSize.x >= chunkSizeMax) {
        return 0;
    }
    if (imageSize.x * imageSize.y <= chunkSizeMax) {
        return 0;
    }

    const rows = chunkSizeMax / imageSize.x;
    return rows * imageSize.x;
}

// 8, 4 => 2 | 7, 4 => 2 | 9, 4 => 3
fn integerCeilingDivide(n: usize, s: usize) usize
{
    return @divTrunc(n + s - 1, s);
}

const StbCallbackData = struct {
    fail: bool,
    writer: std.ArrayList(u8).Writer,
};

fn stbCallback(context: ?*anyopaque, data: ?*anyopaque, size: c_int) callconv(.C) void
{
    const cbData = @as(*StbCallbackData, @ptrCast(@alignCast(context)));
    if (cbData.fail) {
        return;
    }

    const dataPtr = data orelse {
        cbData.fail = true;
        return;
    };
    const dataU = @as([*]u8, @ptrCast(dataPtr));
    cbData.writer.writeAll(dataU[0..@intCast(size)]) catch {
        cbData.fail = true;
    };
}

pub fn imageToPngChunkedFormat(image: zigimg.Image, slice: m.Rect2usize, chunkSize: usize, allocator: std.mem.Allocator) ![]const u8
{
    var outBuf = std.ArrayList(u8).init(allocator);
    defer outBuf.deinit();

    const sliceSize = slice.size();
    std.debug.assert(slice.min.x <= image.width and slice.max.x <= image.width);
    std.debug.assert(sliceSize.x <= image.width);
    std.debug.assert(slice.min.y <= image.height and slice.max.y <= image.height);
    std.debug.assert(sliceSize.y <= image.height);

    const sizeType = u64;
    const widthBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
    std.mem.writeIntBig(sizeType, widthBytes, @as(sizeType, @intCast(sliceSize.x)));
    const heightBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
    std.mem.writeIntBig(sizeType, heightBytes, @as(sizeType, @intCast(sliceSize.y)));
    const chunkSizeBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
    std.mem.writeIntBig(sizeType, chunkSizeBytes, @as(sizeType, chunkSize));

    var pngDataBuf = std.ArrayList(u8).init(allocator);
    defer pngDataBuf.deinit();

    if (chunkSize % sliceSize.x != 0) {
        return error.ChunkSizeBadModulo;
    }
    const chunkRows = if (chunkSize == 0) sliceSize.y else chunkSize / sliceSize.x;
    const dataSizePixels = sliceSize.x * sliceSize.y;
    const n = if (chunkSize == 0) 1 else integerCeilingDivide(dataSizePixels, chunkSize);

    const numChunksBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
    std.mem.writeIntBig(sizeType, numChunksBytes, n);

    const channels = image.pixelFormat().channelCount();
    const imageBytes = image.rawBytes();
    // std.debug.assert(image.pixels == .rgba32);
    std.debug.assert(imageBytes.len == image.width * image.height * channels);

    var i: usize = 0;
    while (i < n) : (i += 1) {
        const rowStart = chunkRows * i + slice.min.y; // idk why min
        const rowEnd = @min(chunkRows * (i + 1) + slice.min.y, sliceSize.y - 1);
        std.debug.assert(rowEnd >= rowStart);
        const rows = rowEnd - rowStart;

        const chunkStart = (rowStart * image.width + slice.min.x) * channels;
        const chunkEnd = (rowEnd * image.width + slice.min.x) * channels;
        std.debug.assert(chunkStart <= imageBytes.len and chunkEnd <= imageBytes.len);

        pngDataBuf.clearRetainingCapacity();
        var cbData = StbCallbackData {
            .fail = false,
            .writer = pngDataBuf.writer(),
        };
        const pngStride = image.rowByteSize();
        const writeResult = stb.stbi_write_png_to_func(stbCallback, &cbData, @intCast(sliceSize.x), @intCast(rows), @intCast(channels), &imageBytes[chunkStart], @intCast(pngStride));
        if (writeResult == 0) {
            return error.stbWriteFail;
        }

        const chunkLenBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
        std.mem.writeIntBig(sizeType, chunkLenBytes, pngDataBuf.items.len);
        try outBuf.appendSlice(pngDataBuf.items);
    }

    return outBuf.toOwnedSlice();
}

fn testIntegerCeilingDivide(v1: usize, v2: usize, expectedResult: usize) !void
{
    const result = integerCeilingDivide(v1, v2);
    try std.testing.expectEqual(expectedResult, result);
}

test "integerCeilingDivide"
{
    try testIntegerCeilingDivide(8, 4, 2);
    try testIntegerCeilingDivide(7, 4, 2);
    try testIntegerCeilingDivide(9, 4, 3);
    try testIntegerCeilingDivide(4096 * 4096, 512 * 1024, 32);
}
