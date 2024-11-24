//! Bezier Math components to use with curves

const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

const comath = @import("comath");

const control_point = @import("control_point.zig");
const bezier_curve = @import("bezier_curve.zig");
const linear_curve = @import("linear_curve.zig");
const generic_curve = @import("generic_curve.zig");
const opentime = @import("opentime");


inline fn expectApproxEql(
    expected: anytype,
    actual: @TypeOf(expected),
) !void 
{
    return std.testing.expectApproxEqAbs(
        expected,
        actual,
        generic_curve.EPSILON
    );
}

/// comath context for operations on duals
pub const CTX = comath.ctx.fnMethod(
    comath.ctx.simple(opentime.dual_ctx),
    .{
        .@"+" = "add",
        .@"-" = &.{"sub", "negate", "neg",},
        .@"*" = "mul",
        .@"/" = "div",
        .@"cos" = "cos",
    },
);

/// lerp from a to b by amount u, [0, 1], using comath
pub fn lerp(
    u: anytype,
    a: anytype,
    b: @TypeOf(a),
) @TypeOf(a) 
{
    return comath.eval(
        "(a * ((-u) + 1.0)) + (b * u)",
        CTX,
        .{
            .a = a,
            .b = b,
            .u = u,
        }
    ) catch @panic("lerp error");
}

pub fn invlerp(
    v: anytype,
    a: anytype,
    b: @TypeOf(a),
) @TypeOf(a)
{
    if (opentime.eql(b, a)) {
        return a;
    }
    return comath.eval(
        "(v - a)/(b - a)",
        CTX,
        .{
            .v = v,
            .a = a,
            .b = b,
        }
    ) catch |err| switch (err) {};
}

pub fn output_at_input_between(
    t: opentime.Ordinate,
    fst: control_point.ControlPoint,
    snd: control_point.ControlPoint,
) opentime.Ordinate 
{
    const u = invlerp(t, fst.in, snd.in);
    return lerp(u, fst.out, snd.out);
}

pub fn input_at_output_between(
    v: opentime.Ordinate,
    fst: control_point.ControlPoint,
    snd: control_point.ControlPoint,
) opentime.Ordinate 
{
    const u = invlerp(v, fst.out, snd.out);
    return lerp(u, fst.in, snd.in);
}

// dual variety
pub fn segment_reduce4_dual(
    u: opentime.Dual_Ord, 
    segment: [4]control_point.Dual_CP
) [4]control_point.Dual_CP 
{
    return .{
        lerp(u, segment[0], segment[1]),
        lerp(u, segment[1], segment[2]),
        lerp(u, segment[2], segment[3]),
        .{}
    };
}

pub fn segment_reduce3_dual(
    u: opentime.Dual_Ord,
    segment: [4]control_point.Dual_CP
) [4]control_point.Dual_CP 
{
    return .{
        lerp(u, segment[0], segment[1]),
        lerp(u, segment[1], segment[2]),
        .{},
        .{},
    };
}

pub fn segment_reduce2_dual(
    u: opentime.Dual_Ord,
    segment: [4]control_point.Dual_CP
) [4]control_point.Dual_CP 
{
    return .{
        lerp(u, segment[0], segment[1]),
        .{},
        .{},
        .{},
    };
}

pub fn segment_reduce4(
    u: opentime.Ordinate,
    segment: bezier_curve.Bezier.Segment,
) bezier_curve.Bezier.Segment 
{
    return .{
        .p0 = lerp(u, segment.p0, segment.p1),
        .p1 = lerp(u, segment.p1, segment.p2),
        .p2 = lerp(u, segment.p2, segment.p3),
    };
}

pub fn segment_reduce3(
    u: opentime.Ordinate,
    segment: bezier_curve.Bezier.Segment,
) bezier_curve.Bezier.Segment 
{
    return .{
        .p0 = lerp(u, segment.p0, segment.p1),
        .p1 = lerp(u, segment.p1, segment.p2),
    };
}

pub fn segment_reduce2(
    u: opentime.Ordinate,
    segment: bezier_curve.Bezier.Segment,
) bezier_curve.Bezier.Segment 
{
    return .{
        .p0 = lerp(u, segment.p0, segment.p1),
    };
}

// evaluate a 1d bezier whose first point is 0.
pub fn _bezier0(
    unorm: opentime.Ordinate,
    p2: opentime.Ordinate,
    p3: opentime.Ordinate,
    p4: opentime.Ordinate,
) opentime.Ordinate
{
    return try comath.eval(
        (
         "u*u*u * p4" 
         ++ " - (p3 * u*u*zmo*3.0)"
         ++ " + (p2 * 3.0 * u * zmo * zmo)"
        ),
        CTX,
        .{
            .u = unorm,
            .zmo = unorm.sub(1),
            .p2 = p2,
            .p3 = p3,
            .p4 = p4,
        }
    );
    // const p1 = 0.0;
    // const z = unorm;
    // const z2 = z*z;
    // const z3 = z2*z;
    //
    // const zmo = z-1.0;
    // const zmo2 = zmo*zmo;
    // const zmo3 = zmo2*zmo;
    //
    // return (p4 * z3) 
    //     - (p3 * (3.0*z2*zmo))
    //     + (p2 * (3.0*z*zmo2))
    //     - (p1 * zmo3);
}

pub fn _bezier0_dual(
    unorm: opentime.Dual_Ord,
    p2: opentime.Ordinate,
    p3: opentime.Ordinate,
    p4: opentime.Ordinate,
) opentime.Dual_Ord
{
    // original math (p1 = 0, so last term falls out)
    // return (p4 * z3) 
    //     - (p3 * (3.0*z2*zmo))
    //     + (p2 * (3.0*z*zmo2))
    //     - (p1 * zmo3);
    return try comath.eval(
        (
         "u*u*u * p4" 
         ++ " - (p3 * u*u*zmo*3.0)"
         ++ " + (p2 * 3.0 * u * zmo * zmo)"
        ),
        CTX,
        .{
            .u = unorm,
            .zmo = unorm.add(opentime.Dual_Ord.from(-1.0)),
            .p2 = opentime.Dual_Ord.from(p2),
            .p3 = opentime.Dual_Ord.from(p3),
            .p4 = opentime.Dual_Ord.from(p4),
        }
    );
}

