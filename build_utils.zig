const std = @import("std");

fn isTermOk(term: std.ChildProcess.Term) bool
{
    switch (term) {
        std.ChildProcess.Term.Exited => |value| {
            return value == 0;
        },
        else => {
            return false;
        }
    }
}

fn checkTermStdout(execResult: std.ChildProcess.ExecResult) ?[]const u8
{
    const ok = isTermOk(execResult.term);
    if (!ok) {
        std.log.err("{}", .{execResult.term});
        if (execResult.stdout.len > 0) {
            std.log.info("{s}", .{execResult.stdout});
        }
        if (execResult.stderr.len > 0) {
            std.log.err("{s}", .{execResult.stderr});
        }
        return null;
    }
    return execResult.stdout;
}

pub fn execCheckTermStdoutWd(argv: []const []const u8, cwd: ?[]const u8, allocator: std.mem.Allocator) ?[]const u8
{
    const result = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = cwd
    }) catch |err| {
        std.log.err("exec error: {}", .{err});
        return null;
    };
    return checkTermStdout(result);
}

pub fn execCheckTermStdout(argv: []const []const u8, allocator: std.mem.Allocator) ?[]const u8
{
    return execCheckTermStdoutWd(argv, null, allocator);
}

pub fn stepWrapper(
    comptime stepFunction: anytype,
    comptime target: std.zig.CrossTarget) fn(*std.build.Step) anyerror!void
{
    // No nice Zig syntax for this yet... this will look better after
    // https://github.com/ziglang/zig/issues/1717
    return struct
    {
        fn f(self: *std.build.Step) anyerror!void
        {
            _ = self;
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            return stepFunction(target, arena.allocator());
        }
    }.f;
}
