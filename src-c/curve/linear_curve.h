// linear_curve.h - Piecewise linear curves
// Ported from src/curve/linear_curve.zig
//
// Linear curves are made of right-met connected line segments.
// A polyline that is linearly interpolated between knots.

#pragma once

#include "../opentime/opentime.h"
#include "control_point.h"
#include "bezier_math.h"
#include <stdlib.h>
#include <stdbool.h>

//=============================================================================
// LinearCurve type
//=============================================================================

/// A piecewise linear curve defined by control point knots
/// This is a monomorphic implementation using ControlPoint
/// Uses standard malloc/free for memory management
typedef struct {
    /// Array of knots (control points) defining the curve
    ControlPoint* knots;
    /// Number of knots in the curve
    size_t knot_count;
} LinearCurve;

/// Monotonic form of a linear curve
/// Guaranteed to be monotonic in the input space (no reversals)
typedef struct {
    /// Array of knots (control points) defining the monotonic curve
    ControlPoint* knots;
    /// Number of knots in the curve
    size_t knot_count;
} LinearCurve_Monotonic;

//=============================================================================
// Lifecycle - LinearCurve
//=============================================================================

/// Initialize an empty linear curve
static inline void linear_curve_init(LinearCurve* curve) {
    curve->knots = NULL;
    curve->knot_count = 0;
}

/// Initialize a linear curve from an array of knots (copies knots)
static inline bool linear_curve_init_from_knots(
    LinearCurve* curve,
    const ControlPoint* knots,
    size_t knot_count
) {
    curve->knot_count = knot_count;

    if (knot_count == 0) {
        curve->knots = NULL;
        return true;
    }

    curve->knots = (ControlPoint*)malloc(knot_count * sizeof(ControlPoint));
    if (!curve->knots) {
        return false;
    }

    for (size_t i = 0; i < knot_count; i++) {
        curve->knots[i] = knots[i];
    }

    return true;
}

/// Initialize an identity linear curve (maps input to output 1:1)
static inline bool linear_curve_init_identity(
    LinearCurve* curve,
    ContinuousInterval interval
) {
    ControlPoint knots[2] = {
        control_point_init(interval.start.v, interval.start.v),
        control_point_init(interval.end.v, interval.end.v)
    };

    return linear_curve_init_from_knots(curve, knots, 2);
}

/// Free linear curve resources
static inline void linear_curve_deinit(LinearCurve* curve) {
    if (curve->knots) {
        free(curve->knots);
    }
    curve->knots = NULL;
    curve->knot_count = 0;
}

/// Clone a linear curve (deep copy)
static inline bool linear_curve_clone(
    const LinearCurve* src,
    LinearCurve* dst
) {
    return linear_curve_init_from_knots(dst, src->knots, src->knot_count);
}

//=============================================================================
// Lifecycle - LinearCurve_Monotonic
//=============================================================================

/// Initialize an empty monotonic linear curve
static inline void linear_curve_monotonic_init(LinearCurve_Monotonic* curve) {
    curve->knots = NULL;
    curve->knot_count = 0;
}

/// Initialize a monotonic linear curve from knots (copies knots)
static inline bool linear_curve_monotonic_init_from_knots(
    LinearCurve_Monotonic* curve,
    const ControlPoint* knots,
    size_t knot_count
) {
    curve->knot_count = knot_count;

    if (knot_count == 0) {
        curve->knots = NULL;
        return true;
    }

    curve->knots = (ControlPoint*)malloc(knot_count * sizeof(ControlPoint));
    if (!curve->knots) {
        return false;
    }

    for (size_t i = 0; i < knot_count; i++) {
        curve->knots[i] = knots[i];
    }

    return true;
}

/// Free monotonic linear curve resources
static inline void linear_curve_monotonic_deinit(LinearCurve_Monotonic* curve) {
    if (curve->knots) {
        free(curve->knots);
    }
    curve->knots = NULL;
    curve->knot_count = 0;
}

/// Clone a monotonic linear curve (deep copy)
static inline bool linear_curve_monotonic_clone(
    const LinearCurve_Monotonic* src,
    LinearCurve_Monotonic* dst
) {
    return linear_curve_monotonic_init_from_knots(dst, src->knots, src->knot_count);
}

//=============================================================================
// Extent computation - Monotonic
//=============================================================================

