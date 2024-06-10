const std = @import("std");
const builtin = @import("builtin");
const root = @import("root");

pub const utils = @import("build_utils.zig");

const bsslSrcs = @import("src/bearssl/srcs.zig");

var basePath: []const u8 = "."; // base path to this module

var iosCertificate: ?[]const u8 = null;
var iosSimulator = true;

const iosAppOutputPath = "app_ios";
const iosMinVersion = std.SemanticVersion {.major = 15, .minor = 0, .patch = 0};
const metalMinVersion = std.SemanticVersion {.major = 2, .minor = 4, .patch = 0};
const iosMinVersionString = std.fmt.comptimePrint("{}.{}", .{
    iosMinVersion.major, iosMinVersion.minor
});
const metalMinVersionString = std.fmt.comptimePrint("{}.{}", .{
    metalMinVersion.major, metalMinVersion.minor
});

const serverOutputPath = "server";

pub fn setupApp(
    b: *std.Build,
    bZigkm: *std.Build,
    options: struct {
        name: []const u8,
        srcApp: []const u8,
        srcServer: []const u8,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        // deps: ?[]const std.Build.Module.Import = null,
        iosSimulator: bool,
        iosCertificate: []const u8,
    },
) !void {
    const targetWasm = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const httpz = bZigkm.dependency("httpz", .{
        .target = options.target,
        .optimize = options.optimize,
    });
    const zigkmCommon = b.dependency("zigkm_common", .{
        .target = options.target,
        .optimize = options.optimize,
    });
    const zigkmCommonWasm = b.dependency("zigkm_common", .{
        .target = targetWasm,
        .optimize = options.optimize,
    });

    basePath = zigkmCommon.path(".").getPath(b);

    const server = b.addExecutable(.{
        .name = options.name,
        .root_source_file = .{.path = options.srcServer},
        .target = options.target,
        .optimize = options.optimize,
    });
    // TODO only a subset of these are required by the most minimal zigkm app
    server.root_module.addImport("httpz", httpz.module("httpz"));
    server.root_module.addImport("zigkm-app", zigkmCommon.module("zigkm-app"));
    server.root_module.addImport("zigkm-auth", zigkmCommon.module("zigkm-auth"));
    server.root_module.addImport("zigkm-google", zigkmCommon.module("zigkm-google"));
    server.root_module.addImport("zigkm-math", zigkmCommon.module("zigkm-math"));
    server.root_module.addImport("zigkm-platform", zigkmCommon.module("zigkm-platform"));
    server.root_module.addImport("zigkm-serialize", zigkmCommon.module("zigkm-serialize"));
    server.root_module.addImport("zigkm-stb", zigkmCommon.module("zigkm-stb"));

    const wasm = b.addExecutable(.{
        .name = "app",
        .root_source_file = .{.path = options.srcApp},
        .target = targetWasm,
        .optimize = options.optimize,
    });
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    // TODO same as above, trim to minimal zigkm app
    wasm.root_module.addImport("zigkm-app", zigkmCommonWasm.module("zigkm-app"));
    wasm.root_module.addImport("zigkm-math", zigkmCommonWasm.module("zigkm-math"));
    wasm.root_module.addImport("zigkm-platform", zigkmCommonWasm.module("zigkm-platform"));
    wasm.root_module.addImport("zigkm-serialize", zigkmCommonWasm.module("zigkm-serialize"));
    wasm.root_module.addImport("zigkm-stb", zigkmCommonWasm.module("zigkm-stb"));

    const buildServerStep = b.step("server_build", "Build server");
    const installServerStep = b.addInstallArtifact(server, .{
        .dest_dir = .{.override = .{.custom = serverOutputPath}}
    });
    buildServerStep.dependOn(&installServerStep.step);

    const installWasmStep = b.addInstallArtifact(wasm, .{
        .dest_dir = .{.override = .{.custom = serverOutputPath}}
    });
    buildServerStep.dependOn(&installWasmStep.step);
    buildServerStep.dependOn(&b.addInstallDirectory(.{
        .source_dir = zigkmCommon.path("src/app/static"),
        .install_dir = .{.custom = "server-temp/static"},
        .install_subdir = "",
    }).step);
    buildServerStep.dependOn(&b.addInstallDirectory(.{
        .source_dir = .{.path = "data"},
        .install_dir = .{.custom = "server-temp/static"},
        .install_subdir = "",
    }).step);
    buildServerStep.dependOn(&b.addInstallDirectory(.{
        .source_dir = .{.path = "src/server_static"},
        .install_dir = .{.custom = "server-temp/static"},
        .install_subdir = "",
    }).step);

    const packageServerStep = b.step("server_package", "Package server");
    packageServerStep.dependOn(buildServerStep);
    packageServerStep.dependOn(&b.addInstallDirectory(.{
        .source_dir = .{.path = "scripts/server"},
        .install_dir = .{.custom = "server"},
        .install_subdir = "scripts",
    }).step);
    packageServerStep.dependOn(&b.addInstallArtifact(zigkmCommon.artifact("genbigdata"), .{
        .dest_dir = .{.override = .{.custom = "tools"}}
    }).step);
    packageServerStep.makeFn = stepPackageServer;

    if (builtin.os.tag == .macos) {
        iosSimulator = options.iosSimulator;
        iosCertificate = options.iosCertificate;

        const targetAppIosQuery = if (iosSimulator)
            std.Target.Query {
                .cpu_arch = null,
                .os_tag = .ios,
                .os_version_min = .{.semver = iosMinVersion},
                .abi = .simulator,
            }
        else
            std.Target.Query {
                .cpu_arch = .aarch64,
                .os_tag = .ios,
                .os_version_min = .{.semver = iosMinVersion},
                .abi = null,
            };

        const targetAppIos = b.resolveTargetQuery(targetAppIosQuery);
        const zigkmCommonIos = b.dependency("zigkm_common", .{
            .target = targetAppIos,
            .optimize = options.optimize,
        });

        const lib = b.addStaticLibrary(.{
            .name = "applib",
            .root_source_file = .{.path = options.srcApp},
            .target = targetAppIos,
            .optimize = options.optimize
        });
        try addSdkPaths(b, lib, targetAppIos.result);
        lib.root_module.addImport("zigkm-app", zigkmCommonIos.module("zigkm-app"));
        lib.root_module.addImport("zigkm-math", zigkmCommonIos.module("zigkm-math"));
        lib.root_module.addImport("zigkm-platform", zigkmCommonIos.module("zigkm-platform"));
        lib.root_module.addImport("zigkm-serialize", zigkmCommonIos.module("zigkm-serialize"));
        lib.root_module.addImport("zigkm-stb", zigkmCommonIos.module("zigkm-stb"));
        // TODO not sure why I need this
        lib.addIncludePath(zigkmCommonIos.path("deps/stb"));
        lib.addCSourceFiles(.{
            .files = &[_][]const u8{
                zigkmCommonIos.path("deps/stb/stb_rect_pack_impl.c").getPath(b),
                zigkmCommonIos.path("deps/stb/stb_truetype_impl.c").getPath(b),
            },
            .flags = &[_][]const u8{"-std=c99"},
        });
        lib.bundle_compiler_rt = true;

        const appPath = getAppBuildPath();
        const buildAppIosStep = b.step("app_build", "Build and install app");
        const appInstallStep = b.addInstallArtifact(lib, .{
            .dest_dir = .{.override = .{.custom = iosAppOutputPath}}
        });
        const installDataStep = b.addInstallDirectory(.{
            .source_dir = .{.path = "data"},
            .install_dir = .{.custom = appPath},
            .install_subdir = "",
        });
        const installDataIosStep = b.addInstallDirectory(.{
            .source_dir = .{.path = "data_ios"},
            .install_dir = .{.custom = appPath},
            .install_subdir = "",
        });
        buildAppIosStep.dependOn(&appInstallStep.step);
        buildAppIosStep.dependOn(&installDataStep.step);
        buildAppIosStep.dependOn(&installDataIosStep.step);

        const packageAppStep = b.step("app_package", "Package app");
        packageAppStep.dependOn(buildAppIosStep);
        packageAppStep.makeFn = stepPackageAppIos;

        const runAppStep = b.step("app_run", "Run app on connected device");
        runAppStep.dependOn(packageAppStep);
        runAppStep.makeFn = stepRunAppIos;
    }
}

