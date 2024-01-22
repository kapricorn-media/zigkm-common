const std = @import("std");

const OOM = std.mem.Allocator.Error;
const EOS = error {EndOfStream};

pub const VERSION: u8 = 0;

pub fn serialize(comptime T: type, value: T, writer: anytype) @TypeOf(writer).Error!void
{
    try writer.writeByte(VERSION);
    try serializeInternal(T, value, writer);
}

pub fn serializeAlloc(comptime T: type, value: T, allocator: std.mem.Allocator) OOM![]const u8
{
    var bytes = std.ArrayList(u8).init(allocator);
    errdefer bytes.deinit();
    try serialize(T, value, bytes.writer());
    return bytes.toOwnedSlice();
}

pub fn deserialize(comptime T: type, reader: anytype, allocator: std.mem.Allocator) (@TypeOf(reader).Error || EOS || OOM)!T
{
    const version = try reader.readByte();
    std.debug.assert(version == VERSION);
    return deserializeInternal(T, reader, allocator);
}

pub fn deserializeBuf(comptime T: type, buf: []const u8, allocator: std.mem.Allocator) (EOS || OOM)!T
{
    var bufStream = std.io.fixedBufferStream(buf);
    return deserialize(T, bufStream.reader(), allocator);
}

fn serializeInternal(comptime T: type, value: T, writer: anytype) @TypeOf(writer).Error!void
{
    std.log.info("{}\n{any}", .{T, value});
    switch (@typeInfo(T)) {
        .Bool => {
            try writer.writeByte(if (value) 1 else 0);
        },
        .Int => {
            try writer.writeInt(T, value, .little);
        },
        .Pointer => |ti| {
            if (ti.size != .Slice) {
                @compileLog("Unsupported non-slice pointer", ti);
            }
            const tiChild = @typeInfo(ti.child);
            if (tiChild == .Int and tiChild.Int.bits == 8) {
                try writer.writeInt(u64, value.len, .little);
                if (value.len > 0) {
                    try writer.writeAll(value);
                }
            } else {
                try writer.writeInt(u64, value.len, .little);
                for (value) |v| {
                    try serializeInternal(ti.child, v, writer);
                }
            }
        },
        .Struct => |ti| {
            inline for (ti.fields) |f| {
                try serializeInternal(f.type, @field(value, f.name), writer);
            }
        },
        .Optional => |ti| {
            try writer.writeByte(if (value == null) 0 else 1);
            if (value) |v| {
                try serializeInternal(ti.child, v, writer);
            }
        },
        else => @compileLog("Unsupported type", T),
    }
}

fn deserializeInternal(comptime T: type, reader: anytype, allocator: std.mem.Allocator) (@TypeOf(reader).Error || EOS || OOM)!T
{
    std.log.info("{}", .{T});
    switch (@typeInfo(T)) {
        .Bool => {
            const byte = try reader.readByte();
            return byte != 0;
        },
        .Int => {
            return reader.readInt(T, .little);
        },
        .Pointer => |ti| {
            if (ti.size != .Slice) {
                @compileLog("Unsupported non-slice pointer", ti);
            }
            const tiChild = @typeInfo(ti.child);
            if (tiChild == .Int and tiChild.Int.bits == 8) {
                const numBytes = try reader.readInt(u64, .little);
                if (numBytes > 0) {
                    const bytes = try allocator.alloc(u8, @intCast(numBytes));
                    const readBytes = try reader.read(bytes);
                    if (readBytes != numBytes) {
                        return error.EndOfStream;
                    }
                    return bytes;
                } else {
                    return "";
                }
            } else {
                const n = try reader.readInt(u64, .little);
                if (n > 0) {
                    const slice = try allocator.alloc(ti.child, @intCast(n));
                    for (slice) |*v| {
                        v.* = try deserializeInternal(ti.child, reader, allocator);
                    }
                    return slice;
                } else {
                    return @alignCast(@constCast(std.mem.bytesAsSlice(ti.child, "")));
                }
            }
        },
        .Struct => |ti| {
            var t: T = undefined;
            inline for (ti.fields) |f| {
                @field(t, f.name) = try deserializeInternal(f.type, reader, allocator);
            }
            return t;
        },
        .Optional => |ti| {
            const nullByte = try reader.readByte();
            if (nullByte == 0) {
                return null;
            } else {
                return try deserializeInternal(ti.child, reader, allocator);
            }
        },
        else => @compileLog("Unsupported type", T),
    }
}

test "serialize/deserialize"
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
        const bytes = try serializeAlloc(TestType, c.value, allocator);
        defer allocator.free(bytes);
        try std.testing.expectEqualSlices(u8, c.expected, bytes);

        const deserialized = try deserializeBuf(TestType, bytes, arena.allocator());
        try std.testing.expectEqualDeep(c.value, deserialized);
    }
}
