const std = @import("std");

const string = @import("string_stuff");
const opentime = @import("opentime");
const otio = @import("opentimelineio");
const sampling = @import("sampling");

const builtin = @import("builtin");

/// Tree drawing characters - Unicode (fancy) version
const TreeCharsUnicode = struct {
    const branch: []const u8 = "├── ";
    const last: []const u8 = "└── ";
    const vertical: []const u8 = "│   ";
    const space: []const u8 = "    ";
    const header_line: []const u8 = "═══════════════════════════════════════════════════════════════";
    const vertical_single: []const u8 = "│";
};

/// Tree drawing characters - ASCII version
const TreeCharsAscii = struct {
    const branch: []const u8 = "+-- ";
    const last: []const u8 = "+-- ";
    const vertical: []const u8 = "|   ";
    const space: []const u8 = "    ";
    const header_line: []const u8 = "===================================================================";
    const vertical_single: []const u8 = "|";
};

/// Parsed command line arguments
const ParsedArgs = struct {
    files: []const []const u8,
    use_ascii: bool,
};

/// parse the commandline arguments and setup the state
fn _parse_args(
    allocator: std.mem.Allocator,
) !ParsedArgs
{
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // ignore the app name, always first in args
    _ = args.skip();

    var files_to_view: std.ArrayList([]const u8) = .empty;
    defer files_to_view.deinit(allocator);

    var use_ascii = false;

    // read all the filepaths from the commandline
    while (args.next())
        |nextarg|
    {
        const fpath: [:0]const u8 = nextarg;

        if (
            string.eql_latin_s8(fpath, "--help")
            or (string.eql_latin_s8(fpath, "-h"))
        ) {
            usage("");
        }

        if (
            string.eql_latin_s8(fpath, "--ascii")
            or (string.eql_latin_s8(fpath, "-a"))
        ) {
            use_ascii = true;
            continue;
        }

        try files_to_view.append(allocator, fpath);
    }

    return .{
        .files = try files_to_view.toOwnedSlice(allocator),
        .use_ascii = use_ascii,
    };
}

/// Usage message for argument parsing.
pub fn usage(
    msg: []const u8,
) void
{
    std.debug.print(
        \\
        \\Display an ASCII diagram of the hierarchy of an OpenTimelineIO file.
        \\
        \\usage:
        \\  otio_hierarchy_view [options] path/to/somefile.otio
        \\
        \\options:
        \\  -h --help   print this message and exit
        \\  -a --ascii  use ASCII characters (+, -, |) instead of Unicode box-drawing
        \\
        \\{s}
        , .{msg}
    );
    std.process.exit(1);
}

/// Format bounds info if present, with optional discrete info
fn format_bounds(
    allocator: std.mem.Allocator,
    maybe_bounds: ?opentime.ContinuousInterval,
) ![]const u8
{
    if (maybe_bounds) |bounds| {
        return try std.fmt.allocPrint(
            allocator,
            " [{d:.2}s - {d:.2}s]",
            .{ bounds.start.as(f64), bounds.end.as(f64) },
        );
    }
    return try allocator.dupe(u8, "");
}

/// Format bounds with discrete sample info
fn format_bounds_with_discrete(
    allocator: std.mem.Allocator,
    maybe_bounds: ?opentime.ContinuousInterval,
    maybe_discrete: ?sampling.SampleIndexGenerator,
) ![]const u8
{
    if (maybe_bounds) |bounds| {
        if (maybe_discrete) |discrete| {
            // Calculate discrete indices for start and end
            const start_idx = discrete.index_at_ordinate(bounds.start);
            const end_idx = discrete.index_at_ordinate(bounds.end);

            // Format the rate string - use "/" for rationals like "24000/1001 hz"
            const rate_str = switch (discrete.sample_rate_hz) {
                .Int => |r| try std.fmt.allocPrint(allocator, "{d} hz", .{r}),
                .Rat => |r| try std.fmt.allocPrint(allocator, "{d}/{d} hz", .{r.num, r.den}),
            };
            defer allocator.free(rate_str);

            return try std.fmt.allocPrint(
                allocator,
                " [{d:.2}s - {d:.2}s] ({d} - {d} @ {s})",
                .{
                    bounds.start.as(f64),
                    bounds.end.as(f64),
                    start_idx,
                    end_idx,
                    rate_str,
                },
            );
        } else {
            return try std.fmt.allocPrint(
                allocator,
                " [{d:.2}s - {d:.2}s]",
                .{ bounds.start.as(f64), bounds.end.as(f64) },
            );
        }
    }
    return try allocator.dupe(u8, "");
}

