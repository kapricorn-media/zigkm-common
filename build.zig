const std = @import("std");
const builtin = @import("builtin");
const root = @import("root");

pub const utils = @import("build_utils.zig");

const bsslSrcs = @import("src/bearssl/srcs.zig");

var basePath: []const u8 = "."; // base path to this module

var jdkPath: []const u8 = undefined;
var androidSdkPath: []const u8 = undefined;
var debugKeystore: bool = true;
var keystoreAlias: []const u8 = "";
var keystorePass: []const u8 = "";
const ANDROID_SDK_MIN_VERSION = 21; // Required by Google Play installer
const ANDROID_SDK_VERSION = 35;
const ANDROID_SDK_VERSION_STRING = std.fmt.comptimePrint("{}", .{ANDROID_SDK_VERSION});
const ANDROID_SDK_BUILDTOOLS_VERSION = "35.0.0-rc4";

var iosCertificate: []const u8 = undefined;
var iosSimulator: bool = undefined;

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
        jdkPath: []const u8,
        androidSdkPath: []const u8,
        debugKeystore: bool,
        keystoreAlias: []const u8,
        keystorePass: []const u8,
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
        .root_source_file = b.path(options.srcServer),
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
        .root_source_file = b.path(options.srcApp),
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
        .source_dir = b.path("data"),
        .install_dir = .{.custom = "server-temp/static"},
        .install_subdir = "",
    }).step);
    buildServerStep.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("src/server_static"),
        .install_dir = .{.custom = "server-temp/static"},
        .install_subdir = "",
    }).step);

    const packageServerStep = b.step("server_package", "Package server");
    packageServerStep.dependOn(buildServerStep);
    packageServerStep.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("scripts/server"),
        .install_dir = .{.custom = "server"},
        .install_subdir = "scripts",
    }).step);
    packageServerStep.dependOn(&b.addInstallArtifact(zigkmCommon.artifact("genbigdata"), .{
        .dest_dir = .{.override = .{.custom = "tools"}}
    }).step);
    packageServerStep.makeFn = stepPackageServer;

    const buildAppStep = b.step("app_build", "Build and install app");
    const packageAppStep = b.step("app_package", "Package app");
    packageAppStep.dependOn(buildAppStep);
    const runAppStep = b.step("app_run", "Run app on connected device");
    runAppStep.dependOn(packageAppStep);

    if (builtin.os.tag == .macos) {
        // App - iOS
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
            .root_source_file = b.path(options.srcApp),
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
        lib.addCSourceFiles(.{
            .root = zigkmCommonIos.path(""),
            .files = &[_][]const u8{
                "deps/stb/stb_rect_pack_impl.c",
                "deps/stb/stb_truetype_impl.c",
            },
            .flags = &[_][]const u8{"-std=c99"},
        });
        lib.bundle_compiler_rt = true;

        const appPath = getAppBuildPath();
        const appInstallStep = b.addInstallArtifact(lib, .{
            .dest_dir = .{.override = .{.custom = iosAppOutputPath}}
        });
        const installDataStep = b.addInstallDirectory(.{
            .source_dir = b.path("data"),
            .install_dir = .{.custom = appPath},
            .install_subdir = "",
        });
        const installDataIosStep = b.addInstallDirectory(.{
            .source_dir = b.path("data_ios"),
            .install_dir = .{.custom = appPath},
            .install_subdir = "",
        });
        buildAppStep.dependOn(&appInstallStep.step);
        buildAppStep.dependOn(&installDataStep.step);
        buildAppStep.dependOn(&installDataIosStep.step);

        packageAppStep.makeFn = stepPackageAppIos;
        runAppStep.makeFn = stepRunAppIos;
    } else {
        // App - Android
        jdkPath = options.jdkPath;
        androidSdkPath = options.androidSdkPath;
        debugKeystore = options.debugKeystore;
        keystoreAlias = options.keystoreAlias;
        keystorePass = options.keystorePass;

        // TODO: Support Android build on mac?
        const targetAppAndroidQuery = std.Target.Query {
            .cpu_arch = .aarch64,
            .os_tag = .linux,
            // .os_version_min = .{.semver = iosMinVersion},
            .abi = .android,
        };
        const targetAppAndroid = b.resolveTargetQuery(targetAppAndroidQuery);
        const zigkmCommonIos = b.dependency("zigkm_common", .{
            .target = targetAppAndroid,
            .optimize = options.optimize,
        });

        const lib = b.addSharedLibrary(.{
            .name = "update",
            .root_source_file = b.path(options.srcApp),
            .target = targetAppAndroid,
            .optimize = options.optimize,
        });
        // try addSdkPaths(b, lib, targetAppIos.result);
        lib.root_module.addImport("zigkm-app", zigkmCommonIos.module("zigkm-app"));
        lib.root_module.addImport("zigkm-math", zigkmCommonIos.module("zigkm-math"));
        lib.root_module.addImport("zigkm-platform", zigkmCommonIos.module("zigkm-platform"));
        lib.root_module.addImport("zigkm-serialize", zigkmCommonIos.module("zigkm-serialize"));
        lib.root_module.addImport("zigkm-stb", zigkmCommonIos.module("zigkm-stb"));
        const ndkPath = try std.fs.path.join(b.allocator, &.{androidSdkPath, "ndk", "27.0.12077973"});
        const ndkSysroot = try std.fs.path.join(b.allocator, &.{ndkPath, "toolchains", "llvm", "prebuilt", "windows-x86_64", "sysroot", "usr"});
        lib.addLibraryPath(.{.cwd_relative = try std.fs.path.join(b.allocator, &.{ndkSysroot, "lib", "aarch64-linux-android", "35"})});
        lib.linkSystemLibrary("android");
        lib.linkSystemLibrary("EGL");
        lib.linkSystemLibrary("GLESv2");
        lib.linkSystemLibrary("log");
        lib.setLibCFile(b.path("data_android/libc.txt"));
        lib.linkLibC();
        // TODO not sure why I need this
        // lib.addCSourceFiles(.{
        //     .root = zigkmCommonIos.path(""),
        //     .files = &[_][]const u8{
        //         "deps/stb/stb_rect_pack_impl.c",
        //         "deps/stb/stb_truetype_impl.c",
        //     },
        //     .flags = &[_][]const u8{"-std=c99"},
        // });
        // lib.linkLibC();

        const appPath = "hello_world";
        const appInstallStep = b.addInstallArtifact(lib, .{
            .dest_dir = .{.override = .{.custom = appPath}}
        });
        const installAndroidShadersStep = b.addInstallDirectory(.{
            .source_dir = bZigkm.path("src/app/gles3/shaders"),
            .install_dir = .{.custom = appPath},
            .install_subdir = "data/shaders",
        });
        const installDataStep = b.addInstallDirectory(.{
            .source_dir = b.path("data"),
            .install_dir = .{.custom = appPath},
            .install_subdir = "data",
        });
        const installDataAndroidStep = b.addInstallDirectory(.{
            .source_dir = b.path("data_android"),
            .install_dir = .{.custom = appPath},
            .install_subdir = "data",
        });
        buildAppStep.dependOn(&appInstallStep.step);
        buildAppStep.dependOn(&installAndroidShadersStep.step);
        buildAppStep.dependOn(&installDataStep.step);
        buildAppStep.dependOn(&installDataAndroidStep.step);

        packageAppStep.makeFn = stepPackageAppAndroid;
        runAppStep.makeFn = stepRunAppAndroid;
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
        .root_source_file = b.path("src/math.zig"),
    });

    // zigkm-serialize
    const serializeModule = b.addModule("zigkm-serialize", .{
        .root_source_file = b.path("src/serialize.zig"),
    });

    // zigkm-platform
    const platformModule = b.addModule("zigkm-platform", .{
        .root_source_file = b.path("src/platform/platform.zig"),
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
        .root_source_file = b.path("src/stb/stb.zig"),
    });
    stbModule.addIncludePath(b.path("deps/stb"));
    stbModule.linkLibrary(stbLib);

    // zigkm-app
    const appModule = b.addModule("zigkm-app", .{
        .root_source_file = b.path("src/app/app.zig"),
        .imports = &[_]std.Build.Module.Import{
            .{.name = "httpz", .module = httpz.module("httpz")},
            .{.name = "zigkm-math", .module = mathModule},
            .{.name = "zigkm-platform", .module = platformModule},
            .{.name = "zigkm-stb", .module = stbModule},
            .{.name = "zigimg", .module = zigimg.module("zigimg")},
        },
    });
    appModule.addIncludePath(b.path("src/app"));
    if (true) { // if android
        // lib.addIncludePath(.{.cwd_relative = "C:\\Users\\jmric\\dev\\jdk-22.0.2\\include"});
        const ndkPath = try std.fs.path.join(b.allocator, &.{androidSdkPath, "ndk", "27.0.12077973"});
        const ndkSysroot = try std.fs.path.join(b.allocator, &.{ndkPath, "toolchains", "llvm", "prebuilt", "windows-x86_64", "sysroot", "usr"});
        appModule.addIncludePath(.{.cwd_relative = try std.fs.path.join(b.allocator, &.{ndkSysroot, "include"})});
        appModule.addIncludePath(.{.cwd_relative = try std.fs.path.join(b.allocator, &.{ndkSysroot, "include", "aarch64-linux-android"})});
        // appModule.linkLibC();
        // appModule.addIncludePath(.{.cwd_relative = "C:\\Users\\jmric\\dev\\jdk-22.0.2\\include"});
    }

    // zigkm-bearssl
    const bsslLib = b.addStaticLibrary(.{
        .name = "zigkm-bearssl-lib",
        .target = target,
        .optimize = optimize,
    });
    bsslLib.addIncludePath(bearssl.path("inc"));
    bsslLib.addIncludePath(bearssl.path("src"));
    bsslLib.addCSourceFiles(.{
        .root = bearssl.path(""),
        .files = &bsslSrcs.SRCS,
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
        .root_source_file = b.path("src/bearssl/bearssl.zig"),
    });
    bsslModule.addIncludePath(bearssl.path("inc"));
    bsslModule.linkLibrary(bsslLib);

    // zigkm-google
    const googleModule = b.addModule("zigkm-google", .{
        .root_source_file = b.path("src/google/google.zig"),
        .imports = &[_]std.Build.Module.Import {
            .{.name = "zigkm-bearssl", .module = bsslModule},
        },
    });

    // zigkm-auth
    const authModule = b.addModule("zigkm-auth", .{
        .root_source_file = b.path("src/auth.zig"),
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
        .root_source_file = b.path("src/tools/genbigdata.zig"),
        .target = target,
        .optimize = optimize,
    });
    genbigdata.root_module.addImport("zigkm-app", appModule);
    b.installArtifact(genbigdata);

    const gmail = b.addExecutable(.{
        .name = "gmail",
        .root_source_file = b.path("src/tools/gmail.zig"),
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
            .root_source_file = b.path(src),
            .target = target,
            .optimize = optimize,
        });
        testCompile.root_module.addImport("zigkm-math", mathModule);

        const testRun = b.addRunArtifact(testCompile);
        testRun.has_side_effects = true;
        runTests.dependOn(&testRun.step);
    }
}

