const std = @import("std");
const c = @import("imzokol");
const sokol = c.sokol;
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const print = @import("std").debug.print;

var pass_action: sg.PassAction = .{};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

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
    print("Backend: {}\n", .{sg.queryBackend()});
}

export fn frame() void {
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

export fn cleanup() void {
    c.ImPlot_DestroyContext(null);
    c.simgui_shutdown();
    sg.shutdown();
}

export fn event(ev: [*c]const sapp.Event) void {
    _ = c.simgui_handle_event(@ptrCast(ev));
}

fn drawGui() !void {
    // c.igShowDemoWindow(null);
    // c.ImPlot_ShowDemoWindow(null);

    // const size = gfx_state.gctx.window_provider.fn_getFramebufferSize(gfx_state.gctx.window_provider.window);
    // const width:f32 = @floatFromInt(size[0]);
    // const height:f32 = @floatFromInt(size[1]);
    //
    // zgui.setNextWindowSize(.{ .w = width, .h = height, });
    //

    c.igSetNextWindowPos(
        .{ .x = 0, .y = 0 },
        0,
        .{},
    );

    var main_flags : c.ImGuiWindowFlags = c.ImGuiWindowFlags_None;

    main_flags |= c.ImGuiWindowFlags_NoResize;
    main_flags |= c.ImGuiWindowFlags_NoBackground;
    main_flags |= c.ImGuiWindowFlags_NoMove;
    main_flags |= c.ImGuiWindowFlags_NoScrollWithMouse;
    main_flags |= c.ImGuiWindowFlags_NoBringToFrontOnFocus;
    main_flags |= c.ImGuiWindowFlags_NoDecoration;

    var main_is_open : bool = true;
    defer c.igEnd();
    if (!c.igBegin("###FULLSCREEN", @ptrCast(&main_is_open), main_flags))
    {
        return;
    }

    // FPS/status line
    c.igBulletText(
        "Ok, pieces are working...\nAverage : %.3f ms/frame (%.1f fps)",
        1000.0 / c.igGetIO().*.Framerate, c.igGetIO().*.Framerate,
    );
    // zgui.bulletText(
    //     "Average : {d:.3} ms/frame ({d:.1} fps)",
    //     .{ gfx_state.gctx.stats.average_cpu_time, gfx_state.gctx.stats.fps },
    // );

    // // FPS/status line
    // zgui.bulletText(
    //     "Average : {d:.3} ms/frame ({d:.1} fps)",
    //     .{ gfx_state.gctx.stats.average_cpu_time, gfx_state.gctx.stats.fps },
    // );
    // zgui.spacing();
    //
    // var tmp_buf:[1024:0]u8 = undefined;
    // @memset(&tmp_buf, 0);
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = 640,
        .height = 480,
        .icon = .{ .sokol_default = true },
        .window_title = "Wrinkles Sokol Test",
        .logger = .{ .func = slog.func },
        .win32_console_attach = true,
    });
}