/// Tree character set selection
const TreeChars = union(enum) {
    unicode: void,
    ascii: void,

    fn branch(self: @This()) []const u8 {
        return switch (self) {
            .unicode => TreeCharsUnicode.branch,
            .ascii => TreeCharsAscii.branch,
        };
    }

    fn last(self: @This()) []const u8 {
        return switch (self) {
            .unicode => TreeCharsUnicode.last,
            .ascii => TreeCharsAscii.last,
        };
    }

    fn vertical(self: @This()) []const u8 {
        return switch (self) {
            .unicode => TreeCharsUnicode.vertical,
            .ascii => TreeCharsAscii.vertical,
        };
    }

    fn space(self: @This()) []const u8 {
        return switch (self) {
            .unicode => TreeCharsUnicode.space,
            .ascii => TreeCharsAscii.space,
        };
    }

    fn header_line(self: @This()) []const u8 {
        return switch (self) {
            .unicode => TreeCharsUnicode.header_line,
            .ascii => TreeCharsAscii.header_line,
        };
    }

    fn vertical_single(self: @This()) []const u8 {
        return switch (self) {
            .unicode => TreeCharsUnicode.vertical_single,
            .ascii => TreeCharsAscii.vertical_single,
        };
    }
};

/// Render stack children - forward declaration needed for recursion
fn render_stack(
    allocator: std.mem.Allocator,
    stack: *const otio.Stack,
    prefix: []const u8,
    chars: TreeChars,
) void
{
    for (stack.children, 0..) |child, i| {
        const is_last = (i == stack.children.len - 1);
        render_item(allocator, child, prefix, is_last, chars);
    }
}

/// Render a composition item and its children recursively
fn render_item(
    allocator: std.mem.Allocator,
    item: otio.CompositionItemHandle,
    prefix: []const u8,
    is_last: bool,
    chars: TreeChars,
) void
{
    const connector = if (is_last) chars.last() else chars.branch();
    const child_prefix_add = if (is_last) chars.space() else chars.vertical();

    const child_prefix = std.fmt.allocPrint(
        allocator,
        "{s}{s}",
        .{ prefix, child_prefix_add },
    ) catch "(alloc error)";
    defer allocator.free(child_prefix);

    switch (item) {
        .timeline => |tl| {
            const name = tl.maybe_name orelse "(unnamed)";
            std.debug.print(
                "{s}{s}Timeline: {s}\n",
                .{ prefix, connector, name },
            );

            // Render tracks stack
            render_stack(allocator, &tl.tracks, child_prefix, chars);
        },
        .stack => |st| {
            const name = st.maybe_name orelse "(unnamed)";
            const bounds_str = format_bounds(allocator, st.maybe_bounds_s) catch "";
            defer if (bounds_str.len > 0) allocator.free(bounds_str);

            std.debug.print(
                "{s}{s}Stack: {s}{s}\n",
                .{ prefix, connector, name, bounds_str },
            );

            render_stack(allocator, st, child_prefix, chars);
        },
        .track => |tr| {
            const name = tr.maybe_name orelse "(unnamed)";
            const bounds_str = format_bounds(allocator, tr.maybe_bounds_s) catch "";
            defer if (bounds_str.len > 0) allocator.free(bounds_str);

            std.debug.print(
                "{s}{s}Track: {s}{s} ({d} children)\n",
                .{ prefix, connector, name, bounds_str, tr.children.len },
            );

            // Render track children
            for (tr.children, 0..) |child, i| {
                const child_is_last = (i == tr.children.len - 1);
                render_item(allocator, child, child_prefix, child_is_last, chars);
            }
        },
        .clip => |cl| {
            const name = cl.maybe_name orelse "(unnamed)";
            // Use clip bounds if set, otherwise fall back to media bounds
            const bounds_to_show = cl.maybe_bounds_s orelse cl.media.maybe_bounds_s;
            const bounds_str = format_bounds_with_discrete(
                allocator,
                bounds_to_show,
                cl.media.maybe_discrete_partition,
            ) catch "";
            defer if (bounds_str.len > 0) allocator.free(bounds_str);

            // Get media info
            const media_info = switch (cl.media.data_reference) {
                .uri => |uri| uri.target_uri,
                .signal => "(signal)",
                .null => "(no media)",
            };

            std.debug.print(
                "{s}{s}Clip: {s}{s}\n",
                .{ prefix, connector, name, bounds_str },
            );
            std.debug.print(
                "{s}    media: {s}\n",
                .{ child_prefix, media_info },
            );
        },
        .gap => |gp| {
            const name = gp.maybe_name orelse "(unnamed)";
            const bounds_str = format_bounds(allocator, gp.bounds_s) catch "";
            defer if (bounds_str.len > 0) allocator.free(bounds_str);

            std.debug.print(
                "{s}{s}Gap: {s}{s}\n",
                .{ prefix, connector, name, bounds_str },
            );
        },
        .warp => |wp| {
            const name = wp.maybe_name orelse "(unnamed)";
            std.debug.print(
                "{s}{s}Warp: {s}\n",
                .{ prefix, connector, name },
            );

            // Render warp's child
            render_item(allocator, wp.child, child_prefix, true, chars);
        },
        .transition => |tr| {
            const name = tr.maybe_name orelse "(unnamed)";
            const bounds_str = format_bounds(allocator, tr.maybe_bounds_s) catch "";
            defer if (bounds_str.len > 0) allocator.free(bounds_str);

            std.debug.print(
                "{s}{s}Transition: {s} (kind: {s}){s}\n",
                .{ prefix, connector, name, tr.kind, bounds_str },
            );

            // Render transition's container (stack)
            render_stack(allocator, &tr.container, child_prefix, chars);
        },
    }
}