fn getIosSdkFlavor() []const u8
{
    return if (iosSimulator) "iphonesimulator" else "iphoneos";
}

fn getAppBuildPath() []const u8
{
    return iosAppOutputPath ++ "/Payload/update.app";
}

fn stepPackageAppAndroid(step: *std.Build.Step, node: std.Progress.Node) !void
{
    _ = node;
    std.log.info("Packaging app for Android", .{});
    const allocator = step.owner.allocator;

    {
        var buildDir = try std.fs.cwd().openDir("zig-out", .{});
        defer buildDir.close();
        try buildDir.deleteTree("android");
        try buildDir.makeDir("android");
    }

    var androidDir = try std.fs.cwd().openDir("zig-out/android", .{});
    defer androidDir.close();

    try androidDir.makeDir("classes");
    try androidDir.makeDir("compile");
    try androidDir.makeDir("gen");
    try androidDir.makeDir("staging");

    const jdk_jar = try std.fs.path.join(allocator, &.{
        jdkPath, "bin", "jar.exe"
    });
    const jdk_jarsigner = try std.fs.path.join(allocator, &.{
        jdkPath, "bin", "jarsigner.exe"
    });
    const jdk_java = try std.fs.path.join(allocator, &.{
        jdkPath, "bin", "java.exe"
    });
    const jdk_javac = try std.fs.path.join(allocator, &.{
        jdkPath, "bin", "javac.exe"
    });

    const sdk_aapt2 = try std.fs.path.join(allocator, &.{
        androidSdkPath, "build-tools", ANDROID_SDK_BUILDTOOLS_VERSION, "aapt2.exe"
    });
    const sdk_androidJar = try std.fs.path.join(allocator, &.{
        androidSdkPath, "platforms", "android-" ++ ANDROID_SDK_VERSION_STRING, "android.jar",
    });
    const sdk_d8 = try std.fs.path.join(allocator, &.{
        androidSdkPath, "build-tools", ANDROID_SDK_BUILDTOOLS_VERSION, "d8.bat",
    });
    const sdk_zipalign = try std.fs.path.join(allocator, &.{
        androidSdkPath, "build-tools", ANDROID_SDK_BUILDTOOLS_VERSION, "zipalign.exe",
    });

    const zigkmCommon = step.owner.dependency("zigkm_common", .{});
    const bundletool = zigkmCommon.path("deps/bundletool/bundletool-all-1.17.1.jar").getPath(step.owner);

    // aapt2 compile
    if (!utils.execCheckTerm(&.{
        sdk_aapt2, "compile", "--dir", "data_android/res", "-o", "zig-out/android/compile"
    }, allocator)) {
        return error.appt2Compile;
    }

    // aapt2 link
    var aapt2LinkArgs = std.ArrayList([]const u8).init(allocator);
    defer aapt2LinkArgs.deinit();
    try aapt2LinkArgs.appendSlice(&.{
        sdk_aapt2, "link",
        "--proto-format",
        "--auto-add-overlay",
        "--min-sdk-version", std.fmt.comptimePrint("{}", .{ANDROID_SDK_MIN_VERSION}),
        "--target-sdk-version", ANDROID_SDK_VERSION_STRING,
        "-I", sdk_androidJar,
        "--manifest", "data_android/AndroidManifest.xml",
        "-o", "zig-out/android/app-temp.apk",
        "--java", "zig-out/android/gen"
    });
    if (debugKeystore) {
        try aapt2LinkArgs.append("--debug-mode");
    }
    const flatFiles = try utils.listDirFiles("zig-out/android/compile", allocator);
    try aapt2LinkArgs.appendSlice(flatFiles.items);
    if (!utils.execCheckTerm(aapt2LinkArgs.items, allocator)) {
        return error.aapt2Link;
    }

    // javac
    if (!utils.execCheckTerm(&.{
        jdk_javac,
        "-classpath", sdk_androidJar,
        // "-target", "1.8",
        // "-source", "1.8",
        "-d", "zig-out/android/classes",
        "zig-out/android/gen/app/clientupdate/update/R.java",
        "data_android/java/app/clientupdate/update/UpdateApplication.java",
        "data_android/java/app/clientupdate/update/MainActivity.java",
    }, allocator)) {
        return error.javac;
    }

    // d8
    var d8Args = std.ArrayList([]const u8).init(allocator);
    defer d8Args.deinit();
    try d8Args.appendSlice(&.{
        sdk_d8,
        if (debugKeystore) "--debug" else "--release",
        "--output", "zig-out/android/classes"
    });
    const classFiles = try utils.listDirFiles("zig-out/android/classes/app/clientupdate/update", allocator);
    try d8Args.appendSlice(classFiles.items);
    if (!utils.execCheckTerm(d8Args.items, allocator)) {
        return error.d8;
    }

    // unzip
    if (!utils.execCheckTermWd(&.{
        jdk_jar, "-xf", "../app-temp.apk"
    }, "zig-out/android/staging", allocator)) {
        return error.unzip;
    }

    // pack stuff for zip
    try androidDir.makeDir("staging/manifest");
    try androidDir.rename("staging/AndroidManifest.xml", "staging/manifest/AndroidManifest.xml");
    try androidDir.makeDir("staging/dex");
    try androidDir.rename("classes/classes.dex", "staging/dex/classes.dex");
    try androidDir.makePath("staging/lib/arm64-v8a");
    try std.fs.Dir.copyFile(std.fs.cwd(), "zig-out/hello_world/libupdate.so", androidDir, "staging/lib/arm64-v8a/libupdate.so", .{});
    try copyDir("zig-out/hello_world/data", "zig-out/android/staging/assets", allocator);

    // zip
    if (!utils.execCheckTermWd(&.{
        jdk_jar, "-cfM", "../base.zip", "."
    }, "zig-out/android/staging", allocator)) {
        return error.zip;
    }

    // bundletool build-bundle
    if (!utils.execCheckTerm(&.{
        jdk_java, "-jar", bundletool, "build-bundle",
        "--modules", "zig-out/android/base.zip",
        "--output", "zig-out/android/bundle.aab.unaligned"
    }, allocator)) {
        return error.bundletoolBuildBundle;
    }

    // zipalign
    if (!utils.execCheckTerm(&.{
        sdk_zipalign, "-f", "4", "zig-out/android/bundle.aab.unaligned", "zig-out/android/bundle.aab"
    }, allocator)) {
        return error.zipalign;
    }

    // jarsigner
    if (!utils.execCheckTerm(&.{
        jdk_jarsigner,
        "-keystore", if (debugKeystore) "data_android/debug.keystore" else "keys/release.keystore",
        "-storepass", if (debugKeystore) "android" else keystorePass,
        "zig-out/android/bundle.aab",
        if (debugKeystore) "androiddebugkey" else "update"
    }, allocator)) {
        return error.jarsigner;
    }

    const pass = if (debugKeystore) "android" else keystorePass;
    const alias = if (debugKeystore) "androiddebugkey" else keystoreAlias;
    const ksPassArg = try std.fmt.allocPrint(allocator, "--ks-pass=pass:{s}", .{pass});
    const ksAliasArg = try std.fmt.allocPrint(allocator, "--ks-key-alias={s}", .{alias});
    const keyPassArg = try std.fmt.allocPrint(allocator, "--key-pass=pass:{s}", .{pass});
    // bundletool build-apks
    if (!utils.execCheckTerm(&.{
        jdk_java, "-jar", bundletool, "build-apks",
        "--bundle", "zig-out/android/bundle.aab",
        "--output", "zig-out/android/update.apks",
        if (debugKeystore) "--ks=data_android/debug.keystore" else "--ks=keys/release.keystore",
        ksPassArg, ksAliasArg, keyPassArg
    }, allocator)) {
        return error.bundletoolBuildApks;
    }
}

