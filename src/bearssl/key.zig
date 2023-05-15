const std = @import("std");

const c = @import("c.zig");
const pem = @import("pem.zig");

pub const RsaPublicKey = struct {
    allocator: std.mem.Allocator,
    key: c.br_rsa_public_key,

    const Self = @This();

    pub fn init(key: *const c.br_rsa_public_key, allocator: std.mem.Allocator) !Self
    {
        var self = Self {
            .allocator = allocator,
            .key = undefined,
        };
        try copyRsaPublicKey(&self.key, key, allocator);
        return self;
    }

    pub fn deinit(self: Self) void
    {
        freeRsaPublicKey(self.key, self.allocator);
    }
};

pub const EcPublicKey = struct {
    allocator: std.mem.Allocator,
    key: c.br_ec_public_key,

    const Self = @This();

    pub fn init(key: *const c.br_ec_public_key, allocator: std.mem.Allocator) !Self
    {
        var self = Self {
            .allocator = allocator,
            .key = undefined,
        };
        try copyEcPublicKey(&self.key, key, allocator);
        return self;
    }

    pub fn deinit(self: Self) void
    {
        freeEcPublicKey(self.key, self.allocator);
    }
};

pub fn copyRsaPublicKey(
    dst: *c.br_rsa_public_key,
    src: *const c.br_rsa_public_key,
    allocator: std.mem.Allocator) !void
{
    try copyBytes(&dst.n, src.n, src.nlen, allocator);
    dst.nlen = src.nlen;
    try copyBytes(&dst.e, src.e, src.elen, allocator);
    dst.elen = src.elen;
}

pub fn freeRsaPublicKey(key: c.br_rsa_public_key, allocator: std.mem.Allocator) void
{
    allocator.free(key.n[0..key.nlen]);
    allocator.free(key.e[0..key.elen]);
}

pub fn copyEcPublicKey(
    dst: *c.br_ec_public_key,
    src: *const c.br_ec_public_key,
    allocator: std.mem.Allocator) !void
{
    dst.curve = src.curve;
    try copyBytes(&dst.q, src.q, src.qlen, allocator);
    dst.qlen = src.qlen;
}

pub fn freeEcPublicKey(key: c.br_ec_public_key, allocator: std.mem.Allocator) void
{
    allocator.free(key.q[0..key.qlen]);
}

pub fn copyPublicKey(
    dst: *c.br_x509_pkey,
    src: *const c.br_x509_pkey,
    allocator: std.mem.Allocator) !void
{
    dst.key_type = src.key_type;
    switch (dst.key_type) {
        c.BR_KEYTYPE_RSA => {
            try copyRsaPublicKey(&dst.key.rsa, &src.key.rsa, allocator);
        },
        c.BR_KEYTYPE_EC => {
            try copyEcPublicKey(&dst.key.ec, &src.key.ec, allocator);
        },
        else => return error.BadKeyType,
    }
}

pub fn freePublicKey(key: c.br_x509_pkey, allocator: std.mem.Allocator) void
{
    switch (key.key_type) {
        c.BR_KEYTYPE_RSA => {
            freeRsaPublicKey(key.key.rsa, allocator);
        },
        c.BR_KEYTYPE_EC => {
            freeEcPublicKey(key.key.ec, allocator);
        },
        else => {},
    }
}

fn copyBytes(dst: *[*c]u8, src: [*]const u8, len: usize, allocator: std.mem.Allocator) !void
{
    const srcSlice = src[0..len];
    const copy = try allocator.dupe(u8, srcSlice);
    dst.* = &copy[0];
}

fn freeBytes(ptr: [*]const u8, len: usize, allocator: std.mem.Allocator) void
{
    const slice = ptr[0..len];
    allocator.free(slice);
}

/// Only supports RSA for now
pub const PrivateKey = struct {
    rsaKey: c.br_rsa_private_key,

    const Self = @This();

    pub fn initFromPem(pemData: []const u8, allocator: std.mem.Allocator) !Self
    {
        var self = Self {
            .rsaKey = undefined,
        };

        var context: c.br_skey_decoder_context = undefined;
        c.br_skey_decoder_init(&context);

        var pemState = PemState {
            .context = &context,
            .pushed = false,
        };
        try pem.decode(pemData, *PemState, &pemState, pemCallback, allocator);

        const err = c.br_skey_decoder_last_error(&context);
        if (err != 0) {
            return error.DecoderError;
        }

        const keyType = c.br_skey_decoder_key_type(&context);
        switch (keyType) {
            c.BR_KEYTYPE_RSA => {
                const rsaKey = c.br_skey_decoder_get_rsa(&context);
                try copyRsaPrivateKey(&self.rsaKey, rsaKey, allocator);
            },
            c.BR_KEYTYPE_EC => return error.UnsupportedEcKeyType,
            else => return error.BadKeyType,
        }

        return self;
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void
    {
        freeRsaPrivateKey(self.rsaKey, allocator);
    }
};

pub fn copyRsaPrivateKey(
    dst: *c.br_rsa_private_key,
    src: *const c.br_rsa_private_key,
    allocator: std.mem.Allocator) !void
{
    dst.n_bitlen = src.n_bitlen;
    try copyBytes(&dst.p, src.p, src.plen, allocator);
    dst.plen = src.plen;
    try copyBytes(&dst.q, src.q, src.qlen, allocator);
    dst.qlen = src.qlen;
    try copyBytes(&dst.dp, src.dp, src.dplen, allocator);
    dst.dplen = src.dplen;
    try copyBytes(&dst.dq, src.dq, src.dqlen, allocator);
    dst.dqlen = src.dqlen;
    try copyBytes(&dst.iq, src.iq, src.iqlen, allocator);
    dst.iqlen = src.iqlen;
}

pub fn freeRsaPrivateKey(key: c.br_rsa_private_key, allocator: std.mem.Allocator) void
{
    allocator.free(key.p[0..key.plen]);
    allocator.free(key.q[0..key.qlen]);
    allocator.free(key.dp[0..key.dplen]);
    allocator.free(key.dq[0..key.dqlen]);
    allocator.free(key.iq[0..key.iqlen]);
}

const PemState = struct {
    context: *c.br_skey_decoder_context,
    pushed: bool,
};

fn pemCallback(state: *PemState, data: []const u8) !void
{
    c.br_skey_decoder_push(state.context, &data[0], data.len);
}
