const std = @import("std");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = zgui.plot;

const sokol_app_wrapper = @import("sokol_app_wrapper");

const topology = @import("topology");
const curve = @import("curve");
const opentime = @import("opentime");

const build_options = @import("build_options");
const WINDOW_TITLE = (
    "OpenTimelineIO V2 Prototype Transformation Visualizer [" 
    ++ build_options.hash[0..6] 
    ++ "]"
);

const exe_build_options = @import("exe_build_options");
const content_dir = exe_build_options.content_dir;

const PLOT_STEPS = 1000;

/// plot a bezier curve
pub fn plot_curve_bezier_segment(
    _: std.mem.Allocator,
    name: [:0]const u8,
    crv : curve.Bezier.Segment,
) !void
{
    const input_bounds_ord = crv.extents_input();
    var input_bounds : [2]f64 = .{
        input_bounds_ord.start.as(f64),
        input_bounds_ord.end.as(f64),
    };

    const plot_limits = zgui.plot.getPlotLimits(
        .x1,
        .y1
    );

    if (input_bounds_ord.start.is_inf()) {
        input_bounds[0] = plot_limits.x[0];
    }
    if (input_bounds_ord.end.is_inf()) {
        input_bounds[1] = plot_limits.x[1];
    }

    var buf: [1024:0]u8 = undefined;

    var inputs : [PLOT_STEPS + 1]f64 = undefined;
    var outputs : [PLOT_STEPS + 1]f64 = undefined;
    // var outputs_dual: [PLOT_STEPS + 1]curve.control_point.Dual_CP = undefined;

    var len : usize = 0;
    const step = (input_bounds[1] - input_bounds[0]) / PLOT_STEPS;
    var i = input_bounds[0];
    while (i < input_bounds[1])
        : ({i += step; len += 1;})
    {
        inputs[len] = i;
        outputs[len] = crv.output_at_input(i).as(f64);

        if (@mod(len, PLOT_STEPS/10) == 0) {
            const d = crv.output_at_input_dual(
                opentime.Ordinate.init(i)
            );
            zplot.plotLine(
                "dx/dy",
                f64,
                .{
                    .xv = &.{ 
                        d.r.in.as(f64),
                        d.r.in.as(f64) + d.i.in.as(f64),
                    },
                    .yv = &.{ 
                        d.r.out.as(f64),
                        d.r.out.as(f64) + d.i.out.as(f64),
                    },
                },
            );
        }
    }
    len = 0;
    i = 0;
    while (i < 1)
        : ({i += step; len += 1;})
    {
        if (@mod(len, PLOT_STEPS/10) == 0) {
            const d = crv.eval_at_dual(
                opentime.Dual_Ord.init_ri(i,1.0)
            );
            zplot.plotLine(
                "d/du",
                f64,
                .{
                    .xv = &.{ 
                        d.r.in.as(f64),
                        d.r.in.as(f64) + d.i.in.as(f64),
                    },
                    .yv = &.{ 
                        d.r.out.as(f64),
                        d.r.out.as(f64) + d.i.out.as(f64),
                    },
                    },
                );
        }
    }

    zplot.plotLine(
        name,
        f64, 
        .{
            .xv = &inputs,
            .yv = &outputs, 
        },
    );

    zgui.pushStrId("line_direction_test_point");
    {
        defer zgui.popId();
        _ = zplot.dragPoint(
            12,
            .{
                .col = .{ 0.0, 0.0, 1.0, 1.0, },
                .x = &STATE.line_direction_test_point.x,
                .y = &STATE.line_direction_test_point.y,
            },
        );

        const dual_u_ri = crv.findU_input_dual(
            opentime.Ordinate.init(
                STATE.line_direction_test_point.x
            )
        );
        const dual_u = dual_u_ri.r.as(f64);
        const direct_u = crv.findU_input(
            opentime.Ordinate.init(
                STATE.line_direction_test_point.x
            )
        );

        const label_lo = try std.fmt.bufPrintZ(
            &buf,
            "u: {d:0.2}, {d:0.2} (dual) {d:9.2} (direct)",
            .{ dual_u_ri.r.as(f64), dual_u_ri.i.as(f64), direct_u },
        );
        zplot.plotText(
            label_lo,
            .{ 
                .x = STATE.line_direction_test_point.x + 0.1,
                .y = STATE.line_direction_test_point.y + 0.1,
            },
        );

        const dual_pt = crv.eval_at(dual_u);
        const direct_pt = crv.eval_at(direct_u);

        zplot.plotLine(
            "[DUAL] Test point -> find input",
            f64,
            .{
                .xv = &.{ 
                    STATE.line_direction_test_point.x,
                    dual_pt.in.as(f64),
                },
                .yv = &.{
                    STATE.line_direction_test_point.y,
                    dual_pt.out.as(f64),
                },
            },
        );

        zplot.plotLine(
            "[DIRECT] Test point -> find input",
            f64,
            .{
                .xv = &.{ 
                    STATE.line_direction_test_point.x,
                    direct_pt.in.as(f64),
                },
                .yv = &.{
                    STATE.line_direction_test_point.y,
                    direct_pt.out.as(f64),
                },
            },
        );

        // const lerp_pt = curve.bezier_math.lerp(
        //     u,
        //     crv.p0,
        //     crv.p3,
        // );

        // zplot.plotLine(
        //     "p0->lerp(u)->p3",
        //     f64,
        //     .{
        //         .xv = &.{ 
        //             crv.p0.in.as(f64),
        //             lerp_pt.in.as(f64),
        //             crv.p3.in.as(f64),
        //         },
        //         .yv = &.{
        //             crv.p0.out.as(f64),
        //             lerp_pt.out.as(f64),
        //             crv.p3.out.as(f64),
        //         },
        //     },
        // );

        zplot.plotScatter(
            "Vertices",
            f64,
            .{
                .xv = &.{
                    crv.p0.in.as(f64),
                    crv.p1.in.as(f64),
                    crv.p2.in.as(f64),
                    crv.p3.in.as(f64),
                },
                .yv = &.{
                    crv.p0.out.as(f64),
                    crv.p1.out.as(f64),
                    crv.p2.out.as(f64),
                    crv.p3.out.as(f64),
                },
            },
        );
    }
}