/// Compute both input and output extents for the curve
/// Returns false if curve is empty
/// min is written to extents[0], max to extents[1]
static inline bool linear_curve_monotonic_extents(
    const LinearCurve_Monotonic* curve,
    ControlPoint extents[2]
) {
    if (curve->knot_count == 0) {
        return false;
    }

    ControlPoint min = curve->knots[0];
    ControlPoint max = curve->knots[0];

    // Check first and last knots
    const ControlPoint* knots_to_check[2] = {
        &curve->knots[0],
        &curve->knots[curve->knot_count - 1]
    };

    for (size_t i = 0; i < 2; i++) {
        const ControlPoint* knot = knots_to_check[i];

        if (ordinate_lt(knot->in, min.in)) min.in = knot->in;
        if (ordinate_gt(knot->in, max.in)) max.in = knot->in;
        if (ordinate_lt(knot->out, min.out)) min.out = knot->out;
        if (ordinate_gt(knot->out, max.out)) max.out = knot->out;
    }

    extents[0] = min;
    extents[1] = max;
    return true;
}

/// Compute input extents for the curve
/// Returns false if curve is empty
static inline bool linear_curve_monotonic_extents_input(
    const LinearCurve_Monotonic* curve,
    ContinuousInterval* interval
) {
    if (curve->knot_count < 1) {
        return false;
    }

    Ordinate fst = curve->knots[0].in;
    Ordinate lst = curve->knots[curve->knot_count - 1].in;

    interval->start = ordinate_lt(fst, lst) ? fst : lst;
    interval->end = ordinate_gt(fst, lst) ? fst : lst;

    return true;
}

/// Compute output extents for the curve
/// Returns false if curve is empty
static inline bool linear_curve_monotonic_extents_output(
    const LinearCurve_Monotonic* curve,
    ContinuousInterval* interval
) {
    if (curve->knot_count < 1) {
        return false;
    }

    Ordinate fst = curve->knots[0].out;
    Ordinate lst = curve->knots[curve->knot_count - 1].out;

    interval->start = ordinate_lt(fst, lst) ? fst : lst;
    interval->end = ordinate_gt(fst, lst) ? fst : lst;

    return true;
}

//=============================================================================
// Interpolation - Monotonic
//=============================================================================

/// Evaluate the curve at a given input value
/// Returns the output value at the given input
static inline Ordinate linear_curve_monotonic_output_at_input(
    const LinearCurve_Monotonic* curve,
    Ordinate input
) {
    if (curve->knot_count == 0) {
        return input;  // Identity fallback
    }

    if (curve->knot_count == 1) {
        return curve->knots[0].out;
    }

    // Find the segment containing the input
    for (size_t i = 0; i < curve->knot_count - 1; i++) {
        const ControlPoint* p0 = &curve->knots[i];
        const ControlPoint* p1 = &curve->knots[i + 1];

        // Check if input is in this segment
        bool in_segment =
            (ordinate_lteq(p0->in, input) && ordinate_lt(input, p1->in)) ||
            (ordinate_gteq(p0->in, input) && ordinate_gt(input, p1->in));

        if (in_segment || i == curve->knot_count - 2) {
            return output_at_input_between(input, *p0, *p1);
        }
    }

    // Fallback: return last knot output
    return curve->knots[curve->knot_count - 1].out;
}

/// Find the input value that produces a given output value
/// Returns the input value at the given output (inverse operation)
static inline Ordinate linear_curve_monotonic_input_at_output(
    const LinearCurve_Monotonic* curve,
    Ordinate output
) {
    if (curve->knot_count == 0) {
        return output;  // Identity fallback
    }

    if (curve->knot_count == 1) {
        return curve->knots[0].in;
    }

    // Find the segment containing the output
    for (size_t i = 0; i < curve->knot_count - 1; i++) {
        const ControlPoint* p0 = &curve->knots[i];
        const ControlPoint* p1 = &curve->knots[i + 1];

        // Check if output is in this segment
        bool in_segment =
            (ordinate_lteq(p0->out, output) && ordinate_lt(output, p1->out)) ||
            (ordinate_gteq(p0->out, output) && ordinate_gt(output, p1->out));

        if (in_segment || i == curve->knot_count - 2) {
            return input_at_output_between(output, *p0, *p1);
        }
    }

    // Fallback: return last knot input
    return curve->knots[curve->knot_count - 1].in;
}
