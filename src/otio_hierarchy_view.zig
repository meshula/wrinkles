const std = @import("std");

const string = @import("string_stuff");
const otio = @import("opentimelineio");

const hierarchy_render = @import("opentimelineio").hierarchy_text_render;
const TreeChars = hierarchy_render.TreeChars;

const builtin = @import("builtin");

/// Parsed command line arguments
const ParsedArgs = struct {
    files: []const []const u8,
    use_ascii: bool,
    show_metadata: bool,
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
    var show_metadata = false;

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

        if (
            string.eql_latin_s8(fpath, "--show-metadata")
            or (string.eql_latin_s8(fpath, "-m"))
        ) {
            show_metadata = true;
            continue;
        }

        try files_to_view.append(allocator, fpath);
    }

    return .{
        .files = try files_to_view.toOwnedSlice(allocator),
        .use_ascii = use_ascii,
        .show_metadata = show_metadata,
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
        \\Supports timeline files (.otio, .tla, .tlb, .tlz) and collection
        \\ files (.tlca, .tlcb).
        \\
        \\usage:
        \\  otio_hierarchy_view [options] path/to/somefile.otio
        \\
        \\Options:
        \\  -h, --help           Print this message and exit
        \\  -a, --ascii          Use ASCII characters (+, -, |) instead of Unicode box-drawing
        \\  -m, --show-metadata  Display metadata present on clips (off by default)
        \\
        \\{s}
        , .{msg}
    );
    std.process.exit(1);
}

/// Read a file to SerializableTimeline (preserves metadata)
/// Supports: .otio, .tla, .tlb, .tlz
fn read_to_serializable_timeline(
    allocator: std.mem.Allocator,
    filepath: []const u8,
) !otio.serialization.SerializableTimeline
{
    return try otio.serialization.read_from_file(allocator, filepath);
}

/// Read a collection file to SerializableCollection
/// Supports: .tlca, .tlcb
fn read_to_serializable_collection(
    allocator: std.mem.Allocator,
    filepath: []const u8,
) !otio.serialization.SerializableCollection
{
    return try otio.serialization.read_collection_from_file(allocator, filepath);
}

/// Get file extension from path
fn get_extension(
    path: []const u8,
) ?[]const u8
{
    const ext_start = std.mem.lastIndexOfScalar(u8, path, '.') orelse return null;
    return path[ext_start..];
}

/// Check if file is a collection format based on extension
fn is_collection_file(
    filepath: []const u8,
) bool
{
    const ext = get_extension(filepath) orelse return false;
    return std.mem.eql(u8, ext, ".tlca") or std.mem.eql(u8, ext, ".tlcb");
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

        // Check if this is a collection file
        if (is_collection_file(filepath)) {
            // Print header for collection
            std.debug.print("\n", .{});
            std.debug.print("{s}\n", .{chars.header_line()});
            std.debug.print(" Collection Hierarchy: {s}\n", .{filepath});
            std.debug.print("{s}\n", .{chars.header_line()});
            std.debug.print("\n", .{});

            // Read and render collection
            const ser_collection = read_to_serializable_collection(allocator, filepath) catch |err| {
                std.log.err(
                    "Failed to read collection file '{s}': {s}",
                    .{ filepath, @errorName(err) }
                );
                continue;
            };

            hierarchy_render.render_serializable_collection(allocator, ser_collection, chars, parsed_args.show_metadata);
        } else {
            // Print header for timeline
            std.debug.print("\n", .{});
            std.debug.print("{s}\n", .{chars.header_line()});
            std.debug.print(" Timeline Hierarchy: {s}\n", .{filepath});
            std.debug.print("{s}\n", .{chars.header_line()});
            std.debug.print("\n", .{});

            if (parsed_args.show_metadata) {
                // Read as SerializableTimeline to access metadata
                const ser_timeline = read_to_serializable_timeline(allocator, filepath) catch |err| {
                    std.log.err(
                        "Failed to read file '{s}': {s}",
                        .{ filepath, @errorName(err) }
                    );
                    continue;
                };

                hierarchy_render.render_serializable_timeline(allocator, ser_timeline, chars, true);
            } else {
                // Read the file without metadata for faster reads
                var tl_ref = otio.read_from_file(
                    allocator,
                    filepath,
                    .{ .file_contents_to_read = .all_except_metadata },
                ) catch |err| {
                    std.log.err(
                        "Failed to read file '{s}': {s}",
                        .{ filepath, @errorName(err) }
                    );
                    continue;
                };
                defer tl_ref.deinit(allocator);

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
                    hierarchy_render.render_item(allocator, child, "    ", is_last, chars, false, null);
                }
            }
        }

        std.debug.print("\n", .{});
    }
}
