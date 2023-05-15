const std = @import("std");

const c = @import("c.zig");
const key = @import("key.zig");
const pem = @import("pem.zig");

pub const Anchor = struct {
    anchor: c.br_x509_trust_anchor,

    const Self = @This();

    pub fn init(der: []const u8, allocator: std.mem.Allocator) !Self
    {
        var state = X509State {
            .list = std.ArrayList(u8).init(allocator),
            .success = true,
        };
        defer state.list.deinit();

        var context: c.br_x509_decoder_context = undefined;
        c.br_x509_decoder_init(&context, x509Callback, &state);
        c.br_x509_decoder_push(&context, &der[0], der.len);

        if (!state.success) {
            return error.x509DecodeCallback;
        }
        if (state.list.items.len == 0) {
            return error.NoAnchorData;
        }

        const err = c.br_x509_decoder_last_error(&context);
        if (err != 0) {
            return error.x509Decode;
        }

        var self = Self {
            .anchor = undefined,
        };
        const dn = state.list.toOwnedSlice();
        errdefer allocator.free(dn);
        self.anchor.dn.data = &dn[0];
        self.anchor.dn.len = dn.len;
        self.anchor.flags = @intCast(c_uint, c.br_x509_decoder_isCA(&context));
        const publicKey = c.br_x509_decoder_get_pkey(&context);
        try key.copyPublicKey(&self.anchor.pkey, publicKey, allocator);
        errdefer key.freePublicKey(self.anchor.pkey);

        return self;
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void
    {
        allocator.free(self.anchor.dn.data[0..self.anchor.dn.len]);
        key.freePublicKey(self.anchor.pkey, allocator);
    }
};

const X509State = struct {
    list: std.ArrayList(u8),
    success: bool,
};

fn x509Callback(userData: ?*anyopaque, data: ?*const anyopaque, len: usize) callconv(.C) void
{
    var state = @ptrCast(*X509State, @alignCast(@alignOf(*X509State), userData));
    const bytes = @ptrCast([*]const u8, data);
    const slice = bytes[0..len];
    state.list.appendSlice(slice) catch {
        state.success = false;
    };
}

pub const Anchors = struct {
    anchors: []Anchor,

    const Self = @This();

    pub fn init(pemData: []const u8, allocator: std.mem.Allocator) !Self
    {
        var state = PemAnchorsState {
            .allocator = allocator,
            .list = std.ArrayList(Anchor).init(allocator),
        };
        defer state.list.deinit();

        try pem.decode(pemData, *PemAnchorsState, &state, pemAnchorsCallback, allocator);
        if (state.list.items.len == 0) {
            return error.NoCerts;
        }

        var self = Self {
            .anchors = state.list.toOwnedSlice(),
        };
        return self;
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void
    {
        for (self.anchors) |anchor| {
            anchor.deinit(allocator);
        }
        allocator.free(self.anchors);
    }

    /// Caller should call allocator.free on the result
    pub fn getRawAnchors(self: Self, allocator: std.mem.Allocator) ![]const c.br_x509_trust_anchor
    {
        var raw = try allocator.alloc(c.br_x509_trust_anchor, self.anchors.len);
        for (self.anchors) |_, i| {
            raw[i] = self.anchors[i].anchor;
        }
        return raw;
    }
};

const PemAnchorsState = struct {
    allocator: std.mem.Allocator,
    list: std.ArrayList(Anchor),
};

fn pemAnchorsCallback(state: *PemAnchorsState, data: []const u8) !void
{
    var anchor = try state.list.addOne();
    anchor.* = try Anchor.init(data, state.allocator);
}

pub const Chain = struct {
    chain: []c.br_x509_certificate,

    const Self = @This();

    pub fn init(pemData: []const u8, allocator: std.mem.Allocator) !Self
    {
        var state = PemChainState {
            .allocator = allocator,
            .list = std.ArrayList(c.br_x509_certificate).init(allocator),
        };
        defer state.list.deinit();

        try pem.decode(pemData, *PemChainState, &state, pemChainCallback, allocator);
        if (state.list.items.len == 0) {
            return error.NoCerts;
        }

        var self = Self {
            .chain = state.list.toOwnedSlice(),
        };
        return self;
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void
    {
        for (self.chain) |cert| {
            if (cert.data_len > 0) {
                allocator.free(cert.data[0..cert.data_len]);
            }
        }
        allocator.free(self.chain);
    }
};

const PemChainState = struct {
    allocator: std.mem.Allocator,
    list: std.ArrayList(c.br_x509_certificate),
};

fn pemChainCallback(state: *PemChainState, data: []const u8) !void
{
    const copy = try state.allocator.dupe(u8, data);
    var entry = try state.list.addOne();
    entry.data = &copy[0];
    entry.data_len = copy.len;
}
