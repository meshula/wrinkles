const std = @import("std");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = zgui.plot;

const sokol_app_wrapper = @import("sokol_app_wrapper");

const time_topology = @import("time_topology");

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
    map : time_topology.mapping.Mapping,
) !void
{
    const limits = zgui.plot.getPlotLimits(.x1,.y1);
    var inputs : [PLOT_STEPS]f32 = undefined;
    var outputs : [PLOT_STEPS]f32 = undefined;

    const step = (
        @as(f32, @floatCast(limits.x[1] - limits.x[0])) 
        / @as(f32, @floatFromInt(PLOT_STEPS))
    );

    for (&inputs, &outputs, 0..)
        |*in, *out, ind|
    {
        in.* = @as(f32, @floatCast(limits.x[0])) + @as(f32, @floatFromInt(ind)) * step;
        out.* = @floatCast(try map.project_instantaneous_cc(@floatCast(in.*)));
    }

    zplot.plotLine(
        "test plot",
        f32, 
        .{
            .xv = &inputs,
            .yv = &outputs, 
        },
    );
}

const SpaceUI = struct {
    name: []const u8,
    input: []const u8,
    output: []const u8,
    mapping: time_topology.mapping.Mapping,

    pub fn draw_ui(
        self: @This(),
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
                zgui.plot.setupFinish();

                try plot_mapping(self.mapping);
            }
        }
    }
};

const UI = struct {
    spaces: []const SpaceUI = &.{},
};

const PresetNames = enum {
    single_identity, single_affine,
};

const PRESETBIN = std.enums.EnumFieldStruct(
    PresetNames,
    UI,
    .{}
);
const PRESETS = PRESETBIN{
        .single_identity = UI{ 
            .spaces = &.{
                .{ 
                    .name = "Clip",
                    .input = "presentation",
                    .output = "media",
                    .mapping = time_topology.mapping.INFINITE_IDENTIY,
                },
            },
        },
        .single_affine = UI{
            .spaces = &.{
                .{ 
                    .name = "Clip",
                    .input = "presentation",
                    .output = "media",
                    .mapping = (time_topology.mapping.MappingAffine{
                        .input_bounds_val = .{
                            .start_seconds = -10,
                            .end_seconds = 10,
                        },
                        .input_to_output_xform = .{
                            .offset_seconds = 10,
                            .scale = 2,
                        },
                    }).mapping(),
                },
            },
        },
};

const State = struct {
    current_preset : PresetNames = .single_affine,
    data : UI = .{}, 
};
var STATE = State{};

/// draw the UI
fn draw(
) !void 
{
    draw_err() catch std.log.err("Error running gui.", .{});
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
                .{ .w = 600, .h = -1, .child_flags = .{ .border = true, }, },
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
                    try s.draw_ui();
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
