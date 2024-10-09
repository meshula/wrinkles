//! Build script for wrinkles project

const std = @import("std");
const builtin = @import("builtin");
const ziis = @import("zgui_cimgui_implot_sokol");

/// the minimum required zig version to build this project, manually updated
pub const MIN_ZIG_VERSION = std.SemanticVersion{
    .major = 0,
    .minor = 13,
    .patch = 0,
    .pre = "" 
    // .pre = "dev.46"  <- for setting the dev version string
};

/// guarantee that the zig compiler version is more than the minimum
fn ensureZigVersion() !void 
{
    var installed_ver = builtin.zig_version;
    installed_ver.build = null;

    if (installed_ver.order(MIN_ZIG_VERSION) == .lt) 
    {
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
            , 
            .{ MIN_ZIG_VERSION, installed_ver }
        );

        return error.ZigIsTooOld;
    }
}

/// check for the `dot` program
fn graphviz_dot_on_path() !bool
{
    const result = try std.process.Child.run(
        .{
            .allocator = std.heap.page_allocator,
            .argv = &[_][]const u8{
                "which",
                "dot"
            },
        }
    );

    return result.term.Exited == 0;
}

/// build options for the wrinkles project
pub const Options = struct {
    optimize: std.builtin.Mode,
    target: std.Build.ResolvedTarget,

    /// select which tests to run 
    test_filter: ?[]const u8 = null,

    /// place to put general user-facing compile options that get passed to
    /// each compilation unit.
    common_build_options: *std.Build.Step.Options,

    // common build steps to attach artifacts to

    /// unit test step
    test_step: *std.Build.Step,
    /// documentation generation step
    all_docs_step: *std.Build.Step,
    /// code check step (for zls)
    all_check_step: *std.Build.Step,

    // ziis dep is needed for some internal steps
    dep_ziis: ?*std.Build.Dependency = null,
};

/// c-code compilation arguments
const C_ARGS = [_][]const u8{
    "-std=c11",
    "-fno-sanitize=undefined",
};

/// sign the executable
// pub fn codesign_step_for(
//     install_exe_step: *std.Build.Step,
//     comptime name: []const u8,
//     b: *std.Build,
// ) *std.Build.Step
// {
//     const codesign = b.addSystemCommand(&.{"codesign"});
//     codesign.addArgs(
//         &.{"-f", "-s", "-", "zig-out/bin/" ++ name  }
//     );
//     codesign.step.dependOn(install_exe_step);
//
//     return &codesign.step;
// }

