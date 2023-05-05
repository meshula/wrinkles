// curve visualizer tool for opentime
const std = @import("std");

const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");
const zm = @import("zmath");
const zstbi = @import("zstbi");


const build_options = @import("build_options");
const content_dir = build_options.curvet_content_dir;

const opentime = @import("opentime/opentime.zig");
const curve = opentime.curve;
const string = opentime.string;

const VisCurve = struct {
    original: struct{
        fpath: [:0]const u8,
        bezier: curve.TimeCurve,
    },
};

const VisState = struct {
    curves: []VisCurve,
};

const DemoState = struct {
    gctx: *zgpu.GraphicsContext,

    font_normal: zgui.Font,
    font_large: zgui.Font,

    // texture: zgpu.TextureHandle,
    texture_view: zgpu.TextureViewHandle,

    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        window: zglfw.Window
    ) !*DemoState 
    {
        const gctx = try zgpu.GraphicsContext.create(allocator, window);

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        // Create a texture.
        zstbi.init(arena);
        defer zstbi.deinit();

        const font_path = content_dir ++ "genart_0025_5.png";

        var image = try zstbi.Image.init(font_path, 4);
        defer image.deinit();

        const texture = gctx.createTexture(.{
            .usage = .{ .texture_binding = true, .copy_dst = true },
            .size = .{
                .width = image.width,
                .height = image.height,
                .depth_or_array_layers = 1,
            },
            .format = .rgba8_unorm,
            .mip_level_count = 1,
        });
        const texture_view = gctx.createTextureView(texture, .{});

        gctx.queue.writeTexture(
            .{ .texture = gctx.lookupResource(texture).? },
            .{
                .bytes_per_row = image.bytes_per_row,
                .rows_per_image = image.height,
            },
            .{ .width = image.width, .height = image.height },
            u8,
            image.data,
        );

        zgui.init(allocator);
        zgui.plot.init();
        const scale_factor = scale_factor: {
            const scale = window.getContentScale();
            break :scale_factor std.math.max(scale[0], scale[1]);
        };

        // const fira_font_path = content_dir ++ "FiraCode-Medium.ttf";
        const robota_font_path = content_dir ++ "Roboto-Medium.ttf";

        const font_size = 16.0 * scale_factor;
        const font_large = zgui.io.addFontFromFile(robota_font_path, font_size * 1.1);
        const font_normal = zgui.io.addFontFromFile(robota_font_path, font_size);
        std.debug.assert(zgui.io.getFont(0) == font_large);
        std.debug.assert(zgui.io.getFont(1) == font_normal);

        // This needs to be called *after* adding your custom fonts.
        zgui.backend.init(
            window,
            gctx.device,
            @enumToInt(zgpu.GraphicsContext.swapchain_format)
        );

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

     
        const demo = try allocator.create(DemoState);
        demo.* = .{
            .gctx = gctx,
            .texture_view = texture_view,
            .font_normal = font_normal,
            .font_large = font_large,
            .allocator = allocator,
        };

        return demo;
    }

    fn deinit(self: *@This()) void {
        zgui.backend.deinit();
        zgui.plot.deinit();
        zgui.deinit();
        self.gctx.destroy(self.allocator);
        self.allocator.destroy(self);
    }
};

pub fn main() !void {
    zglfw.init() catch {
        std.log.err("GLFW did not initialize properly.", .{});
        return;
    };
    defer zglfw.terminate();

    zglfw.defaultWindowHints();
    zglfw.windowHint(.cocoa_retina_framebuffer, 1);
    zglfw.windowHint(.client_api, 0);

    const title = (
        "OpenTimelineIO V2 Prototype Bezier Curve Visualizer [" 
        ++ build_options.hash[0..6] 
        ++ "]"
    );

    const window = (
        zglfw.createWindow(1600, 1000, title, null, null) 
        catch {
            std.log.err("Could not create a window", .{});
            return;
        }
    );
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const demo = DemoState.init(allocator, window) catch {
        std.log.err("Could not initialize resources", .{});
        return;
    };
    defer demo.deinit();

    const state = try _parse_args(allocator);
    defer allocator.free(state.curves);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        update(demo, state);
        draw(demo);
    }
}