///
/// Given x in the interval [0, p3], and a monotonically nondecreasing
/// 1-D Bezier bezier_curve, B(u), with control points (0, p1, p2, p3), find
/// u so that B(u) == x.
///
pub fn _findU(
    x:opentime.Ordinate,
    p1:opentime.Ordinate,
    p2:opentime.Ordinate,
    p3:opentime.Ordinate,
) opentime.Ordinate
{
    const MAX_ABS_ERROR = opentime.Ordinate.init(
        std.math.floatEps(opentime.Ordinate.BaseType) * 2.0
    );
    const MAX_ITERATIONS: u8 = 45;

    if (opentime.lteq(x, opentime.Ordinate.ZERO)) {
        return opentime.Ordinate.ZERO;
    }

    if (opentime.gteq(x, p3)) {
        return opentime.Ordinate.ONE;
    }

    var _u1=opentime.Ordinate.ZERO;
    var _u2=opentime.Ordinate.ZERO;

    var x1 = x.neg(); // same as: bezier0 (0, p1, p2, p3) - x;
    var x2 = opentime.eval(
        "p3 - x",
        .{ .p3 = p3, .x = x }
    ); // same as: bezier0 (1, p1, p2, p3) - x;

    {
        const _u3 = opentime.eval(
            "ONE - (x2 / (x2 - x1))",
            .{ .ONE = opentime.Ordinate.ONE, .x2 = x2, .x1 = x1 }
        );
        const x3 = _bezier0(
            _u3,
            p1,
            p2,
            p3,
        ).sub(x);

        if (x3.eql(0)) {
            return _u3;
        }

        if (x3.lt(0))
        {
            if (opentime.Ordinate.ONE.sub(_u3).lteq(MAX_ABS_ERROR)) {
                if (x2.lt(x3.neg())) {
                    return opentime.Ordinate.ONE;
                }

                return _u3;
            }

            _u1 = opentime.Ordinate.ONE;
            x1 = x2;
        }
        else
        {
            _u1 = opentime.Ordinate.ZERO;
            x1 = opentime.eval(
                "x1 * x2 / (x2 + x3)",
                .{ .x1 = x1, .x2 = x2, .x3 = x3 }
            );

            if (_u3.lteq(MAX_ABS_ERROR)) 
            {
                if (x1.neg().lt(x3)) {
                    return opentime.Ordinate.ZERO;
                }

                return _u3;
            }
        }
        _u2 = _u3;
        x2 = x3;
    }

    var i: u8 = MAX_ITERATIONS - 1;

    while (i > 0) 
        : (i -= 1)
    {
        const _u3:opentime.Ordinate = opentime.eval(
            "_u2 - x2 * ((_u2 - _u1) / (x2 - x1))",
            .{ ._u2 = _u2, .x2 = x2, ._u1 = _u1, .x1 = x1 },
        );
        const x3 = _bezier0 (_u3, p1, p2, p3).sub(x);

        if (x3.eql(0)) {
            return _u3;
        }

        if (x2.mul(x3).lteq(0))
        {
            _u1 = _u2;
            x1 = x2;
        }
        else
        {
            x1 = opentime.eval(
                "x1 * x2 / (x2 + x3)",
                .{ .x1 = x1, .x2 = x2, .x3 = x3 }
            );
        }

        _u2 = _u3;
        x2 = x3;

        if (_u2.gt(_u1))
        {
            if (_u2.sub(_u1).lteq(MAX_ABS_ERROR)) {
                break;
            }
        }
        else
        {
            if (_u1.sub(_u2).lteq(MAX_ABS_ERROR)) {
                break;
            }
        }
    }

    if (x1.lt(0)) {
        x1 = x1.neg();
    }
    if (x2.lt(0)) {
        x2 = x2.neg();
    }

    if (x1.lt(x2)) {
        return _u1;
    }

    return _u2;
}

fn first_valid_root(
    possible_roots: [] const opentime.Dual_Ord,
) opentime.Dual_Ord
{
    for (possible_roots)
        |root|
    {
        if (
            opentime.Ordinate.ZERO.lteq(root.r) 
            and root.r.lteq(opentime.Ordinate.ONE)
        )
        {
            return root;
        }
    }

    return possible_roots[0];
}

/// cube root function yielding real roots
inline fn crt(
    v:opentime.Dual_Ord
) opentime.Dual_Ord
{
    if (v.r.lt(0)) {
        return ((v.negate()).pow(1.0/3.0)).negate();
    } 
    else {
        return (v.pow(1.0/3.0));
    }
}

/// calculate the actual order of the bezier.  IE if its linear, return 1,
/// quadratic return 2, cubic return 3.
pub fn actual_order(
    p0: opentime.Ordinate,
    p1: opentime.Ordinate,
    p2: opentime.Ordinate,
    p3: opentime.Ordinate,
) !u8 
{
    const d = try comath.eval(
        "(-pa) + (pb * 3.0) - (pc * 3.0) + pd",
        CTX,
        .{ 
            .pa = p0,
            .pb = p1,
            .pc = p2,
            .pd = p3,
        },
    );

    const a = try comath.eval(
        // "(pa * 3.0) - (pb * 6.0) + (pc * 3.0)",
        "pa * 3.0 - pb * 6.0 + pc * 3.0",
        CTX,
        .{ 
            .pa = p0,
            .pb = p1,
            .pc = p2,
        },
    );

    const b = try comath.eval(
        "(-pa * 3.0) + (pb * 3.0)",
        CTX,
        .{ 
            .pa = p0,
            .pb = p1,
        },
    );

    if (opentime.lt(d.abs(), opentime.Ordinate.EPSILON))
    {
        // not cubic
        if (opentime.lt(a.abs(), opentime.Ordinate.EPSILON))
        {
            // linear
            if (opentime.lt(b.abs(), opentime.Ordinate.EPSILON))
            {
                return error.NoSolution;
            }

            return 1;
        }
        return 2;
    }

    return 3;
}

test "bezier_math: actual_order: linear" 
{
    const crv = try bezier_curve.read_curve_json(
        "curves/linear.curve.json",
        std.testing.allocator
    );
    defer std.testing.allocator.free(crv.segments);

    const seg = crv.segments[0];

    try expectEqual(
        1,
        try actual_order(
            seg.p0.in,
            seg.p1.in,
            seg.p2.in,
            seg.p3.in,
        )
    );
    try expectEqual(
        1,
        try actual_order(
            seg.p0.out,
            seg.p1.out,
            seg.p2.out,
            seg.p3.out,
        )
    );
}

test "bezier_math: actual_order: quadratic" 
{
    const crv = try bezier_curve.read_curve_json(
        "curves/upside_down_u.curve.json",
        std.testing.allocator
    );
    defer std.testing.allocator.free(crv.segments);

    const seg = crv.segments[0];

    // cubic over time
    try expectEqual(
        @as(u8, 3),
        try actual_order(
            seg.p0.in,
            seg.p1.in,
            seg.p2.in,
            seg.p3.in
        )
    );
    // quadratic over value
    try expectEqual(
        @as(u8, 2),
        try actual_order(
            seg.p0.out,
            seg.p1.out,
            seg.p2.out,
            seg.p3.out
        )
    );
}

test "bezier_math: actual_order: cubic" 
{
    const crv = try bezier_curve.read_curve_json(
        "curves/scurve_extreme.curve.json",
        std.testing.allocator
    );
    defer std.testing.allocator.free(crv.segments);

    const seg = crv.segments[0];

    try expectEqual(
        @as(u8, 3),
        try actual_order(seg.p0.in, seg.p1.in, seg.p2.in, seg.p3.in)
    );
    try expectEqual(
        @as(u8, 3),
        try actual_order(seg.p0.out, seg.p1.out, seg.p2.out, seg.p3.out)
    );
}

