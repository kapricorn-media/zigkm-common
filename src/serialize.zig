const std = @import("std");

const OOM = std.mem.Allocator.Error;
const EOS = error {EndOfStream};
const SERIAL_ENDIANNESS = std.builtin.Endian.little;
const VERSION: u8 = 0;

pub fn serializeAlloc(comptime T: type, ptr: *const T, allocator: std.mem.Allocator) OOM![]const u8
{
    var bytes = std.ArrayList(u8).init(allocator);
    errdefer bytes.deinit();
    try serialize(T, ptr, bytes.writer());
    return bytes.toOwnedSlice();
}

pub fn deserializeBuf(comptime T: type, buf: []const u8, allocator: std.mem.Allocator) (EOS || OOM)!T
{
    var bufStream = std.io.fixedBufferStream(buf);
    return deserializeValue(T, bufStream.reader(), allocator);
}

pub fn deserializeValue(comptime T: type, reader: anytype, allocator: std.mem.Allocator) (@TypeOf(reader).Error || EOS || OOM)!T
{
    var t: T = undefined;
    try deserialize(T, reader, allocator, &t);
    return t;
}

pub fn serialize(comptime T: type, ptr: *const T, writer: anytype) @TypeOf(writer).Error!void
{
    try writer.writeByte(VERSION);
    try serializeAny(T, ptr, writer);
}

pub fn deserialize(comptime T: type, reader: anytype, allocator: std.mem.Allocator, ptr: *T) (@TypeOf(reader).Error || EOS || OOM)!void
{
    const version = try reader.readByte();
    _ = version;
    try deserializeAny(T, reader, allocator, ptr);
}

fn serializeAny(comptime T: type, ptr: *const T, writer: anytype) @TypeOf(writer).Error!void
{
    const typeInfo = @typeInfo(T);
    switch (typeInfo) {
        .Bool => {
            try writer.writeByte(if (ptr.*) 1 else 0);
        },
        .Int => |ti| {
            const IntType = getIntTypePad(ti.signedness, ti.bits);
            try writer.writeInt(IntType, ptr.*, SERIAL_ENDIANNESS);
        },
        .Float => {
            try writer.writeAll(std.mem.asBytes(ptr));
        },
        .Vector => |ti| {
            for (0..ti.len) |i| {
                try serializeAny(ti.child, &ptr[i], writer);
            }
        },
        .Array => |ti| {
            for (0..ti.len) |i| {
                try serializeAny(ti.child, &ptr[i], writer);
            }
        },
        .Struct => |ti| {
            switch (ti.layout) {
                .auto, .@"extern" => {
                    inline for (ti.fields) |f| {
                        if (comptime shouldSerializeField(f)) {
                            // const field = @field(ptr.*, f.name);
                            try serializeAny(f.type, &@field(ptr.*, f.name), writer);
                        }
                    }
                },
                .@"packed" => {
                    try writer.writeInt(ti.backing_integer.?, @bitCast(ptr.*), SERIAL_ENDIANNESS);
                },
            }
        },
        .Enum => |ti| {
            try writer.writeInt(ti.tag_type, @intFromEnum(ptr.*), SERIAL_ENDIANNESS);
        },
        .Union => |ti| {
            if (ti.layout != .auto) {
                @compileLog("Unsupported union layout", ti.layout);
            }
            const tagType = ti.tag_type orelse @compileLog("Unsupported untagged union");
            const tag = std.meta.activeTag(ptr.*);
            try serializeAny(tagType, &tag, writer);
            switch (tag) {
                inline else => |tagValue| {
                    const PayloadType = @TypeOf(@field(ptr.*, @tagName(tagValue)));
                    try serializeAny(PayloadType, &@field(ptr.*, @tagName(tagValue)), writer);
                }
            }
        },
        .Pointer => |ti| {
            if (ti.size != .Slice) {
                @compileLog("Unsupported type", T);
            }
            try writer.writeInt(u64, ptr.len, SERIAL_ENDIANNESS);
            const tiChild = @typeInfo(ti.child);
            if (tiChild == .Int and tiChild.Int.bits == 8) {
                if (ptr.len > 0) {
                    try writer.writeAll(ptr.*);
                }
            } else {
                for (0..ptr.len) |i| {
                    try serializeAny(ti.child, &ptr.*[i], writer);
                }
            }
        },
        .Optional => |ti| {
            try writer.writeByte(if (ptr.* == null) 0 else 1);
            if (ptr.*) |value| {
                try serializeAny(ti.child, &value, writer);
            }
        },
        else => {
            @compileLog("Unsupported type", T);
        },
    }
}

