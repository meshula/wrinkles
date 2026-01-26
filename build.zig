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
    comptime description: []const u8,
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
            "Install " ++ name ++ ": " ++ description,
        );
        install_step.dependOn(&install_exe_step.step);
        b.getInstallStep().dependOn(install_step);

        // a run step specifically for the executable
        var run_step = b.step(
            "run-" ++ name,
            "Run " ++ name ++ ": " ++ description,
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
            (
                  "Copy documentation artifacts to prefix path for " 
                  ++ name
            ),
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

/// Schema update step: regenerate tlb.zig from tlb.fbs (Schema)
/// Requires: flatc (FlatBuffers compiler) to be installed and on PATH
/// Note that both the tlb.fbs and the resulting tlb.zig are checked into the
/// tree.
///
/// Other intermediates are NOT copied to the source tree and versioned,
/// although they could be.
///
/// Note that this means that unless the .fbs file is changed, flatc does not
/// need to be installed on a development system.
fn update_tlb_schema(
    b: *std.Build,
    dep_flatbuffers: *std.Build.Dependency,
    options: Options,
) *std.Build.Module
{
    const update_schema_step = b.step(
        "update_tlb_schema",
        (
            "Regenerate FlatBuffers schema (tlb.fbs -> tlb.bfbs "
            ++ "-> tlb.zon -> tlb.zig).  Only needs to be run when the "
            ++ ".fbs file (schema) has been changed."
        ),
    );

    // Step 1: Run flatc to generate .bfbs from .fbs
    ///////////////////////////////////////////////////////////////////////////
    const flatc_cmd = b.addSystemCommand(&.{"flatc"});
    flatc_cmd.addArgs(
        &.{
            "-b",
            "--schema",
            "--bfbs-comments",
            "--bfbs-builtins",
            "-o",
        }
    );
    flatc_cmd.setName("Run flatc (tlb.fbs -> tlb.bfbs)");

    const bfbs_dir = flatc_cmd.addOutputDirectoryArg("flatbuf_files");

    // input file (the source tlb.fbs schema file to convert)
    flatc_cmd.addFileArg(b.path("tlb_schema/tlb.fbs"));

    // output (bfbs)
    const tlb_bfbs_path = bfbs_dir.path( b, "tlb.bfbs");

    // Step 2: Run zfbs-parse to generate .zon from .bfbs
    ///////////////////////////////////////////////////////////////////////////

    // Step 2.1: first compilte zfbs-parse
    const zfbs_parse = b.addExecutable(
        .{
            .name = "zfbs-parse-runner",
            .root_module = b.createModule(
                .{
                    .root_source_file = dep_flatbuffers.path(
                        "src/parse.zig"
                    ),
                    .target = options.target,
                    .optimize = options.optimize,
                    .imports = &.{
                        .{
                            .name = "flatbuffers",
                            .module = dep_flatbuffers.module(
                                "flatbuffers"
                            ),
                        },
                    },
                }
            ),
        }
    );
    zfbs_parse.step.name = "compile exe zfbs-parse-runner (program that will convert .bfbs -> zon)";

    // Step 2.2: ...then use it to convert the bfbs to zon
    const parse_cmd = b.addRunArtifact(zfbs_parse);
    parse_cmd.step.name = "run exe zfbs-parse-runner (tlb.bfbs -> tlb.zon)";
    parse_cmd.addFileArg(tlb_bfbs_path);
    parse_cmd.step.dependOn(&flatc_cmd.step);
    const zon_output = parse_cmd.captureStdOut();

    // XXX: zig 0.15.2: in 0.16 captureStdOut has a second argument which
    //      allows you to specify the name of the captured output, until then
    //      this is needed
    parse_cmd.captured_stdout.?.basename = "stdout.zon";

    // Step 3: Run zfbs-generate to generate .zig from .zon
    ///////////////////////////////////////////////////////////////////////////

    // Step 3.1: compile the zfbs-generate program
    const zfbs_generate = b.addExecutable(
        .{
            .name = "zfbs-generate-runner",
            .root_module = b.createModule(
                .{
                    .root_source_file = dep_flatbuffers.path(
                        "src/generate.zig"
                    ),
                    .target = options.target,
                    .optimize = options.optimize,
                    .imports = &.{
                        .{
                            .name = "flatbuffers",
                            .module = dep_flatbuffers.module(
                                "flatbuffers"
                            ),
                        },
                    },
                },
            ),
        },
    );
    zfbs_generate.step.name = "zfbs-generate-runner (tlb.zon -> tlb.zig)";

    // Step 3.2: run the generator and produce the .zig file
    const generate_cmd = b.addRunArtifact(zfbs_generate);
    // generate_cmd.addFileArg(bfbs_dir.path(b, "tlb.zon"));
    generate_cmd.addFileArg(zon_output);
    generate_cmd.step.dependOn(&parse_cmd.step);
    const zig_output = generate_cmd.captureStdOut();

    // Step 3.3: copy the result to the source tree with the correct name
    const tlb_zig_source_path = "tlb_schema/tlb.zig";
    const install_zig = b.addUpdateSourceFiles();
    install_zig.step.name = (
        "UpdateSourceFiles (copy tlb.zig -> src/tlb_schema/tlb.zig)"
    );
    install_zig.step.dependOn(&generate_cmd.step);
    install_zig.addCopyFileToSource(
        zig_output,
        tlb_zig_source_path,
    );

    update_schema_step.dependOn(&install_zig.step);

    // Step 4: build a module using the source tree tlb.zig file
    ///////////////////////////////////////////////////////////////////////////

    // Note that the return module depends on the source file, which is
    // installed to the source tree.  This means that most users who aren't
    // updating the TLB Schema won't need flatc installed to compile the
    // project.
    //
    // In other words, when the tlb schema is updated, update tlb walks through
    // the steps of generating a fresh zig file that gets checked into the repo
    // and distributed.
    return b.addModule(
        "tlb_parser", 
        .{
            .root_source_file = b.path(tlb_zig_source_path),
            .target = options.target,
            .optimize = options.optimize,
            .imports = &.{
                .{
                    .name = "flatbuffers",
                    .module = dep_flatbuffers.module("flatbuffers") 
                },
            },
        },
    );
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

        const enable_tlb_timing = b.option(
            bool,
            "enable_tlb_timing",
            "Enable TLB serialization timing output (default: false)",
        ) orelse false;

        build_options.addOption(
            bool,
            "enable_tlb_timing",
            enable_tlb_timing,
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

    const cpp_test_output = b.option(
        bool,
        "cpp_test_output",
        "Show C++ test output (default: false, tests run silently)",
    ) orelse false;

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

    const dep_ziggy = b.dependency(
        "ziggy",
        .{
            .target = options.target,
            .optimize = options.optimize,
        }
    );

    const dep_flatbuffers = b.dependency(
        "flatbuffers",
        .{
            .target = options.target,
            .optimize = options.optimize,
        }
    );

    const tlb_schema = update_tlb_schema(
        b,
        dep_flatbuffers,
        options,
    );

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
                .{ .name = "ziggy", .module = dep_ziggy.module("ziggy") },
                .{ .name = "flatbuffers", .module = dep_flatbuffers.module("flatbuffers") },
                .{ .name = "tlb_schema", .module = tlb_schema },
            },
        },
    );

    const opentimelineio_c = b.addLibrary(
        .{
            .name = "opentimelineio_c",
            // Use dynamic linkage for Python bindings 
            // (static has __divtf3 symbol issues)
            .linkage = .dynamic,
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
        "Interactive curve editor and visualizer",
        "src/curvet.zig",
        options,
        common_deps,
    );

    try executable(
        b,
        "sokol_test",
        "Sokol graphics backend test",
        "src/sokol_test.zig",
        options,
        common_deps,
    );

    try executable(
        b,
        "transformation_visualizer",
        "Visualize time transformations between spaces",
        "src/transformation_visualizer.zig",
        options,
        common_deps,
    );

    try executable(
        b,
        "wrinkles_visual_debugger",
        "Visual debugger for wrinkles data structures",
        "src/wrinkles_visual_debugger.zig",
        options,
        common_deps,
    );

    try executable(
        b,
        "otio_space_visualizer",
        "Visualize OTIO timeline coordinate spaces",
        "src/otio_space_visualizer.zig",
        options,
        common_deps,
    );

    try executable(
        b,
        "otio_leak_test",
        "Memory leak detection test for OTIO parsing",
        "src/otio_leak_test.zig",
        options,
        common_deps,
    );

    try executable(
        b,
        "otio_dump_graph",
        "Dump OTIO file as a graphviz dot graph",
        "src/otio_dump_graph.zig",
        options,
        &.{
            .{ .name = "string_stuff", .module = string_stuff },
            .{ .name = "opentimelineio", .module = opentimelineio },
        },
    );

    try executable(
        b,
        "otio_measure_timeline",
        "Measure and display OTIO timeline durations",
        "src/otio_measure_timeline.zig",
        options,
        &.{
            .{ .name = "string_stuff", .module = string_stuff },
            .{ .name = "opentimelineio", .module = opentimelineio },
            .{ .name = "opentime", .module = opentime },
        },
    );

    try executable(
        b,
        "otio_hierarchy_view",
        "Display OTIO file structure as a tree",
        "src/otio_hierarchy_view.zig",
        options,
        &.{
            .{ .name = "string_stuff", .module = string_stuff },
            .{ .name = "opentimelineio", .module = opentimelineio },
            .{ .name = "opentime", .module = opentime },
            .{ .name = "sampling", .module = sampling },
            .{ .name = "ziggy", .module = dep_ziggy.module("ziggy") },
        },
    );

    try executable(
        b,
        "otiocat",
        "Convert files between formats (.otio, .tl*)",
        "src/otiocat.zig",
        options,
        &.{
            .{ .name = "string_stuff", .module = string_stuff },
            .{ .name = "opentimelineio", .module = opentimelineio },
            .{ .name = "ziggy", .module = dep_ziggy.module("ziggy") },
        },
    );

    //
    // C++ binding library and examples
    //
    if (options.target.result.cpu.arch.isWasm() == false) 
    {
        // C++ binding library
        const opentimelineio_cpp = b.addLibrary(
            .{
                .name = "opentimelineio_cpp",
                .linkage = .static,
                .root_module = b.createModule(
                    .{
                        .target = options.target,
                        .optimize = options.optimize,
                    },
                ),
            },
        );

        opentimelineio_cpp.addCSourceFile(
            .{
                .file = b.path("src/cpp_binding/src/opentimelineio.cpp"),
                .flags = &.{"-std=c++17"},
            },
        );

        opentimelineio_cpp.addIncludePath(b.path("src/cpp_binding/include"));
        opentimelineio_cpp.addIncludePath(b.path("src/c_binding"));
        opentimelineio_cpp.linkLibrary(opentimelineio_c);
        opentimelineio_cpp.linkLibCpp();

        b.installArtifact(opentimelineio_cpp);

        // C++ example: otio_hierarchy_view_cpp
        {
            const exe = b.addExecutable(
                .{
                    .name = "otio_hierarchy_view_cpp",
                    .root_module = b.createModule(
                        .{
                            .target = options.target,
                            .optimize = options.optimize,
                        },
                    ),
                },
            );

            exe.addCSourceFile(
                .{
                    .file = b.path(
                        "src/cpp_examples/otio_hierarchy_view.cpp",
                    ),
                    .flags = &.{"-std=c++17"},
                },
            );

            exe.addIncludePath(b.path("src/cpp_binding/include"));
            exe.addIncludePath(b.path("src/c_binding"));
            exe.linkLibrary(opentimelineio_cpp);
            exe.linkLibCpp();

            const install_exe_step = b.addInstallArtifact(
                exe,
                .{},
            );
            b.getInstallStep().dependOn(&install_exe_step.step);

            var run_step = b.step(
                "run-otio_hierarchy_view_cpp",
                "Run C++ timeline hierarchy viewer",
            );
            var run_cmd = b.addRunArtifact(exe);
            run_step.dependOn(&run_cmd.step);
            if (b.args) |args| {
                run_cmd.addArgs(args);
            }
        }

        // C++ example: otio_measure_timeline_cpp
        {
            const exe = b.addExecutable(
                .{
                    .name = "otio_measure_timeline_cpp",
                    .root_module = b.createModule(
                        .{
                            .target = options.target,
                            .optimize = options.optimize,
                        },
                    ),
                },
            );

            exe.addCSourceFile(
                .{
                    .file = b.path(
                        "src/cpp_examples/otio_measure_timeline.cpp"
                    ),
                    .flags = &.{"-std=c++17"},
                },
            );

            exe.addIncludePath(b.path("src/cpp_binding/include"));
            exe.addIncludePath(b.path("src/c_binding"));
            exe.linkLibrary(opentimelineio_cpp);
            exe.linkLibCpp();

            const install_exe_step = b.addInstallArtifact(exe, .{});
            b.getInstallStep().dependOn(&install_exe_step.step);

            var run_step = b.step(
                "run-otio_measure_timeline_cpp",
                "Run C++ timeline measurement tool",
            );
            var run_cmd = b.addRunArtifact(exe);
            run_step.dependOn(&run_cmd.step);
            if (b.args) |args| {
                run_cmd.addArgs(args);
            }
        }

        // C++ example: otiocat_cpp
        {
            const exe = b.addExecutable(
                .{
                    .name = "otiocat_cpp",
                    .root_module = b.createModule(
                        .{
                            .target = options.target,
                            .optimize = options.optimize,
                        },
                    ),
                },
            );

            exe.addCSourceFile(
                .{
                    .file = b.path("src/cpp_examples/otiocat.cpp"),
                    .flags = &.{"-std=c++17"},
                },
            );

            exe.addIncludePath(b.path("src/cpp_binding/include"));
            exe.addIncludePath(b.path("src/c_binding"));
            exe.linkLibrary(opentimelineio_cpp);
            exe.linkLibCpp();

            const install_exe_step = b.addInstallArtifact(
                exe,
                .{},
            );
            b.getInstallStep().dependOn(&install_exe_step.step);

            var run_step = b.step(
                "run-otiocat_cpp",
                "Run C++ timeline format viewer",
            );
            var run_cmd = b.addRunArtifact(exe);
            run_step.dependOn(&run_cmd.step);
            if (b.args) 
                |args| 
            {
                run_cmd.addArgs(args);
            }
        }

        // C++ unit tests
        {
            const cpp_test_exe = b.addExecutable(
                .{
                    .name = "test_opentimelineio_cpp",
                    .root_module = b.createModule(
                        .{
                            .target = options.target,
                            .optimize = options.optimize,
                        },
                    ),
                },
            );

            cpp_test_exe.addCSourceFile(
                .{
                    .file = b.path(
                        "src/cpp_binding/test/test_opentimelineio.cpp"
                    ),
                    .flags = &.{"-std=c++17"},
                },
            );

            cpp_test_exe.addIncludePath(b.path("src/cpp_binding/include"));
            cpp_test_exe.addIncludePath(b.path("src/c_binding"));
            cpp_test_exe.linkLibrary(opentimelineio_cpp);
            cpp_test_exe.linkLibCpp();

            b.installArtifact(cpp_test_exe);

            // Run the C++ tests with a sample file
            const run_cpp_tests = b.addRunArtifact(cpp_test_exe);
            run_cpp_tests.addArg("sample_otio_files/multiple_track.otio");

            // Suppress C++ test output unless -Dcpp_test_output=true
            if (!cpp_test_output) 
            {
                run_cpp_tests.expectExitCode(0);
            }

            const cpp_test_step = b.step(
                "test_cpp",
                "Run C++ binding unit tests",
            );
            cpp_test_step.dependOn(&run_cpp_tests.step);

            // Add to main test step if no filter is set
            if (options.test_filter == null) {
                options.test_step.dependOn(cpp_test_step);
            }
        }
    }
}
