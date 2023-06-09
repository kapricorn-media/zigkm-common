const std = @import("std");

pub const utils = @import("build_utils.zig");

const bearsslSources = @import("src/bearssl/srcs.zig").srcs;

pub const Package = enum {
    app,
    bearssl,
    google,
    http_common,
    http_client,
    http_server,
    math,
    stb,
    zigimg,
};

pub fn addPackagesToSteps(
    comptime dir: []const u8,
    packages: []const Package,
    steps: []*std.build.LibExeObjStep) void
{
    var pkgs: Packages = undefined;
    pkgs.load(dir);

    var deps = std.EnumSet(Package).init(.{});
    for (packages) |p| {
        addAllPackageDepsRecursive(p, &deps);
    }
    var depsIt = deps.iterator();
    while (depsIt.next()) |d| {
        const dInd = @enumToInt(d);
        for (steps) |step| {
            step.addPackage(pkgs.pkgs[dInd].pkg);
        }

        switch (d) {
            .app => {},
            .bearssl => linkBearssl(dir, steps),
            .google => {},
            .http_common => {},
            .http_client => {
                for (steps) |step| {
                    // for macos_certs.h, only on macOS
                    step.addIncludePath(dir ++ "/src/http");
                }
            },
            .http_server => {},
            .math => {},
            .stb => linkStb(dir, steps),
            .zigimg => {},
        }
    }
}

pub fn addPackages(
    comptime dir: []const u8,
    packages: []const Package,
    step: *std.build.LibExeObjStep) void
{
    addPackagesToSteps(dir, packages, &[_]*std.build.LibExeObjStep {step});
}

pub fn addPackage(
    comptime dir: []const u8,
    package: Package,
    step: *std.build.LibExeObjStep) void
{
    addPackagesToSteps(dir, &[_]Package {package}, &[_]*std.build.LibExeObjStep {step});
}

pub fn linkBearssl(comptime dir: []const u8, steps: []*std.build.LibExeObjStep) void
{
    for (steps) |step| {
        step.addIncludePath(dir ++ "/deps/BearSSL/inc");
        step.addIncludePath(dir ++ "/deps/BearSSL/src");

        const cOptions = &[_][]const u8 {
            "-Wall",
            "-Wextra",
            "-Werror",
            "-Wno-unknown-pragmas",
            "-DBR_LE_UNALIGNED=0", // this prevents BearSSL from using undefined behaviour when doing potential unaligned access
        };
        var fullSources: [bearsslSources.len][]const u8 = undefined;
        inline for (bearsslSources) |file, i| {
            fullSources[i] = dir ++ file;
        }

        step.addCSourceFiles(&fullSources, cOptions);
    }
}

pub fn linkStb(comptime dir: []const u8, steps: []*std.build.LibExeObjStep) void
{
    for (steps) |step| {
        step.addIncludePath(dir ++ "/deps/stb");
        step.addCSourceFiles(&[_][]const u8{
            dir ++ "/deps/stb/stb_image_impl.c",
            dir ++ "/deps/stb/stb_image_write_impl.c",
            dir ++ "/deps/stb/stb_rect_pack_impl.c",
            dir ++ "/deps/stb/stb_truetype_impl.c",
        }, &[_][]const u8{"-std=c99"});
    }
}

