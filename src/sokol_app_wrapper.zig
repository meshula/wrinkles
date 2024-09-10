const std = @import("std");
const ig = @import("cimgui");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = ziis.zgui.plot;
const sokol = ziis.sokol;
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const simgui = sokol.imgui;

const state = struct {
    var pass_action: sg.PassAction = .{};
};

var content_dir : []const u8 = undefined;

// const font_data = @embedFile(content_dir ++ "/Roboto-Medium.ttf");

var raw = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = raw.allocator();

// var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
// const allocator = arena.allocator();

export fn init(
) void 
{
    // initialize sokol-gfx
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    // initialize sokol-imgui
    simgui.setup(.{
        .logger = .{ .func = slog.func },
    });

    // initial clear color
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
    };

    zgui.init(allocator);
    zgui.plot.init();

    {
        const scale_factor = sokol.app.sapp_dpi_scale();
        //
        // const robota_font_path = std.fs.path.joinZ(
        //     gfx_allocator,
        //     &.{ content_dir, "Roboto-Medium.ttf" }
        // ) catch @panic("couldn't find font");
        // defer gfx_allocator.free(robota_font_path);
        //
        // const font_size = 16.0 * scale_factor;
        // const font_large = zgui.io.addFontFromFile(
        //     robota_font_path,
        //     font_size * 1.1
        // );
        // _ = font_large;
        // // std.debug.assert(zgui.io.getFont(0) == font_large);
        //
        // const font_normal = zgui.io.addFontFromFile(
        //     robota_font_path,
        //     font_size
        // );
        // // std.debug.assert(zgui.io.getFont(1) == font_normal);
        //
        // // This call is optional. Initially, zgui.io.getFont(0) is a default font.
        // zgui.io.setDefaultFont(font_normal);

        // You can directly manipulate zgui.Style *before* `newFrame()` call.
        // Once frame is started (after `newFrame()` call) you have to use
        // zgui.pushStyleColor*()/zgui.pushStyleVar*() functions.
        const style = zgui.getStyle();

        style.window_min_size = .{ 320.0, 240.0 };
        style.window_border_size = 8.0;
        style.scrollbar_size = 6.0;
        {
            var color = style.getColor(.scrollbar_grab);
            color[1] = 0.8;
            style.setColor(.scrollbar_grab, color);
        }
        style.scaleAllSizes(scale_factor);

        // To reset zgui.Style with default values:
        //zgui.getStyle().* = zgui.Style.init();

        {
            zgui.plot.getStyle().line_weight = 3.0;
            const plot_style = zgui.plot.getStyle();
            plot_style.marker = .circle;
            plot_style.marker_size = 5.0;
        }
    }
}

export fn frame(
) void 
{
    // call simgui.newFrame() before any ImGui calls
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });

    app.draw() catch |err| {
        std.debug.print(">>> ERROR: {any}\n", .{err});
        std.process.exit(1);
    };

    sg.beginPass(
        .{
            .action = state.pass_action,
            .swapchain = sglue.swapchain()
        }
    );
    simgui.render();
    sg.endPass();
    sg.commit();
}

export fn cleanup(
) void 
{
    simgui.shutdown();
    zgui.deinit();
    zplot.deinit();
    sg.shutdown();
}

/// handle keypresses
export fn event(
    ev: [*c]const sapp.Event,
) void 
{
    _ = simgui.handleEvent(ev.*);

    // Check if the key event is a key press, and if it is the Escape key 
    if (
        ev.*.type == .KEY_DOWN
        and ev.*.key_code == .ESCAPE
    ) 
    { 
        // Quit the application 
        sapp.quit();
    }
}

const SokolApp = struct {
    title: [:0]const u8 = "Wrinkles Sokol Test",
    event: *const fn (ev: [*c]const sapp.Event) callconv(.C) void = &event,
    draw: *const fn () error{}!void,
    content_dir: []const u8 = "",
    dimensions: [2]i32 = .{ 800, 800 },
};
var app : SokolApp = undefined;

pub fn sokol_main(
    comptime app_in: SokolApp,
) void 
{
    app = app_in;
    content_dir = app.content_dir;

    sapp.run(
        .{
            .init_cb = init,
            .frame_cb = frame,
            .cleanup_cb = cleanup,
            .event_cb = app.event,
            .width = app.dimensions[0],
            .height = app.dimensions[1],
            .icon = .{ .sokol_default = true },
            .window_title = app.title,
            .logger = .{ .func = slog.func },
            .win32_console_attach = true,
        }
    );
}
