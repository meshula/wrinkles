const std = @import("std");

const string = @import("string_stuff");
const opentime = @import("opentime");
const otio = @import("opentimelineio");
const sampling = @import("sampling");
const ziggy = @import("ziggy");

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
        \\usage:
        \\  otio_hierarchy_view [options] path/to/somefile.otio
        \\
        \\options:
        \\  -h --help           print this message and exit
        \\  -a --ascii          use ASCII characters (+, -, |) instead of Unicode box-drawing
        \\  -m --show-metadata  display metadata present on clips (off by default)
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
    show_metadata: bool,
    maybe_metadata_map: ?otio.serialization.MetadataMap,
) void
{
    for (stack.children, 0..) |child, i| {
        const is_last = (i == stack.children.len - 1);
        render_item(allocator, child, prefix, is_last, chars, show_metadata, maybe_metadata_map);
    }
}

/// Render a composition item and its children recursively
fn render_item(
    allocator: std.mem.Allocator,
    item: otio.CompositionItemHandle,
    prefix: []const u8,
    is_last: bool,
    chars: TreeChars,
    show_metadata: bool,
    maybe_metadata_map: ?otio.serialization.MetadataMap,
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
            render_stack(allocator, &tl.tracks, child_prefix, chars, show_metadata, maybe_metadata_map);
        },
        .stack => |st| {
            const name = st.maybe_name orelse "(unnamed)";
            const bounds_str = format_bounds(allocator, st.maybe_bounds_s) catch "";
            defer if (bounds_str.len > 0) allocator.free(bounds_str);

            std.debug.print(
                "{s}{s}Stack: {s}{s}\n",
                .{ prefix, connector, name, bounds_str },
            );

            render_stack(allocator, st, child_prefix, chars, show_metadata, maybe_metadata_map);
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
                render_item(allocator, child, child_prefix, child_is_last, chars, show_metadata, maybe_metadata_map);
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
            // Note: metadata display is only available when using --show-metadata flag,
            // which uses render_serializable_item instead of this function
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
            render_item(allocator, wp.child, child_prefix, true, chars, show_metadata, maybe_metadata_map);
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
            render_stack(allocator, &tr.container, child_prefix, chars, show_metadata, maybe_metadata_map);
        },
    }
}

/// Render a metadata value with proper indentation
fn render_metadata_value(
    allocator: std.mem.Allocator,
    value: otio.serialization.MetadataValue,
    prefix: []const u8,
    indent: usize,
) void
{
    const indent_str = allocator.alloc(u8, indent) catch return;
    defer allocator.free(indent_str);
    @memset(indent_str, ' ');

    switch (value) {
        .null => std.debug.print("{s}{s}null\n", .{ prefix, indent_str }),
        .bool => |b| std.debug.print("{s}{s}{}\n", .{ prefix, indent_str, b }),
        .integer => |i| std.debug.print("{s}{s}{d}\n", .{ prefix, indent_str, i }),
        .float => |f| std.debug.print("{s}{s}{d}\n", .{ prefix, indent_str, f }),
        .bytes => |s| std.debug.print("{s}{s}\"{s}\"\n", .{ prefix, indent_str, s }),
        .tag => |t| std.debug.print("{s}{s}<tag: {s}>\n", .{ prefix, indent_str, t.name }),
        .array => |arr| {
            std.debug.print("{s}{s}[\n", .{ prefix, indent_str });
            for (arr) |item| {
                render_metadata_value(allocator, item, prefix, indent + 2);
            }
            std.debug.print("{s}{s}]\n", .{ prefix, indent_str });
        },
        .kv => |map| {
            var iter = map.fields.iterator();
            while (iter.next()) |entry| {
                std.debug.print("{s}{s}{s}: ", .{ prefix, indent_str, entry.key_ptr.* });
                // For simple values, print on same line
                switch (entry.value_ptr.*) {
                    .null, .bool, .integer, .float, .bytes, .tag => {
                        render_metadata_value_inline(entry.value_ptr.*);
                        std.debug.print("\n", .{});
                    },
                    .array, .kv => {
                        std.debug.print("\n", .{});
                        render_metadata_value(allocator, entry.value_ptr.*, prefix, indent + 2);
                    },
                }
            }
        },
    }
}

