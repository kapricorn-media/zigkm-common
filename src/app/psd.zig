const std = @import("std");
const Allocator = std.mem.Allocator;

const m = @import("zigkm-math");
const zigimg = @import("zigimg");

pub const ImageDataFormat = enum(u8) {
    Raw       = 0,
    RLE       = 1,
    ZipNoPred = 2,
    ZipPred   = 3,
};

pub const LayerBlendMode = enum {
    Normal,
    Multiply,
};

pub const LayerChannelId = enum(i16) {
    UserMask = -2,
    Alpha    = -1,
    Red      = 0,
    Green    = 1,
    Blue     = 2,
};

pub const LayerChannelData = struct {
    id: LayerChannelId,
    dataFormat: ImageDataFormat,
    data: []const u8,
};

pub const LayerData = struct {
    name: []const u8,
    topLeft: m.Vec2i,
    size: m.Vec2usize,
    opacity: u8,
    blendMode: ?LayerBlendMode,
    visible: bool,
    channels: []LayerChannelData,

    const Self = @This();

    pub fn getPixelDataImage(self: *const Self, channel: ?LayerChannelId, topLeft: m.Vec2i, image: zigimg.Image, dst: m.Rect2usize) !m.Rect2usize
    {
        if (channel != null) {
            return error.Unsupported;
        }

        const imageSize = m.Vec2usize.init(image.width, image.height);
        if (dst.max.x > imageSize.x or dst.max.y > imageSize.y) {
            return error.OutOfBounds;
        }

        const topLeftMax = m.max(topLeft, self.topLeft);
        const layerTopLeft = m.sub(topLeftMax, self.topLeft).toVec2usize();
        if (layerTopLeft.x >= self.size.x or layerTopLeft.y >= self.size.y) {
            return error.OutOfBounds;
        }

        const srcSizeCapped = m.min(dst.size(), m.sub(self.size, layerTopLeft));
        const dstTopLeftOffset = m.max(m.sub(topLeftMax, topLeft), m.Vec2i.zero).toVec2usize();
        const dstTopLeft = m.add(dst.min, dstTopLeftOffset);
        std.debug.assert(dstTopLeft.x <= imageSize.x and dstTopLeft.y <= imageSize.y);
        const dstSizeCapped = m.min(srcSizeCapped, m.sub(imageSize, dstTopLeft));
        const src = m.Rect2usize.initOriginSize(layerTopLeft, dstSizeCapped);
        const dstAdjusted = m.Rect2usize.initOriginSize(
            m.add(dst.min, dstTopLeftOffset),
            dstSizeCapped
        );

        for (self.channels) |c| {
            if (channel) |cc| {
                if (cc != c.id) {
                    continue;
                }
            }

            const channelOffset: usize = blk: {
                if (channel == null) {
                    break :blk switch (c.id) {
                        .Red => 0,
                        .Green => 1,
                        .Blue => 2,
                        .Alpha => 3,
                        else => continue,
                    };
                } else {
                    break :blk 0;
                }
            };

            switch (c.dataFormat) {
                .Raw => readPixelDataRaw(c.data, self.size, src, image, dstAdjusted, channelOffset),
                .RLE => try readPixelDataLRE(c.data, self.size, src, image, dstAdjusted, channelOffset),
                else => return error.UnsupportedDataFormat,
            }
        }

        return dstAdjusted;
    }

    pub fn getPixelDataCanvasSize(self: *const Self, channel: ?LayerChannelId, canvasSize: m.Vec2usize, allocator: Allocator) !zigimg.Image
    {
        const topLeft = m.max(self.topLeft, m.Vec2i.zero);
        const bottomRight = m.min(m.add(self.topLeft, self.size.toVec2i()), canvasSize.toVec2i());
        if (bottomRight.x <= 0 and bottomRight.y <= 0) {
            return zigimg.Image {
                .allocator = undefined,
                .width = 0,
                .height = 0,
            };
        }
        const size = m.sub(bottomRight.toVec2usize(), topLeft.toVec2usize());
        var image = try zigimg.Image.create(allocator, size.x, size.y, .rgba32);
        std.mem.set(u8, image.pixels.asBytes(), 0);
        const dst = m.Rect2usize.init(m.Vec2usize.zero, size);
        const result = try self.getPixelDataImage(channel, topLeft, image, dst);
        _ = result;
        return image;
    }

    pub fn getPixelData(self: *const Self, channel: ?LayerChannelId, allocator: Allocator) !zigimg.Image
    {
        const image = try zigimg.Image.create(allocator, self.size.x, self.size.y, .rgba32);
        const dst = m.Rect2usize.init(m.Vec2usize.zero, self.size);
        const result = try self.getPixelDataImage(channel, self.topLeft, image, dst);
        std.debug.assert(std.meta.eql(dst, result));
        return image;
    }
};

