const builtin = @import("builtin");
const std = @import("std");

const zgui = @import("libs/zgui/build.zig");
const zgpu = @import("libs/zgpu/build.zig");
const zpool = @import("libs/zpool/build.zig");
const zglfw = @import("libs/zglfw/build.zig");
const zstbi = @import("libs/zstbi/build.zig");

pub const min_zig_version = std.SemanticVersion{
    .major = 0,
    .minor = 11,
    .patch = 0,
    .pre = "dev.3395" 
};

fn ensureZigVersion() !void {
    var installed_ver = @import("builtin").zig_version;
    installed_ver.build = null;

    if (installed_ver.order(min_zig_version) == .lt) {
        std.log.err("\n" ++
            \\---------------------------------------------------------------------------
            \\
            \\Installed Zig compiler version is too old.
            \\
            \\Min. required version: {any}
            \\Installed version: {any}
            \\
            \\Please install newer version and try again.
            \\Latest version can be found here: https://ziglang.org/download/
            \\
            \\---------------------------------------------------------------------------
            \\
        , .{ min_zig_version, installed_ver });
        return error.ZigIsTooOld;
    }
}

fn ensureTarget(cross: std.zig.CrossTarget) !void {
    const target = (
        std.zig.system.NativeTargetInfo.detect(cross) catch unreachable
    ).target;

    const supported = switch (target.os.tag) {
        .windows => target.cpu.arch.isX86() and target.abi.isGnu(),
        .linux => (
            target.cpu.arch.isX86() 
            or target.cpu.arch.isAARCH64()
        ) and target.abi.isGnu(),
        .macos => blk: {
            if (
                !target.cpu.arch.isX86() 
                and !target.cpu.arch.isAARCH64()
            ) break :blk false;

            // If min. target macOS version is lesser than the min version we
            // have available, then our Dawn binary is incompatible with the
            // target.
            const min_available = std.SemanticVersion{
                .major = 12,
                .minor = 0,
                .patch = 0,
            };
            if (
                target.os.version_range.semver.min.order(
                    min_available
                ) == .lt
            ) {
                break :blk false;
            }

            break :blk true;
        },
        else => false,
    };
    if (!supported) {
        std.log.err("\n" ++
            \\---------------------------------------------------------------------------
            \\
            \\Unsupported build target. Dawn/WebGPU binary for this target is not available.
            \\
            \\Following targets are supported:
            \\
            \\x86_64-windows-gnu
            \\x86_64-linux-gnu
            \\x86_64-macos.12-none
            \\aarch64-linux-gnu
            \\aarch64-macos.12-none
            \\
            \\---------------------------------------------------------------------------
            \\
        , .{});
        return error.TargetNotSupported;
    }
}

var raw = std.heap.GeneralPurposeAllocator(.{}){};
pub const ALLOCATOR = raw.allocator();

pub const Options = struct {
    optimize: std.builtin.Mode,
    target: std.zig.CrossTarget,
    test_filter: ?[]const u8 = null,

    zd3d12_enable_debug_layer: bool,
    zd3d12_enable_gbv: bool,

    zpix_enable: bool,
};

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

const c_args = [_][]const u8{
    "-std=c11",
    "-fno-sanitize=undefined",
};

const SOURCES_WITH_TESTS = [_][]const u8{
    "./src/opentime/dual.zig",
    "./src/curve/curve.zig",
    "./src/test_hodograph.zig",
};



