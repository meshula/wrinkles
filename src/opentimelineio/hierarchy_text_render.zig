const std = @import("std");

const opentime = @import("opentime");
const sampling = @import("sampling");
const schema = @import("schema.zig");
const references = @import("references.zig");

const serialization = @import("serialization/root.zig");

/// Tree drawing character set - holds string constants for tree rendering.
/// Use `unicode` or `ascii` constants for the appropriate character set.
pub const TreeChars = struct {
    branch: []const u8,
    last: []const u8,
    vertical: []const u8,
    space: []const u8,
    header_line: []const u8,
    vertical_single: []const u8,

    /// Unicode (fancy) tree characters
    pub const unicode = TreeChars{
        .branch = "├── ",
        .last = "└── ",
        .vertical = "│   ",
        .space = "    ",
        .header_line = "═══════════════════════════════════════════════════════════════",
        .vertical_single = "│",
    };

    /// ASCII tree characters
    pub const ascii = TreeChars{
        .branch = "+-- ",
        .last = "+-- ",
        .vertical = "|   ",
        .space = "    ",
        .header_line = "===================================================================",
        .vertical_single = "|",
    };
};

/// Format bounds info if present, with optional discrete info
pub fn format_bounds(
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
pub fn format_bounds_with_discrete(
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
                .Integer => |r| try std.fmt.allocPrint(allocator, "{d} hz", .{r}),
                .Rational => |r| try std.fmt.allocPrint(allocator, "{d}/{d} hz", .{r.num, r.den}),
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

/// Render stack children - forward declaration needed for recursion
pub fn render_stack(
    allocator: std.mem.Allocator,
    stack: *const schema.Stack,
    prefix: []const u8,
    chars: TreeChars,
    show_metadata: bool,
    maybe_metadata_map: ?serialization.ascii.MetadataMap,
) void
{
    for (stack.children, 0..) |child, i| {
        const is_last = (i == stack.children.len - 1);
        render_item(allocator, child, prefix, is_last, chars, show_metadata, maybe_metadata_map);
    }
}

/// Render a composition item and its children recursively
pub fn render_item(
    allocator: std.mem.Allocator,
    item: references.CompositionItemHandle,
    prefix: []const u8,
    is_last: bool,
    chars: TreeChars,
    show_metadata: bool,
    maybe_metadata_map: ?serialization.ascii.MetadataMap,
) void
{
    const connector = if (is_last) chars.last else chars.branch;
    const child_prefix_add = if (is_last) chars.space else chars.vertical;

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

            // Display markers if present - Stack has children, so always show vertical
            if (st.markers.len > 0) {
                std.debug.print(
                    "{s}{s}       markers: {} marker(s)\n",
                    .{ child_prefix, chars.vertical_single, st.markers.len },
                );
                for (st.markers, 0..) |marker, idx| {
                    const marker_name = marker.maybe_name orelse "(unnamed)";
                    std.debug.print(
                        "{s}{s}         [{d}] {s} ({s}) [{d:.2}s - {d:.2}s]\n",
                        .{ child_prefix, chars.vertical_single, idx + 1, marker_name, marker.color.to_string(),
                           marker.marked_range.start.as(f64), marker.marked_range.end.as(f64) },
                    );
                }
            }

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

            // Display markers if present - Track has children, so always show vertical
            if (tr.markers.len > 0) {
                std.debug.print(
                    "{s}{s}       markers: {} marker(s)\n",
                    .{ child_prefix, chars.vertical_single, tr.markers.len },
                );
                for (tr.markers, 0..) |marker, idx| {
                    const marker_name = marker.maybe_name orelse "(unnamed)";
                    std.debug.print(
                        "{s}{s}         [{d}] {s} ({s}) [{d:.2}s - {d:.2}s]\n",
                        .{ child_prefix, chars.vertical_single, idx + 1, marker_name, marker.color.to_string(),
                           marker.marked_range.start.as(f64), marker.marked_range.end.as(f64) },
                    );
                }
            }

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
                .image_sequence => "(image sequence)",
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

            // Display markers if present - Clip is a leaf, use child_prefix for vertical
            if (cl.markers.len > 0) {
                std.debug.print(
                    "{s}    markers: {} marker(s)\n",
                    .{ child_prefix, cl.markers.len },
                );
                for (cl.markers, 0..) |marker, idx| {
                    const marker_name = marker.maybe_name orelse "(unnamed)";
                    std.debug.print(
                        "{s}      [{d}] {s} ({s}) [{d:.2}s - {d:.2}s]\n",
                        .{ child_prefix, idx + 1, marker_name, marker.color.to_string(),
                           marker.marked_range.start.as(f64), marker.marked_range.end.as(f64) },
                    );
                }
            }
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

            // Display markers if present - Gap is a leaf, use child_prefix for vertical
            if (gp.markers.len > 0) {
                std.debug.print(
                    "{s}    markers: {} marker(s)\n",
                    .{ child_prefix, gp.markers.len },
                );
                for (gp.markers, 0..) |marker, idx| {
                    const marker_name = marker.maybe_name orelse "(unnamed)";
                    std.debug.print(
                        "{s}      [{d}] {s} ({s}) [{d:.2}s - {d:.2}s]\n",
                        .{ child_prefix, idx + 1, marker_name, marker.color.to_string(),
                           marker.marked_range.start.as(f64), marker.marked_range.end.as(f64) },
                    );
                }
            }
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
pub fn render_metadata_value(
    allocator: std.mem.Allocator,
    value: serialization.ascii.MetadataValue,
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
pub fn render_metadata_value_inline(
    value: serialization.ascii.MetadataValue,
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

/// Render a SerializableTimeline hierarchy
pub fn render_serializable_timeline(
    allocator: std.mem.Allocator,
    ser_timeline: serialization.ascii.SerializableTimeline,
    chars: TreeChars,
    show_metadata: bool,
) void
{
    const name = ser_timeline.name orelse "(unnamed)";
    std.debug.print("Timeline: {s}\n", .{name});
    std.debug.print("{s}\n", .{chars.vertical_single});

    std.debug.print("{s}Stack: (tracks)\n", .{chars.last});

    for (ser_timeline.children, 0..) |child, i| {
        const is_last = (i == ser_timeline.children.len - 1);
        render_serializable_item(allocator, child, "    ", is_last, chars, show_metadata, ser_timeline.metadata_map);
    }
}

/// Render a SerializableComposable item and its children recursively
pub fn render_serializable_item(
    allocator: std.mem.Allocator,
    item: serialization.ascii.SerializableComposable,
    prefix: []const u8,
    is_last: bool,
    chars: TreeChars,
    show_metadata: bool,
    maybe_metadata_map: ?serialization.ascii.MetadataMap,
) void
{
    const connector = if (is_last) chars.last else chars.branch;
    const child_prefix_add = if (is_last) chars.space else chars.vertical;

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

            // Display markers if present - Track has children, so always show vertical
            if (tr.markers.len > 0) {
                std.debug.print(
                    "{s}{s}       markers: {} marker(s)\n",
                    .{ child_prefix, chars.vertical_single, tr.markers.len },
                );
                for (tr.markers, 0..) |marker, idx| {
                    const marker_name = marker.name orelse "(unnamed)";
                    std.debug.print(
                        "{s}{s}         [{d}] {s} ({s}) [{d:.2}s - {d:.2}s]\n",
                        .{ child_prefix, chars.vertical_single, idx + 1, marker_name, marker.color,
                           marker.marked_range[0], marker.marked_range[1] },
                    );
                }
            }

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

            // Display markers if present - Stack has children, so always show vertical
            if (st.markers.len > 0) {
                std.debug.print(
                    "{s}{s}       markers: {} marker(s)\n",
                    .{ child_prefix, chars.vertical_single, st.markers.len },
                );
                for (st.markers, 0..) |marker, idx| {
                    const marker_name = marker.name orelse "(unnamed)";
                    std.debug.print(
                        "{s}{s}         [{d}] {s} ({s}) [{d:.2}s - {d:.2}s]\n",
                        .{ child_prefix, chars.vertical_single, idx + 1, marker_name, marker.color,
                           marker.marked_range[0], marker.marked_range[1] },
                    );
                }
            }

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
                .image_sequence => "(image sequence)",
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

            // Display markers if present - Clip is a leaf, use child_prefix for vertical
            if (cl.markers.len > 0) {
                std.debug.print(
                    "{s}    markers: {} marker(s)\n",
                    .{ child_prefix, cl.markers.len },
                );
                for (cl.markers, 0..) |marker, idx| {
                    const marker_name = marker.name orelse "(unnamed)";
                    std.debug.print(
                        "{s}      [{d}] {s} ({s}) [{d:.2}s - {d:.2}s]\n",
                        .{ child_prefix, idx + 1, marker_name, marker.color,
                           marker.marked_range[0], marker.marked_range[1] },
                    );
                }
            }

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

            // Display markers if present - Gap is a leaf, use child_prefix for vertical
            if (gp.markers.len > 0) {
                std.debug.print(
                    "{s}    markers: {} marker(s)\n",
                    .{ child_prefix, gp.markers.len },
                );
                for (gp.markers, 0..) |marker, idx| {
                    const marker_name = marker.name orelse "(unnamed)";
                    std.debug.print(
                        "{s}      [{d}] {s} ({s}) [{d:.2}s - {d:.2}s]\n",
                        .{ child_prefix, idx + 1, marker_name, marker.color,
                           marker.marked_range[0], marker.marked_range[1] },
                    );
                }
            }
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
pub fn format_serializable_bounds(
    allocator: std.mem.Allocator,
    maybe_bounds: ?serialization.ascii.SerializableBounds,
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

/// Render a SerializableCollection hierarchy
pub fn render_serializable_collection(
    allocator: std.mem.Allocator,
    collection: serialization.SerializableCollection,
    chars: TreeChars,
    show_metadata: bool,
) void
{
    const name = collection.name orelse "(unnamed)";
    std.debug.print("Collection: {s}\n", .{name});

    if (collection.description) |desc| {
        std.debug.print("  description: {s}\n", .{desc});
    }

    std.debug.print("{s}\n", .{chars.vertical_single});

    for (collection.children, 0..) |child, i| {
        const is_last = (i == collection.children.len - 1);
        render_serializable_collection_item(allocator, child, "", is_last, chars, show_metadata, collection.metadata_map);
    }
}

/// Render a SerializableCollectionItem and its children recursively
pub fn render_serializable_collection_item(
    allocator: std.mem.Allocator,
    item: serialization.ascii.SerializableCollectionItem,
    prefix: []const u8,
    is_last: bool,
    chars: TreeChars,
    show_metadata: bool,
    maybe_metadata_map: ?serialization.ascii.MetadataMap,
) void
{
    const connector = if (is_last) chars.last else chars.branch;
    const child_prefix_add = if (is_last) chars.space else chars.vertical;

    const child_prefix = std.fmt.allocPrint(
        allocator,
        "{s}{s}",
        .{ prefix, child_prefix_add },
    ) catch "(alloc error)";
    defer allocator.free(child_prefix);

    switch (item) {
        .timeline => |tl| {
            const name = tl.name orelse "(unnamed)";
            std.debug.print(
                "{s}{s}Timeline: {s} ({d} tracks)\n",
                .{ prefix, connector, name, tl.children.len },
            );

            // Display markers if present
            if (tl.markers.len > 0) {
                std.debug.print(
                    "{s}{s}          markers: {} marker(s)\n",
                    .{ child_prefix, chars.vertical_single, tl.markers.len },
                );
            }

            // Render children (tracks)
            for (tl.children, 0..) |child, i| {
                const child_is_last = (i == tl.children.len - 1);
                render_serializable_item(allocator, child, child_prefix, child_is_last, chars, show_metadata, tl.metadata_map orelse maybe_metadata_map);
            }
        },
        .track => |tr| {
            const name = tr.name orelse "(unnamed)";
            std.debug.print(
                "{s}{s}Track: {s} ({d} children)\n",
                .{ prefix, connector, name, tr.children.len },
            );

            // Display markers if present
            if (tr.markers.len > 0) {
                std.debug.print(
                    "{s}{s}       markers: {} marker(s)\n",
                    .{ child_prefix, chars.vertical_single, tr.markers.len },
                );
            }

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

            // Display markers if present
            if (st.markers.len > 0) {
                std.debug.print(
                    "{s}{s}       markers: {} marker(s)\n",
                    .{ child_prefix, chars.vertical_single, st.markers.len },
                );
            }

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
                .image_sequence => "(image sequence)",
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

            // Display markers if present
            if (cl.markers.len > 0) {
                std.debug.print(
                    "{s}    markers: {} marker(s)\n",
                    .{ child_prefix, cl.markers.len },
                );
            }

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

            // Display markers if present
            if (gp.markers.len > 0) {
                std.debug.print(
                    "{s}    markers: {} marker(s)\n",
                    .{ child_prefix, gp.markers.len },
                );
            }
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