pub const PsdFile = struct {
    allocator: Allocator,
    canvasSize: m.Vec2usize,
    data: []const u8,
    layers: []LayerData,

    const Self = @This();

    pub fn load(self: *Self, data: []const u8, allocator: Allocator) !void
    {
        self.allocator = allocator;
        self.data = data;

        var reader = Reader.init(data);

        // section: header
        const HeaderRaw = extern struct {
            signature: [4]u8,
            version: [2]u8,
            reserved: [6]u8,
            channels: [2]u8,
            height: [4]u8,
            width: [4]u8,
            depth: [2]u8,
            colorMode: [2]u8,
        };
        comptime {
            std.debug.assert(@sizeOf(HeaderRaw) == 4 + 2 + 6 + 2 + 4 + 4 + 2 + 2);
        }

        const Header = struct {
            signature: [4]u8,
            version: u16,
            reserved: [6]u8,
            channels: u16,
            height: u32,
            width: u32,
            depth: u16,
            colorMode: u16,
        };

        const headerRaw = try reader.readStruct(HeaderRaw);
        var header = Header {
            .signature = headerRaw.signature,
            .version = std.mem.readInt(u16, &headerRaw.version, .big),
            .reserved = headerRaw.reserved,
            .channels = std.mem.readInt(u16, &headerRaw.channels, .big),
            .height = std.mem.readInt(u32, &headerRaw.height, .big),
            .width = std.mem.readInt(u32, &headerRaw.width, .big),
            .depth = std.mem.readInt(u16, &headerRaw.depth, .big),
            .colorMode = std.mem.readInt(u16, &headerRaw.colorMode, .big),
        };

        if (!std.mem.eql(u8, &header.signature, "8BPS")) {
            return error.InvalidSignature;
        }

        if (header.version != 1) {
            return error.InvalidVersion;
        }
        if (header.depth != 8) {
            return error.UnsupportedColorDepth;
        }

        const colorModeRgb = 3;
        if (header.colorMode != colorModeRgb) {
            return error.UnsupportedColorMode;
        }

        self.canvasSize = m.Vec2usize.init(header.width, header.height);

        // section: color mode data
        const colorModeData = try reader.readLengthAndBytes(u32);
        _ = colorModeData;

        // section: image resources
        const imageResources = try reader.readLengthAndBytes(u32);
        _ = imageResources;

        // section: layer and mask information
        const layerMaskInfoIndexBefore = reader.index;
        const layerMaskInfo = try reader.readLengthAndBytes(u32);
        if (layerMaskInfo.len > 0) {
            var layerMaskInfoReader = Reader.init(layerMaskInfo);
            const layersInfoLength = try layerMaskInfoReader.readInt(u32);
            _ = layersInfoLength;

            const layerCountSigned = try layerMaskInfoReader.readInt(i16);
            const layerCount: u32 = if (layerCountSigned < 0) @intCast(-layerCountSigned) else @intCast(layerCountSigned);
            self.layers = try allocator.alloc(LayerData, layerCount);

            for (self.layers) |*layer| {
                const top = try layerMaskInfoReader.readInt(i32);
                const left = try layerMaskInfoReader.readInt(i32);
                const bottom = try layerMaskInfoReader.readInt(i32);
                const right = try layerMaskInfoReader.readInt(i32);
                layer.topLeft = m.Vec2i.init(left, top);
                layer.size = m.Vec2usize.init(@intCast(right - left), @intCast(bottom - top));

                const channels = try layerMaskInfoReader.readInt(u16);
                layer.channels = try allocator.alloc(LayerChannelData, channels);
                for (layer.channels) |*c| {
                    const idInt = try layerMaskInfoReader.readInt(i16);
                    const size = try layerMaskInfoReader.readInt(u32);
                    const id = std.meta.intToEnum(LayerChannelId, idInt) catch |err| {
                        std.log.err("Unknown channel ID {}", .{idInt});
                        return err;
                    };
                    if (size < @sizeOf(u16)) {
                        return error.BadChannelSize;
                    }
                    c.* = LayerChannelData {
                        .id = id,
                        .dataFormat = .Raw,
                        .data = undefined,
                    };
                    c.data.len = size - @sizeOf(u16);
                }

                const LayerMaskData2 = extern struct {
                    blendModeSignature: [4]u8,
                    blendModeKey: [4]u8,
                    opacity: u8,
                    clipping: u8,
                    flags: u8,
                    zero: u8,
                };

                const layerMaskData2 = try layerMaskInfoReader.readStruct(LayerMaskData2);
                if (!std.mem.eql(u8, &layerMaskData2.blendModeSignature, "8BIM")) {
                    return error.InvalidBlendModeSignature;
                }
                layer.opacity = layerMaskData2.opacity;
                layer.blendMode = stringToBlendMode(&layerMaskData2.blendModeKey);
                layer.visible = (layerMaskData2.flags & 0b00000010) == 0;

                layer.name = "";
                const extraData = try layerMaskInfoReader.readLengthAndBytes(u32);
                if (extraData.len > 0) {
                    var extraDataReader = Reader.init(extraData);
                    const maskAdjustmentData = try extraDataReader.readLengthAndBytes(u32);
                    _ = maskAdjustmentData;
                    const blendRangeData = try extraDataReader.readLengthAndBytes(u32);
                    _ = blendRangeData;
                    layer.name = try extraDataReader.readPascalString();
                }
            }

            for (self.layers) |*layer| {
                for (layer.channels) |*c| {
                    const formatInt = try layerMaskInfoReader.readInt(i16);
                    const format = std.meta.intToEnum(ImageDataFormat, formatInt) catch |err| {
                        std.log.err("Unknown data format {}", .{formatInt});
                        return err;
                    };
                    c.dataFormat = format;
                    const dataStart = layerMaskInfoIndexBefore + @sizeOf(u32) + layerMaskInfoReader.index;
                    const dataEnd = dataStart + c.data.len;
                    c.data = data[dataStart..dataEnd];

                    if (!layerMaskInfoReader.hasRemaining(c.data.len)) {
                        return error.OutOfBounds;
                    }
                    layerMaskInfoReader.index += c.data.len;
                }
            }
        }

        // section: image data
        const imageData = reader.remainingBytes();
        _ = imageData;
    }

    pub fn deinit(self: *Self) void
    {
        for (self.layers) |layer| {
            self.allocator.free(layer.channels);
        }
        self.allocator.free(self.layers);
    }
};

