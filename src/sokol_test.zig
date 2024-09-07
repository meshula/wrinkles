const std = @import("std");
const c = @import("imzokol");
const zgui = c.zgui;
const zplot = zgui.plot;
const sokol = c.sokol;
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;

var pass_action: sg.PassAction = .{};

var gfx_arena_state : std.heap.ArenaAllocator = undefined;
var gfx_allocator : std.mem.Allocator = undefined;


export fn init(
) void 
{
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_state.allocator();
    gfx_arena_state = arena_state;
    gfx_allocator = arena;
    
    sg.setup(
        .{
            .environment = sglue.environment(),
            .logger = .{ .func = slog.func },
        }
    );

    var desc: c.simgui_desc_t = .{};
    c.simgui_setup(&desc);
    _ = c.ImPlot_CreateContext();

    var io: *c.ImGuiIO = @ptrCast(c.igGetIO());
    io.ConfigFlags |= c.ImGuiConfigFlags_NavEnableKeyboard;
    io.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;
    io.FontGlobalScale = 1.0 / io.DisplayFramebufferScale.y;

    pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    };
    std.debug.print("Backend: {}\n", .{sg.queryBackend()});

    zgui.init(arena);
    zgui.temp_buffer = std.ArrayList(u8).init(arena);
    zgui.temp_buffer.?.resize(3 * 1024 + 1) catch unreachable;
    zgui.plot.init();
}

export fn frame(
) void 
{
    var new_frame: c.simgui_frame_desc_t = .{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    };
    c.simgui_new_frame(&new_frame);

    drawGui() catch |err| {
        std.debug.print(">>> ERROR: {any}\n", .{err});
        std.process.exit(1);
    };

    sg.beginPass(.{ .action = pass_action, .swapchain = sglue.swapchain() });
    c.simgui_render();
    sg.endPass();
    sg.commit();
}

export fn cleanup(
) void 
{
    c.ImPlot_DestroyContext(null);
    gfx_arena_state.deinit();
    c.simgui_shutdown();
    sg.shutdown();
}

/// handle keypresses
export fn event(
    ev: [*c]const sapp.Event,
) void 
{
    _ = c.simgui_handle_event(@ptrCast(ev));

    // Check if the key event is a key press, and if it is the Escape key 
    if (
        ev.*.type == .KEY_DOWN
        and ev.*.key_code == .ESCAPE
    ) 
    { 
        // Quit the application 
        c.sapp_request_quit(); 
    }
}

/// draw the UI
fn drawGui(
) !void 
{
    const viewport = c.igGetMainViewport();

    zgui.setNextWindowPos(.{ .x = 0, .y = 0 });
    zgui.setNextWindowSize(
        .{ 
            .w = viewport.*.WorkSize.x,
            .h = viewport.*.WorkSize.y,
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

        zgui.bulletText("pasta, potato: {d}\n", .{ 12 });

        if (
            zgui.beginChild(
                "Plot", 
                .{
                    .w = -1,
                    .h = -1,
                }
            )
        )
        {
            defer zgui.endChild();
            if (
                zgui.plot.beginPlot(
                    "Curve Plot",
                    .{ 
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
    sapp.run(
        .{
            .init_cb = init,
            .frame_cb = frame,
            .cleanup_cb = cleanup,
            .event_cb = event,
            .width = 800,
            .height = 800,
            .icon = .{ .sokol_default = true },
            .window_title = "Wrinkles Sokol Test",
            .logger = .{ .func = slog.func },
            .win32_console_attach = true,
        }
    );
}
