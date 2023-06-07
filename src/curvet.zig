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
const interval = opentime.interval;
const curve = opentime.curve;
const string = opentime.string;
const util = @import("opentime/util.zig");

const VisCurve = struct {
    original: struct{
        fpath: [:0]const u8,
        bezier: curve.TimeCurve,
        split_hodograph: curve.TimeCurve,
    },
    affine: curve.TimeCurve,
};

const VisState = struct {
    curves: []VisCurve,

    // xforms: std.ArrayList(CurveOperator),
    xforms: std.ArrayList(AffineTransformOpts),

    // const CurveOperator = union {
    //     .affine = AffineTransformOpts,
    //     .curve = CurveOpts,
    // }

    const AffineTransformOpts = struct{
        offset:f32 = 0,
        scale:f32 = 1,
        bound_input_min:f32 = -util.inf,
        bound_input_max:f32 =  util.inf,
        mode:i32 = @enumToInt(Modes.projected_through_curve),

        const Modes = enum(i32) {
            projected_through_curve,
            projecting_curve,
        };

        const modestring:[:0]const u8 = (
            ""
            ++ "Projected through Curve" ++ "\x00" 
            ++ "Projecting Curve" ++ "\x00"
            ++ "\x00"
        );
    };

    pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
        for (self.curves) |crv| {
            allocator.free(crv.original.bezier.segments);
            allocator.free(crv.original.split_hodograph.segments);
        }
        allocator.free(self.curves);
        self.xforms.deinit();
    }
};

const GraphicsState = struct {
    gctx: *zgpu.GraphicsContext,

    font_normal: zgui.Font,
    font_large: zgui.Font,

    // texture: zgpu.TextureHandle,
    texture_view: zgpu.TextureViewHandle,

    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        window: zglfw.Window
    ) !*GraphicsState 
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


        const gfx_state = try allocator.create(GraphicsState);
        gfx_state.* = .{
            .gctx = gctx,
            .texture_view = texture_view,
            .font_normal = font_normal,
            .font_large = font_large,
            .allocator = allocator,
        };

        return gfx_state;
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

    const gfx_state = GraphicsState.init(allocator, window) catch {
        std.log.err("Could not initialize resources", .{});
        return;
    };
    defer gfx_state.deinit();

    var state = try _parse_args(allocator);
    defer state.deinit(allocator);

    std.debug.assert(state.curves[0].original.bezier.segments.len > 0);
    std.debug.print("curve segments: {any}\n", .{ state.curves[0].original.bezier.segments.len });
    std.debug.print("curve extents: {any}\n", .{ state.curves[0].original.bezier.extents() });

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        try update(gfx_state, &state, allocator);
        draw(gfx_state);
    }
}


pub fn evaluated_curve(
    crv: curve.TimeCurve,
    comptime steps:usize
) !struct{ xv: [steps]f32, yv: [steps]f32 }
{
    const ext = crv.extents();
    const stepsize:f32 = (ext[1].time - ext[0].time) / @as(f32, steps);

    var xv:[steps]f32 = .{};
    var yv:[steps]f32 = .{};

    var i:usize = 0;
    var uv:f32 = ext[0].time;
    for (crv.segments) |seg| {
        uv = seg.p0.time;

        while (i < steps - 1) : (i += 1) {

            // guarantee that it hits the end point
            if (uv > seg.p3.time) {
                xv[i] = seg.p3.time;
                yv[i] = seg.p3.value;
                i += 1;

                break;
            }

            // should not ever be hit
            errdefer std.log.err(
                "error: uv was: {} extents: {any}\n",
                .{ uv, ext }
            );
            const p = try crv.evaluate(uv);

            xv[i] = uv;
            yv[i] = p;

            uv += stepsize;
        }
    }


    const end_point = crv.segments[crv.segments.len - 1].p3;

    xv[steps - 1] = end_point.time;
    yv[steps - 1] = end_point.value;

    return .{ .xv = xv, .yv = yv };
}

