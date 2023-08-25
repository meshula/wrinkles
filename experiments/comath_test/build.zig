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
        const unit_tests = b.addTest(.{
            .root_source_file = .{ .path = name },
            .target = target,
            .optimize = optimize,
        });

        unit_tests.addModule("comath", comath_dep.module("comath"));

        const run_unit_tests = b.addRunArtifact(unit_tests);

        test_step.dependOn(&run_unit_tests.step);
    }
}
