// curve visualizer tool for opentime
const std = @import("std");

// sokol
const ig = @import("cimgui");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const simgui = sokol.imgui;

const zgui = @import("zgui");

const build_options = @import("build_options");
const content_dir = build_options.curvet_content_dir;

const opentime = @import("opentime");
const interval = opentime.interval;
const curve = @import("curve");
const string = @import("string_stuff");
const time_topology = @import("time_topology");
const util = opentime.util;

const DERIVATIVE_STEPS = 10;
const CURVE_SAMPLE_COUNT = 1000;

const DebugBezierFlags = struct {
    bezier: bool = true,
    knots: bool = false,
    control_points: bool = false,
    linearized: bool = false,
    find_u_test: bool = false,
    natural_midpoint: bool = false,
    derivatives_ddu: bool = false,
    derivatives_dydx: bool = false,
    derivatives_dydx_isect: bool = false,
    derivatives_hodo_ddu: bool = false,
    show_dydx_point: bool = false,
    show_decastlejau_point: bool = false,
    sample_point: f32 = 0,

    pub fn draw_ui(
        self: * @This(),
        name: [:0]const u8
    ) void 
    {
        if (zgui.treeNodeFlags(name, .{ .default_open = true })) 
        {
            defer zgui.treePop();
            const fields = .{
                .{ "Draw Bezier Curves", "bezier"},
                .{ "Draw Knots", "knots"},
                .{ "Draw Control Points", "control_points" },
                .{ "Draw Linearized", "linearized" },
                .{ "Draw Find U Test", "find_u_test" },
                .{ "Natural Midpoint (t=0.5)", "natural_midpoint" },
                .{ "Show Derivatives (d/du)", "derivatives_ddu" },
                .{ "Show Derivatives (dy/dx)", "derivatives_dydx" },
                .{ "Show dy/dx intersection point", "derivatives_dydx_isect" },
                .{ "Show dy/dx at sample point", "show_dydx_point" },
                .{ "Show DeCastlejau at sample point", "show_decastlejau_point" },
                .{ "Show Derivatives (hodograph d/du)", "derivatives_hodo_ddu" },
            };

            zgui.pushStrId(name);

            inline for (fields) 
                |field| 
            {
                // unpack into a bool type
                var c_value:bool = @field(self, field[1]);
                _ = zgui.checkbox(field[0], .{ .v = &c_value,});
                // pack back into the alzguined field
                @field(self, field[1]) = c_value;

            }

            _ = zgui.sliderFloat(
                "sample point",
                .{
                    .v = &self.sample_point,
                    .min = 0,
                    .max = 1,
                },
            );

            zgui.popId();
        }
    }
};

const two_point_approx_flags = struct {
    result_curves: DebugBezierFlags = .{ .bezier = true },

    pub fn draw_ui(self: *@This(), name: [:0]const u8) void {
        if (zgui.treeNode(name)) 
        {
            defer zgui.treePop();

            self.result_curves.draw_ui("result of two point approximation");

            // const fields = .{
            // };
            //
            // if (zgui.treeNode("two Point Approx internals")) 
            // {
            //     defer zgui.treePop();
            //     inline for (fields) |field| {
            //         _ = zgui.checkbox(field, .{ .v = & @field(self, field) });
            //     }
            // }
        }
    }
};

const tpa_flags = struct {
    result_curves: DebugBezierFlags = .{ .bezier = true },
    start: bool = false,
    start_ddt: bool = false,
    A: bool = false,
    midpoint: bool = false,
    C: bool = false,
    end: bool = false,
    end_ddt: bool = false,
    e1_2: bool = false,
    v1_2: bool = false,
    C1_2: bool = false,
    u_0: bool = false,
    u_1_4: bool = false,
    u_1_2: bool = false,
    u_3_4: bool = false,
    u_1: bool = false,

    pub fn draw_ui(self: *@This(), name: [:0]const u8) void {
        if (zgui.treeNode(name)) 
        {
            defer zgui.treePop();
            self.result_curves.draw_ui("result of three point approx");

            const fields = .{
                "start",
                "start_ddt",
                "A", 
                "midpoint", 
                "C",
                "end",
                "end_ddt",
                "e1_2",
                "v1_2",
                "C1_2",
                "u_0",
                "u_1_4",
                "u_1_2",
                "u_3_4",
                "u_1",
            };

            if (zgui.treeNode("Three Point Approx internals")) 
            {
                defer zgui.treePop();
                inline for (fields) |field| {
                    _ = zgui.checkbox(field, .{ .v = & @field(self, field) });
                }
            }
        }
    }
};

const DebugDrawCurveFlags = struct {
    input_curve: DebugBezierFlags = .{},
    split_critical_points: DebugBezierFlags = .{ .bezier = false },
    three_point_approximation: tpa_flags = .{
        .result_curves = .{ .bezier = false },
        .midpoint = true,
        .e1_2 = true,
    },
    two_point_approx: two_point_approx_flags = .{},

    pub fn draw_ui(self: *@This(), name: []const u8) void {
        zgui.pushStrId(name);
        self.input_curve.draw_ui("input_curve");
        self.split_critical_points.draw_ui("split on critical points");
        self.three_point_approximation.draw_ui("three point approximation");
        self.two_point_approx.draw_ui("two point approximation");
        zgui.popId();
    }
};

const VisCurve = struct {
    fpath: [:0]const u8,
    curve: curve.TimeCurve,
    split_hodograph: curve.TimeCurve,
    active: bool = true,
    editable: bool = false,
    show_approximation: bool = false,
    draw_flags: DebugDrawCurveFlags = .{},
};

const projTmpTest = struct {
    fst: VisCurve,
    snd: VisCurve,
};

fn _is_between(val: f32, fst: f32, snd: f32) bool {
    return ((fst <= val and val < snd) or (fst >= val and val > snd));
}

const VisTransform = struct {
    topology: time_topology.AffineTopology = .{},
    active: bool = true,
};

const VisOperation = union(enum) {
    curve: VisCurve,
    transform: VisTransform,
};

const ProjectionResultDebugFlags = struct {
    fst: DebugBezierFlags = .{},
    self_split: DebugBezierFlags = .{},
    snd: DebugBezierFlags = .{},
    other_split: DebugBezierFlags = .{},
    tpa_flags: tpa_flags = .{},
    to_project: DebugBezierFlags = .{},
};