/// Returns the result of running `git rev-parse HEAD`
pub fn rev_HEAD(
    allocator: std.mem.Allocator,
) ![]const u8 
{
    const max = 1024 ;
    const dirg = try std.fs.cwd().openDir(".git", .{});

    const head_file = std.mem.trim(
        u8,
        try dirg.readFileAlloc(
            allocator,
            "HEAD",
            max,
        ),
        "\n"
    );

    return std.mem.trim(
        u8,
        try dirg.readFileAlloc(
            allocator,
            head_file[5..],
            max
        ),
        "\n"
    );
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
    const exe = if (options.target.result.isWasm()) 
        b.addStaticLibrary(
            .{
                .name = name,
                .root_source_file = b.path(main_file_name),
                .target = options.target,
                .optimize = options.optimize,
            }
        )
        else b.addExecutable(
        .{
            .name = name,
            .root_source_file = b.path(main_file_name),
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
        exe.root_module.addOptions(
            "build_options",
            options.common_build_options,
        );

        const exe_options = b.addOptions();
        exe.root_module.addOptions(
            "exe_build_options",
            exe_options
        );

        var content_dir_lp = b.path("src/" ++ source_dir_path);
        var content_dir_path = content_dir_lp.getPath(b);

        if (!options.target.result.isWasm()) {
            const subdir = "bin/" ++ name ++ "_content";
            const install_content_step = b.addInstallDirectory(
                .{
                    .source_dir = content_dir_lp,
                    .install_dir = .{ .custom = "" },
                    .install_subdir = subdir,
                }
            );
            exe.step.dependOn(&install_content_step.step);
            content_dir_path = b.getInstallPath(
                .bin,
                subdir
            );
        }

        exe_options.addOption(
            []const u8,
            "content_dir",
            content_dir_path,
        );

    }

    exe.want_lto = false;

    // run and install the executable
    if (!options.target.result.isWasm())
    {
        const install_exe_step = &b.addInstallArtifact(
            exe,
            .{}
        ).step;

        const install = b.step(
            name,
            "Build/install '" ++ name ++ "' executable"
        );
        // install.dependOn(codesign_exe_step);
        install.dependOn(install_exe_step);

        var run_cmd = b.addRunArtifact(exe).step;
        run_cmd.dependOn(install);

        const run_step = b.step(
            name ++ "-run",
            "Run '" ++ name ++ "' executable"
        );
        run_step.dependOn(&run_cmd);

        b.getInstallStep().dependOn(install);
    }
    else
    {
        const emsdk = ziis.fetchEmSdk(
            options.dep_ziis.?,
            options.optimize,
            options.target,
        );

        for (module_deps) 
            |mod| 
        {
            mod.module.addSystemIncludePath(
                ziis.fetchEmSdkIncludePath(
                    options.dep_ziis.?,
                    options.optimize,
                    options.target,
                )
            );
        }

        const shell_path_abs = ziis.fetchShellPath(
            options.dep_ziis.?,
            options.optimize,
            options.target,
        );

        const link_step = try ziis.emLinkStep(
            b,
            .{
                .lib_main = exe,
                .target = options.target,
                .optimize = options.optimize,
                .emsdk = emsdk,
                // .use_webgpu = backend == .wgpu,
                .use_webgl2 = true,
                .use_emmalloc = true,
                .use_filesystem = true,
                .shell_file_path = shell_path_abs,
                .extra_args = &.{
                    "-sUSE_OFFSET_CONVERTER=1",
                    // "-sTOTAL_STACK=1024MB",
                     "-sALLOW_MEMORY_GROWTH=1",
                     "-sASSERTIONS=1",
                     "-sSAFE_HEAP=0",
                     "-g",
                     "-gsource-map",
                },
            }
        );
        const run = ziis.emRunStep(
            b,
            .{ 
                .name = name,
                .emsdk = emsdk 
            }
        );
        run.step.dependOn(&link_step.step);
        b.step(
            name ++ "-run",
            "Run " ++ name
        ).dependOn(&run.step);
    }

    // docs
    {
        const install_docs = b.addInstallDirectory(
            .{
                .source_dir = exe.getEmittedDocs(),
                .install_dir = .prefix,
                .install_subdir = "docs",
            }
        );

        const docs_step = b.step(
            "docs_exe_" ++ name,
            "Copy documentation artifacts to prefix path"
        );
        docs_step.dependOn(&install_docs.step);
    }

    // zls check
    {
        options.all_check_step.dependOn(&exe.step);
    }
}

/// options for module_with_tests_and_artifact
pub const CreateModuleOptions = struct {
    b: *std.Build,
    options: Options,
    fpath: []const u8,
    deps: []const std.Build.Module.Import = &.{},
};

/// build a submodule w/ unit tests
pub fn module_with_tests_and_artifact(
    comptime name: []const u8,
    opts:CreateModuleOptions,
) *std.Build.Module 
{
    const mod = opts.b.createModule(
        .{
            .root_source_file = opts.b.path(opts.fpath),
            .imports = opts.deps,
            .optimize = opts.options.optimize,
            .target = opts.options.target,
        }
    );

    const mod_unit_tests = opts.b.addTest(
        .{
            .name = "test_" ++ name,
            .root_source_file = opts.b.path(opts.fpath),
            .optimize = opts.options.optimize,
            .target =opts.options.target,
            .filter = opts.options.test_filter orelse &.{},
        }
    );

    mod_unit_tests.root_module.addOptions(
        "build_options",
        opts.options.common_build_options,
    );

    // unit tests for the module
    {
        for (opts.deps) 
            |dep_mod| 
        {
            mod_unit_tests.root_module.addImport(
                dep_mod.name,
                dep_mod.module
            );
        }

        const run_unit_tests = opts.b.addRunArtifact(mod_unit_tests);
        opts.options.test_step.dependOn(&run_unit_tests.step);

        // also install the test binary for lldb needs
        const install_test_bin = opts.b.addInstallArtifact(
            mod_unit_tests,
            .{}
        );

        opts.options.test_step.dependOn(&install_test_bin.step);
    }

    // docs
    {
        const install_docs = opts.b.addInstallDirectory(
            .{
                .source_dir = mod_unit_tests.getEmittedDocs(),
                .install_dir = .prefix,
                .install_subdir = "docs/" ++ name,
            }
        );

        const docs_step = opts.b.step(
            "docs_" ++ name,
            "Copy documentation artifacts to prefix path"
        );
        docs_step.dependOn(&install_docs.step);
        opts.options.all_docs_step.dependOn(docs_step);
    }

    // zls checks
    {
        opts.options.all_check_step.dependOn(&mod_unit_tests.step);
    }

    return mod;
}

/// main entry point
pub fn build(
    b: *std.Build,
) void 
{
    ensureZigVersion() catch return;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    //
    // Options and system checks
    //
    var options = Options{
        .optimize = b.standardOptimizeOption(.{}),
        .target = b.standardTargetOptions(.{}),
        .test_filter = b.option(
            []const u8,
            "test-filter",
            "filter for tests to run"
        ) orelse null,

        .common_build_options = b.addOptions(),

        // steps
        .test_step = b.step(
            "test",
            "step to run all unit tests",
        ),
        .all_docs_step = b.step(
            "docs",
            "build the documentation for the entire library",
        ),
        .all_check_step = b.step(
            "check",
            "Check if everything compiles",
        ),
    };

    {
        // configure build options (flags from commandline and such)
        options.common_build_options.addOption(
            []const u8,
            "hash",
            rev_HEAD(allocator) catch "COULDNT READ HASH",
        );

        const graphviz_dot_on = graphviz_dot_on_path() catch false;

        if (graphviz_dot_on == false) {
            std.log.warn("`dot` program not on path.\n",.{});
        }

        options.common_build_options.addOption(
            bool,
            "graphviz_dot_on",
            graphviz_dot_on,
        );

        const debug_graph_construction_trace_messages = b.option(
            bool,
            "debug_graph_construction_trace_messages",
            "print OTIO graph traversal trace info during "
            ++ "projection operator construction"
        ) orelse false;

        options.common_build_options.addOption(
            bool,
            "debug_graph_construction_trace_messages", 
            debug_graph_construction_trace_messages,
        );

        const run_perf_tests = b.option(
            bool,
            "run_perf_tests",
            "run (potentially slow) performance stress tests",
        ) orelse false;

        options.common_build_options.addOption(
            bool,
            "run_perf_tests", 
            run_perf_tests,
        );
    }

    // submodules and dependencies
    options.dep_ziis = b.dependency(
        "zgui_cimgui_implot_sokol",
        .{
            .optimize = options.optimize,
            .target = options.target,
        }
    );

    const comath_dep = b.dependency(
        "comath",
        .{
            .target = options.target,
            .optimize = options.optimize,
        }
    );

    const wav_dep = module_with_tests_and_artifact(
        "wav",
        .{
            .b = b,
            .options = options,
            .fpath = "libs/zig-wav/src/wav.zig",
        }
    );

    const string_stuff = module_with_tests_and_artifact(
        "string_stuff",
        .{
            .b = b,
            .options = options,
            .fpath = "src/string_stuff.zig",
        }
    );

    const kissfft = b.addStaticLibrary(
        .{
            .name = "kissfft",
            .target = options.target,
            .optimize = options.optimize,
            .root_source_file = b.path(
                "libs/wrapped_kissfft.zig"
            ),
        }
    );
    {
        kissfft.addIncludePath(b.path("./libs/kissfft"));
        kissfft.addCSourceFile(
            .{ 
                .file = b.path("./libs/kissfft/kiss_fft.c"),
                .flags = &C_ARGS
            }
        );
        if (options.target.result.isWasm()) {
            kissfft.addSystemIncludePath(
                ziis.fetchEmSdkIncludePath(
                    options.dep_ziis.?,
                    options.optimize,
                    options.target,
                )
            );
        }
    }

    const treecode = module_with_tests_and_artifact(
        "treecode_lib",
        .{ 
            .b = b,
            .options = options,
            .fpath = "src/treecode.zig",
            .deps = &.{},
        }
    );

    const opentime = module_with_tests_and_artifact(
        "opentime_lib",
        .{ 
            .b = b,
            .options = options,
            .fpath = "src/opentime/opentime.zig",
            .deps = &.{
                .{ .name = "string_stuff", .module = string_stuff },
                .{ .name = "comath", .module = comath_dep.module("comath") },
            },
        }
    );

    const spline_gym = b.addStaticLibrary(
        .{
            .name = "spline_gym",
            .target = options.target,
            .optimize = options.optimize,
            .root_source_file = b.path(
                "./spline-gym/src/hodographs.zig" 
            ),
        }
    );
    {
        spline_gym.addIncludePath(b.path("./spline-gym/src"));
        spline_gym.addCSourceFile(
            .{ 
                .file = b.path("./spline-gym/src/hodographs.c"),
                .flags = &C_ARGS
            }
        );
        if (options.target.result.isWasm()) {
            spline_gym.addSystemIncludePath(
                ziis.fetchEmSdkIncludePath(
                    options.dep_ziis.?,
                    options.optimize,
                    options.target,
                )
            );
        }
        b.installArtifact(spline_gym);
    }

    const curve = module_with_tests_and_artifact(
        "curve",
        .{ 
            .b = b,
            .options = options,
            .fpath = "src/curve/curve.zig",
            .deps = &.{
                .{ .name = "spline_gym", .module = &spline_gym.root_module },
                .{ .name = "string_stuff", .module = string_stuff },
                .{ .name = "opentime", .module = opentime },
                .{ .name = "comath", .module = comath_dep.module("comath") },
            },
        }
    );

    const libsamplerate = b.addStaticLibrary(
        .{
            .name = "libsamplerate",
            .target = options.target,
            .optimize = options.optimize,
            .root_source_file = b.path(
                    "libs/wrapped_libsamplerate/wrapped_libsamplerate.zig"
            ),
        }
    );
    {
        libsamplerate.addIncludePath(
            b.path("./libs/wrapped_libsamplerate/libsamplerate/include")
        );
        libsamplerate.addIncludePath(
            b.path("./libs/wrapped_libsamplerate")
        );
        libsamplerate.addCSourceFile(
            .{ 
                .file = b.path(
                    "./libs/wrapped_libsamplerate/wrapped_libsamplerate.c"
                ),
                .flags = &C_ARGS
            }
        );
        if (options.target.result.isWasm()) {
            libsamplerate.addSystemIncludePath(
                ziis.fetchEmSdkIncludePath(
                    options.dep_ziis.?,
                    options.optimize,
                    options.target,
                )
            );
        }
    }

    const time_topology = module_with_tests_and_artifact(
        "time_topology",
        .{ 
            .b = b,
            .options = options,
            .fpath = "src/time_topology/time_topology.zig",
            .deps = &.{
                .{ .name = "opentime", .module = opentime },
                .{ .name = "curve", .module = curve },
            },
        }
    );

    _ = module_with_tests_and_artifact(
        "mapping",
        .{ 
            .b = b,
            .options = options,
            .fpath = "src/time_topology/mapping.zig",
            .deps = &.{
                .{ .name = "opentime", .module = opentime },
                .{ .name = "curve", .module = curve },
            },
        }
    );

    const sampling = module_with_tests_and_artifact(
        "sampling",
        .{
            .b = b,
            .options = options,
            .fpath = "src/sampling.zig",
            .deps = &.{
                .{ 
                    .name = "libsamplerate",
                    .module = &libsamplerate.root_module, 
                },
                .{
                    .name = "kissfft",
                    .module = &kissfft.root_module,
                },
                .{ .name = "curve", .module = curve },
                .{ .name = "wav", .module = wav_dep },
                .{ .name = "opentime", .module = opentime, },
                .{ .name = "time_topology", .module = time_topology, },
            },
        }
    );

    const opentimelineio = module_with_tests_and_artifact(
        "opentimelineio_lib",
        .{ 
            .b = b,
            .options = options,
            .fpath = "src/opentimelineio.zig",
            .deps = &.{
                .{ .name = "string_stuff", .module = string_stuff },
                .{ .name = "opentime", .module = opentime },
                .{ .name = "curve", .module = curve },
                .{ .name = "time_topology", .module = time_topology },
                .{ .name = "treecode", .module = treecode },
                .{ .name = "sampling", .module = sampling },
            },
        }
    );
    opentimelineio.addOptions(
        "build_options",
        options.common_build_options
    );

    const opentimelineio_c = b.addStaticLibrary(
        .{
            .name = "opentimelineio_c",
            .target = options.target,
            .optimize = options.optimize,
            .root_source_file = b.path(
                "src/c_binding/opentimelineio_c.zig"
            ),
        }
    );
    {
        opentimelineio_c.addIncludePath(b.path("src/c_binding/"));
        opentimelineio_c.root_module.addImport(
            "opentimelineio",
            opentimelineio
        );
        opentimelineio_c.root_module.addImport(
            "time_topology",
            time_topology
        );
        opentimelineio_c.linkLibCpp();
        if (options.target.result.isWasm()) {
            opentimelineio_c.addSystemIncludePath(
                ziis.fetchEmSdkIncludePath(
                    options.dep_ziis.?,
                    options.optimize,
                    options.target,
                )
            );
        }
        b.installArtifact(opentimelineio_c);

        const exe = b.addExecutable(
            .{
                .name = "test_opentimelineio_c",
                .optimize = options.optimize,
                .target = options.target,
            }
        );
        exe.addCSourceFile(
            .{
                .file = b.path(
                    "src/c_binding/test_opentimelineio_c.c"
                ),
                .flags = &C_ARGS,
            },
        );
        exe.addIncludePath(b.path("src/c_binding/"));
        exe.linkLibC();
        if (options.target.result.isWasm()) 
        {
            exe.addSystemIncludePath(
                ziis.fetchEmSdkIncludePath(
                    options.dep_ziis.?,
                    options.optimize,
                    options.target,
                )
            );
        }

        exe.linkLibrary(opentimelineio_c);
        b.installArtifact(exe);

        const run_exe = b.addRunArtifact(exe);
        run_exe.addArg("sample_otio_files/multiple_track.otio");
        options.test_step.dependOn(&run_exe.step);
    }

    const sokol_app_wrapper = module_with_tests_and_artifact(
        "sokol_app_wrapper",
        .{ 
            .b = b,
            .options = options,
            .fpath = "src/sokol_app_wrapper.zig",
            .deps = &.{
                .{ 
                    .name = "zgui_cimgui_implot_sokol",
                    .module = options.dep_ziis.?.module(
                        "zgui_cimgui_implot_sokol"
                    )
                }
            },
        }
    );

    // executables
    const common_deps:[]const std.Build.Module.Import = &.{ 
        // external deps
        .{ .name = "comath", .module = comath_dep.module("comath") },
        .{ .name = "wav", .module = wav_dep },
        .{ 
            .name = "zgui_cimgui_implot_sokol",
            .module = options.dep_ziis.?.module("zgui_cimgui_implot_sokol") 
        },

        // internal deps
        .{ .name = "string_stuff", .module = string_stuff },
        .{ .name = "opentime", .module = opentime },
        .{ .name = "curve", .module = curve },
        .{ .name = "time_topology", .module = time_topology },

        // libraries with c components
        .{ .name = "spline_gym", .module = &spline_gym.root_module },
        .{ .name = "sampling", .module = sampling },
        .{ .name = "sokol_app_wrapper", .module = sokol_app_wrapper },
    };
    executable(
        b,
        "curvet",
        "src/curvet.zig",
        "/wrinkles_content/",
        options,
        common_deps,
    );

    executable(
        b,
        "sokol_test",
        "src/sokol_test.zig",
        "/wrinkles_content/",
        options,
        common_deps,
    );

    executable(
        b,
        "transformation_visualizer",
        "src/transformation_visualizer.zig",
        "/wrinkles_content/",
        options,
        common_deps,
    );
}
