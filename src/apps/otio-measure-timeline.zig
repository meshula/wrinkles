const std = @import("std");

const string = @import("string_stuff");
const opentime = @import("opentime");
const otio = @import("opentimelineio");

const builtin = @import("builtin");

/// parse the commandline arguments and setup the state
fn _parse_args(
    allocator: std.mem.Allocator,
    args: std.process.Args,
) !struct {
    files_to_measure: []const []const u8,
    output_fps: ?u8,
}
{
    var arg_iter = args.iterate();

    // ignore the app name, always first in args
    _ = arg_iter.skip();

    var arg_count: usize = 0;

    var files_to_measure: std.ArrayList([]const u8) = .empty;
    defer files_to_measure.deinit(allocator);

    var discrete_fps: ?u8 = null;

    // read all the filepaths from the commandline
    while (arg_iter.next())
        |nextarg|
    {
        arg_count += 1;
        const fpath: [:0]const u8 = nextarg;

        if (
            string.eql_latin_s8(fpath, "--discrete-fps")
            or (string.eql_latin_s8(fpath, "-d"))
        )
        {
            if (arg_iter.next())
                |fps|
            {
                discrete_fps = (
                    std.fmt.parseInt(u8, fps, 10)
                    catch c: {
                        usage("Error: --discrete-fps -d expected a u8.");
                        break :c null;
                    }
                );
                continue;
            }
            else
            {
                usage("Error: --discrete-fps -d requires a number argument");
            }
        }

        if (
            string.eql_latin_s8(fpath, "--help")
            or (string.eql_latin_s8(fpath, "-h"))
        )
        {
            usage("");
        }

        try files_to_measure.append(allocator, fpath);
    }

    return .{
        .files_to_measure = try files_to_measure.toOwnedSlice(allocator),
        .output_fps = discrete_fps,
    };
}

/// Usage message for argument parsing.
pub fn usage(
    msg: []const u8,
) void
{
    std.debug.print(
        \\
        \\From the output timeline, measure the temporal footprint of all of the elements in the timeline.  Optionally add a discretization.
        \\
        \\usage:
        \\  otio_measure_graph path/to/somefile.otio path/to/output.png [arguments]
        \\
        \\arguments:
        \\  -d --discrete-fps add an output space discretization to an fps
        \\  -h --help: print this message and exit
        \\
        \\{s}
        ,
        .{msg},
    );
    std.process.exit(1);
}

pub fn main(
    init: std.process.Init,
) !void
{
    // use the debug allocator in debug builds, otherwise use smp
    const allocator = init.gpa;
    const io = init.io;

    const args = try _parse_args(allocator, init.minimal.args);
    defer allocator.free(args.files_to_measure);

    const prog = std.Progress.start(io, .{});
    defer prog.end();

    const parent_prog = prog.start(
        "Measuring OTIO Files",
        args.files_to_measure.len,
    );

    var buffer: [1024]u8 = undefined;

    for (args.files_to_measure)
        |filepath|
    {
        const name = try std.fmt.bufPrint(&buffer, "File: {s}", .{filepath});
        const file_prog = parent_prog.start(
            name,
            4,
        );

        const read_prog = file_prog.start(
            "Reading file...",
            0,
        );

        var found = true;
        std.Io.Dir.cwd().access(
            io,
            filepath,
            .{},
        )
        catch |e| switch (e) {
            error.FileNotFound => found = false,
            else => return e,
        };
        if (found == false)
        {
            std.log.err(
                "File: {s} does not exist or is not accessible.",
                .{filepath},
            );
        }

        // read the file - skip metadata for faster reads
        var tl_ref = try otio.read_from_file(
            allocator,
            io,
            filepath,
            .{ .content_filter = .all_except_metadata },
        );
        defer tl_ref.deinit(allocator);

        read_prog.end();

        const build_map_pro = file_prog.start(
            "Building Projection Topology",
            0,
        );

        std.debug.print(
            "Timeline {?s} has {d} tracks\nTracks:\n",
            .{ tl_ref.name(), tl_ref.timeline.tracks.children.len },
        );

        for (tl_ref.timeline.tracks.children, 0..)
            |child, track_ind|
        {
            const children = try child.children_refs(allocator);
            std.debug.print(
                "  Track: {d}:{?s} has {d} children\n",
                .{
                    track_ind,
                    child.name(),
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
                        child_child.name(),
                    },
                );
            }
        }

        var pb_from_tl_pres = (
            try otio.projection.TemporalProjectionBuilder.init_from(
                allocator,
                tl_ref.space_node(.presentation),
            )
        );
        defer pb_from_tl_pres.deinit(allocator);

        build_map_pro.end();

        std.debug.print(
            "Tracks: {d}\n",
            .{tl_ref.timeline.tracks.children.len},
        );
        var items: usize = 0;
        for (tl_ref.timeline.tracks.children, 0..)
            |child, ind|
        {
            std.debug.print(
                "  Track [{d}]: {d} items\n",
                .{ ind, child.track.children.len },
            );
            items += child.track.children.len;
        }

        std.debug.print("Total items: {d}\n", .{items});
        std.debug.print("RefTopo: {f}\n", .{pb_from_tl_pres});

        std.debug.print("Discrete Infomration / Domain:\n", .{});

        const domains = [_]otio.Domain{
            .picture,
            .audio,
        };
        
        for (&domains) |dmn|
        {
            if (
                tl_ref.discrete_partition_for_space(
                    .presentation,
                    dmn,
                )
            ) |index_generator|
            {
                std.debug.print(
                    "  {s}: {f}\n",
                    .{ @tagName(dmn), index_generator },
                );
            }
            else
            {
                std.debug.print("  {s}: (none)\n", .{@tagName(dmn)});
            }
        }
    }
}
