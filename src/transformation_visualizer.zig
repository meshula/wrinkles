const std = @import("std");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = zgui.plot;

const sokol_app_wrapper = ziis.app_wrapper;

const topology = @import("topology");
const curve = @import("curve");
const opentime = @import("opentime");

const build_options = @import("build_options");
const WINDOW_TITLE = (
    "OpenTimelineIO V2 Prototype Transformation Visualizer [" 
    ++ build_options.hash[0..6] 
    ++ "]"
);

const PLOT_STEPS = 1000;

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

    var inputs: std.ArrayList(f64) = .{};
    defer inputs.deinit(allocator);

    try inputs.ensureTotalCapacity(allocator, PLOT_STEPS);

    var outputs: std.ArrayList(f64) = .{};
    defer outputs.deinit(allocator);

    try outputs.ensureTotalCapacity(allocator, PLOT_STEPS);
    var len : usize = 0;

    switch (map) {
        .affine => |map_aff| {
            try inputs.append(allocator, input_bounds[0]);
            try inputs.append(allocator, input_bounds[1]);

            try outputs.append(
                allocator,
                (
                 try map_aff.project_instantaneous_cc(
                     opentime.Ordinate.init(input_bounds[0])
                 ).ordinate()
                ).as(f64)
            );
            try outputs.append(
                allocator,
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
                try inputs.append(allocator, k.in.as(f64));
                try outputs.append(allocator, k.out.as(f64));
            }

            len = map_lin.input_to_output_curve.knots.len;
        },
        // .bezier => |map_bez| {
        //     const step = (
        //         @as(f32, @floatCast(input_bounds[1] - input_bounds[0])) 
        //         / @as(f32, @floatFromInt(PLOT_STEPS))
        //     );
        //
        //     var x = input_bounds[0];
        //     while (x <= input_bounds[1])
        //         : (x += step)
        //     {
        //         try inputs.append(x);
        //         try outputs.append(
        //             try map_bez.project_instantaneous_cc(@floatCast(x))
        //         );
        //     }
        //
        //     len = PLOT_STEPS;
        // },

        inline else => {},
    }

    try inputs.resize(allocator, len);
    const in_im = try inputs.toOwnedSlice(allocator);
    try outputs.resize(allocator, len);
    const out_im = try outputs.toOwnedSlice(allocator);

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
                zgui.plot.setupAxisLimits(
                    .x1, 
                    .{
                        .min = input_limits.start.as(f64),
                        .max = input_limits.end.as(f64),
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
};
var STATE = State{};

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
    }
}

pub fn main(
) void 
{
    sokol_app_wrapper.sokol_main(
        .{
            .title = WINDOW_TITLE,
            .draw = draw, 
            .dimensions = .{ 1600, 600 },
        },
    );
}
