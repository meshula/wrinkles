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
const timeline_widget = @import("timeline_widget");
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
    var io: std.Io = undefined;

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
        playhead: f32 = 0.0,  // Playhead position in seconds
        start: f32 = 0.0,  // Timeline start time in seconds
        duration: f32 = 10.0,  // Timeline duration in seconds
        inspector_width: f32 = 200.0,  // Inspector panel width (resizable)
    } = .{};

    /// Widget state for the Gantt-chart timeline renderer.
    var tl_widget_state: timeline_widget.State = .{
        .scale = 100.0,
        .track_height = 30.0,
        .label_width = 80.0,
    };
};


/// Track kind enum for display purposes
const TrackKind = enum {
    video,
    audio,

    /// Determine track kind from a track handle by checking:
    /// 1. Track name (if contains "audio" case-insensitive)
    /// 2. First clip's media domain (audio vs picture)
    fn from_track(
        allocator: std.mem.Allocator,
        track_handle: otio.CompositionItemHandle,
    ) TrackKind {
        const track_ptr = switch (track_handle) {
            .track => |t| t,
            else => return .video,
        };

        // First check track name
        if (from_name(if (track_ptr.name.len > 0) track_ptr.name else null) == .audio) {
            return .audio;
        }

        // Check first clip's media domain
        const children = track_handle.children_refs(allocator) catch return .video;
        defer allocator.free(children);

        for (children) |child| {
            switch (child) {
                .clip => |clip_ptr| {
                    switch (clip_ptr.media.domain) {
                        .audio => return .audio,
                        else => return .video,
                    }
                },
                else => {},
            }
        }

        return .video;
    }

    fn from_name(name: ?[]const u8) TrackKind {
        if (name) |n| {
            // Check if name contains "audio" (case-insensitive)
            if (n.len >= 5) {
                var i: usize = 0;
                while (i + 4 < n.len) : (i += 1) {
                    if (std.ascii.toLower(n[i]) == 'a' and
                        std.ascii.toLower(n[i + 1]) == 'u' and
                        std.ascii.toLower(n[i + 2]) == 'd' and
                        std.ascii.toLower(n[i + 3]) == 'i' and
                        std.ascii.toLower(n[i + 4]) == 'o')
                    {
                        return .audio;
                    }
                }
            }
        }
        return .video;
    }

    fn prefix(self: TrackKind) u8 {
        return switch (self) {
            .video => 'V',
            .audio => 'A',
        };
    }
};

/// Results of categorizing tracks from an OTIO timeline
const CategorizedTracks = struct {
    video_tracks: std.ArrayListUnmanaged(otio.CompositionItemHandle),
    audio_tracks: std.ArrayListUnmanaged(otio.CompositionItemHandle),

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.video_tracks.deinit(allocator);
        self.audio_tracks.deinit(allocator);
    }
};