pub fn build(b: *std.Build) !void
{
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const bearssl = b.dependency("bearssl", .{
        .target = target,
        .optimize = optimize,
    });
    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });
    const zigimg = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

    // zigkm-math
    const mathModule = b.addModule("zigkm-math", .{
        .root_source_file = .{.path = "src/math.zig"}
    });

    // zigkm-serialize
    const serializeModule = b.addModule("zigkm-serialize", .{
        .root_source_file = .{.path = "src/serialize.zig"}
    });

    // zigkm-platform
    const platformModule = b.addModule("zigkm-platform", .{
        .root_source_file = .{.path = "src/platform/platform.zig"},
    });

    // zigkm-stb
    const stbLib = b.addStaticLibrary(.{
        .name = "zigkm-stb-lib",
        .target = target,
        .optimize = optimize,
    });
    stbLib.addCSourceFiles(.{
        .files = &[_][]const u8{
            "deps/stb/stb_rect_pack_impl.c",
            "deps/stb/stb_truetype_impl.c",
        },
        .flags = &[_][]const u8{"-std=c99"}
    });
    const stbModule = b.addModule("zigkm-stb", .{
        .root_source_file = .{.path = "src/stb/stb.zig"}
    });
    stbModule.addIncludePath(.{.path = "deps/stb"});
    stbModule.linkLibrary(stbLib);

    // zigkm-app
    const appModule = b.addModule("zigkm-app", .{
        .root_source_file = .{.path = "src/app/app.zig"},
        .imports = &[_]std.Build.Module.Import{
            .{.name = "httpz", .module = httpz.module("httpz")},
            .{.name = "zigkm-math", .module = mathModule},
            .{.name = "zigkm-platform", .module = platformModule},
            .{.name = "zigkm-stb", .module = stbModule},
            .{.name = "zigimg", .module = zigimg.module("zigimg")},
        },
    });
    appModule.addIncludePath(.{.path = "src/app"});

    // zigkm-bearssl
    const bsslLib = b.addStaticLibrary(.{
        .name = "zigkm-bearssl-lib",
        .target = target,
        .optimize = optimize,
    });
    bsslLib.addIncludePath(bearssl.path("inc"));
    bsslLib.addIncludePath(bearssl.path("src"));
    const bsslSources = try bsslSrcs.getSrcs(bearssl.path("").getPath(b), b.allocator);
    bsslLib.addCSourceFiles(.{
        .files = bsslSources,
        .flags = &[_][]const u8{
            "-Wall",
            "-DBR_LE_UNALIGNED=0", // this prevent BearSSL from using undefined behaviour when doing potential unaligned access
        },
    });
    bsslLib.linkLibC();
    if (target.result.os.tag == .windows) {
        bsslLib.linkSystemLibrary("advapi32");
    }
    const bsslModule = b.addModule("zigkm-bearssl", .{
        .root_source_file = .{.path = "src/bearssl/bearssl.zig"}
    });
    bsslModule.addIncludePath(bearssl.path("inc"));
    bsslModule.linkLibrary(bsslLib);

    // zigkm-google
    const googleModule = b.addModule("zigkm-google", .{
        .root_source_file = .{.path = "src/google/google.zig"},
        .imports = &[_]std.Build.Module.Import {
            .{.name = "zigkm-bearssl", .module = bsslModule},
        },
    });

    // zigkm-auth
    const authModule = b.addModule("zigkm-auth", .{
        .root_source_file = .{.path = "src/auth.zig"},
        .imports = &[_]std.Build.Module.Import {
            .{.name = "httpz", .module = httpz.module("httpz")},
            .{.name = "zigkm-google", .module = googleModule},
            .{.name = "zigkm-platform", .module = platformModule},
            .{.name = "zigkm-serialize", .module = serializeModule},
        }
    });
    _ = authModule;

    // tools
    const genbigdata = b.addExecutable(.{
        .name = "genbigdata",
        .root_source_file = .{.path = "src/tools/genbigdata.zig"},
        .target = target,
        .optimize = optimize,
    });
    genbigdata.root_module.addImport("zigkm-app", appModule);
    b.installArtifact(genbigdata);

    const gmail = b.addExecutable(.{
        .name = "gmail",
        .root_source_file = .{.path = "src/tools/gmail.zig"},
        .target = target,
        .optimize = optimize,
    });
    gmail.root_module.addImport("zigkm-google", googleModule);
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
        testCompile.root_module.addImport("zigkm-math", mathModule);

        const testRun = b.addRunArtifact(testCompile);
        testRun.has_side_effects = true;
        runTests.dependOn(&testRun.step);
    }
}


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

