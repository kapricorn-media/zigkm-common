const std = @import("std");

// deps are math and stb
pub fn getPackageApp(comptime dir: []const u8, deps: *const [2]std.build.Pkg) std.build.Pkg
{
    return std.build.Pkg {
        .name = "zigkm-common-app",
        .source = .{.path = dir ++ "/src/app/app.zig"},
        .dependencies = deps
    };
}

pub fn getPackageMath(comptime dir: []const u8) std.build.Pkg
{
    return std.build.Pkg {
        .name = "zigkm-common-math",
        .source = .{ .path = dir ++ "/src/math/math.zig" },
    };
}

pub fn getPackageStb(comptime dir: []const u8) std.build.Pkg
{
    return std.build.Pkg {
        .name = "zigkm-common-stb",
        .source = .{ .path = dir ++ "/src/stb/stb.zig" },
    };
}

pub fn linkStb(comptime dir: []const u8, step: *std.build.LibExeObjStep) void
{
    step.addIncludePath(dir ++ "/deps/stb");
    step.addCSourceFiles(&[_][]const u8{
        dir ++ "/deps/stb/stb_image_impl.c",
        dir ++ "/deps/stb/stb_image_write_impl.c",
        dir ++ "/deps/stb/stb_rect_pack_impl.c",
        dir ++ "/deps/stb/stb_truetype_impl.c",
    }, &[_][]const u8{"-std=c99"});
}

pub fn addAllPackages(comptime dir: []const u8, step: *std.build.LibExeObjStep) void
{
    const math = getPackageMath(dir);
    const stb = getPackageStb(dir);
    const appDeps = [_]std.build.Pkg {math, stb};
    const app = getPackageApp(dir, &appDeps);
    step.addPackage(math);
    step.addPackage(stb);
    step.addPackage(app);
    linkStb(dir, step);
}

pub fn addGenBigdataExe(comptime dir: []const u8, b: *std.build.Builder, mode: std.builtin.Mode, target: std.zig.CrossTarget) *std.build.LibExeObjStep
{
    const genbigdata = b.addExecutable("genbigdata", dir ++ "/src/tools/genbigdata.zig");
    genbigdata.setBuildMode(mode);
    genbigdata.setTarget(target);
    addAllPackages(dir, genbigdata);
    genbigdata.linkLibC();
    return genbigdata;
}

pub fn build(b: *std.build.Builder) !void
{
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const genbigdata = addGenBigdataExe(".", b, mode, target);
    genbigdata.install();
}
