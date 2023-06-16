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
    fpath: [:0]u8,
    curve: curve.TimeCurve,
    split_hodograph: curve.TimeCurve,
    active: bool = true,
};

const projTmpTest = struct {
    fst: VisCurve,
    snd: VisCurve,
};

fn _is_between(val: f32, fst: f32, snd: f32) bool {
    return ((fst <= val and val < snd) or (fst >= val and val > snd));
}

const VisTransform = struct {
    topology: opentime.time_topology.AffineTopology = .{},
    active: bool = true,
};

const VisOperation = union(enum) {
    curve: VisCurve,
    transform: VisTransform,
};

const VisState = struct {
    operations: std.ArrayList(VisOperation),

    pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
        for (self.operations.items) |visop| {
            switch (visop) {
                .curve => |crv| {
                    allocator.free(crv.curve.segments);
                    allocator.free(crv.split_hodograph.segments);
                    allocator.free(crv.fpath);
                },
                else => {},
            }
        }
        self.operations.deinit();
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
    var pbuf:[1024:0]u8 = .{};
    var u_path:[:0]u8 = try std.fmt.bufPrintZ(
        &pbuf,
        "{s}",
        .{ "curves/upside_down_u.curve.json" }
    );
    const u_curve = try curve.read_curve_json(u_path, allocator);
    defer u_curve.deinit(allocator);

    // const identSeg_half = curve.create_linear_segment(
    //     .{ .time = -2, .value = -1 },
    //     .{ .time = 2, .value = 1 },
    // );
    // const lin_half = try curve.TimeCurve.init(&.{identSeg_half});
    // const lin_name_half = try std.fmt.bufPrintZ(
    //     pbuf[512..],
    //     "{s}",
    //     .{  "linear slope of 0.5 [-2, 2)" }
    // );


    const identSeg = curve.create_identity_segment(-0.2, 1) ;
    const lin = try curve.TimeCurve.init(&.{identSeg});
    const lin_name = try std.fmt.bufPrintZ(
        pbuf[512..],
        "{s}",
        .{  "linear [0, 1)" }
    );
    const tmpCurves = projTmpTest{
        .fst = .{ 
            .curve = u_curve,
            // .curve = lin_half,
            .fpath = u_path,
            // .fpath = lin_name_half,
            // .split_hodograph = try lin_half.split_on_critical_points(allocator),
            .split_hodograph = try u_curve.split_on_critical_points(allocator),
        },
        .snd = .{ 
            .curve = lin,
            .fpath = lin_name,
            .split_hodograph = try lin.split_on_critical_points(allocator),
        },
    };
    defer tmpCurves.fst.split_hodograph.deinit(allocator);
    defer tmpCurves.snd.split_hodograph.deinit(allocator);
    defer state.deinit(allocator);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        try update(gfx_state, &state, tmpCurves, allocator);
        draw(gfx_state);
    }
}


pub fn evaluated_curve(
    crv: curve.TimeCurve,
    comptime steps:usize
) !struct{ xv: [steps]f32, yv: [steps]f32 }
{
    if (crv.segments.len == 0) {
        return .{ .xv = .{}, .yv = .{} };
    }

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

    if (crv.segments.len > 0) {
        const end_point = crv.segments[crv.segments.len - 1].p3;

        xv[steps - 1] = end_point.time;
        yv[steps - 1] = end_point.value;
    }

    return .{ .xv = xv, .yv = yv };
}

fn plot_knots(
    hod: curve.TimeCurve, 
    name: [:0]const u8,
    allocator: std.mem.Allocator,
) !void 
{
    var buf:[1024:0]u8 = .{};
    std.mem.set(u8, &buf, 0);

    {
        const name_ = try std.fmt.bufPrintZ(
            &buf,
            "{s}: Bezier Control Points",
            .{name}
        );

        const knots_xv = try allocator.alloc(f32, hod.segments.len + 1);
        defer allocator.free(knots_xv);
        const knots_yv = try allocator.alloc(f32, hod.segments.len + 1);
        defer allocator.free(knots_yv);

        for (try hod.segment_endpoints()) |knot, knot_ind| {
            knots_xv[knot_ind] = knot.time;
            knots_yv[knot_ind] = knot.value;
        }

        zgui.plot.plotScatter(
            name_,
            f32,
            .{
                .xv = knots_xv,
                .yv = knots_yv,
            }
        );
    }
}

fn plot_control_points(
    hod: curve.TimeCurve, 
    name: [:0]const u8,
    allocator: std.mem.Allocator,
) !void 
{
    var buf:[1024:0]u8 = .{};
    std.mem.set(u8, &buf, 0);

    {
        const name_ = try std.fmt.bufPrintZ(
            &buf,
            "{s}: Bezier Control Points",
            .{name}
        );

        const knots_xv = try allocator.alloc(f32, 4 * hod.segments.len);
        defer allocator.free(knots_xv);
        const knots_yv = try allocator.alloc(f32, 4 * hod.segments.len);
        defer allocator.free(knots_yv);

        for (hod.segments) |seg, seg_ind| {
            for (seg.points()) |pt, pt_ind| {
                knots_xv[seg_ind * 4 + pt_ind] = pt.time;
                knots_yv[seg_ind * 4 + pt_ind] = pt.value;
            }
        }

        zgui.plot.plotScatter(
            name_,
            f32,
            .{
                .xv = knots_xv,
                .yv = knots_yv,
            }
        );
    }
}

