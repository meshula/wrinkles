//! example app using the app wrapper

const std = @import("std");
const builtin = @import("builtin");

const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = zgui.plot;
const sg = ziis.sokol.gfx;
const app_wrapper = ziis.app_wrapper;

const cimgui = ziis.cimgui;

/// State container
const STATE = struct {
    var f: f32 = 0;
    var demo_window_gui = false;
    var demo_window_plot = false;
    const TEX_DIM : [2]i32 = .{ 256, 256 };
    const COLOR_CHANNELS:usize = 4;
    var tex: sg.Image = .{};
    var view: sg.View = .{};
    var texid: u64 = 0;
    var frame_number: usize = 0;
    var buffer = std.mem.zeroes(
        [STATE.TEX_DIM[0]][STATE.TEX_DIM[1]][COLOR_CHANNELS]u8
    );
    var maybe_journal : ?ziis.undo.Journal = null;
    var image_data = ziis.sokol.gfx.ImageData{};

    var allocator: std.mem.Allocator = undefined;
    var maybe_debug_allocator: ?std.heap.DebugAllocator(.{}) = null;
};

const IS_WASM = builtin.target.cpu.arch.isWasm();

/// draw the UI
fn draw(
) !void 
{
    const vp = zgui.getMainViewport();
    const size = vp.getSize();

    STATE.frame_number = @intFromFloat(@abs(STATE.f));

    sg.updateImage(
        STATE.tex,
        init: {
            // initialize the image STATE.buffer
            var x:usize = 0;
            const iw_m_one: f64 = @floatFromInt(STATE.TEX_DIM[0] - 1);
            const ih_m_one: f64 = @floatFromInt(STATE.TEX_DIM[1] - 1);
            while (x < STATE.TEX_DIM[0])
                : (x += 1)
            {
                const fx: f64 = @floatFromInt(
                    @mod(x + STATE.frame_number, STATE.TEX_DIM[0])
                );
                var y:usize = 0;
                while (y < STATE.TEX_DIM[1])
                    : (y += 1)
                {
                    const fy: f64 = @floatFromInt(
                        @mod(y + STATE.frame_number, STATE.TEX_DIM[1])
                    );

                    const r = fx / iw_m_one;
                    const g = fy / ih_m_one;
                    const b:f64 = 0.0;

                    STATE.buffer[x][y][0] = @intFromFloat(255.999 * r);
                    STATE.buffer[x][y][1] = @intFromFloat(255.999 * g);
                    STATE.buffer[x][y][2] = @intFromFloat(255.999 * b);
                    STATE.buffer[x][y][3] = 255;
                }
            }

            STATE.image_data.mip_levels[0] = ziis.sokol.gfx.asRange(
                &STATE.buffer,
            );

            break :init STATE.image_data;
        },
    );

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

        // zgui.pushStyleVar1f( .{ .idx = .child_border_size, .v = 0});
        // zgui.pushStyleVar1f( .{ .idx = .docking_separator_size, .v = 0});
        zgui.pushStyleVar1f(.{ .idx = .child_rounding, .v = 0});
        zgui.pushStyleVar1f(.{ .idx = .popup_rounding, .v = 0});
        zgui.pushStyleVar1f(.{ .idx = .tab_rounding,   .v = 0});
        zgui.pushStyleVar1f(.{ .idx = .window_rounding,.v = 0});
        zgui.pushStyleVar1f(.{ .idx = .grab_rounding,  .v = 0});
        zgui.pushStyleVar1f(.{ .idx = .frame_rounding, .v = 0});
        zgui.pushStyleVar1f(.{ .idx = .scrollbar_rounding, .v = 0});
        defer zgui.popStyleVar(.{ .count = 7});

        var new = STATE.f;
        if (zgui.dragFloat("texture offset", .{.v = &new})) 
        {
            const cmd = try ziis.undo.SetValue(f32).init(
                    STATE.allocator,
                    &STATE.f,
                    new,
                    "texture offset"
            );
            try cmd.do();
            try STATE.maybe_journal.?.update_if_new_or_add(cmd);
        }

        for (STATE.maybe_journal.?.entries.items, 0..)
            |cmd, ind|
        {
            zgui.bulletText("{d}: {s}", .{ ind, cmd.message });
        }

        zgui.bulletText(
            "Head Entry in Journal: {?d}",
            .{ STATE.maybe_journal.?.maybe_head_entry }
        );

        if (zgui.beginItemTooltip()) 
        {
            zgui.text("Hi, this is a tooltip", .{});
            zgui.endTooltip();
        }

        if (zgui.button("undo", .{}))
        {
            try STATE.maybe_journal.?.undo();
        }

        zgui.sameLine(.{});

        if (zgui.button("redo", .{}))
        {
            try STATE.maybe_journal.?.redo();
        }

        if (zgui.button("show gui demo", .{}) )
        { 
            STATE.demo_window_gui = ! STATE.demo_window_gui; 
        }
        if (zgui.button("show plot demo", .{}))
        {
            STATE.demo_window_gui = ! STATE.demo_window_plot; 
        }

        if (STATE.demo_window_gui) 
        {
            zgui.showDemoWindow(&STATE.demo_window_gui);
        }
        if (STATE.demo_window_plot) 
        {
            zplot.showDemoWindow(&STATE.demo_window_plot);
        }

        if (zgui.beginTabBar("Panes", .{}))
        {
            defer zgui.endTabBar();

            if (zgui.beginTabItem("PlotTab", .{}))
            {
                defer zgui.endTabItem();

                if (
                    zgui.beginChild(
                        "Plot", 
                        .{ .w = -1, .h = -1, },
                    )
                )
                {
                    defer zgui.endChild();

                    if (
                        zgui.plot.beginPlot(
                            "Test ZPlot Plot",
                            .{ 
                                .w = -1.0,
                                .h = -1.0,
                                .flags = .{ .equal = true },
                            },
                        )
                    ) 
                    {
                        defer zgui.plot.endPlot();

                        zgui.plot.setupAxis(
                            .x1,
                            .{ .label = "input" },
                        );
                        zgui.plot.setupAxis(
                            .y1,
                            .{ .label = "output" },
                        );
                        zgui.plot.setupLegend(
                            .{ 
                                .south = true,
                                .west = true 
                            },
                            .{},
                        );
                        zgui.plot.setupFinish();

                        const xs= [_]f32{0, 1, 2, 3, 4};
                        const ys= [_]f32{0, 1, 2, 3, 6};

                        zplot.pushStyleColor4f(
                            .{
                                .idx = .fill,
                                .c = .{ 0.1, 0.1, 0.4, 0.4 },
                            },
                        );
                        zplot.plotShaded(
                            "test plot (shaded)",
                            f32, 
                            .{
                                .xv = &xs,
                                .yv = &ys,
                                .flags = .{
                                },
                            },
                        );
                        zplot.popStyleColor(.{.count = 1});

                        zplot.plotLine(
                            "test plot",
                            f32, 
                            .{
                                .xv = &xs,
                                .yv = &ys,
                            },
                        );
                    }
                }
            }

            if (zgui.beginTabItem("Texture Example", .{}))
            {
                defer zgui.endTabItem();

                const wsize = zgui.getWindowSize();

                ziis.cimgui.igImage(
                    .{ ._TexID = STATE.texid },
                    .{ .x = wsize[0], .y = wsize[1]},
                );
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
    STATE.tex = sg.makeImage(
        .{
            .width = STATE.TEX_DIM[0],
            .height = STATE.TEX_DIM[1],
            .usage = .{ .stream_update = true },
            .pixel_format = .RGBA8,
        },
    );

    STATE.view = sg.makeView(
        .{
            .texture = .{
                .image = STATE.tex,
            },
        },
    );

    STATE.texid = ziis.sokol.imgui.imtextureid(STATE.view);
}

pub fn main(
) !void 
{
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

    app_wrapper.sokol_main(
        .{
            .draw = draw, 
            .maybe_pre_zgui_shutdown_cleanup = cleanup,
            .maybe_post_zgui_init = init,
        },
    );
}