/// Render a simple metadata value inline (no newline)
fn render_metadata_value_inline(
    value: otio.serialization.MetadataValue,
) void
{
    switch (value) {
        .null => std.debug.print("null", .{}),
        .bool => |b| std.debug.print("{}", .{b}),
        .integer => |i| std.debug.print("{d}", .{i}),
        .float => |f| std.debug.print("{d}", .{f}),
        .bytes => |s| std.debug.print("\"{s}\"", .{s}),
        .tag => |t| std.debug.print("<tag: {s}>", .{t.name}),
        .array => std.debug.print("[...]", .{}),
        .kv => std.debug.print("{{...}}", .{}),
    }
}

/// Read a file to SerializableTimeline (preserves metadata)
fn read_to_serializable_timeline(
    allocator: std.mem.Allocator,
    filepath: []const u8,
) !otio.serialization.SerializableTimeline
{
    // Check file extension to determine format
    const ext_start = std.mem.lastIndexOfScalar(u8, filepath, '.') orelse {
        return error.NoFileExtension;
    };
    const extension = filepath[ext_start..];

    const file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    const source = try file.readToEndAllocOptions(
        allocator,
        std.math.maxInt(u32),
        null,
        .@"1",
        0,
    );
    defer allocator.free(source);

    if (std.mem.eql(u8, extension, ".ziggy"))
    {
        return try ziggy.parseLeaky(
            otio.serialization.SerializableTimeline,
            allocator,
            source,
            .{},
        );
    }

    if (std.mem.eql(u8, extension, ".tlb"))
    {
        return try otio.binary_serialization.deserialize_to_serializable_timeline(
            allocator,
            source[0..source.len],
        );
    }

    if (std.mem.eql(u8, extension, ".tlfb"))
    {
        return try otio.binary_serialization_flatbufs.deserialize_to_serializable_timeline(
            allocator,
            source[0..source.len],
            .{},
        );
    }

    if (std.mem.eql(u8, extension, ".otio"))
    {
        // For OTIO JSON files with --show-metadata, the direct conversion path has issues.
        // The OTIO JSON metadata serialization in otio_json_to_serializable_timeline has
        // known issues. For metadata viewing, users should convert to .ziggy first:
        //   otiocat file.otio file.ziggy
        //   otio_hierarchy_view --show-metadata file.ziggy
        std.log.err(
            "OTIO JSON files are not supported with --show-metadata. " ++
            "Convert to .ziggy first with: otiocat {s} output.ziggy",
            .{filepath}
        );
        return error.UnsupportedFileFormatWithMetadata;
    }

    return error.UnsupportedFileFormat;
}

/// Render a SerializableTimeline hierarchy
fn render_serializable_timeline(
    allocator: std.mem.Allocator,
    ser_timeline: otio.serialization.SerializableTimeline,
    chars: TreeChars,
    show_metadata: bool,
) void
{
    const name = ser_timeline.name orelse "(unnamed)";
    std.debug.print("Timeline: {s}\n", .{name});
    std.debug.print("{s}\n", .{chars.vertical_single()});

    std.debug.print("{s}Stack: (tracks)\n", .{chars.last()});

    for (ser_timeline.children, 0..) |child, i| {
        const is_last = (i == ser_timeline.children.len - 1);
        render_serializable_item(allocator, child, "    ", is_last, chars, show_metadata, ser_timeline.metadata_map);
    }
}

