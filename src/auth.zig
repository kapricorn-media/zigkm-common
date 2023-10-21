const std = @import("std");

const serialize = @import("serialize.zig");

const OOM = std.mem.Allocator.Error;

pub const PwHashError = error {PwHashError};
pub const RegisterError = OOM || PwHashError || error {
    Exists,
    ExistsUnconfirmed,
};

pub const Session = struct {
    id: u64,
    user: []const u8,
    expirationUtcS: i64,
};

pub const State = struct {
    arena: std.heap.ArenaAllocator,
    users: std.ArrayList(UserRecord),
    usersUnconfirmed: std.ArrayList(UserRecord),
    sessions: std.AutoArrayHashMap(u64, Session),
    plainRandom: std.rand.DefaultPrng,
    cryptoRandom: std.rand.DefaultCsprng,
    sessionDurationS: i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, sessionDurationS: i64) Self
    {
        const seedPrng = std.crypto.random.int(u64);
        var seedCsprng: [32]u8 = undefined;
        std.crypto.random.bytes(&seedCsprng);

        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .users = std.ArrayList(UserRecord).init(allocator),
            .usersUnconfirmed = std.ArrayList(UserRecord).init(allocator),
            .sessions = std.AutoArrayHashMap(u64, Session).init(allocator),
            .plainRandom = std.rand.DefaultPrng.init(seedPrng),
            .cryptoRandom = std.rand.DefaultCsprng.init(seedCsprng),
            .sessionDurationS = sessionDurationS,
        };
    }

    pub fn deinit(self: *Self) void
    {
        self.arena.deinit();
        self.users.deinit();
        self.usersUnconfirmed.deinit();
        self.sessions.deinit();
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

    pub fn login(self: *Self, user: []const u8, password: []const u8, tempAllocator: std.mem.Allocator) !u64
    {
        const userRecord = getUserRecord(user, self.users.items) orelse return error.NoUser;
        try std.crypto.pwhash.argon2.strVerify(userRecord.passwordHash, password, .{.allocator = tempAllocator});

        const session = Session {
            .id = self.cryptoRandom.random().int(u64),
            .user = try self.arena.allocator().dupe(u8, user),
            .expirationUtcS = std.time.timestamp() + self.sessionDurationS,
        };
        try self.sessions.put(session.id, session);

        std.log.info("LOGGED IN {s}", .{user});
        return session.id;
    }

    pub fn logoff(self: *Self, sessionId: u64) !void
    {
        var sessionData = self.sessions.get(sessionId) orelse {
            return error.NoSession;
        };
        if (!self.sessions.remove(sessionId)) {
            std.log.warn("Failed to clear session {}", .{sessionId});
        }

        std.log.info("LOGGED OFF {s}", .{sessionData.user});
    }

    /// True on success
    pub fn register(self: *Self, params: RegisterParams, dataPublic: anytype, dataPrivate: anytype) RegisterError!void
    {
        if (getUserRecord(params.user, self.users.items) != null) {
            return error.Exists;
        }
        if (getUserRecord(params.user, self.usersUnconfirmed.items) != null) {
            return error.ExistsUnconfirmed;
        }

        const userRecord = try fillUserRecord(params, dataPublic, dataPrivate, self.arena.allocator());
        try self.users.append(userRecord);
    }
};

pub const UserRecord = struct {
    id: u64,
    user: []const u8,
    email: ?[]const u8,
    dataPublic: []const u8,
    passwordHash: []const u8, // 128 bytes
    encryptSalt: u64,
    encryptKey: []const u8, // this key is itself encrypted
    dataPrivate: []const u8,
};

pub const RegisterParams = struct {
    user: []const u8,
    email: ?[]const u8,
    password: []const u8,
};

fn fillUserRecord(params: RegisterParams, dataPublic: anytype, dataPrivate: anytype, allocator: std.mem.Allocator) (OOM || PwHashError)!UserRecord
{
    var hashBuf = try allocator.alloc(u8, 128);
    const hash = std.crypto.pwhash.argon2.strHash(params.password, .{
        .allocator = allocator,
        .params = .{.t = 50, .m = 4096, .p = 2},
    }, hashBuf) catch return error.PwHashError;

    const dataPublicBytes = try serialize.serializeAlloc(@TypeOf(dataPublic), dataPublic, allocator);
    const dataPrivateBytes = try serialize.serializeAlloc(@TypeOf(dataPrivate), dataPrivate, allocator);
    // TODO encrypt private data

    return .{
        .id = 0,
        .user = try allocator.dupe(u8, params.user),
        .email = if (params.email) |e| try allocator.dupe(u8, e) else null,
        .dataPublic = dataPublicBytes,
        .passwordHash = hash,
        .encryptSalt = 0,
        .encryptKey = "",
        .dataPrivate = dataPrivateBytes,
    };
}

fn getUserRecord(user: []const u8, userRecords: []UserRecord) ?*UserRecord
{
    for (userRecords) |*record| {
        if (std.mem.eql(u8, record.user, user)) {
            return record;
        }
    }
    return null;
}