fn stepRunAppAndroid(step: *std.Build.Step, node: std.Progress.Node) !void
{
    _ = node;
    std.log.info("Running app for Android", .{});
    const allocator = step.owner.allocator;

    const jdk_java = try std.fs.path.join(allocator, &.{
        jdkPath, "bin", "java.exe"
    });

    const sdk_adb = try std.fs.path.join(allocator, &.{
        androidSdkPath, "platform-tools", "adb.exe",
    });

    const zigkmCommon = step.owner.dependency("zigkm_common", .{});
    const bundletool = zigkmCommon.path("deps/bundletool/bundletool-all-1.17.1.jar").getPath(step.owner);

    if (!utils.execCheckTerm(&.{
        jdk_java, "-jar", bundletool, "install-apks",
        "--adb", sdk_adb,
        "--apks", "zig-out/android/update.apks"
    }, allocator)) {
        return error.bundletoolInstallApks;
    }

    if (!utils.execCheckTerm(&.{
        sdk_adb, "shell", "am", "start", "-n", "app.clientupdate.update/app.clientupdate.update.MainActivity"
    }, allocator)) {
        return error.adbShell;
    }
}

fn stepPackageAppIos(step: *std.Build.Step, node: std.Progress.Node) !void
{
    _ = node;

    std.log.info("Packaging app for iOS", .{});
    const allocator = step.owner.allocator;

    const appPathFull = "zig-out/" ++ comptime getAppBuildPath();
    const appBuildDirFull = "zig-out/" ++ iosAppOutputPath;
    const iosSdkFlavor = getIosSdkFlavor();

    // Compile native code (Objective-C, maybe we can do Swift in the future)
    std.log.info("Compiling native code", .{});
    if (utils.execCheckTermStdout(&.{
        "./scripts/ios/compile_native.sh", // TODO move to zigkm-common? exe permissions are weird
        basePath, iosSdkFlavor, iosMinVersionString, appPathFull, appBuildDirFull
    }, allocator) == null) {
        return error.nativeCompile;
    }

    // Compile and link metal shaders
    std.log.info("Compiling shaders", .{});
    const metalTarget = if (iosSimulator) "air64-apple-ios" ++ iosMinVersionString ++ "-simulator" else "air64-apple-ios" ++ iosMinVersionString;
    if (utils.execCheckTermStdout(&.{
        "xcrun", "-sdk", iosSdkFlavor,
        "metal",
        "-Werror",
        "-target", metalTarget,
        "-std=ios-metal" ++ metalMinVersionString,
        "-mios-version-min=" ++ iosMinVersionString,
        "-c", try std.mem.concat(allocator, u8, &[_][]const u8 {basePath, "/src/app/ios/shaders.metal"}),
        "-o", appBuildDirFull ++ "/shaders.air"
    }, allocator) == null) {
        return error.metalCompile;
    }
    std.log.info("Linking shaders", .{});
    if (utils.execCheckTermStdout(&.{
        "xcrun", "-sdk", iosSdkFlavor,
        "metallib",
        appBuildDirFull ++ "/shaders.air",
        "-o", appPathFull ++ "/default.metallib"
    }, allocator) == null) {
        return error.metalLink;
    }

    if (!iosSimulator) {
        std.log.info("Running codesign", .{});
        if (utils.execCheckTermStdout(&.{
            "codesign", "-s", iosCertificate, "--entitlements", "scripts/ios/update.entitlements", appPathFull
        }, allocator) == null) {
            return error.codesign;
        }

        std.log.info("zipping .ipa archive", .{});
        if (utils.execCheckTermStdoutWd(&.{
            "zip", "-r", "update.ipa", "Payload"
        }, appBuildDirFull, allocator) == null) {
            return error.ipaZip;
        }
    }
}

