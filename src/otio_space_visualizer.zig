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
const topology = @import("topology");
const treecode = @import("treecode");

/// State container
const STATE = struct {
    var demo_window_gui = false;
    var demo_window_plot = false;

    var maybe_journal : ?ziis.undo.Journal = null;

    var allocator: std.mem.Allocator = undefined;
    var debug_allocator: std.heap.DebugAllocator(.{}) = undefined;

    var target_otio_file: []const u8 = undefined;
    var otio_root: otio.ComposedValueRef = undefined;
    var maybe_current_selected_object: ?otio.ComposedValueRef = null;
    var maybe_cached_topology: ?topology.Topology = null;

    var maybe_src: ?otio.references.SpaceReference = null;
    var maybe_dst: ?otio.references.SpaceReference = null;
    var maybe_transform: ?topology.Topology = null;
    var maybe_proj_builder: ?otio.TemporalProjectionBuilder = null;

    var xs:[1024 * 10]f32 = undefined;
    var ys:[1024 * 10]f32 = undefined;

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
    var discrete_points: std.MultiArrayList(PlotPoint2d) = .empty;

    var maybe_cut_points: ?[]f32 = null;

    var maybe_hovered_interval: ?usize = null;

    // a depth first list of all the nodes in the tree
    var table_data: std.MultiArrayList(
        struct{
            name: []const u8,
            depth: usize,
            ref: *const otio.references.SpaceReference,
            // spaces: SpacesBitMask,
            code: *treecode.Treecode,
        }
    ) = .empty;

    var otio_src_json:[]const u8 = undefined;

    var options: struct {
        show_discrete_ouput_spaces: enum (u4) {
            never,
            hovered,
            always,
        } = .always,
    } = .{};
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
                ++ " not supported."
            ),
        }
    }
}

fn parent_path(
    allocator: std.mem.Allocator,
    builder: otio.TemporalProjectionBuilder,
    destination: otio.references.SpaceReference,
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

    var last_ref: otio.ComposedValueRef = undefined;

    var buf: std.ArrayList(u8) = .empty;
    var writer = buf.writer(allocator);

    for (path)
        |node_index|
    {
        const current_node_ref = builder.tree.nodes.items(.ref)[node_index];
        if (std.meta.eql(destination.ref, current_node_ref))
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
    src: otio.references.SpaceReference
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
    var discrete_points = &STATE.discrete_points;
    const cut_points = &STATE.maybe_cut_points;

    // clear whatever is there
    points.deinit(allocator);
    discrete_points.deinit(allocator);

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
    discrete_points.* = .empty;
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
            //         .ref = (
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
                        ).SuccessOrdinate,
                        aff.project_instantaneous_cc_assume_in_bounds(
                            ib.end,
                        ).SuccessOrdinate,
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

                    if (dst.discrete_info())
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
                                    .y = mapping.project_instantaneous_cc_assume_in_bounds(current).SuccessOrdinate.as(f32),
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
                        },
                    );

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

                    if (dst.discrete_info())
                        |discrete_space|
                    {
                        discrete_indices = .{ points.len, points.len };
                        // make a discrete space over the continuous one
                        const ib = mapping.input_bounds();
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
                                    .y = mapping.project_instantaneous_cc_assume_in_bounds(current).SuccessOrdinate.as(f32),
                                }
                            );
                        }

                        discrete_indices.?[1] = points.len;
                    }


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
                        },
                    );
                },
                else => {
                },
            }
        }
    }

    cut_points.*.?[builder.intervals.len] = builder.input_bounds().end.as(f32);
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
    if (STATE.maybe_src.?.discrete_info())
        |discrete_info|
    {
        const buffer_length = discrete_info.buffer_size_for_length(
            builder.input_bounds().duration()
        );

        try STATE.discrete_points.ensureTotalCapacity(
            allocator, 
            // two points per index to create horizontal line
            2 * buffer_length,
        );

        for (discrete_info.start_index.. (discrete_info.start_index + buffer_length))
            |index|
        {
            const ord = discrete_info.ord_interval_for_index(index);

            STATE.discrete_points.appendAssumeCapacity(
                .{
                    .x = ord.start.as(f32),
                    .y = ord.start.as(f32),
                }
            );
            STATE.discrete_points.appendAssumeCapacity(
                .{
                    .x = ord.end.as(f32),
                    .y = ord.start.as(f32),
                }
            );
        }
    }

    if (STATE.slices.len > 100)
    {
        STATE.options.show_discrete_ouput_spaces = .never;
    }
}

