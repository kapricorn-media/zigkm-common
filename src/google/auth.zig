pub const AuthType = enum {
    apiKey
};

pub const AuthData = union(AuthType) {
    apiKey: []const u8,
};
