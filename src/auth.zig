const std = @import("std");

const google = @import("zigkm-google");
const httpz = @import("httpz");
const platform = @import("zigkm-platform");
const serialize = @import("zigkm-serialize");

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

pub const UserRecord = struct {
    id: u64,
    user: []const u8,
    email: ?[]const u8,
    emailVerified: bool,
    data: []const u8,
    passwordHash: []const u8, // 128 bytes
    encryptSalt: u64,
    encryptKey: []const u8, // this key is itself encrypted
    dataEncrypted: []const u8,
};

pub const RegisterParams = struct {
    user: []const u8,
    email: ?[]const u8,
    password: []const u8,
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

    const SessionEntry = struct {
        id: u64,
        session: Session,
    };

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

    pub fn save(self: *const Self, path: []const u8, tempAllocator: std.mem.Allocator) !void
    {
        var sessions = std.ArrayList(SessionEntry).init(tempAllocator);
        var it = self.sessions.iterator();
        while (it.next()) |s| {
            try sessions.append(.{
                .id = s.key_ptr.*,
                .session = s.value_ptr.*,
            });
        }

        var f = try std.fs.cwd().createFile(path, .{});
        defer f.close();

        try serialize.serialize([]UserRecord, self.users.items, f.writer());
        try serialize.serialize([]SessionEntry, sessions.items, f.writer());
    }

    pub fn load(self: *Self, path: []const u8) !void
    {
        var f = try std.fs.cwd().openFile(path, .{});
        defer f.close();

        const usersLoaded = try serialize.deserialize([]UserRecord, f.reader(), self.arena.allocator());
        self.users.clearRetainingCapacity();
        try self.users.appendSlice(usersLoaded);

        const sessions = try serialize.deserialize([]SessionEntry, f.reader(), self.arena.allocator());
        for (sessions) |s| {
            try self.sessions.put(s.id, s.session);
        }
    }

    pub fn getUserRecord(self: *Self, user: []const u8) ?*UserRecord
    {
        return searchUserRecord(user, self.users.items);
    }

    pub fn getSession(self: *Self, sessionId: u64) ?Session
    {
        const sessionData = self.sessions.get(sessionId) orelse return null;
        const now = std.time.timestamp();
        if (now >= sessionData.expirationUtcS) {
            if (!self.sessions.swapRemove(sessionId)) {
                std.log.err("Failed to clear session", .{});
            }
            std.log.info("SESSION EXPIRED", .{});
            return null;
        }
        return sessionData;
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
        const sessionData = self.sessions.get(sessionId) orelse {
            std.log.warn("Logoff with no session", .{});
            return;
        };
        if (!self.sessions.swapRemove(sessionId)) {
            std.log.warn("Failed to clear session {}", .{sessionId});
        }

        std.log.info("LOGGED OFF {s}", .{sessionData.user});
    }

    pub fn register(self: *Self, params: RegisterParams, data: anytype, dataEncrypted: anytype, comptime emailFmt: []const u8, verifyUrlBase: []const u8, verifyPath: []const u8, gmailClient: *google.gmail.Client, tempAllocator: std.mem.Allocator) RegisterError!void
    {
        if (searchUserRecord(params.user, self.users.items) != null) {
            return error.Exists;
        }

        const userRecord = try fillUserRecord(params, data, dataEncrypted, self.cryptoRandom.random(), self.arena.allocator());
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
            const toDelete: ?u64 = null;
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

        const verifyData = self.verifies.get(email) orelse return error.NoVerifyData;
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

        const hashBuf = try allocator.alloc(u8, 128);
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

fn fillUserRecord(params: RegisterParams, data: anytype, dataEncrypted: anytype, random: std.rand.Random, allocator: std.mem.Allocator) (OOM || PwHashError)!UserRecord
{
    const hashBuf = try allocator.alloc(u8, 128);
    const hash = std.crypto.pwhash.argon2.strHash(params.password, .{
        .allocator = allocator,
        .params = pwHashParams,
    }, hashBuf) catch return error.PwHashError;

    const dataBytes = try serialize.serializeAlloc(@TypeOf(data), data, allocator);
    const dataEncryptedBytes = try serialize.serializeAlloc(@TypeOf(dataEncrypted), dataEncrypted, allocator);
    // TODO encrypt

    return .{
        .id = random.int(u64),
        .user = try allocator.dupe(u8, params.user),
        .email = if (params.email) |e| try allocator.dupe(u8, e) else null,
        .emailVerified = false,
        .data = dataBytes,
        .passwordHash = hash,
        .encryptSalt = 0,
        .encryptKey = "",
        .dataEncrypted = dataEncryptedBytes,
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

pub fn parseNewlineStrings(comptime T: type, data: []const u8, allowExtra: bool) !T
{
    var result: T = undefined;
    var splitIt = std.mem.splitScalar(u8, data, '\n');

    const typeInfo = @typeInfo(T);
    inline for (typeInfo.Struct.fields) |f| {
        @field(result, f.name) = splitIt.next() orelse return error.MissingField;
    }
    if (!allowExtra and splitIt.next() != null) {
        return error.ExtraField;
    }
    return result;
}

pub fn getSessionId(req: *httpz.Request) ?u64
{
    // TODO customize cookie? idk, global constant is probably fine
    const sessionIdStr = req.header(platform.SESSION_ID_COOKIE) orelse return null;
    const sessionId = std.fmt.parseUnsigned(u64, sessionIdStr, 16) catch return null;
    return sessionId;
}

const AuthEndpoints = struct {
    login: []const u8 = "/login",
    logout: []const u8 = "/logout",
    register: []const u8 = "/register",
    unregister: []const u8 = "/unregister",
    verify: []const u8 = "/verify_email",
};

pub fn authEndpoints(
    comptime DataPublic: type, comptime DataPrivate: type,
    req: *httpz.Request, res: *httpz.Response,
    state: *State,
    backupPath: []const u8,
    lock: *std.Thread.RwLock,
    dataInitFunc: fn ([]const u8, *DataPublic, *DataPrivate) ?void,
    gmailClient: *google.gmail.Client,
    comptime emailVerifyFmt: []const u8, verifyUrlBase: []const u8,
    endpoints: AuthEndpoints,
    tempAllocator: std.mem.Allocator) !void
{
    const maybeSessionId = getSessionId(req);
    const maybeSession = if (maybeSessionId) |sid| state.getSession(sid) else null;

    if (req.method == .GET) {
        if (std.mem.eql(u8, req.url.path, endpoints.verify)) {
            const queryParams = try req.query();
            const guidString = queryParams.get("guid") orelse {
                std.log.err("Verify missing guid", .{});
                res.status = 400;
                return;
            };
            const guid = std.fmt.parseUnsigned(u64, guidString, 10) catch {
                std.log.err("Verify invalid guid", .{});
                res.status = 400;
                return;
            };
            const email = queryParams.get("email") orelse {
                std.log.err("Verify missing email", .{});
                res.status = 400;
                return;
            };

            lock.unlockShared();
            defer lock.lockShared();
            lock.lock();
            defer lock.unlock();

            state.verify(email, guid, tempAllocator) catch |err| {
                std.log.err("Verify failed {}", .{err});
                res.status = 400;
                return;
            };

            if (!backupAuth(state, backupPath, tempAllocator)) {
                std.log.err("backupAuth failed", .{});
            }

            res.status = 302;
            res.header("Location", "/verified");
        }
    } else if (req.method == .POST) {
        if (std.mem.eql(u8, req.url.path, endpoints.login)) {
            const body = try req.body() orelse {
                res.status = 400;
                return;
            };
            const LoginData = struct {
                email: []const u8,
                password: []const u8,
            };
            const loginData = parseNewlineStrings(LoginData, body, false) catch {
                res.status = 400;
                return;
            };
            if (loginData.email.len == 0) {
                res.status = 400;
                return;
            }

            lock.unlockShared();
            defer lock.lockShared();
            lock.lock();
            defer lock.unlock();

            const sessionId = state.login(loginData.email, loginData.password, true, tempAllocator) catch |err| {
                switch (err) {
                    error.NoUser => {
                        try res.writer().writeAll("user");
                    },
                    error.WrongPassword => {
                        try res.writer().writeAll("password");
                    },
                    error.NotVerified => {
                        try res.writer().writeAll("verify");
                    },
                    else => {},
                }
                res.status = 401;
                return;
            };

            try std.fmt.format(res.writer(), "{x}", .{sessionId});

            if (!backupAuth(state, backupPath, tempAllocator)) {
                std.log.err("backupAuth failed", .{});
            }
        } else if (std.mem.eql(u8, req.url.path, endpoints.logout)) {
            const session = maybeSession orelse {
                res.status = 401;
                return;
            };
            _ = session;
            const sessionId = maybeSessionId orelse {
                res.status = 500;
                return;
            };

            lock.unlockShared();
            defer lock.lockShared();
            lock.lock();
            defer lock.unlock();

            state.logoff(sessionId);

            if (!backupAuth(state, backupPath, tempAllocator)) {
                std.log.err("backupAuth failed", .{});
            }
        } else if (std.mem.eql(u8, req.url.path, endpoints.register)) {
            const body = try req.body() orelse {
                res.status = 400;
                return;
            };
            const RegisterData = struct {
                email: []const u8,
                password: []const u8,
            };
            const registerData = parseNewlineStrings(RegisterData, body, true) catch {
                res.status = 400;
                return;
            };
            if (registerData.email.len == 0) {
                res.status = 400;
                return;
            }
            if (registerData.password.len < 8) {
                res.status = 400;
                return;
            }

            lock.unlockShared();
            defer lock.lockShared();
            lock.lock();
            defer lock.unlock();

            var dataPublic: DataPublic = undefined;
            var dataPrivate: DataPrivate = undefined;
            dataInitFunc(body, &dataPublic, &dataPrivate) orelse {
                res.status = 400;
                return;
            };
            state.register(.{
                .user = registerData.email,
                .email = registerData.email,
                .password = registerData.password,
            }, dataPublic, dataPrivate, emailVerifyFmt, verifyUrlBase, endpoints.verify, gmailClient, tempAllocator) catch |err| {
                switch (err) {
                    error.Exists => {
                        std.log.info("DUPE REGISTER: {s}", .{registerData.email});
                        res.status = 401;
                    },
                    error.EmailVerifySendError, error.PwHashError, error.OutOfMemory => {
                        std.log.err("state.register failed", .{});
                        res.status = 500;
                    },
                }
                return;
            };

            if (!backupAuth(state, backupPath, tempAllocator)) {
                std.log.err("backupAuth failed", .{});
            }
        } else if (std.mem.eql(u8, req.url.path, endpoints.unregister)) {
            const session = maybeSession orelse {
                res.status = 401;
                return;
            };

            lock.unlockShared();
            defer lock.lockShared();
            lock.lock();
            defer lock.unlock();

            // WARNING! This will clobber session. Do not use that variable anymore.
            state.unregister(session.user);
            if (!backupAuth(state, backupPath, tempAllocator)) {
                std.log.err("backupAuth failed", .{});
            }
        }
    }
}

fn backupAuth(authState: *State, path: []const u8, tempAllocator: std.mem.Allocator) bool
{
    const cwd = std.fs.cwd();
    const bakPath = std.fmt.allocPrint(tempAllocator, "{s}.bak", .{path}) catch |err| {
        std.log.err("allocPrint failed during backup err={}", .{err});
        return false;
    };
    cwd.rename(path, bakPath) catch |err| {
        std.log.err("auth state rename failed err={}", .{err});
        return false;
    };
    authState.save(path, tempAllocator) catch |err| {
        std.log.err("authState.save failed err={}", .{err});
        return false;
    };
    return true;
}
