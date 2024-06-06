// zig std stuff
const builtin = @import("builtin");
const std = @import("std");

pub const MIN_ZIG_VERSION = std.SemanticVersion{
    .major = 0,
    .minor = 13,
    .patch = 0,
    .pre = "dev.46" 
};

fn ensureZigVersion() !void {
    var installed_ver = @import("builtin").zig_version;
    installed_ver.build = null;

    if (installed_ver.order(MIN_ZIG_VERSION) == .lt) {
        std.log.err(
            "\n" ++
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
            , .{ MIN_ZIG_VERSION, installed_ver }
        );

        return error.ZigIsTooOld;
    }
}

// fn ensureTarget(
//     cross: std.zig.CrossTarget
// ) !void 
// {
//     // const target = (
//     //     std.zig.system.NativeTargetInfo.detect(cross) catch unreachable
//     // ).target;
//     const target = cross;
//
//     const supported = switch (target.os_tag.?) 
//     {
//         .windows => target.cpu_arch.?.isX86() and target.abi.?.isGnu(),
//         .linux => (
//             target.cpu_arch.?.isX86() 
//             or target.cpu_arch.?.isAARCH64()
//         ) and target.abi.?.isGnu(),
//         .macos => blk: {
//             if (
//                 !target.cpu_arch.?.isX86() 
//                 and !target.cpu_arch.?.isAARCH64()
//             ) break :blk false;
//
//             // If min. target macOS version is lesser than the min version we
//             // have available, then our Dawn binary is incompatible with the
//             // target.
//             const min_available = std.SemanticVersion{
//                 .major = 12,
//                 .minor = 0,
//                 .patch = 0,
//             };
//             if (
//                 target.os_version_min(
//                     min_available
//                 ) == .lt
//             ) {
//                 break :blk false;
//             }
//
//             break :blk true;
//         },
//         else => false,
//     };
//     if (!supported) {
//         std.log.err(
//             "\n" ++
//             \\---------------------------------------------------------------------------
//             \\
//             \\Unsupported build target. Dawn/WebGPU binary for this target is not available.
//             \\
//             \\Following targets are supported:
//             \\
//             \\x86_64-windows-gnu
//             \\x86_64-linux-gnu
//             \\x86_64-macos.12-none
//             \\aarch64-linux-gnu
//             \\aarch64-macos.12-none
//             \\
//             \\---------------------------------------------------------------------------
//             \\
//             , .{}
//         );
//         return error.TargetNotSupported;
//     }
// }

var raw = std.heap.GeneralPurposeAllocator(.{}){};
pub const ALLOCATOR = raw.allocator();

pub const Options = struct {
    optimize: std.builtin.Mode,
    target: std.Build.ResolvedTarget,
    test_filter: ?[]const u8 = null,

    zd3d12_enable_debug_layer: bool,
    zd3d12_enable_gbv: bool,

    zpix_enable: bool,
};

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

const C_ARGS = [_][]const u8{
    "-std=c11",
    "-fno-sanitize=undefined",
};

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