fn stepRunAppIos(step: *std.Build.Step, node: std.Progress.Node) !void
{
    _ = node;

    std.log.info("Running app for iOS", .{});
    const allocator = step.owner.allocator;

    const appBuildDirFull = "zig-out/" ++ iosAppOutputPath;
    const appPathFull = "zig-out/" ++ comptime getAppBuildPath();

    if (iosSimulator) {
        if (utils.execCheckTermStdout(&.{
            "xcrun", "simctl", "install", "booted", appPathFull
        }, allocator) == null) {
            return error.xcrunInstallError;
        }

        if (utils.execCheckTermStdout(&.{
            "xcrun", "simctl", "launch", "booted", "app.clientupdate.update"
        }, allocator) == null) {
            return error.xcrunLaunchError;
        }
    } else {
        if (utils.execCheckTermStdout(&.{
            "ideviceinstaller", "-i", appBuildDirFull ++ "/update.ipa"
        }, allocator) == null) {
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

    compileStep.addFrameworkPath(.{.cwd_relative = frameworkPath});
    compileStep.addSystemIncludePath(.{.cwd_relative = includePath});
    compileStep.addLibraryPath(.{.cwd_relative = libPath});
}

fn stepPackageServer(step: *std.Build.Step, node: std.Progress.Node) !void
{
    _ = node;

    std.log.info("Generating bigdata file archive...", .{});
    const allocator = step.owner.allocator;

    if (utils.execCheckTermStdout(&.{
        "./zig-out/tools/genbigdata", "./zig-out/server-temp/static", "./zig-out/server/static.bigdata",
    }, allocator) == null) {
        return error.genbigdata;
    }
}

fn copyDir(srcPath: []const u8, dstPath: []const u8, allocator: std.mem.Allocator) !void
{
    const cwd = std.fs.cwd();
    try cwd.deleteTree(dstPath);
    try cwd.makePath(dstPath);

    var srcDir = try cwd.openDir(srcPath, .{.iterate = true});
    defer srcDir.close();
    var dstDir = try cwd.openDir(dstPath, .{});
    defer dstDir.close();

    var srcWalker = try srcDir.walk(allocator);
    while (try srcWalker.next()) |entry| {
        switch (entry.kind) {
            .file => {
                try std.fs.Dir.copyFile(srcDir, entry.path, dstDir, entry.path, .{});
            },
            .directory => {
                try dstDir.makeDir(entry.path);
            },
            else => {
                return error.UnhandledEntryType;
            },
        }
    }
}