fn update(
    gfx_state: *GraphicsState,
    state: *VisState,
    allocator: std.mem.Allocator,
) !void 
{
    const xform_opt = state.xforms.items[0];
    const xform = opentime.transform.AffineTransform1D{
        .offset_seconds = xform_opt.offset,
        .scale = xform_opt.scale,
    };

    var tmp:[4]opentime.curve.ControlPoint = .{};

    // var affine_bounds_in_affine_input_space = (
    //     opentime.interval.ContinuousTimeInterval{ 
    //         .start_seconds = state.affine_transform.bound_input_min,
    //         .end_seconds = state.affine_transform.bound_input_max,
    //     }
    // );

    // transform the affine curve
    for (state.curves) |crv| {
        // const curve_extents = crv.extents();
        // const curve_output_bounds = interval.ContinuousTimeInterval{
        //     .start_seconds = curve_extents[0].value,
        //     .end_seconds = curve_extents[1].value,
        // };


        // switch (state.affine_transform.mode) {
        //     // affine bounds are applied to the input of the curve
        //     @enumToInt(VisState.AffineTransformOpts.Modes.projected_through_curve) => {
        //         // const curve_input_bounds = interval.ContinuousTimeInterval{
        //         //     .start_seconds = curve_extents[0].time,
        //         //     .end_seconds = curve_extents[1].time,
        //         // };
        //         // const affine_bounds_in_affine_output_space = (
        //         //     xform.applied_to_bounds(
        //         //         affine_bounds_in_affine_input_space
        //         //     )
        //         // );
        //         // const intersected_bounds = interval.intersect(
        //         //     curve_input_bounds,
        //         //     affine_bounds_in_affine_output_space
        //         // );
        //
        //         //
        //         // // if the curve needs to be trimmed
        //         // if (
        //         //     intersected_bounds.start_seconds 
        //         //     > curve_input_bounds.start_seconds
        //         // )
        //         // {
        //         //     const seg_to_split = crv.affine.find_segment(intersected_bounds.start_seconds);
        //         // }
        //     },
        //     else => {}
        // }

        // output of the curve is the input of the affine
        // affine bounds are applied to the output of the curve
        // @enumToInt(VisState.AffineTransformOpts.Modes.projecting_curve) => {
        //     tmp[pt_index] = .{ .time = pt.time, .value = xform.applied_to_seconds(pt.value)};
        //     crv.affine.segments[seg_index] = curve.Segment.from_pt_array(tmp);
        // },
        // output of the affine is the input of the curve
        for (crv.original.bezier.segments) |seg, seg_index| {
            for (seg.points()) |pt, pt_index| {
                switch (xform_opt.mode) {
                    // output of the curve is the input of the affine
                    // affine bounds are applied to the output of the curve
                    @enumToInt(VisState.AffineTransformOpts.Modes.projecting_curve) => {
                        tmp[pt_index] = .{ .time = pt.time, .value = xform.applied_to_seconds(pt.value)};
                        crv.affine.segments[seg_index] = curve.Segment.from_pt_array(tmp);
                    },
                    // output of the affine is the input of the curve
                    // affine bounds are applied to the input of the curve
                    @enumToInt(VisState.AffineTransformOpts.Modes.projected_through_curve) => {
                        tmp[pt_index] = .{ .value = pt.value, .time = xform.applied_to_seconds(pt.time)};
                        crv.affine.segments[seg_index] = curve.Segment.from_pt_array(tmp);
                    },
                    else => {},
                }
            }
        }
    }

    zgui.backend.newFrame(
        gfx_state.gctx.swapchain_descriptor.width,
        gfx_state.gctx.swapchain_descriptor.height,
    );

    zgui.setNextWindowPos(.{ .x = 0.0, .y = 0.0, });

    const size = gfx_state.gctx.window.getFramebufferSize();
    const width = @intToFloat(f32, size[0]);
    const height = @intToFloat(f32, size[1]);

    zgui.setNextWindowSize(.{ .w = width, .h = height, });

    var main_flags = zgui.WindowFlags.no_decoration;
    main_flags.no_resize = true;
    main_flags.no_background = true;
    main_flags.no_move = true;
    main_flags.no_scroll_with_mouse = true;
    main_flags.no_bring_to_front_on_focus = true;
    // main_flags.menu_bar = true;

    if (!zgui.begin("###FULLSCREEN", .{ .flags = main_flags })) {
        zgui.end();
        return;
    }

    // _ = zgui.showDemoWindow(null);

    {
        if (zgui.beginChild("Plot", .{ .w = width - 600 }))
        {

            if (zgui.plot.beginPlot("Curve Plot", .{ .h = -1.0 })) {
                zgui.plot.setupAxis(.x1, .{ .label = "input" });
                zgui.plot.setupAxis(.y1, .{ .label = "output" });

                for (state.curves) |viscurve| {
                    const bez = viscurve.original.bezier;
                    {
                        const pts = try evaluated_curve(bez, 1000);

                        zgui.plot.setupLegend(.{ .south = true, .west = true }, .{});
                        zgui.plot.setupFinish();

                        zgui.plot.plotLine(
                            viscurve.original.fpath,
                            f32,
                            .{ .xv = &pts.xv, .yv = &pts.yv }
                        );
                    }

                    {
                        const aff = viscurve.affine;
                        const pts = try evaluated_curve(aff, 1000);

                        const name = try std.fmt.allocPrintZ(
                            allocator,
                            "{s}: Affine Projection",
                            .{ viscurve.original.fpath }
                        );
                        defer allocator.free(name);

                        zgui.plot.plotLine(
                            name,
                            f32,
                            .{ .xv = &pts.xv, .yv = &pts.yv }
                        );
                    }

                    {
                        const name = try std.fmt.allocPrintZ(
                            allocator,
                            "{s}: Original Bezier Control Points",
                            .{ viscurve.original.fpath }
                        );
                        defer allocator.free(name);

                        const knots_xv = try allocator.alloc(f32, 4 * bez.segments.len);
                        defer allocator.free(knots_xv);
                        const knots_yv = try allocator.alloc(f32, 4 * bez.segments.len);
                        defer allocator.free(knots_yv);

                        for (bez.segments) |seg, seg_ind| {
                            for (seg.points()) |pt, pt_ind| {
                                knots_xv[seg_ind*4 + pt_ind] = pt.time;
                                knots_yv[seg_ind*4 + pt_ind] = pt.value;
                            }
                        }

                        zgui.plot.plotScatter(
                            name,
                            f32,
                            .{ 
                                .xv = knots_xv,
                                .yv = knots_yv,
                            }
                        );
                    }
                    
                    const hod = viscurve.original.split_hodograph;
                    {
                        const name = try std.fmt.allocPrintZ(
                            allocator,
                            "{s}: Split at critical points via Hodograph",
                            .{ viscurve.original.fpath }
                        );
                        defer allocator.free(name);

                        {
                            const pts = try evaluated_curve(hod, 1000);

                            zgui.plot.plotLine(
                                name,
                                f32,
                                .{ .xv = &pts.xv, .yv = &pts.yv }
                            );
                        }
                    }

                    {
                        const name = try std.fmt.allocPrintZ(
                            allocator,
                            "{s}: Split Hodograph Bezier Control Points",
                            .{ viscurve.original.fpath }
                        );
                        defer allocator.free(name);

                        const knots_xv = try allocator.alloc(f32, 4 * hod.segments.len);
                        defer allocator.free(knots_xv);
                        const knots_yv = try allocator.alloc(f32, 4 * hod.segments.len);
                        defer allocator.free(knots_yv);

                        for (bez.segments) |seg, seg_ind| {
                            for (seg.points()) |pt, pt_ind| {
                                knots_xv[seg_ind*4 + pt_ind] = pt.time;
                                knots_yv[seg_ind*4 + pt_ind] = pt.value;
                            }
                        }

                        zgui.plot.plotScatter(
                            name,
                            f32,
                            .{ 
                                .xv = knots_xv,
                                .yv = knots_yv,
                            }
                        );
                    }

                }

                zgui.plot.endPlot();
            }
        }
        defer zgui.endChild();
    }

    zgui.sameLine(.{});

    {
        if (zgui.beginChild("Settings", .{.w = 600, .flags = main_flags })) {
            for (state.xforms.items) |*this_xform| {

                // switch (this_xform) {
                //     .affine => |aff| { // generate affine ui }
                // }
                if (zgui.collapsingHeader("Affine Transform Settings", .{ .default_open = true})) {
                    var bounds:[2]f32 = .{
                        this_xform.bound_input_min, 
                        this_xform.bound_input_max, 
                    };
                    _ = zgui.sliderFloat(
                        "offset",
                        .{ 
                            .min = -10,
                            .max = 10,
                            .v = &this_xform.*.offset
                        }
                    );
                    _ = zgui.sliderFloat(
                        "scale",
                        .{ 
                            .min = -10,
                            .max = 10,
                            .v = &this_xform.*.scale
                        }
                    );
                    _ = zgui.inputFloat2("input space bounds", .{ .v = &bounds});
                    this_xform.bound_input_min = bounds[0];
                    this_xform.bound_input_max = bounds[1];
                    _ = zgui.combo(
                        "Mode",
                        .{
                            .current_item = &this_xform.mode,
                            .items_separated_by_zeros = VisState.AffineTransformOpts.modestring,
                        }
                    );
                }
            }

            var i:usize = 0;
            while (i<10) : (i+=1) {
            }
        }
        defer zgui.endChild();
    }

    // FPS/status line
    zgui.spacing();
    zgui.bulletText(
        "Average : {d:.3} ms/frame ({d:.1} fps)",
        .{ gfx_state.gctx.stats.average_cpu_time, gfx_state.gctx.stats.fps },
    );

    zgui.end();
}

fn draw(gfx_state: *GraphicsState) void {
    const gctx = gfx_state.gctx;

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

        var affine_crv = try curve.TimeCurve.init(crv.segments);

        var viscurve = VisCurve{
            .original = .{
                .fpath = fpath,
                .bezier = crv,
                .split_hodograph = try crv.split_hodograph(allocator),
            },
            .affine = affine_crv,
        };

        std.debug.assert(crv.segments.len > 0);

        try curves.append(viscurve);
    }

    var state = VisState{
        .curves = curves.items,
        .xforms = std.ArrayList(VisState.AffineTransformOpts).init(allocator),
    };

    try state.xforms.append(.{});
    // ^ is shorthand for this:
    // state.xforms.append(VisState.AffineTransformOpts{});

    if (state.curves.len == 0) {
        usage();
    }

    std.debug.assert(state.curves[0].original.bezier.segments.len > 0);

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
