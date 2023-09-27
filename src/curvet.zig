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

const opentime = @import("opentime");
const interval = opentime.interval;
const curve = @import("curve");
const string = @import("string_stuff");
const time_topology = @import("time_topology");
const util = opentime.util;

const DERIVATIVE_STEPS = 100;
const CURVE_SAMPLE_COUNT = 1000;

const DebugBezierFlags = packed struct (i8) {
    bezier: bool = true,
    knots: bool = false,
    control_points: bool = false,
    linearized: bool = false,
    natural_midpoint: bool = false,
    derivatives: bool = true,

    _padding: i2 = 0,

    pub fn draw_ui(
        self: * @This(),
        name: [:0]const u8
    ) void 
    {
        if (zgui.treeNode(name)) 
        {
            defer zgui.treePop();
            const fields = .{
                .{ "Draw Bezier Curves", "bezier"},
                .{ "Draw Knots", "knots"},
                .{ "Draw Control Points", "control_points" },
                .{ "Draw Linearized", "linearized" },
                .{ "Natural Midpoint (t=0.5)", "natural_midpoint" },
                .{ "Show Derivatives", "derivatives" },
            };

            zgui.pushStrId(name);

            inline for (fields) 
                |field| 
            {
                // unpack into a bool type
                var c_value:bool = @field(self, field[1]);
                _ = zgui.checkbox(field[0], .{ .v = &c_value,});
                // pack back into the aligned field
                @field(self, field[1]) = c_value;

            }
            zgui.popId();
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

    pub fn draw_ui(self: *@This(), name: []const u8) void {
        zgui.pushStrId(name);
        self.input_curve.draw_ui("input_curve");
        self.split_critical_points.draw_ui("split on critical points");
        self.three_point_approximation.draw_ui("three point approximation");
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

const GraphicsState = struct {
    gctx: *zgpu.GraphicsContext,

    font_normal: zgui.Font,
    font_large: zgui.Font,

    // texture: zgpu.TextureHandle,
    texture_view: zgpu.TextureViewHandle,

    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        window: *zglfw.Window
    ) !*GraphicsState 
    {
        const gctx = try zgpu.GraphicsContext.create(allocator, window, .{});

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        // Create a texture.
        zstbi.init(arena);
        defer zstbi.deinit();

        const font_path = content_dir ++ "genart_0025_5.png";

        var image = try zstbi.Image.loadFromFile(font_path, 4);
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
            break :scale_factor @max(scale[0], scale[1]);
        };

        // const fira_font_path = content_dir ++ "FiraCode-Medium.ttf";
        const robota_font_path = content_dir ++ "Roboto-Medium.ttf";

        const font_size = 16.0 * scale_factor;
        const font_large = zgui.io.addFontFromFile(
            robota_font_path,
            font_size * 1.1
        );
        const font_normal = zgui.io.addFontFromFile(
            robota_font_path,
            font_size
        );
        std.debug.assert(zgui.io.getFont(0) == font_large);
        std.debug.assert(zgui.io.getFont(1) == font_normal);

        // This needs to be called *after* adding your custom fonts.
        zgui.backend.init(
            window,
            gctx.device,
            @intFromEnum(zgpu.GraphicsContext.swapchain_format)
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

    zglfw.WindowHint.set(.cocoa_retina_framebuffer, 1);
    zglfw.WindowHint.set(.client_api, 0);

    const title = (
        "OpenTimelineIO V2 Prototype Bezier Curve Visualizer [" 
        ++ build_options.hash[0..6] 
        ++ "]"
    );

    const window = (
        zglfw.Window.create(1600, 1000, title, null) 
        catch {
            std.log.err("Could not create a window", .{});
            return;
        }
    );
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    var gpa = std.heap.GeneralPurposeAllocator(.{.stack_trace_frames = 32}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const gfx_state = GraphicsState.init(allocator, window) catch {
        std.log.err("Could not initialize resources", .{});
        return;
    };
    defer gfx_state.deinit();

    var state = try _parse_args(allocator);

    // u
    const fst_name:[:0]const u8 = "upside down u";
    const fst_crv = try curve.read_curve_json(
        "curves/upside_down_u.curve.json" ,
        allocator
    );
    defer fst_crv.deinit(allocator);

    // 1/2 slope
    // const seg = curve.create_linear_segment(
    //     .{ .time = -2, .value = -1 },
    //     .{ .time = 2, .value = 1 },
    // );
    // const lin_half = try curve.TimeCurve.init(&.{identSeg_half});
    // const lin_name_half = try std.fmt.bufPrintZ(
    //     pbuf[512..],
    //     "{s}",
    //     .{  "linear slope of 0.5 [-2, 2)" }
    // );

    // ident_long
    // const seg = curve.create_linear_segment(
    //     .{ .time = -2, .value = -2 },
    //     .{ .time = 2, .value = 2 },
    // );
    // const fst_crv = try curve.TimeCurve.init(&.{seg});
    // const fst_name:[:0]const u8 = "linear slope of 0.5 [-2, 2)";
    

    // const identSeg = curve.create_identity_segment(-0.2, 1) ;
    const identSeg = curve.create_identity_segment(-3, 3) ;
    const snd_crv = try curve.TimeCurve.init(&.{identSeg});
    const snd_name:[:0]const u8 ="linear [-0.2, 1)" ;

    var tmpCurves = projTmpTest{
        // projecting "snd" through "fst"
        // .snd = .{ 
        .fst = .{ 
            .curve = fst_crv,
            .fpath = fst_name,
            .split_hodograph = try fst_crv.split_on_critical_points(allocator),
        },
        // .fst = .{ 
        .snd = .{ 
            .curve = snd_crv,
            .fpath = snd_name,
            .split_hodograph = try snd_crv.split_on_critical_points(allocator),
        },
    };
    defer tmpCurves.fst.split_hodograph.deinit(allocator);
    defer tmpCurves.snd.split_hodograph.deinit(allocator);
    defer state.deinit(allocator);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        try update(gfx_state, &state, &tmpCurves, allocator);
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
    var buf:[1024:0]u8 = .{};
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

        const endpoints = try hod.segment_endpoints();

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
    var buf:[1024:0]u8 = .{};
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

    var tmp_buf:[1024:0]u8 = .{};
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

    var buf:[1024:0]u8 = .{};
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

    if (flags.derivatives) {
        const deriv_label = try std.fmt.bufPrintZ(
            &buf,
            "{s} derivatives",
            .{ name }
        );
        const increment : f32 = (
            @as(f32, @floatFromInt(DERIVATIVE_STEPS))
            / @as(f32, @floatFromInt(CURVE_SAMPLE_COUNT))
        );
        var unorm : f32 = 0;
        while (unorm < 1.0) 
            : (unorm += increment)
        {
            for (crv.segments)
                |seg|
            {
                // dual of control points
                const d_du = seg.eval_at_dual(unorm);

                const xv : [2]f32 = .{
                    d_du.r.time,
                    d_du.r.time + d_du.i.time 
                };
                const yv : [2]f32 = .{
                    d_du.r.value,
                    d_du.r.value + d_du.i.value 
                };

                zgui.plot.plotLine(
                    deriv_label,
                    f32,
                    .{ .xv = &xv, .yv = &yv }
                );
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
    var buf: [1024:0]u8 = .{};

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

fn plot_three_point_approx(
    crv: curve.TimeCurve,
    flags: DebugDrawCurveFlags,
    name: [:0]const u8,
    allocator: std.mem.Allocator,
) !void
{
    var buf:[1024:0]u8 = .{};

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
            var mid_point = seg.eval_at(u);

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

        const approx_crv = try curve.TimeCurve.init(approx_segments.items);

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
    var buf:[1024:0]u8 = .{};
    @memset(&buf, 0);

    const flags = crv.draw_flags;

    // input curve
    if (flags.input_curve.bezier) {
        if (crv.editable) {
            try plot_editable_bezier_curve(&crv.curve, name, allocator);
            crv.split_hodograph.deinit(allocator);
            crv.split_hodograph = try crv.curve.split_on_critical_points(allocator);
        } else {
            try plot_bezier_curve(
                crv.curve,
                name,
                flags.input_curve,
                allocator
            );
        }
    }

    // input curve linearized
    if (flags.input_curve.linearized) {
        const lin_label = try std.fmt.bufPrintZ(
            &buf,
            "{s} / linearized", 
            .{ name }
        );
        const orig_linearized = crv.curve.linearized();
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
            const linearized = split.linearized();
            try plot_linear_curve(linearized, label, allocator);
        }
    }

}

fn update(
    gfx_state: *GraphicsState,
    state: *VisState,
    tmpCurves: *projTmpTest,
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

        _proj = _topology.project_topology(_proj) catch inf;
    }

    zgui.backend.newFrame(
        gfx_state.gctx.swapchain_descriptor.width,
        gfx_state.gctx.swapchain_descriptor.height,
    );

    zgui.setNextWindowPos(.{ .x = 0.0, .y = 0.0, });

    const size = gfx_state.gctx.window.getFramebufferSize();
    const width:f32 = @floatFromInt(size[0]);
    const height:f32 = @floatFromInt(size[1]);

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
    defer zgui.end();

    // FPS/status line
    zgui.bulletText(
        "Average : {d:.3} ms/frame ({d:.1} fps)",
        .{ gfx_state.gctx.stats.average_cpu_time, gfx_state.gctx.stats.fps },
    );
    zgui.spacing();

    var tmp_buf:[1024:0]u8 = .{};
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

                if (state.show_projection_result) {
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

                if (state.show_test_curves) 
                {
                    // debug 
                    var self = tmpCurves.fst.curve;
                    var other = tmpCurves.snd.curve;

                    try plot_bezier_curve(
                        self,
                        "self",
                        state.show_projection_result_guts.fst,
                        allocator
                    );
                    try plot_bezier_curve(
                        other,
                        "other",
                        state.show_projection_result_guts.snd,
                        allocator
                    );

                    const self_hodograph = try self.split_on_critical_points(allocator);
                    defer self_hodograph.deinit(allocator);

                    const other_hodograph = try other.split_on_critical_points(allocator);
                    defer other_hodograph.deinit(allocator);

                    const other_bounds = other.extents();
                    var other_copy = try curve.TimeCurve.init(
                        other_hodograph.segments
                    );

                    {
                        var split_points = std.ArrayList(f32).init(allocator);
                        defer split_points.deinit();

                        // find all knots in self that are within the other bounds
                        for (try self_hodograph.segment_endpoints())
                            |self_knot| 
                        {
                            if (
                                _is_between(
                                    self_knot.time,
                                    other_bounds[0].value,
                                    other_bounds[1].value
                                )
                            ) {
                                try split_points.append(self_knot.time);
                            }

                        }

                        var result = try other_copy.split_at_each_output_ordinate(
                            split_points.items,
                            allocator
                        );
                        other_copy = try curve.TimeCurve.init(result.segments);
                        result.deinit(allocator);
                    }

                    const result_guts = try self_hodograph.project_curve_guts(
                        other_hodograph,
                        allocator
                    );
                    defer result_guts.deinit();

                    try plot_bezier_curve(
                        result_guts.self_split.?,
                        "self_split",
                        state.show_projection_result_guts.self_split,
                        allocator
                    );

                    // zgui.text("Segments to project through indices: ", .{});
                    // for (
                    //     result_guts.segments_to_project_through.?
                    // ) |ind| {
                    //     zgui.text("{d}", .{ ind });
                    // }

                    try plot_bezier_curve(
                        result_guts.other_split.?,
                        "other_split",
                        state.show_projection_result_guts.other_split,
                        allocator
                    );

                    var buf:[1024:0]u8 = .{};
                    @memset(&buf, 0);
                    {
                        const result_name = try std.fmt.bufPrintZ(
                            &buf,
                            "result of projection{s}",
                            .{
                                if (result_guts.result.?.segments.len > 0) "" 
                                else " [NO SEGMENTS/EMPTY]",
                            }
                        );

                        try plot_bezier_curve(
                            result_guts.result.?,
                            result_name,
                            state.show_projection_result_guts.tpa_flags.result_curves,
                            allocator
                        );
                    }

                    {
                        try plot_bezier_curve(
                            result_guts.to_project.?,
                            "Segments of Other that will be projected",
                            state.show_projection_result_guts.to_project,
                            allocator
                        );
                    }

                    {
                        for (result_guts.tpa.?, 0..) 
                            |tpa, ind| 
                        {
                            const label = try std.fmt.bufPrintZ(
                                &buf,
                                "Three Point Approx Projected.segments[{d}]",
                                .{ind }
                            );
                            try plot_tpa_guts(
                                tpa,
                                label,
                                state.show_projection_result_guts.tpa_flags,
                                allocator,
                            );

                        }
                    }

                    const derivs = .{
                        "f_prime_of_g_of_t",
                        "g_prime_of_t",
                        "midpoint_derivatives",
                    };

                    // midpoint derivatives
                    inline for (derivs) 
                        |d_name| 
                    {
                        if (@field(state, d_name))
                        {
                            for (@field(result_guts, d_name).?, 0..) 
                                |d, ind|
                                {
                                    const midpoint = result_guts.tpa.?[ind].midpoint.?;
                                    const p1 = midpoint.add(d);
                                    const p2 = midpoint.sub(d);

                                    const xv = &.{ p1.time,  midpoint.time,  p2.time };
                                    const yv = &.{ p1.value, midpoint.value, p2.value };

                                    zgui.plot.plotLine(
                                        d_name,
                                        f32,
                                        .{ .xv = xv, .yv = yv }
                                    );
                                    {
                                        const label = try std.fmt.bufPrintZ(
                                            &buf,
                                            "d/dt: ({d:0.6}, {d:0.6})",
                                            .{d.time, d.value},
                                        );
                                        zgui.plot.plotText(
                                            label,
                                            .{ 
                                                .x = p1.time, 
                                                .y = p1.value, 
                                                .pix_offset = .{ 0, 16 } 
                                            },
                                            );
                                    }
                                }
                        }
                    }
                }

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
                    .flags = zgui.WindowFlags{ .no_scrollbar = false} 
                }
            )
        ) 
        {
            _ = zgui.checkbox(
                "Show ZGui Demo Windows",
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

            if (zgui.treeNode("Projection Algorithm Debug Switches")) {
                defer zgui.treePop();
                zgui.text("U value: {d}", .{ curve.bezier_curve.u_val_of_midpoint });
                _ = zgui.sliderFloat(
                    "U Value",
                    .{
                        .min = 0,
                        .max = 1,
                        .v = &curve.bezier_curve.u_val_of_midpoint 
                    }
                );
                zgui.text("fudge: {d}", .{ curve.bezier_curve.fudge });
                _ = zgui.sliderFloat(
                    "scale e1/e2 fudge factor",
                    .{ 
                        .min = 0.1,
                        .max = 10,
                        .v = &curve.bezier_curve.fudge 
                    }
                );

                _ = zgui.comboFromEnum(
                    "Projection Algorithm",
                    &curve.bezier_curve.project_algo
                );
            }


            if (state.show_test_curves and zgui.treeNode("Test Curve Settings"))
            {
                defer zgui.treePop();
                state.show_projection_result_guts.fst.draw_ui(
                    "self"
                );
                state.show_projection_result_guts.self_split.draw_ui(
                    "self split"
                );
                state.show_projection_result_guts.snd.draw_ui(
                    "other"
                );
                state.show_projection_result_guts.other_split.draw_ui(
                    "other split"
                );
                state.show_projection_result_guts.to_project.draw_ui(
                    "segments in other to project"
                );

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
            var op_index:usize = 0;
            for (state.operations.items) |*visop| {
                switch (visop.*) {
                    .curve => |*crv| {
                        var buf:[1024:0]u8 = .{};
                        @memset(&buf, 0);
                        const top_label = try std.fmt.bufPrintZ(
                            &buf,
                            "Curve Settings: {s}",
                            .{ crv.fpath }
                        );

                        zgui.pushPtrId(@ptrCast(crv));
                        defer zgui.popId();
                        if (zgui.treeNode(top_label))
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

                            if (zgui.treeNode("Draw Flags")) {
                                defer zgui.treePop();

                                crv.draw_flags.draw_ui(crv.fpath);
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
                            if (zgui.treeNode("Original Knots")) {
                                defer zgui.treePop();

                                for (try crv.curve.segment_endpoints(), 0..) 
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

                                const cSeg = crv.curve.segments[0].to_cSeg();
                                const inflections = curve.bezier_curve.hodographs.inflection_points(&cSeg);
                                zgui.bulletText(
                                    "inflection point: {d:0.4}",
                                    .{inflections.x},
                                );
                                const hodo = curve.bezier_curve.hodographs.compute_hodograph(&cSeg);
                                const roots = curve.bezier_curve.hodographs.bezier_roots(&hodo);
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

                                for (try split.segment_endpoints(), 0..) 
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

    if (state.show_demo) {
        _ = zgui.showDemoWindow(null);
        _ = zgui.plot.showDemoWindow(null);
    }
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

        var viscurve = VisCurve{
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
    std.os.exit(1);
}
