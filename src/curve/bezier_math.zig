const std = @import("std");

const control_point = @import("control_point.zig");
const ControlPoint = control_point.ControlPoint;
const curve = @import("bezier_curve.zig");
const linear_curve = @import("linear_curve.zig");
const generic_curve = @import("generic_curve.zig");
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const comath = @import("comath");
const dual = @import("opentime").dual;


fn expectApproxEql(expected: anytype, actual: @TypeOf(expected)) !void {
    return std.testing.expectApproxEqAbs(
        expected,
        actual,
        generic_curve.EPSILON*100
    );
}

const allocator = @import("otio_allocator");
const ALLOCATOR = allocator.ALLOCATOR;

const CTX = comath.ctx.fnMethod(
    comath.ctx.simple(dual.dual_ctx{}),
    .{
        .@"+" = "add",
        .@"-" = &.{"sub", "negate"},
        .@"*" = "mul",
        .@"/" = "div",
        .@"cos" = "cos",
    }
);

pub fn lerp(u: anytype, a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return comath.eval(
        "a * (-u + 1.0) + b * u",
        CTX,
        .{
            .a = a,
            .b = b,
            .u = u,
        }
    ) catch |err| switch (err) {};
}

// pub fn lerp_vector(u: anytype, a: anytype, b: @TypeOf(a)) @TypeOf(a) {
//     const u_vec: @Vector(2, @TypeOf(u)) = @splat(u);
//     const one_vec:@Vector(2, @TypeOf(u)) = @splat(@as(@TypeOf(u), 1));
//     return ((one_vec - u_vec) * a + b * u_vec);
// }
//
pub fn invlerp(v: f32, a: f32, b: f32) f32 {
    if (b == a)
        return a;
    return (v - a)/(b - a);
}

pub fn value_at_time_between(
    t: f32,
    fst: ControlPoint,
    snd: ControlPoint,
) f32 
{
    const u = invlerp(t, fst.time, snd.time);
    return lerp(u, fst.value, snd.value);
}

// dual variety
pub fn segment_reduce4_dual(
    u: dual.Dual_f32, 
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
    u: dual.Dual_f32,
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
    u: dual.Dual_f32,
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

pub fn segment_reduce4(u: f32, segment: curve.Segment) curve.Segment {
    return .{
        .p0 = lerp(u, segment.p0, segment.p1),
        .p1 = lerp(u, segment.p1, segment.p2),
        .p2 = lerp(u, segment.p2, segment.p3),
    };
}

pub fn segment_reduce3(u: f32, segment: curve.Segment) curve.Segment {
    return .{
        .p0 = lerp(u, segment.p0, segment.p1),
        .p1 = lerp(u, segment.p1, segment.p2),
    };
}

pub fn segment_reduce2(u: f32, segment: curve.Segment) curve.Segment {
    return .{
        .p0 = lerp(u, segment.p0, segment.p1),
    };
}

// evaluate a 1d bezier whose first point is 0.
pub fn _bezier0(
    unorm: f32,
    p2: f32,
    p3: f32,
    p4: f32
) f32
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
            .zmo = unorm - 1,
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
    unorm: dual.Dual_f32,
    p2: f32,
    p3: f32,
    p4: f32
) dual.Dual_f32
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
            .zmo = unorm.sub(.{.r = 1.0, .i = 0.0}),
            .p2 = dual.Dual_f32{ .r = p2, .i = 0.0 },
            .p3 = dual.Dual_f32{ .r = p3, .i = 0.0 },
            .p4 = dual.Dual_f32{ .r = p4, .i = 0.0 },
        }
    );
}

//
// Given x in the interval [0, p3], and a monotonically nondecreasing
// 1-D Bezier curve, B(u), with control points (0, p1, p2, p3), find
// u so that B(u) == x.
//