pub fn findU_dual3(
    x_input: opentime.Ordinate,
    p0: opentime.Ordinate,
    p1: opentime.Ordinate,
    p2: opentime.Ordinate,
    p3: opentime.Ordinate,
) opentime.Dual_Ord
{
    // assumes that p3 > p0
    const x = opentime.min(opentime.max(x_input, p0), p3);

    const p0_d = opentime.Dual_Ord{.r = p0.sub(x), .i = opentime.Ordinate.init(-1)};
    const p1_d = opentime.Dual_Ord{.r = p1.sub(x), .i = opentime.Ordinate.init(-1)};
    const p2_d = opentime.Dual_Ord{.r = p2.sub(x), .i = opentime.Ordinate.init(-1)};
    const p3_d = opentime.Dual_Ord{.r = p3.sub(x), .i = opentime.Ordinate.init(-1)};

    const d = comath.eval(
        // "(-pa) + (pb * 3.0) - (pc * 3.0) + pd",
        "(-pa) + (pb * 3.0) - (pc * 3.0) + pd",
        CTX,
        .{ 
            .pa = p0_d,
            .pb = p1_d,
            .pc = p2_d,
            .pd = p3_d,
        },
    ) catch @panic("comath error 1");

    var a = comath.eval(
        // "(pa * 3.0) - (pb * 6.0) + (pc * 3.0)",
        "pa * 3.0 - pb * 6.0 + pc * 3.0",
        CTX,
        .{ 
            .pa = p0_d,
            .pb = p1_d,
            .pc = p2_d,
        },
    ) catch @panic("comath error 2");

    var b = comath.eval(
        "(-pa * 3.0) + (pb * 3.0)",
        CTX,
        .{ 
            .pa = p0_d,
            .pb = p1_d,
        },
    ) catch @panic("comath dual error 3");

    var c = p0_d;

    if (opentime.lt(opentime.abs(d.r), opentime.Ordinate.EPSILON))
    {
        // not cubic
        if (opentime.lt(opentime.abs(a.r), opentime.Ordinate.EPSILON))
        {
            // linear
            if (opentime.lt(opentime.abs(b.r), opentime.Ordinate.EPSILON))
            {
                // no solutions
                return .{
                    .r = opentime.Ordinate.NAN,
                    .i = opentime.Ordinate.NAN,
                };
            }

            return try comath.eval(
                "(-c) / b", 
                CTX,
                .{ .c = c, .b = b }
            );
        }

        // quadratic
        const q2 = try comath.eval(
            "(b * b) - (a * c * 4.0)",
            CTX,
            .{ .b = b, .a = a, .c = c},
        );
        const q = q2.sqrt();

        const a2 = a.mul(2.0);

        const pos_sol = try comath.eval(
            "(q - b) / a2",
            CTX,
            .{ .q = q, .b = b, .a2 = a2 }
        );

        if (
            opentime.Ordinate.ZERO.lteq(pos_sol.r) 
            and pos_sol.r.lteq(opentime.Ordinate.ONE)
        )
        {
            return pos_sol;
        }

        // negative solution
        return try comath.eval(
            "(-b - q) / a2",
            CTX,
            .{ .q = q, .b = b, .a2 = a2 }
        );

    }

    // cubic solution
    a = a.div(d);
    b = b.div(d);
    c = c.div(d);

    const p = try comath.eval(
        "((b * 3.0) - (a * a)) / 3.0",
        CTX,
        .{
            .a = a,
            .b = b,
        },
    );

    @setEvalBranchQuota(100000);
    const q = try comath.eval(
        "((a * a * a) * 2.0 -  ((a * b) * 9.0) + (c * 27.0)) / 27.0",
        CTX,
        .{ 
            .a = a,
            .b = b,
            .c = c
        } 
    );

    const q2 = q.div(2.0);

    const p_div_3 = p.div(3.0);
    const discriminant = try comath.eval(
        "(q2 * q2) + (p_div_3 * p_div_3 * p_div_3)",
        CTX,
        .{ 
            .q2 = q2,
            .p_div_3 = p_div_3,
        },
    );

    if (discriminant.r.lt(opentime.Ordinate.ZERO)) 
    {
        const mp3 = (p.negate()).div(3.0);
        const mp33 = mp3.mul(mp3).mul(mp3);
        const r = mp33.sqrt();
        const t = try comath.eval(
            "-q / (r*2.0)",
            CTX,
            .{ .q = q, .r = r, },
        );
        const ONE_DUAL = opentime.Dual_Ord.init_ri(
            1.0,
            t.i 
        );
        const cosphi = (
            if (t.r.lt(-1) ) ONE_DUAL.negate() 
            else (
                if (t.r.gt(1)) ONE_DUAL else t
            )
        );
        const phi = cosphi.acos();
        const crtr = crt(r);
        const t1 = crtr.mul(2.0);

        const x1 = try comath.eval(
            "(t1 * cos_phi_over_three) - (a / 3.0)",
            CTX,
            .{
                .t1 = t1,
                .cos_phi_over_three = (phi.div(3.0)).cos(),
                .a = a 
            }
        );
        const x2 = try comath.eval(
            "(t1 * cos_phi_plus_tau) - (a / 3)",
            CTX,
            .{
                .t1 = t1,
                // cos((phi + std.math.tau) / 3) 
                .cos_phi_plus_tau = ((phi.add(std.math.tau)).div(3.0)).cos(),
                .a = a 
            }
        );
        const x3 = try comath.eval(
            "(t1 * cos_phi_plus_2tau) - (a / 3)",
            CTX,
                // cos((phi + 2 * std.math.tau) / 3) 
            .{
                .t1 = t1,
                .cos_phi_plus_2tau = (
                    ((phi.add(2.0 * std.math.tau)).div(3.0)).cos()
                ),
                .a = a 
            },
        );

        return first_valid_root(&.{x1, x2, x3});
    } else if (discriminant.r.eql(0)) {
        const u_1 = if (q2.r.lt(0)) crt(q2.negate()) else crt(q2).negate();
        const x1 = try comath.eval(
            "(u_1 * 2.0) - (a / 3.0)",
            CTX,
            .{ .u_1 = u_1, .a = a },
        );
        const x2 = try comath.eval(
            "(-u_1) - (a / 3)",
            CTX,
            .{ .u_1 = u_1, .a = a },
        );
        return first_valid_root(&.{x1, x2});
    } else {
        const sd = discriminant.sqrt();
        const u_1 = crt(q2.negate().add(sd));
        const v1 = crt(q2.add(sd));
        return try comath.eval(
            "u_1 - v1 - (a / 3)",
            CTX,
            .{ .u_1 = u_1, .v1 = v1, .a = a }
        );
    }

    return d;
}