fn readPixelDataRaw(
    data: []const u8,
    layerSize: m.Vec2usize,
    src: m.Rect2usize,
    image: zigimg.Image,
    dst: m.Rect2usize,
    channelOffset: usize) void
{
    std.debug.assert(image.pixels == .rgba32);
    std.debug.assert(m.eql(src.size(), dst.size()));
    std.debug.assert(src.max.x <= layerSize.x and src.max.y <= layerSize.y);

    const srcSize = src.size();
    var y: usize = 0;
    while (y < srcSize.y) : (y += 1) {
        const yIn = src.min.y + y;
        const yOut = dst.min.y + y;

        var x: usize = 0;
        while (x < srcSize.x) : (x += 1) {
            const xIn = src.min.x + x;
            const xOut = dst.min.x + x;

            const inIndex = yIn * layerSize.x + xIn;
            const outIndex = yOut * image.width + xOut;
            const pixelPtr = &image.pixels.rgba32[outIndex];
            var pixelPtrBytes = @as(*[4]u8, @ptrCast(pixelPtr));
            pixelPtrBytes[channelOffset] = data[inIndex];
        }
    }
}

fn readRowLength(rowLengths: []const u8, row: usize) u16
{
    const ptr: *const [2]u8 = @ptrCast(&rowLengths[row * @sizeOf(u16)]);
    return std.mem.readIntBig(u16, ptr);
}