/// Allocator is required for slices. Another option is to require deserialization from a full in-memory buffer.
fn deserializeAny(comptime T: type, reader: anytype, allocator: std.mem.Allocator, ptr: *T) (@TypeOf(reader).Error || EOS || OOM)!void
{
    const typeInfo = @typeInfo(T);
    switch (typeInfo) {
        .Bool => {
            const byte = try reader.readByte();
            ptr.* = byte != 0;
        },
        .Int => |ti| {
            const IntType = getIntTypePad(ti.signedness, ti.bits);
            const value = try reader.readInt(IntType, SERIAL_ENDIANNESS);
            ptr.* = @intCast(value);
        },
        .Float => {
            try readExactly(reader, std.mem.asBytes(ptr));
        },
        .Vector => |ti| {
            // TODO optimize bool Vector?
            for (0..ti.len) |i| {
                try deserializeAny(ti.child, reader, allocator, &ptr[i]);
            }
        },
        .Array => |ti| {
            for (0..ti.len) |i| {
                try deserializeAny(ti.child, reader, allocator, &ptr[i]);
            }
        },
        .Struct => |ti| {
            switch (ti.layout) {
                .auto, .@"extern" => {
                    inline for (ti.fields) |f| {
                        if (comptime shouldSerializeField(f)) {
                            try deserializeAny(f.type, reader, allocator, &@field(ptr.*, f.name));
                        }
                    }
                },
                .@"packed" => {
                    ptr.* = @bitCast(try reader.readInt(ti.backing_integer.?, SERIAL_ENDIANNESS));
                },
            }
        },
        .Enum => |ti| {
            ptr.* = @enumFromInt(try reader.readInt(ti.tag_type, SERIAL_ENDIANNESS));
        },
        .Union => |ti| {
            if (ti.layout != .auto) {
                @compileLog("Unsupported union layout", ti.layout);
            }
            const tagType = ti.tag_type orelse @compileLog("Unsupported untagged union");
            var tag: tagType = undefined;
            try deserializeAny(tagType, reader, &tag, allocator);
            switch (tag) {
                inline else => |tagValue| {
                    ptr.* = @unionInit(T, @tagName(tagValue), undefined);
                    const PayloadType = @TypeOf(@field(ptr.*, @tagName(tagValue)));
                    try deserializeAny(PayloadType, reader, &@field(ptr.*, @tagName(tagValue)), allocator);
                }
            }
        },
        .Pointer => |ti| {
            if (ti.size != .Slice) {
                @compileLog("Unsupported type", T);
            }
            const len = try reader.readInt(u64, SERIAL_ENDIANNESS);
            ptr.* = try allocator.alloc(ti.child, @intCast(len));
            const tiChild = @typeInfo(ti.child);
            if (tiChild == .Int and tiChild.Int.bits == 8) {
                if (ptr.len > 0) {
                    const readBytes = try reader.read(@constCast(ptr.*));
                    if (readBytes != ptr.len) {
                        return error.EndOfStream;
                    }
                }
            } else {
                for (ptr.*) |*element| {
                    try deserializeAny(ti.child, reader, allocator, @constCast(element));
                }
            }
        },
        .Optional => |ti| {
            const nullByte = try reader.readByte();
            if (nullByte == 0) {
                ptr.* = null;
            } else {
                var v: ti.child = undefined;
                try deserializeAny(ti.child, reader, allocator, &v);
                ptr.* = v;
            }
        },
        else => {
            @compileLog("Unsupported type", T);
        },
    }
}

