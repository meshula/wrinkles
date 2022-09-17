const builtin = @import("builtin");
const std = @import("std");
const zgpu = @import("libs/zgpu/build.zig");
const zpool = @import("libs/zpool/build.zig");
const zglfw = @import("libs/zglfw/build.zig");
const zgui = @import("libs/zgui/build.zig");
const zstbi = @import("libs/zstbi/build.zig");
const content_dir = "wrinkles_content/";

pub const Options = struct {
    build_mode: std.builtin.Mode,
    target: std.zig.CrossTarget,
};

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

pub fn build_wrinkles_like(
    b: *std.build.Builder,
    comptime name:[]const u8,
    comptime main_file_path:[]const u8
) void {
    var options = Options{
        .build_mode = b.standardReleaseOptions(),
        .target = b.standardTargetOptions(.{}),
    };

    const exe = b.addExecutable(name, thisDir() ++ main_file_path);
    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);
    exe_options.addOption([]const u8, "content_dir", content_dir);

    const install_content_step = b.addInstallDirectory(.{
        .source_dir = thisDir() ++ "/src/" ++ content_dir,
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/" ++ name ++ "_content",
    });
    exe.step.dependOn(&install_content_step.step);

    std.debug.print("source {s}\n", .{thisDir() ++ "/" ++ content_dir});

    exe.setBuildMode(options.build_mode);
    exe.setTarget(options.target);
    exe.want_lto = false;

    const zgpu_pkg = zgpu.getPkg(&.{ zpool.pkg, zglfw.pkg });
    const zgui_pkg = zgui.getPkg(&.{zglfw.pkg});

    exe.addPackage(zgpu_pkg);
    exe.addPackage(zgui_pkg);
    exe.addPackage(zglfw.pkg);
    exe.addPackage(zstbi.pkg);

    zgpu.link(exe);
    zglfw.link(exe);
    zgui.link(exe);
    zstbi.link(exe);

    const install = b.step(name, "Build '"++name++"'");
    install.dependOn(&b.addInstallArtifact(exe).step);

    const run_step = b.step(name ++ "-run", "Run '" ++ name ++ "'");
    const run_cmd = exe.run();
    run_cmd.step.dependOn(install);
    run_step.dependOn(&run_cmd.step);

    b.getInstallStep().dependOn(install);
}

pub fn build(b: *std.build.Builder) void {
    // build_wrinkles_like(b, "wrinkles", "/src/wrinkles.zig");
    build_wrinkles_like(b, "planetary", "/src/planetary.zig");
}
