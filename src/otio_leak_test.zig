//! example app using the app wrapper

const std = @import("std");
const builtin = @import("builtin");

const otio = @import("opentimelineio");

pub fn main(
) !void 
{
    const prog = std.Progress.start(.{});
    defer prog.end();

    const parent_prog = prog.start(
        "Testing Reading OTIO For leaks",
        0,
    );

    {
        var outer_debug_allocator: std.heap.DebugAllocator(.{}) = .{};
        const outer_allocator = outer_debug_allocator.allocator();

        const cmd_args = try _parse_args(outer_allocator);

        const read_prog = parent_prog.start(
            "Checking files for leaks...", 
            cmd_args.target_files.len,
        );
        defer read_prog.end();

        for (cmd_args.target_files)
            |fpath|
        {
            var buf:[1024]u8 = undefined;
            const prog_str =  try std.fmt.bufPrint(
                &buf,
                "Reading: {s}",
                .{ fpath },
            );
            const read_file_prog = read_prog.start(
                prog_str, 
                0,
            );
            defer read_file_prog.end();

            var inner_debug_allocator: std.heap.DebugAllocator(.{}) = .{};
            const inner_allocator = inner_debug_allocator.allocator();

            try std.fs.cwd().access(
                fpath,
                .{},
            );

            // test
            var otio_root = try otio.read_from_file(
                inner_allocator,
                fpath,
            );
            otio_root.recursively_deinit(inner_allocator);


            const did_leak = inner_debug_allocator.deinit();

            if (did_leak == .leak)
            {
                std.log.err("Leaked on file: {s}\n", .{ fpath });
            }
        }
    }

    parent_prog.end();
}

/// Usage message for argument parsing.
pub fn usage(
    msg: []const u8,
) void 
{
    std.debug.print(
        \\
        \\Load and deinit an otio file and see if there were any leaks.
        \\
        \\usage:
        \\  otio_leak_test path1/to/otio path2/to/otio
        \\
        \\arguments:
        \\  -h --help: print this message and exit
        \\
        \\{s}
        \\
        , .{msg}
    );
    std.process.exit(1);
}

fn _parse_args(
    allocator: std.mem.Allocator,
) !struct {
    target_files: [][]const u8, 
}
{
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // ignore the app name, always first in args
    _ = args.skip();

    var arg_count: usize = 0;

    var target_files: std.ArrayList([]const u8) = .empty;
    defer target_files.deinit(allocator);

    // read all the filepaths from the commandline
    while (args.next()) 
        |nextarg| 
    {
        arg_count += 1;
        const fpath: [:0]const u8 = nextarg;

        if (
            std.mem.eql(u8, fpath, "--help")
            or std.mem.eql(u8, fpath, "-h")
        ) {
            usage("");
        }
       
        try target_files.append(allocator, nextarg);
    }

    if (arg_count < 1) {
        usage("No files given.");
    }

    return .{
        .target_files = try target_files.toOwnedSlice(allocator),
    };
}