pub fn main() !void {
    // use the debug allocator in debug builds, otherwise use smp
    const allocator = (
        if (builtin.mode == .Debug) alloc: {
            var da = std.heap.DebugAllocator(.{}){};
            break :alloc da.allocator();
        } else std.heap.smp_allocator
    );

    const parsed_args = try _parse_args(allocator);
    defer allocator.free(parsed_args.files);

    if (parsed_args.files.len == 0) {
        usage("Error: No input files specified.");
    }

    const chars: TreeChars = if (parsed_args.use_ascii) .ascii else .unicode;

    for (parsed_args.files) |filepath| {
        // Check file exists
        var found = true;
        std.fs.cwd().access(filepath, .{}) catch |e| switch (e) {
            error.FileNotFound => found = false,
            else => return e,
        };

        if (!found) {
            std.log.err(
                "File: {s} does not exist or is not accessible.",
                .{filepath}
            );
            continue;
        }

        // Read the file - skip metadata for faster reads
        var tl_ref = try otio.read_from_file(
            allocator,
            filepath,
            .{ .file_contents_to_read = .all_except_metadata },
        );
        defer tl_ref.deinit(allocator);

        // Print header
        std.debug.print("\n", .{});
        std.debug.print("{s}\n", .{chars.header_line()});
        std.debug.print(" Timeline Hierarchy: {s}\n", .{filepath});
        std.debug.print("{s}\n", .{chars.header_line()});
        std.debug.print("\n", .{});

        // Render the timeline
        const name = tl_ref.maybe_name() orelse "(unnamed)";
        std.debug.print("Timeline: {s}\n", .{name});
        std.debug.print("{s}\n", .{chars.vertical_single()});

        // Render the tracks stack
        const tracks = &tl_ref.timeline.tracks;
        const tracks_name = tracks.maybe_name orelse "(tracks)";
        std.debug.print("{s}Stack: {s}\n", .{ chars.last(), tracks_name });

        for (tracks.children, 0..) |child, i| {
            const is_last = (i == tracks.children.len - 1);
            render_item(allocator, child, "    ", is_last, chars);
        }

        std.debug.print("\n", .{});
    }
}