const VisState = struct {
    operations: std.ArrayList(VisOperation),
    show_demo: bool = false,
    show_test_curves: bool = false,
    show_projection_result: bool = false,
    show_projection_result_guts: ProjectionResultDebugFlags = .{},
    midpoint_derivatives: bool = false,
    f_prime_of_g_of_t: bool = false,
    g_prime_of_t: bool = false,

    pub fn deinit(
        self: *const @This(),
        allocator: std.mem.Allocator
    ) void 
    {
        for (self.operations.items) 
            |visop| 
        {
            switch (visop) 
            {
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

// const GraphicsState = struct {
//     gctx: *zgpu.GraphicsContext,
//
//     font_normal: zgui.Font,
//     font_large: zgui.Font,
//
//     // texture: zgpu.TextureHandle,
//     texture_view: zgpu.TextureViewHandle,
//
//     allocator: std.mem.Allocator,
//
//     pub fn init(
//         allocator: std.mem.Allocator,
//         window: *zglfw.Window
//     ) !*GraphicsState 
//     {
//         const gctx = try zgpu.GraphicsContext.create(
//             allocator,
//             .{
//                 .window  = window,
//                 .fn_getTime = @ptrCast(&zglfw.getTime),
//                 .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),
//                 .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
//                 .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
//                 .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
//                 .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
//             },
//             .{}
//         );
//
//         var arena_state = std.heap.ArenaAllocator.init(allocator);
//         defer arena_state.deinit();
//         const arena = arena_state.allocator();
//
//         // Create a texture.
//         zstbi.init(arena);
//         defer zstbi.deinit();
//
//         const font_path = content_dir ++ "genart_0025_5.png";
//
//         var image = try zstbi.Image.loadFromFile(font_path, 4);
//         defer image.deinit();
//
//         const texture = gctx.createTexture(.{
//             .usage = .{ .texture_binding = true, .copy_dst = true },
//             .size = .{
//                 .width = image.width,
//                 .height = image.height,
//                 .depth_or_array_layers = 1,
//             },
//             .format = .rgba8_unorm,
//             .mip_level_count = 1,
//         });
//         const texture_view = gctx.createTextureView(texture, .{});
//
//         gctx.queue.writeTexture(
//             .{ .texture = gctx.lookupResource(texture).? },
//             .{
//                 .bytes_per_row = image.bytes_per_row,
//                 .rows_per_image = image.height,
//             },
//             .{ .width = image.width, .height = image.height },
//             u8,
//             image.data,
//         );
//
//         zgui.init(allocator);
//         zgui.plot.init();
//         const scale_factor = scale_factor: {
//             const scale = window.getContentScale();
//             break :scale_factor @max(scale[0], scale[1]);
//         };
//
//         // const fira_font_path = content_dir ++ "FiraCode-Medium.ttf";
//         const robota_font_path = content_dir ++ "Roboto-Medium.ttf";
//
//         const font_size = 16.0 * scale_factor;
//         const font_large = zgui.io.addFontFromFile(
//             robota_font_path,
//             font_size * 1.1
//         );
//         const font_normal = zgui.io.addFontFromFile(
//             robota_font_path,
//             font_size
//         );
//         std.debug.assert(zgui.io.getFont(0) == font_large);
//         std.debug.assert(zgui.io.getFont(1) == font_normal);
//
//         // This needs to be called *after* adding your custom fonts.
//         zgui.backend.init(
//             window,
//             gctx.device,
//             @intFromEnum(zgpu.GraphicsContext.swapchain_format),
//             @intFromEnum(zgpu.wgpu.TextureFormat.undef),
//         );
//
//         // This call is optional. Initially, zgui.io.getFont(0) is a default font.
//         zgui.io.setDefaultFont(font_normal);
//
//         // You can directly manipulate zgui.Style *before* `newFrame()` call.
//         // Once frame is started (after `newFrame()` call) you have to use
//         // zgui.pushStyleColor*()/zgui.pushStyleVar*() functions.
//         const style = zgui.getStyle();
//
//         style.window_min_size = .{ 320.0, 240.0 };
//         style.window_border_size = 8.0;
//         style.scrollbar_size = 6.0;
//         {
//             var color = style.getColor(.scrollbar_grab);
//             color[1] = 0.8;
//             style.setColor(.scrollbar_grab, color);
//         }
//         style.scaleAllSizes(scale_factor);
//
//         // To reset zgui.Style with default values:
//         //zgui.getStyle().* = zgui.Style.init();
//
//         {
//             zgui.plot.getStyle().line_weight = 3.0;
//             const plot_style = zgui.plot.getStyle();
//             plot_style.marker = .circle;
//             plot_style.marker_size = 5.0;
//         }
//
//
//         const gfx_state = try allocator.create(GraphicsState);
//         gfx_state.* = .{
//             .gctx = gctx,
//             .texture_view = texture_view,
//             .font_normal = font_normal,
//             .font_large = font_large,
//             .allocator = allocator,
//         };
//
//         return gfx_state;
//     }
//
//     fn deinit(self: *@This()) void {
//         zgui.backend.deinit();
//         zgui.plot.deinit();
//         zgui.deinit();
//         self.gctx.destroy(self.allocator);
//         self.allocator.destroy(self);
//     }
// };

const sokol_state = struct {
    var pass_action: sg.PassAction = .{};
};

export fn init() void 
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
    sokol_state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
    };

    const io = ig.igGetIO();
    io.*.ConfigFlags |= ig.ImGuiConfigFlags_DockingEnable;
}

var STATE: VisState = undefined;
var ALLOCATOR: std.mem.Allocator = undefined;

export fn frame() void 
{
    // call simgui.newFrame() before any ImGui calls
    simgui.newFrame(
        .{
            .width = sapp.width(),
            .height = sapp.height(),
            .delta_time = sapp.frameDuration(),
            .dpi_scale = sapp.dpiScale(),
        }
    );

    //=== UI CODE STARTS HERE
    update(&STATE, ALLOCATOR) catch unreachable;

    // create a new ImGui window and set it up as the main docking window. This
    // will create a new docking space and set it as the main docking space.

    // get the main viewport
    const hostWindowFlags = ig.ImGuiWindowFlags_NoCollapse;
    ig.igSetNextWindowSize(.{ .x = 600, .y = 600 }, ig.ImGuiCond_Once);
    const dockId = ig.igGetID_Str("DockSpace");
    _ = ig.igBegin("Docking Space", 0, hostWindowFlags);
    _ = ig.igDockSpace(dockId, .{ .x = 0, .y = 0 }, ig.ImGuiDockNodeFlags_None, null);
    ig.igEnd();

    ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once, .{ .x = 0, .y = 0 });
    ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
    _ = ig.igBegin("Hello Dear ImGui!", 0, ig.ImGuiWindowFlags_None);
    _ = ig.igColorEdit3("Background", &sokol_state.pass_action.colors[0].clear_value.r, ig.ImGuiColorEditFlags_None);
    ig.igEnd();

    // make a second window to test the dock.
    ig.igSetNextWindowPos(.{ .x = 10, .y = 120 }, ig.ImGuiCond_Once, .{ .x = 0, .y = 0 });
    ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
    _ = ig.igBegin("Hello Dear ImGui 2!", 0, ig.ImGuiWindowFlags_None);
    _ = ig.igColorEdit3("Background 2", &sokol_state.pass_action.colors[0].clear_value.g, ig.ImGuiColorEditFlags_None);
    ig.igEnd();

    //=== UI CODE ENDS HERE

    // call simgui.render() inside a sokol-gfx pass
    sg.beginPass(.{ .action = sokol_state.pass_action, .swapchain = sglue.swapchain() });
    simgui.render();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    simgui.shutdown();
    sg.shutdown();
}

export fn event(ev: [*c]const sapp.Event) void {
    // forward input events to sokol-imgui
    _ = simgui.handleEvent(ev.*);
}

pub fn main() !void 
{
    // zglfw.init() catch {
    //     std.log.err("GLFW did not initialize properly.", .{});
    //     return;
    // };
    // defer zglfw.terminate();

    // zglfw.WindowHint.set(.cocoa_retina_framebuffer, 1);
    // zglfw.WindowHint.set(.client_api, 0);

    const title = (
        "OpenTimelineIO V2 Prototype Bezier Curve Visualizer [" 
        ++ build_options.hash[0..6] 
        ++ "]"
    );
    _ = title;

    // const window = (
    //     zglfw.Window.create(1600, 1000, title, null) 
    //     catch {
    //         std.log.err("Could not create a window", .{});
    //         return;
    //     }
    // );
    // defer window.destroy();
    // window.setSizeLimits(400, 400, -1, -1);

    var gpa = std.heap.GeneralPurposeAllocator(.{.stack_trace_frames = 32}){};
    defer _ = gpa.deinit();

    ALLOCATOR = gpa.allocator();

    // const gfx_state = GraphicsState.init(allocator, window) catch {
    //     std.log.err("Could not initialize resources", .{});
    //     return;
    // };
    // defer gfx_state.deinit();

    STATE = try _parse_args(ALLOCATOR);

    // u
    // const fst_name:[:0]const u8 = "upside down u";
    // const fst_crv = try curve.read_curve_json(
    //     "curves/upside_down_u.curve.json" ,
    //     allocator
    // );
    // defer fst_crv.deinit(allocator);
    //
    // // const identSeg = curve.Segment.init_identity(-0.2, 1) ;
    // const identSeg = curve.Segment.init_identity(-3, 3) ;
    // const snd_crv = try curve.TimeCurve.init(
    //     allocator,
    //     &.{identSeg}
    // );
    // defer snd_crv.deinit(allocator);
    // const snd_name:[:0]const u8 ="linear [-0.2, 1)" ;
    //
    // var tmpCurves = projTmpTest{
    //     // projecting "snd" through "fst"
    //     .fst = .{ 
    //         .curve = fst_crv,
    //         .fpath = fst_name,
    //         .split_hodograph = try fst_crv.split_on_critical_points(allocator),
    //     },
    //     .snd = .{ 
    //         .curve = snd_crv,
    //         .fpath = snd_name,
    //         .split_hodograph = try snd_crv.split_on_critical_points(allocator),
    //     },
    // };
    // defer tmpCurves.fst.split_hodograph.deinit(allocator);
    // defer tmpCurves.snd.split_hodograph.deinit(allocator);
    defer STATE.deinit(ALLOCATOR);

    // while (!window.shouldClose() and window.getKey(.escape) != .press) {
    //     zglfw.pollEvents();
    //     try update(gfx_state, &state, &tmpCurves, allocator);
    //     draw(gfx_state);
    // }

    sapp.run(
        .{
            .init_cb = init,
            .frame_cb = frame,
            .cleanup_cb = cleanup,
            .event_cb = event,
            .window_title = "sokol-zig + Dear Imgui",
            .width = 800,
            .height = 600,
            .icon = .{ .sokol_default = true },
            .logger = .{ .func = slog.func },
        }
    );
}


pub fn evaluated_curve(
    crv: curve.TimeCurve,
    comptime steps:usize
) !struct{ xv: [steps]f32, yv: [steps]f32 }
{
    if (crv.segments.len == 0) {
        return .{ .xv = undefined, .yv = undefined };
    }

    const ext = crv.extents();
    const stepsize:f32 = (ext[1].time - ext[0].time) / @as(f32, steps);

    var xv:[steps]f32 = undefined;
    var yv:[steps]f32 = undefined;

    var i:usize = 0;
    var uv:f32 = ext[0].time;
    for (crv.segments) 
        |seg| 
    {
        uv = seg.p0.time;

        while (i < steps - 1) 
            : (i += 1) 
        {
            // guarantee that it hits the end point
            if (uv > seg.p3.time) 
            {
                xv[i] = seg.p3.time;
                yv[i] = seg.p3.value;
                i += 1;

                break;
            }

            // should not ever be hit
            errdefer std.log.err(
                "error: uv was: {:0.3} extents: {any:0.3}\n",
                .{ uv, ext }
            );

            const p = crv.evaluate(uv) catch blk: {
                break :blk ext[0].value;
            };

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

fn plot_cp_line(
    label: [:0]const u8,
    points: []const curve.ControlPoint,
    allocator: std.mem.Allocator,
) !void
{
    const xv = try allocator.alloc(f32, points.len);
    defer allocator.free(xv);
    const yv = try allocator.alloc(f32, points.len);
    defer allocator.free(yv);

    for (points, xv, yv) |p, *x, *y| {
        x.* = p.time;
        y.* = p.value;
    }

    zgui.plot.plotLine(
        label,
        f32,
        .{ .xv = xv, .yv = yv }
    );
}

fn plot_point(
    full_label: [:0]const u8,
    short_label: [:0]const u8,
    pt: curve.ControlPoint,
    size: f32,
) void
{
    zgui.plot.pushStyleVar1f(.{ .idx = .marker_size, .v = size });
    _ = zgui.plot.plotScatter(
        full_label,
        f32,
        .{
            .xv = &.{pt.time},
            .yv = &.{pt.value},
        }
    );
    zgui.plot.plotText(
        short_label,
        .{
            .x = pt.time,
            .y = pt.value,
            .pix_offset = .{ 0, size * 1.75 },
        }
    );
    zgui.plot.popStyleVar(.{ .count = 1 });
}

fn plot_knots(
    hod: curve.TimeCurve, 
    name: [:0]const u8,
    allocator: std.mem.Allocator,
) !void 
{
    var buf:[1024:0]u8 = undefined;
    @memset(&buf, 0);

    {
        const name_ = try std.fmt.bufPrintZ(
            &buf,
            "{s}: Bezier Knots",
            .{name}
        );

        const knots_xv = try allocator.alloc(f32, hod.segments.len + 1);
        defer allocator.free(knots_xv);
        const knots_yv = try allocator.alloc(f32, hod.segments.len + 1);
        defer allocator.free(knots_yv);

        const endpoints = try hod.segment_endpoints(allocator);
        defer allocator.free(endpoints);

        for (endpoints, 0..) |knot, knot_ind| {
            knots_xv[knot_ind] = knot.time;
            knots_yv[knot_ind] = knot.value;
        }

        zgui.plot.pushStyleVar1f(.{ .idx = .marker_size, .v = 30 });
        zgui.plot.plotScatter(
            name_,
            f32,
            .{
                .xv = knots_xv,
                .yv = knots_yv,
            }
        );

        for (endpoints, 0..) |pt, pt_ind| {
            const label = try std.fmt.bufPrintZ(&buf, "{d}", .{ pt_ind });
            zgui.plot.plotText(
                label,
                .{ .x = pt.time, .y = pt.value, .pix_offset = .{ 0, 45 } }
            );
        }

        zgui.plot.popStyleVar(.{ .count = 1 });
    }
}

fn plot_control_points(
    hod: curve.TimeCurve, 
    name: [:0]const u8,
    allocator: std.mem.Allocator,
) !void 
{
    var buf:[1024:0]u8 = undefined;
    @memset(&buf, 0);

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

        zgui.pushStrId(name_);
        for (hod.segments, 0..) |seg, seg_ind| {
            for (seg.points(), 0..) |pt, pt_ind| {
                knots_xv[seg_ind * 4 + pt_ind] = pt.time;
                knots_yv[seg_ind * 4 + pt_ind] = pt.value;
                const pt_text = try std.fmt.bufPrintZ(
                    buf[512..],
                    "{d}.{d}: ({d:0.2}, {d:0.2})",
                    .{ seg_ind, pt_ind, pt.time, pt.value },
                );
                zgui.plot.plotText(
                    pt_text,
                    .{.x = pt.time, .y = pt.value, .pix_offset = .{0, 36}} 
                );
            }
        }
        zgui.popId();
        
        zgui.plot.plotLine(
            name_,
            f32,
            .{
                .xv = knots_xv,
                .yv = knots_yv,
            }
        );

        zgui.plot.pushStyleVar1f(.{ .idx = .marker_size, .v = 20 });
        zgui.plot.plotScatter(
            name_,
            f32,
            .{
                .xv = knots_xv,
                .yv = knots_yv,
            }
        );
        zgui.plot.popStyleVar(.{ .count = 1 });
    }
}

fn plot_linear_curve(
    lin:curve.TimeCurveLinear,
    name:[:0]const u8,
    allocator:std.mem.Allocator
) !void
{
    var xv:[]f32 = try allocator.alloc(f32, lin.knots.len);
    defer allocator.free(xv);
    var yv:[]f32 = try allocator.alloc(f32, lin.knots.len);
    defer allocator.free(yv);

    for (lin.knots, 0..) |knot, knot_index| {
        xv[knot_index] = knot.time;
        yv[knot_index] = knot.value;
    }

    var tmp_buf:[1024:0]u8 = undefined;
    @memset(&tmp_buf, 0);

    const label = try std.fmt.bufPrintZ(
        &tmp_buf,
        "{s}: {d} knots",
        .{ name, lin.knots.len }
    );

    zgui.plot.plotLine(
        label,
        f32,
        .{ .xv = xv, .yv = yv }
    );
}

fn plot_editable_bezier_curve(
    crv:*curve.TimeCurve,
    name:[:0]const u8,
    allocator:std.mem.Allocator
) !void 
{
    const col: [4]f32 = .{ 1, 0, 0, 1 };

    var hasher = std.hash.Wyhash.init(0);
    for (name) |char| {
        std.hash.autoHash(&hasher, char);
    }

    for (crv.segments, 0..) |*seg, seg_ind| {
        std.hash.autoHash(&hasher, seg_ind);

        var in_pts = seg.points();
        var times: [4]f64 = .{ 
            @floatCast(in_pts[0].time),
            @floatCast(in_pts[1].time),
            @floatCast(in_pts[2].time),
            @floatCast(in_pts[3].time),
        };
        var values: [4]f64 = .{ 
            @floatCast(in_pts[0].value),
            @floatCast(in_pts[1].value),
            @floatCast(in_pts[2].value),
            @floatCast(in_pts[3].value),
        };

        inline for (0..4) |idx| {
            std.hash.autoHash(&hasher, idx);

            _ = zgui.plot.dragPoint(
                @truncate(@as(i65, @intCast(hasher.final()))),
                .{ 
                    .x = &times[idx],
                    .y = &values[idx], 
                    .size = 20,
                    .col = col,
                }
            );
            in_pts[idx] = .{
                .time = @floatCast(times[idx]),
                .value = @floatCast(values[idx]),
            };
        }

        seg.set_points(in_pts);
    }

    try plot_bezier_curve(crv.*, name, .{}, allocator);
}

fn plot_bezier_curve(
    crv:curve.TimeCurve,
    name:[:0]const u8,
    flags: DebugBezierFlags,
    allocator:std.mem.Allocator
) !void 
{
    // evaluate curve points over the x domain
    const pts = try evaluated_curve(crv, CURVE_SAMPLE_COUNT);

    var buf:[1024:0]u8 = undefined;
    @memset(&buf, 0);

    const label = try std.fmt.bufPrintZ(
        &buf,
        "{s} [{d} segments]",
        .{ name, crv.segments.len }
    );

    if (flags.bezier) {
        zgui.plot.plotLine(
            label,
            f32,
            .{ .xv = &pts.xv, .yv = &pts.yv }
        );
    }

    if (flags.control_points) {
        try plot_control_points(crv, name, allocator);
    }

    if (flags.knots) {
        try plot_knots(crv, name, allocator);
    }

    if (flags.natural_midpoint) {
        for (crv.segments) |seg| {
            plot_point(
                label,
                "midpoint",
                seg.eval_at(0.5),
                18,
            );
        }
    }

    if (flags.find_u_test) 
    {
        const crv_extents = crv.extents();

        const findu_label = try std.fmt.bufPrintZ(
            &buf,
            "{s} findu test",
            .{ name }
        );

        var xv : [2]f32 = .{0, 0};
        var yv : [2]f32 = .{0, 0};

        for (crv.segments)
            |seg|
        {
            var x = seg.p0.time;
            const xmax = seg.p3.time;
            const step = (xmax - x) / 10.0;

            while (x < xmax)
                : (x += step)
            {
                const u_at_x = seg.findU_input_dual(x);
                const pt = seg.eval_at_dual(u_at_x);

                xv[0] = x;
                xv[1] = pt.r.time;

                yv[0] = crv_extents[0].value;
                yv[1] = pt.r.value;

                zgui.plot.plotLine(
                    findu_label,
                    f32,
                    .{ .xv = &xv, .yv = &yv }
                );
            }
        }
    }

    if (flags.derivatives_ddu or flags.derivatives_dydx) 
    {
        const deriv_label_ddu = try std.fmt.bufPrintZ(
            buf[512..],
            "{s} derivatives (ddu)",
            .{ name }
        );
        const deriv_label_hodo_ddu = try std.fmt.bufPrintZ(
            buf[700..],
            "{s} derivatives (hodograph ddu)",
            .{ name }
        );
        const deriv_label_dydx = try std.fmt.bufPrintZ(
            &buf,
            "{s} derivatives (dy/dx)",
            .{ name }
        );
        const increment : f32 = (
            @as(f32, @floatFromInt(DERIVATIVE_STEPS))
            / @as(f32, @floatFromInt(CURVE_SAMPLE_COUNT))
        );
        var unorm : f32 = 0;
        while (unorm <= 1.0 + increment) 
            : (unorm += increment)
        {
            for (crv.segments)
                |seg|
            {
                // dual of control points
                const d_du = seg.eval_at_dual(.{.r = unorm, .i = 1 });

                if (flags.derivatives_ddu) 
                {
                    const xv : [2]f32 = .{
                        d_du.r.time,
                        d_du.r.time + d_du.i.time,
                    };
                    const yv : [2]f32 = .{
                        d_du.r.value,
                        d_du.r.value + d_du.i.value,
                    };

                    zgui.plot.plotLine(
                        deriv_label_ddu,
                        f32,
                        .{ .xv = &xv, .yv = &yv }
                    );
                }

                if (flags.derivatives_dydx) 
                {
                    const d_dx = seg.eval_at_input_dual(d_du.r.time);

                    const xv : [2]f32 = .{
                        d_dx.r.time,
                        d_dx.r.time + d_dx.i.time,
                    };
                    const yv : [2]f32 = .{
                        d_dx.r.value,
                        d_dx.r.value + d_dx.i.value,
                    };

                    zgui.plot.plotLine(
                        deriv_label_dydx,
                        f32,
                        .{ .xv = &xv, .yv = &yv }
                    );
                }

                if (flags.derivatives_hodo_ddu)
                {
                    const cSeg = seg.to_cSeg();
                    var hodo = curve.bezier_curve.hodographs.compute_hodograph(
                        &cSeg
                    );
                    const hodo_d_du = (
                        curve.bezier_curve.hodographs.evaluate_bezier(
                            &hodo,
                            unorm
                        )
                    );

                    const xv : [2]f32 = .{
                        d_du.r.time,
                        d_du.r.time + hodo_d_du.x,
                    };
                    const yv : [2]f32 = .{
                        d_du.r.value,
                        d_du.r.value + hodo_d_du.y,
                    };

                    zgui.plot.plotLine(
                        deriv_label_hodo_ddu,
                        f32,
                        .{ .xv = &xv, .yv = &yv }
                    );
                }
            }
        }
    }

    if (flags.derivatives_dydx_isect) 
    {
        const deriv_label_isect = try std.fmt.bufPrintZ(
            buf[512..],
            "{s} derivatives at p0, p3 (dydx)",
            .{ name }
        );

        const unorms= [_] f32{ 0, 1 };
        for (unorms) 
            |unorm|
        {
            for (crv.segments)
                |seg|
            {
                // dual of control points
                const d_du = seg.eval_at_dual(.{.r = unorm, .i = 1 });

                if (flags.derivatives_dydx_isect) 
                {
                    const d_dx = seg.eval_at_input_dual(d_du.r.time);

                    const xv : [3]f32 = .{
                        d_dx.r.time - d_dx.i.time,
                        d_dx.r.time,
                        d_dx.r.time + d_dx.i.time,
                    };
                    const yv : [3]f32 = .{
                        d_dx.r.value - d_dx.i.value,
                        d_dx.r.value,
                        d_dx.r.value + d_dx.i.value,
                    };

                    zgui.plot.plotLine(
                        deriv_label_isect,
                        f32,
                        .{ .xv = &xv, .yv = &yv }
                    );
                }
            }
        }
    }

    if (flags.show_dydx_point) 
    {
        const decastlejau_label = try std.fmt.bufPrintZ(
            buf[512..],
            "{s} decastlejau at sample_point",
            .{ name }
        );

        const unorm = flags.sample_point;

        for (crv.segments)
            |seg|
        {
            // dual of control points
            const d_du = seg.eval_at_dual(.{.r = unorm, .i = 1 });

            if (flags.show_dydx_point) 
            {
                const d_dx = seg.eval_at_input_dual(d_du.r.time);

                const xv : [3]f32 = .{
                    d_dx.r.time - d_dx.i.time,
                    d_dx.r.time,
                    d_dx.r.time + d_dx.i.time,
                };
                const yv : [3]f32 = .{
                    d_dx.r.value - d_dx.i.value,
                    d_dx.r.value,
                    d_dx.r.value + d_dx.i.value,
                };

                zgui.plot.plotLine(
                    decastlejau_label,
                    f32,
                    .{ .xv = &xv, .yv = &yv }
                );

                plot_point("sample_point", "p", seg.eval_at(unorm), 20);
            }

            if (flags.show_decastlejau_point)
            {
                const I1 = curve.bezier_math.lerp(unorm, seg.p0, seg.p1);
                const I2 = curve.bezier_math.lerp(unorm, seg.p1, seg.p2);
                const I3 = curve.bezier_math.lerp(unorm, seg.p2, seg.p3);

                {
                    const xv = [_]f32{
                        I1.time,
                        I2.time,
                        I3.time,
                    };
                    const yv = [_]f32{
                        I1.value,
                        I2.value,
                        I3.value,
                    };
                    zgui.plot.plotLine(
                        decastlejau_label,
                        f32,
                        .{ .xv = &xv, .yv = &yv }
                    );
                }

                const e1 = curve.bezier_math.lerp(unorm, I1, I2);
                const e2 = curve.bezier_math.lerp(unorm, I2, I3);

                {
                    const xv = [_]f32{
                        e1.time,
                        e2.time,
                    };
                    const yv = [_]f32{
                        e1.value,
                        e2.value,
                    };
                    zgui.plot.plotLine(
                        decastlejau_label,
                        f32,
                        .{ .xv = &xv, .yv = &yv }
                    );
                }

                for ([_]curve.ControlPoint{ I1, I2, I3, e1, e2 })
                    |pt|
                {
                    plot_point("decastlejau_pt", "", pt, 20);
                }
            }
        }
    }
}

fn plot_tpa_guts(
    guts: curve.bezier_curve.tpa_result,
    name: []const u8,
    flags: tpa_flags,
    allocator: std.mem.Allocator,
) !void 
{
    var buf: [1024:0]u8 = undefined;

    const fields = &.{
        "start",
        "midpoint",
        "end",
        "A",
        "C",
    };

    inline for (fields) 
        |f| 
    {
        if (@field(flags, f)) {
            const label =  try std.fmt.bufPrintZ(
                &buf,
                "{s} / {s}",
                .{ name, f }
            );
            
            plot_point(label, f, @field(guts, f).?, 20);
        }
    }

    // draw the line from A to C
    if (flags.A and flags.C) {
        try plot_cp_line("A->C", &.{guts.A.?, guts.C.?}, allocator);
        const baseline_len = guts.C.?.distance(guts.A.?);
        const label = try std.fmt.bufPrintZ(
            &buf,
            "A->C length {d}\nt: {d}",
            .{ baseline_len, guts.t.? }
        );
        zgui.plot.plotText(
            label,
            .{ 
                .x = guts.A.?.time, 
                .y = guts.A.?.value,
                .pix_offset = .{ 0, 60 }
            }
        );
    }

    if (flags.start and flags.end) {
        try plot_cp_line("start->end", &.{guts.start.?, guts.end.?}, allocator);
        const baseline_len = guts.start.?.distance(guts.end.?);
        const label = try std.fmt.bufPrintZ(&buf, "start->end length: {d}", .{ baseline_len });
        zgui.plot.plotText(
            label,
            .{ 
                .x = guts.start.?.time, 
                .y = guts.start.?.value,
                .pix_offset = .{ 0, 60 }
            }
        );
    }

    if (flags.start_ddt and guts.start_ddt != null) {
        const ddt = guts.start_ddt.?;
        const off = guts.start.?.add(ddt);

        const xv = &.{ guts.start.?.time, off.time };
        const yv = &.{ guts.start.?.value, off.value };

        const label =  try std.fmt.bufPrintZ(
            &buf,
            "{s} / start->start_ddt",
            .{ name }
        );

        zgui.plot.plotLine(
            label,
            f32,
            .{ .xv = xv, .yv = yv }
        );

        plot_point(label, "start_ddt", off, 20);
    }

    if (flags.end_ddt and guts.end_ddt != null) {
        const ddt = guts.end_ddt.?;
        const off = guts.end.?.sub(ddt);

        const xv = &.{ guts.end.?.time, off.time };
        const yv = &.{ guts.end.?.value, off.value };

        const label =  try std.fmt.bufPrintZ(
            &buf,
            "{s} / end->end_ddt",
            .{ name }
        );

        zgui.plot.plotLine(
            label,
            f32,
            .{ .xv = xv, .yv = yv }
        );

        plot_point(label, "end_ddt", off, 20);
    }

    if (flags.e1_2) 
    {
        const e1 = guts.e1.?;
        const e2 = guts.e2.?;

        const xv = &.{ e1.time, guts.midpoint.?.time, e2.time };
        const yv = &.{ e1.value, guts.midpoint.?.value, e2.value };

        const label =  try std.fmt.bufPrintZ(
            &buf,
            "{s} / e1->midpoint->e2",
            .{ name }
        );

        zgui.plot.plotLine(
            label,
            f32,
            .{ .xv = xv, .yv = yv }
        );

        plot_point(label, "e1", e1, 20);
        plot_point(label, "e2", e2, 20);

        {
            const d = e1.sub(guts.midpoint.?);
            const d_label = try std.fmt.bufPrintZ(
                &buf,
                "d/dt: ({d:0.6}, {d:0.6}) len: {d:0.4}",
                .{d.time, d.value, e1.distance(guts.midpoint.?) },
            );
            zgui.plot.plotText(
                d_label,
                .{ 
                    .x = e1.time, 
                    .y = e1.value, 
                    .pix_offset = .{ 0, 48 } 
                },
                );
        }
    }

    if (flags.v1_2) 
    {
        const v1 = guts.v1.?;
        const v2 = guts.v2.?;

        const xv = &.{ v1.time,  guts.A.?.time,  v2.time };
        const yv = &.{ v1.value, guts.A.?.value, v2.value };

        const label =  try std.fmt.bufPrintZ(
            &buf,
            "{s} / v1->A->v2",
            .{ name }
        );

        zgui.plot.plotLine(
            label,
            f32,
            .{ .xv = xv, .yv = yv }
        );

        plot_point(label, "v1", v1, 20);
        plot_point(label, "v2", v2, 20);
    }

    if (flags.C1_2) 
    {
        const c1 = guts.C1.?;
        const c2 = guts.C2.?;

        // const xv = &.{ v1.time,  mid_point.time,  v2.time };
        // const yv = &.{ v1.value, mid_point.value, v2.value };

        const label =  try std.fmt.bufPrintZ(
            &buf,
            "{s} / c1/c2",
            .{ name }
        );

        // zgui.plot.plotLine(
        //     label,
        //     f32,
        //     .{ .xv = xv, .yv = yv }
        // );

        plot_point(label, "c1", c1, 20);
        plot_point(label, "c2", c2, 20);
    }
}

// plot using a two point approximation
fn plot_two_point_approx(
    crv: curve.TimeCurve,
    flags: DebugDrawCurveFlags,
    name: [:0]const u8,
    allocator: std.mem.Allocator,
) !void
{
    var buf:[1024:0]u8 = undefined;

    const approx_label = try std.fmt.bufPrintZ(
        &buf,
        "{s} / approximation using two point method (+computed derivatives at endpoints)",
        .{ name }
    );
    var approx_segments = std.ArrayList(curve.Segment).init(allocator);
    defer approx_segments.deinit();

    for (crv.segments) 
        |seg| 
    {
        if (seg.p0.time > 0) {
            continue;
        }
        // const cSeg = seg.to_cSeg();
        // var hodo = curve.bezier_curve.hodographs.compute_hodograph(&cSeg);
        //     const d_midpoint_dt = (
        //         curve.bezier_curve.hodographs.evaluate_bezier(
        //             &hodo,
        //             u
        //         )
        //     );
        //     const d_mid_point_dt = curve.ControlPoint{
        //         .time = d_midpoint_dt.x,
        //         .value = d_midpoint_dt.y,
        //     };
        //
        //     const tpa_guts = curve.bezier_curve.three_point_guts_plot(
        //         seg.p0,
        //         mid_point,
        //         u,
        //         d_mid_point_dt,
        //         seg.p3,
        //     );
        //
        //     // derivative at the midpoint
        //     try approx_segments.append(tpa_guts.result.?);
        //
        //     try plot_tpa_guts(
        //         tpa_guts,
        //         label,
        //         flags.three_point_approximation,
        //         allocator,
        //     );
    }

    const approx_crv = try curve.TimeCurve.init(
        allocator,
        approx_segments.items
    );

    try plot_bezier_curve(
        approx_crv,
        approx_label,
        flags.three_point_approximation.result_curves,
        allocator
    );
}

fn plot_three_point_approx(
    crv: curve.TimeCurve,
    flags: DebugDrawCurveFlags,
    name: [:0]const u8,
    allocator: std.mem.Allocator,
) !void
{
    var buf:[1024:0]u8 = undefined;

    const approx_label = try std.fmt.bufPrintZ(
        &buf,
        "{s} / approximation using three point method",
        .{ name }
    );
    var approx_segments = std.ArrayList(curve.Segment).init(allocator);
    defer approx_segments.deinit();

    const u_vals:[]const f32 = &.{0, 0.25, 0.5, 0.75, 1};
    const u_names = &.{"u_0", "u_1_4", "u_1_2", "u_3_4", "u_1"};
    var u_bools : [u_names.len]bool = undefined;

    inline for (u_names, 0..) |n, i| {
        u_bools[i] = @field(flags.three_point_approximation, n);
    }

    for (u_bools, u_vals) 
        |b, u|
    {
        if (b != true) {
            continue;
        }

        const label = try std.fmt.bufPrintZ(
            &buf,
            "{s} three points approximation [u = {d}]",
            .{ name, u }
        );

        zgui.pushStrId(label);
        defer zgui.popId();

        approx_segments.clearAndFree();

        for (crv.segments) 
            |seg| 
        {
            const mid_point = seg.eval_at(u);

            const cSeg = seg.to_cSeg();
            var hodo = curve.bezier_curve.hodographs.compute_hodograph(&cSeg);
            const d_midpoint_dt = (
                curve.bezier_curve.hodographs.evaluate_bezier(
                    &hodo,
                    u
                )
            );
            const d_mid_point_dt = curve.ControlPoint{
                .time = d_midpoint_dt.x,
                .value = d_midpoint_dt.y,
            };

            const tpa_guts = curve.bezier_curve.three_point_guts_plot(
                seg.p0,
                mid_point,
                u,
                d_mid_point_dt,
                seg.p3,
            );

            // derivative at the midpoint
            try approx_segments.append(tpa_guts.result.?);

            try plot_tpa_guts(
                tpa_guts,
                label,
                flags.three_point_approximation,
                allocator,
            );
        }

        const approx_crv = try curve.TimeCurve.init(
            allocator,
            approx_segments.items,
        );

        try plot_bezier_curve(
            approx_crv,
            approx_label,
            flags.three_point_approximation.result_curves,
            allocator
        );
    }
}

fn plot_curve(
    crv: *VisCurve,
    name: [:0]const u8,
    allocator: std.mem.Allocator,
) !void 
{
    var buf:[1024:0]u8 = undefined;
    @memset(&buf, 0);

    const flags = crv.draw_flags;

    // input curve
    if (flags.input_curve.bezier) {
        if (crv.editable) {
            try plot_editable_bezier_curve(&crv.curve, name, allocator);
            crv.split_hodograph.deinit(allocator);
            crv.split_hodograph = (
                try crv.curve.split_on_critical_points(allocator)
            );
        }

        try plot_bezier_curve(
            crv.curve,
            name,
            flags.input_curve,
            allocator
        );
    }

    // input curve linearized
    if (flags.input_curve.linearized) {
        const lin_label = try std.fmt.bufPrintZ(
            &buf,
            "{s} / linearized", 
            .{ name }
        );
        const orig_linearized = try crv.curve.linearized(allocator);
        defer orig_linearized.deinit(allocator);

        try plot_linear_curve(orig_linearized, lin_label, allocator);
    }

    // three point approximation
    try plot_three_point_approx(crv.split_hodograph, flags, name, allocator);

    // split on critical points
    {
        const split = try crv.curve.split_on_critical_points(allocator);
        defer split.deinit(allocator);

        @memset(&buf, 0);
        const label = try std.fmt.bufPrintZ(
            &buf,
            "{s} / split on critical points", 
            .{ name }
        );

        try plot_bezier_curve(
            split,
            label,
            flags.split_critical_points,
            allocator
        );

        if (flags.split_critical_points.linearized) {
            const linearized = try split.linearized(allocator);
            defer linearized.deinit(allocator);
            try plot_linear_curve(linearized, label, allocator);
        }
    }

}

fn update(
    // gfx_state: *GraphicsState,
    state: *VisState,
    // tmpCurves: *projTmpTest,
    allocator: std.mem.Allocator,
) !void 
{
    var _proj = time_topology.TimeTopology.init_identity_infinite();
    const inf = time_topology.TimeTopology.init_identity_infinite();

    for (state.operations.items) 
        |visop| 
    {
        var _topology: time_topology.TimeTopology = .{ .empty = .{} };

        switch (visop) 
        {
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

        _proj = _topology.project_topology(
            allocator,
            _proj
        ) catch inf;
    }

    const width:f32 = @floatFromInt(sapp.width());
    // const hezguiht:f32 = @floatFromInt(sapp.hezguiht());

    // FPS/status line
    // zgui.bulletText(
    //     "Average : {d:.3} ms/frame ({d:.1} fps)",
    //     .{ gfx_state.gctx.stats.average_cpu_time, gfx_state.gctx.stats.fps },
    // );
    // zgui.spacing();

    var tmp_buf:[1024:0]u8 = undefined;
    @memset(&tmp_buf, 0);

    {
        if (zgui.beginChild("Plot", .{ .w = width - 600 }))
        {

            if (zgui.plot.beginPlot(
                    "Curve Plot",
                    .{ 
                        .h = -1.0,
                        .flags = .{ .equal = true },
                    }
                )
            ) 
            {
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
                for (state.operations.items, 0..) 
                    |*visop, op_index| 
                {

                    switch (visop.*) 
                    {
                        .curve => |*crv| {
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

                if (state.show_projection_result) 
                {
                    switch (_proj) 
                    {
                        .linear_curve => |lint| { 
                            const lin = lint.curve;
                            try plot_linear_curve(
                                lin,
                                "result / linear",
                                allocator
                            );
                        },
                        .bezier_curve => |bez| {
                            const pts = try evaluated_curve(
                                bez.curve,
                                CURVE_SAMPLE_COUNT
                            );

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
                }

                // if (state.show_test_curves) 
                // {
                //     // debug 
                //     var self = tmpCurves.fst.curve;
                //     var other = tmpCurves.snd.curve;
                //
                //     try plot_bezier_curve(
                //         self,
                //         "self",
                //         state.show_projection_result_guts.fst,
                //         allocator
                //     );
                //     try plot_bezier_curve(
                //         other,
                //         "other",
                //         state.show_projection_result_guts.snd,
                //         allocator
                //     );
                //
                //     const self_hodograph = try self.split_on_critical_points(allocator);
                //     defer self_hodograph.deinit(allocator);
                //
                //     const other_hodograph = try other.split_on_critical_points(allocator);
                //     defer other_hodograph.deinit(allocator);
                //
                //     const other_bounds = other.extents();
                //     var other_copy = try curve.TimeCurve.init(
                //         allocator,
                //         other_hodograph.segments,
                //     );
                //
                //     {
                //         var split_points = std.ArrayList(f32).init(allocator);
                //         defer split_points.deinit();
                //
                //         // find all knots in self that are within the other bounds
                //         const endpoints = try self_hodograph.segment_endpoints(
                //             allocator
                //         );
                //         defer allocator.free(endpoints);
                //
                //         for (endpoints)
                //             |self_knot| 
                //         {
                //             if (
                //                 _is_between(
                //                     self_knot.time,
                //                     other_bounds[0].value,
                //                     other_bounds[1].value
                //                 )
                //             ) {
                //                 try split_points.append(self_knot.time);
                //             }
                //
                //         }
                //
                //         var result = try other_copy.split_at_each_output_ordinate(
                //             split_points.items,
                //             allocator
                //         );
                //         other_copy = try curve.TimeCurve.init(
                //             allocator,
                //             result.segments,
                //         );
                //         result.deinit(allocator);
                //     }
                //
                //     const result_guts = try self_hodograph.project_curve_guts(
                //         other_hodograph,
                //         allocator
                //     );
                //     defer result_guts.deinit();
                //
                //     try plot_bezier_curve(
                //         result_guts.self_split.?,
                //         "self_split",
                //         state.show_projection_result_guts.self_split,
                //         allocator
                //     );
                //
                //     // zgui.text("Segments to project through indices: ", .{});
                //     // for (
                //     //     result_guts.segments_to_project_through.?
                //     // ) |ind| {
                //     //     zgui.text("{d}", .{ ind });
                //     // }
                //
                //     try plot_bezier_curve(
                //         result_guts.other_split.?,
                //         "other_split",
                //         state.show_projection_result_guts.other_split,
                //         allocator
                //     );
                //
                //     var buf:[1024:0]u8 = undefined;
                //     @memset(&buf, 0);
                //     {
                //         const result_name = try std.fmt.bufPrintZ(
                //             &buf,
                //             "result of projection{s}",
                //             .{
                //                 if (result_guts.result.?.segments.len > 0) "" 
                //                 else " [NO SEGMENTS/EMPTY]",
                //             }
                //         );
                //
                //         try plot_bezier_curve(
                //             result_guts.result.?,
                //             result_name,
                //             state.show_projection_result_guts.tpa_flags.result_curves,
                //             allocator
                //         );
                //     }
                //
                //     {
                //         try plot_bezier_curve(
                //             result_guts.to_project.?,
                //             "Segments of Other that will be projected",
                //             state.show_projection_result_guts.to_project,
                //             allocator
                //         );
                //     }
                //
                //     {
                //         for (result_guts.tpa.?, 0..) 
                //             |tpa, ind| 
                //         {
                //             const label = try std.fmt.bufPrintZ(
                //                 &buf,
                //                 "Three Point Approx Projected.segments[{d}]",
                //                 .{ind }
                //             );
                //             try plot_tpa_guts(
                //                 tpa,
                //                 label,
                //                 state.show_projection_result_guts.tpa_flags,
                //                 allocator,
                //             );
                //
                //         }
                //     }
                //
                //     const derivs = .{
                //         "f_prime_of_g_of_t",
                //         "g_prime_of_t",
                //         "midpoint_derivatives",
                //     };
                //
                //     // midpoint derivatives
                //     inline for (derivs) 
                //         |d_name| 
                //     {
                //         if (@field(state, d_name))
                //         {
                //             for (@field(result_guts, d_name).?, 0..) 
                //                 |d, ind|
                //             {
                //                 const midpoint = result_guts.tpa.?[ind].midpoint.?;
                //                 const p1 = midpoint.add(d);
                //                 const p2 = midpoint.sub(d);
                //
                //                 const xv = &.{ p1.time,  midpoint.time,  p2.time };
                //                 const yv = &.{ p1.value, midpoint.value, p2.value };
                //
                //                 zgui.plot.plotLine(
                //                     d_name,
                //                     f32,
                //                     .{ .xv = xv, .yv = yv }
                //                 );
                //                 {
                //                     const label = try std.fmt.bufPrintZ(
                //                         &buf,
                //                         "d/dt: ({d:0.6}, {d:0.6})",
                //                         .{d.time, d.value},
                //                     );
                //                     zgui.plot.plotText(
                //                         label,
                //                         .{ 
                //                             .x = p1.time, 
                //                             .y = p1.value, 
                //                             .pix_offset = .{ 0, 16 } 
                //                         },
                //                     );
                //                 }
                //             }
                //         }
                //     }
                // }

                zgui.plot.endPlot();
            }
        }
        defer zgui.endChild();
    }

    zgui.sameLine(.{});

    {
        if (
            zgui.beginChild(
                "Settings",
                .{ 
                    .w = 600,
                    .window_flags = zgui.WindowFlags{ .no_scrollbar = false} 
                }
            )
        ) 
        {
            _ = zgui.checkbox(
                "Show zgui Demo Windows",
                .{ .v = &state.show_demo }
            );
            _ = zgui.checkbox(
                "Show Projection Test Curves",
                .{ .v = &state.show_test_curves }
            );
            _ = zgui.checkbox(
                "Show Projection Result",
                .{ .v = &state.show_projection_result }
            );

            if (zgui.treeNode("Projection Algorithm Debug Switches")) 
            {
                defer zgui.treePop();

                const bcrv = curve.bezier_curve;
                zgui.text("U value: {d}", .{ bcrv.u_val_of_midpoint });
                _ = zgui.sliderFloat(
                    "U Value",
                    .{
                        .min = 0,
                        .max = 1,
                        .v = &bcrv.u_val_of_midpoint 
                    }
                );
                zgui.text("fudge: {d}", .{ bcrv.fudge });
                _ = zgui.sliderFloat(
                    "scale e1/e2 fudge factor",
                    .{ 
                        .min = 0.1,
                        .max = 10,
                        .v = &bcrv.fudge 
                    }
                );

                _ = zgui.comboFromEnum(
                    "Projection Algorithm",
                    &bcrv.project_algo
                );
            }


            if (state.show_test_curves and zgui.treeNode("Test Curve Settings"))
            {
                defer zgui.treePop();

                {
                    var guts = state.show_projection_result_guts;
                    guts.fst.draw_ui("self");
                    guts.self_split.draw_ui("self split");
                    guts.snd.draw_ui("other");
                    guts.other_split.draw_ui("other split");
                    guts.to_project.draw_ui("segments in other to project");
                }

                if (zgui.treeNode("Derivative Debug Info"))
                {
                    defer zgui.treePop();
                    const derivs = .{
                        .{"f_prime_of_g_of_t", "Show Derivative of self at midpoint"},
                        .{"g_prime_of_t", "Show derivative of other at midpoint"},
                        .{"midpoint_derivatives", "Show chain rule result of multiplying derivatives"},
                    };

                    // midpoint derivatives
                    inline for (derivs) 
                        |d_info| 
                    {
                        _ = zgui.checkbox(
                            d_info[1],
                            .{ .v = &@field(state,d_info[0]) }
                        );
                    }
                }

                state.show_projection_result_guts.tpa_flags.draw_ui(
                    "Projection Result"
                );
            }

            var remove = std.ArrayList(usize).init(allocator);
            defer remove.deinit();
            const op_index:usize = 0;
            for (state.operations.items) 
                |*visop| 
            {
                switch (visop.*) 
                {
                    .curve => |*crv| {
                        var buf:[1024:0]u8 = undefined;
                        @memset(&buf, 0);
                        const top_label = try std.fmt.bufPrintZ(
                            &buf,
                            "Curve Settings: {s}",
                            .{ crv.fpath }
                        );

                        zgui.pushPtrId(@ptrCast(crv));
                        defer zgui.popId();
                        if (
                            zgui.treeNodeFlags(
                                top_label,
                                .{ .default_open = true }
                            )
                        )
                        {
                            defer zgui.treePop();

                            zgui.pushPtrId(&crv.active);
                            defer zgui.popId();

                            // debug flags
                            _ = zgui.checkbox(
                                "Active In Projections",
                                .{.v = &crv.active}
                            );
                            _ = zgui.checkbox(
                                "Editable",
                                .{.v = &crv.editable}
                            );

                            if (
                                zgui.treeNodeFlags(
                                    "Draw Flags",
                                    .{ .default_open = true }
                                )
                            ) {
                                defer zgui.treePop();

                                crv.draw_flags.draw_ui(crv.fpath);
                            }

                            if (zgui.treeNode("Debug Data"))
                            {
                                defer zgui.treePop();

                                for (crv.curve.segments, 0..)
                                    |seg, ind|
                                {
                                    zgui.bulletText(
                                        "Measured Order [time]: {d}",
                                        .{ 
                                            try curve.bezier_math.actual_order(
                                                seg.p0.time,
                                                seg.p1.time,
                                                seg.p2.time,
                                                seg.p3.time,
                                            )
                                        },
                                    );

                                    zgui.bulletText(
                                        "Measured Order [value]: {d}",
                                        .{ 
                                            try curve.bezier_math.actual_order(
                                                seg.p0.value,
                                                seg.p1.value,
                                                seg.p2.value,
                                                seg.p3.value,
                                            )
                                        },
                                    );

                                    // dy/dx
                                    {
                                        const d_p0 = seg.eval_at_input_dual(
                                            seg.p0.time
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] dy/dx at p0: {}",
                                            .{
                                                ind,
                                                d_p0.i.time,
                                            },
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] p1-p0: {}",
                                            .{
                                                ind,
                                                seg.p1.time - seg.p0.time,
                                            },
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] (dy/dx) / (p1-p0): {}",
                                            .{
                                                ind,
                                                (
                                                 d_p0.i.time 
                                                 / (
                                                     seg.p1.time 
                                                     - seg.p0.time
                                                 )
                                                ),
                                            },
                                        );

                                        const d_p3 = seg.eval_at_input_dual(
                                            seg.p3.time
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] dy/dx at p3: {}",
                                            .{
                                                ind,
                                                d_p3.i.time,
                                            },
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] p3-p2: {}",
                                            .{
                                                ind,
                                                seg.p3.time - seg.p2.time,
                                            },
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] (dy/dx) / (p3-p2): {}",
                                            .{
                                                ind,
                                                d_p3.i.time / (seg.p3.time - seg.p2.time),
                                            },
                                        );
                                    }

                                    // dy/du
                                    {
                                        const d_p0 = seg.eval_at_dual(
                                            .{ .r = 0, .i = 1.0}
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] dy/du at p0: {}",
                                            .{
                                                ind,
                                                d_p0.i.time,
                                            },
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] p1-p0: {}",
                                            .{
                                                ind,
                                                seg.p1.time - seg.p0.time,
                                            },
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] (dy/du) / (p1-p0): {}",
                                            .{
                                                ind,
                                                d_p0.i.time / (
                                                    seg.p1.time - seg.p0.time
                                                ),
                                            },
                                        );

                                        const d_p3 = seg.eval_at_dual(
                                            .{ .r = 1.0, .i = 1.0 }
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] dy/du at p3: {}",
                                            .{
                                                ind,
                                                d_p3.i.time,
                                            },
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] p3-p2: {}",
                                            .{
                                                ind,
                                                seg.p3.time - seg.p2.time,
                                            },
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] (dy/du) / (p3-p2): {}",
                                            .{
                                                ind,
                                                d_p3.i.time / (seg.p3.time - seg.p2.time),
                                            },
                                        );
                                    }
                                }
                            }

                            if (zgui.smallButton("Remove")) {
                                try remove.append(op_index);
                            }
                            zgui.sameLine(.{});
                            zgui.text(
                                "file path: {s}",
                                .{ crv.*.fpath[0..] }
                            );

                            // show the knots
                            if (zgui.treeNode("Orzguiinal Knots")) {
                                defer zgui.treePop();

                                const endpoints = (
                                    try crv.curve.segment_endpoints(allocator)
                                );
                                defer allocator.free(endpoints);
                                for (endpoints, 0..) 
                                    |pt, ind| 
                                {
                                    zgui.bulletText(
                                        "{d}: ({d}, {d})",
                                        .{ ind, pt.time, pt.value },
                                    );
                                }
                            }

                            if (zgui.treeNode("Hodograph Debug")) {
                                defer zgui.treePop();

                                const hgraph = curve.bezier_curve.hodographs;
                                const cSeg = crv.curve.segments[0].to_cSeg();
                                const inflections = hgraph.inflection_points(
                                    &cSeg
                                );
                                zgui.bulletText(
                                    "inflection point: {d:0.4}",
                                    .{inflections.x},
                                );
                                const hodo = hgraph.compute_hodograph(&cSeg);
                                const roots = hgraph.bezier_roots(&hodo);
                                zgui.bulletText(
                                    "roots: {d:0.4} {d:0.4}",
                                    .{roots.x, roots.y},
                                );
                            }

                            // split on critical points knots
                            if ( zgui.treeNode( "Split on Critical Points Knots",))
                            {
                                defer zgui.treePop();

                                const split = try crv.curve.split_on_critical_points(allocator);
                                defer split.deinit(allocator);

                                const endpoints = try split.segment_endpoints(
                                    allocator,
                                );
                                defer allocator.free(endpoints);

                                for (endpoints, 0..) 
                                    |pt, ind| 
                                {
                                    zgui.bulletText(
                                        "{d}: ({d}, {d})",
                                        .{ ind, pt.time, pt.value },
                                    );
                                }
                            }

                            if (zgui.treeNode("Three Point Projection"))
                            {
                                defer zgui.treePop();

                                crv.draw_flags.three_point_approximation.draw_ui("curve three point");
                            }
                        }
                    },
                    .transform => |*xform| {
                        if (
                            zgui.treeNode( "Affine Transform Settings",)
                        ) 
                        {
                            defer zgui.treePop();
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
                // @TODO: after updating to zzgui 0.11
                // zgui.openPopup("Delete?");
            }

            // Remove any "remove"'d operations
            var i:usize = remove.items.len;
            while (i > 0) {
                i -= 1;
                const visop = state.operations.orderedRemove(remove.items[i]);
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

    // if (state.show_demo) {
    //     _ = zgui.showDemoWindow(null);
    //     _ = zgui.plot.showDemoWindow(null);
    // }
}

// fn draw(gfx_state: *GraphicsState) void {
//     const gctx = gfx_state.gctx;
//
//     const back_buffer_view = gctx.swapchain.getCurrentTextureView();
//     defer back_buffer_view.release();
//
//     const commands = commands: {
//         const encoder = gctx.device.createCommandEncoder(null);
//         defer encoder.release();
//
//         // Gui pass.
//         {
//             const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
//                 .view = back_buffer_view,
//                 .load_op = .load,
//                 .store_op = .store,
//             }};
//             const render_pass_info = wgpu.RenderPassDescriptor{
//                 .color_attachment_count = color_attachments.len,
//                 .color_attachments = &color_attachments,
//             };
//             const pass = encoder.beginRenderPass(render_pass_info);
//             defer {
//                 pass.end();
//                 pass.release();
//             }
//
//             zgui.backend.draw(pass);
//         }
//
//         break :commands encoder.finish(null);
//     };
//     defer commands.release();
//
//     gctx.submit(&.{commands});
//     _ = gctx.present();
// }

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
    while (args.next()) 
        |nextarg| 
    {
        const fpath: [:0]const u8 = nextarg;

        if (
            string.eql_latin_s8(fpath, "--help")
            or (string.eql_latin_s8(fpath, "-h"))
        ) {
            usage();
        }

        std.debug.print("reading curve: '{s}'\n", .{ fpath });

        const crv = curve.read_curve_json(fpath, allocator) catch |err| {
            std.debug.print(
                "Something went wrong reading: '{s}'\n",
                .{ fpath }
            );

            return err;
        };

        const viscurve = VisCurve{
            .fpath = try allocator.dupeZ(u8, fpath),
            .curve = crv,
            .split_hodograph = try crv.split_on_critical_points(allocator),
        };

        std.debug.assert(crv.segments.len > 0);

        try operations.append(.{ .curve = viscurve });
    }

    try operations.append(.{ .transform = .{} });

    return .{ .operations = operations };
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
    std.process.exit(1);
}
