//! curve visualizer tool for opentime

const std = @import("std");

const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;

const build_options = @import("build_options");
const exe_build_options = @import("exe_build_options");
const content_dir = exe_build_options.content_dir;

const opentime = @import("opentime");
const interval = opentime.interval;
const curve = @import("curve");
const string = @import("string_stuff");
const topology = @import("topology");
const util = opentime.util;

const DERIVATIVE_STEPS = 10;
const CURVE_SAMPLE_COUNT = 1000;

const sokol_app_wrapper = @import("sokol_app_wrapper");

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
        if (
            zgui.treeNodeFlags(
                name,
                .{ .default_open = true })
            ) 
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
                // pack back into the aligned field
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

    pub fn draw_ui(
        self: *@This(),
        name: [:0]const u8
    ) void 
    {
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
            //     inline for (fields) 
            //     |field| 
            //     {
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

    pub fn draw_ui(
        self: *@This(),
        name: [:0]const u8
    ) void 
    {
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
                inline for (fields) 
                    |field| 
                {
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

    pub fn draw_ui(
        self: *@This(),
        name: []const u8
    ) void 
    {
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
    curve: curve.Bezier,
    split_hodograph: curve.Bezier,
    active: bool = true,
    editable: bool = false,
    show_approximation: bool = false,
    draw_flags: DebugDrawCurveFlags = .{},
};

const projTmpTest = struct {
    a2b: VisCurve,
    b2c: VisCurve,
};

fn _is_between(
    val: f32,
    fst: f32,
    snd: f32
) bool 
{
    return (
        (fst <= val and val < snd) 
        or (fst >= val and val > snd)
    );
}

const VisTransform = struct {
    topology: topology.Topology = topology.INFINITE_IDENTIY,
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

pub fn main(
) !void 
{
    const title = (
        "OpenTimelineIO V2 Prototype Bezier Curve Visualizer [" 
        ++ build_options.hash[0..6] 
        ++ "]"
    );

    const builtin = @import("builtin");

    ALLOCATOR = alloc: {
        if (builtin.os.tag == .emscripten) {
            break :alloc std.heap.c_allocator;
        } else {
            var gpa = std.heap.GeneralPurposeAllocator(
                .{}
            ){};

            break :alloc gpa.allocator();
        }
    };
    const allocator = ALLOCATOR;

    STATE = try _parse_args(allocator);

    const built_in_curve_data = struct{
        const upside_down_u = @embedFile("upside_down_u.curve.json");
    };

    // u
    const fst_name:[:0]const u8 = "upside down u";
    const fst_crv = try curve.read_bezier_curve_data(
        allocator,
        built_in_curve_data.upside_down_u
    );
    defer fst_crv.deinit(allocator);

    const identSeg = curve.Bezier.Segment.init_identity(-3, 3) ;
    const snd_crv = try curve.Bezier.init(
        allocator,
        &.{identSeg}
    );
    defer snd_crv.deinit(allocator);
    const snd_name:[:0]const u8 ="linear [-0.2, 1)" ;

    TMPCURVES = projTmpTest{
        // projecting "snd" through "fst"
        .b2c = .{ 
            .curve = fst_crv,
            .fpath = fst_name,
            .split_hodograph = try fst_crv.split_on_critical_points(allocator),
        },
        .a2b = .{ 
            .curve = snd_crv,
            .fpath = snd_name,
            .split_hodograph = try snd_crv.split_on_critical_points(allocator),
        },
    };
    defer TMPCURVES.a2b.split_hodograph.deinit(allocator);
    defer TMPCURVES.b2c.split_hodograph.deinit(allocator);
    defer STATE.deinit(allocator);

    sokol_app_wrapper.sokol_main(
        .{
            .title = title,
            .draw = update,
            .content_dir = content_dir,
            .dimensions = .{ 1600, 1000},
        }
    );
}

pub fn evaluated_curve(
    crv: curve.Bezier,
    comptime steps:usize
) !struct{ xv: [steps]f32, yv: [steps]f32 }
{
    if (crv.segments.len == 0) {
        return .{ .xv = undefined, .yv = undefined };
    }

    const ext = crv.extents();
    const stepsize:f32 = (ext[1].in - ext[0].in) / @as(f32, steps);

    var xv:[steps]f32 = undefined;
    var yv:[steps]f32 = undefined;

    var i:usize = 0;
    var uv:f32 = ext[0].in;
    for (crv.segments) 
        |seg| 
    {
        uv = seg.p0.in;

        while (i < steps - 1) 
            : (i += 1) 
        {
            // guarantee that it hits the end point
            if (uv > seg.p3.in) 
            {
                xv[i] = seg.p3.in;
                yv[i] = seg.p3.out;
                i += 1;

                break;
            }

            // should not ever be hit
            errdefer std.log.err(
                "error: uv was: {:0.3} extents: {any:0.3}\n",
                .{ uv, ext }
            );

            const p = crv.output_at_input(uv) catch blk: {
                break :blk ext[0].out;
            };

            xv[i] = uv;
            yv[i] = p;

            uv += stepsize;
        }
    }

    if (crv.segments.len > 0) {
        const end_point = crv.segments[crv.segments.len - 1].p3;

        xv[steps - 1] = end_point.in;
        yv[steps - 1] = end_point.out;
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

    for (points, xv, yv) 
        |p, *x, *y| 
    {
        x.* = p.in;
        y.* = p.out;
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
            .xv = &.{pt.in},
            .yv = &.{pt.out},
        }
    );
    zgui.plot.plotText(
        short_label,
        .{
            .x = pt.in,
            .y = pt.out,
            .pix_offset = .{ 0, size * 1.75 },
        }
    );
    zgui.plot.popStyleVar(.{ .count = 1 });
}

fn plot_knots(
    hod: curve.Bezier, 
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

        for (endpoints, 0..) 
            |knot, knot_ind| 
        {
            knots_xv[knot_ind] = knot.in;
            knots_yv[knot_ind] = knot.out;
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

        for (endpoints, 0..) 
            |pt, pt_ind| 
        {
            const label = try std.fmt.bufPrintZ(&buf, "{d}", .{ pt_ind });
            zgui.plot.plotText(
                label,
                .{ .x = pt.in, .y = pt.out, .pix_offset = .{ 0, 45 } }
            );
        }

        zgui.plot.popStyleVar(.{ .count = 1 });
    }
}

fn plot_control_points(
    hod: curve.Bezier, 
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
        for (hod.segments, 0..) 
            |seg, seg_ind| 
        {
            for (seg.points(), 0..) 
                |pt, pt_ind| 
            {
                knots_xv[seg_ind * 4 + pt_ind] = pt.in;
                knots_yv[seg_ind * 4 + pt_ind] = pt.out;
                const pt_text = try std.fmt.bufPrintZ(
                    buf[512..],
                    "{d}.{d}: ({d:0.2}, {d:0.2})",
                    .{ seg_ind, pt_ind, pt.in, pt.out },
                );
                zgui.plot.plotText(
                    pt_text,
                    .{.x = pt.in, .y = pt.out, .pix_offset = .{0, 36}} 
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
    lin:curve.Linear,
    name:[:0]const u8,
    allocator:std.mem.Allocator
) !void
{
    var xv:[]f32 = try allocator.alloc(f32, lin.knots.len);
    defer allocator.free(xv);
    var yv:[]f32 = try allocator.alloc(f32, lin.knots.len);
    defer allocator.free(yv);

    for (lin.knots, 0..) 
        |knot, knot_index| 
    {
        xv[knot_index] = knot.in;
        yv[knot_index] = knot.out;
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
    crv:*curve.Bezier,
    name:[:0]const u8,
    allocator:std.mem.Allocator
) !void 
{
    const col: [4]f32 = .{ 1, 0, 0, 1 };

    var hasher = std.hash.Wyhash.init(0);
    for (name) 
        |char| 
    {
        std.hash.autoHash(&hasher, char);
    }

    for (crv.segments, 0..) 
        |*seg, seg_ind| 
    {
        std.hash.autoHash(&hasher, seg_ind);

        var in_pts = seg.points();
        var times: [4]f64 = .{ 
            @floatCast(in_pts[0].in),
            @floatCast(in_pts[1].in),
            @floatCast(in_pts[2].in),
            @floatCast(in_pts[3].in),
        };
        var values: [4]f64 = .{ 
            @floatCast(in_pts[0].out),
            @floatCast(in_pts[1].out),
            @floatCast(in_pts[2].out),
            @floatCast(in_pts[3].out),
        };

        inline for (0..4) 
            |idx| 
        {
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
                .in = @floatCast(times[idx]),
                .out = @floatCast(values[idx]),
            };
        }

        seg.set_points(in_pts);
    }

    try plot_bezier_curve(crv.*, name, .{}, allocator);
}

fn plot_bezier_curve(
    crv:curve.Bezier,
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
        for (crv.segments) 
            |seg| 
        {
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
            var x = seg.p0.in;
            const xmax = seg.p3.in;
            const step = (xmax - x) / 10.0;

            while (x < xmax)
                : (x += step)
            {
                const u_at_x = seg.findU_input_dual(x);
                const pt = seg.eval_at_dual(u_at_x);

                xv[0] = x;
                xv[1] = pt.r.in;

                yv[0] = crv_extents[0].out;
                yv[1] = pt.r.out;

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
                        d_du.r.in,
                        d_du.r.in + d_du.i.in,
                    };
                    const yv : [2]f32 = .{
                        d_du.r.out,
                        d_du.r.out + d_du.i.out,
                    };

                    zgui.plot.plotLine(
                        deriv_label_ddu,
                        f32,
                        .{ .xv = &xv, .yv = &yv }
                    );
                }

                if (flags.derivatives_dydx) 
                {
                    const d_dx = seg.output_at_input_dual(d_du.r.in);

                    const xv : [2]f32 = .{
                        d_dx.r.in,
                        d_dx.r.in + d_dx.i.in,
                    };
                    const yv : [2]f32 = .{
                        d_dx.r.out,
                        d_dx.r.out + d_dx.i.out,
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
                        d_du.r.in,
                        d_du.r.in + hodo_d_du.x,
                    };
                    const yv : [2]f32 = .{
                        d_du.r.out,
                        d_du.r.out + hodo_d_du.y,
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
                    const d_dx = seg.output_at_input_dual(d_du.r.in);

                    const xv : [3]f32 = .{
                        d_dx.r.in - d_dx.i.in,
                        d_dx.r.in,
                        d_dx.r.in + d_dx.i.in,
                    };
                    const yv : [3]f32 = .{
                        d_dx.r.out - d_dx.i.out,
                        d_dx.r.out,
                        d_dx.r.out + d_dx.i.out,
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
                const d_dx = seg.output_at_input_dual(d_du.r.in);

                const xv : [3]f32 = .{
                    d_dx.r.in - d_dx.i.in,
                    d_dx.r.in,
                    d_dx.r.in + d_dx.i.in,
                };
                const yv : [3]f32 = .{
                    d_dx.r.out - d_dx.i.out,
                    d_dx.r.out,
                    d_dx.r.out + d_dx.i.out,
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
                        I1.in,
                        I2.in,
                        I3.in,
                    };
                    const yv = [_]f32{
                        I1.out,
                        I2.out,
                        I3.out,
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
                        e1.in,
                        e2.in,
                    };
                    const yv = [_]f32{
                        e1.out,
                        e2.out,
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
        try plot_cp_line(
            "A->C",
            &.{ guts.A.?, guts.C.? },
            allocator,
        );
        const a = guts.A.?;
        const baseline_len = guts.C.?.distance(a);
        const label = try std.fmt.bufPrintZ(
            &buf,
            "A->C length {d}\nt: {d}",
            .{ baseline_len, guts.t.? }
        );
        zgui.plot.plotText(
            label,
            .{ 
                .x = guts.A.?.in, 
                .y = guts.A.?.out,
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
                .x = guts.start.?.in, 
                .y = guts.start.?.out,
                .pix_offset = .{ 0, 60 }
            }
        );
    }

    if (flags.start_ddt and guts.start_ddt != null) {
        const ddt = guts.start_ddt.?;
        const off = guts.start.?.add(ddt);

        const xv = &.{ guts.start.?.in, off.in };
        const yv = &.{ guts.start.?.out, off.out };

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

        const xv = &.{ guts.end.?.in, off.in };
        const yv = &.{ guts.end.?.out, off.out };

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

        const xv = &.{ e1.in, guts.midpoint.?.in, e2.in };
        const yv = &.{ e1.out, guts.midpoint.?.out, e2.out };

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
                .{d.in, d.out, e1.distance(guts.midpoint.?) },
            );
            zgui.plot.plotText(
                d_label,
                .{ 
                    .x = e1.in, 
                    .y = e1.out, 
                    .pix_offset = .{ 0, 48 } 
                },
                );
        }
    }

    if (flags.v1_2) 
    {
        const v1 = guts.v1.?;
        const v2 = guts.v2.?;

        const xv = &.{ v1.in,  guts.A.?.in,  v2.in };
        const yv = &.{ v1.out, guts.A.?.out, v2.out };

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

        // const xv = &.{ v1.in,  mid_point.in,  v2.in };
        // const yv = &.{ v1.out, mid_point.out, v2.out };

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
    crv: curve.Bezier,
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
    var approx_segments = std.ArrayList(curve.Bezier.Segment).init(allocator);
    defer approx_segments.deinit();

    for (crv.segments) 
        |seg| 
    {
        if (seg.p0.in > 0) {
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
        //         .in = d_midpoint_dt.x,
        //         .out = d_midpoint_dt.y,
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

    const approx_crv = try curve.Bezier.init(
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
    crv: curve.Bezier,
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
    var approx_segments = std.ArrayList(curve.Bezier.Segment).init(allocator);
    defer approx_segments.deinit();

    const u_vals:[]const f32 = &.{0, 0.25, 0.5, 0.75, 1};
    const u_names = &.{"u_0", "u_1_4", "u_1_2", "u_3_4", "u_1"};
    var u_bools : [u_names.len]bool = undefined;

    inline for (u_names, 0..) 
        |n, i| 
    {
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
                .in = d_midpoint_dt.x,
                .out = d_midpoint_dt.y,
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

        const approx_crv = try curve.Bezier.init(
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

var STATE : VisState = undefined;
var TMPCURVES : projTmpTest = undefined; 
var ALLOCATOR : std.mem.Allocator = undefined;

fn update() !void
{
    update_with_error() catch {
        @panic("update hit an error");
    };
}

var first_time = true;

fn update_with_error(
) !void 
{
    if (first_time) {
        
    }

    var _proj = topology.Topology.init_identity_infinite(allocator);
    const inf = topology.Topology.init_identity_infinite(allocator);

    for (STATE.operations.items) 
        |visop| 
    {
        var _topology: topology.Topology = .{ .empty = .{} };

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

        const tmp = _proj;
        _proj = _topology.project_topology(
            ALLOCATOR,
            _proj
        ) catch inf;
        tmp.deinit(ALLOCATOR);
    }

    zgui.setNextWindowPos(.{ .x = 0.0, .y = 0.0, });

    const vp = zgui.getMainViewport();
    const size = vp.getSize();

    const width:f32 = size[0];
    const height:f32 = size[1];

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
        std.debug.print("early end\n", .{});
        return;
    }
    defer zgui.end();

    // FPS/status line
    zgui.bulletText(
        "Average : frame ({d:.1} fps)",
        .{ zgui.io.getFramerate() },
    );
    zgui.spacing();

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
                for (STATE.operations.items, 0..) 
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

                            try plot_curve(crv, name, ALLOCATOR);
                        },
                        else => {},
                    }
                }

                if (STATE.show_projection_result) 
                {
                    switch (_proj) 
                    {
                        .linear_curve => |lint| { 
                            const lin = lint.curve;
                            try plot_linear_curve(
                                lin,
                                "result / linear",
                                ALLOCATOR
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

                if (STATE.show_test_curves) 
                {
                    // debug 
                    const self = TMPCURVES.a2b.curve;
                    const other = TMPCURVES.b2c.curve;

                    try plot_bezier_curve(
                        self,
                        "self",
                        STATE.show_projection_result_guts.fst,
                        ALLOCATOR
                    );
                    try plot_bezier_curve(
                        other,
                        "other",
                        STATE.show_projection_result_guts.snd,
                        ALLOCATOR
                    );

                    //
                    const self_hodograph = try self.split_on_critical_points(ALLOCATOR);
                    defer self_hodograph.deinit(ALLOCATOR);

                    const other_hodograph = try other.split_on_critical_points(ALLOCATOR);
                    defer other_hodograph.deinit(ALLOCATOR);
                    //
                    const other_bounds = other.extents();
                    var other_copy = try curve.Bezier.init(
                        ALLOCATOR,
                        other_hodograph.segments,
                    );

                    {
                        var split_points = std.ArrayList(f32).init(ALLOCATOR);
                        defer split_points.deinit();

                        // find all knots in self that are within the other bounds
                        const endpoints = try self_hodograph.segment_endpoints(
                            ALLOCATOR
                        );
                        defer ALLOCATOR.free(endpoints);

                        for (endpoints)
                            |self_knot| 
                        {
                            if (
                                _is_between(
                                    self_knot.in,
                                    other_bounds[0].out,
                                    other_bounds[1].out
                                )
                            ) {
                                try split_points.append(self_knot.in);
                            }

                        }

                        var result = try other_copy.split_at_each_output_ordinate(
                            ALLOCATOR,
                            split_points.items,
                        );
                        const tmp = other_copy;
                        other_copy = try curve.Bezier.init(
                            ALLOCATOR,
                            result.segments,
                        );
                        tmp.deinit(ALLOCATOR);
                        result.deinit(ALLOCATOR);
                    }

                     defer other_copy.deinit(ALLOCATOR);

                     const result_guts = try self_hodograph.project_curve_guts(
                         ALLOCATOR,
                         other_hodograph,
                     );
                     defer result_guts.deinit();

                     try plot_bezier_curve(
                         result_guts.self_split.?,
                         "self_split",
                         STATE.show_projection_result_guts.self_split,
                         ALLOCATOR
                     );

                     zgui.text("Segments to project through indices: ", .{});
                     for (result_guts.segments_to_project_through.?) 
                     |ind| 
                     {
                         zgui.text("{d}", .{ ind });
                     }

                     try plot_bezier_curve(
                         result_guts.other_split.?,
                         "other_split",
                         STATE.show_projection_result_guts.other_split,
                         ALLOCATOR
                     );

                     var buf:[1024:0]u8 = undefined;
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
                             STATE.show_projection_result_guts.tpa_flags.result_curves,
                             ALLOCATOR
                         );
                     }

                     {
                         try plot_bezier_curve(
                             result_guts.to_project.?,
                             "Segments of Other that will be projected",
                             STATE.show_projection_result_guts.to_project,
                             ALLOCATOR
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
                                 STATE.show_projection_result_guts.tpa_flags,
                                 ALLOCATOR,
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
                         if (@field(STATE, d_name))
                         {
                             for (@field(result_guts, d_name).?, 0..) 
                                 |d, ind|
                             {
                                 const midpoint = result_guts.tpa.?[ind].midpoint.?;
                                 const p1 = midpoint.add(d);
                                 const p2 = midpoint.sub(d);

                                 const xv = &.{ p1.in,  midpoint.in,  p2.in };
                                 const yv = &.{ p1.out, midpoint.out, p2.out };

                                 zgui.plot.plotLine(
                                     d_name,
                                     f32,
                                     .{ .xv = xv, .yv = yv }
                                 );
                                 {
                                     const label = try std.fmt.bufPrintZ(
                                         &buf,
                                         "d/dt: ({d:0.6}, {d:0.6})",
                                         .{d.in, d.out},
                                     );
                                     zgui.plot.plotText(
                                         label,
                                         .{ 
                                             .x = p1.in, 
                                             .y = p1.out, 
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
                    .window_flags = zgui.WindowFlags{ .no_scrollbar = false} 
                }
            )
        ) 
        {
            _ = zgui.checkbox(
                "Show ZGui Demo Windows",
                .{ .v = &STATE.show_demo }
            );
            _ = zgui.checkbox(
                "Show Projection Test Curves",
                .{ .v = &STATE.show_test_curves }
            );
            _ = zgui.checkbox(
                "Show Projection Result",
                .{ .v = &STATE.show_projection_result }
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


            if (STATE.show_test_curves and zgui.treeNode("Test Curve Settings"))
            {
                defer zgui.treePop();

                {
                    var guts = STATE.show_projection_result_guts;
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
                            .{ .v = &@field(STATE,d_info[0]) }
                        );
                    }
                }

                STATE.show_projection_result_guts.tpa_flags.draw_ui(
                    "Projection Result"
                );
            }

            var remove = std.ArrayList(usize).init(ALLOCATOR);
            defer remove.deinit();
            const op_index:usize = 0;
            for (STATE.operations.items) 
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
                                                seg.p0.in,
                                                seg.p1.in,
                                                seg.p2.in,
                                                seg.p3.in,
                                            )
                                        },
                                    );

                                    zgui.bulletText(
                                        "Measured Order [value]: {d}",
                                        .{ 
                                            try curve.bezier_math.actual_order(
                                                seg.p0.out,
                                                seg.p1.out,
                                                seg.p2.out,
                                                seg.p3.out,
                                            )
                                        },
                                    );

                                    // dy/dx
                                    {
                                        const d_p0 = seg.output_at_input_dual(
                                            seg.p0.in
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] dy/dx at p0: {}",
                                            .{
                                                ind,
                                                d_p0.i.in,
                                            },
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] p1-p0: {}",
                                            .{
                                                ind,
                                                seg.p1.in - seg.p0.in,
                                            },
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] (dy/dx) / (p1-p0): {}",
                                            .{
                                                ind,
                                                (
                                                 d_p0.i.in 
                                                 / (
                                                     seg.p1.in 
                                                     - seg.p0.in
                                                 )
                                                ),
                                            },
                                        );

                                        const d_p3 = seg.output_at_input_dual(
                                            seg.p3.in
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] dy/dx at p3: {}",
                                            .{
                                                ind,
                                                d_p3.i.in,
                                            },
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] p3-p2: {}",
                                            .{
                                                ind,
                                                seg.p3.in - seg.p2.in,
                                            },
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] (dy/dx) / (p3-p2): {}",
                                            .{
                                                ind,
                                                d_p3.i.in / (seg.p3.in - seg.p2.in),
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
                                                d_p0.i.in,
                                            },
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] p1-p0: {}",
                                            .{
                                                ind,
                                                seg.p1.in - seg.p0.in,
                                            },
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] (dy/du) / (p1-p0): {}",
                                            .{
                                                ind,
                                                d_p0.i.in / (
                                                    seg.p1.in - seg.p0.in
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
                                                d_p3.i.in,
                                            },
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] p3-p2: {}",
                                            .{
                                                ind,
                                                seg.p3.in - seg.p2.in,
                                            },
                                        );
                                        zgui.bulletText(
                                            "[Seg: {}] (dy/du) / (p3-p2): {}",
                                            .{
                                                ind,
                                                d_p3.i.in / (seg.p3.in - seg.p2.in),
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
                            if (zgui.treeNode("Original Knots")) {
                                defer zgui.treePop();

                                const endpoints = (
                                    try crv.curve.segment_endpoints(ALLOCATOR)
                                );
                                defer ALLOCATOR.free(endpoints);
                                for (endpoints, 0..) 
                                    |pt, ind| 
                                {
                                    zgui.bulletText(
                                        "{d}: ({d}, {d})",
                                        .{ ind, pt.in, pt.out },
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

                                const split = try crv.curve.split_on_critical_points(ALLOCATOR);
                                defer split.deinit(ALLOCATOR);

                                const endpoints = try split.segment_endpoints(
                                    ALLOCATOR,
                                );
                                defer ALLOCATOR.free(endpoints);

                                for (endpoints, 0..) 
                                    |pt, ind| 
                                {
                                    zgui.bulletText(
                                        "{d}: ({d}, {d})",
                                        .{ ind, pt.in, pt.out },
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
                                    .v = &xform.topology.transform.offset
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
                const visop = STATE.operations.orderedRemove(remove.items[i]);
                switch (visop) {
                    .curve => |crv| {
                        ALLOCATOR.free(crv.curve.segments);
                        ALLOCATOR.free(crv.split_hodograph.segments);
                        ALLOCATOR.free(crv.fpath);
                    },
                    else => {},
                }
            }
        }
        defer zgui.endChild();
    }

    if (STATE.show_demo) {
        _ = zgui.showDemoWindow(null);
        _ = zgui.plot.showDemoWindow(null);
    }

    _proj.deinit(ALLOCATOR);
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