pub fn addBearsslToolsExe(
    comptime dir: []const u8,
    b: *std.build.Builder,
    mode: std.builtin.Mode,
    target: std.zig.CrossTarget) *std.build.LibExeObjStep
{
    const cOptions = [_][]const u8 {
        "-Wall",
        "-Wextra",
        "-Werror",

        "-Wno-sign-compare",
        "-Wno-pointer-sign",
        "-Wno-unused-but-set-variable",
        "-Wno-constant-conversion",
        "-Wno-unknown-pragmas",
    };

    const brsslToolSources = [_][]const u8 {
        "deps/BearSSL/tools/brssl.c",
        "deps/BearSSL/tools/certs.c",
        "deps/BearSSL/tools/chain.c",
        "deps/BearSSL/tools/client.c",
        "deps/BearSSL/tools/errors.c",
        "deps/BearSSL/tools/files.c",
        "deps/BearSSL/tools/impl.c",
        "deps/BearSSL/tools/keys.c",
        "deps/BearSSL/tools/names.c",
        "deps/BearSSL/tools/server.c",
        "deps/BearSSL/tools/skey.c",
        "deps/BearSSL/tools/sslio.c",
        "deps/BearSSL/tools/ta.c",
        "deps/BearSSL/tools/twrch.c",
        "deps/BearSSL/tools/vector.c",
        "deps/BearSSL/tools/verify.c",
        "deps/BearSSL/tools/xmem.c",
    };
    const brssl = b.addExecutable("brssl", null);
    inline for (brsslToolSources) |src| {
        brssl.addCSourceFile(src, &cOptions);
    }
    brssl.setBuildMode(mode);
    brssl.setTarget(target);
    linkBearssl(dir, &[_]*std.build.LibExeObjStep {brssl});
    brssl.linkLibC();
    return brssl;
}

pub fn addGenBigdataExe(
    comptime dir: []const u8,
    b: *std.build.Builder,
    mode: std.builtin.Mode,
    target: std.zig.CrossTarget) !*std.build.LibExeObjStep
{
    const genbigdata = b.addExecutable("genbigdata", dir ++ "/src/tools/genbigdata.zig");
    genbigdata.setBuildMode(mode);
    genbigdata.setTarget(target);
    addPackage(dir, .app, genbigdata);
    genbigdata.linkLibC();
    return genbigdata;
}

const NUM_PACKAGES = std.meta.fields(Package).len;

fn getDirectPackageDeps(package: Package) []const Package
{
    return switch (package) {
        .app => &[_]Package {.math, .stb, .zigimg},
        .bearssl => &[_]Package {},
        .google => &[_]Package {.http_common, .http_client},
        .http_common => &[_]Package {.bearssl},
        .http_client => &[_]Package {.bearssl, .http_common},
        .http_server => &[_]Package {.bearssl, .http_common},
        .math => &[_]Package {},
        .stb => &[_]Package {},
        .zigimg => &[_]Package {},
    };
}

fn addAllPackageDepsRecursive(package: Package, deps: *std.EnumSet(Package)) void
{
    deps.insert(package);
    const directDeps = getDirectPackageDeps(package);
    for (directDeps) |dep| {
        addAllPackageDepsRecursive(dep, deps);
    }
}

const PkgStuff = struct {
    pkg: std.build.Pkg,
    deps: std.BoundedArray(std.build.Pkg, NUM_PACKAGES),
};

const Packages = struct {
    pkgs: [NUM_PACKAGES]PkgStuff,

    const Self = @This();

    fn load(self: *Self, comptime dir: []const u8) void
    {
        for (self.pkgs) |*pkg, i| {
            const p = @intToEnum(Package, i);
            pkg.pkg = switch (p) {
                .app => .{
                    .name = "zigkm-app",
                    .source = .{.path = dir ++ "/src/app/app.zig"},
                },
                .bearssl => .{
                    .name = "zigkm-bearssl",
                    .source = .{.path = dir ++ "/src/bearssl/bearssl.zig"},
                },
                .google => .{
                    .name = "zigkm-google",
                    .source = .{.path = dir ++ "/src/google/google.zig"},
                },
                .http_common => .{
                    .name = "zigkm-http-common",
                    .source = .{.path = dir ++ "/src/http/common.zig"},
                },
                .http_client => .{
                    .name = "zigkm-http-client",
                    .source = .{.path = dir ++ "/src/http/client.zig"},
                },
                .http_server => .{
                    .name = "zigkm-http-server",
                    .source = .{.path = dir ++ "/src/http/server.zig"},
                },
                .math => .{
                    .name = "zigkm-math",
                    .source = .{.path = dir ++ "/src/math/math.zig"},
                },
                .stb => .{
                    .name = "zigkm-stb",
                    .source = .{.path = dir ++ "/src/stb/stb.zig"},
                },
                .zigimg => .{
                    .name = "zigimg",
                    .source = .{.path = dir ++ "/deps/zigimg/zigimg.zig"},
                },
            };
            pkg.deps.len = getDirectPackageDeps(p).len;
        }

        var depth: usize = 0;
        const MAX_DEPENDENCY_DEPTH = NUM_PACKAGES;
        while (depth < MAX_DEPENDENCY_DEPTH) : (depth += 1) {
            for (self.pkgs) |*pkg, i| {
                const p = @intToEnum(Package, i);
                const deps = getDirectPackageDeps(p);
                for (deps) |d, j| {
                    const dInd = @enumToInt(d);
                    pkg.deps.buffer[j] = self.pkgs[dInd].pkg;
                }
                pkg.pkg.dependencies = pkg.deps.slice();
            }
        }

        for (self.pkgs) |*pkg| {
            pkg.pkg.dependencies = pkg.deps.slice();
        }
    }
};