/// Render a SerializableComposable item and its children recursively
fn render_serializable_item(
    allocator: std.mem.Allocator,
    item: otio.serialization.SerializableComposable,
    prefix: []const u8,
    is_last: bool,
    chars: TreeChars,
    show_metadata: bool,
    maybe_metadata_map: ?otio.serialization.MetadataMap,
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
        .track => |tr| {
            const name = tr.name orelse "(unnamed)";
            std.debug.print(
                "{s}{s}Track: {s} ({d} children)\n",
                .{ prefix, connector, name, tr.children.len },
            );

            for (tr.children, 0..) |child, i| {
                const child_is_last = (i == tr.children.len - 1);
                render_serializable_item(allocator, child, child_prefix, child_is_last, chars, show_metadata, maybe_metadata_map);
            }
        },
        .stack => |st| {
            const name = st.name orelse "(unnamed)";
            std.debug.print(
                "{s}{s}Stack: {s} ({d} children)\n",
                .{ prefix, connector, name, st.children.len },
            );

            for (st.children, 0..) |child, i| {
                const child_is_last = (i == st.children.len - 1);
                render_serializable_item(allocator, child, child_prefix, child_is_last, chars, show_metadata, maybe_metadata_map);
            }
        },
        .clip => |cl| {
            const name = cl.name orelse "(unnamed)";
            const bounds_str = format_serializable_bounds(allocator, cl.bounds_s) catch "";
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

            // Show metadata if enabled and available
            if (show_metadata) {
                if (cl.metadata_hash) |hash| {
                    if (maybe_metadata_map) |mm| {
                        if (mm.fields.get(hash)) |metadata_value| {
                            std.debug.print("{s}    metadata:\n", .{child_prefix});
                            render_metadata_value(allocator, metadata_value, child_prefix, 6);
                        }
                    }
                }
            }
        },
        .gap => |gp| {
            const name = gp.name orelse "(unnamed)";
            const bounds_str = std.fmt.allocPrint(
                allocator,
                " [{d:.2}s - {d:.2}s]",
                .{ gp.bounds_s[0], gp.bounds_s[1] },
            ) catch "";
            defer if (bounds_str.len > 0) allocator.free(bounds_str);

            std.debug.print(
                "{s}{s}Gap: {s}{s}\n",
                .{ prefix, connector, name, bounds_str },
            );
        },
        .warp => |wp| {
            const name = wp.name orelse "(unnamed)";
            std.debug.print(
                "{s}{s}Warp: {s}\n",
                .{ prefix, connector, name },
            );

            render_serializable_item(allocator, wp.child.*, child_prefix, true, chars, show_metadata, maybe_metadata_map);
        },
        .transition => |tr| {
            const name = tr.name orelse "(unnamed)";
            std.debug.print(
                "{s}{s}Transition: {s} (kind: {s})\n",
                .{ prefix, connector, name, tr.kind },
            );

            // Render transition's container children
            for (tr.container.children, 0..) |child, i| {
                const child_is_last = (i == tr.container.children.len - 1);
                render_serializable_item(allocator, child, child_prefix, child_is_last, chars, show_metadata, maybe_metadata_map);
            }
        },
    }
}

/// Format SerializableBounds
fn format_serializable_bounds(
    allocator: std.mem.Allocator,
    maybe_bounds: ?otio.serialization.SerializableBounds,
) ![]const u8
{
    if (maybe_bounds) |bounds| {
        return switch (bounds) {
            .continuous => |cont| try std.fmt.allocPrint(
                allocator,
                " [{d:.2}s - {d:.2}s]",
                .{ cont[0], cont[1] },
            ),
            .discrete => |disc| try std.fmt.allocPrint(
                allocator,
                " [frame {d} - {d}]",
                .{ disc[0], disc[1] },
            ),
        };
    }
    return try allocator.dupe(u8, "");
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

        // Print header
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

            render_serializable_timeline(allocator, ser_timeline, chars, true);
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
                render_item(allocator, child, "    ", is_last, chars, false, null);
            }
        }

        std.debug.print("\n", .{});
    }
}
