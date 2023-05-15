const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const bssl = @import("zigkm-bearssl");
const key = bssl.key;

const localhost = @import("localhost.zig");

fn compareRsaKeys(
    expected: *const bssl.c.br_rsa_private_key,
    actual: *const bssl.c.br_rsa_private_key) !void
{
    try expectEqual(expected.n_bitlen, actual.n_bitlen);
    try expectEqualSlices(u8, expected.p[0..expected.plen], actual.p[0..actual.plen]);
    try expectEqualSlices(u8, expected.q[0..expected.qlen], actual.q[0..actual.qlen]);
    try expectEqualSlices(u8, expected.dp[0..expected.dplen], actual.dp[0..actual.dplen]);
    try expectEqualSlices(u8, expected.dq[0..expected.dqlen], actual.dq[0..actual.dqlen]);
    try expectEqualSlices(u8, expected.iq[0..expected.iqlen], actual.iq[0..actual.iqlen]);
}

test "RSA key"
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer expect(!gpa.deinit()) catch |err| std.log.err("{}", .{err});
    var allocator = gpa.allocator();

    const pemData = @embedFile("localhost.key");
    var rsaKey = try key.PrivateKey.initFromPem(pemData, allocator);
    defer rsaKey.deinit(allocator);

    try compareRsaKeys(&localhost.RSA, &rsaKey.rsaKey);
}
