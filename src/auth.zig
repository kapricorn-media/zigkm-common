const std = @import("std");

const google = @import("zigkm-google");

const serialize = @import("serialize.zig");

const OOM = std.mem.Allocator.Error;

pub const PwHashError = error {PwHashError};
pub const LoginError = OOM || error {
    NoUser,
    WrongPassword,
    NotVerified,
};
pub const VerifyError = OOM || PwHashError || error {
    NoEmail,
    NoVerifyData,
    BadVerify,
};
pub const CreateVerifyError = OOM || PwHashError;
pub const RegisterError = OOM || PwHashError || error {
    Exists,
    EmailVerifySendError,
};

const pwHashParams = std.crypto.pwhash.argon2.Params { .t = 50, .m = 4096, .p = 2 };

pub const Session = struct {
    user: []const u8,
    expirationUtcS: i64,
};

pub const VerifyData = struct {
    guidHash: []const u8,
    expirationUtcS: i64,
};

pub const State = struct {
    arena: std.heap.ArenaAllocator,
    users: std.ArrayList(UserRecord),
    sessions: std.AutoArrayHashMap(u64, Session),
    verifies: std.StringArrayHashMap(VerifyData),
    plainRandom: std.rand.DefaultPrng,
    cryptoRandom: std.rand.DefaultCsprng,
    sessionDurationS: i64,
    emailVerifyExpirationS: i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, sessionDurationS: i64, emailVerifyExpirationS: i64) Self
    {
        const seedPrng = std.crypto.random.int(u64);
        var seedCsprng: [32]u8 = undefined;
        std.crypto.random.bytes(&seedCsprng);

        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .users = std.ArrayList(UserRecord).init(allocator),
            .sessions = std.AutoArrayHashMap(u64, Session).init(allocator),
            .verifies = std.StringArrayHashMap(VerifyData).init(allocator),
            .plainRandom = std.rand.DefaultPrng.init(seedPrng),
            .cryptoRandom = std.rand.DefaultCsprng.init(seedCsprng),
            .sessionDurationS = sessionDurationS,
            .emailVerifyExpirationS = emailVerifyExpirationS,
        };
    }

    pub fn deinit(self: *Self) void
    {
        self.arena.deinit();
        self.users.deinit();
        self.sessions.deinit();
        self.verifies.deinit();
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

    pub fn getUserRecord(self: *Self, user: []const u8) ?*UserRecord
    {
        return searchUserRecord(user, self.users.items);
    }

    pub fn isLoggedIn(self: *Self, sessionId: u64) bool
    {
        var sessionData = self.sessions.get(sessionId) orelse return false;
        const now = std.time.timestamp();
        if (now >= sessionData.expirationUtcS) {
            if (!self.sessions.swapRemove(sessionId)) {
                std.log.err("Failed to clear session", .{});
            }
            return false;
        }
        return true;
    }

    pub fn login(self: *Self, user: []const u8, password: []const u8, mustBeVerified: bool, tempAllocator: std.mem.Allocator) LoginError!u64
    {
        const userRecord = searchUserRecord(user, self.users.items) orelse return error.NoUser;
        if (mustBeVerified and !userRecord.emailVerified) {
            return error.NotVerified;
        }
        std.crypto.pwhash.argon2.strVerify(userRecord.passwordHash, password, .{.allocator = tempAllocator}) catch return error.WrongPassword;

        const sessionId = self.cryptoRandom.random().int(u64);
        const session = Session {
            .user = try self.arena.allocator().dupe(u8, user),
            .expirationUtcS = std.time.timestamp() + self.sessionDurationS,
        };
        try self.sessions.put(sessionId, session);

        std.log.info("LOGGED IN {s}", .{user});
        return sessionId;
    }

    pub fn logoff(self: *Self, sessionId: u64) void
    {
        var sessionData = self.sessions.get(sessionId) orelse {
            std.log.warn("Logoff with no session", .{});
            return;
        };
        if (!self.sessions.swapRemove(sessionId)) {
            std.log.warn("Failed to clear session {}", .{sessionId});
        }

        std.log.info("LOGGED OFF {s}", .{sessionData.user});
    }

    pub fn register(self: *Self, params: RegisterParams, dataPublic: anytype, dataPrivate: anytype, comptime emailFmt: []const u8, verifyUrlBase: []const u8, verifyPath: []const u8, gmailClient: *google.gmail.Client, tempAllocator: std.mem.Allocator) RegisterError!void
    {
        if (searchUserRecord(params.user, self.users.items) != null) {
            return error.Exists;
        }

        const userRecord = try fillUserRecord(params, dataPublic, dataPrivate, self.cryptoRandom.random(), self.arena.allocator());
        try self.users.append(userRecord);

        std.log.info("REGISTERED {s}", .{userRecord.user});

        if (userRecord.email) |email| {
            const guid = try self.createVerifyRecord(email);
            const emailBody = try std.fmt.allocPrint(tempAllocator, emailFmt, .{
                verifyUrlBase, verifyPath, guid, email,
            });

            gmailClient.send("Update App", email, null, "Email Verification", emailBody) catch |err| {
                std.log.err("gmailClient send error {}", .{err});
                return error.EmailVerifySendError;
            };

            std.log.info("VERIFICATION SENT {s}", .{email});
        }
    }

    pub fn unregister(self: *Self, user: []const u8) void
    {
        // Remove all sessions for this user
        while (true) {
            var it = self.sessions.iterator();
            var toDelete: ?u64 = null;
            while (it.next()) |s| {
                if (std.mem.eql(u8, s.value_ptr.user, user)) {
                }
            }
            if (toDelete) |sessionId| {
                _ = self.sessions.swapRemove(sessionId);
            } else {
                break;
            }
        }
        _ = self.verifies.swapRemove(user);

        var toDelete: ?usize = null;
        for (self.users.items, 0..) |u, i| {
            if (std.mem.eql(u8, u.user, user)) {
                toDelete = i;
                break;
            }
        }
        if (toDelete) |i| {
            _ = self.users.swapRemove(i);
        } else {
            std.log.err("User to unregister not found {s}", .{user});
        }

        std.log.info("UNREGISTERED {s}", .{user});
    }

    pub fn verify(self: *Self, email: []const u8, guid: u64, tempAllocator: std.mem.Allocator) VerifyError!void
    {
        const userRecord = searchUserRecordByEmail(email, self.users.items) orelse return error.NoEmail;
        if (userRecord.emailVerified) {
            return;
        }

        var verifyData = self.verifies.get(email) orelse return error.NoVerifyData;
        const guidBytes = std.mem.toBytes(guid);
        std.crypto.pwhash.argon2.strVerify(verifyData.guidHash, &guidBytes, .{.allocator = tempAllocator}) catch return error.BadVerify;

        _ = self.verifies.swapRemove(email);

        userRecord.emailVerified = true;

        std.log.info("VERIFIED {s}", .{email});
    }

    /// `email` will not be copied, so it should come from a persistent UserRecord struct.
    fn createVerifyRecord(self: *Self, email: []const u8) CreateVerifyError!u64
    {
        const allocator = self.arena.allocator();

        const guid = self.cryptoRandom.random().int(u64);

        var hashBuf = try allocator.alloc(u8, 128);
        const hash = std.crypto.pwhash.argon2.strHash(&std.mem.toBytes(guid), .{
            .allocator = allocator,
            .params = pwHashParams,
        }, hashBuf) catch return error.PwHashError;
        const expiration = std.time.timestamp() + self.emailVerifyExpirationS;

        try self.verifies.put(email, .{
            .guidHash = hash,
            .expirationUtcS = expiration,
        });

        std.log.info("PENDING VERIFICATION {s}", .{email});

        return guid;
    }
};

