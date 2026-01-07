//! example app using the app wrapper

const std = @import("std");
const build_options = @import("build_options");
const builtin = @import("builtin");

const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = zgui.plot;
const sg = ziis.sokol.gfx;
const app_wrapper = ziis.app_wrapper;

const cimgui = ziis.cimgui;

const opentime = @import("opentime");
const otio = @import("opentimelineio");
const otio_serialization = @import("opentimelineio").serialization;
const topology = @import("topology");
const treecode = @import("treecode");

/// State container
const STATE = struct {
    var demo_window_gui = false;
    var demo_window_plot = false;

    var maybe_journal : ?ziis.undo.Journal = null;

    var allocator: std.mem.Allocator = undefined;
    var debug_allocator: std.heap.DebugAllocator(.{}) = undefined;

    /// path to the otio file
    var target_otio_file: []const u8 = undefined;
    var maybe_file_read_query: ?*app_wrapper.FetchQuery = null;

    /// copy of the OTIO json
    var otio_src_json:[]const u8 = undefined;

    /// root object in the read in OTIO file
    var otio_root: otio.CompositionItemHandle = undefined;

    var maybe_current_selected_object: ?otio.CompositionItemHandle = null;
    var maybe_cached_topology: ?topology.Topology = null;

    var maybe_src: ?otio.references.TemporalSpaceNode = null;
    var maybe_dst: ?otio.references.TemporalSpaceNode = null;
    var maybe_transform: ?topology.Topology = null;
    var maybe_proj_builder: ?otio.TemporalProjectionBuilder = null;

    /// referrred to by the label field in the slices MAL
    var points: std.MultiArrayList(PlotPoint2d) = .empty;
    var slices: std.MultiArrayList(
        struct{
            // continuous points
            xs: []const f32,
            ys: []const f32,

            // discrete points
            discrete_points: ?[2][]const f32,
            
            /// Text label for the mapping curve
            label: [:0]const u8,
        }
    ) = .empty;

    /// plotted space by domain
    var discrete_points: struct {
        audio: ?std.MultiArrayList(PlotPoint2d) = null,
        picture: ?std.MultiArrayList(PlotPoint2d) = null,
    } = .{};

    var maybe_cut_points: ?[]f32 = null;

    var maybe_hovered_interval: ?usize = null;

    var options: struct {
        show_discrete_input_spaces: enum (u4) {
            never,
            hovered,
            always,
        } = .always,
        show_discrete_ouput_spaces: enum (u4) {
            never,
            hovered,
            always,
        } = .always,
    } = .{};

    /// Timeline view state (raven-like)
    var timeline: struct {
        scale: f32 = 100.0,  // Pixels per second
        track_height: f32 = 30.0,
        playhead: f32 = 0.0,  // Playhead position in seconds
        scroll_to_playhead: bool = false,
        start: f32 = 0.0,  // Timeline start time in seconds
        duration: f32 = 10.0,  // Timeline duration in seconds
    } = .{};
};

/// Colors for timeline view (raven-style)
const TimelineColors = struct {
    const background: u32 = 0xFF141414;
    const track_label: u32 = 0xFF2A2A2A;
    const track_label_hover: u32 = 0xFF3A3A3A;
    const track_label_selected: u32 = 0xFF176B42;
    // Item colors - greenish like raven
    const item: u32 = 0xFF355535;  // Muted green
    const item_hover: u32 = 0xFF456545;  // Brighter green on hover
    const item_selected: u32 = 0xFF176B42;  // Bright green when selected
    const gap: u32 = 0xFF1E1E1E;  // Darker than track, visible as empty space
    const gap_hover: u32 = 0xFF2E2E2E;
    const transition: u32 = 0xFF6A4A6A;
    const transition_line: u32 = 0xFFAA8AAA;
    // Playhead - gold/yellow like raven
    const playhead: u32 = 0x80C8A020;  // Semi-transparent gold
    const playhead_line: u32 = 0xFFC8A020;  // Solid gold line
    const tick_major: u32 = 0xFF808080;
    const tick_minor: u32 = 0xFF404040;
    const label: u32 = 0xFFF0F0F0;
};


fn struct_editor_ui(
    comptime T: type,
    thing: *T,
) !void
{
    inline for (std.meta.fields(T))
        |field|
    {
        switch (@typeInfo(field.type)) {
            .@"enum" => |_| {
                _ = zgui.comboFromEnum(
                    field.name, 
                    &@field(thing.*, field.name)
                );
            },
            else => @compileError(
                "Field type: " 
                ++ @typeName(field.type) 
                ++ " not supported.",
            ),
        }
    }
}

fn parent_path(
    allocator: std.mem.Allocator,
    builder: otio.TemporalProjectionBuilder,
    destination: otio.references.TemporalSpaceNode,
) ![]const u8
{
    const path = try builder.tree.path(
        allocator,
        .{
            .source = 0,
            .destination = builder.tree.index_for_node(destination).?,
        }
    );
    defer allocator.free(path);

    var last_ref: otio.CompositionItemHandle = undefined;

    var buf: std.ArrayList(u8) = .empty;
    var writer = buf.writer(allocator);

    for (path)
        |node_index|
    {
        const current_node_ref = builder.tree.nodes.items(.item)[node_index];
        if (std.meta.eql(destination.item, current_node_ref))
        {
            break;
        }

        if (std.meta.eql(last_ref, current_node_ref))
        {
            continue;
        }

        last_ref = current_node_ref;
        try writer.print("{f}/", .{last_ref});
    }

    try writer.print("{f}", .{ destination });

    return try buf.toOwnedSlice(allocator);
}

fn set_source(
    allocator: std.mem.Allocator,
    src: otio.references.TemporalSpaceNode,
) !void
{
    STATE.maybe_src = src;

    if (STATE.maybe_proj_builder)
        |*builder|
    {
        builder.deinit(allocator);
    }

    STATE.maybe_proj_builder = (
        try otio.TemporalProjectionBuilder.init_from(
            allocator,
            src,
        )
    );
    STATE.maybe_transform = null;

    if (STATE.maybe_proj_builder)
        |builder|
    {
        std.debug.print(
            "{f}\n",
            .{builder}
        );
    }

    try fill_topdown_point_buffers(allocator);
}

fn table_fill_row(
    cells: []const []const u8,
) void
{
    for (cells, 0..)
        |text, col|
    {
        _ = zgui.tableSetColumnIndex(@intCast(col));
        zgui.text("{s}", .{text});
    }
}