fn update(
    demo: *DemoState,
    state: VisState
) void 
{
    zgui.backend.newFrame(
        demo.gctx.swapchain_descriptor.width,
        demo.gctx.swapchain_descriptor.height,
    );

    zgui.setNextWindowPos(.{ .x = 0.0, .y = 0.0, .cond = .first_use_ever });
    zgui.setNextWindowSize(.{ .w = -1, .h = 1, .cond = .first_use_ever });

    var main_flags = zgui.WindowFlags.no_decoration;
    main_flags.no_resize = true;
    main_flags.no_background = true;
    main_flags.no_move = true;
    main_flags.no_scroll_with_mouse = true;
    main_flags.no_bring_to_front_on_focus = true;
    main_flags.menu_bar = true;
 
    if (!zgui.begin("###FULLSCREEN", .{ .flags = main_flags })) {
        zgui.end();
        return;
    }

    zgui.bulletText(
        "Average : {d:.3} ms/frame ({d:.1} fps)",
        .{ demo.gctx.stats.average_cpu_time, demo.gctx.stats.fps },
    );
    zgui.spacing();

    if (
        zgui.collapsingHeader(
            "Curves",
            .{
                .span_full_width = true,
                .default_open = true,
                .framed = true,
            }
            )
        ) 
    {
        for (state.curves) |viscurve| {
            if (zgui.collapsingHeader(viscurve.original.fpath, .{})) {
                if (zgui.plot.beginPlot(viscurve.original.fpath, .{ .h = -1.0 })) {
                    zgui.plot.setupAxis(.x1, .{ .label = "xaxis" });
                    zgui.plot.setupAxisLimits(.x1, .{ .min = 0, .max = 5 });
                    zgui.plot.setupLegend(.{ .south = true, .west = true }, .{});
                    zgui.plot.setupFinish();
                    zgui.plot.plotLineValues("y data", i32, .{ .v = &.{ 0, 1, 0, 1, 0, 1 } });
                    zgui.plot.plotLine("xy data", f32, .{
                        .xv = &.{ 0.1, 0.2, 0.5, 2.5 },
                        .yv = &.{ 0.1, 0.3, 0.5, 0.9 },
                    });
                    zgui.plot.endPlot();
                }
            }
        }
    }

    zgui.end();
}

fn draw(demo: *DemoState) void {
    const gctx = demo.gctx;

    const back_buffer_view = gctx.swapchain.getCurrentTextureView();
    defer back_buffer_view.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        // Gui pass.
        {
            const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                .view = back_buffer_view,
                .load_op = .load,
                .store_op = .store,
            }};
            const render_pass_info = wgpu.RenderPassDescriptor{
                .color_attachment_count = color_attachments.len,
                .color_attachments = &color_attachments,
            };
            const pass = encoder.beginRenderPass(render_pass_info);
            defer {
                pass.end();
                pass.release();
            }

            zgui.backend.draw(pass);
        }

        break :commands encoder.finish(null);
    };
    defer commands.release();

    gctx.submit(&.{commands});
    _ = gctx.present();
}

/// parse the commandline arguments and setup the state
fn _parse_args(
    allocator: std.mem.Allocator
) !VisState 
{
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // ignore the app name, always first in args
    _ = args.skip();

    // inline for (std.meta.fields(@TypeOf(state))) |field| {
    //     std.debug.print("{s}: {}\n", .{ field.name, @field(state, field.name) });
    // }

    var curves = std.ArrayList(VisCurve).init(allocator);

    // read all the filepaths from the commandline
    while (args.next()) |nextarg| 
    {
        var fpath: [:0]const u8 = nextarg;

        if (
            string.eql_latin_s8(fpath, "--help")
            or (string.eql_latin_s8(fpath, "-h"))
        ) {
            usage();
        }

        std.debug.print("reading curve: {s}\n", .{ fpath });

        var crv = curve.read_curve_json(fpath, allocator) catch |err| {
            std.debug.print(
                "Something went wrong reading: '{s}'\n",
                .{ fpath }
            );

            return err;
        };
        defer allocator.free(crv.segments);

        var viscurve = VisCurve{
            .original = .{
                .fpath = fpath,
                .bezier = crv 
            }
        };

       try curves.append(viscurve);
    }

    var state = VisState{
        .curves = curves.items,
    };

    if (state.curves.len == 0) {
        usage();
    }

    return state;
}

/// print the usage message out and quit
pub fn usage() void {
    std.debug.print(
        \\
        \\usage:
        \\  curvet path/to/seg1.json [path/to/seg2.json] [...] [args]
        \\
        \\arguments:
        \\  -h --help: print this message and exit
        \\
        \\
        , .{}
    );
    std.os.exit(1);
}