pub fn add_test_for_source(
    b: *std.build.Builder,
    target: anytype,
    test_step: anytype,
    fpath: []const u8,
    module_deps: []const ModuleSpec,
    filter: ?[]const u8,
) void 
{
    const test_thing = b.addTest(
        .{
            .name = std.fs.path.basename(fpath),
            .root_source_file = .{ .path = fpath },
            .target = target,
            .optimize = .Debug,
            .filter = filter,
        }
    );

    for (module_deps) 
        |mod| 
    {
        test_thing.addModule(mod.name, mod.module);
    }

    test_thing.addIncludePath(.{ .path = "./spline-gym/src"});
    test_thing.addCSourceFile(
        .{ 
            .file = .{ .path = "./spline-gym/src/hodographs.c"},
            .flags = &c_args
        }
    );

    // install the binary for the test, so that it can be used with lldb
    {
        var test_exe = b.addTest(
            .{
                .name = "otio_test",
                .root_source_file = .{ .path = fpath },
                .target = target,
                .optimize = .Debug,
                // .filter = filter,
            }
        );

        test_exe.addIncludePath(.{ .path = "./spline-gym/src"});
        test_exe.addCSourceFile(
            .{ 
                .file = .{ .path = "./spline-gym/src/hodographs.c"},
                .flags = &c_args
            }
        );

        const install_test_bin = b.addInstallArtifact(test_exe, .{});

        for (module_deps) |mod| {
            test_exe.addModule(mod.name, mod.module);
        }
        test_step.dependOn(&install_test_bin.step);
        test_step.dependOn(&test_exe.step);
    }

    test_step.dependOn(&b.addRunArtifact(test_thing).step);
}

/// Returns the result of running `git rev-parse HEAD`
pub fn rev_HEAD(alloc: std.mem.Allocator) ![]const u8 {
    const max = std.math.maxInt(usize);
    const dirg = try std.fs.cwd().openDir(".git", .{});
    const h = std.mem.trim(
        u8,
        try dirg.readFileAlloc(alloc, "HEAD", max),
        "\n"
    );
    const r = std.mem.trim(
        u8,
        try dirg.readFileAlloc(alloc, h[5..], max),
        "\n"
    );
    return r;
}

const ModuleSpec = struct {
    name: []const u8,
    module: *std.build.Module,
};

/// build an app that is like the wrinkles one
pub fn build_wrinkles_like(
    b: *std.build.Builder,
    comptime name: []const u8,
    comptime main_file_name: []const u8,
    comptime source_dir_path: []const u8,
    options: Options,
    module_deps: []const ModuleSpec,
) void 
{
    const exe = b.addExecutable(
        .{
            .name = name,
            .root_source_file = .{ .path = thisDir() ++ main_file_name },
            .target = options.target,
            .optimize = options.optimize,
        }
    );

    exe.addIncludePath(.{ .path = "./src"});
    exe.addCSourceFiles(
        &.{
            "./src/opentime.c",
            "./src/munit.c",
        },
        &c_args
    );

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
        rev_HEAD(ALLOCATOR
    ) catch "COULDNT READ HASH");
    // this
    const install_content_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = thisDir() ++ "/src/" ++ source_dir_path },
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/" ++ name ++ "_content",
    });
    exe.step.dependOn(&install_content_step.step);

    std.debug.print(
        "[build: {s}] content source directory path: {s}\n",
        .{name, thisDir() ++ source_dir_path}
    );

    exe.want_lto = false;

    const zgui_pkg = zgui.package(b, options.target, options.optimize, .{
        .options = .{ .backend = .glfw_wgpu },
    });

    zgui_pkg.link(exe);

    exe.addIncludePath(.{ .path = "./spline-gym/src"});
    exe.addCSourceFile(
        .{ 
            .file = .{ .path = "./spline-gym/src/hodographs.c"},
            .flags = &c_args
        }
    );

    for (module_deps) |mod| {
        exe.addModule(mod.name, mod.module);
    }

    // zgpu.link(exe, zgpu_options);
    // zglfw.link(exe);
    // zgui.link(exe);
    // zstbi.link(exe);

    // Needed for glfw/wgpu rendering backend
    const zglfw_pkg = zglfw.package(b, options.target, options.optimize, .{});
    const zpool_pkg = zpool.package(b, options.target, options.optimize, .{});
    const zgpu_pkg = zgpu.package(b, options.target, options.optimize, .{
        .deps = .{ .zpool = zpool_pkg.zpool, .zglfw = zglfw_pkg.zglfw },
    });
    const zstbi_pkg = zstbi.package(b, options.target, options.optimize, .{});
    zglfw_pkg.link(exe);
    zgpu_pkg.link(exe);
    zstbi_pkg.link(exe);

    const install = b.step(name, "Build '" ++ name ++ "'");
    install.dependOn(&b.addInstallArtifact(exe, .{}).step);

    var run_cmd = b.addRunArtifact(exe).step;
    run_cmd.dependOn(install);

    // const run_step = b.step(name ++ "-run", "Run '" ++ name ++ "'");
    // run_step.dependOn(&run_cmd);

    b.getInstallStep().dependOn(install);
}

