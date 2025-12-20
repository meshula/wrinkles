//! Build script for wrinkles project

const std = @import("std");

const ziis = @import("zgui_cimgui_implot_sokol");

/// check for the `dot` program on $PATH
fn graphviz_dot_on_path(
    allocator: std.mem.Allocator,
) ?[]const u8
{
    const result = std.process.Child.run(
        .{
            .allocator = allocator,
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
    optimize: std.builtin.OptimizeMode,
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

    c_deps: []const *std.Build.Step.Compile = undefined,
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
    options: Options,
    module_deps: []const std.Build.Module.Import,
) !void
{
    const exe = (
        if (options.target.result.cpu.arch.isWasm())
            b.addLibrary(
                .{
                    .name = name,
                    .root_module = b.createModule(
                        .{
                            .root_source_file = b.path(main_file_name),
                            .target = options.target,
                            .optimize = options.optimize,
                        }
                    ),
                    .linkage = .static,
                },
            )
        else b.addExecutable(
            .{
                .name = name,
                .root_module = b.createModule(
                    .{
                        .root_source_file = b.path(main_file_name),
                        .target = options.target,
                        .optimize = options.optimize,
                    },
                ),
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
    }

    exe.want_lto = false;

    // run and install the executable
    if (options.target.result.cpu.arch.isWasm())
    {
        _ = try ziis.build_wasm(
            b,
            .{
                .app_name = name,
                .mod_main = exe.root_module,
                .dep_c_libs = options.c_deps,
                .dep_ziis_builder = options.dep_ziis.?.builder,
                .target = options.target,
                .optimize = options.optimize,
            }
        );
    }
    else
    {
        // an install step specifically for the executable
        const install_exe_step = b.addInstallArtifact(
            exe,
            .{},
        );
        var install_step = b.step(
            "install-" ++ name,
            "Install " ++ name,
        );
        install_step.dependOn(&install_exe_step.step);
        b.getInstallStep().dependOn(install_step);

        // a run step specifically for the executable
        var run_step = b.step(
            "run-" ++ name,
            "Run " ++ name,
        );
        var run_cmd = b.addRunArtifact(exe);
        run_step.dependOn(&run_cmd.step);

        // pass commandline arguments to the executable
        // zig build blah-run -- arg1 arg2 etc
        if (b.args) 
            |args| 
        {
            run_cmd.addArgs(args);
        }
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
    /// file path to root source file
    fpath: []const u8,
    deps: []const std.Build.Module.Import = &.{},
};

/// build a submodule w/ unit tests, docs, and the check step (for zls)
pub fn module_with_tests_and_artifact(
    comptime name: []const u8,
    opts: CreateModuleOptions,
) *std.Build.Module
{
    const mod = opts.b.addModule(
        name,
        .{
            .root_source_file = opts.b.path(opts.fpath),
            .imports = opts.deps,
            .optimize = opts.options.optimize,
            .target = opts.options.target,
        },
    );

    // add dependencies to test
    for (opts.deps)
        |dep_mod|
    {
        mod.addImport(
            dep_mod.name,
            dep_mod.module,
        );
    }

    // unit tests for the module
    const mod_unit_tests = unit_tests: 
    {
        const mod_unit_tests = opts.b.addTest(
            .{
                .name = "test_" ++ name,
                .root_module = mod,
                .filters = &.{
                    opts.options.test_filter orelse &.{},
                },
            },
        );

        // test runner step
        const run_unit_tests = opts.b.addRunArtifact(mod_unit_tests);

        const mod_test_step = opts.b.step(
            "test_" ++ name,
            "Run unit tests for " ++ name,
        );
        mod_test_step.dependOn(&run_unit_tests.step);
        opts.options.test_step.dependOn(mod_test_step);

        // also install the test binary for lldb needs
        const install_test_bin = opts.b.addInstallArtifact(
            mod_unit_tests,
            .{},
        );

        // always install the tests
        opts.options.test_step.dependOn(&install_test_bin.step);

        break :unit_tests mod_unit_tests;
    };

    // docs
    {
        const install_docs = opts.b.addInstallDirectory(
            .{
                .source_dir = mod_unit_tests.getEmittedDocs(),
                .install_dir = .prefix,
                .install_subdir = "docs/" ++ name,
            },
        );

        // each module gets an individual docs step
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
) !void
{
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
            rev_HEAD(b.allocator) catch "COULDNT READ HASH",
        );

        const graphviz_path = b.option(
            []const u8,
            "graphviz_path",
            (
             "path to the `dot` executable from graphviz. Used to generate "
             ++ "diagrams of temporal hierarchies."
            ),
        ) orelse graphviz_dot_on_path(b.allocator);

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
            "enable print messages from opentime.dbg_print",
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

    //
    // submodules and dependencies
    //
    options.dep_ziis = b.dependency(
        "zgui_cimgui_implot_sokol",
        .{
            .optimize = options.optimize,
            .target = options.target,
        },
    );

    const comath_dep = b.dependency(
        "comath",
        .{},
    );

    const wav_dep = b.dependency(
        "zig_wav_io",
        .{
            .target = options.target,
            .optimize = options.optimize,
        },
    ).module("wav_io");

    const string_stuff = module_with_tests_and_artifact(
        "string_stuff",
        .{
            .b = b,
            .options = options,
            .fpath = "src/string_stuff.zig",
            .deps = &.{},
        },
    );

    const kissfft = b.addLibrary(
        .{
            .name = "kissfft",
            .root_module = b.createModule(
                .{
                    .root_source_file = b.path(
                        "libs/wrapped_kissfft.zig"
                    ),
                    .target = options.target,
                    .optimize = options.optimize,
                },
            ),
            .linkage = .static,
        },
    );
    {
        const dep_kissfft = b.dependency(
            "kissfft",
            .{ 
                .target = options.target,
                .optimize = options.optimize,
            },
        );

        kissfft.addIncludePath(dep_kissfft.path("."));
        kissfft.addCSourceFile(
            .{
                .file = dep_kissfft.path("kiss_fft.c"),
                .flags = &C_ARGS,
            },
        );
        // @TODO: fix the WASM build
        // if (options.target.result.cpu.arch.isWasm())
        // {
        //     kissfft.addSystemIncludePath(
        //         ziis.fetchEmSdkIncludePath(
        //             options.dep_ziis.?,
        //             options.optimize,
        //             options.target,
        //         )
        //     );
        // }
    }

    const treecode = module_with_tests_and_artifact(
        "treecode",
        .{
            .b = b,
            .options = options,
            .fpath = "src/treecode/root.zig",
            .deps = &.{
                .{ .name = "build_options", .module = build_options_mod},
            },
        },
    );

    const opentime = module_with_tests_and_artifact(
        "opentime",
        .{
            .b = b,
            .options = options,
            .fpath = "src/opentime/root.zig",
            .deps = &.{
                .{ .name = "string_stuff", .module = string_stuff },
                .{ .name = "comath", .module = comath_dep.module("comath") },
                .{ .name = "build_options", .module = build_options_mod},
            },
        },
    );

    const spline_gym = b.addLibrary(
        .{
            .name = "spline_gym",
            .root_module = b.createModule(
                .{
                    .root_source_file = b.path(
                        "spline-gym/src/hodographs.zig",
                    ),
                    .target = options.target,
                    .optimize = options.optimize,
                },
            ),
            .linkage = .static,
        },
    );
    {
        spline_gym.addIncludePath(b.path("spline-gym/src"));
        spline_gym.addCSourceFile(
            .{
                .file = b.path("spline-gym/src/hodographs.c"),
                .flags = &C_ARGS,
            },
        );
        // @TODO: fix the wasm build
        // if (options.target.result.cpu.arch.isWasm())
        // {
        //     spline_gym.addSystemIncludePath(
        //         ziis.fetchEmSdkIncludePath(
        //             options.dep_ziis.?,
        //             options.optimize,
        //             options.target,
        //         )
        //     );
        //     spline_gym.linkLibC();
        // }
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
        },
    );

    const libsamplerate = b.addLibrary(
        .{
            .name = "libsamplerate",
            .root_module = b.createModule(
                .{
                    .target = options.target,
                    .optimize = options.optimize,
                    .root_source_file = b.path(
                        "libs/wrapped_libsamplerate/wrapped_libsamplerate.zig",
                    ),
                },
            )
        },
    );
    {
        const dep_libsamplerate = b.dependency(
            "libsamplerate",
            .{ 
                .target = options.target,
                .optimize = options.optimize,
            },
        );
        
        libsamplerate.addIncludePath(dep_libsamplerate.path("include"));
        libsamplerate.addIncludePath(dep_libsamplerate.path("src"));
        libsamplerate.addIncludePath(b.path("libs/wrapped_libsamplerate"));

        libsamplerate.addCSourceFile(
            .{
                .file = b.path(
                    "libs/wrapped_libsamplerate/wrapped_libsamplerate.c",
                ),
                .flags = &C_ARGS,
            },
        );
        // if (options.target.result.cpu.arch.isWasm())
        // {
        //     libsamplerate.addSystemIncludePath(
        //         ziis.fetchEmSdkIncludePath(
        //             options.dep_ziis.?,
        //             options.optimize,
        //             options.target,
        //         )
        //     );
        // }
    }

    options.c_deps = &.{
        libsamplerate,
        spline_gym,
        kissfft,
    };

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
        },
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
        },
    );

    const opentimelineio = module_with_tests_and_artifact(
        "opentimelineio",
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
        },
    );

    const opentimelineio_c = b.addLibrary(
        .{
            .name = "opentimelineio_c",
            .root_module = b.createModule(
                .{
                    .target = options.target,
                    .optimize = options.optimize,
                    .root_source_file = b.path(
                        "src/c_binding/opentimelineio_c.zig",
                    ),
                },
            ),
        },
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
        // @TODO: restore WASM build
        // if (options.target.result.cpu.arch.isWasm())
        // {
        //     opentimelineio_c.addSystemIncludePath(
        //         ziis.fetchEmSdkIncludePath(
        //             options.dep_ziis.?,
        //             options.optimize,
        //             options.target,
        //         )
        //     );
        // }
        b.installArtifact(opentimelineio_c);

        const exe = b.addExecutable(
            .{
                .name = "test_opentimelineio_c",
                .root_module = b.createModule(
                    .{
                        .optimize = options.optimize,
                        .target = options.target,
                    },
                ),
            },
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
        // @TODO: fix WASM build
        // if (options.target.result.cpu.arch.isWasm())
        // {
        //     exe.addSystemIncludePath(
        //         ziis.fetchEmSdkIncludePath(
        //             options.dep_ziis.?,
        //             options.optimize,
        //             options.target,
        //         )
        //     );
        // }

        exe.linkLibrary(opentimelineio_c);
        b.installArtifact(exe);

        const run_exe = b.addRunArtifact(exe);
        run_exe.addArg("sample_otio_files/multiple_track.otio");

        if (options.test_filter == null) {
            options.test_step.dependOn(&run_exe.step);
        }
    }

    // Documentation Module that exposes the others (as a sort of landing page)
    const opentimelineio_docs = module_with_tests_and_artifact(
        "docs",
        .{
            .b = b,
            .options = options,
            .fpath = "src/docs/root.zig",
            .deps = &.{
                .{ .name = "string_stuff", .module = string_stuff },
                .{ .name = "opentime", .module = opentime },
                .{ .name = "opentimelineio", .module = opentimelineio },
                .{ .name = "curve", .module = curve },
                .{ .name = "topology", .module = topology },
                .{ .name = "treecode", .module = treecode },
                .{ .name = "sampling", .module = sampling },
                .{ .name = "build_options", .module = build_options_mod},
            },
        },
    );

    {
        const opentimelineio_docs_test = b.addTest(
            .{
                .name = "test_docs",
                .root_module = opentimelineio_docs,
                .filters = &.{
                    options.test_filter orelse &.{},
                },
            },
        );
        const install_docs = b.addInstallDirectory(
            .{
                .source_dir = opentimelineio_docs_test.getEmittedDocs(),
                .install_dir = .prefix,
                .install_subdir = "docs",
            },
        );

        // each module gets an individual docs step
        const docs_step = b.step(
            "docs_wrinkles",
            "User-facing documentation for the wrinkles library.",
        );
        docs_step.dependOn(&install_docs.step);
        options.all_docs_step.dependOn(docs_step);
    }

    //
    // executables
    //
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

        .{ .name = "opentimelineio", .module = opentimelineio },
    };

    // probably gone for good, but haven't removed yet
    try executable(
        b,
        "curvet",
        "src/curvet.zig",
        options,
        common_deps,
    );

    try executable(
        b,
        "sokol_test",
        "src/sokol_test.zig",
        options,
        common_deps,
    );

    try executable(
        b,
        "transformation_visualizer",
        "src/transformation_visualizer.zig",
        options,
        common_deps,
    );

    try executable(
        b,
        "wrinkles_visual_debugger",
        "src/wrinkles_visual_debugger.zig",
        options,
        common_deps,
    );

    try executable(
        b,
        "otio_space_visualizer",
        "src/otio_space_visualizer.zig",
        options,
        common_deps,
    );

    try executable(
        b,
        "otio_leak_test",
        "src/otio_leak_test.zig",
        options,
        common_deps,
    );

    try executable(
        b,
        "otio_dump_graph",
        "src/otio_dump_graph.zig",
        options,
        &.{
            .{ .name = "string_stuff", .module = string_stuff },
            .{ .name = "opentimelineio", .module = opentimelineio },
        },
    );

    try executable(
        b,
        "otio_dump_json",
        "src/otio_dump_json.zig",
        options,
        &.{
            .{ .name = "string_stuff", .module = string_stuff },
            .{ .name = "opentimelineio", .module = opentimelineio },
        },
    );

    try executable(
        b,
        "otio_measure_timeline",
        "src/otio_measure_timeline.zig",
        options,
        &.{
            .{ .name = "string_stuff", .module = string_stuff },
            .{ .name = "opentimelineio", .module = opentimelineio },
            .{ .name = "opentime", .module = opentime },
        },
    );
}