pub fn _findU(x:f32, p1:f32, p2:f32, p3:f32) f32
{
    const MAX_ABS_ERROR = std.math.floatEps(f32) * 2.0;
    const MAX_ITERATIONS: u8 = 45;

    if (x <= 0) {
        return 0;
    }

    if (x >= p3) {
        return 1;
    }

    var _u1:f32 = 0;
    var _u2:f32 = 0;
    var x1 = -x; // same as: bezier0 (0, p1, p2, p3) - x;
    var x2 = p3 - x; // same as: bezier0 (1, p1, p2, p3) - x;

    {
        const _u3 = 1.0 - x2 / (x2 - x1);
        const x3 = _bezier0(_u3, p1, p2, p3) - x;

        if (x3 == 0)
            return _u3;

        if (x3 < 0)
        {
            if (1.0 - _u3 <= MAX_ABS_ERROR) {
                if (x2 < -x3)
                    return 1.0;
                return _u3;
            }

            _u1 = 1.0;
            x1 = x2;
        }
        else
        {
            _u1 = 0.0;
            x1 = x1 * x2 / (x2 + x3);

            if (_u3 <= MAX_ABS_ERROR) {
                if (-x1 < x3)
                    return 0.0;
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
        const _u3:f32 = _u2 - x2 * ((_u2 - _u1) / (x2 - x1));
        const x3 = _bezier0 (_u3, p1, p2, p3) - x;

        if (x3 == 0)
            return _u3;

        if (x2 * x3 <= 0)
        {
            _u1 = _u2;
            x1 = x2;
        }
        else
        {
            x1 = x1 * x2 / (x2 + x3);
        }

        _u2 = _u3;
        x2 = x3;

        if (_u2 > _u1)
        {
            if (_u2 - _u1 <= MAX_ABS_ERROR)
                break;
        }
        else
        {
            if (_u1 - _u2 <= MAX_ABS_ERROR)
                break;
        }
    }

    if (x1 < 0)
        x1 = -x1;
    if (x2 < 0)
        x2 = -x2;

    if (x1 < x2)
        return _u1;
    return _u2;
}

fn first_valid_root(possible_roots: [] const dual.Dual_f32 ) dual.Dual_f32
{
    for (possible_roots)
        |root|
    {
        if (0 <= root.r and root.r <= 1)
        {
            return root;
        }
    }


    return possible_roots[0];
}

// cube root function yielding real roots
inline fn crt(
    v:dual.Dual_f32
) dual.Dual_f32
{
    if (v.r < 0) {
        return ((v.negate()).pow(1.0/3.0)).negate();
    } 
    else {
        return (v.pow(1.0/3.0));
    }
}

pub fn findU_dual3(
    x_input: f32,
    p0: f32,
    p1: f32,
    p2: f32,
    p3: f32,
) dual.Dual_f32
{
    // assumes that p3 > p0
    const x = @min(@max(x_input, p0), p3);

    const p0_d = dual.Dual_f32{.r = p0 - x, .i = -1 };
    const p1_d = dual.Dual_f32{.r = p1 - x, .i = -1 };
    const p2_d = dual.Dual_f32{.r = p2 - x, .i = -1 };
    const p3_d = dual.Dual_f32{.r = p3 - x, .i = -1 };

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
    ) catch .{ .r = -12, .i=3.14};

    var a = comath.eval(
        // "(pa * 3.0) - (pb * 6.0) + (pc * 3.0)",
        "pa * 3.0 - pb * 6.0 + pc * 3.0",
        CTX,
        .{ 
            .pa = p0_d,
            .pb = p1_d,
            .pc = p2_d,
        },
    ) catch .{ .r = -12, .i=3.14};

    var b = comath.eval(
        "(-pa * 3.0) + (pb * 3.0)",
        CTX,
        .{ 
            .pa = p0_d,
            .pb = p1_d,
        },
    ) catch .{ .r = -12, .i=3.14};

    var c = p0_d;

    if (@fabs(d.r) < generic_curve.EPSILON) 
    {
        // not cubic
        if (@fabs(a.r) < generic_curve.EPSILON) 
        {
            // linear
            if (@fabs(b.r) < generic_curve.EPSILON)
            {
                // no solutions
                // todo optiona/error
                return .{
                    .r = std.math.nan(f32),
                    .i = std.math.nan(f32),
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

        if (0 <= pos_sol.r and pos_sol.r <= 1)
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

    if (discriminant.r < 0) {
        const mp3 = (p.negate()).div(3.0);
        const mp33 = mp3.mul(mp3).mul(mp3);
        const r = mp33.sqrt();
        const t = try comath.eval(
            "-q / (r*2.0)",
            CTX,
            .{ .q = q, .r = r, },
        );
        const ONE_DUAL = dual.Dual_f32{ .r = 1.0, .i = t.i };
        const cosphi = if (t.r < -1) 
            ONE_DUAL.negate() 
            else (
                if (t.r > 1) ONE_DUAL else t
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
    } else if (discriminant.r == 0) {
        const u_1 = if (q2.r < 0) crt(q2.negate()) else crt(q2).negate();
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
    x_input: f32,
    p1: f32,
    p2: f32,
    p3: f32,
) dual.Dual_f32
{
    // first guess
    var u_guess: dual.Dual_f32 = .{ .r = 0.5, .i = 1.0 };

    const MAX_ABS_ERROR = std.math.floatEps(f32) * 2.0;
    const MAX_ITERATIONS = 45;

    var u_max = dual.Dual_f32{.r = 1.0, .i = 0.0 };
    var u_min = dual.Dual_f32{.r = 0.0, .i = 0.0 };

    const TWO = dual.Dual_f32{ .r = 2.0, .i = 0.0 };

    var iter:usize = 0;
    while (iter < MAX_ITERATIONS) 
        : (iter += 1)
    {
        var x_at_u_guess = _bezier0_dual(u_guess, p1, p2, p3);

        const delta = x_at_u_guess.r - x_input;

        if (@fabs(delta) < MAX_ABS_ERROR) 
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

    // var u_guess = dual.Dual_f32{ .r =  1.5, .i = 1.0 };
    // const x_input_dual = dual.Dual_f32{ .r = x_input, .i = 0 };
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
    //             .dx_at_uguess_du = dual.Dual_f32{ .r = u_guess.i, .i = 0 },
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
    x_input:f32,
    p1:f32,
    p2:f32,
    p3:f32
) dual.Dual_f32
{
    const MAX_ABS_ERROR = std.math.floatEps(f32) * 2.0;
    const MAX_ITERATIONS: u8 = 45;

    const ONE_DUAL  = dual.Dual_f32{ .r = 1, .i = 0};
    const ZERO_DUAL = dual.Dual_f32{ .r = 0, .i = 0};

    // if (x_input < 0) {
    //     return ZERO_DUAL;
    // }
    //
    // if (x_input > p3) {
    //     return ONE_DUAL;
    // }

    // differentiate from x on
    const x = dual.Dual_f32{ .r = x_input, .i = 1 };

    var _u1=ZERO_DUAL;
    var _u2=ZERO_DUAL;
    var x1 = x.negate(); // same as: bezier0 (0, p1, p2, p3) - x;
    var x2 = try comath.eval(
        "x1 + p3",
        CTX, .{ .x1 = x1, .p3 = dual.Dual_f32{ .r = p3, .i = 0 } },
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

//
// Given x in the interval [p0, p3], and a monotonically nondecreasing
// 1-D Bezier curve, B(u), with control points (p0, p1, p2, p3), find
// u so that B(u) == x.
//
pub fn findU(x:f32, p0:f32, p1:f32, p2:f32, p3:f32) f32
{
    return _findU(x - p0, p1 - p0, p2 - p0, p3 - p0);
}

pub fn findU_dual(x:f32, p0:f32, p1:f32, p2:f32, p3:f32) dual.Dual_f32
{
    // return findU_dual2(x - p0, p1 - p0, p2 - p0, p3 - p0);
    // return _findU_dual(x - p0, p1 - p0, p2 - p0, p3 - p0);
    return findU_dual3(x, p0, p1, p2, p3);
}


test "lerp" {
    const fst: ControlPoint = .{ .time = 0, .value = 0 };
    const snd: ControlPoint = .{ .time = 1, .value = 1 };

    try expectEqual(@as(f32, 0), lerp(0, fst, snd).value);
    try expectEqual(@as(f32, 0.25), lerp(0.25, fst, snd).value);
    try expectEqual(@as(f32, 0.5), lerp(0.5, fst, snd).value);
    try expectEqual(@as(f32, 0.75), lerp(0.75, fst, snd).value);

    try expectEqual(@as(f32, 0), lerp(0, fst, snd).time);
    try expectEqual(@as(f32, 0.25), lerp(0.25, fst, snd).time);
    try expectEqual(@as(f32, 0.5), lerp(0.5, fst, snd).time);
    try expectEqual(@as(f32, 0.75), lerp(0.75, fst, snd).time);
}

test "findU" {
    try expectEqual(@as(f32, 0), findU(0, 0,1,2,3));
    // out of range values are clamped in u
    try expectEqual(@as(f32, 0), findU(-1, 0,1,2,3));
    try expectEqual(@as(f32, 1), findU(4, 0,1,2,3));
}

test "_bezier0 matches _bezier0_dual" {
    {
        const test_data = [_][4]f32{
            [4]f32{ 0, 1, 2, 3 },
        };

        for (test_data)
            |t|
        {
            var x : f32 = t[0];
            while (x < t[3])
                : (x += 0.01)
            {
                errdefer std.log.err("Error on loop: {}\n",.{x});
                try expectApproxEql(
                    _bezier0(x, t[1], t[2], t[3]),
                    _bezier0_dual(.{ .r = x, .i = 1}, t[1], t[2], t[3]).r,
                );
            }
        }
    }
}

test "findU_dual matches findU" {

    try expectEqual(@as(f32, 0), findU_dual(0, 0,1,2,3).r);
    try expectEqual(@as(f32, 1.0/6.0), findU_dual(0.5, 0,1,2,3).r);

    try expectApproxEql(@as(f32, 1.0/3.0), findU_dual(0, 0,1,2,3).i);
    try expectApproxEql(@as(f32, 1.0/3.0), findU_dual(0.5, 0,1,2,3).i);

    try expectEqual(@as(f32, 0), findU_dual(-1, -1,0,1,2).r);
    try expectEqual(@as(f32, 1.0/6.0), findU_dual(-0.5, -1,0,1,2).r);

    try expectApproxEql(@as(f32, 1.0/3.0), findU_dual(0, -1,0,1,2).i);
    try expectApproxEql(@as(f32, 1.0/3.0), findU_dual(-0.5, -1,0,1,2).i);

    {
        const test_data = [_][4]f32{
            [4]f32{ 0, 1, 2, 3 },
        };

        // sweep values in range and make sure that findU and findU_dual match
        for (test_data)
            |t|
        {
            var x : f32 = t[0];
            while (x < t[3])
                : (x += 0.01)
            {
                errdefer std.log.err("Error on loop: {}\n",.{x});
                try expectApproxEql(
                    findU(x, t[0], t[1], t[2], t[3]),
                    findU_dual(x, t[0], t[1], t[2], t[3]).r,
                );
            }
        }
    }

    // out of range values are clamped in u
    try expectEqual(@as(f32, 0), findU_dual(-1, 0,1,2,3).r);
    try expectEqual(@as(f32, 1), findU_dual(4, 0,1,2,3).r);
}

test "dydx matches expected at endpoints" {
    const crv = try curve.read_curve_json(
        "curves/scurve_extreme.curve.json",
        std.testing.allocator
    );
    defer std.testing.allocator.free(crv.segments);

    const seg0 = crv.segments[0];

    // {
    //     const u_zero_dual = seg0.eval_at_dual(.{ .r = 0.1, .i = 1 });
    //     try expectApproxEql(@as(f32, 1.0), u_zero_dual.i.time);
    // }

    // {
    //     const u_zero_dual = seg0.eval_at_dual(.{ .r = 0, .i = 1 });
    //     try expectApproxEql(@as(f32, 1.0), u_zero_dual.i.time);
    // }

    {
        const x_zero_dual = seg0.eval_at_x_dual(seg0.p0.time);
        try expectApproxEql(seg0.p1.time - seg0.p0.time, x_zero_dual.i.time);
    }
}

test "findU for upside down u" {
    const crv = try curve.read_curve_json(
        "curves/upside_down_u.curve.json",
        std.testing.allocator
    );
    defer std.testing.allocator.free(crv.segments);

    const seg_0 = crv.segments[0];

    {
        const u_zero_dual =  seg_0.findU_input_dual(seg_0.p0.time);
        try expectApproxEql(@as(f32, 0), u_zero_dual.r);

        const half_x = lerp(0.5, seg_0.p0.time, seg_0.p3.time);
        @breakpoint();
        const u_half_dual = seg_0.findU_input_dual(half_x);
        try expectApproxEql(@as(f32, 0.5), u_half_dual.r);
        try expectApproxEql(@as(f32, 1.0), u_half_dual.i);

        const u_one_dual =   seg_0.findU_input_dual(seg_0.p3.time);
        try expectApproxEql(@as(f32, 1), u_one_dual.r);
    }

}

test "derivative at 0 for linear curve" {
    const crv = try curve.read_curve_json(
        "curves/linear.curve.json",
        std.testing.allocator
    );
    defer std.testing.allocator.free(crv.segments);

    try expectEqual(@as(usize, 1), crv.segments.len);

    const seg_0 = crv.segments[0];

    // test that eval_at_dual gets the same result
    {
        const u_zero_dual = seg_0.eval_at_dual(.{ .r = 0, .i = 1 });
        const u_half_dual = seg_0.eval_at_dual(.{ .r = 0.5, .i = 1 });

        try expectApproxEql(u_zero_dual.i.time, u_half_dual.i.time);
        try expectApproxEql(u_zero_dual.i.value, u_half_dual.i.value);
    }

    // findU dual comparison
    {
        const u_zero_dual =  seg_0.findU_input_dual(seg_0.p0.time);
        const u_third_dual = seg_0.findU_input_dual(seg_0.p1.time);
        const u_one_dual =   seg_0.findU_input_dual(seg_0.p3.time);

        // known 0 values
        try expectApproxEql(@as(f32, 0), u_zero_dual.r);
        try expectApproxEql(@as(f32, 1), u_one_dual.r);

        // derivative should be the same everywhere, linear function
        try expectApproxEql(@as(f32, 1), u_zero_dual.i);
        try expectApproxEql(@as(f32, 1), u_third_dual.i);
        try expectApproxEql(@as(f32, 1), u_one_dual.i);
    }

    {
        const x_zero_dual =  seg_0.eval_at_x_dual(crv.segments[0].p0.time);
        const x_third_dual = seg_0.eval_at_x_dual(crv.segments[0].p1.time);

        try expectApproxEql(x_zero_dual.i.time, x_third_dual.i.time);
        try expectApproxEql(x_zero_dual.i.value, x_third_dual.i.value);
    }
}

fn remap_float(
    val:f32,
    in_min:f32, in_max:f32,
    out_min:f32, out_max:f32,
) f32 {
    return ((val-in_min)/(in_max-in_min) * (out_max-out_min) + out_min);
}

/// return crv normalized into the space provided
pub fn normalized_to(
    crv:curve.TimeCurve,
    min_point:ControlPoint,
    max_point:ControlPoint,
) curve.TimeCurve 
{

    // return input, curve is empty
    if (crv.segments.len == 0) {
        return crv;
    }

    const extents = crv.extents();
    const crv_min = extents[0];
    const crv_max = extents[1];

    // copy the curve
    var result = crv;
    result.segments = ALLOCATOR.dupe(curve.Segment, crv.segments) catch unreachable;

    for (result.segments, 0..) |seg, seg_index| {
        var new_points:[4]ControlPoint = .{};
        for (seg.points(), 0..) |pt, pt_index| {
            new_points[pt_index] = .{
                .time = remap_float(
                    pt.time,
                    crv_min.time, crv_max.time,
                    min_point.time, max_point.time
                ),
                .value = remap_float(
                    pt.value,
                    crv_min.value, crv_max.value,
                    min_point.value, max_point.value
                ),
            };
        }
        result.segments[seg_index] = curve.Segment.from_pt_array(new_points);
    }

    return result;
}

test "remap_float" {
    try expectEqual(
        remap_float(0.5, 0.25, 1.25, -4, -5),
        @as(f32, -4.25)
    );
}

test "normalized_to" {
    var slope2 = [_]curve.Segment{
        curve.create_bezier_segment(
            .{.time = -500, .value=600},
            .{.time = -300, .value=-100},
            .{.time = 200, .value=300},
            .{.time = 500, .value=700},
        )
    };
    const input_crv:curve.TimeCurve = .{ .segments = &slope2 };

    const min_point = ControlPoint{.time=-100, .value=-300};
    const max_point = ControlPoint{.time=100, .value=-200};

    const result_crv = normalized_to(input_crv, min_point, max_point);
    const result_extents = result_crv.extents();

    try expectEqual(min_point.time, result_extents[0].time);
    try expectEqual(min_point.value, result_extents[0].value);

    try expectEqual(max_point.time, result_extents[1].time);
    try expectEqual(max_point.value, result_extents[1].value);
}

test "normalize_to_screen_coords" {
    var segments = [_]curve.Segment{
        curve.create_bezier_segment(
            .{.time = -500, .value=600},
            .{.time = -300, .value=-100},
            .{.time = 200, .value=300},
            .{.time = 500, .value=700},
        )
    };
    const input_crv:curve.TimeCurve = .{
        .segments = &segments
    };

    const min_point = ControlPoint{.time=700, .value=100};
    const max_point = ControlPoint{.time=2500, .value=1900};

    const result_crv = normalized_to(input_crv, min_point, max_point);
    const result_extents = result_crv.extents();

    try expectEqual(min_point.time, result_extents[0].time);
    try expectEqual(min_point.value, result_extents[0].value);

    try expectEqual(max_point.time, result_extents[1].time);
    try expectEqual(max_point.value, result_extents[1].value);
}

pub fn _compute_slope(p1: ControlPoint, p2: ControlPoint) f32 {
    return (p2.value - p1.value) / (p2.time - p1.time); 
}

pub fn inverted_linear(
    crv: linear_curve.TimeCurveLinear
) linear_curve.TimeCurveLinear 
{
    // require two points to define a line
    if (crv.knots.len < 2) {
        return crv;
    }

    var result = crv;
    result.knots = ALLOCATOR.dupe(
        ControlPoint,
        crv.knots
    ) catch unreachable;


    // check the slope
    const slope = _compute_slope(crv.knots[0], crv.knots[1]);

    const needs_reversal = slope < 0;
    const knot_count = crv.knots.len;

    for (crv.knots, 0..) |knot, index| {
        const real_index : usize = index;
        const real_knot:ControlPoint = knot;
        const target_index = (
            if (needs_reversal) knot_count - real_index - 1 else real_index
        );
        result.knots[target_index] = .{
            .time = real_knot.value,
            .value = real_knot.time, 
        };
    }

    return result;
}

pub fn inverted_bezier(
    crv: curve.TimeCurve
) linear_curve.TimeCurveLinear 
{
    const lin_crv = crv.linearized();
    return inverted_linear(lin_crv);
}

test "inverted: invert linear" {
    // slope 2
    const forward_crv = try curve.TimeCurve.init_from_start_end(
            .{.time = -1, .value = -3},
            .{.time = 1, .value = 1}
    );

    const inverse_crv = inverted_bezier(forward_crv);

    // ensure that temporal ordering is correct
    { 
        errdefer std.log.err(
            "knot0.time ({any}) < knot1.time ({any})",
            .{inverse_crv.knots[0].time, inverse_crv.knots[1].time}
        );
        try expect(inverse_crv.knots[0].time < inverse_crv.knots[1].time);
    }

    var identity_seg = [_]curve.Segment{
        // slope of 2
        curve.create_identity_segment(-3, 1)
    };
    const identity_crv:curve.TimeCurve = .{ .segments = &identity_seg };

    var t :f32 = 0;
    //           no split at t=1 (end point)
    while (t<1 - 0.01) 
        : (t += 0.01) 
    {
        const idntity_p = try identity_crv.evaluate(t);
        const forward_p = try forward_crv.evaluate(t);
        const inverse_p = try inverse_crv.evaluate(forward_p);

        errdefer std.log.err(
            "[t: {any}] ident: {any} forwd: {any} inv: {any}",
            .{t, idntity_p, forward_p, inverse_p}
        );

        // A * A-1 => 1
        try expectApproxEql(idntity_p, inverse_p);
    }
}

fn _rescale_val(
    t: f32,
    measure_min: f32, measure_max: f32,
    target_min: f32, target_max: f32
) f32
{
    return (
        (
         ((t - measure_min)/(measure_max - measure_min))
         * (target_max - target_min) 
        )
        + target_min
    );
}

fn _rescaled_pt(
    pt:ControlPoint,
    extents: [2]ControlPoint,
    target_range: [2]ControlPoint,
) ControlPoint
{
    return .{
        .time = _rescale_val(
            pt.time, 
            extents[0].time, extents[1].time,
            target_range[0].time, target_range[1].time
        ),
        .value = _rescale_val(
            pt.value,
            extents[0].value, extents[1].value,
            target_range[0].value, target_range[1].value
        ),
    };
}

// return a new curve rescaled over the domain
pub fn rescaled_curve(
    crv: curve.TimeCurve,
    target_range: [2]ControlPoint,
) !curve.TimeCurve
{
    const extents = crv.extents();

    var segments = std.ArrayList(curve.Segment).init(ALLOCATOR);
    defer segments.deinit();

    for (crv.segments) |seg| {
        const pts = seg.points();

        var new_pts:[4]ControlPoint = pts;

        for (pts, 0..) |pt, index| {
            new_pts[index] = _rescaled_pt(pt, extents, target_range);
        }

        var new_seg = curve.Segment.from_pt_array(new_pts);

        try segments.append(new_seg);
    }

    return curve.TimeCurve.init(segments.items);
}

test "TimeCurve: rescaled parameter" {
    const crv = try curve.read_curve_json(
        "curves/scurve.curve.json",
        std.testing.allocator
    );
    defer std.testing.allocator.free(crv.segments);

    const start_extents = crv.extents();

    try expectApproxEql(@as(f32, -0.5), start_extents[0].time);
    try expectApproxEql(@as(f32,  0.5), start_extents[1].time);

    try expectApproxEql(@as(f32, -0.5), start_extents[0].value);
    try expectApproxEql(@as(f32,  0.5), start_extents[1].value);

    const result = try rescaled_curve(
        crv,
        .{
            .{ .time = 100, .value = 0 },
            .{ .time = 200, .value = 10 },
        }
    );

    const end_extents = result.extents();

    try expectApproxEql(@as(f32, 100), end_extents[0].time);
    try expectApproxEql(@as(f32, 200), end_extents[1].time);

    try expectApproxEql(@as(f32, 0),  end_extents[0].value);
    try expectApproxEql(@as(f32, 10), end_extents[1].value);

}

// test "inverted: invert bezier" {
//     const forward_crv = try curve.read_curve_json("curves/scurve.curve.json");
//     const inverse_crv = inverted_bezier(forward_crv);
//
//     var identity_seg = [_]curve.Segment{
//         // slope of 2
//         curve.create_identity_segment(-3, 1)
//     };
//     const identity_crv:curve.TimeCurve = .{ .segments = &identity_seg };
//
//     var t :f32 = 0;
//     while (t<1) : (t += 0.01) {
//         errdefer std.log.err(
//             "[t: {any}]",
//             .{t}
//         );
//         const idntity_p = try identity_crv.evaluate(t);
//         errdefer std.log.err(
//             " ident: {any}",
//             .{idntity_p}
//         );
//         const forward_p = try forward_crv.evaluate(t);
//         errdefer std.log.err(
//             " forwd: {any}",
//             .{forward_p}
//         );
//         const inverse_p = try inverse_crv.evaluate(forward_p);
//         errdefer std.log.err(
//             " inv: {any}\n",
//             .{inverse_p}
//         );
//
//         // A * A-1 => 1
//         try expectApproxEql(idntity_p, inverse_p);
//     }
// }
