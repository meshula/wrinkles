// bezier_math.h - Bezier curve mathematics and algorithms
// Ported from src/curve/bezier_math.zig
//
// Provides algorithms for working with cubic Bezier curves including:
// - Segment reduction (de Casteljau's algorithm)
// - Bezier evaluation
// - Root finding for parameter inversion
// - Curve order detection

#pragma once

#include "../opentime/opentime.h"
#include "../opentime/lerp.h"
#include "control_point.h"
#include "epsilon.h"
#include <math.h>
#include <stdbool.h>

//=============================================================================
// Helper: linear interpolation for control points
//=============================================================================

/// Linear interpolation between two control points
static inline ControlPoint control_point_lerp(
    Ordinate u,
    ControlPoint a,
    ControlPoint b
) {
    return (ControlPoint){
        .in = opentime_lerp(u, a.in, b.in),
        .out = opentime_lerp(u, a.out, b.out)
    };
}

/// Linear interpolation between two dual control points
static inline Dual_CP dual_cp_lerp(
    Dual_Ord u,
    Dual_CP a,
    Dual_CP b
) {
    return (Dual_CP){
        .in = opentime_lerp_dual(u, a.in, b.in),
        .out = opentime_lerp_dual(u, a.out, b.out)
    };
}

//=============================================================================
// Forward declarations for bezier curve types
//=============================================================================

/// Bezier segment with 4 control points
typedef struct {
    ControlPoint p0;
    ControlPoint p1;
    ControlPoint p2;
    ControlPoint p3;
} BezierSegment;

/// Dual bezier segment with 4 dual control points (for automatic differentiation)
typedef struct {
    Dual_CP p0;
    Dual_CP p1;
    Dual_CP p2;
    Dual_CP p3;
} BezierSegment_Dual;

//=============================================================================
// Simple interpolation utilities
//=============================================================================

/// Compute output value at input between two control points (linear interp)
static inline Ordinate output_at_input_between(
    Ordinate t,
    ControlPoint fst,
    ControlPoint snd
) {
    Ordinate u = opentime_invlerp(t, fst.in, snd.in);
    return opentime_lerp(u, fst.out, snd.out);
}

/// Compute input value at output between two control points (inverse linear interp)
static inline Ordinate input_at_output_between(
    Ordinate v,
    ControlPoint fst,
    ControlPoint snd
) {
    Ordinate u = opentime_invlerp(v, fst.out, snd.out);
    return opentime_lerp(u, fst.in, snd.in);
}

//=============================================================================
// Segment reduction (de Casteljau's algorithm)
//=============================================================================

/// Reduce a cubic bezier to a quadratic (4 points -> 3 points)
/// This is one step of de Casteljau's algorithm
static inline BezierSegment bezier_segment_reduce4(
    Ordinate u,
    BezierSegment segment
) {
    return (BezierSegment){
        .p0 = control_point_lerp(u, segment.p0, segment.p1),
        .p1 = control_point_lerp(u, segment.p1, segment.p2),
        .p2 = control_point_lerp(u, segment.p2, segment.p3),
        .p3 = control_point_zero()
    };
}

/// Reduce a quadratic to a linear (3 points -> 2 points)
static inline BezierSegment bezier_segment_reduce3(
    Ordinate u,
    BezierSegment segment
) {
    return (BezierSegment){
        .p0 = control_point_lerp(u, segment.p0, segment.p1),
        .p1 = control_point_lerp(u, segment.p1, segment.p2),
        .p2 = control_point_zero(),
        .p3 = control_point_zero()
    };
}

/// Reduce a linear to a point (2 points -> 1 point)
static inline BezierSegment bezier_segment_reduce2(
    Ordinate u,
    BezierSegment segment
) {
    return (BezierSegment){
        .p0 = control_point_lerp(u, segment.p0, segment.p1),
        .p1 = control_point_zero(),
        .p2 = control_point_zero(),
        .p3 = control_point_zero()
    };
}

//=============================================================================
// Dual segment reduction (for automatic differentiation)
//=============================================================================

/// Reduce a dual cubic bezier to a quadratic (4 points -> 3 points)
static inline BezierSegment_Dual bezier_segment_reduce4_dual(
    Dual_Ord u,
    BezierSegment_Dual segment
) {
    return (BezierSegment_Dual){
        .p0 = dual_cp_lerp(u, segment.p0, segment.p1),
        .p1 = dual_cp_lerp(u, segment.p1, segment.p2),
        .p2 = dual_cp_lerp(u, segment.p2, segment.p3),
        .p3 = dual_cp_zero()
    };
}

/// Reduce a dual quadratic to a linear (3 points -> 2 points)
static inline BezierSegment_Dual bezier_segment_reduce3_dual(
    Dual_Ord u,
    BezierSegment_Dual segment
) {
    return (BezierSegment_Dual){
        .p0 = dual_cp_lerp(u, segment.p0, segment.p1),
        .p1 = dual_cp_lerp(u, segment.p1, segment.p2),
        .p2 = dual_cp_zero(),
        .p3 = dual_cp_zero()
    };
}

