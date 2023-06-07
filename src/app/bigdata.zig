const std = @import("std");

const m = @import("zigkm-math");
const stb = @import("zigkm-stb");
const zigimg = @import("zigimg");

const psd = @import("psd.zig");

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

pub fn save(map: *const std.StringHashMap([]const u8), allocator: std.mem.Allocator) ![]const u8
{
    var mapIt = map.iterator();
    while (mapIt.next()) |entry| {
        _ = entry;
        _ = allocator;
    }
    return "";
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

pub fn imageToPngChunkedFormat(image: zigimg.Image, slice: m.Rect2usize, chunkSize: usize, allocator: std.mem.Allocator) ![]const u8
{
    var outBuf = std.ArrayList(u8).init(allocator);
    defer outBuf.deinit();

    const sizeType = u64;
    const sliceSize = slice.size();
    var widthBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
    std.mem.writeIntBig(sizeType, widthBytes, @intCast(sizeType, sliceSize.x));
    var heightBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
    std.mem.writeIntBig(sizeType, heightBytes, @intCast(sizeType, sliceSize.y));
    var chunkSizeBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
    std.mem.writeIntBig(sizeType, chunkSizeBytes, chunkSize);

    var pngDataBuf = std.ArrayList(u8).init(allocator);
    defer pngDataBuf.deinit();

    if (chunkSize % sliceSize.x != 0) {
        return error.ChunkSizeBadModulo;
    }
    const chunkRows = if (chunkSize == 0) sliceSize.y else chunkSize / sliceSize.x;
    const dataSizePixels = sliceSize.x * sliceSize.y;
    const n = if (chunkSize == 0) 1 else integerCeilingDivide(dataSizePixels, chunkSize);

    var numChunksBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
    std.mem.writeIntBig(sizeType, numChunksBytes, n);

    var i: usize = 0;
    while (i < n) : (i += 1) {
        const rowStart = chunkRows * i;
        const rowEnd = std.math.min(chunkRows * (i + 1), sliceSize.y);
        std.debug.assert(rowEnd > rowStart);
        const rows = rowEnd - rowStart;

        const channels = image.pixelFormat().channelCount();
        const chunkStart = ((rowStart + slice.min.y) * image.width + slice.min.x) * channels;
        const chunkEnd = ((rowEnd + slice.min.y) * image.width + slice.min.x) * channels;
        const chunkBytes = image.rawBytes()[chunkStart..chunkEnd];

        pngDataBuf.clearRetainingCapacity();
        var cbData = StbCallbackData {
            .fail = false,
            .writer = pngDataBuf.writer(),
        };
        const pngStride = image.rowByteSize();
        const writeResult = stb.stbi_write_png_to_func(stbCallback, &cbData, @intCast(c_int, sliceSize.x), @intCast(c_int, rows), @intCast(c_int, channels), &chunkBytes[0], @intCast(c_int, pngStride));
        if (writeResult == 0) {
            return error.stbWriteFail;
        }

        var chunkLenBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
        std.mem.writeIntBig(sizeType, chunkLenBytes, pngDataBuf.items.len);
        try outBuf.appendSlice(pngDataBuf.items);
    }

    return outBuf.toOwnedSlice();
}

pub fn pngToChunkedFormat(pngData: []const u8, chunkSizeMax: usize, allocator: std.mem.Allocator) ![]const u8
{
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const tempAllocator = arena.allocator();

    var imageStream = std.io.StreamSource {.const_buffer = std.io.fixedBufferStream(pngData)};
    const pngHeader = try zigimg.png.loadHeader(&imageStream);
    const imageSize = m.Vec2usize.init(pngHeader.width, pngHeader.height);
    const chunkSize = calculateChunkSize(imageSize, chunkSizeMax);

    if (chunkSize != 0) {
        // TODO reuse existing imageStream + pngHeader?
        const image = try zigimg.Image.fromMemory(tempAllocator, pngData);
        const slice = m.Rect2usize.init(m.Vec2usize.zero, imageSize);
        return imageToPngChunkedFormat(image, slice, chunkSize, allocator);
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
