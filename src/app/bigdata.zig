const std = @import("std");

const m = @import("zigkm-math");
const stb = @import("zigkm-stb");

const image = @import("image.zig");
const psd = @import("psd.zig");

const CHUNK_SIZE_MAX = 512 * 1024;

pub fn load(data: []const u8, map: *std.StringHashMap([]const u8)) !void
{
    var stream = std.io.fixedBufferStream(data);
    var reader = stream.reader();

    const numEntries = try reader.readIntBig(u64);
    var i: usize = 8;
    var n: u64 = 0;
    while (n < numEntries) : (n += 1) {
        const uriEnd = std.mem.indexOfScalarPos(u8, data, i, 0) orelse return error.BadData;
        const uri = data[i..uriEnd];
        if (uriEnd + 1 + 16 > data.len) {
            return error.BadData;
        }
        const intBuf = data[uriEnd+1..uriEnd+1+16];
        var intStream = std.io.fixedBufferStream(intBuf);
        var intReader = intStream.reader();
        const dataIndex = try intReader.readIntBig(u64);
        const dataSize = try intReader.readIntBig(u64);
        if (dataIndex > data.len) {
            return error.BadData;
        }
        if (dataIndex + dataSize > data.len) {
            return error.BadData;
        }
        const theData = data[dataIndex..dataIndex+dataSize];

        i = uriEnd + 1 + 16;

        try map.put(uri, theData);
    }
}