pub fn findU_dual2(
    x_input: opentime.Ordinate,
    p1: opentime.Ordinate,
    p2: opentime.Ordinate,
    p3: opentime.Ordinate,
) opentime.Dual_Ord
{
    // first guess
    var u_guess: opentime.Dual_Ord = .{ .r = 0.5, .i = 1.0 };

    const MAX_ABS_ERROR = std.math.floatEps(opentime.Ordinate) * 2.0;
    const MAX_ITERATIONS = 45;

    var u_max = opentime.Dual_Ord.from(1.0);
    var u_min = opentime.Dual_Ord.from(0);

    const TWO = opentime.Dual_Ord.from(2.0);

    var iter:usize = 0;
    while (iter < MAX_ITERATIONS) 
        : (iter += 1)
    {
        const x_at_u_guess = _bezier0_dual(u_guess, p1, p2, p3);

        const delta = x_at_u_guess.r - x_input;

        if (opentime.abs(delta) < MAX_ABS_ERROR) 
        {
            return u_guess;
        }

        if (delta < 0)
        {
            u_min = u_guess;
            u_guess = try comath.eval(
                "(u_max + u_guess) / two",
                CTX,
                .{
                    .u_max = u_max,
                    .u_guess = u_guess,
                    .two = TWO,
                },
            );
        } 
        else 
        {
            u_max = u_guess;
            u_guess = try comath.eval(
                "(u_guess + u_min) / two",
                CTX,
                .{
                    .u_guess = u_guess,
                    .u_min = u_min,
                    .two = TWO,
                },
            );
        }
    }

    // best guess
    return u_guess;

    // var u_guess = opentime.Dual_Ord{ .r =  1.5, .i = 1.0 };
    // const x_input_dual = opentime.Dual_Ord{ .r = x_input, .i = 0 };
    //
    // var iter:usize = 0;
    // while (iter < MAX_ITERATIONS)
    //     : (iter += 1)
    // {
    //     const x_at_u_guess = _bezier0_dual(u_guess, p1, p2, p3);
    //
    //     if (@fabs(x_at_u_guess.r - x_input) < MAX_ABS_ERROR)
    //     {
    //         return u_guess;
    //     }
    //
    //     // u_(n+1) = u_n - f(u_n) / f'(u_n)
    //     u_guess = try comath.eval(
    //         "u_guess - ((x_at_u_guess - x_input_dual) / dx_at_uguess_du)",
    //         CTX,
    //         .{
    //             .u_guess = u_guess,
    //             .x_at_u_guess = x_at_u_guess,
    //             .x_input_dual = x_input_dual,
    //             .dx_at_uguess_du = opentime.Dual_Ord{ .r = u_guess.i, .i = 0 },
    //         },
    //     );
    // }
    //
    // std.log.err("woo\nwoo\nwoo\n", .{});
    // return u_guess;
    //
    // // def find_u_for_x(bezier_curve, target_x, tolerance=1e-6, max_iterations=100):
    // // u = 0.5  # Initial guess for u
    // // for i in range(max_iterations):
    // //     x_at_u = evaluate_bezier_x(bezier_curve, u)  # Evaluate x-coordinate
    // //     if abs(x_at_u - target_x) < tolerance:
    // //         return u  # Found a close enough u
    // //     # Adjust u based on the difference between x_at_u and target_x
    // //     u -= (x_at_u - target_x) / derivative_of_x_at_u(bezier_curve, u)
    // // return None  # Convergence failed
}

pub fn _findU_dual(
    x_input:opentime.Ordinate,
    p1:opentime.Ordinate,
    p2:opentime.Ordinate,
    p3:opentime.Ordinate,
) opentime.Dual_Ord
{
    const MAX_ABS_ERROR = std.math.floatEps(opentime.Ordinate) * 2.0;
    const MAX_ITERATIONS: u8 = 45;

    const ONE_DUAL  = opentime.Dual_Ord{ .r = 1, .i = 0};
    const ZERO_DUAL = opentime.Dual_Ord{ .r = 0, .i = 0};

    // if (x_input < 0) {
    //     return ZERO_DUAL;
    // }
    //
    // if (x_input > p3) {
    //     return ONE_DUAL;
    // }

    // differentiate from x on
    const x = opentime.Dual_Ord{ .r = x_input, .i = 1 };

    var _u1=ZERO_DUAL;
    var _u2=ZERO_DUAL;
    var x1 = x.negate(); // same as: bezier0 (0, p1, p2, p3) - x;
    var x2 = try comath.eval(
        "x1 + p3",
        CTX, .{ .x1 = x1, .p3 = opentime.Dual_Ord{ .r = p3, .i = 0 } },
    ); // same as: bezier0 (1, p1, p2, p3) - x;

    // find a good start point for the newton-raphson search, bail out early on
    // endpoints
    {
        const _u3 = try comath.eval(
            "one - (x2 / (x2 - x1))",
            CTX,
            .{
                .x1 = x1,
                .x2 = x2, 
                .one = ONE_DUAL,
            }
        );
        const x3 = _bezier0_dual(_u3, p1, p2, p3).sub(x);

        if (x3.r < 0)
        {
            // if ((ONE_DUAL.sub(_u3)).r <= MAX_ABS_ERROR) {
            //     // if (x2.r < x3.negate().r)
            //     // {
            //     //     return ONE_DUAL;
            //     // }
            //     @breakpoint();
            //     return _u3;
            // }

            _u1 = ONE_DUAL;
            x1 = x2;
        }
        else
        {
            _u1 = ZERO_DUAL;
            x1 = try comath.eval(
                "x1 * x2 / (x2 + x3)",
                CTX,
                .{ 
                    .x1 = x1,
                    .x2 = x2,
                    .x3 = x3 
                }
            );

            // if (_u3.r <= MAX_ABS_ERROR) {
            //     // if (x1.negate().r < x3.r)
            //     // {
            //     //     return ZERO_DUAL;
            //     // }
            //     @breakpoint();
            //     return _u3;
            // }
        }
        _u2 = _u3;
        x2 = x3;
    }

    // if ((x_input <= 0) or (x_input >= p3))
    // {
    //     @breakpoint();
    //     return _u2;
    // }

    var i: u8 = MAX_ITERATIONS - 1;

    while (i > 0)
        : (i -= 1)
    {
        const _u3 = try comath.eval(
            "_u2 - x2 * ((_u2 - _u1) / (x2 - x1))",
            CTX,
            .{
                .x1 = x1,
                .x2 = x2,
                ._u1 = _u1,
                ._u2 = _u2,
            },
        );
        const x3 = (_bezier0_dual(_u3, p1, p2, p3)).sub(x);

        if (x3.r == 0) {
            return _u3;
        }

        if ((x2.mul(x3)).r <= 0)
        {
            _u1 = _u2;
            x1 = x2;
        }
        else
        {
            x1 = try comath.eval(
                "x1 * x2 / (x2 + x3)",
                CTX,
                .{
                    .x1 = x1,
                    .x2 = x2,
                    .x3 = x3,
                },
            );
        }

        _u2 = _u3;
        x2 = x3;

        if (_u2.r > _u1.r)
        {
            if (_u2.sub(_u1).r <= MAX_ABS_ERROR) {
                break;
            }
        }
        else
        {
            if (_u1.sub(_u2).r <= MAX_ABS_ERROR) {
                break;
            }
        }
    }

    if (x1.r < 0) {
        x1 = x1.negate();
    }
    if (x2.r < 0) {
        x2 = x2.negate();
    }

    if (x1.r < x2.r) {
        return _u1;
    }

    return _u2;
}

// @TODO: this has some behavioral differences when set to true
const ALWAYS_USE_DUALS_FINDU = false;

/// Given x in the interval [p0, p3], and a monotonically nondecreasing
/// 1-D Bezier bezier_curve, B(u), with control points (p0, p1, p2, p3), find
/// u so that B(u) == x.
pub fn findU(
    x:opentime.Ordinate,
    p0:opentime.Ordinate,
    p1:opentime.Ordinate,
    p2:opentime.Ordinate,
    p3:opentime.Ordinate,
) opentime.Ordinate
{
    if (ALWAYS_USE_DUALS_FINDU) {
        return findU_dual(x, p0, p1, p2, p3).r;
    }
    else {
        return _findU(
            x.sub(p0),
            p1.sub(p0),
            p2.sub(p0),
            p3.sub(p0)
        );
    }
}

pub fn findU_dual(
    x:opentime.Ordinate,
    p0:opentime.Ordinate,
    p1:opentime.Ordinate, 
    p2:opentime.Ordinate,
    p3:opentime.Ordinate,
) opentime.Dual_Ord
{
    return findU_dual3(x, p0, p1, p2, p3);
}