pub fn build(b: *std.build.Builder) void {
    //
    // Options and system checks
    //
    ensureZigVersion() catch return;
    const options = Options{
        .optimize = b.standardOptimizeOption(.{}),
        .target = b.standardTargetOptions(.{}),
        .zd3d12_enable_debug_layer = b.option(
            bool,
            "zd3d12-enable-debug-layer",
            "Enable DirectX 12 debug layer",
        ) orelse false,
        .zd3d12_enable_gbv = b.option(
            bool,
            "zd3d12-enable-gbv",
            "Enable DirectX 12 GPU-Based Validation (GBV)",
        ) orelse false,
        .zpix_enable = b.option(
            bool,
            "zpix-enable",
            "Enable PIX for Windows profiler"
        ) orelse false,
        .test_filter = b.option(
            []const u8,
            "test-filter",
            "filter for tests to run"
        ) orelse null,
    };
    ensureTarget(options.target) catch return;

    //b.prominent_compile_errors = true;
    const comath_dep = b.dependency(
        "comath",
        .{
            .target = options.target,
            .optimize = options.optimize,
        }
    );


    const otio_allocator = b.createModule(
        .{
            .source_file = .{ .path = "src/allocator.zig" },
            .dependencies = &.{},
        }
    );
    const string_stuff = b.createModule(
        .{
            .source_file = .{ .path = "src/string_stuff.zig" },
            .dependencies = &.{},
        }
    );
    const opentime = b.createModule(
        .{
            .source_file = .{ .path = "src/opentime/opentime.zig" },
            .dependencies = &.{ 
                .{ .name = "string_stuff", .module = string_stuff },
                .{ .name = "otio_allocator", .module = otio_allocator },
                .{ .name = "comath", .module = comath_dep.module("comath") },
            },
        }
    );
    const curve = b.createModule(
        .{
            .source_file = .{ .path = "src/curve/curve.zig" },
            .dependencies = &.{ 
                .{ .name = "string_stuff", .module = string_stuff },
                .{ .name = "opentime", .module = opentime },
                .{ .name = "otio_allocator", .module = otio_allocator },
                .{ .name = "comath", .module = comath_dep.module("comath") },
            },
        }
    );
    const time_topology = b.createModule(
        .{
            .source_file = .{ .path = "src/time_topology/time_topology.zig" },
            .dependencies = &.{ 
                .{ .name = "string_stuff", .module = string_stuff },
                .{ .name = "opentime", .module = opentime },
                .{ .name = "otio_allocator", .module = otio_allocator },
                .{ .name = "curve", .module = curve },
            },
        }
    );

    const deps:[]const ModuleSpec = &.{ 
        .{ .name = "string_stuff", .module = string_stuff },
        .{ .name = "opentime", .module = opentime },
        .{ .name = "curve", .module = curve },
        .{ .name = "otio_allocator", .module = otio_allocator },
        .{ .name = "time_topology", .module = time_topology },
        .{ .name = "comath", .module = comath_dep.module("comath") },
    };

    build_wrinkles_like(
        b, 
        "wrinkles",
        "/src/wrinkles.zig",
        "/wrinkles_content/",
        options,
        deps,
    );
   build_wrinkles_like(
       b,
       "curvet",
       "/src/curvet.zig",
       "/wrinkles_content/",
        options,
        deps,
   );
   build_wrinkles_like(
       b,
       "example_zgui_app",
       "/src/example_zgui_app.zig",
       "/wrinkles_content/",
        options,
        deps,
   );

    const test_step = b.step("test", "run all unit tests");

    for (SOURCES_WITH_TESTS) |fpath| {
        add_test_for_source(
            b,
            options.target,
            test_step,
            fpath,
            deps,
            options.test_filter,
        );
    }
}
