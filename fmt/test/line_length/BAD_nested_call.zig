const std = @import("std");

const Module = struct {
    target: i32,
    optimize: bool,
};

const Executable = struct {
    name: []const u8,
    root_module: Module,
};

fn createModule(
    opts: struct { target: i32, optimize: bool },
) Module
{
    return .{ .target = opts.target, .optimize = opts.optimize };
}

fn addExecutable(
    opts: struct { name: []const u8, root_module: Module },
) Executable
{
    return .{ .name = opts.name, .root_module = opts.root_module };
}

pub fn build(
) Executable
{
    const exe = addExecutable(.{ .name = "hello", .root_module = createModule(.{
        .target = 42,
        .optimize = true,
    }) });
    return exe;
}

test "nested call"
{
    const exe = build();
    try std.testing.expectEqual(@as(i32, 42), exe.root_module.target);
}
