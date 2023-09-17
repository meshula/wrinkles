const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const comath_dep = b.dependency("comath", .{
        .target = target,
        .optimize = optimize,
    });

    inline for (.{
        .{ "comath_test.zig", "comath_test" },
    }) |val| {
        const lib = b.addSharedLibrary(.{
            .name = val[1],
            .root_source_file = .{ .path = val[0] },
            .target = target,
            .optimize = optimize,
        });

        lib.addModule("comath", comath_dep.module("comath"));

        b.installArtifact(lib);

        // const run_cmd = b.addRunArtifact(lib);

        // run_cmd.step.dependOn(b.getInstallStep());

        // if (b.args) |args| {
        //     run_cmd.addArgs(args);
        // }

        // const run_step = b.step("run-" ++ val[1], "Run " ++ val[1]);
        // run_step.dependOn(&run_cmd.step);
    }

    const test_step = b.step("test", "Run unit tests");

    inline for (.{"comath_test.zig"}) |name| {
        const unit_tests = b.addTest(
            .{
                .root_source_file = .{ .path = name },
                .target = target,
                .optimize = optimize,
            }
        );
        const install_asm = b.addInstallFile(
            unit_tests.getEmittedAsm(),
            "file.asm"
        );
        b.getInstallStep().dependOn(&install_asm.step);

        unit_tests.addModule("comath", comath_dep.module("comath"));

        const run_unit_tests = b.addRunArtifact(unit_tests);

        test_step.dependOn(&run_unit_tests.step);
        test_step.dependOn(&install_asm.step);
    }

    // Create executable for our example
    const exe = b.addExecutable(.{
        .name = "comath_test_app",
        .root_source_file = .{ .path = "comath_test.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addModule("comath", comath_dep.module("comath"));
    // exe.emit_asm = .emit;

    // Install the executable into the prefix when invoking "zig build"
    b.installArtifact(exe);

    const install_asm_on_build = false;
    if (install_asm_on_build) {
        const install_asm = b.addInstallFile(
            exe.getEmittedAsm(),
            "file.asm"
        );
        b.getInstallStep().dependOn(&install_asm.step);
    }
}
