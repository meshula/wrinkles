const builtin = @import("builtin");
const std = @import("std");
const zgpu = @import("libs/zgpu/build.zig");
const zpool = @import("libs/zpool/build.zig");
const zglfw = @import("libs/zglfw/build.zig");
const zgui = @import("libs/zgui/build.zig");
const zstbi = @import("libs/zstbi/build.zig");

var raw = std.heap.GeneralPurposeAllocator(.{}){};
pub const ALLOCATOR = raw.allocator();

pub const Options = struct {
    build_mode: std.builtin.Mode,
    target: std.zig.CrossTarget,
};

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

const c_args = [_][]const u8{
    "-std=c11",
    "-fno-sanitize=undefined",
};

/// Returns the result of running `git rev-parse HEAD`
pub fn rev_HEAD(alloc: std.mem.Allocator) ![]const u8 {
    const max = std.math.maxInt(usize);
    const dirg = try std.fs.cwd().openDir(".git", .{});
    const h = std.mem.trim(u8, try dirg.readFileAlloc(alloc, "HEAD", max), "\n");
    const r = std.mem.trim(u8, try dirg.readFileAlloc(alloc, h[5..], max), "\n");
    return r;
}

pub fn build_wrinkles_like(
    b: *std.build.Builder,
    comptime name:[]const u8,
    comptime main_file_name:[]const u8,
    comptime source_dir_path:[]const u8,
    options: Options,
) void {

    const exe = b.addExecutable(name, thisDir() ++ main_file_name);
    exe.addIncludePath("./src");
    exe.addCSourceFile("./src/opentime.c", &c_args);
    exe.addCSourceFile("./src/munit.c", &c_args);

    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);

    // @TODO: should this be in the install directory instead of `thisDir()`?
    exe_options.addOption(
        []const u8,
        name ++ "_content_dir",
        thisDir() ++ "/src" ++ source_dir_path
    );
    exe_options.addOption(
        []const u8,
        "hash",
        rev_HEAD(ALLOCATOR) catch "COULDNT READ HASH"
    );

    const install_content_step = b.addInstallDirectory(
        .{
            .source_dir = thisDir() ++ "/src/" ++ source_dir_path,
            .install_dir = .{ .custom = "" },
            .install_subdir = "bin/" ++ name ++ "_content",
        }
    );
    exe.step.dependOn(&install_content_step.step);

    std.debug.print("[build] content source directory path: {s}\n", .{thisDir() ++ source_dir_path});

    exe.setBuildMode(options.build_mode);
    exe.setTarget(options.target);
    exe.want_lto = false;

    const zgpu_options = zgpu.BuildOptionsStep.init(b, .{});
    const zgpu_pkg = zgpu.getPkg(&.{ zgpu_options.getPkg(), zpool.pkg, zglfw.pkg });

    exe.addPackage(zgpu_pkg);
    exe.addPackage(zgui.pkg);
    exe.addPackage(zglfw.pkg);
    exe.addPackage(zstbi.pkg);

    zgpu.link(exe, zgpu_options);
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
    var options = Options{
        .build_mode = b.standardReleaseOptions(),
        .target = b.standardTargetOptions(.{}),
    };

    b.prominent_compile_errors = true;

    build_wrinkles_like(
        b, 
        "wrinkles",
        "/src/wrinkles.zig",
        "/wrinkles_content/",
        options
    );
   build_wrinkles_like(
       b,
       "otvis",
       "/src/otvis.zig",
       "/wrinkles_content/",
       options
   );
}
