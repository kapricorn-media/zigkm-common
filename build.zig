const std = @import("std");

pub fn getPackageAsset(comptime dir: []const u8, deps: []const std.build.Pkg) std.build.Pkg
{
    return std.build.Pkg {
        .name = "zigkm-common-asset",
        .source = .{ .path = dir ++ "/src/asset.zig" },
        .dependencies = deps,
    };
}

pub fn getPackageMath(comptime dir: []const u8) std.build.Pkg
{
    return std.build.Pkg {
        .name = "zigkm-common-math",
        .source = .{ .path = dir ++ "/src/math.zig" },
    };
}

pub fn getPackageStb(comptime dir: []const u8) std.build.Pkg
{
    return std.build.Pkg {
        .name = "zigkm-common-stb",
        .source = .{ .path = dir ++ "/src/stb.zig" },
    };
}

pub fn linkStb(comptime dir: []const u8, step: *std.build.LibExeObjStep) void
{
    step.addIncludePath(dir ++ "/deps/stb");
    step.addCSourceFiles(&[_][]const u8{
        dir ++ "/deps/stb/stb_rect_pack_impl.c",
        dir ++ "/deps/stb/stb_truetype_impl.c",
    }, &[_][]const u8{"-std=c99"});
    step.linkLibC();
}

pub fn addAllPackages(comptime dir: []const u8, step: *std.build.LibExeObjStep) void
{
    const math = getPackageMath(dir);
    const stb = getPackageStb(dir);
    const assetDeps = [_]std.build.Pkg {
        math,
        stb
    };
    const asset = getPackageAsset(dir, &assetDeps);
    step.addPackage(math);
    step.addPackage(stb);
    step.addPackage(asset);
    linkStb(dir, step);
}