fn fill_topdown_point_buffers(
    allocator: std.mem.Allocator,
) !void
{
    var points = &STATE.points;
    var slices = &STATE.slices;
    var discrete_points = STATE.discrete_points;
    const cut_points = &STATE.maybe_cut_points;

    // clear whatever is there
    points.deinit(allocator);
    inline for (&[_][]const u8{ "picture", "audio" })
        |field|
    {
        if (@field(discrete_points, field))
            |*discrete|
        {
            discrete.deinit(allocator);
        }
        @field(discrete_points, field) = null;
    }

    if (cut_points.*)
        |cp|
    {
        allocator.free(cp);
    }

    for (slices.items(.label))
        |label|
    {
        allocator.free(@as([]const u8, @ptrCast(label)));
    }
    slices.deinit(allocator);

    points.* = .empty;
    slices.* = .empty;
    discrete_points.picture = null;
    discrete_points.audio = null;
    cut_points.* = null;

    // var label_writer = label_bucket.writer(allocator);
    var allocating_label_writer = std.Io.Writer.Allocating.init(
        allocator
    );
    defer allocating_label_writer.deinit();
    const label_writer = &allocating_label_writer.writer;

    // generate profile curve
    const builder = (
        STATE.maybe_proj_builder.?
    );

    try slices.ensureTotalCapacity(
        allocator, 
        builder.intervals.len
    );

    cut_points.* = try allocator.alloc(f32, builder.intervals.len + 1);

    const interval_slice =  builder.intervals.slice();
    const mapping_slice = builder.mappings.slice();

    var slice_indices: std.MultiArrayList(
        struct{
            start: usize,
            end: usize,
            discrete_indedx_range: ?[2]usize,
            label: [:0]const u8,
            domain: otio.Domain,
        },
    ) = .empty;
    defer slice_indices.deinit(allocator);

    for (
        interval_slice.items(.mapping_index),
        interval_slice.items(.input_bounds),
        0..,
    ) |mapping_indices, input_bound, interval_ind|
    {
        cut_points.*.?[interval_ind] = input_bound.start.as(f32);
        for (mapping_indices)
            |mapping_ind|
        {
            const mapping = mapping_slice.items(.mapping)[mapping_ind];
            const ref_ind = mapping_slice.items(.destination)[mapping_ind];
            const dst = builder.tree.nodes.get(ref_ind);

            // try table_data.append(
            //     allocator,
            //     .{
            //         .name = try std.fmt.allocPrint(
            //             allocator,
            //             "{f}", 
            //             .{ dst },
            //         ),
            //         .item = (
            //             &builder.tree.nodes.get(ref_ind)
            //         ),
            //         .indices = .{ interval_ind, mapping_ind },
            //     },
            // );

            switch (mapping)
            {
                .affine => |aff| {
                    const start = points.len;
                    const end = start + 2;
                    try points.ensureUnusedCapacity(
                        allocator,
                        2,
                    );
                    const ib = aff.input_bounds();
                    var ob: [2]opentime.Ordinate = .{
                        aff.project_instantaneous_cc_assume_in_bounds(
                            ib.start,
                        ).success_ordinate,
                        aff.project_instantaneous_cc_assume_in_bounds(
                            ib.end,
                        ).success_ordinate,
                    };

                    points.appendAssumeCapacity(
                        .{
                            .x = ib.start.as(f32),
                            .y = ob[0].as(f32),
                        },
                    );
                    var last_point = points.get(points.len - 1);
                    points.appendAssumeCapacity(
                        .{.x = ib.end.as(f32), .y = ob[1].as(f32)},
                    );
                    last_point = points.get(points.len - 1);
                    const path = try parent_path(
                        allocator,
                        builder,
                        dst,
                    );
                    defer allocator.free(path);

                    var discrete_indices:?[2]usize = null;

                    inline for (@typeInfo(otio.Domain).@"union".fields)
                        |field|
                    {
                        const domain = @unionInit(
                            otio.Domain,
                            field.name,
                            undefined,
                        );

                        if (dst.discrete_partition(domain))
                            |discrete_space|
                        {
                            discrete_indices = .{ points.len, points.len };
                            // make a discrete space over the continuous one
                            var current = ib.start;
                            const inc = ib.duration().div(
                                discrete_space.sample_rate_hz.as_ordinate()
                            ).as(f32);
                            while  (current.lt(ib.end))
                                : (current = current.add(inc))
                            {
                                try points.append(
                                    allocator,
                                    .{
                                        .x = current.as(f32),
                                        .y = mapping.project_instantaneous_cc_assume_in_bounds(current).success_ordinate.as(f32),
                                    }
                                );
                            }

                            discrete_indices.?[1] = points.len;
                        }

                        try label_writer.print("{s}\x00", .{ path });
                        try slice_indices.append(
                            allocator,
                            .{
                                .start = start,
                                .end = end,
                                .discrete_indedx_range = discrete_indices,
                                .label = @ptrCast(
                                    try allocating_label_writer.toOwnedSlice()
                                ),
                                .domain = domain,
                            },
                        );
                    }


                },
                .linear => |lin| {
                    const start = points.len;
                    const end = start + lin.input_to_output_curve.knots.len;

                    try points.ensureUnusedCapacity(
                        allocator,
                        lin.input_to_output_curve.knots.len,
                    );

                    for (lin.input_to_output_curve.knots)
                        |k|
                    {
                        points.appendAssumeCapacity(
                            .{
                                .x = k.in.as(f32),
                                .y = k.out.as(f32),
                            },
                        );
                    }

                    var discrete_indices:?[2]usize = null;

                    inline for (@typeInfo(otio.Domain).@"union".fields)
                        |field|
                    {
                        const domain = @unionInit(
                            otio.Domain,
                            field.name,
                            undefined,
                        );
                        if (dst.discrete_partition(domain))
                            |discrete_space|
                        {
                            discrete_indices = .{ points.len, points.len };

                            // make a discrete space over the continuous one
                            const maybe_ib = mapping.input_bounds();

                            if (maybe_ib)
                                |ib|
                            {
                                var current = ib.start;
                                const inc = ib.duration().div(
                                    discrete_space.sample_rate_hz.as_ordinate()
                                ).as(f32);
                                while  (current.lt(ib.end))
                                    : (current = current.add(inc))
                                {
                                    try points.append(
                                        allocator,
                                        .{
                                            .x = current.as(f32),
                                            .y = mapping.project_instantaneous_cc_assume_in_bounds(current).success_ordinate.as(f32),
                                        }
                                    );
                                }
                            }

                            discrete_indices.?[1] = points.len;

                            try label_writer.print("{f}" ++ .{0}, .{ dst });
                            try slice_indices.append(
                                allocator,
                                .{
                                    .start = start,
                                    .end = end,
                                    .discrete_indedx_range = discrete_indices,
                                    .label = @ptrCast(
                                        try allocating_label_writer.toOwnedSlice()
                                    ),
                                    .domain = domain,
                                },
                            );
                        }

                    }
                },
                else => {
                },
            }
        }
    }

    cut_points.*.?[builder.intervals.len] = builder.input_bounds().?.end.as(f32);
    std.debug.assert(slice_indices.len != 0);

    for (
        slice_indices.items(.start),
        slice_indices.items(.end),
        slice_indices.items(.discrete_indedx_range),
        slice_indices.items(.label),
    ) |start, end, discrete_indices, label|
    {
        try slices.append(
            allocator,
            .{
                .xs = points.items(.x)[start..end],
                .ys = points.items(.y)[start..end],
                .discrete_points = if (discrete_indices) |di| .{
                    points.items(.x)[di[0]..di[1]],
                    points.items(.y)[di[0]..di[1]],
                } else null,
                .label = label,
            },
        );
    }

    std.debug.assert(slices.len != 0);

    // generate the discrete space, if there is a definition on the source
    inline for (&[_][]const u8{"picture", "audio"})
        |field|
    {
        const domain = @unionInit(
            otio.Domain,
            field,
            undefined,
        );

        const result = &@field(STATE.discrete_points, field);
        result.* = null;

        if (STATE.maybe_src.?.discrete_partition(domain))
            |discrete_info|
        {
            result.* = .empty;
            const buffer_length = discrete_info.buffer_size_for_length(
                builder.input_bounds().?.duration()
            );

            try result.*.?.ensureTotalCapacity(
                allocator, 
                // two points per index to create horizontal line
                2 * buffer_length,
            );

            for (discrete_info.start_index.. (discrete_info.start_index + buffer_length))
                |index|
            {
                const ord = discrete_info.ord_interval_for_index(index);

                result.*.?.appendAssumeCapacity(
                    .{
                        .x = ord.start.as(f32),
                        .y = ord.start.as(f32),
                    }
                );
                result.*.?.appendAssumeCapacity(
                    .{
                        .x = ord.end.as(f32),
                        .y = ord.start.as(f32),
                    }
                );
            }
        }
    }

    if (STATE.slices.len > 100)
    {
        STATE.options.show_discrete_ouput_spaces = .never;
    }
}

