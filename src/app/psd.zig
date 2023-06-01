const std = @import("std");
const Allocator = std.mem.Allocator;

const m = @import("zigkm-math");
const zigimg = @import("zigimg");

const image = @import("image.zig");

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

    pub fn getPixelDataRectBuf(self: *const Self, channel: ?LayerChannelId, topLeft: m.Vec2i, buf: image.PixelData, sliceDst: image.PixelDataSlice) !image.PixelDataSlice
    {
        if (channel != null) {
            return error.Unsupported;
        }

        const maxCoords = m.add(sliceDst.topLeft, sliceDst.size);
        if (maxCoords.x > buf.size.x or maxCoords.y > buf.size.y) {
            return error.OutOfBounds;
        }

        const topLeftMax = m.max(topLeft, self.topLeft);
        const layerTopLeft = m.Vec2usize.initFromVec2i(m.sub(topLeftMax, self.topLeft));
        if (layerTopLeft.x >= self.size.x or layerTopLeft.y >= self.size.y) {
            return error.OutOfBounds;
        }

        const srcSizeCapped = m.min(sliceDst.size, m.sub(self.size, layerTopLeft));
        const dstTopLeftOffset = m.Vec2usize.initFromVec2i(m.max(m.sub(topLeftMax, topLeft), m.Vec2i.zero));
        const dstTopLeft = m.add(sliceDst.topLeft, dstTopLeftOffset);
        std.debug.assert(dstTopLeft.x <= buf.size.x and dstTopLeft.y <= buf.size.y);
        const dstSizeCapped = m.min(srcSizeCapped, m.sub(buf.size, dstTopLeft));
        const sliceSrc = image.PixelDataSlice {
            .topLeft = layerTopLeft,
            .size = dstSizeCapped,
        };
        const sliceDstAdjusted = image.PixelDataSlice {
            .topLeft = m.add(sliceDst.topLeft, dstTopLeftOffset),
            .size = dstSizeCapped,
        };

        for (self.channels) |c| {
            if (channel) |cc| {
                if (cc != c.id) {
                    continue;
                }
            }

            var channelOffset: usize = blk: {
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
                .Raw => readPixelDataRaw(c.data, self.size, sliceSrc, buf, sliceDstAdjusted, channelOffset),
                .RLE => try readPixelDataLRE(c.data, self.size, sliceSrc, buf, sliceDstAdjusted, channelOffset),
                else => return error.UnsupportedDataFormat,
            }
        }

        return sliceDstAdjusted;
    }

    pub fn getPixelData(self: *const Self, channel: ?LayerChannelId, allocator: Allocator) !image.PixelData
    {
        var data = image.PixelData {
            .size = self.size,
            .channels = if (channel == null) 4 else return error.Unsupported,
            .data = undefined,
        };
        data.data = try allocator.alloc(u8, data.size.x * data.size.y * data.channels);
        const sliceDst = image.PixelDataSlice {
            .topLeft = m.Vec2usize.zero,
            .size = data.size,
        };
        const sliceResult = try self.getPixelDataRectBuf(channel, self.topLeft, data, sliceDst);
        std.debug.assert(std.meta.eql(sliceDst, sliceResult));
        return data;
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
            .version = std.mem.readIntBig(u16, &headerRaw.version),
            .reserved = headerRaw.reserved,
            .channels = std.mem.readIntBig(u16, &headerRaw.channels),
            .height = std.mem.readIntBig(u32, &headerRaw.height),
            .width = std.mem.readIntBig(u32, &headerRaw.width),
            .depth = std.mem.readIntBig(u16, &headerRaw.depth),
            .colorMode = std.mem.readIntBig(u16, &headerRaw.colorMode),
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

            var layerCountSigned = try layerMaskInfoReader.readInt(i16);
            const layerCount: u32 = if (layerCountSigned < 0) @intCast(u32, -layerCountSigned) else @intCast(u32, layerCountSigned);
            self.layers = try allocator.alloc(LayerData, layerCount);

            for (self.layers) |*layer| {
                const top = try layerMaskInfoReader.readInt(i32);
                const left = try layerMaskInfoReader.readInt(i32);
                const bottom = try layerMaskInfoReader.readInt(i32);
                const right = try layerMaskInfoReader.readInt(i32);
                layer.topLeft = m.Vec2i.init(left, top);
                layer.size = m.Vec2usize.init(@intCast(usize, right - left), @intCast(usize, bottom - top));

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

fn readPixelDataRaw(data: []const u8, layerSize: m.Vec2usize, sliceSrc: image.PixelDataSlice, buf: image.PixelData, sliceDst: image.PixelDataSlice, channelOffset: usize) void
{
    std.debug.assert(m.eql(sliceSrc.size, sliceDst.size));
    const srcMax = m.add(sliceSrc.topLeft, sliceSrc.size);
    std.debug.assert(srcMax.x <= layerSize.x and srcMax.y <= layerSize.y);

    var y: usize = 0;
    while (y < sliceSrc.size.y) : (y += 1) {
        const yIn = sliceSrc.topLeft.y + y;
        const yOut = sliceDst.topLeft.y + y;

        var x: usize = 0;
        while (x < sliceSrc.size.x) : (x += 1) {
            const xIn = sliceSrc.topLeft.x + x;
            const xOut = sliceDst.topLeft.x + x;

            const inIndex = yIn * layerSize.x + xIn;
            const outIndex = (yOut * buf.size.x + xOut) * buf.channels + channelOffset;
            buf.data[outIndex] = data[inIndex];
        }
    }
}

fn readRowLength(rowLengths: []const u8, row: usize) u16
{
    return std.mem.readIntBig(u16, &rowLengths[row * @sizeOf(u16)]);
}

fn readPixelDataLRE(data: []const u8, layerSize: m.Vec2usize, sliceSrc: image.PixelDataSlice, buf: image.PixelData, sliceDst: image.PixelDataSlice, channelOffset: usize) !void
{
    std.debug.assert(m.eql(sliceSrc.size, sliceDst.size));
    const srcMax = m.add(sliceSrc.topLeft, sliceSrc.size);
    std.debug.assert(srcMax.x <= layerSize.x and srcMax.y <= layerSize.y);

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

        if (y < sliceSrc.topLeft.y or y >= srcMax.y) continue;
        const yOut = y - sliceSrc.topLeft.y + sliceDst.topLeft.y;

        // Parse data in PackBits format
        // https://en.wikipedia.org/wiki/PackBits
        var x: usize = 0;
        var rowInd: usize = 0;
        while (true) {
            if (rowInd >= rowData.len) {
                break;
            }
            const header = @bitCast(i8, rowData[rowInd]);
            rowInd += 1;

            if (header == -128) {
                continue;
            } else if (header < 0) {
                if (rowInd >= rowData.len) {
                    return error.BadRowData;
                }
                const byte = rowData[rowInd];
                rowInd += 1;
                const repeats = 1 - @intCast(i16, header);
                var i: usize = 0;
                while (i < repeats) : ({i += 1; x += 1;}) {
                    if (x < sliceSrc.topLeft.x or x >= srcMax.x) continue;
                    const xOut = x - sliceSrc.topLeft.x + sliceDst.topLeft.x;
                    const outIndex = (yOut * buf.size.x + xOut) * buf.channels + channelOffset;
                    buf.data[outIndex] = byte;
                }
            } else if (header >= 0) {
                const n = 1 + @intCast(u16, header);
                if (rowInd + n > rowData.len) {
                    return error.BadRowData;
                }

                var i: usize = 0;
                while (i < n) : ({i += 1; x += 1;}) {
                    const byte = rowData[rowInd + i];
                    if (x < sliceSrc.topLeft.x or x >= srcMax.x) continue;
                    const xOut = x - sliceSrc.topLeft.x + sliceDst.topLeft.x;
                    const outIndex = (yOut * buf.size.x + xOut) * buf.channels + channelOffset;
                    buf.data[outIndex] = byte;
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

        const ptr = @ptrCast(*const T, &self.data[self.index]);
        self.index += size;
        return ptr;
    }

    fn readInt(self: *Self, comptime T: type) !T
    {
        const size = @sizeOf(T);
        if (!self.hasRemaining(size)) {
            return error.OutOfBounds;
        }

        const value = std.mem.readIntBig(T, &self.data[self.index]);
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
