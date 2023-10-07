pub const UserRecord = struct {
    id: u64,
    email: []const u8,
    username: ?[]const u8,
    dataPublic: []const u8,
    passwordSalt: u64,
    passwordHash: []const u8, // 128 bytes
    encryptSalt: u64,
    encryptKey: []const u8, // this key is itself encrypted
    dataPrivate: []const u8,
};
