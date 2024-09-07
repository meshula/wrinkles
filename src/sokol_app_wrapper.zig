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

var content_dir : []const u8 = undefined;

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

    {
        const scale_factor = c.sokol.app.sapp_dpi_scale();


        const robota_font_path = std.fs.path.joinZ(
            gfx_allocator,
            &.{ content_dir, "Roboto-Medium.ttf" }
        ) catch @panic("couldn't find font");
        defer gfx_allocator.free(robota_font_path);

        const font_size = 16.0 * scale_factor;
        const font_large = zgui.io.addFontFromFile(
            robota_font_path,
            font_size * 1.1
        );
        _ = font_large;
        // std.debug.assert(zgui.io.getFont(0) == font_large);

        const font_normal = zgui.io.addFontFromFile(
            robota_font_path,
            font_size
        );
        // std.debug.assert(zgui.io.getFont(1) == font_normal);

        // This call is optional. Initially, zgui.io.getFont(0) is a default font.
        zgui.io.setDefaultFont(font_normal);

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
    var new_frame: c.simgui_frame_desc_t = .{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    };
    c.simgui_new_frame(&new_frame);

    app.draw() catch |err| {
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

const SokolApp = struct {
    title: [:0]const u8 = "Wrinkles Sokol Test",
    event: *const fn (ev: [*c]const sapp.Event) callconv(.C) void = &event,
    draw: *const fn () error{}!void,
    content_dir: []const u8 = "",
    dimensions: [2]i32 = .{ 800, 800 },
};
var app : SokolApp = undefined;

pub fn main(
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
