const std = @import("std");

pub const utils = @import("build_utils.zig");

const bsslSrcs = @import("src/bearssl/srcs.zig");

pub fn build(b: *std.build.Builder) !void
{
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // const zigimg = b.dependency("zigimg", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    const zigimg = b.anonymousDependency("deps/zigimg", @import("deps/zigimg/build.zig"), .{
        .target = target,
        .optimize = optimize,
    });
    const zigimgModule = zigimg.module("zigimg");

    // zigkm-math
    const mathModule = b.addModule("zigkm-math", .{
        .source_file = .{.path = "src/math.zig"}
    });

    // zigkm-auth
    const authModule = b.addModule("zigkm-auth", .{
        .source_file = .{.path = "src/auth.zig"}
    });
    _ = authModule;

    // zigkm-platform
    const platformModule = b.addModule("zigkm-platform", .{
        .source_file = .{.path = "src/platform/platform.zig"},
    });

    // zigkm-stb
    const stbModule = b.addModule("zigkm-stb", .{
        .source_file = .{.path = "src/stb/stb.zig"}
    });
    const stbLib = b.addStaticLibrary(.{
        .name = "zigkm-stb-lib",
        .target = target,
        .optimize = optimize,
    });
    stbLib.addIncludePath(.{.path = "deps/stb"});
    stbLib.addCSourceFiles(&[_][]const u8{
        "deps/stb/stb_image_impl.c",
        "deps/stb/stb_image_write_impl.c",
        "deps/stb/stb_rect_pack_impl.c",
        "deps/stb/stb_truetype_impl.c",
    }, &[_][]const u8{"-std=c99"});
    stbLib.linkLibC();
    stbLib.installHeadersDirectory("deps/stb", "");
    b.installArtifact(stbLib);

    // zigkm-app
    const appModule = b.addModule("zigkm-app", .{
        .source_file = .{.path = "src/app/app.zig"},
        .dependencies = &[_]std.build.ModuleDependency {
            .{.name = "zigkm-math", .module = mathModule},
            .{.name = "zigkm-platform", .module = platformModule},
            .{.name = "zigkm-stb", .module = stbModule},
            .{.name = "zigimg", .module = zigimgModule},
        },
    });

    // zigkm-bearssl
    const bsslModule = b.addModule("zigkm-bearssl", .{
        .source_file = .{.path = "src/bearssl/bearssl.zig"}
    });
    const bsslLib = b.addStaticLibrary(.{
        .name = "zigkm-bearssl",
        .target = target,
        .optimize = optimize,
    });
    bsslLib.addIncludePath(.{.path = "deps/BearSSL/inc"});
    bsslLib.addIncludePath(.{.path = "deps/BearSSL/src"});
    bsslLib.addCSourceFiles(
        &bsslSrcs.srcs,
        &[_][]const u8{
            "-Wall",
            "-DBR_LE_UNALIGNED=0", // this prevent BearSSL from using undefined behaviour when doing potential unaligned access
        },
    );
    bsslLib.linkLibC();
    if (target.isWindows()) {
        bsslLib.linkSystemLibrary("advapi32");
    }
    bsslLib.installHeadersDirectory("deps/BearSSL/inc", "");
    b.installArtifact(bsslLib);

    // zigkm-google
    const googleModule = b.addModule("zigkm-google", .{
        .source_file = .{.path = "src/google/google.zig"},
        .dependencies = &[_]std.build.ModuleDependency {
            .{.name = "zigkm-bearssl", .module = bsslModule},
        },
    });

    // tools
    const genbigdata = b.addExecutable(.{
        .name = "genbigdata",
        .root_source_file = .{.path = "src/tools/genbigdata.zig"},
        .target = target,
        .optimize = optimize,
    });
    genbigdata.addModule("zigkm-stb", stbModule);
    genbigdata.addModule("zigkm-app", appModule);
    genbigdata.addIncludePath(.{.path = "deps/stb"});
    genbigdata.linkLibrary(stbLib);
    b.installArtifact(genbigdata);

    const gmail = b.addExecutable(.{
        .name = "gmail",
        .root_source_file = .{.path = "src/tools/gmail.zig"},
        .target = target,
        .optimize = optimize,
    });
    gmail.addModule("zigkm-google", googleModule);
    gmail.linkLibrary(bsslLib);
    b.installArtifact(gmail);

    // tests
    const runTests = b.step("test", "Run all tests");
    const testSrcs = [_][]const u8 {
        "src/auth.zig",
        "src/serialize.zig",
        "src/app/bigdata.zig",
        "src/app/tree.zig",
        "src/app/ui.zig",
        "src/app/uix.zig",
        // "src/google/login.zig",
    };
    for (testSrcs) |src| {
        const testCompile = b.addTest(.{
            .root_source_file = .{
                .path = src,
            },
            .target = target,
            .optimize = optimize,
        });
        testCompile.addModule("zigkm-app", appModule);
        testCompile.addModule("zigkm-math", mathModule);

        const testRun = b.addRunArtifact(testCompile);
        testRun.has_side_effects = true;
        runTests.dependOn(&testRun.step);
    }
}