/// Reduce a dual linear to a point (2 points -> 1 point)
static inline BezierSegment_Dual bezier_segment_reduce2_dual(
    Dual_Ord u,
    BezierSegment_Dual segment
) {
    return (BezierSegment_Dual){
        .p0 = dual_cp_lerp(u, segment.p0, segment.p1),
        .p1 = dual_cp_zero(),
        .p2 = dual_cp_zero(),
        .p3 = dual_cp_zero()
    };
}

//=============================================================================
// Bezier evaluation
//=============================================================================

/// Evaluate a 1D cubic Bezier curve where the first point is 0
/// This is an optimized form used in root finding
/// Formula: B(u) = u³*p4 - 3*u²*(1-u)*p3 + 3*u*(1-u)²*p2
static inline Ordinate bezier_evaluate_bezier0(
    Ordinate unorm,
    Ordinate p2,
    Ordinate p3,
    Ordinate p4
) {
    // p1 = 0, so the last term falls out
    Ordinate u = unorm;
    Ordinate u2 = ordinate_mul(u, u);
    Ordinate u3 = ordinate_mul(u2, u);

    Ordinate u_minus_one = ordinate_sub(u, ordinate_init(1.0)); // u - 1 (negative!)
    Ordinate umo2 = ordinate_mul(u_minus_one, u_minus_one);

    // u³ * p4
    Ordinate term1 = ordinate_mul(u3, p4);

    // - (p3 * u² * (u-1) * 3.0)
    Ordinate term2 = ordinate_mul(
        ordinate_mul(ordinate_mul(p3, u2), u_minus_one),
        ordinate_init(3.0)
    );

    // p2 * 3.0 * u * (u-1)²
    Ordinate term3 = ordinate_mul(
        ordinate_mul(ordinate_mul(p2, ordinate_init(3.0)), u),
        umo2
    );

    return ordinate_add(ordinate_sub(term1, term2), term3);
}

/// Dual version of bezier0 evaluation for automatic differentiation
/// Evaluates a 1D cubic Bezier where the first point is 0
/// Returns dual number with derivative information
static inline Dual_Ord bezier_evaluate_bezier0_dual(
    Dual_Ord unorm,
    Ordinate p2,
    Ordinate p3,
    Ordinate p4
) {
    // Convert ordinates to dual numbers for computation
    Dual_Ord p2_dual = dual_ord_init(p2);
    Dual_Ord p3_dual = dual_ord_init(p3);
    Dual_Ord p4_dual = dual_ord_init(p4);

    // u and (u-1)
    Dual_Ord u = unorm;
    Dual_Ord u_minus_one = dual_ord_sub_ord(u, dual_ord_init_d(1.0).r);
    // Derivative of (u-1) w.r.t. u is 1, so u_minus_one.i remains u.i (already set by sub_ord)

    // u², u³
    Dual_Ord u2 = dual_ord_mul(u, u);
    Dual_Ord u3 = dual_ord_mul(u2, u);

    // (u-1)²
    Dual_Ord umo2 = dual_ord_mul(u_minus_one, u_minus_one);

    // u³ * p4
    Dual_Ord term1 = dual_ord_mul(u3, p4_dual);

    // - (p3 * u² * (u-1) * 3.0)
    Dual_Ord term2 = dual_ord_mul(
        dual_ord_mul(
            dual_ord_mul(p3_dual, u2),
            u_minus_one
        ),
        dual_ord_init(ordinate_init(3.0))
    );

    // p2 * 3.0 * u * (u-1)²
    Dual_Ord term3 = dual_ord_mul(
        dual_ord_mul(
            dual_ord_mul(p2_dual, dual_ord_init(ordinate_init(3.0))),
            u
        ),
        umo2
    );

    // u³*p4 - (p3*u²*(u-1)*3.0) + (p2*3.0*u*(u-1)²)
    return dual_ord_add(dual_ord_sub(term1, term2), term3);
}

//=============================================================================
// Root finding
//=============================================================================