fn draw_hover_extras(
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

            if (proj_result == .OutOfBounds)
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
            ).SuccessOrdinate;

            const dest_ind_d = (
                if (dest.discrete_info()) |_|
                    try projection_operator.project_instantaneous_cd(
                        source_ord
                    )
                else null
            );

            try active_media.append(
                STATE.allocator,
                try std.fmt.allocPrint(
                    STATE.allocator,
                    "{f}: {d:0.2}s / d: {?d}",
                    .{
                        dest,
                        dest_time.as(f32),
                        dest_ind_d,
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

            if (dest.discrete_info())
                |_|
            {
                const dest_time_discrete = (
                    try projection_operator.project_instantaneous_cd(
                        source_ord
                    )
                );
                var xs: [1]f64 = .{ mouse_pos[0] };
                var ys: [1]f64 = .{ @floatFromInt(dest_time_discrete) }; 
                zplot.plotScatter(
                    "Projected Point (Discrete)",
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
            .{lbl}
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
    ref: otio.ComposedValueRef,
) ![]const u8
{
    return try std.fmt.bufPrintZ(
        buf,
        "{s}.{?s}",
        .{ @tagName(ref), ref.name() }
    );

}

fn child_tree(
    allocator: std.mem.Allocator,
    children: []otio.ComposedValueRef,
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

/// draw the UI
fn draw(
) !void 
{
    const vp = zgui.getMainViewport();
    const size = vp.getSize();

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
                    b.intervals.len 
                else 0
            );

            if (
                zgui.beginTabItem("Interval Spreadsheet", .{})
                and zgui.beginTable(
                    "IntervalTable",
                    .{
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
                
                zgui.textUnformatted(STATE.otio_src_json);
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

                                const ib = builder.input_bounds();
                                xs[0] = 0;
                                xs[1] = ib.duration().as(f32);

                                ys[0] = ib.start.as(f32);
                                ys[1] = ib.end.as(f32);

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
                                        .flags = .{ 
                                            .shaded = true, 
                                        },
                                    },
                                );
                                zplot.popStyleVar(.{ .count = 1 });
                            }

                            // plot each child space
                            const slices = STATE.slices.slice();
                            zplot.pushStyleVar1f(
                                .{
                                    .idx = .fill_alpha,
                                    .v = 0.2,
                                },
                            );

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
                                    zplot.popStyleVar(.{ .count = 1 });
                                }
                            }
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
                                try draw_hover_extras(builder);
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
                                var current_x = builder.input_bounds().start;
                                var current_y:opentime.Ordinate = .ZERO;
                                const inc = builder.input_bounds().duration().div(
                                    @as(f32, @floatFromInt(NUM_POINTS))
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
                                var current_x = xform.input_bounds().start;
                                const inc = xform.input_bounds().duration().div(
                                    @as(f32, @floatFromInt(NUM_POINTS))
                                );
                                zgui.text("Inc: {f}", .{ inc });

                                for (&xs, &ys)
                                    |*x, *y|
                                {
                                    x.* = current_x.as(f32);
                                    y.* = (
                                        xform.project_instantaneous_cc_assume_in_bounds(
                                            current_x,
                                        ).SuccessOrdinate.as(f32)
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
    if (STATE.maybe_journal)
        |*definitely_journal|
    {
        definitely_journal.deinit();
    }

    var points = &STATE.points;
    var slices = &STATE.slices;
    var discrete_points = &STATE.discrete_points;
    const cut_points = &STATE.maybe_cut_points;

    // clear whatever is there
    points.deinit(STATE.allocator);
    discrete_points.deinit(STATE.allocator);

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

    STATE.otio_root.recursively_deinit(STATE.allocator);
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
        STATE.otio_root = try otio.read_from_file(
            STATE.allocator,
            STATE.target_otio_file,
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
                1024*1024,
            );
        }

        try set_source(
            STATE.allocator,
            STATE.otio_root.space(.presentation)
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