pub const UserRecord = struct {
    id: u64,
    user: []const u8,
    email: ?[]const u8,
    emailVerified: bool,
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

fn fillUserRecord(params: RegisterParams, dataPublic: anytype, dataPrivate: anytype, random: std.rand.Random, allocator: std.mem.Allocator) (OOM || PwHashError)!UserRecord
{
    var hashBuf = try allocator.alloc(u8, 128);
    const hash = std.crypto.pwhash.argon2.strHash(params.password, .{
        .allocator = allocator,
        .params = pwHashParams,
    }, hashBuf) catch return error.PwHashError;

    const dataPublicBytes = try serialize.serializeAlloc(@TypeOf(dataPublic), dataPublic, allocator);
    const dataPrivateBytes = try serialize.serializeAlloc(@TypeOf(dataPrivate), dataPrivate, allocator);
    // TODO encrypt private data

    return .{
        .id = random.int(u64),
        .user = try allocator.dupe(u8, params.user),
        .email = if (params.email) |e| try allocator.dupe(u8, e) else null,
        .emailVerified = false,
        .dataPublic = dataPublicBytes,
        .passwordHash = hash,
        .encryptSalt = 0,
        .encryptKey = "",
        .dataPrivate = dataPrivateBytes,
    };
}

fn searchUserRecord(user: []const u8, userRecords: []UserRecord) ?*UserRecord
{
    for (userRecords) |*record| {
        if (std.mem.eql(u8, record.user, user)) {
            return record;
        }
    }
    return null;
}

fn searchUserRecordByEmail(email: []const u8, userRecords: []UserRecord) ?*UserRecord
{
    for (userRecords) |*record| {
        if (record.email) |e| {
            if (std.mem.eql(u8, e, email)) {
                return record;
            }
        }
    }
    return null;
}