/// plot a given mapping with dear imgui
pub fn plot_mapping(
    allocator: std.mem.Allocator,
    map : topology.mapping.Mapping,
    name: [:0]const u8,
) !void
{
    const input_bounds_ord = map.input_bounds();
    var input_bounds : [2]f64 = .{
        input_bounds_ord.start.as(f64),
        input_bounds_ord.end.as(f64),
    };

    const plot_limits = zgui.plot.getPlotLimits(
        .x1,
        .y1
    );

    if (input_bounds_ord.start.is_inf()) {
        input_bounds[0] = plot_limits.x[0];
    }
    if (input_bounds_ord.end.is_inf()) {
        input_bounds[1] = plot_limits.x[1];
    }

    var inputs = std.ArrayList(f64).init(allocator);
    try inputs.ensureTotalCapacity(PLOT_STEPS);
    defer inputs.deinit();
    var outputs = std.ArrayList(f64).init(allocator);
    try outputs.ensureTotalCapacity(PLOT_STEPS);
    defer outputs.deinit();
    var len : usize = 0;

    switch (map) {
        .affine => |map_aff| {
            try inputs.append(input_bounds[0]);
            try inputs.append(input_bounds[1]);

            try outputs.append(
                (
                 try map_aff.project_instantaneous_cc(
                     opentime.Ordinate.init(input_bounds[0])
                 ).ordinate()
                ).as(f64)
            );
            try outputs.append(
                (
                 try map_aff.project_instantaneous_cc(
                     opentime.Ordinate.init(input_bounds[1])
                 ).ordinate()
                ).as(f64)
            );

            len = 2;
        },
        .linear => |map_lin| {
            for (map_lin.input_to_output_curve.knots)
                |k|
            {
                try inputs.append(k.in.as(f64));
                try outputs.append(k.out.as(f64));
            }

            len = map_lin.input_to_output_curve.knots.len;
        },

        inline else => {},
    }

    try inputs.resize(len);
    const in_im = try inputs.toOwnedSlice();
    try outputs.resize(len);
    const out_im = try outputs.toOwnedSlice();

    zplot.plotLine(
        name,
        f64, 
        .{
            .xv = in_im,
            .yv = out_im, 
        },
    );
}

