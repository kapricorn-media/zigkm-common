const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const bssl = @import("zigkm-bearssl");
const crt = bssl.crt;

const localhost = @import("localhost.zig");

const Params = struct {
    pemData: []const u8,
    numCerts: usize,
};

const params = [_]Params {
    .{
        .pemData = @embedFile("five_certs.pem"),
        .numCerts = 5,
    },
    .{
        .pemData = @embedFile("many_certs.pem"),
        .numCerts = 132,
    },
};

fn compareRsaPublicKey(
    expected: bssl.c.br_rsa_public_key,
    actual: bssl.c.br_rsa_public_key) !void
{
    try expectEqualSlices(u8, expected.n[0..expected.nlen], actual.n[0..actual.nlen]);
    try expectEqualSlices(u8, expected.e[0..expected.elen], actual.e[0..actual.elen]);
}

fn comparePublicKey(
    expected: bssl.c.br_x509_pkey,
    actual: bssl.c.br_x509_pkey) !void
{
    try expectEqual(expected.key_type, actual.key_type);
    try expectEqual(bssl.c.BR_KEYTYPE_RSA, actual.key_type); // only cover RSA for now
    try compareRsaPublicKey(expected.key.rsa, actual.key.rsa);
}

fn compareAnchors(
    expected: []const bssl.c.br_x509_trust_anchor,
    actual: []const bssl.c.br_x509_trust_anchor) !void
{
    try expectEqual(expected.len, actual.len);
    for (expected) |_, i| {
        const dnSliceExpected = expected[i].dn.data[0..expected[i].dn.len];
        const dnSliceActual = actual[i].dn.data[0..actual[i].dn.len];
        try expectEqualSlices(u8, dnSliceExpected, dnSliceActual);
        try expectEqual(expected[i].flags, actual[i].flags);
        try comparePublicKey(expected[i].pkey, actual[i].pkey);
    }
}

test "cert anchors (single)"
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch |err| std.log.err("{}", .{err});
    var allocator = gpa.allocator();

    const pemData = @embedFile("localhost.crt");
    var anchors = try crt.Anchors.init(pemData, allocator);
    defer anchors.deinit(allocator);

    const rawAnchors = try anchors.getRawAnchors(allocator);
    defer allocator.free(rawAnchors);
    try compareAnchors(&localhost.TAs, rawAnchors);
}

test "cert anchors (multiple, no compare for now)"
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch |err| std.log.err("{}", .{err});
    var allocator = gpa.allocator();

    for (params) |param| {
        var anchors = try crt.Anchors.init(param.pemData, allocator);
        defer anchors.deinit(allocator);
        try expectEqual(param.numCerts, anchors.anchors.len);

        const rawAnchors = try anchors.getRawAnchors(allocator);
        defer allocator.free(rawAnchors);
        try expectEqual(param.numCerts, rawAnchors.len);
    }
}

fn compareChain(
    expected: []const bssl.c.br_x509_certificate,
    actual: []const bssl.c.br_x509_certificate) !void
{
    try expectEqual(expected.len, actual.len);
    for (expected) |_, i| {
        const sliceExpected = expected[i].data[0..expected[i].data_len];
        const sliceActual = actual[i].data[0..actual[i].data_len];
        try expectEqualSlices(u8, sliceExpected, sliceActual);
    }
}

test "cert chain (single)"
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch |err| std.log.err("{}", .{err});
    var allocator = gpa.allocator();

    const pemData = @embedFile("localhost.crt");
    var chain = try crt.Chain.init(pemData, allocator);
    defer chain.deinit(allocator);

    try compareChain(&localhost.CHAIN, chain.chain);
}

test "cert chain (multiple, no compare for now)"
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch |err| std.log.err("{}", .{err});
    var allocator = gpa.allocator();

    for (params) |param| {
        var chain = try crt.Chain.init(param.pemData, allocator);
        defer chain.deinit(allocator);
        try expectEqual(param.numCerts, chain.chain.len);
    }
}