fn checkTermStdout(execResult: std.ChildProcess.RunResult) ?[]const u8
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
    const result = std.ChildProcess.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = cwd
    }) catch |err| {
        std.log.err("ChildProcess.run error: {}", .{err});
        return null;
    };
    return checkTermStdout(result);
}

pub fn execCheckTermStdout(argv: []const []const u8, allocator: std.mem.Allocator) ?[]const u8
{
    return execCheckTermStdoutWd(argv, null, allocator);
}

fn getIosSdkFlavor() []const u8
{
    return if (iosSimulator) "iphonesimulator" else "iphoneos";
}

fn getAppBuildPath() []const u8
{
    return iosAppOutputPath ++ "/Payload/update.app";
}

fn stepPackageAppIos(step: *std.Build.Step, node: *std.Progress.Node) !void
{
    _ = node;

    std.log.info("Packaging app for iOS", .{});
    const allocator = step.owner.allocator;

    const appPathFull = "zig-out/" ++ comptime getAppBuildPath();
    const appBuildDirFull = "zig-out/" ++ iosAppOutputPath;
    const iosSdkFlavor = getIosSdkFlavor();

    // Compile native code (Objective-C, maybe we can do Swift in the future)
    std.log.info("Compiling native code", .{});
    if (execCheckTermStdout(&[_][]const u8 {
        "./scripts/ios/compile_native.sh", // TODO move to zigkm-common? exe permissions are weird
        basePath, iosSdkFlavor, iosMinVersionString, appPathFull, appBuildDirFull
    }, allocator) == null) {
        return error.nativeCompile;
    }

    // Compile and link metal shaders
    std.log.info("Compiling shaders", .{});
    const metalTarget = if (iosSimulator) "air64-apple-ios" ++ iosMinVersionString ++ "-simulator" else "air64-apple-ios" ++ iosMinVersionString;
    if (execCheckTermStdout(&[_][]const u8 {
        "xcrun", "-sdk", iosSdkFlavor,
        "metal",
        "-Werror",
        "-target", metalTarget,
        "-std=ios-metal" ++ metalMinVersionString,
        "-mios-version-min=" ++ iosMinVersionString,
        // "-std=metal3.0",
        "-c", try std.mem.concat(allocator, u8, &[_][]const u8 {basePath, "/src/app/ios/shaders.metal"}),
        "-o", appBuildDirFull ++ "/shaders.air"
    }, allocator) == null) {
        return error.metalCompile;
    }
    std.log.info("Linking shaders", .{});
    if (execCheckTermStdout(&[_][]const u8 {
        "xcrun", "-sdk", iosSdkFlavor,
        "metallib",
        appBuildDirFull ++ "/shaders.air",
        "-o", appPathFull ++ "/default.metallib"
    }, allocator) == null) {
        return error.metalLink;
    }

    if (!iosSimulator) {
        std.log.info("Running codesign", .{});
        if (execCheckTermStdout(&[_][]const u8 {
            "codesign", "-s", iosCertificate.?, "--entitlements", "scripts/ios/update.entitlements", appPathFull
        }, allocator) == null) {
            return error.codesign;
        }

        std.log.info("zipping .ipa archive", .{});
        if (execCheckTermStdoutWd(&[_][]const u8 {
            "zip", "-r", "update.ipa", "Payload"
        }, appBuildDirFull, allocator) == null) {
            return error.ipaZip;
        }
    }
}