pub fn generate(dirPath: []const u8, allocator: std.mem.Allocator) ![]const u8
{
    const Entry = struct {
        uri: []const u8,
        data: []const u8,
    };
    var entries = std.ArrayList(Entry).init(allocator);
    defer {
        for (entries.items) |entry| {
            allocator.free(entry.uri);
            allocator.free(entry.data);
        }
        entries.deinit();
    }

    const cwd = std.fs.cwd();
    var dir = try cwd.openDir(dirPath, .{});
    defer dir.close();

    var dirIterable = try cwd.openIterableDir(dirPath, .{});
    defer dirIterable.close();

    var walker = try dirIterable.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != .File) {
            continue;
        }

        var arenaAllocator = std.heap.ArenaAllocator.init(allocator);
        defer arenaAllocator.deinit();
        const tempAllocator = arenaAllocator.allocator();

        const file = try dir.openFile(entry.path, .{});
        defer file.close();
        const fileData = try file.readToEndAlloc(tempAllocator, 1024 * 1024 * 1024);

        if (std.mem.endsWith(u8, entry.path, ".png")) {
            std.log.info("loading {s}", .{entry.path});

            // Read file data
            const chunked = try pngToChunkedFormat(fileData, CHUNK_SIZE_MAX, tempAllocator);
            // const uri = try std.fmt.allocPrint(allocator, "/images/{s}", .{entry.path});
            try entries.append(Entry {
                .uri = try std.fmt.allocPrint(allocator, "/{s}", .{entry.path}),
                .data = try allocator.dupe(u8, chunked),
            });
            std.log.info("- done ({}K -> {}K)", .{fileData.len / 1024, chunked.len / 1024});
        } else if (std.mem.endsWith(u8, entry.path, ".psd")) {
            std.log.info("loading {s}", .{entry.path});

            var psdFile: psd.PsdFile = undefined;
            try psdFile.load(fileData, tempAllocator);
            for (psdFile.layers) |l, i| {
                const dashInd = std.mem.indexOfScalar(u8, l.name, '-') orelse continue;
                const pre = l.name[0..dashInd];
                var allNumbers = true;
                for (pre) |c| {
                    if (!('0' <= c and c <= '9')) {
                        allNumbers = false;
                        break;
                    }
                }
                if (!allNumbers) continue;

                const safeAspect = 3;
                const sizeX = @floatToInt(usize, @intToFloat(f32, psdFile.canvasSize.y) * safeAspect);
                const parallaxSize = m.Vec2usize.init(sizeX, psdFile.canvasSize.y);
                const topLeft = m.Vec2i.init(@divTrunc((@intCast(i32, psdFile.canvasSize.x) - @intCast(i32, sizeX)), 2), 0);
                const layerPixelData = image.PixelData {
                    .size = parallaxSize,
                    .channels = 4,
                    .data = try tempAllocator.alloc(u8, parallaxSize.x * parallaxSize.y * 4),
                };
                std.mem.set(u8, layerPixelData.data, 0);
                const sliceDst = image.PixelDataSlice {
                    .topLeft = m.Vec2usize.zero,
                    .size = parallaxSize,
                };
                _ = try psdFile.layers[i].getPixelDataRectBuf(null, topLeft, layerPixelData, sliceDst);

                const sliceAll = image.PixelDataSlice {
                    .topLeft = m.Vec2usize.zero,
                    .size = layerPixelData.size,
                };
                const sliceTrim = image.trim(layerPixelData, sliceAll);
                const slice = blk: {
                    const offsetLeftX = sliceTrim.topLeft.x - sliceAll.topLeft.x;
                    const offsetRightX = (sliceAll.topLeft.x + sliceAll.size.x) - (sliceTrim.topLeft.x + sliceTrim.size.x);
                    const offsetMin = std.math.min(offsetLeftX, offsetRightX);
                    break :blk image.PixelDataSlice {
                        .topLeft = m.Vec2usize.init(sliceAll.topLeft.x + offsetMin, sliceAll.topLeft.y),
                        .size = m.Vec2usize.init(sliceAll.size.x - offsetMin * 2, sliceAll.size.y),
                    };
                };
                const chunkSize = calculateChunkSize(slice.size, CHUNK_SIZE_MAX);
                const chunked = try pixelDataToPngChunkedFormat(layerPixelData, slice, chunkSize, allocator);
                const outputDir = entry.path[0..entry.path.len - 4];
                const uri = try std.fmt.allocPrint(allocator, "/{s}/{s}.png", .{outputDir, l.name});
                try entries.append(Entry {
                    .uri = uri,
                    .data = chunked,
                });
                std.log.info("wrote chunked layer as {s} ({}K)", .{uri, chunked.len / 1024});

                // const png = @import("png.zig");
                // const testPath = try std.fmt.allocPrint(tempAllocator, "{s}.png", .{l.name});
                // try png.writePngFile(testPath, layerPixelData, slice);
            }
        } else {
            try entries.append(Entry {
                .uri = try std.fmt.allocPrint(allocator, "/{s}", .{entry.path}),
                .data = try allocator.dupe(u8, fileData),
            });
        }
    }

    var buf: [8]u8 = undefined;

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    var writer = out.writer();

    try writer.writeIntBig(u64, entries.items.len);
    for (entries.items) |entry| {
        try writer.writeAll(entry.uri);
        try writer.writeByte(0);
        try writer.writeByteNTimes(0, 16); // filled later
    }

    var i: usize = 8;
    for (entries.items) |entry| {
        const dataIndex = out.items.len;
        try writer.writeAll(entry.data);

        i = std.mem.indexOfScalarPos(u8, out.items, i, 0) orelse return error.BadData;
        i += 1;
        if (i + 16 > out.items.len) {
            return error.BadData;
        }
        std.mem.writeIntBig(u64, &buf, dataIndex);
        std.mem.copy(u8, out.items[i..i+8], &buf);
        std.mem.writeIntBig(u64, &buf, entry.data.len);
        std.mem.copy(u8, out.items[i+8..i+16], &buf);
        i += 16;
    }

    return out.toOwnedSlice();
}

fn calculateChunkSize(imageSize: m.Vec2usize, chunkSizeMax: usize) usize
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
    const cbData = @ptrCast(*StbCallbackData, @alignCast(@alignOf(*StbCallbackData), context));
    if (cbData.fail) {
        return;
    }

    const dataPtr = data orelse {
        cbData.fail = true;
        return;
    };
    const dataU = @ptrCast([*]u8, dataPtr);
    cbData.writer.writeAll(dataU[0..@intCast(usize, size)]) catch {
        cbData.fail = true;
    };
}