/// ui for a particular space
const SpaceUI = struct {
    name: []const u8,
    input: []const u8,
    output: []const u8,
    mapping: topology.mapping.Mapping,

    pub fn draw_ui(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !void
    {
        var buf : [1024:0]u8 = undefined;
        const label = try std.fmt.bufPrintZ(
            &buf,
            "Space: {s}",
            .{ self.name }
        );
        if (
            zgui.collapsingHeader(
                label,
                .{ .default_open = true }
                )
            )
        {
            zgui.text(
                "Input space name: {s}\n"
                ++ "Transform type: {s}\n"
                ++ "output space name: {s}",
                .{
                    self.input,
                    @tagName(self.mapping),
                    self.output,
                }
            );

            const plot_label = try std.fmt.bufPrintZ(
                buf[label.len..],
                "{s}.{s} -> {s}.{s} Mapping Plot",
                .{ self.name, self.input, self.name, self.output },
            );
            if (
                zgui.plot.beginPlot(
                    plot_label,
                    .{ 
                        .w = -1.0,
                        .h = -1.0,
                        .flags = .{ .equal = true },
                    }
                )
            ) 
            {
                defer zgui.plot.endPlot();

                zgui.plot.setupAxis(
                    .x1,
                    .{ .label = @ptrCast(self.input) }
                );
                zgui.plot.setupAxis(
                    .y1,
                    .{ .label = @ptrCast(self.output) }
                );
                zgui.plot.setupLegend(
                    .{ 
                        .south = true,
                        .west = true 
                    },
                    .{}
                );
                const input_limits = self.mapping.input_bounds();
                const range_start = @max(
                    input_limits.start.as(f64),
                    @as(f64, @floatFromInt(- std.math.maxInt(i64))),
                );
                const range_end = @min(
                    input_limits.end.as(f64),
                    @as(f64, @floatFromInt(std.math.maxInt(i64))),
                );
                zgui.plot.setupAxisLimits(
                    .x1, 
                    .{
                        .min = range_start,
                        .max = range_end,
                    },
                );

                const output_limits = self.mapping.output_bounds();
                zgui.plot.setupAxisLimits(
                    .y1, 
                    .{
                        .min = output_limits.start.as(f64),
                        .max = output_limits.end.as(f64),
                    },
                );

                zgui.plot.setupFinish();

            const graph_label = try std.fmt.bufPrintZ(
                buf[label.len + plot_label.len..],
                "{s}.{s} -> {s}.{s}",
                .{ self.name, self.input, self.name, self.output },
            );

                try plot_mapping(
                    allocator,
                    self.mapping,
                    graph_label,
                );
            }
        }
    }
};

/// state for the ui
const UI = struct {
    spaces: []const SpaceUI = &.{},
};

/// preset examples to choose from... pub const decls get added to an enum
/// and shown in the dropdown in the menu
const PRESETS = struct{
    pub const single_identity = UI{ 
        .spaces = &.{
            .{ 
                .name = "Clip",
                .input = "presentation",
                .output = "media",
                .mapping = topology.mapping.INFINITE_IDENTITY,
            },
        },
    };

    pub const single_affine = UI{
        .spaces = &.{
            .{ 
                .name = "Clip",
                .input = "presentation",
                .output = "media",
                .mapping = (
                    topology.mapping.MappingAffine{
                        .input_bounds_val = opentime.ContinuousInterval.init(
                            .{ 
                                .start = -10,
                                .end = 10, 
                            },
                        ),
                        .input_to_output_xform = .{
                                .offset = opentime.Ordinate.init(10),
                                .scale = opentime.Ordinate.init(2), 
                        },
                    }
                ).mapping(),
            },
        },
    };

    pub const affine_linear = UI{
        .spaces = &.{
            .{ 
                .name = "Track",
                .input = "presentation",
                .output = "media",
                .mapping = (
                    topology.mapping.MappingAffine{
                        .input_bounds_val = opentime.ContinuousInterval.init(
                            .{ 
                                .start = -10,
                                .end = 10, 
                            }
                        ),
                        .input_to_output_xform = .{
                            .offset = opentime.Ordinate.init(10),
                            .scale = opentime.Ordinate.init(2),
                        },
                    }
                ).mapping(),
            },
            .{ 
                .name = "Clip",
                .input = "presentation",
                .output = "media",
                .mapping = (
                    topology.mapping.MappingCurveLinearMonotonic{
                        .input_to_output_curve = .{
                                .knots = @constCast(
                                    &[_]curve.ControlPoint{
                                        .{
                                            .in = opentime.Ordinate.init(-10),
                                            .out = opentime.Ordinate.init(-10),
                                        },
                                        .{ 
                                            .in = opentime.Ordinate.init(0),
                                            .out = opentime.Ordinate.init(0),
                                        },
                                        .{ 
                                            .in = opentime.Ordinate.init(5),
                                            .out = opentime.Ordinate.init(10),
                                        },
                                    },
                                )
                            },
                        }
                ).mapping(),
            },
        },
    };
};
const PresetNames = std.meta.DeclEnum(PRESETS);

/// wrap the state for the entire UI
const State = struct {
    current_preset : PresetNames = .single_affine,
    data : UI = .{}, 
    line_direction_test_point : struct { x: f64 = 0, y: f64 = 0, } = .{},
};
var STATE = State{};

/// container union for debug apps
const DebuggerApp = union (enum) {
    bezier_curve_visualizer : BezierCurveVisualizer,
    transformation_visualizer : TransformVisualizer,

    pub inline fn name(self: @This()) [:0]const u8 {
        return switch (self) { inline else => |thing| thing.name() }; 
    }
    pub inline fn draw(self: @This(), allocator: std.mem.Allocator) !void {
        return switch (self) { inline else => |thing| thing.draw(allocator) }; 
    }
};

const APPS = [_]DebuggerApp{
    .{ .bezier_curve_visualizer = .{} },
    .{ .transformation_visualizer = .{} },
};

const BezierCurveVisualizer = struct {
    const name_data =  "Bezier Curve Visualizer";

    pub fn name(_: @This()) [:0]const u8 {
        return name_data;
    }
    pub fn draw(
        self: @This(),
        allocator:std.mem.Allocator,
    ) !void 
    {
        _ = self;

        const segment=curve.Bezier.Segment.init_f32(
            .{
                .p0 = .{ .in = 1, .out = 0, },
                .p1 = .{ .in = 1.25, .out = 1, },
                .p2 = .{ .in = 1.75, .out = 0.65, },
                .p3 = .{ .in = 2, .out = 0.24, },
            }
        );

        var buf_raw: [1024:0]u8 = undefined;
        var buf:[]u8 = buf_raw[0..];

        // const start = segment.p0.in;
        // const end = segment.p3.in;

        const plot_label = try std.fmt.bufPrintZ(
            buf,
            "Convex Hull Test Plot", 
            .{}
        );
        buf = buf[plot_label.len..];

        if (
            zgui.plot.beginPlot(
                plot_label,
                .{ 
                    .w = -1.0,
                    .h = -1.0,
                    .flags = .{ .equal = true },
                }
            )
        ) 
        {
            defer zgui.plot.endPlot();

            const input_label = try std.fmt.bufPrintZ(buf, "input", .{},);
            buf = buf[input_label.len..];

            zgui.plot.setupAxis(
                .x1,
                .{ .label = input_label }
            );

            const output_label = try std.fmt.bufPrintZ( buf, "output", .{},);
            buf = buf[output_label.len..];

            zgui.plot.setupAxis(
                .y1,
                .{ .label = output_label }
            );
            zgui.plot.setupLegend(
                .{ 
                    .south = true,
                    .west = true 
                },
                .{}
            );
            zgui.plot.setupFinish();

            const line_label = try std.fmt.bufPrintZ(
                buf,
                "convex hull segment",
                .{},
            );
            buf = buf[line_label.len..];

            try plot_curve_bezier_segment(
                allocator,
                line_label,
                segment,
            );
        }


        return;
    }
};

const TransformVisualizer = struct {
    const name_data =  "Curve Transformation Visualizer";

    pub fn name(_: @This()) [:0]const u8 {
        return name_data;
    }
    pub fn draw(
        _: @This(),
        allocator: std.mem.Allocator,
    ) !void 
    {
        if (
            zgui.beginChild(
                "Options", 
                .{
                    .w = 600, .h = -1
                        , .child_flags = .{
                            .border = true, 
                        }, 
                    .window_flags = .{
                        .always_vertical_scrollbar = true,
                    },
                },
            )
        )
        {
            defer zgui.endChild();

            if (zgui.collapsingHeader("Presets", .{}))
            {
                _ = zgui.comboFromEnum(
                    "Preset",
                    &STATE.current_preset,
                );

                if (zgui.button("LOAD PRESET", .{}))
                {
                    // load into state
                    STATE.data = switch(STATE.current_preset) {
                        inline else => |f| @field(
                            PRESETS,
                            @tagName(f)
                        ),
                    };
                }
            }

            zgui.separator();

            if (
                zgui.collapsingHeader(
                    "Spaces",
                    .{ .default_open =  true, },
                )
            )
            {
                for (STATE.data.spaces)
                    |s|
                {
                    try s.draw_ui(allocator);
                }
            }
        }

        zgui.sameLine(.{});

        if (
            zgui.beginChild(
                "main Thing", 
                .{
                    .w = -1,
                    .h = -1,
                }
            )
        )
        {
            defer zgui.endChild();

            var buf_raw: [1024:0]u8 = undefined;
            var buf:[]u8 = buf_raw[0..];

            if (STATE.data.spaces.len == 0) {
                return;
            }

            const start = STATE.data.spaces[0];
            const end = STATE.data.spaces[STATE.data.spaces.len-1];

            const plot_label = try std.fmt.bufPrintZ(
                buf,
                "Plot of Mapping: {s}.{s} -> {s}.{s}", 
                .{ start.name, start.input, end.name, end.output }
            );
            buf = buf[plot_label.len..];

            if (
                zgui.plot.beginPlot(
                    plot_label,
                    .{ 
                        .w = -1.0,
                        .h = -1.0,
                        .flags = .{ .equal = true },
                    }
                )
            ) 
            {
                defer zgui.plot.endPlot();

                const input_label = try std.fmt.bufPrintZ(
                    buf,
                    "{s}.{s}",
                    .{ start.name, start.input },
                );
                buf = buf[input_label.len..];

                zgui.plot.setupAxis(
                    .x1,
                    .{ .label = input_label }
                );

                const output_label = try std.fmt.bufPrintZ(
                    buf,
                    "{s}.{s}",
                    .{ start.name, start.input },
                );
                buf = buf[output_label.len..];

                zgui.plot.setupAxis(
                    .y1,
                    .{ .label = output_label }
                );
                zgui.plot.setupLegend(
                    .{ 
                        .south = true,
                        .west = true 
                    },
                    .{}
                );
                zgui.plot.setupFinish();

                var total_map = STATE.data.spaces[0].mapping;

                for (STATE.data.spaces[1..])
                    |s|
                    {
                        total_map = try topology.mapping.join(
                            allocator,
                            .{
                                .a2b = total_map,
                                .b2c = s.mapping,
                            },
                            );
                    }

                const line_label = try std.fmt.bufPrintZ(
                    buf,
                    "{s}.{s}",
                    .{ start.name, start.input },
                );
                buf = buf[line_label.len..];

                try plot_mapping(
                    allocator,
                    total_map,
                    line_label,
                );
            }
        }

        return;
    }
};

/// top level draw fn
fn draw(
) !void 
{
    draw_err() catch |err| std.log.err(
        "Error running gui. Error: {any}",
        .{ err }
    );
}

fn draw_err(
) !void
{
    const vp = zgui.getMainViewport();
    const size = vp.getSize();

    zgui.setNextWindowPos(.{ .x = 0, .y = 0 });
    zgui.setNextWindowSize(
        .{ 
            .w = size[0],
            .h = size[1],
        }
    );

    const allocator = std.heap.c_allocator;

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
            }
        )
    )
    {
        defer zgui.end();

        if (zgui.beginTabBar("Applications", .{}))
        {
            defer zgui.endTabBar();

            // each "app" gets its own tab
            for (APPS)
                |app|
            {
                // _ = app;

                if (zgui.beginTabItem(app.name(), .{}))
                {
                    defer zgui.endTabItem();

                    if (zgui.beginChild("child", .{}))
                    {
                        defer zgui.endChild();

                        try app.draw(allocator);
                    }
                }
            }
        }


    }
}

pub fn main(
) void 
{
    sokol_app_wrapper.sokol_main(
        .{
            .title = WINDOW_TITLE,
            .draw = draw, 
            .content_dir = content_dir,
            .dimensions = .{ 1600, 600 },
        },
    );
}