test "bezier_math: lerp" 
{
    const fst = control_point.ControlPoint.init(.{ .in = 0, .out = 0 });
    const snd = control_point.ControlPoint.init(.{ .in = 1, .out = 1 });

    try opentime.expectOrdinateEqual(0, lerp(0, fst, snd).out);
    try opentime.expectOrdinateEqual(0.25, lerp(0.25, fst, snd).out);
    try opentime.expectOrdinateEqual(0.5, lerp(0.5, fst, snd).out);
    try opentime.expectOrdinateEqual(0.75, lerp(0.75, fst, snd).out);

    try opentime.expectOrdinateEqual(0, lerp(0, fst, snd).in);
    try opentime.expectOrdinateEqual(0.25, lerp(0.25, fst, snd).in);
    try opentime.expectOrdinateEqual(0.5, lerp(0.5, fst, snd).in);
    try opentime.expectOrdinateEqual(0.75, lerp(0.75, fst, snd).in);

    // dual lerp test
    {
        const d_u = opentime.Dual_Ord.init_ri(0.25, 1);
        const p1 = opentime.Dual_Ord.from(10);
        const p2 = opentime.Dual_Ord.from(20);

        const measured = lerp(d_u, p1, p2);

        try opentime.expectOrdinateEqual(
            12.5,           
            measured.r
        );

        try opentime.expectOrdinateEqual(
            10.0, 
            measured.i,
        );

        // a * ((-u) + 1) + (b * u)
        const algebraic = (
            ((d_u.negate().add(1)).mul(p1)).add(d_u.mul(p2))
        );

        try opentime.expectOrdinateEqual(
            algebraic.r,           
            measured.r
        );

        try opentime.expectOrdinateEqual(
            algebraic.i, 
            measured.i,
        );

        try opentime.expectOrdinateEqual(
            10.0,
            algebraic.i, 
        );
    }
}

test "bezier_math: findU" 
{
    try opentime.expectOrdinateEqual(
        opentime.Ordinate.init(0),
        findU(
            opentime.Ordinate.init(0),
            opentime.Ordinate.init(0),
            opentime.Ordinate.init(1),
            opentime.Ordinate.init(2),
            opentime.Ordinate.init(3),
        )
    );
    // oopentime.expectOrdinateEqual mped in u
    try opentime.expectOrdinateEqual(
        opentime.Ordinate.init(0),
        findU(
            opentime.Ordinate.init(-1),
            opentime.Ordinate.init(0),
            opentime.Ordinate.init(1),
            opentime.Ordinate.init(2),
            opentime.Ordinate.init(3),
        )
    );
    try opentime.expectOrdinateEqual(
        opentime.Ordinate.init(1),
        findU(
            opentime.Ordinate.init(4),
            opentime.Ordinate.init(0),
            opentime.Ordinate.init(1),
            opentime.Ordinate.init(2),
            opentime.Ordinate.init(3),
        )
    );
}

test "bezier_math: _bezier0 matches _bezier0_dual" 
{
    const test_data = [_][4]opentime.Ordinate.BaseType{
        [4]opentime.Ordinate.BaseType{ 0, 1, 2, 3 },
    };

    for (test_data)
        |t|
    {
        var x = opentime.Ordinate.init(t[0]);
        const t1 = opentime.Ordinate.init(t[1]);
        const t2 = opentime.Ordinate.init(t[2]);
        const t3 = opentime.Ordinate.init(t[3]);
        while (opentime.lt(x, t3))
            : (x = x.add(0.01))
        {
            errdefer std.log.err("Error on loop: {}\n",.{x});
            try opentime.expectOrdinateEqual(
                _bezier0(x, t1, t2, t3),
                _bezier0_dual(
                    .{ .r = x, .i = opentime.Ordinate.ONE},
                    t1,
                    t2,
                    t3
                ).r,
            );
        }
    }
}

test "bezier_math: findU_dual matches findU" 
{
    const t0 = opentime.Ordinate.init(0);
    const t1 = opentime.Ordinate.init(1);
    const t1_n = opentime.Ordinate.init(-1);
    const t2 = opentime.Ordinate.init(2);
    const t3 = opentime.Ordinate.init(3);

    const t05 = opentime.Ordinate.init(0.5);
    const t05_n = opentime.Ordinate.init(-0.5);

    try expectEqual(
        opentime.Ordinate.init(0),
        findU_dual( t0, t0,t1,t2,t3).r
    );
    try expectEqual(
        opentime.Ordinate.init(1.0/6.0),
        findU_dual(t05, t0,t1,t2,t3).r
    );

    try opentime.expectOrdinateEqual(
        opentime.Ordinate.init(1.0/3.0),
        findU_dual( t0, t0,t1,t2,t3).i
    );
    try opentime.expectOrdinateEqual(
        opentime.Ordinate.init(1.0/3.0),
        findU_dual(t05, t0,t1,t2,t3).i
    );

    try opentime.expectOrdinateEqual(
        opentime.Ordinate.init(0),
        findU_dual(  t1_n, t1_n,t0,t1,t2).r
    );
    try opentime.expectOrdinateEqual(
        opentime.Ordinate.init(1.0/6.0),
        findU_dual( t05_n, t1_n,t0,t1,t2).r
    );

    try opentime.expectOrdinateEqual(
        opentime.Ordinate.init(1.0/3.0),
        findU_dual(  t0, t1_n,t0,t1,t2).i
    );
    try opentime.expectOrdinateEqual(
        opentime.Ordinate.init(1.0/3.0),
        findU_dual(  t05_n, t1_n,t0,t1,t2).i
    );

    {
        const test_data = [_][4]opentime.Ordinate.BaseType{
           .{ 0.0, 1.0, 2.0, 3.0 }
       };

        // sweep values in range and make sure that findU and findU_dual match
        for (test_data)
            |t|
        {
            var x = t[0];
            while (x < t[3])
                : (x += 0.01)
            {
                errdefer std.log.err("Error on loop: {}\n",.{x});
                try opentime.expectOrdinateEqual(
                    findU(
                         opentime.Ordinate.init(x),
                        opentime.Ordinate.init(t[0]),
                        opentime.Ordinate.init(t[1]),
                        opentime.Ordinate.init(t[2]),
                        opentime.Ordinate.init(t[3]),
                    ),
                    findU_dual(
                        opentime.Ordinate.init(x),
                        opentime.Ordinate.init(t[0]),
                        opentime.Ordinate.init(t[1]),
                        opentime.Ordinate.init(t[2]),
                        opentime.Ordinate.init(t[3])
                    ).r,
                );
            }
        }
    }

    // out of range values are clamped in u
    try opentime.expectOrdinateEqual(
        0,
        findU_dual(
            opentime.Ordinate.init(-1),
            opentime.Ordinate.init(0),
            opentime.Ordinate.init(1),
            opentime.Ordinate.init(2),
            opentime.Ordinate.init(3),
        ).r,
    );
    try opentime.expectOrdinateEqual(
        1,
        findU_dual(
             opentime.Ordinate.init(4),
            opentime.Ordinate.init(0),
            opentime.Ordinate.init(1),
            opentime.Ordinate.init(2),
            opentime.Ordinate.init(3),
        ).r,
    );
}