fn draw_hover_extras(
    allocator: std.mem.Allocator,
    builder: otio.projection.TemporalProjectionBuilder,
) !void
{
    const mouse_pos = zplot.getPlotMousePos(
        .x1,
        .y1,
    );

    const source_ord = opentime.Ordinate.init(mouse_pos[0]);

    STATE.maybe_hovered_interval = builder.interval_index_for_time(source_ord);

    var active_media: std.ArrayList([]const u8) = .empty;
    defer {
        for (active_media.items)
            |n|
        {
            STATE.allocator.free(n);
        }
        active_media.deinit(STATE.allocator);
    }

    if (STATE.maybe_hovered_interval)
        |hovered_ind|
    {
        const hovered_mapping_indices = (
            builder.intervals.items(
                .mapping_index,
            )[hovered_ind]
        );

        for (hovered_mapping_indices)
            |hovered_map_ind|
        {
            const dest_ind= builder.mappings.items(.destination)[hovered_map_ind];
            const dest = builder.tree.nodes.get(dest_ind);
            const mapping = builder.mappings.items(.mapping)[hovered_map_ind];

            const projection_operator = (
                otio.ProjectionOperator{
                    .destination = dest,
                    .source = builder.source,
                    .src_to_dst_topo = .{
                        .mappings = &.{ mapping },
                    },
                }
            );

            const proj_result = projection_operator.project_instantaneous_cc_assume_in_bounds(
                source_ord
            );

            if (proj_result == .out_of_bounds)
            {
                std.debug.print(
                    "Error: could not project into space: {f}.\n",
                    .{
                        dest
                    }
                );
                continue;
            }
            const dest_time = projection_operator.project_instantaneous_cc_assume_in_bounds(
                source_ord
            ).success_ordinate;

            var discrete_writer = std.Io.Writer.Allocating.init(
                allocator,
            );
            const d_w = &discrete_writer.writer;
            defer discrete_writer.deinit();

            inline for (@typeInfo(otio.Domain).@"union".fields)
                |field|
            {
                const domain = @unionInit(
                    otio.Domain,
                    field.name,
                    undefined,
                );
                if (
                    if (dest.discrete_partition(domain) != null) (
                        try projection_operator.project_instantaneous_cd(
                            source_ord,
                            domain,
                        )
                    )
                    else null
                ) |discrete_ind|
                {
                    try d_w.print(
                        "\n  d/{s}: {d}",
                        .{
                            @tagName(domain),
                            discrete_ind,
                        },
                    );
                }
            }

            try active_media.append(
                STATE.allocator,
                try std.fmt.allocPrint(
                    STATE.allocator,
                    "{f}: {d:0.2}s / {s}",
                    .{
                        dest,
                        dest_time.as(f32),
                        discrete_writer.written(),
                    },
                )
            );

            zplot.pushStyleVar1f(
                .{ .idx = .line_weight, .v = 4.0 },
            );
            zplot.pushStyleVar1f(
                .{ .idx = .marker_weight, .v = 4.0 },
            );
            defer zplot.popStyleVar(.{ .count = 2 });

            // x-axis -> mouse
            {
                var xs: [2]f64 = .{ mouse_pos[0], mouse_pos[0] };
                var ys: [2]f64 = .{ 0, dest_time.as(f64), }; 

                zplot.plotLine(
                    "Projected Point",
                    f64, 
                    .{
                        .xv = &xs,
                        .yv = &ys,
                    },
                );
            }

            // mouse -> y-axis
            {
                var xs: [2]f64 = .{ 0, mouse_pos[0] };
                var ys: [2]f64 = .{ dest_time.as(f64), dest_time.as(f64) }; 

                zplot.plotLine(
                    "Projected Point",
                    f64, 
                    .{
                        .xv = &xs,
                        .yv = &ys,
                    },
                );
            }

            {
                var xs: [1]f64 = .{ mouse_pos[0] };
                var ys: [1]f64 = .{ dest_time.as(f64) }; 
                zplot.plotScatter(
                    "Projected Point",
                    f64, 
                    .{
                        .xv = &xs,
                        .yv = &ys,
                    },
                );
            }
        }
    }

    var bufs= std.Io.Writer.Allocating.init(STATE.allocator);
    for (active_media.items, 0..)
        |cl, ind|
    {
        try bufs.writer.print(
            "  {s}",
            .{ cl },
        );
        if (ind < active_media.items.len - 1)
        {
            _ = try bufs.writer.write("\n");
        }
    }
    defer bufs.deinit();

    var buf2:[1024]u8 = undefined;
    const lbl = try std.fmt.bufPrintZ(
        &buf2,
        (
              "source time: {d:0.2}s\n"
              ++ "interval: {?d}\n"
              ++ "mappings active:\n{s}\n"
        ),
        .{
            mouse_pos[0],
            STATE.maybe_hovered_interval,
            bufs.written(),
        },
    );

    const mouse_screen_pos = zgui.getMousePos();
    zgui.setNextWindowPos(
        .{
            .x = mouse_screen_pos[0] + 15,
            .y = mouse_screen_pos[1] + 15,
        }
    );
    zgui.setNextWindowBgAlpha(.{ .alpha = 0.75 });

    if (
        zgui.begin(
            "###PlotHoveredText",
            .{
                .flags = .{
                    .no_title_bar = true,
                    .no_resize = true,
                    .no_move = true,
                    .always_auto_resize = true,
                    .no_saved_settings = true,
                    .no_focus_on_appearing = true,
                    .no_nav_inputs = true,
                    .no_nav_focus = true,
                },
            },
        )
    )
    {
        defer zgui.end();

        zgui.text(
            "{s}",
            .{lbl},
        );
    }
}

/// 2d Point in a plot
const PlotPoint2d = struct{
    x: f32,
    y: f32,
};

const Spaces = std.EnumSet(
    enum {
        presentation,
        intrinsic,
        media,
    }
);

const IS_WASM = builtin.target.cpu.arch.isWasm();

fn label_for_ref(
    buf: []u8,
    item: otio.CompositionItemHandle,
) ![]const u8
{
    return try std.fmt.bufPrintZ(
        buf,
        "{s}.{?s}",
        .{ @tagName(item), item.name() },
    );

}

fn child_tree(
    allocator: std.mem.Allocator,
    children: []otio.CompositionItemHandle,
) !void
{
    if (children.len == 0)
    {
        return;
    }

    for (children, 0..)
        |child,ind|
    {
        var buf:[1024:0]u8 = undefined;

        const label = try std.fmt.bufPrintZ(
            buf[0..512],
            "{d}: {s}",
            .{ ind, try label_for_ref(buf[512..], child) }
        );

        const next_children = try child.children_refs(allocator);
        defer allocator.free(next_children);

        if (
            zgui.treeNodeFlags(
                label,
                .{
                    .bullet = next_children.len == 0,
                }
            )
        )
        {
            defer zgui.treePop();

            try child_tree(allocator, next_children);
        }

        if (zgui.isItemClicked(.left))
        {
            STATE.maybe_current_selected_object = child;

            if (STATE.maybe_cached_topology)
                |topo|
            {
                topo.deinit(allocator);
                STATE.maybe_cached_topology = null;
            }

            STATE.maybe_cached_topology = try child.topology(allocator);
            std.debug.print("clicked on: {s}\n", .{label});
        }
    }
}

// ============================================================================
// Timeline View (raven-like)
// ============================================================================

/// Convert time in seconds to pixel position
fn time_to_pixel(time_seconds: f32, scale: f32) f32 {
    return (time_seconds - STATE.timeline.start) * scale;
}

/// Convert pixel position to time in seconds
fn pixel_to_time(pixel: f32, scale: f32) f32 {
    return STATE.timeline.start + pixel / scale;
}

/// Format time as timecode string HH:MM:SS:FF (assuming 24fps)
fn format_timecode(buf: []u8, time_seconds: f32) []const u8 {
    const fps: f32 = 24.0;
    const total_frames: u32 = @intFromFloat(@abs(time_seconds) * fps);
    const frames = total_frames % 24;
    const total_seconds = total_frames / 24;
    const seconds = total_seconds % 60;
    const total_minutes = total_seconds / 60;
    const minutes = total_minutes % 60;
    const hours = total_minutes / 60;

    return std.fmt.bufPrint(
        buf,
        "{d:0>2}:{d:0>2}:{d:0>2}:{d:0>2}",
        .{ hours, minutes, seconds, frames },
    ) catch "00:00:00:00";
}

