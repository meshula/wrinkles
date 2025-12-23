const std = @import("std");

const string = @import("string_stuff");
const opentime = @import("opentime");
const otio = @import("opentimelineio");

const builtin = @import("builtin");

/// parse the commandline arguments and setup the state
fn _parse_args(
    allocator: std.mem.Allocator,
) ![]const []const u8 
{
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // ignore the app name, always first in args
    _ = args.skip();

    var arg_count: usize = 0;

    var files_to_measure: std.ArrayList([]const u8) = .empty;
    defer files_to_measure.deinit(allocator);

    // read all the filepaths from the commandline
    while (args.next()) 
        |nextarg| 
    {
        arg_count += 1;
        const fpath: [:0]const u8 = nextarg;

        if (
            string.eql_latin_s8(fpath, "--help")
            or (string.eql_latin_s8(fpath, "-h"))
        ) {
            usage("");
        }
        
        try files_to_measure.append(allocator, fpath);
    }

    return try files_to_measure.toOwnedSlice(allocator);
}

/// Usage message for argument parsing.
pub fn usage(
    msg: []const u8,
) void 
{
    std.debug.print(
        \\
        \\Render a graph of the temporal spaces in an OpenTimelineIO file.
        \\
        \\usage:
        \\  otio_measure_graph path/to/somefile.otio path/to/output.png
        \\
        \\arguments:
        \\  -h --help: print this message and exit
        \\
        \\{s}
        , .{msg}
    );
    std.process.exit(1);
}

pub fn main(
) !void
{
    // use the debug allocator in debug builds, otherwise use smp
    const allocator = (
        if (builtin.mode == .Debug) alloc: {
            var da = std.heap.DebugAllocator(.{}){};
            break :alloc da.allocator();
        } else std.heap.smp_allocator
    );

    const input_files = try _parse_args(allocator);
    defer allocator.free(input_files);

    const prog = std.Progress.start(.{});
    defer prog.end();

    const parent_prog = prog.start(
        "Measuring OTIO Files",
        input_files.len,
    );

    var buffer:[1024]u8 = undefined;

    for (input_files)
        |filepath|
    {
        const name = try std.fmt.bufPrint(
            &buffer,
            "File: {s}",
            .{ filepath }
        );
        const file_prog = parent_prog.start(
            name,
            4,
        );

        const read_prog = file_prog.start(
            "Reading file...",
            0,
        );

        var found = true;
        std.fs.cwd().access(
            filepath,
            .{},
        ) catch |e| switch (e) {
            error.FileNotFound => found = false,
            else => return e,
        };
        if (found == false)
        {
            std.log.err(
                "File: {s} does not exist or is not accessible.",
                .{filepath}
            );
        }

        // read the file
        var tl_ref = try otio.read_from_file(
            allocator,
            filepath,
        );
        defer tl_ref.deinit(allocator);

        read_prog.end();

        const build_map_pro = file_prog.start(
            "Building Projection Topology",
            0,
        );

        std.debug.print(
            "Timeline {?s} has {d} tracks\nTracks:\n",
            .{
                tl_ref.maybe_name(),
                tl_ref.timeline.tracks.children.len 
            },
        );

        for (tl_ref.timeline.tracks.children, 0..)
            |child, track_ind|
        {
            const children = (
                try child.children_refs(allocator)
            );
            std.debug.print(
                "  Track: {d}:{?s} has {d} children\n",
                .{ 
                    track_ind,
                    child.maybe_name(),
                    children.len,
                },
            );
            defer allocator.free(children);

            for (children, 0..)
                |child_child, ind|
            {
                std.debug.print(
                    "    Child {d}:{s}.{?s}\n",
                    .{
                        ind,
                        @tagName(child_child),
                        child_child.maybe_name(),
                    }
                );
            }
        }

        var projection_topo = (
            try otio.projection.TemporalProjectionBuilder.init_from(
                allocator,
                tl_ref.space_node(.presentation),
            )
        );
        defer projection_topo.deinit(allocator);

        build_map_pro.end();

        std.debug.print(
            "Tracks: {d}\n",
            .{tl_ref.timeline.tracks.children.len}
        );
        var items: usize = 0;
        for (tl_ref.timeline.tracks.children, 0..)
            |child, ind|
        {
            std.debug.print(
                "  Track [{d}]: {d} items\n",
                .{ind, child.track.children.len},
            );
            items += child.track.children.len;
        }

        tl_ref.timeline.discrete_space_partitions.presentation.picture = .{
            .sample_rate_hz = .{ .Int = 24 },
            .start_index = 86400,
        };

        std.debug.print("Total items: {d}\n", .{items});
        std.debug.print("RefTopo: {f}\n", .{projection_topo});
    }
}