/// build an executable that uses zgui/zgflw etc from zig-gamedev
pub fn executable(
    b: *std.Build,
    comptime name: []const u8,
    comptime main_file_name: []const u8,
    comptime source_dir_path: []const u8,
    options: Options,
    module_deps: []const std.Build.Module.Import,
) void 
{
    const exe = b.addExecutable(
        .{
            .name = name,
            .root_source_file = .{ 
                .path = thisDir() ++ main_file_name 
            },
            .target = options.target,
            .optimize = options.optimize,
        }
    );

    for (module_deps) 
        |mod| 
    {
        exe.root_module.addImport(mod.name, mod.module);
    }

    // options for exposing the content directory and build hash
    {
        const exe_options = b.addOptions();
        exe.root_module.addOptions("build_options", exe_options);

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
                .source_dir = .{ 
                    .path = thisDir() ++ "/src/" ++ source_dir_path 
                },
                .install_dir = .{ .custom = "" },
                .install_subdir = "bin/" ++ name ++ "_content",
            }
        );
        exe.step.dependOn(&install_content_step.step);
        std.debug.print(
            "[build: {s}] content source directory path: {s}\n",
            .{name, thisDir() ++ source_dir_path}
        );
    }

    exe.want_lto = false;

    // zig gamedev dependencies
    {
        @import("zgpu").addLibraryPathsTo(exe);

        const zgpu_pkg = b.dependency("zgpu", .{
            .target = options.target,
            .optimize = options.optimize,
        });
        exe.root_module.addImport(
            "zgpu",
            zgpu_pkg.module("root")
        );
        exe.linkLibrary(zgpu_pkg.artifact("zdawn"));

        const zgui_pkg = b.dependency(
            "zgui",
            .{
                .target = options.target,
                .optimize = options.optimize,
                .shared = false,
                .with_implot = true,
                .backend = .glfw_wgpu,
            }
        );
        exe.root_module.addImport(
            "zgui",
            zgui_pkg.module("root")
        );
        exe.linkLibrary(zgui_pkg.artifact("imgui"));

        const zglfw_pkg = b.dependency("zglfw", .{
            .target = options.target,
            .optimize = options.optimize,
            .shared = false,
        });
        exe.root_module.addImport(
            "zglfw",
            zglfw_pkg.module("root")
        );
        exe.linkLibrary(zglfw_pkg.artifact("glfw"));

        const zpool_pkg = b.dependency("zpool", .{
            .target = options.target,
            .optimize = options.optimize,
        });
        exe.root_module.addImport(
            "zpool",
            zpool_pkg.module("root")
        );

        const zstbi_pkg = b.dependency("zstbi", .{
            .target = options.target,
            .optimize = options.optimize,
        });
        exe.root_module.addImport(
            "zstbi",
            zstbi_pkg.module("root")
        );
        exe.linkLibrary(zstbi_pkg.artifact("zstbi"));
    }

    // run and install the executable
    {
        const install = b.step(
            name,
            "Build/install '" ++ name ++ "' executable"
        );
        install.dependOn(&b.addInstallArtifact(exe, .{}).step);

        var run_cmd = b.addRunArtifact(exe).step;
        run_cmd.dependOn(install);

        const run_step = b.step(
            name ++ "-run",
            "Run '" ++ name ++ "' executable"
        );
        run_step.dependOn(&run_cmd);

        b.getInstallStep().dependOn(install);
    }
}

/// options for module_with_tests_and_artifact
pub const CreateModuleOptions = struct {
    b: *std.Build,
    fpath: []const u8,
    target: std.Build.ResolvedTarget,
    test_step: *std.Build.Step,
    deps: []const std.Build.Module.Import = &.{},
};

pub fn module_with_tests_and_artifact(
    comptime name: []const u8,
    opts:CreateModuleOptions
) *std.Build.Module 
{
    const mod = opts.b.createModule(
        .{
            .root_source_file = .{ .path = opts.fpath },
            .imports = opts.deps,
        }
    );

    // unit tests for the module
    {
        const mod_unit_tests = opts.b.addTest(
            .{
                .name = "test_" ++ name,
                .root_source_file = .{ .path = opts.fpath },
                .target =opts. target,
            }
        );

        for (opts.deps) 
            |dep_mod| 
        {
            mod_unit_tests.root_module.addImport(dep_mod.name, dep_mod.module);
        }

        const run_unit_tests = opts.b.addRunArtifact(mod_unit_tests);
        opts.test_step.dependOn(&run_unit_tests.step);

        // also install the test binary for lldb needs
        const install_test_bin = opts.b.addInstallArtifact(mod_unit_tests, .{});
        opts.test_step.dependOn(&install_test_bin.step);
    }

    return mod;
}