test "bezier_math: dydx matches expected at endpoints" 
{
    var seg0 : bezier_curve.Bezier.Segment = .{
        .p0 = control_point.ControlPoint.init(.{.in = 0, .out=0}),
        .p1 = control_point.ControlPoint.init(.{.in = 0, .out=1}),
        .p2 = control_point.ControlPoint.init(.{.in = 1, .out=1}),
        .p3 = control_point.ControlPoint.init(.{.in = 1, .out=0}),
    };

    const test_data = struct {
        r : opentime.Ordinate.BaseType,
        e_dydu: opentime.Ordinate.BaseType,
    };
    const tests = [_]test_data{
        .{ .r = 0.0,  .e_dydu = 0.0, },
        .{ .r = 0.25, .e_dydu = 1.125 ,},
        .{ .r = 0.5,  .e_dydu = 1.5 ,},
        .{ .r = 0.75, .e_dydu = 1.125 ,},
        .{ .r = 1.0,  .e_dydu = 0, }
    };
   
    for (tests, 0..)
        |t, test_ind|
    {
        errdefer {
            std.debug.print(
                "Error on iteration: {d}\n  r: {d} e_dydu: {d}\n",
               .{ test_ind, t.r, t.e_dydu },
            );
        }
        const u_zero_dual = seg0.eval_at_dual(
            .{ .r = opentime.Ordinate.init(t.r), .i = opentime.Ordinate.ONE }
        );
        try opentime.expectOrdinateEqual(
            opentime.Ordinate.init(t.e_dydu),
            u_zero_dual.i.in
        );

    }

    const x_zero_dual = seg0.output_at_input_dual(seg0.p0.in);
    try opentime.expectOrdinateEqual(
        seg0.p1.in.sub(seg0.p0.in),
        x_zero_dual.i.in
    );
}

test "bezier_math: findU for upside down u" 
{
    const crv = try bezier_curve.read_curve_json(
        "curves/upside_down_u.curve.json",
        std.testing.allocator
    );
    defer std.testing.allocator.free(crv.segments);

    const seg_0 = crv.segments[0];

    const u_zero_dual =  seg_0.findU_input_dual(seg_0.p0.in);
    try opentime.expectOrdinateEqual(0, u_zero_dual.r);

    const half_x = lerp(0.5, seg_0.p0.in, seg_0.p3.in);
    const u_half_dual = seg_0.findU_input_dual(half_x);

    // u_half_dual = (u, du/dx)
    try opentime.expectOrdinateEqual(0.5, u_half_dual.r);
    try opentime.expectOrdinateEqual(0.666666667, u_half_dual.i);

    const u_one_dual =   seg_0.findU_input_dual(seg_0.p3.in);
    try opentime.expectOrdinateEqual(1, u_one_dual.r);
}

test "bezier_math: derivative at 0 for linear bezier_curve" 
{
    const allocator = std.testing.allocator;

    const crv = try bezier_curve.Bezier.init_from_start_end(
        allocator,
        control_point.ControlPoint.init(
            .{ .in = -0.5, .out = -0.5, }
        ),
        control_point.ControlPoint.init(
            .{ .in = 0.5, .out = 0.5, }
        ),
    );
    defer allocator.free(crv.segments);

    try expectEqual(1, crv.segments.len);

    const seg_0 = crv.segments[0];

    // test that eval_at_dual gets the same result
    {
        const u_zero_dual = seg_0.eval_at_dual(
            opentime.Dual_Ord.init_ri( 0, 1)
        );
        const u_half_dual = seg_0.eval_at_dual(
            opentime.Dual_Ord.init_ri(0.5,  1)
        );

        try opentime.expectOrdinateEqual(
            u_zero_dual.i.in,
            u_half_dual.i.in
        );
        try opentime.expectOrdinateEqual(
            u_zero_dual.i.out,
            u_half_dual.i.out
        );
    }

    // findU dual comparison
    {
        const u_zero_dual =  seg_0.findU_input_dual(seg_0.p0.in);
        const u_third_dual = seg_0.findU_input_dual(seg_0.p1.in);
        const u_one_dual =   seg_0.findU_input_dual(seg_0.p3.in);

        // known 0 values
        try opentime.expectOrdinateEqual(0, u_zero_dual.r);
        try opentime.expectOrdinateEqual(1, u_one_dual.r);

        // derivative should be the same 
        try opentime.expectOrdinateEqual(1, u_zero_dual.i);
        try opentime.expectOrdinateEqual(1, u_third_dual.i);
        try opentime.expectOrdinateEqual(1, u_one_dual.i);
    }

    {
        const x_zero_dual =  seg_0.output_at_input_dual(crv.segments[0].p0.in);
        const x_third_dual = seg_0.output_at_input_dual(crv.segments[0].p1.in);

        try opentime.expectOrdinateEqual(x_zero_dual.i.in, x_third_dual.i.in);
        try opentime.expectOrdinateEqual(x_zero_dual.i.out, x_third_dual.i.out);
    }
}

/// return crv normalized into the space provided
pub fn normalized_to(
    allocator: std.mem.Allocator,
    crv:bezier_curve.Bezier,
    min_point:control_point.ControlPoint,
    max_point:control_point.ControlPoint,
) !bezier_curve.Bezier 
{
    // return input, bezier_curve is empty
    if (crv.segments.len == 0) {
        return crv;
    }

    const src_extents = crv.extents();

    const result = try crv.clone(allocator);
    for (result.segments) 
        |*seg| 
    {
        for (seg.point_ptrs()) 
            |pt| 
        {
            pt.* = _remap(
                pt.*,
                src_extents[0], src_extents[1],
                min_point, max_point
            );
        }
    }

    return result;
}

test "bezier_math: normalized_to" 
{
    var slope2 = [_]bezier_curve.Bezier.Segment{
        .{
            .p0 = control_point.ControlPoint.init(.{.in = -500, .out=600}),
            .p1 = control_point.ControlPoint.init(.{.in = -300, .out=-100}),
            .p2 = control_point.ControlPoint.init(.{.in = 200, .out=300}),
            .p3 = control_point.ControlPoint.init(.{.in = 500, .out=700}),
        }
    };
    const input_crv:bezier_curve.Bezier = .{ .segments = &slope2 };

    const min_point= control_point.ControlPoint.init(.{.in=-100, .out=-300});
    const max_point= control_point.ControlPoint.init(.{.in=100, .out=-200});

    const result_crv = try normalized_to(
        std.testing.allocator,
        input_crv,
        min_point,
        max_point
    );
    defer result_crv.deinit(std.testing.allocator);
    const result_extents = result_crv.extents();

    try expectEqual(min_point.in, result_extents[0].in);
    try expectEqual(min_point.out, result_extents[0].out);

    try expectEqual(max_point.in, result_extents[1].in);
    try expectEqual(max_point.out, result_extents[1].out);
}

test "bezier_math: normalize_to_screen_coords" 
{
    var segments = [_]bezier_curve.Bezier.Segment{
        .{
            .p0 = control_point.ControlPoint.init(.{.in = -500, .out=600}),
            .p1 = control_point.ControlPoint.init(.{.in = -300, .out=-100}),
            .p2 = control_point.ControlPoint.init(.{.in = 200, .out=300}),
            .p3 = control_point.ControlPoint.init(.{.in = 500, .out=700}),
        },
    };
    const input_crv:bezier_curve.Bezier = .{
        .segments = &segments
    };

    const min_point = control_point.ControlPoint.init(.{.in=700, .out=100});
    const max_point = control_point.ControlPoint.init(.{.in=2500, .out=1900});

    const result_crv = try normalized_to(
        std.testing.allocator,
        input_crv,
        min_point,
        max_point
    );
    defer result_crv.deinit(std.testing.allocator);
    const result_extents = result_crv.extents();

    try expectEqual(min_point.in, result_extents[0].in);
    try expectEqual(min_point.out, result_extents[0].out);

    try expectEqual(max_point.in, result_extents[1].in);
    try expectEqual(max_point.out, result_extents[1].out);
}