fn stepRunAppIos(step: *std.Build.Step, node: *std.Progress.Node) !void
{
    _ = node;

    std.log.info("Running app for iOS", .{});
    const allocator = step.owner.allocator;

    const appBuildDirFull = "zig-out/" ++ iosAppOutputPath;
    const appPathFull = "zig-out/" ++ comptime getAppBuildPath();

    if (iosSimulator) {
        const installArgs = &[_][]const u8 {
            "xcrun", "simctl", "install", "booted", appPathFull
        };
        if (execCheckTermStdout(installArgs, allocator) == null) {
            return error.xcrunInstallError;
        }

        const launchArgs = &[_][]const u8 {
            "xcrun", "simctl", "launch", "booted", "app.clientupdate.update"
        };
        if (execCheckTermStdout(launchArgs, allocator) == null) {
            return error.xcrunLaunchError;
        }
    } else {
        const installerArgs = &[_][]const u8 {
            "ideviceinstaller", "-i", appBuildDirFull ++ "/update.ipa"
        };
        if (execCheckTermStdout(installerArgs, allocator) == null) {
            return error.install;
        }
    }
}

fn addSdkPaths(b: *std.Build, compileStep: *std.Build.Step.Compile, target: std.Target) !void
{
    const sdk = std.zig.system.darwin.getSdk(b.allocator, target) orelse {
        std.log.warn("No iOS SDK found, skipping", .{});
        return;
    };
    std.log.info("SDK path: {s}", .{sdk});
    if (b.sysroot == null) {
        // b.sysroot = sdk;
    }

    // const sdkPath = b.sysroot.?;
    const frameworkPath = try std.fmt.allocPrint(b.allocator, "{s}/System/Library/Frameworks", .{sdk});
    const includePath = try std.fmt.allocPrint(b.allocator, "{s}/usr/include", .{sdk});
    const libPath = try std.fmt.allocPrint(b.allocator, "{s}/usr/lib", .{sdk});

    compileStep.addFrameworkPath(.{.path = frameworkPath});
    compileStep.addSystemIncludePath(.{.path = includePath});
    compileStep.addLibraryPath(.{.path = libPath});
    // _ = compileStep;
}

fn stepPackageServer(step: *std.Build.Step, node: *std.Progress.Node) !void
{
    _ = step;
    _ = node;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    std.log.info("Generating bigdata file archive...", .{});

    const genBigdataArgs = &[_][]const u8 {
        "./zig-out/tools/genbigdata", "./zig-out/server-temp/static", "./zig-out/server/static.bigdata",
    };
    if (execCheckTermStdout(genBigdataArgs, allocator) == null) {
        return error.genbigdata;
    }
}