fn getIntTypePad(comptime signedness: std.builtin.Signedness, comptime bits: comptime_int) type
{
    if (bits <= 8) {
        return if (signedness == .signed) i8 else u8;
    } else if (bits <= 16) {
        return if (signedness == .signed) i16 else u16;
    } else if (bits <= 32) {
        return if (signedness == .signed) i32 else u32;
    } else if (bits <= 64) {
        return if (signedness == .signed) i64 else u64;
    } else {
        unreachable;
    }
}

fn shouldSerializeField(comptime field: std.builtin.Type.StructField) bool
{
    return !std.mem.startsWith(u8, field.name, "ns_");
}

fn readExactly(reader: anytype, buffer: []u8) !void
{
    const size = try reader.readAll(buffer);
    if (size != buffer.len) {
        return error.EndOfStream;
    }
}

test "serializeAny/deserializeAny"
{
    const Test = struct {
        countryCode: u16,
        number: []const u8,
    };
    const TestType = struct {
        id: u64,
        firstName: []const u8,
        lastName: []const u8,
        address: ?[]const u8,
        phones: ?[]const Test,
    };

    const TestCase = struct {
        value: TestType,
        expected: []const u8,
    };
    const cases = [_]TestCase {
        .{
            .value = .{
                .id = 0,
                .firstName = "Jeanne",
                .lastName = "Iron Maiden",
                .address = null,
                .phones = null,
            },
            .expected = "\x00"
                ++ "\x00\x00\x00\x00\x00\x00\x00\x00"
                ++ "\x06\x00\x00\x00\x00\x00\x00\x00Jeanne"
                ++ "\x0B\x00\x00\x00\x00\x00\x00\x00Iron Maiden"
                ++ "\x00"
                ++ "\x00",
        },
        .{
            .value = .{
                .id = 0x2DDF19F23081A90,
                .firstName = "Uvuvuevuevue Onyetuenwuevue",
                .lastName = "Ugbemugbem Ossas",
                .address = "Edo State, Nigeria",
                .phones = null,
            },
            .expected = "\x00"
                ++ "\x90\x1A\x08\x23\x9F\xF1\xDD\x02"
                ++ "\x1B\x00\x00\x00\x00\x00\x00\x00Uvuvuevuevue Onyetuenwuevue"
                ++ "\x10\x00\x00\x00\x00\x00\x00\x00Ugbemugbem Ossas"
                ++ "\x01\x12\x00\x00\x00\x00\x00\x00\x00Edo State, Nigeria"
                ++ "\x00",
        },
        .{
            .value = .{
                .id = 0,
                .firstName = "Chrollo",
                .lastName = "Lucilfer!",
                .address = "Greed Island?",
                .phones = &[_]Test {
                    .{.countryCode = 0x1234, .number = "1234578idifaisdjf"},
                    .{.countryCode = std.math.maxInt(u16), .number = "109230202905412"},
                },
            },
            .expected = "\x00"
                ++ "\x00\x00\x00\x00\x00\x00\x00\x00"
                ++ "\x07\x00\x00\x00\x00\x00\x00\x00Chrollo"
                ++ "\x09\x00\x00\x00\x00\x00\x00\x00Lucilfer!"
                ++ "\x01\x0D\x00\x00\x00\x00\x00\x00\x00Greed Island?"
                ++ "\x01\x02\x00\x00\x00\x00\x00\x00\x00"
                ++ "\x34\x12\x11\x00\x00\x00\x00\x00\x00\x001234578idifaisdjf"
                ++ "\xff\xff\x0F\x00\x00\x00\x00\x00\x00\x00109230202905412",
        },
    };

    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    for (cases) |c| {
        const bytes = try serializeAlloc(TestType, &c.value, allocator);
        defer allocator.free(bytes);
        try std.testing.expectEqualSlices(u8, c.expected, bytes);

        const deserialized = try deserializeBuf(TestType, bytes, arena.allocator());
        try std.testing.expectEqualDeep(c.value, deserialized);
    }
}
