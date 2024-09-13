const std = @import("std");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = zgui.plot;

const sokol_app_wrapper = @import("sokol_app_wrapper");

const time_topology = @import("time_topology");
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

/// plot a given mapping with dear imgui
pub fn plot_mapping(
    allocator: std.mem.Allocator,
    map : time_topology.mapping.Mapping,
    name: [:0]const u8,
) !void
{
    const input_bounds_ord = map.input_bounds();
    var input_bounds : [2]f64 = .{
        @floatCast(input_bounds_ord.start_seconds),
        @floatCast(input_bounds_ord.end_seconds),
    };

    const plot_limits = zgui.plot.getPlotLimits(
        .x1,
        .y1
    );

    if (input_bounds_ord.start_seconds == std.math.inf(opentime.Ordinate)) {
        input_bounds[0] = plot_limits.x[0];
    }
    if (input_bounds_ord.end_seconds == std.math.inf(opentime.Ordinate)) {
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
                try map_aff.project_instantaneous_cc(@floatCast(input_bounds[0]))
            );
            try outputs.append(
                try map_aff.project_instantaneous_cc(@floatCast(input_bounds[1]))
            );

            len = 2;
        },
        .linear => |map_lin| {
            for (map_lin.input_to_output_curve.knots)
                |k|
            {
                try inputs.append(k.in);
                try outputs.append(k.out);
            }

            len = map_lin.input_to_output_curve.knots.len;
        },
        .bezier => |map_bez| {
            const step = (
                @as(f32, @floatCast(input_bounds[1] - input_bounds[0])) 
                / @as(f32, @floatFromInt(PLOT_STEPS))
            );

            var x = input_bounds[0];
            while (x <= input_bounds[1])
                : (x += step)
            {
                try inputs.append(x);
                try outputs.append(
                    try map_bez.project_instantaneous_cc(@floatCast(x))
                );
            }

            len = PLOT_STEPS;
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
    mapping: time_topology.mapping.Mapping,

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
        if (zgui.collapsingHeader(label, .{ .default_open = true }))
        {
            zgui.text("Input space name: {s}", .{ self.input });
            zgui.text("output space name: {s}", .{ self.output });

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
                        .min = input_limits.start_seconds,
                        .max = input_limits.end_seconds,
                    },
                );

                const output_limits = self.mapping.output_bounds();
                zgui.plot.setupAxisLimits(
                    .y1, 
                    .{
                        .min = output_limits.start_seconds,
                        .max = output_limits.end_seconds,
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
                .mapping = time_topology.mapping.INFINITE_IDENTIY,
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
                    time_topology.mapping.MappingAffine{
                        .input_bounds_val = .{
                            .start_seconds = -10,
                            .end_seconds = 10,
                        },
                        .input_to_output_xform = .{
                            .offset_seconds = 10,
                            .scale = 2,
                        },
                    }
                ).mapping(),
            },
        },
    };

    pub const affine_linear = UI{
        .spaces = &.{
            .{ 
                .name = "Clip1",
                .input = "presentation",
                .output = "media",
                .mapping = (
                    time_topology.mapping.MappingAffine{
                        .input_bounds_val = .{
                            .start_seconds = -10,
                            .end_seconds = 10,
                        },
                        .input_to_output_xform = .{
                            .offset_seconds = 10,
                            .scale = 2,
                        },
                    }
                ).mapping(),
            },
            .{ 
                .name = "Clip2",
                .input = "presentation",
                .output = "media",
                .mapping = (
                    time_topology.mapping.MappingCurveLinear{
                        .input_to_output_curve = 
                            .{
                                .knots = @constCast(
                                    &[_]curve.ControlPoint{
                                        .{ .in = -10, .out = -10 },
                                        .{ .in = 0, .out = 0 },
                                        .{ .in = 5, .out = 10 },
                                        .{ .in = 10, .out = 3 },
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
                    .{ .default_open =  true}
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



            zgui.bulletText("pasta, potato: {d}\n", .{ 12 });

            if (
                zgui.plot.beginPlot(
                    "Test ZPlot Plot",
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
                    .{ .label = "input" }
                );
                zgui.plot.setupAxis(
                    .y1,
                    .{ .label = "output" }
                );
                zgui.plot.setupLegend(
                    .{ 
                        .south = true,
                        .west = true 
                    },
                    .{}
                );
                zgui.plot.setupFinish();

                const xs= [_]f32{0, 1, 2, 3, 4};
                const ys= [_]f32{0, 1, 2, 3, 6};

                zplot.plotLine(
                    "test plot",
                    f32, 
                    .{
                        .xv = &xs,
                        .yv = &ys 
                    },
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
            .content_dir = content_dir,
            .dimensions = .{ 1600, 600 },
        },
    );
}