fn pixelDataToPngChunkedFormat(pixelData: image.PixelData, slice: image.PixelDataSlice, chunkSize: usize, allocator: std.mem.Allocator) ![]const u8
{
    var outBuf = std.ArrayList(u8).init(allocator);
    defer outBuf.deinit();

    const sizeType = u64;
    var widthBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
    std.mem.writeIntBig(sizeType, widthBytes, @intCast(sizeType, slice.size.x));
    var heightBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
    std.mem.writeIntBig(sizeType, heightBytes, @intCast(sizeType, slice.size.y));
    var chunkSizeBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
    std.mem.writeIntBig(sizeType, chunkSizeBytes, chunkSize);

    var pngDataBuf = std.ArrayList(u8).init(allocator);
    defer pngDataBuf.deinit();

    if (chunkSize % slice.size.x != 0) {
        return error.ChunkSizeBadModulo;
    }
    const chunkRows = if (chunkSize == 0) slice.size.y else chunkSize / slice.size.x;
    const dataSizePixels = slice.size.x * slice.size.y;
    const n = if (chunkSize == 0) 1 else integerCeilingDivide(dataSizePixels, chunkSize);

    var numChunksBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
    std.mem.writeIntBig(sizeType, numChunksBytes, n);

    var i: usize = 0;
    while (i < n) : (i += 1) {
        const rowStart = chunkRows * i;
        const rowEnd = std.math.min(chunkRows * (i + 1), slice.size.y);
        std.debug.assert(rowEnd > rowStart);
        const rows = rowEnd - rowStart;

        const chunkStart = ((rowStart + slice.topLeft.y) * pixelData.size.x + slice.topLeft.x) * pixelData.channels;
        const chunkEnd = ((rowEnd + slice.topLeft.y) * pixelData.size.x + slice.topLeft.x) * pixelData.channels;
        const chunkBytes = pixelData.data[chunkStart..chunkEnd];

        pngDataBuf.clearRetainingCapacity();
        var cbData = StbCallbackData {
            .fail = false,
            .writer = pngDataBuf.writer(),
        };
        const pngStride = pixelData.size.x * pixelData.channels;
        const writeResult = stb.stbi_write_png_to_func(stbCallback, &cbData, @intCast(c_int, slice.size.x), @intCast(c_int, rows), @intCast(c_int, pixelData.channels), &chunkBytes[0], @intCast(c_int, pngStride));
        if (writeResult == 0) {
            return error.stbWriteFail;
        }

        var chunkLenBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
        std.mem.writeIntBig(sizeType, chunkLenBytes, pngDataBuf.items.len);
        try outBuf.appendSlice(pngDataBuf.items);
    }

    return outBuf.toOwnedSlice();
}

fn pngToChunkedFormat(pngData: []const u8, chunkSizeMax: usize, allocator: std.mem.Allocator) ![]const u8
{
    const pngDataLenInt = @intCast(c_int, pngData.len);

    // PNG file -> pixel data (stb_image)
    var width: c_int = undefined;
    var height: c_int = undefined;
    var channels: c_int = undefined;
    var result = stb.stbi_info_from_memory(&pngData[0], pngDataLenInt, &width, &height, &channels);
    if (result != 1) {
        return error.stbiInfoFail;
    }

    const imageSize = m.Vec2usize.initFromVec2i(m.Vec2i.init(width, height));
    const chunkSize = calculateChunkSize(imageSize, chunkSizeMax);

    if (chunkSize != 0) {
        var d = stb.stbi_load_from_memory(&pngData[0], @intCast(c_int, pngData.len), &width, &height, &channels, 0);
        if (d == null) {
            return error.stbReadFail;
        }
        defer stb.stbi_image_free(d);

        const channelsU8 = @intCast(u8, channels);
        const dataSizeBytes = imageSize.x * imageSize.y * channelsU8;

        const pixelData = image.PixelData {
            .size = imageSize,
            .channels = channelsU8,
            .data = d[0..dataSizeBytes],
        };
        const slice = image.PixelDataSlice {
            .topLeft = m.Vec2usize.zero,
            .size = imageSize,
        };
        return pixelDataToPngChunkedFormat(pixelData, slice, chunkSize, allocator);
    } else {
        var outBuf = std.ArrayList(u8).init(allocator);
        defer outBuf.deinit();

        const sizeType = u64;
        var widthBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
        std.mem.writeIntBig(sizeType, widthBytes, @intCast(sizeType, imageSize.x));
        var heightBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
        std.mem.writeIntBig(sizeType, heightBytes, @intCast(sizeType, imageSize.y));
        var chunkSizeBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
        std.mem.writeIntBig(sizeType, chunkSizeBytes, chunkSize);

        var numChunksBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
        std.mem.writeIntBig(sizeType, numChunksBytes, 1);
        var chunkLenBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
        std.mem.writeIntBig(sizeType, chunkLenBytes, pngData.len);
        try outBuf.appendSlice(pngData);

        return outBuf.toOwnedSlice();
    }
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
