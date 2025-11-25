//! example app using the app wrapper

const std = @import("std");
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

fn set_source(
    allocator: std.mem.Allocator,
    src: otio.references.SpaceReference
) !void
{
    STATE.maybe_src = src;

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

    try fill_topdown_point_buffers(
        allocator,
    );
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
        allocator.free(label);
    }
    slices.deinit(allocator);

    points.* = .empty;
    slices.* = .empty;
    discrete_points.* = .empty;
    cut_points.* = null;

    // var label_writer = label_bucket.writer(allocator);
    var allocating_label_writer = std.Io.Writer.Allocating.init(allocator);
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

    var slice_indices : std.MultiArrayList(
        struct{
            start: usize,
            end: usize,
            label: [:0]const u8,
        },
    ) = .empty;

    for (
        interval_slice.items(.mapping_index),
        interval_slice.items(.input_bounds),
        0..,
    ) |mapping_indices, input_bound, ind|
    {
        cut_points.*.?[ind] = input_bound.start.as(f32);
        for (mapping_indices)
            |mapping_ind|
        {
            const mapping = mapping_slice.items(.mapping)[mapping_ind];
            const ref_ind = mapping_slice.items(.destination)[mapping_ind];
            const dst = builder.tree.nodes.get(ref_ind);
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
                    try label_writer.print("{f}" ++ .{0}, .{ dst });
                    try slice_indices.append(
                        allocator,
                        .{
                            .start = start,
                            .end = end,
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

                    try label_writer.print("{f}" ++ .{0}, .{ dst });
                    try slice_indices.append(
                        allocator,
                        .{
                            .start = start,
                            .end = end,
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
        slice_indices.items(.label),
    )
        |start, end, label|
    {
        try slices.append(
            allocator,
            .{
                .xs = points.items(.x)[start..end],
                .ys = points.items(.y)[start..end],
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
}

/// 2d Point in a plot
const PlotPoint2d = struct{
    x: f32,
    y: f32,
};

/// State container
const STATE = struct {
    // var f: f32 = 0;
    var demo_window_gui = false;
    var demo_window_plot = false;
    // const TEX_DIM : [2]i32 = .{ 256, 256 };
    // const COLOR_CHANNELS:usize = 4;
    // var tex: sg.Image = .{};
    // var view: sg.View = .{};
    // var texid: u64 = 0;
    // var frame_number: usize = 0;
    // var buffer = std.mem.zeroes(
    //     [STATE.TEX_DIM[0]][STATE.TEX_DIM[1]][COLOR_CHANNELS]u8
    // );
    // var image_data = ziis.sokol.gfx.ImageData{};

    var maybe_journal : ?ziis.undo.Journal = null;

    var allocator: std.mem.Allocator = undefined;
    var maybe_debug_allocator: ?std.heap.DebugAllocator(.{}) = null;

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
            xs: []const f32,
            ys: []const f32,
            label: [:0]const u8,
        }
    ) = .empty;
    var discrete_points: std.MultiArrayList(PlotPoint2d) = .empty;

    var maybe_cut_points: ?[]f32 = null;
};

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
    const allocator = STATE.allocator;

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
                },
            },
        )
    )
    {
        defer zgui.end();

        const LEFT_PANEL_WIDTH = 300;

        if (
            zgui.beginChild(
                "LEFT_PANEL",
                .{
                    .w = LEFT_PANEL_WIDTH,
                    .child_flags = .{
                        .border = true,
                        .resize_x = true,
                    },
                },
            )
        )
        {
            defer zgui.endChild();

            if (
                zgui.beginChild(
                    "Object Info",
                    .{
                        .h = 180,
                    }
                )
            )
            {
                defer zgui.endChild();

                var buf2:[1024]u8 = undefined;

                zgui.text(
                    "Current Object: {s}",
                    .{
                        if (STATE.maybe_current_selected_object) |obj| (
                            try label_for_ref(&buf2, obj)
                        ) else "[Click in the tree to select an object]"
                    },
                );

                if (STATE.maybe_current_selected_object)
                    |obj|
                {
                    if (
                        zgui.beginTable(
                            "Object Details",
                            .{
                                .column = 2,
                            },
                        )
                    )
                    {
                        defer zgui.endTable();

                        // header row
                        zgui.tableNextRow(
                            .{ .row_flags = .{ .headers = true } }
                        );

                        _ = zgui.tableSetColumnIndex(0);
                        zgui.text("Key", .{});

                        _ = zgui.tableSetColumnIndex(1);
                        zgui.text("Value", .{});

                        zgui.tableNextRow(.{});

                        var buf3_s: [1024]u8 = undefined;
                        var buf3: []u8 = &buf3_s;

                        const pres_bounds = try std.fmt.bufPrint(
                            buf3,
                            "{f}",
                            .{ 
                                STATE.maybe_cached_topology.?.input_bounds(),
                            },
                        );
                        buf3 = buf3[pres_bounds.len..];

                        const pres_di = try std.fmt.bufPrint(
                            buf3,
                            "{?f}", 
                            .{ obj.discrete_info_for_space(.presentation) },
                        );
                        buf3 = buf3[pres_di.len..];

                        const rows = [_][2][]const u8{
                            .{ "Schema", @tagName(obj) },
                            .{ "Presentation Space Bounds", pres_bounds },
                            .{ "Presentation Space Discrete Info", pres_di },
                            .{ "Coordinate Spaces", "" },
                        };

                        for (&rows)
                            |row|
                        {
                            for (row, 0..)
                                |field, col|
                            {
                                _ = zgui.tableSetColumnIndex(@intCast(col));
                                zgui.text("{s}", .{ field });
                            }
                            zgui.tableNextRow(.{});
                        }

                        for (obj.spaces())
                            |space|
                        {
                            _ = zgui.tableSetColumnIndex(@intCast(0));
                            zgui.text("Space: {s}", .{@tagName(space)});

                            _ = zgui.tableSetColumnIndex(@intCast(1));

                            zgui.pushIntId(@intFromEnum(space));
                            defer zgui.popId();

                            if (zgui.button("SET SOURCE", .{}))
                            {
                                try set_source(
                                    allocator,
                                    STATE.maybe_current_selected_object.?.space(space)
                                );
                            }
                            zgui.sameLine(.{});
                            if (zgui.button("SET DEST", .{}))
                            {
                                STATE.maybe_dst = (
                                    STATE.maybe_current_selected_object.?.space(space)
                                );
                                STATE.maybe_transform = null;
                                if (STATE.maybe_proj_builder)
                                    |builder|
                                {
                                    STATE.maybe_transform = (
                                        try builder.projection_operator_to(
                                            allocator,
                                            STATE.maybe_dst.?,
                                        )
                                    ).src_to_dst_topo;
                                }
                            }
                            zgui.tableNextRow(.{});
                        }
                    }
                }
            }

            if (zgui.beginChild("Object Tree", .{}))
            {
                defer zgui.endChild();

                zgui.text("Current File: {s}", .{ STATE.target_otio_file });

                var root = [_]otio.ComposedValueRef{
                    STATE.otio_root,
                };

                try child_tree(allocator, &root );
            }
        }

        zgui.sameLine(.{});

        if (zgui.beginChild("Transform", .{}))
        {
            defer zgui.endChild();

            if (
                zgui.beginTable(
                    "Transform Info Table",
                    .{
                        .column = 2,
                        .flags = .{
                            .borders = .all,
                        },
                    },
                )
            )
            {
                defer zgui.endTable();

                zgui.tableNextRow(.{});

                _ = zgui.tableSetColumnIndex(0);
                zgui.text("Source Space: ", .{});

                _ = zgui.tableSetColumnIndex(1);

                if (STATE.maybe_src)
                    |src|
                {
                    zgui.text("{f}", .{src});
                }
                else
                {
                    zgui.text("NONE SET", .{});
                }

                zgui.tableNextRow(.{});

                _ = zgui.tableSetColumnIndex(0);
                zgui.text("Destination Space: ", .{});

                _ = zgui.tableSetColumnIndex(1);
                if (STATE.maybe_dst)
                    |dst|
                {
                    zgui.text("{f}", .{dst});
                }
                else
                {
                    zgui.text("NONE SET", .{});
                }

                zgui.tableNextRow(.{});

                _ = zgui.tableSetColumnIndex(@intCast(0));
                zgui.text("Mappings", .{});

                _ = zgui.tableSetColumnIndex(@intCast(1));
                if (STATE.maybe_transform)
                    |xform|
                {
                    zgui.text("{d}", .{xform.mappings.len});

                    zgui.tableNextRow(.{});
                    table_fill_row(&.{ "Mappings:", "" });

                    for (xform.mappings)
                        |m|
                    {
                        zgui.tableNextRow(.{});
                        var buf:[1024]u8 = undefined;
                        const m_s = try std.fmt.bufPrint(&buf, "{f}", .{m});
                        table_fill_row(&.{"", m_s});
                    }
                }
                else
                {
                    zgui.text("---", .{});
                }
            }

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

                            // @TODO: make this a control - where in the
                            //        timeline you're viewing
                            const MAX_ITEMS = @min(slices.len, 3000);
                            for (
                                slices.items(.xs)[0..MAX_ITEMS],
                                slices.items(.ys)[0..MAX_ITEMS],
                                slices.items(.label)[0..MAX_ITEMS],
                            ) |xs, ys, label|
                            {
                                // std.debug.print("plotting: {s}\n", .{label});
                                // std.debug.print("  xs: {any}\n", .{xs});
                                // std.debug.print("  ys: {any}\n", .{ys});
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
                            }
                            zplot.popStyleVar(.{ .count = 1 });

                            const max_cut_points = @min(slices.len + 1, 3000);
                            if (STATE.maybe_cut_points)
                                |cut_points|
                            {
                                zplot.plotInfLines(
                                    "Cut Points",
                                    f32,
                                    .{
                                        .v = (
                                            cut_points[0..max_cut_points] 
                                        ),
                                    },
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

    if (IS_WASM == false and builtin.mode == .Debug)
    {
        const result = STATE.maybe_debug_allocator.?.deinit();
        if (result == .leak) 
        {
            std.log.debug("leak!", .{});
        }
    }
}

pub fn init(
) void
{ 
    // STATE.tex = sg.makeImage(
    //     .{
    //         .width = STATE.TEX_DIM[0],
    //         .height = STATE.TEX_DIM[1],
    //         .usage = .{ .stream_update = true },
    //         .pixel_format = .RGBA8,
    //     },
    // );
    //
    // STATE.view = sg.makeView(
    //     .{
    //         .texture = .{
    //             .image = STATE.tex,
    //         },
    //     },
    // );
    //
    // STATE.texid = ziis.sokol.imgui.imtextureid(STATE.view);
}

pub fn main(
) !void 
{
    std.debug.print("bloop\n", .{});

    const prog = std.Progress.start(.{});
    defer prog.end();

    const parent_prog = prog.start(
        "Initializing",
        3,
    );

    {
        const init_progress = parent_prog.start(
            "Initializing State...",
            0,
        );
        defer init_progress.end();

        STATE.allocator = (
            if (builtin.mode == .Debug) alloc: {
                var da = std.heap.DebugAllocator(.{}){};
                STATE.maybe_debug_allocator = da;
                break :alloc da.allocator();
            } else std.heap.smp_allocator
        );

        STATE.maybe_journal = ziis.undo.Journal.init(
            STATE.allocator,
            5,
        ) catch null;
    }

    {
        const read_prog = parent_prog.start(
            "Reading file...",
            0,
        );
        defer read_prog.end();

        STATE.target_otio_file = (try _parse_args(STATE.allocator)).input_otio;
        var found = true;
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
        std.debug.print("bloop\n", .{});

        try set_source(
            STATE.allocator,
            STATE.otio_root.space(.presentation)
        );
    }

    parent_prog.end();

    app_wrapper.sokol_main(
        .{
            .title = "OTIO Space Visualizer",
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
) !struct { input_otio: []const u8, }
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
