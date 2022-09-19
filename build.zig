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

const c_args = [_][]const u8{
    "-std=c11",
    "-fno-sanitize=undefined",
};

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

pub fn build(b: *std.build.Builder) void {
    var options = Options{
        .build_mode = b.standardReleaseOptions(),
        .target = b.standardTargetOptions(.{}),
    };

    const exe = b.addExecutable("wrinkles", thisDir() ++ "/src/wrinkles.zig");
    exe.addIncludeDir("./src");
    exe.addCSourceFile("./src/opentime.c", &c_args);

    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);
    exe_options.addOption([]const u8, "content_dir", content_dir);

    const install_content_step = b.addInstallDirectory(.{
        .source_dir = thisDir() ++ "/src/" ++ content_dir,
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/wrinkles_content",
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
    exe.linkLibC();

    const install = b.step("wrinkles", "Build 'wrinkles'");
    install.dependOn(&b.addInstallArtifact(exe).step);

    const run_step = b.step("wrinkles-run", "Run 'wrinkles'");
    const run_cmd = exe.run();
    run_cmd.step.dependOn(install);
    run_step.dependOn(&run_cmd.step);

    b.getInstallStep().dependOn(install);
}