// main entry point
pub fn build(
    b: *std.Build
) void 
{
    ensureZigVersion() catch return;

    //
    // Options and system checks
    //
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
    // ensureTarget(options.target) catch return;

    const test_step = b.step(
        "test",
        "step to run all unit tests"
    );

    // submodules and dependencies
    const comath_dep = b.dependency(
        "comath",
        .{
            .target = options.target,
            .optimize = options.optimize,
        }
    );

    const otio_allocator = module_with_tests_and_artifact(
        "allocator",
        .{
            .b = b,
            .fpath = "src/allocator.zig",
            .target = options.target,
            .test_step = test_step,
        }
    );

    const string_stuff = module_with_tests_and_artifact(
        "string_stuff",
        .{
            .b = b,
            .fpath = "src/string_stuff.zig",
            .target = options.target,
            .test_step = test_step,
        }
    );

    const libsamplerate = b.addStaticLibrary(
        .{
            .name = "libsamplerate",
            .target = options.target,
            .optimize = options.optimize,
            .root_source_file = .{ 
                .path = 
                    "libs/wrapped_libsamplerate/wrapped_libsamplerate.zig" 
            },
        }
    );
    {
        libsamplerate.addIncludePath(
            .{ 
                .path = 
                    "./libs/wrapped_libsamplerate/libsamplerate/include"
            }
        );
        libsamplerate.addIncludePath(
            .{ .path = "./libs/wrapped_libsamplerate"}
        );
        libsamplerate.addCSourceFile(
            .{ 
                .file = .{
                    .path = 
                        "./libs/wrapped_libsamplerate/wrapped_libsamplerate.c"
                },
                .flags = &C_ARGS
            }
        );
    }
    const sampling = module_with_tests_and_artifact(
        "sampling",
        .{
            .b = b,
            .fpath = "src/sampling.zig",
            .target = options.target,
            .test_step = test_step,
            .deps = &.{
                .{ 
                    .name = "libsamplerate",
                    .module = &libsamplerate.root_module, 
                },
            },
        }
    );

    const opentime = module_with_tests_and_artifact(
        "opentime_lib",
        .{ 
            .b = b,
            .fpath = "src/opentime/opentime.zig",
            .target = options.target,
            .test_step = test_step,
            .deps = &.{
                .{ .name = "string_stuff", .module = string_stuff },
                .{ .name = "otio_allocator", .module = otio_allocator },
                .{ .name = "comath", .module = comath_dep.module("comath") },
            },
        }
    );

    const spline_gym = b.addStaticLibrary(
        .{
            .name = "spline_gym",
            .target = options.target,
            .optimize = options.optimize,
            .root_source_file = .{
                .path = "./spline-gym/src/hodographs.zig" 
            },
        }
    );
    {
        spline_gym.addIncludePath(.{ .path = "./spline-gym/src"});
        spline_gym.addCSourceFile(
            .{ 
                .file = .{ .path = "./spline-gym/src/hodographs.c"},
                .flags = &C_ARGS
            }
        );
        b.installArtifact(spline_gym);
    }

    const curve = module_with_tests_and_artifact(
        "curve",
        .{ 
            .b = b,
            .fpath = "src/curve/curve.zig",
            .target = options.target,
            .test_step = test_step,
            .deps = &.{
                .{ .name = "spline_gym", .module = &spline_gym.root_module },
                .{ .name = "string_stuff", .module = string_stuff },
                .{ .name = "opentime", .module = opentime },
                .{ .name = "otio_allocator", .module = otio_allocator },
                .{ .name = "comath", .module = comath_dep.module("comath") },
            },
        }
    );

    const time_topology = module_with_tests_and_artifact(
        "time_topology",
        .{ 
            .b = b,
            .fpath = "src/time_topology/time_topology.zig",
            .target = options.target,
            .test_step = test_step,
            .deps = &.{
                .{ .name = "string_stuff", .module = string_stuff },
                .{ .name = "opentime", .module = opentime },
                .{ .name = "otio_allocator", .module = otio_allocator },
                .{ .name = "curve", .module = curve },
            },
        }
    );

    const common_deps:[]const std.Build.Module.Import = &.{ 
        // external deps
        .{ .name = "comath", .module = comath_dep.module("comath") },

        // internal deps
        .{ .name = "string_stuff", .module = string_stuff },
        .{ .name = "opentime", .module = opentime },
        .{ .name = "curve", .module = curve },
        .{ .name = "otio_allocator", .module = otio_allocator },
        .{ .name = "time_topology", .module = time_topology },

        // libraries with c components
        .{ .name = "spline_gym", .module = &spline_gym.root_module },
        .{ .name = "sampling", .module = sampling },
    };

    executable(
        b, 
        "wrinkles",
        "/src/wrinkles.zig",
        "/wrinkles_content/",
        options,
        common_deps,
    );
    executable(
        b,
        "curvet",
        "/src/curvet.zig",
        "/wrinkles_content/",
        options,
        common_deps,
    );
    executable(
        b,
        "example_zgui_app",
        "/src/example_zgui_app.zig",
        "/wrinkles_content/",
        options,
        common_deps,
    );
}
