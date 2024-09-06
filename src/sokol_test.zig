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


    const viewport = c.igGetMainViewport();
    // ImGui::SetNextWindowPos(viewport->GetWorkPos());
    // ImGui::SetNextWindowSize(viewport->GetWorkSize());
    // ImGui::SetNextWindowViewport(viewport->ID);
    //
    c.igSetNextWindowSize(viewport.*.WorkSize, c.ImGuiCond_None);
    c.igSetNextWindowPos(.{ .x = 0, .y = 0 }, c.ImGuiCond_None, .{},);
    c.igSetNextWindowViewport(viewport.*.ID);

    var main_is_open : bool = true;
    if (
        c.igBegin(
            "###FULLSCREEN",
            @ptrCast(&main_is_open),
            c.ImGuiWindowFlags_NoDecoration 
            | c.ImGuiWindowFlags_NoResize
            | c.ImGuiWindowFlags_NoScrollWithMouse
            | c.ImGuiWindowFlags_AlwaysAutoResize
            | c.ImGuiWindowFlags_NoMove
            ,
        )
    )
    {
        defer c.igEnd();

        const style = c.igGetStyle();
        style.*.WindowRounding = 0;
        style.*.WindowPadding = .{ .x = 0, .y = 0 };

        const text_header_size = 30;
        // const text_size = c.ImVec2{
        //     .x = viewport.*.WorkSize.x,
        //     .y = text_header_size,
        // };
        // c.igSetNextWindowSize(text_size, c.ImGuiCond_None);

        if (
            c.igBeginChild_Str(
                "Hello Child Plot",
                // text_size,
                viewport.*.WorkSize,
                c.ImGuiChildFlags_None,
                c.ImGuiWindowFlags_NoResize,
            )
        )
        {
            defer c.igEndChild();
            // FPS/status line
            c.igBulletText(
                "Ok, pieces are working...sdfasdfasdfasdfasd filling the window so we can see it go all the way across blah blah blah\nAverage : %.3f ms/frame (%.1f fps)",
                1000.0 / c.igGetIO().*.Framerate, c.igGetIO().*.Framerate,
            );

            var buf : [4048]u8 = undefined;

            _ = try std.fmt.bufPrintZ(
                &buf,
                "viewport data:\n size: {any} \n worksize: {any} \n",
                .{
                    viewport.*.Size,
                    viewport.*.WorkSize,
                } 
            );

            c.igText(
                "read data: %s",
                &buf,
            );
        }
        // c.igSetNextWindowPos(.{ .x = 0, .y = text_header_size }, 0, .{});

        const next_window_size = c.ImVec2{
            .x = viewport.*.WorkSize.x,
            .y = viewport.*.WorkSize.y - text_header_size,
        };

        if (
            c.igBeginChild_Str(
                "Hello Child Plot",
                next_window_size,
                c.ImGuiChildFlags_None,
                c.ImGuiWindowFlags_NoResize,
            )
        )
        {
            defer c.igEndChild();
            if (c.ImPlot_BeginPlot(
                    "Graph View",
                    viewport.*.Size,
                    c.ImPlotFlags_None,
            )){
                const xs= [_]f32{0, 1, 2, 3, 4};
                const ys= [_]f32{0, 1, 2, 3, 6};

                c.ImPlot_PlotLine_FloatPtrFloatPtr(
                    "test plot",
                    &xs,
                    &ys,
                    5,
                    c.ImPlotLineFlags_None,
                    0,
                    @sizeOf(f32),
                );
                defer c.ImPlot_EndPlot();
            }
        }
    }


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