/// Find parameter u such that B(u) == x for a monotonic 1D Bezier
/// Uses Illinois algorithm (modified regula falsi)
///
/// Given x in [0, p3] and a monotonically nondecreasing Bezier B(u)
/// with control points (0, p1, p2, p3), find u such that B(u) == x
static inline double bezier_find_u(
    Ordinate x,
    Ordinate p1,
    Ordinate p2,
    Ordinate p3
) {
    const Ordinate MAX_ABS_ERROR = ordinate_init(2.0 * 2.2204460492503131e-16); // 2 * DBL_EPSILON
    const int MAX_ITERATIONS = 45;

    // Early exits for boundary conditions
    if (ordinate_lteq(x, ORDINATE_ZERO)) {
        return 0.0;
    }
    if (ordinate_gteq(x, p3)) {
        return 1.0;
    }

    // Initialize bracket
    Ordinate u1 = ORDINATE_ZERO;
    Ordinate u2 = ORDINATE_ZERO;
    Ordinate x1 = ordinate_neg(x); // bezier0(0, ...) - x
    Ordinate x2 = ordinate_sub(p3, x); // bezier0(1, ...) - x

    // First iteration using regula falsi
    {
        Ordinate u3 = ordinate_sub(
            ORDINATE_ONE,
            ordinate_div(x2, ordinate_sub(x2, x1))
        );
        Ordinate x3 = ordinate_sub(
            bezier_evaluate_bezier0(u3, p1, p2, p3),
            x
        );

        if (ordinate_eql(x3, ORDINATE_ZERO)) {
            return ordinate_as_double(u3);
        }

        if (ordinate_lt(x3, ORDINATE_ZERO)) {
            if (ordinate_lteq(ordinate_sub(ORDINATE_ONE, u3), MAX_ABS_ERROR)) {
                if (ordinate_lt(x2, ordinate_neg(x3))) {
                    return 1.0;
                }
                return ordinate_as_double(u3);
            }
            u1 = ORDINATE_ONE;
            x1 = x2;
        } else {
            u1 = ORDINATE_ZERO;
            x1 = ordinate_div(
                ordinate_mul(x1, x2),
                ordinate_add(x2, x3)
            );

            if (ordinate_lteq(u3, MAX_ABS_ERROR)) {
                if (ordinate_lt(ordinate_neg(x1), x3)) {
                    return 0.0;
                }
                return ordinate_as_double(u3);
            }
        }
        u2 = u3;
        x2 = x3;
    }

    // Illinois algorithm iteration
    for (int i = MAX_ITERATIONS - 1; i > 0; i--) {
        Ordinate u3 = ordinate_sub(
            u2,
            ordinate_mul(
                x2,
                ordinate_div(ordinate_sub(u2, u1), ordinate_sub(x2, x1))
            )
        );
        Ordinate x3 = ordinate_sub(
            bezier_evaluate_bezier0(u3, p1, p2, p3),
            x
        );

        if (ordinate_eql(x3, ORDINATE_ZERO)) {
            return ordinate_as_double(u3);
        }

        // Check if we have a bracket
        if (ordinate_lteq(ordinate_mul(x2, x3), ORDINATE_ZERO)) {
            u1 = u2;
            x1 = x2;
        } else {
            // Illinois modification: reduce weight of older bound
            x1 = ordinate_div(
                ordinate_mul(x1, x2),
                ordinate_add(x2, x3)
            );
        }

        u2 = u3;
        x2 = x3;

        // Check convergence
        Ordinate diff = ordinate_gt(u2, u1)
            ? ordinate_sub(u2, u1)
            : ordinate_sub(u1, u2);

        if (ordinate_lteq(diff, MAX_ABS_ERROR)) {
            break;
        }
    }

    // Return the bound with smaller absolute error
    Ordinate abs_x1 = ordinate_abs(x1);
    Ordinate abs_x2 = ordinate_abs(x2);

    if (ordinate_lt(abs_x1, abs_x2)) {
        return ordinate_as_double(u1);
    }
    return ordinate_as_double(u2);
}

//=============================================================================
// Curve analysis
//=============================================================================

/// Calculate the actual order of a Bezier curve
/// Returns 1 for linear, 2 for quadratic, 3 for cubic
/// Returns -1 for degenerate (no solution)
static inline int bezier_actual_order(
    Ordinate p0,
    Ordinate p1,
    Ordinate p2,
    Ordinate p3
) {
    // Compute coefficients
    // d = -p0 + 3*p1 - 3*p2 + p3  (cubic coefficient)
    Ordinate d = ordinate_add(
        ordinate_add(ordinate_neg(p0), ordinate_mul_d(p1, 3.0)),
        ordinate_add(ordinate_mul_d(p2, -3.0), p3)
    );

    // a = 3*p0 - 6*p1 + 3*p2  (quadratic coefficient)
    Ordinate a = ordinate_add(
        ordinate_add(ordinate_mul_d(p0, 3.0), ordinate_mul_d(p1, -6.0)),
        ordinate_mul_d(p2, 3.0)
    );

    // b = -3*p0 + 3*p1  (linear coefficient)
    Ordinate b = ordinate_add(
        ordinate_mul_d(p0, -3.0),
        ordinate_mul_d(p1, 3.0)
    );

    // Check order by examining coefficients
    if (ordinate_lt(ordinate_abs(d), ORDINATE_EPSILON)) {
        // Not cubic
        if (ordinate_lt(ordinate_abs(a), ORDINATE_EPSILON)) {
            // Not quadratic
            if (ordinate_lt(ordinate_abs(b), ORDINATE_EPSILON)) {
                // Degenerate
                return -1;
            }
            // Linear
            return 1;
        }
        // Quadratic
        return 2;
    }
    // Cubic
    return 3;
}