fn plot_bezier_curve(
    crv:curve.TimeCurve,
    name:[:0]const u8,
    allocator:std.mem.Allocator
) !void {
    const pts = try evaluated_curve(crv, 1000);

    zgui.plot.plotLine(
        name,
        f32,
        .{ .xv = &pts.xv, .yv = &pts.yv }
    );

    try plot_control_points(crv, name, allocator);
}

fn plot_curve(
    crv: VisCurve,
    name: [:0]const u8,
    allocator: std.mem.Allocator,
) !void 
{
    try plot_bezier_curve(crv.curve, name, allocator);
}

fn update(
    gfx_state: *GraphicsState,
    state: *VisState,
    tmpCurves: projTmpTest,
    allocator: std.mem.Allocator,
) !void {
    var _proj = opentime.TimeTopology.init_identity_infinite();
    for (state.operations.items) |visop| {
        var _topology: opentime.TimeTopology = .{ .empty = .{} };
        switch (visop) {
            .transform => |xform| {
                if (!xform.active) {
                    continue;
                } else {
                    _topology = .{ .affine = xform.topology };
                }
            },
            .curve => |crv| {
                if (!crv.active) {
                    continue;
                } else {
                    _topology = .{ .bezier_curve = .{ .curve = crv.curve } };
                }
            },
        }
        _proj = try _topology.project_topology(_proj);
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


    // FPS/status line
    zgui.bulletText(
        "Average : {d:.3} ms/frame ({d:.1} fps)",
        .{ gfx_state.gctx.stats.average_cpu_time, gfx_state.gctx.stats.fps },
    );
    zgui.spacing();

    _ = zgui.showDemoWindow(null);

    var tmp_buf:[1024:0]u8 = .{};
    std.mem.set(u8, &tmp_buf, 0);

    {
        if (zgui.beginChild("Plot", .{ .w = width - 600 }))
        {

            if (zgui.plot.beginPlot("Curve Plot", .{ .h = -1.0 })) {
                zgui.plot.setupAxis(.x1, .{ .label = "input" });
                zgui.plot.setupAxis(.y1, .{ .label = "output" });
                zgui.plot.setupLegend(
                    .{ 
                        .south = true,
                        .west = true 
                    },
                    .{}
                );
                zgui.plot.setupFinish();
                for (state.operations.items) |visop, op_index| {
                    switch (visop) {
                        .curve => |crv| {
                            const name = try std.fmt.bufPrintZ(
                                &tmp_buf,
                                "{d}: Bezier Curve / {s}",
                                .{op_index, crv.fpath[0..]}
                            );

                            try plot_curve(crv, name, allocator);
                        },
                        else => {},
                    }
                }
                switch (_proj) {
                    .linear_curve => |lint| { 
                        const lin = lint.curve;
                        var xv:[]f32 = try allocator.alloc(f32, lin.knots.len);
                        defer allocator.free(xv);
                        var yv:[]f32 = try allocator.alloc(f32, lin.knots.len);
                        defer allocator.free(yv);
                        
                        for (lin.knots) |knot, knot_index| {
                            xv[knot_index] = knot.time;
                            yv[knot_index] = knot.value;
                        }

                        zgui.plot.plotLine(
                            "result [linear]",
                            f32,
                            .{ .xv = xv, .yv = yv }
                        );
                    },
                    .bezier_curve => |bez| {
                        const pts = try evaluated_curve(bez.curve, 1000);

                        zgui.plot.plotLine(
                            "result [bezier]",
                            f32,
                            .{ .xv = &pts.xv, .yv = &pts.yv }
                        );
                    },
                    .affine =>  {
                        zgui.plot.plotLine(
                            "NO RESULT: AFFINE",
                            f32,
                            .{ 
                                .xv = &[_] f32{},
                                .yv = &[_] f32{},
                            }
                        );
                    },
                    .empty => {
                        zgui.plot.plotLine(
                            "EMPTY RESULT",
                            f32,
                            .{ 
                                .xv = &[_] f32{},
                                .yv = &[_] f32{},
                            }
                        );
                    },
                }

                // debug 
                const self = tmpCurves.fst.curve;
                const other = tmpCurves.snd.curve;

                try plot_bezier_curve(self, "self", allocator);
                try plot_bezier_curve(other, "other", allocator);

                const self_hodograph = try self.split_on_critical_points(allocator);
                try plot_bezier_curve(self_hodograph, "self hodograph", allocator);
                defer self_hodograph.deinit(allocator);
                try plot_knots(self_hodograph, "hodograph knots", allocator);
                const other_hodograph = try other.split_on_critical_points(allocator);
                try plot_bezier_curve(other_hodograph, "other hodograph", allocator);
                defer other_hodograph.deinit(allocator);

                const other_bounds = other.extents();
                var other_copy = try curve.TimeCurve.init(other_hodograph.segments);
                defer other_copy.deinit(allocator);

                {
                    {
                        var split_points = std.ArrayList(f32).init(allocator);
                        defer split_points.deinit();

                        // find all knots in self that are within the other bounds
                        for (self_hodograph.segment_endpoints() catch unreachable)
                            |self_knot| 
                            {
                                if (
                                    _is_between(
                                        self_knot.time,
                                        other_bounds[0].value,
                                        other_bounds[1].value
                                    )
                                ) {
                                    split_points.append(self_knot.time) catch unreachable;
                                }

                            }
                        other_copy = other_copy.split_at_each_output_ordinate(
                            split_points.items,
                            allocator
                        ) catch unreachable;
                    }
                }

                try plot_knots(other_copy, "other copy knots", allocator);
                try plot_bezier_curve(other_copy, "other copy", allocator);

                // const result = self_hodograph.project_curve(other_hodograph);
                // var buf:[1024:0]u8 = .{};
                // std.mem.set(u8, &buf, 0);
                // const result_name = try std.fmt.bufPrintZ(
                //     &buf,
                //     "result of projection{s}",
                //     .{
                //         if (result.segments.len > 0) "" 
                //         else " [NO SEGMENTS/EMPTY]",
                //     }
                // );
                //
                // try plot_knots(result, result_name, allocator);
                // try plot_bezier_curve(result, result_name, allocator);

                zgui.plot.endPlot();
            }
        }
        defer zgui.endChild();
    }

    zgui.sameLine(.{});

    {
        if (zgui.beginChild("Settings", .{ .w = 600, .flags = main_flags })) {
            var remove = std.ArrayList(usize).init(allocator);
            defer remove.deinit();
            var op_index:usize = 0;
            for (state.operations.items) |*visop| {
                switch (visop.*) {
                    .curve => |*crv| {
                        zgui.pushPtrId(@ptrCast(*const anyopaque, crv));
                        defer zgui.popId();
                        if (
                            zgui.collapsingHeader(
                                "Curve Settings",
                                .{ .default_open = true }
                            )
                        )
                        {
                            zgui.pushPtrId(&crv.active);
                            defer zgui.popId();
                            _ = zgui.checkbox("Active", .{.v = &crv.active});
                            zgui.sameLine(.{});
                            if (zgui.smallButton("Remove")) {
                                try remove.append(op_index);
                            }
                            zgui.text(
                                "file path: {s}",
                                .{ crv.*.fpath[0..] }
                            );
                        }
                    },
                    .transform => |*xform| {
                        if (
                            zgui.collapsingHeader(
                                "Affine Transform Settings",
                                .{ .default_open = true }
                            )
                        ) 
                        {
                            _ = zgui.checkbox("Active", .{.v = &xform.active});
                            zgui.sameLine(.{});
                            if (zgui.smallButton("Remove")) {
                                try remove.append(op_index);
                            }
                            var bounds: [2]f32 = .{
                                xform.topology.bounds.start_seconds,
                                xform.topology.bounds.end_seconds,
                            };
                            _ = zgui.sliderFloat(
                                "offset",
                                .{
                                    .min = -10,
                                    .max = 10,
                                    .v = &xform.topology.transform.offset_seconds
                                }
                            );
                            _ = zgui.sliderFloat(
                                "scale",
                                .{
                                    .min = -10,
                                    .max = 10,
                                    .v = &xform.topology.transform.scale
                                }
                            );
                            _ = zgui.inputFloat2(
                                "input space bounds",
                                .{ .v = &bounds }
                            );
                            xform.topology.bounds.start_seconds = bounds[0];
                            xform.topology.bounds.end_seconds = bounds[1];
                        }
                    },
                }
            }
            if (zgui.smallButton("Add")) {
                // @TODO: after updating to zig 0.11
                // zgui.openPopup("Delete?");
            }

            // Remove any "remove"'d operations
            var i:usize = remove.items.len;
            while (i > 0) {
                i -= 1;
                var visop = state.operations.orderedRemove(remove.items[i]);
                switch (visop) {
                    .curve => |crv| {
                        allocator.free(crv.curve.segments);
                        allocator.free(crv.split_hodograph.segments);
                        allocator.free(crv.fpath);
                    },
                    else => {},
                }
            }
        }
        defer zgui.endChild();
    }

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

    var operations = std.ArrayList(VisOperation).init(allocator);

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

        std.debug.print("reading curve: '{s}'\n", .{ fpath });

        var crv = curve.read_curve_json(fpath, allocator) catch |err| {
            std.debug.print(
                "Something went wrong reading: '{s}'\n",
                .{ fpath }
            );

            return err;
        };

        var viscurve = VisCurve{
            .fpath = try allocator.dupeZ(u8, fpath),
            .curve = crv,
            .split_hodograph = try crv.split_on_critical_points(allocator),
        };

        std.debug.assert(crv.segments.len > 0);
        var visoperation = VisOperation{ .curve = viscurve };
        try operations.append(visoperation);
    }

    var state = VisState{
        .operations = operations,
    };

    try state.operations.append(.{ .transform = .{} });

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