/// Draw the timecode ruler at the top of the timeline
fn draw_timecode_ruler(
    origin: [2]f32,
    width: f32,
    height: f32,
    scale: f32,
) void
{
    const draw_list = zgui.getWindowDrawList();

    // Calculate tick interval based on zoom level
    const pixels_per_second = scale;
    var tick_interval: f32 = 1.0; // Start at 1 second
    const min_tick_width: f32 = 100.0;

    // Adjust tick interval based on zoom
    if (pixels_per_second * tick_interval < min_tick_width) {
        tick_interval = 2.0;
    }
    if (pixels_per_second * tick_interval < min_tick_width) {
        tick_interval = 5.0;
    }
    if (pixels_per_second * tick_interval < min_tick_width) {
        tick_interval = 10.0;
    }
    if (pixels_per_second * tick_interval > min_tick_width * 5) {
        tick_interval = 0.5;
    }
    if (pixels_per_second * tick_interval > min_tick_width * 5) {
        tick_interval = 0.25;
    }

    // Draw background
    draw_list.addRectFilled(
        .{
            .pmin = .{ origin[0], origin[1] },
            .pmax = .{ origin[0] + width, origin[1] + height },
            .col = TimelineColors.background,
        },
    );

    // Draw tick marks
    var time: f32 = STATE.timeline.start;
    while (time < STATE.timeline.start + STATE.timeline.duration + tick_interval) : (time += tick_interval) {
        const x = origin[0] + time_to_pixel(time, scale);
        if (x < origin[0] or x > origin[0] + width) continue;

        // Draw tick line
        draw_list.addLine(
            .{
                .p1 = .{ x, origin[1] + height * 0.6 },
                .p2 = .{ x, origin[1] + height },
                .col = TimelineColors.tick_major,
                .thickness = 1.0,
            },
        );

        // Draw time label in timecode format
        var tc_buf: [16]u8 = undefined;
        const tc_str = format_timecode(&tc_buf, time);
        draw_list.addText(
            .{ x + 3, origin[1] + 2 },
            TimelineColors.label,
            "{s}",
            .{tc_str},
        );
    }
}

/// Draw a track label in the left column (legacy function, kept for compatibility)
fn draw_track_label(
    track_name: []const u8,
    _: []const u8,  // track_kind - unused, we always show "V" prefix
    index: usize,
    height: f32,
    is_selected: bool,
) void
{
    const width = zgui.getContentRegionAvail()[0];

    zgui.beginGroup();
    defer zgui.endGroup();

    _ = zgui.invisibleButton(
        "##TrackLabel",
        .{ .w = width, .h = height },
    );

    const p0 = zgui.getItemRectMin();
    const p1 = zgui.getItemRectMax();

    var fill_color = TimelineColors.track_label;
    if (zgui.isItemHovered(.{})) {
        fill_color = TimelineColors.track_label_hover;
    }
    if (is_selected) {
        fill_color = TimelineColors.track_label_selected;
    }

    const draw_list = zgui.getWindowDrawList();
    draw_list.addRectFilled(
        .{
            .pmin = p0,
            .pmax = p1,
            .col = fill_color,
        },
    );

    // Draw label text - format like raven: "V1: Track-00"
    var buf: [64]u8 = undefined;
    const label = std.fmt.bufPrintZ(
        &buf,
        "V{d}: {s}",
        .{
            index,
            track_name,
        },
    ) catch "?";

    draw_list.addText(
        .{ p0[0] + 5, p0[1] + 5 },
        TimelineColors.label,
        "{s}",
        .{label},
    );
}

/// Draw a single item (clip or gap) on the timeline
fn draw_timeline_item(
    item: otio.CompositionItemHandle,
    start_time: f32,
    duration_seconds: f32,
    origin: [2]f32,
    height: f32,
    scale: f32,
) void
{
    if (duration_seconds <= 0) return;

    const x = origin[0] + time_to_pixel(start_time, scale);
    const width = duration_seconds * scale;

    if (width < 1) return;

    // Calculate screen-space rectangle for this item
    const p0 = [2]f32{ x, origin[1] };
    const p1 = [2]f32{ x + width, origin[1] + height };

    // Get the underlying pointer for pushPtrId
    const item_ptr: *const anyopaque = switch (item) {
        inline else => |p| p,
    };
    zgui.pushPtrId(item_ptr);
    defer zgui.popId();

    // Use invisible button for interaction, positioned at the item location
    zgui.setCursorScreenPos(p0);
    _ = zgui.invisibleButton("##Item", .{ .w = width, .h = height });

    // Determine colors based on item type and state
    var fill_color: u32 = undefined;
    var show_label = true;
    const is_gap = item == .gap;

    switch (item) {
        .gap => {
            fill_color = TimelineColors.gap;
            show_label = false;
        },
        .clip => {
            fill_color = TimelineColors.item;
        },
        else => {
            fill_color = TimelineColors.item;
        },
    }

    if (zgui.isItemHovered(.{})) {
        fill_color = if (is_gap) TimelineColors.gap_hover else TimelineColors.item_hover;
    }

    if (STATE.maybe_current_selected_object) |selected| {
        if (std.meta.eql(selected, item)) {
            fill_color = TimelineColors.item_selected;
        }
    }

    // Handle click
    if (zgui.isItemClicked(.left)) {
        STATE.maybe_current_selected_object = item;
    }

    const draw_list = zgui.getWindowDrawList();

    // Draw rectangle - rounded for clips, square for gaps
    if (is_gap) {
        // Gaps: simple rectangle with no rounding
        draw_list.addRectFilled(
            .{
                .pmin = p0,
                .pmax = p1,
                .col = fill_color,
                .rounding = 0,
            },
        );
    } else {
        // Clips: rounded rectangle (top-left, bottom-right corners rounded)
        const rounding: f32 = 5.0;
        draw_list.addRectFilled(
            .{
                .pmin = p0,
                .pmax = p1,
                .col = fill_color,
                .rounding = rounding,
                .flags = .{
                    .round_corners_top_left = true,
                    .round_corners_bottom_right = true,
                },
            },
        );
    }

    // Draw label if there's room
    if (show_label and width > 20) {
        const name = item.maybe_name() orelse "";
        if (name.len > 0) {
            draw_list.addText(
                .{ p0[0] + 5, p0[1] + 5 },
                TimelineColors.label,
                "{s}",
                .{name},
            );
        }
    }

    // Tooltip on hover
    if (zgui.isItemHovered(.{})) {
        if (zgui.beginTooltip()) {
            defer zgui.endTooltip();

            zgui.text("{s}: {s}", .{
                @tagName(item),
                item.maybe_name() orelse "(unnamed)",
            });
            zgui.text("Duration: {d:.2}s", .{duration_seconds});
        }
    }
}

/// Draw a single track's content
fn draw_track_content(
    allocator: std.mem.Allocator,
    track: otio.CompositionItemHandle,
    origin: [2]f32,
    full_width: f32,
    height: f32,
    scale: f32,
) !void
{
    _ = full_width;

    // Get track children
    const children = try track.children_refs(allocator);
    defer allocator.free(children);

    // Calculate positions for each child
    var current_time: f32 = 0.0;

    for (children) |child| {
        // Get duration of this item using bounds_of
        const bounds = child.bounds_of(allocator, .presentation) catch null;
        const duration_seconds: f32 = if (bounds) |b| b.duration().as(f32) else 1.0;

        // Draw the item
        draw_timeline_item(
            child,
            current_time,
            duration_seconds,
            origin,
            height,
            scale,
        );

        current_time += duration_seconds;
    }
}

/// Draw the playhead indicator
fn draw_playhead(
    origin: [2]f32,
    height: f32,
    scale: f32,
    track_height: f32,
) void
{
    const playhead_x = origin[0] + time_to_pixel(STATE.timeline.playhead, scale);

    const draw_list = zgui.getWindowDrawList();

    // Draw vertical line
    draw_list.addLine(
        .{
            .p1 = .{ playhead_x, origin[1] },
            .p2 = .{ playhead_x, origin[1] + height },
            .col = TimelineColors.playhead_line,
            .thickness = 2.0,
        },
    );

    // Draw triangle at top
    const arrow_size: f32 = @min(track_height / 2, 12);
    draw_list.addTriangleFilled(
        .{
            .p1 = .{ playhead_x - arrow_size / 2, origin[1] },
            .p2 = .{ playhead_x + arrow_size / 2, origin[1] },
            .p3 = .{ playhead_x, origin[1] + arrow_size },
            .col = TimelineColors.playhead_line,
        },
    );

    // Draw time label
    draw_list.addText(
        .{ playhead_x + 5, origin[1] + 2 },
        TimelineColors.label,
        "{d:.2}s",
        .{STATE.timeline.playhead},
    );
}

