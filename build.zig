//! Build script for wrinkles project

const std = @import("std");
const builtin = @import("builtin");
const ziis = @import("zgui_cimgui_implot_sokol");

/// check for the `dot` program on $PATH
fn graphviz_dot_on_path() ?[]const u8
{
    const result = std.process.Child.run(
        .{
            .allocator = std.heap.page_allocator,
            .argv = &[_][]const u8{
                "which",
                "dot"
            },
        }
    ) catch return null;

    if (result.term.Exited == 0) {
        const path = std.mem.trim(
            u8,
            result.stdout,
            "\n "
        );
        return path;
    }

    return null;
}

/// build options for the wrinkles project
pub const Options = struct {
    optimize: std.builtin.Mode,
    target: std.Build.ResolvedTarget,

    /// select which tests to run
    test_filter: ?[]const u8 = null,

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
        "\n",
    );

    // trim spaces and newlines out of returned string
    return std.mem.trim(
        u8,
        try dirg.readFileAlloc(
            allocator,
            head_file[5..],
            max
        ),
        "\n",
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
    const exe = (
        if (options.target.result.cpu.arch.isWasm())
            b.addStaticLibrary(
                .{
                    .name = name,
                    .root_source_file = b.path(main_file_name),
                    .target = options.target,
                    .optimize = options.optimize,
                },
            )
        else b.addExecutable(
            .{
                .name = name,
                .root_source_file = b.path(main_file_name),
                .target = options.target,
                .optimize = options.optimize,
            },
        )
    );

    for (module_deps)
        |mod|
    {
        exe.root_module.addImport(mod.name, mod.module);
    }

    // options for exposing the content directory and build hash
    {
        const exe_options = b.addOptions();
        exe.root_module.addOptions(
            "exe_build_options",
            exe_options,
        );

        var content_dir_lp = b.path("src/" ++ source_dir_path);
        var content_dir_path = content_dir_lp.getPath(b);

        if (!options.target.result.cpu.arch.isWasm())
        {
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
                subdir,
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
    if (!options.target.result.cpu.arch.isWasm())
    {
        const install_exe_step = &b.addInstallArtifact(
            exe,
            .{},
        ).step;

        const install = b.step(
            name,
            "Build/install '" ++ name ++ "' executable",
        );
        // install.dependOn(codesign_exe_step);
        install.dependOn(install_exe_step);

        var run_cmd = b.addRunArtifact(exe).step;
        run_cmd.dependOn(install);

        const run_step = b.step(
            name ++ "-run",
            "Run '" ++ name ++ "' executable",
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
                     "-fsanitize=undefined",
                },
            },
        );
        const run = ziis.emRunStep(
            b,
            .{
                .name = name,
                .emsdk = emsdk,
            },
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
            },
        );

        const docs_step = b.step(
            "docs_exe_" ++ name,
            "Copy documentation artifacts to prefix path",
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
            .{},
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
            "Copy documentation artifacts to prefix path",
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

/// main entry point for building wrinkles
pub fn build(
    b: *std.Build,
) void
{
    var arena = std.heap.ArenaAllocator.init(
        std.heap.page_allocator
    );
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
            "filter for tests to run",
        ) orelse null,

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

    const build_options = b.addOptions();
    {
        // configure build options (flags from commandline and such)
        build_options.addOption(
            []const u8,
            "hash",
            rev_HEAD(allocator) catch "COULDNT READ HASH",
        );

        const graphviz_path = b.option(
            []const u8,
            "graphviz_path",
            (
             "path to the `dot` executable from graphviz. Used to generate "
             ++ "diagrams of temporal hierarchies."
            ),
        ) orelse graphviz_dot_on_path();

        if (graphviz_path == null) {
            std.log.warn(
                "`dot` program not on path and not passed in, disabling"
                ++ " graphviz/dot support.\n",
                .{}
            );
        }

        build_options.addOption(
            ?[]const u8,
            "graphviz_dot_path",
            graphviz_path,
        );

        const debug_graph_construction_trace_messages = b.option(
            bool,
            "debug_graph_construction_trace_messages",
            (
                              "print OTIO graph traversal trace info during "
                              ++ "projection operator construction.  Implies "
                              ++ "-Ddebug_print_messages=true"
            ),
        ) orelse false;

        build_options.addOption(
            bool,
            "debug_graph_construction_trace_messages",
            debug_graph_construction_trace_messages,
        );

        const debug_print_messages = b.option(
            bool,
            "debug_print_messages",
            "enable print messages from opentime.dbg_print"

        ) orelse false;

        build_options.addOption(
            bool,
            "debug_print_messages",
            debug_print_messages,
        );

        const write_test_wavs = b.option(
            bool,
            "write_sampling_test_wave_files",
            "write data generated by sampling unit tests out"
            ++ " to wave files for manual inspection",
        ) orelse false;

        build_options.addOption(
            bool, 
            "write_sampling_test_wave_files",
            write_test_wavs,
        );

        const test_data_out_dir = b.option(
            []const u8,
            "test_data_out_dir",
            "Directory to write test data out to "
            ++ "(temporary wavs, pngs from graph renderings, etc.)."
            ,
            // @TODO: should probably not be /var/tmp/ for portability
        ) orelse "/var/tmp";

        build_options.addOption(
            []const u8, 
            "test_data_out_dir",
            test_data_out_dir,
        );
    }

    // create module turns the options into a module that can be linked into
    // stuff.  Bafflingly, without this you get "this is in multiple files"
    // error.
    const build_options_mod = build_options.createModule();

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

    const wav_dep = b.dependency(
        "zig_soundio",
        .{
            .target = options.target,
            .optimize = options.optimize,
        },
    ).module("wav");

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
                "libs/wrapped_kissfft.zig",
            ),
        }
    );
    {
        const dep_kissfft = b.dependency(
            "kissfft",
            .{ 
                .target = options.target,
                .optimize = options.optimize,
            }
        );

        kissfft.addIncludePath(dep_kissfft.path("."));
        kissfft.addCSourceFile(
            .{
                .file = dep_kissfft.path("kiss_fft.c"),
                .flags = &C_ARGS,
            }
        );
        if (options.target.result.cpu.arch.isWasm())
        {
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
            .fpath = "src/opentime/root.zig",
            .deps = &.{
                .{ .name = "string_stuff", .module = string_stuff },
                .{ .name = "comath", .module = comath_dep.module("comath") },
                .{ .name = "build_options", .module = build_options_mod},
            },
        }
    );

    const spline_gym = b.addStaticLibrary(
        .{
            .name = "spline_gym",
            .target = options.target,
            .optimize = options.optimize,
            .root_source_file = b.path(
                "spline-gym/src/hodographs.zig",
            ),
        }
    );
    {
        spline_gym.addIncludePath(b.path("spline-gym/src"));
        spline_gym.addCSourceFile(
            .{
                .file = b.path("spline-gym/src/hodographs.c"),
                .flags = &C_ARGS,
            }
        );
        if (options.target.result.cpu.arch.isWasm())
        {
            spline_gym.addSystemIncludePath(
                ziis.fetchEmSdkIncludePath(
                    options.dep_ziis.?,
                    options.optimize,
                    options.target,
                )
            );
            spline_gym.linkLibC();
        }
        b.installArtifact(spline_gym);
    }

    const curve = module_with_tests_and_artifact(
        "curve",
        .{
            .b = b,
            .options = options,
            .fpath = "src/curve/root.zig",
            .deps = &.{
                .{ .name = "spline_gym", .module = spline_gym.root_module },
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
                    "libs/wrapped_libsamplerate/wrapped_libsamplerate.zig",
            ),
        }
    );
    {
        const dep_libsamplerate = b.dependency(
            "libsamplerate",
            .{ 
                .target = options.target,
                .optimize = options.optimize,
            }
        );
        
        libsamplerate.addIncludePath(dep_libsamplerate.path("include"));
        libsamplerate.addIncludePath(dep_libsamplerate.path("src"));
        libsamplerate.addIncludePath(
            b.path("libs/wrapped_libsamplerate")
        );
        libsamplerate.addCSourceFile(
            .{
                .file = b.path(
                    "libs/wrapped_libsamplerate/wrapped_libsamplerate.c",
                ),
                .flags = &C_ARGS
            },
        );
        if (options.target.result.cpu.arch.isWasm())
        {
            libsamplerate.addSystemIncludePath(
                ziis.fetchEmSdkIncludePath(
                    options.dep_ziis.?,
                    options.optimize,
                    options.target,
                )
            );
        }
    }

    const topology = module_with_tests_and_artifact(
        "topology",
        .{
            .b = b,
            .options = options,
            .fpath = "src/topology/root.zig",
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
                    .module = libsamplerate.root_module,
                },
                .{
                    .name = "kissfft",
                    .module = kissfft.root_module,
                },
                .{ .name = "curve", .module = curve },
                .{ .name = "wav", .module = wav_dep },
                .{ .name = "opentime", .module = opentime, },
                .{ .name = "topology", .module = topology, },
                .{ .name = "build_options", .module = build_options_mod, },
            },
        }
    );

    const opentimelineio = module_with_tests_and_artifact(
        "opentimelineio_lib",
        .{
            .b = b,
            .options = options,
            .fpath = "src/opentimelineio/root.zig",
            .deps = &.{
                .{ .name = "string_stuff", .module = string_stuff },
                .{ .name = "opentime", .module = opentime },
                .{ .name = "curve", .module = curve },
                .{ .name = "topology", .module = topology },
                .{ .name = "treecode", .module = treecode },
                .{ .name = "sampling", .module = sampling },
                .{ .name = "build_options", .module = build_options_mod},
            },
        }
    );

    const opentimelineio_c = b.addStaticLibrary(
        .{
            .name = "opentimelineio_c",
            .target = options.target,
            .optimize = options.optimize,
            .root_source_file = b.path(
                "src/c_binding/opentimelineio_c.zig",
            ),
        }
    );
    {
        opentimelineio_c.addIncludePath(b.path("src/c_binding/"));
        opentimelineio_c.root_module.addImport(
            "opentime",
            opentime,
        );
        opentimelineio_c.root_module.addImport(
            "opentimelineio",
            opentimelineio
        );
        opentimelineio_c.root_module.addImport(
            "topology",
            topology
        );
        opentimelineio_c.linkLibCpp();
        if (options.target.result.cpu.arch.isWasm())
        {
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
                    "src/c_binding/test_opentimelineio_c.c",
                ),
                .flags = &C_ARGS,
            },
        );
        exe.addIncludePath(b.path("src/c_binding/"));
        exe.linkLibC();
        if (options.target.result.cpu.arch.isWasm())
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

        if (options.test_filter == null) {
            options.test_step.dependOn(&run_exe.step);
        }
    }

    // executables
    const common_deps:[]const std.Build.Module.Import = &.{
        .{ .name = "build_options", .module = build_options_mod},

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
        .{ .name = "topology", .module = topology },

        // libraries with c components
        .{ .name = "spline_gym", .module = spline_gym.root_module },
        .{ .name = "sampling", .module = sampling },
    };

    // probably gone for good, but haven't removed yet
    // executable(
    //     b,
    //     "curvet",
    //     "src/curvet.zig",
    //     "/wrinkles_content/",
    //     options,
    //     common_deps,
    // );

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

    executable(
        b,
        "wrinkles_visual_debugger",
        "src/wrinkles_visual_debugger.zig",
        "/wrinkles_content/",
        options,
        common_deps,
    );
}