pub fn build(b: *std.build.Builder) !void
{
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const runTests = b.step("test", "Run all tests");

    // bigdata
    const genbigdata = try addGenBigdataExe(".", b, mode, target);
    genbigdata.install();

    // BearSSL
    const brssl = addBearsslToolsExe(".", b, mode, target);
    brssl.install();

    const testCrt = b.addTest("test/bearssl/test_crt.zig");
    testCrt.setBuildMode(mode);
    testCrt.setTarget(target);
    addPackage(".", .bearssl, testCrt);
    testCrt.linkLibC();
    runTests.dependOn(&testCrt.step);

    const testKey = b.addTest("test/bearssl/test_key.zig");
    testKey.setBuildMode(mode);
    testKey.setTarget(target);
    addPackage(".", .bearssl, testKey);
    testKey.linkLibC();
    runTests.dependOn(&testKey.step);

    const testPem = b.addTest("test/bearssl/test_pem.zig");
    testPem.setBuildMode(mode);
    testPem.setTarget(target);
    addPackage(".", .bearssl, testPem);
    testPem.linkLibC();
    runTests.dependOn(&testPem.step);

    // google
    const drive = b.addExecutable("google_drive", "test/google/drive.zig");
    drive.setBuildMode(mode);
    drive.setTarget(target);
    addPackage(".", .google, drive);
    drive.linkLibC();
    drive.install();

    // HTTP
    const sampleClient = b.addExecutable("sample_client", "test/http/sample_client.zig");
    sampleClient.setBuildMode(mode);
    sampleClient.setTarget(target);
    addPackage(".", .http_client, sampleClient);
    sampleClient.linkLibC();
    sampleClient.install();

    const sampleServer = b.addExecutable("sample_server", "test/http/sample_server.zig");
    sampleServer.setBuildMode(mode);
    sampleServer.setTarget(target);
    addPackage(".", .http_server, sampleServer);
    sampleServer.linkLibC();
    sampleServer.install();

    const testClient = b.addTest("test/http/test_client.zig");
    testClient.setBuildMode(mode);
    testClient.setTarget(target);
    addPackage(".", .http_client, testClient);
    testClient.linkLibC();
    runTests.dependOn(&testClient.step);

    const testCommon = b.addTest("test/http/test_common.zig");
    testCommon.setBuildMode(mode);
    testCommon.setTarget(target);
    addPackage(".", .http_common, testCommon);
    testCommon.linkLibC();
    runTests.dependOn(&testCommon.step);

    // const testServer = b.addTest("test/http/test_server.zig");
    // testServer.setBuildMode(mode);
    // testServer.setTarget(target);
    // addPackage(".", .http_server, testServer);
    // testServer.linkLibC();
    // runTests.dependOn(&testServer.step);

    const testBoth = b.addTest("test/http/test_both.zig");
    testBoth.setBuildMode(mode);
    testBoth.setTarget(target);
    addPackages(".", &[_]Package {.http_client, .http_server}, testBoth);
    testBoth.linkLibC();
    runTests.dependOn(&testBoth.step);
}