/// compute the slope of the line segment from start to end
pub fn slope(
    start: control_point.ControlPoint,
    end: control_point.ControlPoint,
) opentime.Ordinate 
{
    return comath.eval(
        "((end_out - start_out) / (end_in - start_in))",
        CTX,
        .{
            .end_in = end.in,
            .end_out = end.out,
            .start_in = start.in,
            .start_out = start.out,
        },
    ) catch {};
}

test "bezier_math: slope"
{
    const start = control_point.ControlPoint.init(
        .{ .in = 0, .out = 0, }
    );
    const end = control_point.ControlPoint.init(
        .{ .in = 2, .out = 4, }
    );

    try opentime.expectOrdinateEqual(
        2,
        slope(start, end)
    );
}

pub fn inverted_linear(
    allocator: std.mem.Allocator,
    crv: linear_curve.Linear.Monotonic,
) !linear_curve.Linear.Monotonic 
{
    // require two points to define a line
    if (crv.knots.len < 2) {
        return crv;
    }

    var result = (
        std.ArrayList(control_point.ControlPoint).init(allocator)
    );
    try result.appendSlice(crv.knots);

    for (crv.knots, result.items) 
        |src_knot, *dst_knot| 
    {
        dst_knot.* = .{
            .in = src_knot.out,
            .out = src_knot.in, 
        };
    }

    const slope_kind = SlopeKind.compute(
        crv.knots[0],
        crv.knots[1]
    );
    if (slope_kind == .falling) {
        std.mem.reverse(
            control_point.ControlPoint,
            result.items
        );
    }

    return .{ .knots = try result.toOwnedSlice() };
}

// pub fn inverted_bezier(
//     allocator: std.mem.Allocator,
//     crv: bezier_curve.Bezier,
// ) !linear_curve.Linear.Monotonic 
// {
//     const lin_crv = try crv.linearized(allocator);
//     defer lin_crv.deinit(allocator);
//
//     return try inverted_linear(allocator, lin_crv);
// }
//
// test "inverted: invert linear" 
// {
//     // slope 2
//     const forward_crv = try bezier_curve.Bezier.init_from_start_end(
//         std.testing.allocator,
//             .{.in = -1, .out = -3},
//             .{.in = 1, .out = 1}
//     );
//     defer forward_crv.deinit(std.testing.allocator);
//
//     const inverse_crv = try inverted_bezier(
//         std.testing.allocator,
//         forward_crv
//     );
//     defer inverse_crv.deinit(std.testing.allocator);
//
//     // ensure that temporal ordering is correct
//     { 
//         errdefer std.log.err(
//             "knot0.in ({any}) < knot1.in ({any})",
//             .{inverse_crv.knots[0].in, inverse_crv.knots[1].in}
//         );
//         try expect(inverse_crv.knots[0].in < inverse_crv.knots[1].in);
//     }
//
//     var identity_seg = [_]bezier_curve.Bezier.Segment{
//         // slope of 2
//         bezier_curve.Bezier.Segment.init_identity(-3, 1)
//     };
//     const identity_crv:bezier_curve.Bezier = .{ .segments = &identity_seg };
//
//     var t :f32 = -1;
//     //           no split at t=1 (end point)
//     while (t<1 - 0.01) 
//         : (t += 0.01) 
//     {
//         const idntity_p = try identity_crv.output_at_input(t);
//
//         // identity_p(t) == inverse_p(forward_p(t))
//         const forward_p = try forward_crv.output_at_input(t);
//         const inverse_p = try inverse_crv.output_at_input(forward_p);
//
//         errdefer std.log.err(
//             "[t: {any}] ident: {any} forwd: {any} inv: {any}",
//             .{t, idntity_p, forward_p, inverse_p}
//         );
//
//         // A * A-1 => 1
//         try expectApproxEql(idntity_p, inverse_p);
//     }
// }

// test "invert negative slope linear" 
// {
//     // slope 2
//     const forward_crv = try bezier_curve.Bezier.init_from_start_end(
//         std.testing.allocator,
//             .{.in = -1, .out = 1},
//             .{.in = 1, .out = -3}
//     );
//     defer forward_crv.deinit(std.testing.allocator);
//
//     const forward_crv_lin = try forward_crv.linearized(
//         std.testing.allocator
//     );
//     defer forward_crv_lin.deinit(std.testing.allocator);
//
//     const inverse_crv_lin = try inverted_linear(
//         std.testing.allocator,
//         forward_crv_lin
//     );
//     defer inverse_crv_lin.deinit(std.testing.allocator);
//
//     // std.debug.print("\n\n  forward: {any}\n", .{ forward_crv_lin.extents() });
//     // std.debug.print("\n\n  inverse: {any}\n", .{ inverse_crv_lin.extents() });
//
//     // ensure that temporal ordering is correct
//     { 
//         errdefer std.log.err(
//             "knot0.in ({any}) < knot1.in ({any})",
//             .{inverse_crv_lin.knots[0].in, inverse_crv_lin.knots[1].in}
//         );
//         try expect(inverse_crv_lin.knots[0].in < inverse_crv_lin.knots[1].in);
//     }
//
//     const double_inv_lin = try inverted_linear(
//         std.testing.allocator,
//         inverse_crv_lin
//     );
//     defer double_inv_lin.deinit(std.testing.allocator);
//
//     var t: f32 = -1;
//     // end point is exclusive
//     while (t<1 - 0.01) 
//         : (t += 0.01) 
//     {
//         errdefer std.log.err(
//             "\n  [t: {any}] \n",
//             .{t, }
//         );
//
//         const forward_p = try forward_crv.output_at_input(t);
//         const double__p = try double_inv_lin.output_at_input(t);
//
//         errdefer std.log.err(
//             "[t: {any}] forwd: {any} double_inv: {any}",
//             .{t, forward_p, double__p}
//         );
//
//         try expectApproxEql(forward_p, double__p);
//
//         // A * A-1 => 1
//         // const inverse_p = try inverse_crv_lin.output_at_input(forward_p);
//         // try expectApproxEql(t, inverse_p);
//     }
// }

// test "BezierMath: invert linear complicated bezier_curve" 
// {
//     var segments = [_]bezier_curve.Bezier.Segment{
//         // identity
//         bezier_curve.Bezier.Segment.init_identity(0, 1),
//         // go up
//         bezier_curve.Bezier.Segment.init_from_start_end(
//             .{ .in = 1, .out = 1 },
//             .{ .in = 2, .out = 3 },
//         ),
//         // go down
//         bezier_curve.Bezier.Segment.init_from_start_end(
//             .{ .in = 2, .out = 3 },
//             .{ .in = 3, .out = 1 },
//         ),
//         // identity
//         bezier_curve.Bezier.Segment.init_from_start_end(
//             .{ .in = 3, .out = 1 },
//             .{ .in = 4, .out = 2 },
//         ),
//     };
//     const crv : bezier_curve.Bezier = .{
//         .segments = &segments
//     };
//     const crv_linear = try crv.linearized(
//         std.testing.allocator
//     );
//     defer crv_linear.deinit(std.testing.allocator);
//
//     try bezier_curve.write_json_file_curve(
//         std.testing.allocator,
//         crv_linear,
//         "/var/tmp/forward.linear.json"
//     );
//
//     const crv_linear_inv = try inverted_linear(
//         std.testing.allocator,
//         crv_linear
//     );
//     defer crv_linear_inv.deinit(std.testing.allocator);
//     try bezier_curve.write_json_file_curve(
//         std.testing.allocator,
//         crv_linear_inv,
//         "/var/tmp/inverse.linear.json"
//     );
//
//     const crv_double_inv = try inverted_linear(
//         std.testing.allocator,
//         crv_linear_inv,
//     );
//     defer crv_double_inv.deinit(std.testing.allocator);
//
//     var t:f32 = 0;
//     while (t < 3-0.01)
//         : (t+=0.01)
//     {
//         errdefer std.log.err(
//             "\n  t: {d} err! \n",
//             .{ t, }
//         );
//         const fwd = try crv_linear.output_at_input(t);
//         const dbl = try crv_double_inv.output_at_input(t);
//
//         try expectEqual(fwd, dbl);
//
//         // const inv = try crv_linear_inv.output_at_input(fwd);
//         //
//         // errdefer std.log.err(
//         //     "\n  t: {d} not equals projected {d}\n",
//         //     .{ t, inv }
//         // );
//         // try expectEqual(t, inv);
//     }
// }