/// Collect and categorize tracks from the OTIO root into video and audio groups.
/// Video tracks are collected in visual order (first track in file = bottom visually).
/// Audio tracks are collected in file order.
fn categorize_tracks(
    allocator: std.mem.Allocator,
    root: otio.CompositionItemHandle,
) !CategorizedTracks {
    var video_tracks: std.ArrayListUnmanaged(otio.CompositionItemHandle) = .empty;
    var audio_tracks: std.ArrayListUnmanaged(otio.CompositionItemHandle) = .empty;

    const root_children = try root.children_refs(allocator);
    defer allocator.free(root_children);

    for (root_children) |child| {
        switch (child) {
            .track => {
                const kind = TrackKind.from_track(allocator, child);
                if (kind == .audio) {
                    try audio_tracks.append(allocator, child);
                } else {
                    try video_tracks.append(allocator, child);
                }
            },
            .stack => {
                const stack_children = try child.children_refs(allocator);
                defer allocator.free(stack_children);
                for (stack_children) |stack_child| {
                    switch (stack_child) {
                        .track => {
                            const kind = TrackKind.from_track(allocator, stack_child);
                            if (kind == .audio) {
                                try audio_tracks.append(allocator, stack_child);
                            } else {
                                try video_tracks.append(allocator, stack_child);
                            }
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    return .{
        .video_tracks = video_tracks,
        .audio_tracks = audio_tracks,
    };
}

/// Generate track labels for display.
/// Video tracks: V<n> where n counts down from total video tracks (top=highest, bottom=1)
/// Audio tracks: A<n> where n counts up from 1 (top=1, bottom=highest)
const TrackLabel = struct {
    prefix: u8,
    number: usize,
    name: ?[]const u8,

    fn format(
        self: @This(),
        buf: []u8,
    ) []const u8 {
        return std.fmt.bufPrint(
            buf,
            "{c}{d}: {s}",
            .{ self.prefix, self.number, self.name orelse "" },
        ) catch "?";
    }
};

/// Get the display label for a video track at the given visual row.
/// row 0 = topmost video track = highest number (e.g., V4)
/// row n-1 = bottommost video track = V1
fn video_track_label(
    row: usize,
    total_video_tracks: usize,
    track_name: ?[]const u8,
) TrackLabel {
    // row 0 -> V<total>, row 1 -> V<total-1>, ... row n-1 -> V1
    return .{
        .prefix = 'V',
        .number = total_video_tracks - row,
        .name = track_name,
    };
}

/// Get the display label for an audio track at the given visual row.
/// row 0 = topmost audio track = A1
fn audio_track_label(
    row: usize,
    track_name: ?[]const u8,
) TrackLabel {
    return .{
        .prefix = 'A',
        .number = row + 1,
        .name = track_name,
    };
}


fn struct_editor_ui(
    comptime T: type,
    thing: *T,
) !void
{
    inline for (std.meta.fields(T))
        |field|
    {
        switch (@typeInfo(field.type)) {
            .@"enum" => {
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
   
    var allocating_writer =  std.Io.Writer.Allocating.init(allocator);

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
        try allocating_writer.writer.print("{f}/", .{last_ref});
    }

    try allocating_writer.writer.print("{f}", .{ destination });

    return try allocating_writer.toOwnedSlice();
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
                @intCast(2 * buffer_length),
            );

            const start_ind: usize = @intCast(discrete_info.start_index);

            for (start_ind .. start_ind + buffer_length)
                |index|
            {
                const ord = (
                    discrete_info.ord_interval_for_index(@intCast(index))
                );

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
                        .line_weight = 4.0,
                        .marker_size = 4.0,
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
                        .line_weight = 4.0,
                        .marker_size = 4.0,
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
                        .line_weight = 4.0,
                        .marker_size = 4.0,
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

/// Draw inspector tab content for selected object
fn draw_inspector_tab() void {
    if (STATE.maybe_current_selected_object) |selected| {
        // Name
        zgui.text("Name", .{});
        zgui.sameLine(.{ .offset_from_start_x = 100 });
        zgui.text("{s}", .{selected.name() orelse "(unnamed)"});

        zgui.spacing();

        // Schema (type)
        zgui.text("Schema", .{});
        zgui.sameLine(.{ .offset_from_start_x = 100 });
        zgui.text("{s}", .{@tagName(selected)});

        zgui.spacing();
        zgui.separatorText("Trimmed Range");

        // Try to get bounds
        if (selected.bounds_of(STATE.allocator, .presentation)) |bounds| {
            var tc_buf1: [16]u8 = undefined;
            var tc_buf2: [16]u8 = undefined;
            var tc_buf3: [16]u8 = undefined;

            zgui.text("Start", .{});
            zgui.sameLine(.{ .offset_from_start_x = 100 });
            zgui.text("{s}", .{format_timecode(&tc_buf1, bounds.start.as(f32))});

            zgui.text("Duration", .{});
            zgui.sameLine(.{ .offset_from_start_x = 100 });
            zgui.text("{s}", .{format_timecode(&tc_buf2, bounds.duration().as(f32))});

            zgui.text("End", .{});
            zgui.sameLine(.{ .offset_from_start_x = 100 });
            zgui.text("{s}", .{format_timecode(&tc_buf3, bounds.end.as(f32))});
        } else |_| {
            zgui.text("(no bounds)", .{});
        }
    } else {
        zgui.textDisabled("No selection", .{});
    }
}

/// Draw JSON tab content - shows raw OTIO JSON for selected object
fn draw_json_tab() void {
    if (STATE.maybe_current_selected_object) |selected| {
        // Show the tag name and item details
        zgui.text("{s}", .{@tagName(selected)});
        if (selected.name()) |name| {
            zgui.text("name: \"{s}\"", .{name});
        }
        // TODO: Add actual JSON serialization of the selected object
        zgui.textDisabled("(Full JSON serialization not yet implemented)", .{});
    } else {
        zgui.textDisabled("No selection", .{});
    }
}

/// Draw Markers tab content - shows markers on selected object
fn draw_markers_tab() void {
    if (STATE.maybe_current_selected_object) |selected| {
        // TODO: Add marker support when CompositionItemHandle gains markers() API
        zgui.text("Selected: {s}", .{@tagName(selected)});
        zgui.textDisabled("(Marker listing not yet implemented)", .{});
    } else {
        zgui.textDisabled("No selection", .{});
    }
}

/// Draw Settings tab content - timeline display settings
fn draw_settings_tab() void {
    zgui.separatorText("Timeline Display");

    zgui.text("Track Height", .{});
    zgui.sameLine(.{ .offset_from_start_x = 100 });
    zgui.setNextItemWidth(80);
    _ = zgui.sliderFloat(
        "##TrackHeight",
        .{
            .v = &STATE.tl_widget_state.track_height,
            .min = 20.0,
            .max = 60.0,
            .cfmt = "%.0f px",
        },
    );

    zgui.text("Zoom", .{});
    zgui.sameLine(.{ .offset_from_start_x = 100 });
    zgui.setNextItemWidth(80);
    _ = zgui.sliderFloat(
        "##ZoomSetting",
        .{
            .v = &STATE.tl_widget_state.scale,
            .min = 10.0,
            .max = 500.0,
            .cfmt = "%.0f",
            .flags = .{ .logarithmic = true },
        },
    );
}

/// Draw the complete inspector panel with tabs
fn draw_inspector_panel(_: std.mem.Allocator) void {
    if (zgui.beginTabBar("InspectorTabs", .{})) {
        defer zgui.endTabBar();

        if (zgui.beginTabItem("Inspector", .{})) {
            defer zgui.endTabItem();
            draw_inspector_tab();
        }

        if (zgui.beginTabItem("JSON", .{})) {
            defer zgui.endTabItem();
            draw_json_tab();
        }

        if (zgui.beginTabItem("Markers", .{})) {
            defer zgui.endTabItem();
            draw_markers_tab();
        }

        if (zgui.beginTabItem("Settings", .{})) {
            defer zgui.endTabItem();
            draw_settings_tab();
        }
    }
}

/// Draw the timeline view tab content
fn draw_timeline_tab(
    allocator: std.mem.Allocator,
) !void
{
    // Update timeline duration from the loaded OTIO
    if (STATE.maybe_proj_builder) |builder|
    {
        if (builder.input_bounds()) |bounds|
        {
            STATE.timeline.start = bounds.start.as(f32);
            STATE.timeline.duration = bounds.duration().as(f32);
        }
    }

    const splitter_width: f32 = 8.0;
    const min_inspector_width: f32 = 150.0;
    const max_inspector_width: f32 = 400.0;

    const avail = zgui.getContentRegionAvail();
    const timeline_area_width = avail[0] - STATE.timeline.inspector_width - splitter_width;

    // ── Build widget tracks from OTIO ──
    var categorized = try categorize_tracks(allocator, STATE.otio_root);
    defer categorized.deinit(allocator);

    const video_tracks = categorized.video_tracks.items;
    const audio_tracks = categorized.audio_tracks.items;

    // Collect widget tracks + item data.
    // We store handles alongside so we can map clicks back to OTIO objects.
    const MAX_TRACKS = 64;
    const MAX_ITEMS = 256;
    var widget_tracks_buf: [MAX_TRACKS]timeline_widget.Track = undefined;
    var items_bufs: [MAX_TRACKS][MAX_ITEMS]timeline_widget.Item = undefined;
    // Parallel array mapping widget track index → OTIO track handle.
    var track_handles: [MAX_TRACKS]otio.CompositionItemHandle = undefined;
    // Parallel array mapping (track, item) → OTIO child handle.
    var item_handles: [MAX_TRACKS][MAX_ITEMS]otio.CompositionItemHandle = undefined;

    var wt_count: usize = 0;

    // Video tracks (reversed so highest number is at the top)
    {
        const total_video = video_tracks.len;
        var vid_idx: usize = video_tracks.len;
        while (vid_idx > 0)
        {
            vid_idx -= 1;
            const child = video_tracks[vid_idx];
            if (wt_count >= MAX_TRACKS) break;
            switch (child)
            {
                .track => |track_ptr|
                {
                    var label_buf: [64]u8 = undefined;
                    const label = video_track_label(
                        total_video - 1 - vid_idx,
                        total_video,
                        if (track_ptr.name.len > 0) track_ptr.name else null,
                    );
                    const track_label_str = label.format(&label_buf);

                    const children = child.children_refs(allocator) catch continue;
                    defer allocator.free(children);

                    var current_time: f32 = 0.0;
                    var item_count: usize = 0;

                    for (children)
                        |otio_child|
                    {
                        if (item_count >= MAX_ITEMS) break;
                        const bounds = otio_child.bounds_of(
                            allocator,
                            .presentation,
                        ) catch null;
                        const dur: f32 = if (bounds) |b| b.duration().as(f32) else 1.0;

                        const is_gap = otio_child == .gap;
                        items_bufs[wt_count][item_count] = .{
                            .name = otio_child.name() orelse "",
                            .start_time = current_time,
                            .duration = dur,
                            .maybe_color = if (is_gap) @as(?u32, 0xFF1E1E1E) else null,
                        };
                        item_handles[wt_count][item_count] = otio_child;
                        item_count += 1;
                        current_time += dur;
                    }

                    track_handles[wt_count] = child;
                    widget_tracks_buf[wt_count] = .{
                        .label = track_label_str,
                        .items = items_bufs[wt_count][0..item_count],
                        .maybe_color = 0xFF355535, // video green
                    };
                    wt_count += 1;
                },
                else => {},
            }
        }
    }

    // Audio tracks (in order)
    for (audio_tracks, 0..)
        |child, aud_idx|
    {
        if (wt_count >= MAX_TRACKS) break;
        switch (child)
        {
            .track => |track_ptr|
            {
                var label_buf: [64]u8 = undefined;
                const label = audio_track_label(
                    aud_idx,
                    if (track_ptr.name.len > 0) track_ptr.name else null,
                );
                const track_label_str = label.format(&label_buf);

                const children = child.children_refs(allocator) catch continue;
                defer allocator.free(children);

                var current_time: f32 = 0.0;
                var item_count: usize = 0;

                for (children)
                    |otio_child|
                {
                    if (item_count >= MAX_ITEMS) break;
                    const bounds = otio_child.bounds_of(
                        allocator,
                        .presentation,
                    ) catch null;
                    const dur: f32 = if (bounds) |b| b.duration().as(f32) else 1.0;

                    const is_gap = otio_child == .gap;
                    items_bufs[wt_count][item_count] = .{
                        .name = otio_child.name() orelse "",
                        .start_time = current_time,
                        .duration = dur,
                        .maybe_color = if (is_gap) @as(?u32, 0xFF1E1E1E) else null,
                    };
                    item_handles[wt_count][item_count] = otio_child;
                    item_count += 1;
                    current_time += dur;
                }

                track_handles[wt_count] = child;
                widget_tracks_buf[wt_count] = .{
                    .label = track_label_str,
                    .items = items_bufs[wt_count][0..item_count],
                    .maybe_color = 0xFF3A3A5A, // audio blue
                };
                wt_count += 1;
            },
            else => {},
        }
    }

    // ── Timeline area (left) ──
    if (zgui.beginChild(
        "TimelineArea",
        .{
            .w = timeline_area_width,
            .h = avail[1],
        },
    ))
    {
        defer zgui.endChild();

        const maybe_cursor: ?f32 = if (STATE.timeline.playhead > 0)
            STATE.timeline.playhead - STATE.timeline.start
        else
            null;

        const widget_result = timeline_widget.draw(
            &STATE.tl_widget_state,
            .{
                .tracks = widget_tracks_buf[0..wt_count],
                .total_duration = STATE.timeline.duration,
                .maybe_cursor_time = maybe_cursor,
            },
        );

        // Map widget click back to OTIO selection
        if (widget_result.maybe_clicked_item) |clicked|
        {
            if (clicked.track_idx < wt_count and
                clicked.item_idx < widget_tracks_buf[clicked.track_idx].items.len)
            {
                STATE.maybe_current_selected_object =
                    item_handles[clicked.track_idx][clicked.item_idx];
            }
        }
        else if (widget_result.maybe_clicked_track) |track_idx|
        {
            if (track_idx < wt_count)
            {
                STATE.maybe_current_selected_object = track_handles[track_idx];
            }
        }
    }

    zgui.sameLine(.{});

    // ── Splitter ──
    {
        const cursor_pos = zgui.getCursorScreenPos();
        const draw_list = zgui.getWindowDrawList();

        const splitter_color: u32 = 0xFF3A3A3A;
        const splitter_hover_color: u32 = 0xFF5A5A5A;

        _ = zgui.invisibleButton(
            "##TimelineInspectorSplitter",
            .{ .w = splitter_width, .h = avail[1] },
        );

        const is_splitter_hovered = zgui.isItemHovered(.{});
        const is_splitter_active = zgui.isItemActive();

        draw_list.addRectFilled(.{
            .pmin = cursor_pos,
            .pmax = .{
                cursor_pos[0] + splitter_width,
                cursor_pos[1] + avail[1],
            },
            .col = if (is_splitter_hovered or is_splitter_active)
                splitter_hover_color
            else
                splitter_color,
        });

        if (is_splitter_active)
        {
            const mouse_delta = zgui.getMouseDragDelta(.left, .{});
            if (mouse_delta[0] != 0)
            {
                STATE.timeline.inspector_width = @max(
                    min_inspector_width,
                    @min(
                        max_inspector_width,
                        STATE.timeline.inspector_width - mouse_delta[0],
                    ),
                );
                zgui.resetMouseDragDelta(.left);
            }
        }

        if (is_splitter_hovered or is_splitter_active)
        {
            zgui.setMouseCursor(.resize_ew);
        }
    }

    zgui.sameLine(.{});

    // ── Inspector panel (right) ──
    if (zgui.beginChild(
        "InspectorPanel",
        .{
            .w = STATE.timeline.inspector_width,
            .h = avail[1],
            .child_flags = .{ .border = true },
        },
    ))
    {
        defer zgui.endChild();
        draw_inspector_panel(allocator);
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
                try app_wrapper.fetch_resource(
                    STATE.allocator,
                    STATE.target_otio_file, 
                    .{
                        // if there is compression, handle it in the OTIO layer
                        .compression = .auto_detect,
                    },
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

                // @TODO: this should only display when ascii data is loaded
                zgui.textUnformatted(
                    STATE.maybe_file_read_query.?.result_data_buffer,
                );
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

                                zplot.plotLine(
                                    plotlabel,
                                    f32, 
                                    .{
                                        .xv = &xs,
                                        .yv = &ys,
                                        .fill_alpha = 0.4,
                                        .flags = .{ 
                                            .shaded = true, 
                                        },
                                    },
                                );
                            }

                            inline for (&[_][]const u8{ "picture", "audio" })
                                |field|
                            {
                                if (@field(STATE.discrete_points, field))
                                    |discrete|
                                {
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
                                            .fill_alpha = 0.4,
                                            .flags = .{ 
                                                .shaded = true, 
                                            },
                                        },
                                    );
                                }
                            }

                            // plot each child space
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

                                zplot.plotLine(
                                    label,
                                    f32, 
                                    .{
                                        .xv = xs,
                                        .yv = ys,
                                        .line_weight = if (hovered_interval) 4 else 1,
                                        .fill_alpha = if (hovered_interval) 0.2 else 0.1,
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
                                                .line_weight = if (hovered_interval) 4 else 1,
                                                .fill_alpha = if (hovered_interval) 0.2 else 0.1,
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
                            zplot.popStyleVar(.{ .count = 1 });

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
                                zplot.plotLine(
                                    plotlabel,
                                    f32,
                                    .{
                                        .xv = &xs,
                                        .yv = &ys,
                                        .fill_alpha = 0.4,
                                        .flags = .{
                                            .shaded = true
                                        },
                                    },
                                );
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
        query.deinit();
        allocator.destroy(query);
    }

    if (STATE.maybe_journal)
        |*definitely_journal|
    {
        definitely_journal.deinit(STATE.allocator, STATE.io);
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
    juicy_init: std.process.Init,
) !void 
{
    // configure the allocator
    STATE.allocator = juicy_init.gpa;
    const io = juicy_init.io;
    STATE.io = io;

    const prog = (
        if (IS_WASM == false) std.Progress.start(io, .{})
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

        STATE.target_otio_file = (try _parse_args(STATE.allocator, juicy_init.minimal.args)).input_otio;
        var found = true;

        std.debug.print("attempting fetch\n", .{});
        std.Io.Dir.cwd().access(
            io,
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

        // Read timeline file - supports .otio, .tla, .tlb, .tlz
        // Skip metadata for faster visualization
        STATE.otio_root = try otio.read_from_file(
            STATE.allocator,
            io,
            STATE.target_otio_file,
            .{ .content_filter = .all_except_metadata },
        );

        // read the file contents
        {
            const file = try std.Io.Dir.cwd().openFile(
                io,
                STATE.target_otio_file,
                .{},
            );
            defer file.close(io);

            var file_reader = file.reader(io, &.{});
            STATE.otio_src_json = try file_reader.interface.allocRemaining(
                STATE.allocator,
                .limited(1024*1024*1024),
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
        \\  .tlb   - Binary FlatBuffers based format
        \\  .tlz   - TLZ bundle (ZIP archive)
        \\
        \\Note:
        \\  .tlc   - (Container) formats are not supported presently (TODO)
        \\
        \\{s}
        \\
        , .{msg}
    );
    std.process.exit(1);
}

fn _parse_args(
    allocator: std.mem.Allocator,
    args: std.process.Args,
) !struct {
    input_otio: []const u8, 
}
{
    var arg_iter = args.iterate();

    var input_otio_fpath:[]const u8 = undefined;
    var output_png_fpath:[]const u8 = undefined;

    // ignore the app name, always first in args
    _ = arg_iter.skip();

    var arg_count: usize = 0;

    // read all the filepaths from the commandline
    while (arg_iter.next()) 
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

// ============================================================================
// Unit Tests
// ============================================================================

test "TrackKind.from_name: audio track detection" {
    // Tracks with "audio" in the name should be detected as audio
    try std.testing.expectEqual(TrackKind.audio, TrackKind.from_name("Audio"));
    try std.testing.expectEqual(TrackKind.audio, TrackKind.from_name("audio"));
    try std.testing.expectEqual(TrackKind.audio, TrackKind.from_name("AUDIO"));
    try std.testing.expectEqual(TrackKind.audio, TrackKind.from_name("Audio Track 1"));
    try std.testing.expectEqual(TrackKind.audio, TrackKind.from_name("My Audio"));

    // Tracks without "audio" should be video
    try std.testing.expectEqual(TrackKind.video, TrackKind.from_name("Video"));
    try std.testing.expectEqual(TrackKind.video, TrackKind.from_name("Track-001"));
    try std.testing.expectEqual(TrackKind.video, TrackKind.from_name("Sequence"));
    try std.testing.expectEqual(TrackKind.video, TrackKind.from_name(null));
    try std.testing.expectEqual(TrackKind.video, TrackKind.from_name(""));
    try std.testing.expectEqual(TrackKind.video, TrackKind.from_name("aud")); // too short
}

test "video_track_label: correct numbering for display" {
    // With 4 video tracks, from top to bottom: V4, V3, V2, V1
    const total = 4;

    // Row 0 (top) = V4
    const label0 = video_track_label(0, total, "Track A");
    try std.testing.expectEqual(@as(u8, 'V'), label0.prefix);
    try std.testing.expectEqual(@as(usize, 4), label0.number);

    // Row 1 = V3
    const label1 = video_track_label(1, total, "Track B");
    try std.testing.expectEqual(@as(u8, 'V'), label1.prefix);
    try std.testing.expectEqual(@as(usize, 3), label1.number);

    // Row 2 = V2
    const label2 = video_track_label(2, total, "Track C");
    try std.testing.expectEqual(@as(u8, 'V'), label2.prefix);
    try std.testing.expectEqual(@as(usize, 2), label2.number);

    // Row 3 (bottom of video section) = V1
    const label3 = video_track_label(3, total, "Track D");
    try std.testing.expectEqual(@as(u8, 'V'), label3.prefix);
    try std.testing.expectEqual(@as(usize, 1), label3.number);
}

test "audio_track_label: correct numbering for display" {
    // Audio tracks go A1, A2, A3, A4 from top to bottom
    const label0 = audio_track_label(0, "Audio 1");
    try std.testing.expectEqual(@as(u8, 'A'), label0.prefix);
    try std.testing.expectEqual(@as(usize, 1), label0.number);

    const label1 = audio_track_label(1, "Audio 2");
    try std.testing.expectEqual(@as(u8, 'A'), label1.prefix);
    try std.testing.expectEqual(@as(usize, 2), label1.number);

    const label3 = audio_track_label(3, null);
    try std.testing.expectEqual(@as(u8, 'A'), label3.prefix);
    try std.testing.expectEqual(@as(usize, 4), label3.number);
}

test "TrackLabel.format: generates correct string" {
    var buf: [64]u8 = undefined;

    const video_label = TrackLabel{ .prefix = 'V', .number = 4, .name = "MyTrack" };
    const video_str = video_label.format(&buf);
    try std.testing.expectEqualStrings("V4: MyTrack", video_str);

    const audio_label = TrackLabel{ .prefix = 'A', .number = 1, .name = null };
    const audio_str = audio_label.format(&buf);
    try std.testing.expectEqualStrings("A1: ", audio_str);
}

test "categorize_tracks: loads and categorizes multiple_track.tla" {
    const allocator = std.testing.allocator;

    // Load the test file
    const root = try otio.read_from_file(
        allocator,
        "otio_sample_data/multiple_track.tla",
        .{ .content_filter = .all_except_metadata },
    );
    defer {
        var r = root;
        r.deinit(allocator);
    }

    var categorized = try categorize_tracks(allocator, root);
    defer categorized.deinit(allocator);

    // multiple_track.tla has 3 video tracks (Track-001, Track-002, Track-003)
    // and 0 audio tracks
    try std.testing.expectEqual(@as(usize, 3), categorized.video_tracks.items.len);
    try std.testing.expectEqual(@as(usize, 0), categorized.audio_tracks.items.len);

    // Check labels - from top to bottom: V3, V2, V1
    // Video tracks are displayed with highest number at top
    const total_video = categorized.video_tracks.items.len;
    for (categorized.video_tracks.items, 0..) |track, row| {
        const label = video_track_label(row, total_video, track.name());
        const expected_number = total_video - row; // 3, 2, 1
        try std.testing.expectEqual(expected_number, label.number);
    }
}

test "categorize_tracks: loads and categorizes mixed_tracks.tla" {
    const allocator = std.testing.allocator;

    // Load the test file with 4 video + 4 audio tracks
    const root = try otio.read_from_file(
        allocator,
        "otio_sample_data/mixed_tracks.tla",
        .{ .content_filter = .all_except_metadata },
    );
    defer {
        var r = root;
        r.deinit(allocator);
    }

    var categorized = try categorize_tracks(allocator, root);
    defer categorized.deinit(allocator);

    // mixed_tracks.tla has 4 video tracks and 4 audio tracks
    try std.testing.expectEqual(@as(usize, 4), categorized.video_tracks.items.len);
    try std.testing.expectEqual(@as(usize, 4), categorized.audio_tracks.items.len);

    // Video tracks: V4, V3, V2, V1 from top to bottom (reverse order for display)
    const total_video = categorized.video_tracks.items.len;
    for (categorized.video_tracks.items, 0..) |_, row| {
        const label = video_track_label(row, total_video, null);
        const expected_number = total_video - row; // 4, 3, 2, 1
        try std.testing.expectEqual(expected_number, label.number);
    }

    // Audio tracks: A1, A2, A3, A4 from top to bottom (normal order)
    for (0..categorized.audio_tracks.items.len) |row| {
        const label = audio_track_label(row, null);
        const expected_number = row + 1; // 1, 2, 3, 4
        try std.testing.expectEqual(expected_number, label.number);
    }
}
