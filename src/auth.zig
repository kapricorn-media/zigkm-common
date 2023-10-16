const std = @import("std");

const serialize = @import("serialize.zig");

const OOM = std.mem.Allocator.Error;

pub const RegisterError = OOM || error {
    Exists,
    ExistsUnconfirmed,
};

pub const State = struct {
    arena: std.heap.ArenaAllocator,
    users: std.ArrayList(UserRecord),
    usersUnconfirmed: std.ArrayList(UserRecord),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self
    {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .users = std.ArrayList(UserRecord).init(allocator),
            .usersUnconfirmed = std.ArrayList(UserRecord).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void
    {
        self.arena.deinit();
        self.users.deinit();
        self.usersUnconfirmed.deinit();
    }

    pub fn save(self: *const Self, path: []const u8) !void
    {
        var f = try std.fs.cwd().createFile(path, .{});
        defer f.close();

        try serialize.serialize([]UserRecord, self.users.items, f.writer());
    }

    pub fn load(self: *Self, path: []const u8) !void
    {
        var f = try std.fs.cwd().openFile(path, .{});
        defer f.close();

        const usersLoaded = try serialize.deserialize([]UserRecord, f.reader(), self.arena.allocator());
        self.users.clearRetainingCapacity();
        try self.users.appendSlice(usersLoaded);
    }

    pub fn authenticate(self: *Self, email: []const u8, password: []const u8) bool
    {
        const userRecord = getUserRecord(email, self.users.items) orelse return false;
        _ = userRecord;
        _ = password;
        return true;
    }

    /// True on success
    pub fn register(self: *Self, params: RegisterParams) RegisterError!void
    {
        if (getUserRecord(params.email, self.users.items) != null) {
            return error.Exists;
        }
        if (getUserRecord(params.email, self.usersUnconfirmed.items) != null) {
            return error.ExistsUnconfirmed;
        }

        const userRecord = try fillUserRecord(params, self.arena.allocator());
        try self.users.append(userRecord);
    }
};

pub const UserRecord = struct {
    id: u64,
    email: []const u8,
    username: ?[]const u8,
    dataPublic: []u8,
    passwordSalt: u64,
    passwordHash: []const u8, // 128 bytes
    encryptSalt: u64,
    encryptKey: []const u8, // this key is itself encrypted
    dataPrivate: []u8,
};

pub const RegisterParams = struct {
    email: []const u8,
    username: ?[]const u8,
    password: []const u8,
    dataPublic: []u8,
    dataPrivate: []u8,
};

fn fillUserRecord(params: RegisterParams, allocator: std.mem.Allocator) OOM!UserRecord
{
    return .{
        .id = 0,
        .email = try allocator.dupe(u8, params.email),
        .username = null,
        .dataPublic = try allocator.dupe(u8, params.dataPublic),
        .passwordSalt = 0,
        .passwordHash = "",
        .encryptSalt = 0,
        .encryptKey = "",
        .dataPrivate = "",
    };
}

fn getUserRecord(email: []const u8, userRecords: []UserRecord) ?*UserRecord
{
    for (userRecords) |*user| {
        if (std.mem.eql(u8, user.email, email)) {
            return user;
        }
    }
    return null;
}