fn _remap(
    t: anytype,
    measure_min: @TypeOf(t), measure_max: @TypeOf(t),
    target_min: @TypeOf(t), target_max: @TypeOf(t),
) @TypeOf(t)
{
    return comath.eval(
        "(((t-measure_min)/(measure_max-measure_min))"
        ++ " * (target_max - target_min)"
        ++ ") + target_min"
        ,
        CTX,
        .{
            .t = t,
            .measure_min = measure_min,
            .measure_max = measure_max,
            .target_min = target_min,
            .target_max = target_max,
        }
    ) catch |err| switch(err) {};
}

fn _rescaled_pt(
    pt:control_point.ControlPoint,
    extents: [2]control_point.ControlPoint,
    target_range: [2]control_point.ControlPoint,
) control_point.ControlPoint
{
    return _remap(
        pt,
        extents[0], extents[1],
        target_range[0], target_range[1],
    );
}

/// return a new bezier_curve rescaled over the specified target_range
pub fn rescaled_curve(
    allocator: std.mem.Allocator,
    crv: bezier_curve.Bezier,
    target_range: [2]control_point.ControlPoint,
) !bezier_curve.Bezier
{
    const original_extents = crv.extents();

    const result = try crv.clone(allocator);

    for (result.segments) 
        |*seg| 
    {
        for (seg.point_ptrs()) 
            |pt| 
        {

            pt.* = _rescaled_pt(
                pt.*,
                original_extents,
                target_range
            );
        }
    }

    return result;
}

test "bezier_math: BezierMath: rescaled parameter" 
{
    const crv = try bezier_curve.read_curve_json(
        "curves/scurve.curve.json",
        std.testing.allocator
    );
    defer std.testing.allocator.free(crv.segments);

    const start_extents = crv.extents();

    try opentime.expectOrdinateEqual(opentime.Ordinate.init( -0.5), start_extents[0].in);
    try opentime.expectOrdinateEqual(opentime.Ordinate.init(  0.5), start_extents[1].in);

    try opentime.expectOrdinateEqual(opentime.Ordinate.init( -0.5), start_extents[0].out);
    try opentime.expectOrdinateEqual(opentime.Ordinate.init(  0.5), start_extents[1].out);

    const result = try rescaled_curve(
        std.testing.allocator,
        crv,
        .{
            control_point.ControlPoint.init(.{ .in = 100, .out = 0 }),
            control_point.ControlPoint.init(.{ .in = 200, .out = 10 }),
        }
    );
    defer result.deinit(std.testing.allocator);

    const end_extents = result.extents();

    try opentime.expectOrdinateEqual(100, end_extents[0].in);
    try opentime.expectOrdinateEqual(200, end_extents[1].in);

    try opentime.expectOrdinateEqual(0,  end_extents[0].out);
    try opentime.expectOrdinateEqual(10, end_extents[1].out);
}

// test "inverted: invert bezier" 
// {
//     var identity_seg = [_]bezier_curve.Bezier.Segment{
//         bezier_curve.Bezier.Segment.init_identity(-3, 1),
//     };
//     const identity_crv:bezier_curve.Bezier = .{ 
//         .segments = &identity_seg 
//     };
//
//     const a2b_crv = try bezier_curve.read_curve_json(
//         "curves/scurve.curve.json",
//         std.testing.allocator,
//     );
//     defer a2b_crv.deinit(std.testing.allocator);
//     const b2a_lin = try inverted_bezier(
//         std.testing.allocator,
//         a2b_crv,
//     );
//     defer b2a_lin.deinit(std.testing.allocator);
//
//     var t_a :f32 = -0.5;
//     while (t_a<0.5 - generic_curve.EPSILON) 
//         : (t_a += 0.01) 
//     {
//         errdefer std.log.err(
//             "[t_a: {any}]",
//             .{t_a}
//         );
//         const t_a_computed = try identity_crv.output_at_input(t_a);
//         try expectApproxEql(t_a, t_a_computed);
//
//         errdefer std.log.err(
//             " ident: {any}",
//             .{t_a_computed}
//         );
//
//         const p_b = try a2b_crv.output_at_input(t_a);
//         errdefer std.log.err(
//             " forwd: {any}",
//             .{p_b}
//         );
//
//         const p_a = try b2a_lin.output_at_input(p_b);
//         errdefer std.log.err(
//             " inv: {any}\n",
//             .{p_a}
//         );
//
//         // A * A-1 => 1
//         try std.testing.expectApproxEqAbs(
//             t_a_computed,
//             p_a,
//             generic_curve.EPSILON * 100,
//         );
//     }
// }

/// encodes and computes the slope of a segment between two ControlPoints
pub const SlopeKind = enum {
    flat,
    rising,
    falling,

    /// compute the slope kind between the two control points
    pub fn compute(
        start: control_point.ControlPoint,
        end: control_point.ControlPoint,
    ) SlopeKind
    {
        if (
            opentime.eql(start.in, end.in) 
            or opentime.eql(start.out, end.out)
        )
        {
            return .flat;
        }

        const s = slope(start, end);

        if (opentime.gt(s, opentime.Ordinate.ZERO))
        {
            return .rising;
        }
        else 
        {
            return .falling;
        }
    }
};

test "bezier_math: SlopeKind"
{
    const TestCase = struct {
        name: []const u8,
        points: [2]control_point.ControlPoint,
        expected: SlopeKind,
    };
    const tests: []const TestCase = &.{
        .{
            .name = "flat",  
            .points = .{
                control_point.ControlPoint.init(.{ .in = 0, .out = 5 }),
                control_point.ControlPoint.init(.{ .in = 10, .out = 5 }),
            },
            .expected = .flat,
        },
        .{
            .name = "rising",  
            .points = .{
                control_point.ControlPoint.init(.{ .in = 0, .out = 0 }),
                control_point.ControlPoint.init(.{ .in = 10, .out = 15 }),
            },
            .expected = .rising,
        },
        .{
            .name = "falling",  
            .points = .{
                control_point.ControlPoint.init(.{ .in = 0, .out = 10 }),
                control_point.ControlPoint.init(.{ .in = 10, .out = 0 }),
            },
            .expected = .falling,
        },
        .{
            .name = "column",  
            .points = .{
                control_point.ControlPoint.init(.{ .in = 0, .out = 10 }),
                control_point.ControlPoint.init(.{ .in = 0, .out = 0 }),
            },
            .expected = .flat,
        },
    };

    for (tests)
        |t|
    {
        const measured = SlopeKind.compute(
            t.points[0],
            t.points[1]
        );
        try std.testing.expectEqual(
            t.expected,
            measured,
        );
    }
}