/// Draw the timeline view tab content
fn draw_timeline_tab(
    allocator: std.mem.Allocator,
) !void
{
    // Update timeline duration from the loaded OTIO
    if (STATE.maybe_proj_builder) |builder| {
        if (builder.input_bounds()) |bounds| {
            STATE.timeline.start = bounds.start.as(f32);
            STATE.timeline.duration = bounds.duration().as(f32);
        }
    }

    const scale = STATE.timeline.scale;
    const track_height = STATE.timeline.track_height;
    const track_label_width: f32 = 100.0;

    // Get available size for timeline
    const avail = zgui.getContentRegionAvail();
    const content_width = avail[0] - track_label_width - 20;  // Leave some margin

    // Calculate timeline content width - use at least the visible width
    const timeline_content_width = @max(content_width, STATE.timeline.duration * scale);

    // Collect tracks first so we know how many there are
    var tracks_to_draw: std.ArrayListUnmanaged(otio.CompositionItemHandle) = .empty;
    defer tracks_to_draw.deinit(allocator);

    const root_children = try STATE.otio_root.children_refs(allocator);
    defer allocator.free(root_children);

    for (root_children) |child| {
        switch (child) {
            .track => {
                try tracks_to_draw.append(allocator, child);
            },
            .stack => {
                const stack_children = try child.children_refs(allocator);
                defer allocator.free(stack_children);
                for (stack_children) |stack_child| {
                    switch (stack_child) {
                        .track => {
                            try tracks_to_draw.append(allocator, stack_child);
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    const num_tracks = tracks_to_draw.items.len;

    // Transport controls in a row at top
    {
        // Playhead time display in timecode format
        var tc_buf: [16]u8 = undefined;
        const tc_str = format_timecode(&tc_buf, STATE.timeline.playhead);
        zgui.text("{s}", .{tc_str});

        zgui.sameLine(.{});
        zgui.setNextItemWidth(150);
        _ = zgui.sliderFloat(
            "##Zoom",
            .{
                .v = &STATE.timeline.scale,
                .min = 10.0,
                .max = 500.0,
                .cfmt = "Zoom: %.0f",
                .flags = .{ .logarithmic = true },
            },
        );

        zgui.sameLine(.{});
        if (zgui.button("Fit", .{})) {
            if (STATE.timeline.duration > 0) {
                STATE.timeline.scale = content_width / STATE.timeline.duration;
            }
        }
    }

    // Create a child window for the timeline with horizontal scrolling
    if (zgui.beginChild(
        "TimelineScrollArea",
        .{
            .w = avail[0],
            .h = avail[1] - 30,  // Leave room for controls
            .window_flags = .{
                .horizontal_scrollbar = true,
            },
        },
    )) {
        defer zgui.endChild();

        const window_pos = zgui.getCursorScreenPos();
        const draw_list = zgui.getWindowDrawList();

        // Draw background for entire timeline area
        const total_height = @as(f32, @floatFromInt(num_tracks + 1)) * track_height;
        draw_list.addRectFilled(
            .{
                .pmin = window_pos,
                .pmax = .{
                    window_pos[0] + track_label_width + timeline_content_width,
                    window_pos[1] + total_height,
                },
                .col = TimelineColors.background,
            },
        );

        // Ruler row
        const ruler_origin: [2]f32 = .{
            window_pos[0] + track_label_width,
            window_pos[1],
        };

        // Draw "Timeline" label in first column
        draw_list.addRectFilled(
            .{
                .pmin = window_pos,
                .pmax = .{ window_pos[0] + track_label_width, window_pos[1] + track_height },
                .col = TimelineColors.track_label,
            },
        );
        draw_list.addText(
            .{ window_pos[0] + 5, window_pos[1] + 5 },
            TimelineColors.label,
            "Timeline",
            .{},
        );

        // Draw timecode ruler
        draw_timecode_ruler(
            ruler_origin,
            timeline_content_width,
            track_height,
            scale,
        );

        // Invisible button over ruler for click-to-seek
        zgui.setCursorScreenPos(ruler_origin);
        _ = zgui.invisibleButton("##RulerSeek", .{ .w = timeline_content_width, .h = track_height });
        if (zgui.isItemActive()) {
            const mouse_pos = zgui.getMousePos();
            STATE.timeline.playhead = pixel_to_time(
                mouse_pos[0] - ruler_origin[0],
                scale,
            );
            STATE.timeline.playhead = @max(
                STATE.timeline.start,
                @min(
                    STATE.timeline.start + STATE.timeline.duration,
                    STATE.timeline.playhead,
                ),
            );
        }

        // Draw tracks in reverse order (highest track at top, like raven)
        var reverse_idx: usize = num_tracks;
        var row: usize = 1;  // Start after ruler row
        while (reverse_idx > 0) {
            reverse_idx -= 1;
            const child = tracks_to_draw.items[reverse_idx];
            const display_idx = reverse_idx + 1;  // 1-based index

            switch (child) {
                .track => |track_ptr| {
                    const row_y = window_pos[1] + @as(f32, @floatFromInt(row)) * track_height;

                    // Track label
                    const label_p0: [2]f32 = .{ window_pos[0], row_y };
                    const label_p1: [2]f32 = .{ window_pos[0] + track_label_width, row_y + track_height };

                    const is_selected = if (STATE.maybe_current_selected_object) |sel|
                        std.meta.eql(sel, child)
                    else
                        false;

                    var label_color = TimelineColors.track_label;
                    if (is_selected) {
                        label_color = TimelineColors.track_label_selected;
                    }

                    draw_list.addRectFilled(
                        .{
                            .pmin = label_p0,
                            .pmax = label_p1,
                            .col = label_color,
                        },
                    );

                    // Format label like raven: "V1: Track-00"
                    var label_buf: [64]u8 = undefined;
                    const track_label = std.fmt.bufPrint(
                        &label_buf,
                        "V{d}: {s}",
                        .{ display_idx, track_ptr.maybe_name orelse "" },
                    ) catch "?";

                    draw_list.addText(
                        .{ label_p0[0] + 5, label_p0[1] + 8 },
                        TimelineColors.label,
                        "{s}",
                        .{track_label},
                    );

                    // Invisible button for track label selection
                    zgui.setCursorScreenPos(label_p0);
                    zgui.pushPtrId(track_ptr);
                    _ = zgui.invisibleButton("##TrackLabel", .{ .w = track_label_width, .h = track_height });
                    if (zgui.isItemClicked(.left)) {
                        STATE.maybe_current_selected_object = child;
                    }
                    zgui.popId();

                    // Track content origin
                    const content_origin: [2]f32 = .{
                        window_pos[0] + track_label_width,
                        row_y,
                    };

                    // Draw track content (clips, gaps)
                    try draw_track_content(
                        allocator,
                        child,
                        content_origin,
                        timeline_content_width,
                        track_height,
                        scale,
                    );

                    row += 1;
                },
                else => {},
            }
        }

        // Draw playhead over everything
        draw_playhead(ruler_origin, total_height, scale, track_height);

        // Make the entire timeline area clickable for playhead seeking
        zgui.setCursorScreenPos(.{ ruler_origin[0], ruler_origin[1] + track_height });
        _ = zgui.invisibleButton(
            "##TimelineSeek",
            .{ .w = timeline_content_width, .h = total_height - track_height },
        );
        if (zgui.isItemActive()) {
            const mouse_pos = zgui.getMousePos();
            STATE.timeline.playhead = pixel_to_time(
                mouse_pos[0] - ruler_origin[0],
                scale,
            );
            STATE.timeline.playhead = @max(
                STATE.timeline.start,
                @min(
                    STATE.timeline.start + STATE.timeline.duration,
                    STATE.timeline.playhead,
                ),
            );
        }

        // Set content size to enable scrolling
        zgui.dummy(.{ .w = track_label_width + timeline_content_width, .h = total_height });
    }
}

/// draw the UI
fn draw(
) !void
{
    const vp = zgui.getMainViewport();
    const size = vp.getSize();

    const allocator = STATE.allocator;

    zgui.setNextWindowPos(.{ .x = 0, .y = 0 });
    zgui.setNextWindowSize(
        .{ 
            .w = size[0],
            .h = size[1],
        },
    );

    if (
        zgui.begin(
            "###FULLSCREEN",
            .{ 
                .flags = .{
                    .no_resize = true, 
                    .no_scroll_with_mouse  = true, 
                    .always_auto_resize = true, 
                    .no_move = true,
                    .no_collapse = true,
                    .no_title_bar = true,
                    .no_bring_to_front_on_focus = true,
                    .no_scrollbar = true,
                },
            },
        )
    )
    {
        defer zgui.end();

        if (STATE.maybe_file_read_query)
            |query|
        {
            if (query.state != .loaded)
            {
                zgui.text(
                    "not loaded...{s}\n",
                    .{@tagName(query.state)},
                );
                // file hasn't been loaded yet, don't show the UI
                return;
            }
        }
        else {
            // fire off the callback to load the file
            STATE.maybe_file_read_query = (
                try app_wrapper.fetch_resource_from_path(
                    STATE.allocator,
                    STATE.target_otio_file, 
                    null,
                )
            );
        }

        if (
            zgui.beginChild(
                "TopChunk",
                .{
                    .h = 10,
                    .w = size[0],
                    .child_flags = .{
                        .resize_y = true,
                    },
                    .window_flags = .{
                        .no_resize = false,
                    },
                },
            )
            and zgui.beginTabBar(
                "TopChunk",
                .{
                }
            )
        )
        {
            defer zgui.endChild();
            defer zgui.endTabBar();

            if (zgui.beginTabItem("Node Table", .{}))
            {
                defer zgui.endTabItem();
                // defer zgui.endChild();

                if (
                    zgui.beginTable(
                        "NodeTreeTable",
                        .{
                            .column = 4,
                            .flags = .{
                                .resizable = true,
                            }
                        }
                    )
                )
                {
                    defer zgui.endTable();

                    // headers
                    zgui.tableNextRow(
                        .{
                            .row_flags = .{
                                .headers = true,
                            },
                        },
                    );

                    _ = zgui.tableSetColumnIndex(0);
                    inline for (
                        &[_] []const u8{
                            "Node Name",
                            "Show Graph",
                            "Source",
                            "Destination",
                        },
                    ) |key|
                    {
                        zgui.textUnformatted(key);
                        _ = zgui.tableNextColumn();
                    }

                    _ = zgui.tableSetColumnIndex(0);

                    const slices = STATE.slices.slice();
                    const labels = slices.items(.label);
                    for (labels)
                        |name|
                    {
                        zgui.textUnformatted(name);
                        _ = zgui.tableNextColumn();

                        zgui.textUnformatted("View");
                        _ = zgui.tableNextColumn();

                        zgui.textUnformatted("Set Source");
                        _ = zgui.tableNextColumn();

                        zgui.textUnformatted("Set Dest");
                        _ = zgui.tableNextColumn();
                    }
                }
            }

            if (zgui.beginTabItem("Options", .{}))
            {
                defer zgui.endTabItem();

                zgui.separatorText("Runtime Options");

                try struct_editor_ui(
                    @TypeOf(STATE.options),
                    &STATE.options,
                );
            }

            const cols = (
                if (STATE.maybe_proj_builder) 
                    |b| 
                    @min(511, b.intervals.len)
                else 0
            );

            if (
                zgui.beginTabItem("Interval Spreadsheet", .{})
                and zgui.beginTable(
                    "IntervalTable",
                    .{
                        .flags = .{
                            .highlight_hovered_column = true,
                            .resizable = true,
                            .scroll_x = true,
                        },
                        .column = @intCast(cols),
                    }
                )
            )
            {
                defer zgui.endTabItem();
                defer zgui.endTable();

                var rows:usize = 0;
                if (STATE.maybe_proj_builder)
                    |builder|
                {
                    const intervals = builder.intervals.slice();
                    for (intervals.items(.mapping_index))
                        |mappings|
                    {
                        rows = @max(rows, mappings.len);
                    }

                    zgui.tableHeadersRow();
                    _ = zgui.tableSetColumnIndex(0);

                    for (0..cols)
                        |col|
                    {
                        const hovered_interval = (
                            STATE.maybe_hovered_interval != null
                            and STATE.maybe_hovered_interval == col
                        );

                        if (hovered_interval)
                        {
                            zgui.pushStyleColor4f(
                                .{ 
                                    .c = .{ 1, 1, 0, 1  },
                                    .idx = .text,
                                }
                            );
                        }
                        defer {
                            if (hovered_interval)
                            {
                                zgui.popStyleColor(.{ .count = 1 });
                            }
                        }
                        zgui.text(
                            "{d}{s}",
                            .{
                                col,
                                if (hovered_interval) " (HOVERED)" else ""
                            }
                        );
                        _ = zgui.tableNextColumn();
                    }

                    zgui.tableNextRow(.{});
                    _ = zgui.tableSetColumnIndex(0);

                    for (0..rows)
                        |row_index|
                    {
                        for (0..cols)
                            |col|
                        {
                            const hovered_interval = (
                                STATE.maybe_hovered_interval != null
                                and STATE.maybe_hovered_interval == col
                            );

                            if (hovered_interval)
                            {
                                zgui.pushStyleColor4f(
                                    .{ 
                                        .c = .{ 1, 1, 0, 1  },
                                        .idx = .text,
                                    }
                                );
                            }
                            defer {
                                if (hovered_interval)
                                {
                                    zgui.popStyleColor(.{ .count = 1 });
                                }
                            }

                            const mappings = intervals.items(.mapping_index)[col];
                            if (row_index < mappings.len) 
                            {
                                zgui.text(
                                    "{f}",
                                    .{
                                        builder.space_from_mapping_index(
                                            mappings[row_index] 
                                        ) 
                                    },
                                );
                            }

                            _ = zgui.tableNextColumn();
                        }
                        zgui.tableNextRow(.{});
                        _ = zgui.tableSetColumnIndex(0);
                    }

                }

                {
                    const col = zgui.tableGetHoveredColumn();
                    if (col >= 0)
                    {
                        STATE.maybe_hovered_interval = @intCast(col);
                    }
                }
            }

            if (
                zgui.beginTabItem(
                    "Raw OTIO",
                    .{
                        .flags = .{
                            // .leading = true 
                            .leading = false 
                        }
                    },
                )
            )
            {
                defer zgui.endTabItem();

                _ = zgui.beginChild(
                    "Inner Long Text Window",
                    .{
                        .h = -1,
                        .w = -1,
                        .window_flags= .{
                            .always_vertical_scrollbar = true,
                        },
                        .child_flags = .{
                            .border = true,
                        },
                    }
                );
                defer zgui.endChild();

                zgui.text(
                    "Loaded file: {s}",
                    .{ STATE.target_otio_file }
                );
                zgui.separator();

                zgui.textUnformatted(STATE.maybe_file_read_query.?.data);
            }

            // Timeline tab (raven-like view)
            if (zgui.beginTabItem("Timeline", .{}))
            {
                defer zgui.endTabItem();
                try draw_timeline_tab(allocator);
            }
        }

        if (
            zgui.beginChild(
                "Bottom Chunk",
                .{
                    .child_flags = .{
                        .resize_y = true,
                    },
                }
            )
        )
        {
            defer zgui.endChild();

            // if (
            //     zgui.beginTable(
            //         "Transform Info Table",
            //         .{
            //             .column = 2,
            //             .flags = .{
            //                 .borders = .all,
            //             },
            //         },
            //     )
            // )
            // {
            //     defer zgui.endTable();
            //
            //     zgui.tableNextRow(.{});
            //
            //     _ = zgui.tableSetColumnIndex(0);
            //     zgui.text("Source Space: ", .{});
            //
            //     _ = zgui.tableSetColumnIndex(1);
            //
            //     if (STATE.maybe_src)
            //         |src|
            //     {
            //         zgui.text("{f}", .{src});
            //     }
            //     else
            //     {
            //         zgui.text("NONE SET", .{});
            //     }
            //
            //     zgui.tableNextRow(.{});
            //
            //     _ = zgui.tableSetColumnIndex(0);
            //     zgui.text("Destination Space: ", .{});
            //
            //     _ = zgui.tableSetColumnIndex(1);
            //     if (STATE.maybe_dst)
            //         |dst|
            //     {
            //         zgui.text("{f}", .{dst});
            //     }
            //     else
            //     {
            //         zgui.text("NONE SET", .{});
            //     }
            //
            //     zgui.tableNextRow(.{});
            //
            //     _ = zgui.tableSetColumnIndex(@intCast(0));
            //     zgui.text("Mappings", .{});
            //
            //     _ = zgui.tableSetColumnIndex(@intCast(1));
            //     if (STATE.maybe_transform)
            //         |xform|
            //     {
            //         zgui.text("{d}", .{xform.mappings.len});
            //
            //         zgui.tableNextRow(.{});
            //         table_fill_row(&.{ "Mappings:", "" });
            //
            //         for (xform.mappings)
            //             |m|
            //         {
            //             zgui.tableNextRow(.{});
            //             var buf:[1024]u8 = undefined;
            //             const m_s = try std.fmt.bufPrint(&buf, "{f}", .{m});
            //             table_fill_row(&.{"", m_s});
            //         }
            //     }
            //     else
            //     {
            //         zgui.text("---", .{});
            //     }
            // }

            if (zgui.beginChild("PlotsTabs", .{}))
            {
                defer zgui.endChild();

                // graph of the transformation from source to dst
                if (zgui.beginTabBar("Plots", .{}))
                {
                    defer zgui.endTabBar();

                    if (
                        zgui.beginTabItem("All Items Under Source", .{})
                        and zgui.plot.beginPlot(
                            "All Items Under Source",
                            .{ 
                                .w = -1.0,
                                .h = -1.0,
                                .flags = .{ .equal = true },
                            },
                        )
                    )
                    {
                        defer zgui.endTabItem();
                        defer zgui.plot.endPlot();

                        var buf_src:[1024]u8 = undefined;

                        if (STATE.maybe_proj_builder)
                            |builder|
                        {
                            var buf:[]u8 = buf_src[0..];
                            const input_space_name = (
                                try std.fmt.bufPrintZ(
                                    buf,
                                    "{f}",
                                    .{ STATE.maybe_src.? },
                                )
                            );
                            buf = buf[input_space_name.len..];
                            zgui.plot.setupAxis(
                                .x1,
                                .{ .label = input_space_name },
                            );
                            zgui.plot.setupAxis(
                                .y1,
                                .{ .label = "output space" },
                            );
                            zgui.plot.setupLegend(
                                .{ 
                                    .south = true,
                                    .west = true 
                                },
                                .{},
                            );
                            zgui.plot.setupFinish();

                            // plot the input space - always linear
                            {
                                var xs: [2]f32 = undefined;
                                var ys: [2]f32 = undefined;

                                const ib = (
                                    builder.input_bounds().?
                                );
                                xs[0] = 0;
                                xs[1] = ib.duration().as(f32);

                                ys[0] = ib.start.as(f32);
                                ys[1] = ib.end.as(f32);

                                const plotlabel = try std.fmt.bufPrintZ(
                                    buf,
                                    "Continuous Presentation Space of {s}",
                                    .{ input_space_name },
                                );

                                zplot.pushStyleVar1f(
                                    .{
                                        .idx = .fill_alpha,
                                        .v = 0.4,
                                    },
                                );
                                zplot.plotLine(
                                    plotlabel,
                                    f32, 
                                    .{
                                        .xv = &xs,
                                        .yv = &ys,
                                        .flags = .{ 
                                            .shaded = true, 
                                        },
                                    },
                                );
                                zplot.popStyleVar(.{ .count = 1 });
                            }

                            inline for (&[_][]const u8{ "picture", "audio" })
                                |field|
                            {
                                if (@field(STATE.discrete_points, field))
                                    |discrete|
                                {
                                    zplot.pushStyleVar1f(
                                        .{
                                            .idx = .fill_alpha,
                                            .v = 0.4,
                                        },
                                    );

                                    const xs = discrete.items(.x);
                                    const ys = discrete.items(.y);

                                    var buf2:[1024]u8 = undefined;
                                    const plotlabel = try std.fmt.bufPrintZ(
                                        &buf2,
                                        "timeline presentation discrete {s}",
                                        .{ field },
                                    );

                                    zplot.plotLine(
                                        plotlabel,
                                        f32, 
                                        .{
                                            .xv = xs,
                                            .yv = ys,
                                            .flags = .{ 
                                                .shaded = true, 
                                            },
                                        },
                                    );
                                    zplot.popStyleVar(.{ .count = 1 });
                                }
                            }

                            // plot each child space
                            zplot.pushStyleVar1f(
                                .{
                                    .idx = .fill_alpha,
                                    .v = 0.2,
                                },
                            );
                            zplot.pushStyleVar1f(
                                .{
                                    .idx = .minor_alpha,
                                    .v = 0.2,
                                },
                            );

                            const slices = STATE.slices.slice();
                            for (
                                slices.items(.xs),
                                slices.items(.ys),
                                slices.items(.discrete_points),
                                slices.items(.label),
                                0..
                            ) |xs, ys, maybe_d_xys, label, ind|
                            {
                                const hovered_interval = (
                                    STATE.maybe_hovered_interval != null
                                    and STATE.maybe_hovered_interval == ind
                                );
                                if (hovered_interval) 
                                {
                                    zplot.pushStyleVar1f(
                                        .{
                                            .idx = .line_weight,
                                            .v = 4,
                                        }
                                    );
                                    zplot.pushStyleVar1f(
                                        .{
                                            .idx = .fill_alpha,
                                            .v = 0.1,
                                        }
                                    );
                                }

                                zplot.plotLine(
                                    label,
                                    f32, 
                                    .{
                                        .xv = xs,
                                        .yv = ys,
                                        .flags = .{
                                            .shaded = true,
                                        },
                                    },
                                );

                                if (
                                    STATE.options.show_discrete_ouput_spaces == .always
                                    or (
                                        STATE.options.show_discrete_ouput_spaces == .hovered
                                        and hovered_interval
                                    )
                                )
                                {
                                    if (maybe_d_xys)
                                        |d_xys|
                                    {
                                        var style = zplot.getStyle();
                                        const old_marker = style.marker;
                                        defer style.marker = old_marker;
                                        style.marker = .circle;
                                        zplot.plotStairs(
                                            label,
                                            f32, 
                                            .{
                                                .xv = d_xys[0],
                                                .yv = d_xys[1],
                                                .flags = .{
                                                    .shaded = true,
                                                },
                                            },
                                        );
                                    }
                                }
                                if (hovered_interval)
                                {
                                    zplot.popStyleVar(.{ .count = 2 });
                                }
                            }

                            // fill alpha, minor alpha
                            zplot.popStyleVar(.{ .count = 2 });

                            if (STATE.maybe_cut_points)
                                |cut_points|
                            {
                                zplot.plotInfLines(
                                    "Cut Points",
                                    f32,
                                    .{ .v = cut_points, },
                                );
                            }

                            if (zplot.isPlotHovered())
                            {
                                try draw_hover_extras(
                                    allocator,
                                    builder,
                                );
                            }
                        }
                    }

                    if (
                        zgui.beginTabItem("Transformation Plot", .{})
                        and zgui.plot.beginPlot(
                            "Transformation Plot",
                            .{ 
                                .w = -1.0,
                                .h = -1.0,
                                .flags = .{ .equal = true },
                            },
                        )
                    ) 
                    {
                        defer zgui.endTabItem();
                        defer zgui.plot.endPlot();

                        var buf_src:[1024]u8 = undefined;

                        if (STATE.maybe_transform != null)
                        {
                            var buf:[]u8 = buf_src[0..];
                            const input_space_name = try std.fmt.bufPrintZ(
                               buf,
                               "{f}",
                               .{ STATE.maybe_src.? },
                            );
                            buf = buf[input_space_name.len..];
                            zgui.plot.setupAxis(
                                .x1,
                                .{ .label = input_space_name },
                            );

                            const output_space_name = try std.fmt.bufPrintZ(
                               buf,
                               "{f}",
                               .{ STATE.maybe_dst.? },
                            );
                            buf = buf_src[output_space_name.len..];
                            zgui.plot.setupAxis(
                                .y1,
                                .{ .label = output_space_name },
                            );
                            zgui.plot.setupLegend(
                                .{ 
                                    .south = true,
                                    .west = true 
                                },
                                .{},
                            );
                            zgui.plot.setupFinish();

                            const NUM_POINTS = 300;

                            var xs: [NUM_POINTS]f32 = undefined;
                            var ys: [NUM_POINTS]f32 = undefined;

                            // plot the input space
                            if (STATE.maybe_proj_builder)
                                |builder|
                            {
                                var current_x = (
                                    builder.input_bounds().?.start
                                );
                                var current_y:opentime.Ordinate = .zero;
                                const inc = (
                                    builder.input_bounds().?.duration().div(
                                        @as(f32, @floatFromInt(NUM_POINTS))
                                    )
                                );
                                zgui.text("Inc: {f}", .{ inc });

                                for (&xs, &ys)
                                    |*x, *y|
                                {
                                    x.* = current_x.as(f32);
                                    y.* = current_y.as(f32);

                                    current_x = current_x.add(inc);
                                    current_y = current_y.add(inc);
                                }

                                const plotlabel = try std.fmt.bufPrintZ(
                                    buf,
                                    "Full Range of {s}",
                                    .{ input_space_name },
                                );
                                zplot.pushStyleVar1f(
                                    .{
                                        .idx = .fill_alpha,
                                        .v = 0.4,
                                    },
                                );
                                zplot.plotLine(
                                    plotlabel,
                                    f32, 
                                    .{
                                        .xv = &xs,
                                        .yv = &ys,
                                        .flags = .{.shaded = true},
                                    },
                                );
                                zplot.popStyleVar(.{ .count = 1 });
                            }

                            // plot the transform
                            if (STATE.maybe_transform)
                                |xform|
                            {
                                var current_x = (
                                    xform.input_bounds().?.start
                                );
                                const inc = (
                                    xform.input_bounds().?.duration().div(
                                        @as(f32, @floatFromInt(NUM_POINTS))
                                    )
                                );
                                zgui.text("Inc: {f}", .{ inc });

                                for (&xs, &ys)
                                    |*x, *y|
                                {
                                    x.* = current_x.as(f32);
                                    y.* = (
                                        xform.project_instantaneous_cc_assume_in_bounds(
                                            current_x,
                                        ).success_ordinate.as(f32)
                                    );

                                    current_x = current_x.add(inc);
                                }

                                zplot.pushStyleColor4f(
                                    .{
                                        .idx = .fill,
                                        .c = .{ 0.1, 0.1, 0.4, 0.4 },
                                    },
                                );

                                const plotlabel = try std.fmt.bufPrintZ(
                                    buf[800..],
                                    "{s} -> {s}",
                                    .{ input_space_name, output_space_name },
                                );
                                zplot.plotShaded(
                                    plotlabel,
                                    f32, 
                                    .{
                                        .xv = &xs,
                                        .yv = &ys,
                                        .flags = .{},
                                    },
                                );
                                zplot.popStyleColor(.{.count = 1});

                                zplot.plotLine(
                                    plotlabel,
                                    f32, 
                                    .{
                                        .xv = &xs,
                                        .yv = &ys,
                                    },
                                );
                            }
                        }
                    }
                }
            }
        }
    }
}

fn cleanup (
) void
{
    const allocator = STATE.allocator;

    if (STATE.maybe_file_read_query)
        |query|
    {
        allocator.destroy(query);
    }

    if (STATE.maybe_journal)
        |*definitely_journal|
    {
        definitely_journal.deinit();
    }

    var points = &STATE.points;
    var slices = &STATE.slices;
    const cut_points = &STATE.maybe_cut_points;

    var discrete_points = &STATE.discrete_points;
    inline for (&[_][]const u8{ "picture", "audio" })
        |field|
    {
        if (@field(discrete_points, field))
            |*discrete|
        {
            discrete.deinit(allocator);
        }
    }

    // clear whatever is there
    points.deinit(STATE.allocator);

    if (STATE.maybe_cached_topology)
        |topo|
    {
        topo.deinit(STATE.allocator);
        STATE.maybe_cached_topology = null;
    }

    if (cut_points.*)
        |cp|
    {
        STATE.allocator.free(cp);
    }

    for (slices.items(.label))
        |label|
    {
        // Label does some shenanigans with [:0] casting, this puts it back the
        // way it was allocated.  This is because allocPrintZ no longer exists.
        STATE.allocator.free(@as([]const u8, @ptrCast(label)));
    }
    slices.deinit(STATE.allocator);

    if (STATE.maybe_proj_builder)
        |*builder|
    {
        builder.deinit(STATE.allocator);
    }

    STATE.otio_root.deinit(STATE.allocator);
    STATE.allocator.free(STATE.target_otio_file);

    STATE.allocator.free(STATE.otio_src_json);

    if (IS_WASM == false and builtin.mode == .Debug)
    {
        const result = STATE.debug_allocator.deinit();
        if (result == .leak) 
        {
            std.log.debug("leak!", .{});
        }
    }
}

pub fn init(
) void
{
}

pub fn main(
) !void 
{
    // configure the allocator
    STATE.allocator = (
        if (IS_WASM) (
            std.heap.c_allocator
        )
        else 
        (
            if (builtin.mode == .Debug) alloc: {
                STATE.debug_allocator =  std.heap.DebugAllocator(.{}){};
                break :alloc STATE.debug_allocator.allocator();
            } else std.heap.smp_allocator
        )
    );

    const prog = (
        if (IS_WASM == false) std.Progress.start(.{})
    );
    defer if (IS_WASM == false) prog.end();

    const parent_prog = if (IS_WASM == false) (
        prog.start(
            "Initializing",
            3,
        )
    );

    {
        const init_progress = if (IS_WASM == false) (
            parent_prog.start(
                "Initializing State...",
                0,
            )
        );
        defer if (IS_WASM == false) init_progress.end();

        STATE.maybe_journal = ziis.undo.Journal.init(
            STATE.allocator,
            5,
        ) catch null;
    }

    {
        const read_prog = if (IS_WASM == false) (
            parent_prog.start(
                "Reading file...",
                0,
            )
        );
        defer if (IS_WASM == false) read_prog.end();

        STATE.target_otio_file = (try _parse_args(STATE.allocator)).input_otio;
        var found = true;

        std.debug.print("attempting fetch\n", .{});
        std.fs.cwd().access(
            STATE.target_otio_file,
            .{},
        ) catch |e| switch (e) {
            error.FileNotFound => found = false,
            else => return e,
        };
        if (found == false)
        {
            std.log.err(
                "File: {s} does not exist or is not accessible.",
                .{STATE.target_otio_file},
            );
        }

        // Read timeline file - supports .otio, .tla, .tlb, .tlfb, .tlz
        // Skip metadata for faster visualization
        STATE.otio_root = try otio.read_from_file(
            STATE.allocator,
            STATE.target_otio_file,
            .{ .file_contents_to_read = .all_except_metadata },
        );

        // read the file contents
        {
            const file = try std.fs.cwd().openFile(
                STATE.target_otio_file,
                .{},
            );
            defer file.close();

            STATE.otio_src_json = try file.readToEndAlloc(
                STATE.allocator,
                1024*1024*1024,
            );
        }

        try set_source(
            STATE.allocator,
            STATE.otio_root.space_node(.presentation)
        );
    }

    if (IS_WASM == false) parent_prog.end();

    app_wrapper.sokol_main(
        .{
            .title = (
                "OTIO Space Visualizer | " 
                ++ build_options.hash[0..6]
            ),
            .draw = draw, 
            .maybe_pre_zgui_shutdown_cleanup = cleanup,
            .maybe_post_zgui_init = init,
        },
    );
}

/// Usage message for argument parsing.
pub fn usage(
    msg: []const u8,
) void
{
    std.debug.print(
        \\
        \\Visualize the temporal spaces in an OpenTimelineIO file.
        \\
        \\usage:
        \\  otio_space_visualizer path/to/somefile.otio
        \\  otio_space_visualizer path/to/somefile.tla
        \\
        \\arguments:
        \\  -h --help: print this message and exit
        \\
        \\Supported formats:
        \\  .otio  - OpenTimelineIO JSON format
        \\  .tla   - TLA (Timeline ASCII) text format
        \\  .tlb   - Binary CBOR format
        \\  .tlfb  - Binary FlatBuffers format
        \\  .tlz   - TLZ bundle (ZIP archive)
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
    input_otio: []const u8, 
}
{
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    var input_otio_fpath:[]const u8 = undefined;
    var output_png_fpath:[]const u8 = undefined;

    // ignore the app name, always first in args
    _ = args.skip();

    var arg_count: usize = 0;

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
        
        switch (arg_count) {
            1 => {
                input_otio_fpath = try allocator.dupe(u8, fpath);
            },
            2 => {
                output_png_fpath = try allocator.dupe(u8, fpath);
            },
            else => {
                usage("Too many arguments.");
            },
        }
    }

    if (arg_count < 1) {
        usage("Not enough arguments.");
    }

    return .{
        .input_otio = input_otio_fpath,
    };
}