fn readPixelDataLRE(
    data: []const u8,
    layerSize: m.Vec2usize,
    src: m.Rect2usize,
    image: zigimg.Image,
    dst: m.Rect2usize,
    channelOffset: usize) !void
{
    std.debug.assert(image.pixels == .rgba32);
    std.debug.assert(m.eql(src.size(), dst.size()));
    std.debug.assert(src.max.x <= layerSize.x and src.max.y <= layerSize.y);

    const rowLengthsN = layerSize.y * @sizeOf(u16);
    if (rowLengthsN > data.len) {
        return error.OutOfBounds;
    }
    const rowLengths = data[0..rowLengthsN];

    var remaining = data[rowLengthsN..];
    var y: usize = 0;
    while (y < layerSize.y) : (y += 1) {
        const rowLength = readRowLength(rowLengths, y);
        const rowData = remaining[0..rowLength];
        remaining = remaining[rowLength..];

        if (y < src.min.y or y >= src.max.y) continue;
        const yOut = y - src.min.y + dst.min.y;

        // Parse data in PackBits format
        // https://en.wikipedia.org/wiki/PackBits
        var x: usize = 0;
        var rowInd: usize = 0;
        while (true) {
            if (rowInd >= rowData.len) {
                break;
            }
            const header = @as(i8, @bitCast(rowData[rowInd]));
            rowInd += 1;

            if (header == -128) {
                continue;
            } else if (header < 0) {
                if (rowInd >= rowData.len) {
                    return error.BadRowData;
                }
                const byte = rowData[rowInd];
                rowInd += 1;
                const repeats = 1 - @as(i16, @intCast(header));
                var i: usize = 0;
                while (i < repeats) : ({i += 1; x += 1;}) {
                    if (x < src.min.x or x >= src.max.x) continue;
                    const xOut = x - src.min.x + dst.min.x;
                    const outIndex = yOut * image.width + xOut;

                    const pixelPtr = &image.pixels.rgba32[outIndex];
                    var pixelPtrBytes = @as(*[4]u8, @ptrCast(pixelPtr));
                    pixelPtrBytes[channelOffset] = byte;
                    // * buf.channels + channelOffset;
                    // buf.data[outIndex] = byte;
                }
            } else if (header >= 0) {
                const n = 1 + @as(u16, @intCast(header));
                if (rowInd + n > rowData.len) {
                    return error.BadRowData;
                }

                var i: usize = 0;
                while (i < n) : ({i += 1; x += 1;}) {
                    const byte = rowData[rowInd + i];
                    if (x < src.min.x or x >= src.max.x) continue;
                    const xOut = x - src.min.x + dst.min.x;
                    const outIndex = yOut * image.width + xOut;

                    const pixelPtr = &image.pixels.rgba32[outIndex];
                    var pixelPtrBytes = @as(*[4]u8, @ptrCast(pixelPtr));
                    pixelPtrBytes[channelOffset] = byte;
                    // * buf.channels + channelOffset;
                    // buf.data[outIndex] = byte;
                }
                rowInd += n;
            }
        }

        if (x != layerSize.x) {
            std.log.err("row width mismatch x={} layerSize.x={}", .{x, layerSize.x});
            return error.RowWidthMismatch;
        }
    }
}

fn stringToBlendMode(str: []const u8) ?LayerBlendMode
{
    const map = std.ComptimeStringMap(LayerBlendMode, .{
        .{ "norm", .Normal },
        .{ "mul ", .Multiply },
    });
    return map.get(str);
}

const Reader = struct {
    data: []const u8,
    index: usize,

    const Self = @This();

    fn init(data: []const u8) Self
    {
        return Self {
            .data = data,
            .index = 0,
        };
    }

    fn remainingBytes(self: *const Self) []const u8
    {
        std.debug.assert(self.index <= self.data.len);
        return self.data[self.index..];
    }

    fn hasRemaining(self: *const Self, size: usize) bool
    {
        return self.index + size <= self.data.len;
    }

    fn readStruct(self: *Self, comptime T: type) !*const T
    {
        std.debug.assert(@typeInfo(T) == .Struct);

        const size = @sizeOf(T);
        if (!self.hasRemaining(size)) {
            return error.OutOfBounds;
        }

        const ptr = @as(*const T, @ptrCast(&self.data[self.index]));
        self.index += size;
        return ptr;
    }

    fn readInt(self: *Self, comptime T: type) !T
    {
        const size = @sizeOf(T);
        if (!self.hasRemaining(size)) {
            return error.OutOfBounds;
        }

        const ptr: *const [size]u8 = @ptrCast(&self.data[self.index]);
        const value = std.mem.readInt(T, ptr, .big);
        self.index += size;
        return value;
    }

    fn readLengthAndBytes(self: *Self, comptime LengthType: type) ![]const u8
    {
        const length = try self.readInt(LengthType);
        if (!self.hasRemaining(length)) {
            return error.OutOfBounds;
        }
        const end = self.index + length;
        const slice = self.data[self.index..end];
        self.index = end;
        return slice;
    }

    fn readPascalString(self: *Self) ![]const u8
    {
        return self.readLengthAndBytes(u8);
    }
};
