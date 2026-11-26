// bezier_curve.h - Cubic Bezier curve segments and curves
// Ported from src/curve/bezier_curve.zig
//
// A sequence of right-met 2D Bezier curve segments closed on the left and
// open on the right. If the first formal segment does not start at -inf,
// there is an implicit interval spanning -inf to the first formal segment.
// If the final formal segment does not end at +inf, there is an implicit
// interval spanning the last point in the final formal segment to +inf.
//
// The parameterization of the Bezier curve is named 'u'. 'u' must be within
// the closed interval [0, 1].
//
// The input and output value of a Bezier at 'u' is B_in(u) and B_out(u).

#pragma once

#include "../opentime/opentime.h"
#include "control_point.h"
#include "bezier_math.h"
#include "epsilon.h"
#include "../hodographs/hodographs.h"
#include "linear_curve.h"
#include <stdlib.h>
#include <stdbool.h>
#include <math.h>

// Note: BezierSegment is already defined in bezier_math.h

//=============================================================================
// Bezier Curve type
//=============================================================================

/// A piecewise cubic Bezier curve composed of segments
typedef struct {
    /// Array of Bezier segments
    BezierSegment* segments;
    /// Number of segments in the curve
    size_t segment_count;
} BezierCurve;

//=============================================================================
// Segment Constructors
//=============================================================================

/// Initialize an identity Bezier segment (linear, input == output)
/// Maps [input_start, input_end) to itself
static inline BezierSegment bezier_segment_init_identity(
    Ordinate input_start,
    Ordinate input_end
) {
    ControlPoint start = { .in = input_start, .out = input_start };
    ControlPoint end = { .in = input_end, .out = input_end };

    // Linear segment: p1 at 1/3, p2 at 2/3
    ControlPoint p1 = control_point_lerp(ordinate_init(1.0/3.0), start, end);
    ControlPoint p2 = control_point_lerp(ordinate_init(2.0/3.0), start, end);

    return (BezierSegment){
        .p0 = start,
        .p1 = p1,
        .p2 = p2,
        .p3 = end
    };
}

/// Initialize a linear Bezier segment between two control points
/// The segment will be linear (straight line) in both input and output space
static inline BezierSegment bezier_segment_init_from_start_end(
    ControlPoint start,
    ControlPoint end
) {
    // Validate: end must be >= start in input space
    if (ordinate_lt(end.in, start.in)) {
        // Invalid: return identity segment as fallback
        return bezier_segment_init_identity(start.in, start.in);
    }

    // Linear segment: p1 at 1/3, p2 at 2/3
    ControlPoint p1 = control_point_lerp(ordinate_init(1.0/3.0), start, end);
    ControlPoint p2 = control_point_lerp(ordinate_init(2.0/3.0), start, end);

    return (BezierSegment){
        .p0 = start,
        .p1 = p1,
        .p2 = p2,
        .p3 = end
    };
}

/// Initialize a Bezier segment from raw values
static inline BezierSegment bezier_segment_init(
    double p0_in, double p0_out,
    double p1_in, double p1_out,
    double p2_in, double p2_out,
    double p3_in, double p3_out
) {
    return (BezierSegment){
        .p0 = control_point_init(p0_in, p0_out),
        .p1 = control_point_init(p1_in, p1_out),
        .p2 = control_point_init(p2_in, p2_out),
        .p3 = control_point_init(p3_in, p3_out)
    };
}

//=============================================================================
// Segment Evaluation
//=============================================================================

/// Evaluate the Bezier segment at parameter u [0, 1]
/// Uses de Casteljau's algorithm via segment reduction
static inline ControlPoint bezier_segment_eval_at(
    const BezierSegment* seg,
    Ordinate u
) {
    // Convert BezierSegment to bezier_math's format
    BezierSegment seg_math = *seg;

    // Three-step reduction (de Casteljau)
    BezierSegment seg3 = bezier_segment_reduce4(u, seg_math);
    BezierSegment seg2 = bezier_segment_reduce3(u, seg3);
    BezierSegment result = bezier_segment_reduce2(u, seg2);

    return result.p0;
}

/// Evaluate the Bezier segment at parameter u with automatic differentiation
/// Returns both the value and its derivative with respect to u
static inline Dual_CP bezier_segment_eval_at_dual(
    const BezierSegment* seg,
    Dual_Ord u
) {
    // Convert to dual control points
    Dual_CP seg_dual[4] = {
        dual_cp_init(seg->p0),
        dual_cp_init(seg->p1),
        dual_cp_init(seg->p2),
        dual_cp_init(seg->p3)
    };

    // Three-step reduction with dual numbers
    BezierSegment_Dual seg3 = {
        .p0 = seg_dual[0],
        .p1 = seg_dual[1],
        .p2 = seg_dual[2],
        .p3 = seg_dual[3]
    };

    BezierSegment_Dual reduced3 = bezier_segment_reduce4_dual(u, seg3);
    BezierSegment_Dual reduced2 = bezier_segment_reduce3_dual(u, reduced3);
    BezierSegment_Dual result = bezier_segment_reduce2_dual(u, reduced2);

    return result.p0;
}

//=============================================================================
// Segment FindU Functions
//=============================================================================

/// Find the parameter u where the segment's input coordinate equals the target
/// Returns u in [0, 1], or NaN if not found
static inline double bezier_segment_findU_input(
    const BezierSegment* seg,
    Ordinate target_input
) {
    // Extract input ordinates
    Ordinate p0 = seg->p0.in;
    Ordinate p1 = seg->p1.in;
    Ordinate p2 = seg->p2.in;
    Ordinate p3 = seg->p3.in;

    // Use bezier_find_u from bezier_math
    // Note: bezier_find_u expects bezier0 form (first point at 0)
    // so we need to transform: x' = x - p0
    Ordinate target_shifted = ordinate_sub(target_input, p0);
    Ordinate p1_shifted = ordinate_sub(p1, p0);
    Ordinate p2_shifted = ordinate_sub(p2, p0);
    Ordinate p3_shifted = ordinate_sub(p3, p0);

    return bezier_find_u(target_shifted, p1_shifted, p2_shifted, p3_shifted);
}

/// Find the parameter u where the segment's output coordinate equals the target
/// Returns u in [0, 1], or NaN if not found
static inline double bezier_segment_findU_output(
    const BezierSegment* seg,
    Ordinate target_output
) {
    // Extract output ordinates
    Ordinate p0 = seg->p0.out;
    Ordinate p1 = seg->p1.out;
    Ordinate p2 = seg->p2.out;
    Ordinate p3 = seg->p3.out;

    // Transform to bezier0 form
    Ordinate target_shifted = ordinate_sub(target_output, p0);
    Ordinate p1_shifted = ordinate_sub(p1, p0);
    Ordinate p2_shifted = ordinate_sub(p2, p0);
    Ordinate p3_shifted = ordinate_sub(p3, p0);

    return bezier_find_u(target_shifted, p1_shifted, p2_shifted, p3_shifted);
}

//=============================================================================
// Segment Splitting
//=============================================================================

/// Split a Bezier segment at parameter u [0, 1]
/// Returns false if u is out of valid range (< epsilon or >= 1.0)
/// Uses de Casteljau's algorithm for numerically stable splitting
static inline bool bezier_segment_split_at(
    const BezierSegment* seg,
    double u,
    BezierSegment* left,
    BezierSegment* right
) {
    if (u < CURVE_EPSILON || u >= 1.0) {
        return false;
    }

    const Ordinate u_ord = ordinate_init(u);

    // De Casteljau subdivision - three levels of linear interpolation
    // First level
    ControlPoint Q1 = control_point_lerp(u_ord, seg->p0, seg->p1);
    ControlPoint Q2 = control_point_lerp(u_ord, seg->p1, seg->p2);
    ControlPoint Q3 = control_point_lerp(u_ord, seg->p2, seg->p3);

    // Second level
    ControlPoint R1 = control_point_lerp(u_ord, Q1, Q2);
    ControlPoint R2 = control_point_lerp(u_ord, Q2, Q3);

    // Third level - the point on the curve at u
    ControlPoint P = control_point_lerp(u_ord, R1, R2);

    // Left segment: [0, u]
    left->p0 = seg->p0;
    left->p1 = Q1;
    left->p2 = R1;
    left->p3 = P;

    // Right segment: [u, 1]
    right->p0 = P;
    right->p1 = R2;
    right->p2 = Q3;
    right->p3 = seg->p3;

    return true;
}

//=============================================================================
// Segment Extents
//=============================================================================

/// Compute the bounding box of a segment's input space
static inline void bezier_segment_extents_input(
    const BezierSegment* seg,
    ContinuousInterval* interval
) {
    Ordinate min = seg->p0.in;
    Ordinate max = seg->p0.in;

    if (ordinate_lt(seg->p3.in, min)) min = seg->p3.in;
    if (ordinate_gt(seg->p3.in, max)) max = seg->p3.in;

    interval->start = min;
    interval->end = max;
}

/// Compute the bounding box of a segment's output space
static inline void bezier_segment_extents_output(
    const BezierSegment* seg,
    ContinuousInterval* interval
) {
    Ordinate min = seg->p0.out;
    Ordinate max = seg->p0.out;

    if (ordinate_lt(seg->p3.out, min)) min = seg->p3.out;
    if (ordinate_gt(seg->p3.out, max)) max = seg->p3.out;

    interval->start = min;
    interval->end = max;
}

/// Compute both input and output extents
static inline void bezier_segment_extents(
    const BezierSegment* seg,
    ControlPoint extents[2]
) {
    // Min extents
    extents[0].in = seg->p0.in;
    extents[0].out = seg->p0.out;

    // Max extents
    extents[1].in = seg->p0.in;
    extents[1].out = seg->p0.out;

    // Check p3
    if (ordinate_lt(seg->p3.in, extents[0].in)) extents[0].in = seg->p3.in;
    if (ordinate_gt(seg->p3.in, extents[1].in)) extents[1].in = seg->p3.in;
    if (ordinate_lt(seg->p3.out, extents[0].out)) extents[0].out = seg->p3.out;
    if (ordinate_gt(seg->p3.out, extents[1].out)) extents[1].out = seg->p3.out;
}

//=============================================================================
// Bezier Curve Lifecycle
//=============================================================================

/// Initialize an empty Bezier curve
static inline void bezier_curve_init(BezierCurve* curve) {
    curve->segments = NULL;
    curve->segment_count = 0;
}

/// Initialize a Bezier curve from an array of segments (copies segments)
static inline bool bezier_curve_init_from_segments(
    BezierCurve* curve,
    const BezierSegment* segments,
    size_t segment_count
) {
    curve->segment_count = segment_count;

    if (segment_count == 0) {
        curve->segments = NULL;
        return true;
    }

    curve->segments = (BezierSegment*)malloc(segment_count * sizeof(BezierSegment));
    if (!curve->segments) {
        return false;
    }

    for (size_t i = 0; i < segment_count; i++) {
        curve->segments[i] = segments[i];
    }

    return true;
}

/// Free Bezier curve resources
static inline void bezier_curve_deinit(BezierCurve* curve) {
    if (curve->segments) {
        free(curve->segments);
    }
    curve->segments = NULL;
    curve->segment_count = 0;
}

/// Clone a Bezier curve (deep copy)
static inline bool bezier_curve_clone(
    const BezierCurve* src,
    BezierCurve* dst
) {
    return bezier_curve_init_from_segments(dst, src->segments, src->segment_count);
}

//=============================================================================
// Bezier Curve Operations
//=============================================================================

/// Find the index of the segment containing the given input ordinate
/// Returns (size_t)-1 if not found
static inline size_t bezier_curve_find_segment_index(
    const BezierCurve* curve,
    Ordinate input
) {
    if (curve->segment_count == 0) {
        return (size_t)-1;
    }

    // Search for the segment containing this input
    for (size_t i = 0; i < curve->segment_count; i++) {
        const BezierSegment* seg = &curve->segments[i];

        // Check if input is within this segment's input range
        bool in_range =
            (ordinate_gteq(input, seg->p0.in) && ordinate_lt(input, seg->p3.in)) ||
            (ordinate_lteq(input, seg->p0.in) && ordinate_gt(input, seg->p3.in));

        if (in_range) {
            return i;
        }
    }

    // Not found in any segment
    return (size_t)-1;
}

/// Get a pointer to the segment containing the given input ordinate
/// Returns NULL if not found
static inline const BezierSegment* bezier_curve_find_segment(
    const BezierCurve* curve,
    Ordinate input
) {
    size_t index = bezier_curve_find_segment_index(curve, input);
    if (index == (size_t)-1) {
        return NULL;
    }
    return &curve->segments[index];
}

/// Evaluate a segment at a given input value
/// Returns the output ordinate, or NaN if input is out of range
static inline Ordinate bezier_segment_output_at_input(
    const BezierSegment* seg,
    Ordinate input
) {
    // Find u parameter for this input within the segment
    double u = bezier_segment_findU_input(seg, input);
    if (isnan(u)) {
        return ORDINATE_NAN;
    }

    // Evaluate the segment at u to get the output
    ControlPoint result = bezier_segment_eval_at(seg, ordinate_init(u));
    return result.out;
}

/// Evaluate the curve at a given input value
/// Returns the output ordinate, or NaN if input is out of range
static inline Ordinate bezier_curve_output_at_input(
    const BezierCurve* curve,
    Ordinate input
) {
    // Find the segment containing this input
    const BezierSegment* seg = bezier_curve_find_segment(curve, input);
    if (!seg) {
        return ORDINATE_NAN;
    }

    return bezier_segment_output_at_input(seg, input);
}

/// Compute input extents for the curve
static inline bool bezier_curve_extents_input(
    const BezierCurve* curve,
    ContinuousInterval* interval
) {
    if (curve->segment_count == 0) {
        return false;
    }

    Ordinate min = curve->segments[0].p0.in;
    Ordinate max = curve->segments[0].p0.in;

    for (size_t i = 0; i < curve->segment_count; i++) {
        const BezierSegment* seg = &curve->segments[i];

        if (ordinate_lt(seg->p0.in, min)) min = seg->p0.in;
        if (ordinate_gt(seg->p0.in, max)) max = seg->p0.in;
        if (ordinate_lt(seg->p3.in, min)) min = seg->p3.in;
        if (ordinate_gt(seg->p3.in, max)) max = seg->p3.in;
    }

    interval->start = min;
    interval->end = max;
    return true;
}

/// Compute output extents for the curve
static inline bool bezier_curve_extents_output(
    const BezierCurve* curve,
    ContinuousInterval* interval
) {
    if (curve->segment_count == 0) {
        return false;
    }

    Ordinate min = curve->segments[0].p0.out;
    Ordinate max = curve->segments[0].p0.out;

    for (size_t i = 0; i < curve->segment_count; i++) {
        const BezierSegment* seg = &curve->segments[i];

        if (ordinate_lt(seg->p0.out, min)) min = seg->p0.out;
        if (ordinate_gt(seg->p0.out, max)) max = seg->p0.out;
        if (ordinate_lt(seg->p3.out, min)) min = seg->p3.out;
        if (ordinate_gt(seg->p3.out, max)) max = seg->p3.out;
    }

    interval->start = min;
    interval->end = max;
    return true;
}

//=============================================================================
// Hodograph Integration - Conversion Functions
//=============================================================================

/// Convert our BezierSegment to hodographs library HodoBezierSegment format
/// Our segments store control points as (in, out) pairs in 2D space
/// Hodographs library expects Vector2 {x, y} format
static inline HodoBezierSegment bezier_segment_to_hodograph(const BezierSegment* seg) {
    HodoBezierSegment hodo_seg = {
        .order = 3, // Always cubic
        .p = {
            { .x = (float)seg->p0.in.v, .y = (float)seg->p0.out.v },
            { .x = (float)seg->p1.in.v, .y = (float)seg->p1.out.v },
            { .x = (float)seg->p2.in.v, .y = (float)seg->p2.out.v },
            { .x = (float)seg->p3.in.v, .y = (float)seg->p3.out.v }
        }
    };
    return hodo_seg;
}

/// Convert hodographs library HodoBezierSegment back to our format
static inline BezierSegment bezier_segment_from_hodograph(const HodoBezierSegment* hodo_seg) {
    BezierSegment seg = {
        .p0 = control_point_init((double)hodo_seg->p[0].x, (double)hodo_seg->p[0].y),
        .p1 = control_point_init((double)hodo_seg->p[1].x, (double)hodo_seg->p[1].y),
        .p2 = control_point_init((double)hodo_seg->p[2].x, (double)hodo_seg->p[2].y),
        .p3 = control_point_init((double)hodo_seg->p[3].x, (double)hodo_seg->p[3].y)
    };
    return seg;
}

//=============================================================================
// Critical Point Splitting
//=============================================================================

/// Split a Bezier segment at its critical points (inflections and extrema)
/// Returns a dynamically allocated array of segments and updates segment_count
/// Caller must free the returned array
static inline BezierSegment* bezier_segment_split_on_critical_points(
    const BezierSegment* seg,
    size_t* out_segment_count
) {
    // Convert to hodographs format
    HodoBezierSegment hodo_seg = bezier_segment_to_hodograph(seg);

    // Compute hodograph (derivative) and find roots
    HodoBezierSegment hodo = compute_hodograph(&hodo_seg);
    Vector2 roots = bezier_roots(&hodo);
    Vector2 inflections = inflection_points(&hodo_seg);

    // Collect all split points
    double split_points[4];
    size_t split_count = 0;

    // Add roots (extrema)
    if (roots.x >= 0.0f && roots.x <= 1.0f) {
        split_points[split_count++] = (double)roots.x;
    }
    if (roots.y >= 0.0f && roots.y <= 1.0f && roots.y != roots.x) {
        split_points[split_count++] = (double)roots.y;
    }

    // Add inflection points
    if (inflections.x >= 0.0f && inflections.x <= 1.0f) {
        // Check if not already added
        bool already_added = false;
        for (size_t i = 0; i < split_count; i++) {
            if (fabs(split_points[i] - (double)inflections.x) < CURVE_EPSILON) {
                already_added = true;
                break;
            }
        }
        if (!already_added) {
            split_points[split_count++] = (double)inflections.x;
        }
    }
    if (inflections.y >= 0.0f && inflections.y <= 1.0f && inflections.y != inflections.x) {
        // Check if not already added
        bool already_added = false;
        for (size_t i = 0; i < split_count; i++) {
            if (fabs(split_points[i] - (double)inflections.y) < CURVE_EPSILON) {
                already_added = true;
                break;
            }
        }
        if (!already_added) {
            split_points[split_count++] = (double)inflections.y;
        }
    }

    // If no critical points, return original segment
    if (split_count == 0) {
        *out_segment_count = 1;
        BezierSegment* result = (BezierSegment*)malloc(sizeof(BezierSegment));
        if (!result) {
            *out_segment_count = 0;
            return NULL;
        }
        result[0] = *seg;
        return result;
    }

    // Sort split points
    for (size_t i = 0; i < split_count - 1; i++) {
        for (size_t j = i + 1; j < split_count; j++) {
            if (split_points[j] < split_points[i]) {
                double temp = split_points[i];
                split_points[i] = split_points[j];
                split_points[j] = temp;
            }
        }
    }

    // Allocate result array (split_count + 1 segments)
    size_t num_segments = split_count + 1;
    BezierSegment* result = (BezierSegment*)malloc(num_segments * sizeof(BezierSegment));
    if (!result) {
        *out_segment_count = 0;
        return NULL;
    }

    // Split at each point
    BezierSegment current = *seg;
    for (size_t i = 0; i < split_count; i++) {
        BezierSegment left, right;
        if (!bezier_segment_split_at(&current, split_points[i], &left, &right)) {
            // Split failed, return what we have so far
            free(result);
            *out_segment_count = 0;
            return NULL;
        }
        result[i] = left;
        current = right;

        // Adjust remaining split points (they're relative to current segment now)
        for (size_t j = i + 1; j < split_count; j++) {
            split_points[j] = (split_points[j] - split_points[i]) / (1.0 - split_points[i]);
        }
    }
    result[split_count] = current;

    *out_segment_count = num_segments;
    return result;
}

//=============================================================================
// Linearization - Adaptive Subdivision
//=============================================================================

/// Check if a Bezier segment is approximately linear within tolerance
/// Based on control point deviation test
/// Returns true if the segment can be approximated as a straight line
static inline bool bezier_segment_is_approximately_linear(
    const BezierSegment* seg,
    double tolerance
) {
    // Based on: https://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.86.162&rep=rep1&type=pdf
    // Test if control points deviate significantly from line between endpoints
    
    // u = 3*p1 - 2*p0 - p3
    ControlPoint u = control_point_sub(
        control_point_sub(
            control_point_mul_scalar(seg->p1, 3.0),
            control_point_mul_scalar(seg->p0, 2.0)
        ),
        seg->p3
    );
    
    double ux = u.in.v * u.in.v;
    double uy = u.out.v * u.out.v;
    
    // v = 3*p2 - 2*p3 - p0
    ControlPoint v = control_point_sub(
        control_point_sub(
            control_point_mul_scalar(seg->p2, 3.0),
            control_point_mul_scalar(seg->p3, 2.0)
        ),
        seg->p0
    );
    
    double vx = v.in.v * v.in.v;
    double vy = v.out.v * v.out.v;
    
    // Take maximum deviation in each dimension
    if (ux < vx) {
        ux = vx;
    }
    if (uy < vy) {
        uy = vy;
    }
    
    // Check if sum of squared deviations is within tolerance
    return (ux + uy) <= tolerance;
}

/// Recursively linearize a Bezier segment with adaptive subdivision
/// Returns a dynamically allocated array of control points
/// Caller must free the returned array
/// 
/// The algorithm recursively splits the segment at u=0.5 until each subsegment
/// is approximately linear within the specified tolerance
static inline ControlPoint* bezier_segment_linearize(
    const BezierSegment* seg,
    double tolerance,
    size_t* out_point_count
) {
    // Check if segment is already approximately linear
    if (bezier_segment_is_approximately_linear(seg, tolerance)) {
        // Terminal case: just return the endpoints
        ControlPoint* result = (ControlPoint*)malloc(2 * sizeof(ControlPoint));
        if (!result) {
            *out_point_count = 0;
            return NULL;
        }
        result[0] = seg->p0;
        result[1] = seg->p3;
        *out_point_count = 2;
        return result;
    }
    
    // Recursive case: split at u=0.5 and linearize each half
    BezierSegment left, right;
    if (!bezier_segment_split_at(seg, 0.5, &left, &right)) {
        // Split failed
        *out_point_count = 0;
        return NULL;
    }
    
    // Linearize left half
    size_t left_count = 0;
    ControlPoint* left_points = bezier_segment_linearize(&left, tolerance, &left_count);
    if (!left_points) {
        *out_point_count = 0;
        return NULL;
    }
    
    // Linearize right half
    size_t right_count = 0;
    ControlPoint* right_points = bezier_segment_linearize(&right, tolerance, &right_count);
    if (!right_points) {
        free(left_points);
        *out_point_count = 0;
        return NULL;
    }
    
    // Combine results, skipping the first point of right (duplicates last of left)
    size_t total_count = left_count + (right_count - 1);
    ControlPoint* result = (ControlPoint*)malloc(total_count * sizeof(ControlPoint));
    if (!result) {
        free(left_points);
        free(right_points);
        *out_point_count = 0;
        return NULL;
    }
    
    // Copy left points
    for (size_t i = 0; i < left_count; i++) {
        result[i] = left_points[i];
    }
    
    // Copy right points (skip first, which duplicates last of left)
    for (size_t i = 1; i < right_count; i++) {
        result[left_count + i - 1] = right_points[i];
    }
    
    free(left_points);
    free(right_points);
    
    *out_point_count = total_count;
    return result;
}

/// Linearize an entire Bezier curve
/// Returns a LinearCurve_Monotonic with the linearized points
/// The curve is first split at critical points, then each segment is linearized
static inline bool bezier_curve_linearize(
    const BezierCurve* curve,
    double tolerance,
    LinearCurve_Monotonic* out_linear_curve
) {
    if (curve->segment_count == 0) {
        linear_curve_monotonic_init(out_linear_curve);
        return true;
    }
    
    // Collect all linearized points
    ControlPoint* all_points = NULL;
    size_t total_points = 0;
    size_t capacity = 0;
    
    for (size_t seg_idx = 0; seg_idx < curve->segment_count; seg_idx++) {
        const BezierSegment* seg = &curve->segments[seg_idx];
        
        // Split segment on critical points first
        size_t crit_seg_count = 0;
        BezierSegment* crit_segs = bezier_segment_split_on_critical_points(seg, &crit_seg_count);
        if (!crit_segs) {
            free(all_points);
            return false;
        }
        
        // Linearize each critical point segment
        for (size_t crit_idx = 0; crit_idx < crit_seg_count; crit_idx++) {
            size_t lin_count = 0;
            ControlPoint* lin_points = bezier_segment_linearize(
                &crit_segs[crit_idx],
                tolerance,
                &lin_count
            );
            
            if (!lin_points) {
                free(crit_segs);
                free(all_points);
                return false;
            }
            
            // Skip first point of interior segments (duplicates last of previous)
            size_t start_idx = (total_points > 0) ? 1 : 0;
            size_t points_to_add = lin_count - start_idx;
            
            // Ensure capacity
            if (total_points + points_to_add > capacity) {
                capacity = (capacity == 0) ? 16 : capacity * 2;
                while (total_points + points_to_add > capacity) {
                    capacity *= 2;
                }
                ControlPoint* new_points = (ControlPoint*)realloc(all_points, capacity * sizeof(ControlPoint));
                if (!new_points) {
                    free(lin_points);
                    free(crit_segs);
                    free(all_points);
                    return false;
                }
                all_points = new_points;
            }
            
            // Copy points
            for (size_t i = start_idx; i < lin_count; i++) {
                all_points[total_points++] = lin_points[i];
            }
            
            free(lin_points);
        }
        
        free(crit_segs);
    }
    
    // Create linear curve from collected points
    if (total_points == 0) {
        free(all_points);
        linear_curve_monotonic_init(out_linear_curve);
        return true;
    }
    
    bool success = linear_curve_monotonic_init_from_knots(out_linear_curve, all_points, total_points);
    free(all_points);

    return success;
}

//=============================================================================
// Projection & Transformation
//=============================================================================

/// Check if segment_to_project can be projected through this segment
/// Returns true if segment_to_project's output range is contained within this segment's input range
static inline bool bezier_segment_can_project(
    const BezierSegment* self,
    const BezierSegment* segment_to_project
) {
    // Get extents of both segments
    ControlPoint my_extents[2];
    bezier_segment_extents(self, my_extents);

    ControlPoint other_extents[2];
    bezier_segment_extents(segment_to_project, other_extents);

    // Check if other's output range is within my input range (with epsilon tolerance)
    Ordinate epsilon = ordinate_init(CURVE_EPSILON);

    bool min_in_range = ordinate_gteq(
        other_extents[0].out,
        ordinate_sub(my_extents[0].in, epsilon)
    );

    bool max_in_range = ordinate_lt(
        other_extents[1].out,
        ordinate_add(my_extents[1].in, epsilon)
    );

    return min_in_range && max_in_range;
}

/// Project segment_to_project through this segment
/// Assumes segment_to_project is contained by self (use can_project to verify)
/// For each control point: result.in = input, result.out = self.output_at_input(input.out)
static inline BezierSegment bezier_segment_project_segment(
    const BezierSegment* self,
    const BezierSegment* segment_to_project
) {
    BezierSegment result;

    // Project each control point
    // For each point: keep input coord, map output coord through self
    result.p0.in = segment_to_project->p0.in;
    result.p0.out = bezier_segment_output_at_input(self, segment_to_project->p0.out);

    result.p1.in = segment_to_project->p1.in;
    result.p1.out = bezier_segment_output_at_input(self, segment_to_project->p1.out);

    result.p2.in = segment_to_project->p2.in;
    result.p2.out = bezier_segment_output_at_input(self, segment_to_project->p2.out);

    result.p3.in = segment_to_project->p3.in;
    result.p3.out = bezier_segment_output_at_input(self, segment_to_project->p3.out);

    return result;
}

/// Project an affine transformation through a Bezier curve
/// Applies the affine transform to all input coordinates of all segments
/// Returns a new curve with transformed segments (caller must free with bezier_curve_deinit)
static inline bool bezier_curve_project_affine(
    const BezierCurve* self,
    AffineTransform1D transform,
    BezierCurve* out_curve
) {
    if (self->segment_count == 0) {
        bezier_curve_init(out_curve);
        return true;
    }

    // Allocate result segments
    BezierSegment* result_segments = (BezierSegment*)malloc(
        self->segment_count * sizeof(BezierSegment)
    );
    if (!result_segments) {
        return false;
    }

    // Copy segments and transform input coordinates
    for (size_t i = 0; i < self->segment_count; i++) {
        result_segments[i] = self->segments[i];

        // Apply affine transform to all input coordinates
        result_segments[i].p0.in = affine_transform_1d_applied_to_ordinate(
            transform,
            result_segments[i].p0.in
        );
        result_segments[i].p1.in = affine_transform_1d_applied_to_ordinate(
            transform,
            result_segments[i].p1.in
        );
        result_segments[i].p2.in = affine_transform_1d_applied_to_ordinate(
            transform,
            result_segments[i].p2.in
        );
        result_segments[i].p3.in = affine_transform_1d_applied_to_ordinate(
            transform,
            result_segments[i].p3.in
        );
    }

    out_curve->segments = result_segments;
    out_curve->segment_count = self->segment_count;
    return true;
}

/// Project a linear curve through a Bezier curve
/// First linearizes the Bezier curve, then projects the linear curve through it
/// Returns a new linear curve (caller must free with linear_curve_deinit)
///
/// NOTE: Commented out - requires linear_curve_monotonic_project_curve which is not yet ported
///
// static inline bool bezier_curve_project_linear_curve(
//     const BezierCurve* self,
//     const LinearCurve_Monotonic* other,
//     LinearCurve_Monotonic* out_curve
// ) {
//     // Linearize self first
//     LinearCurve_Monotonic self_linearized;
//     if (!bezier_curve_linearize(self, 0.01, &self_linearized)) {
//         return false;
//     }
//
//     // Project other through the linearized version of self
//     bool success = linear_curve_monotonic_project_curve(
//         &self_linearized,
//         other,
//         out_curve
//     );
//
//     linear_curve_monotonic_deinit(&self_linearized);
//     return success;
// }

//=============================================================================
// Trimming & Splitting Operations
//=============================================================================

/// Direction for trimming operations
typedef enum {
    TRIM_BEFORE,  // Keep everything after the ordinate
    TRIM_AFTER    // Keep everything before the ordinate
} TrimDirection;

/// Split a curve at a single input ordinate
/// Returns a new curve with one additional segment at the split point
/// Returns false if ordinate is out of bounds or on error
static inline bool bezier_curve_split_at_input_ordinate(
    const BezierCurve* self,
    Ordinate ordinate,
    BezierCurve* out_curve
) {
    // Find segment containing the ordinate
    size_t seg_index = bezier_curve_find_segment_index(self, ordinate);
    if (seg_index == (size_t)-1) {
        return false;  // Out of bounds
    }

    const BezierSegment* seg_to_split = &self->segments[seg_index];

    // Find u parameter for this ordinate
    double unorm = bezier_segment_findU_input(seg_to_split, ordinate);

    // If at boundary, just copy the curve
    if (unorm < CURVE_EPSILON || fabs(1.0 - unorm) < CURVE_EPSILON) {
        return bezier_curve_clone(self, out_curve);
    }

    // Split the segment
    BezierSegment left, right;
    if (!bezier_segment_split_at(seg_to_split, unorm, &left, &right)) {
        return false;
    }

    // Allocate new segments array (one more than original)
    BezierSegment* new_segments = (BezierSegment*)malloc(
        (self->segment_count + 1) * sizeof(BezierSegment)
    );
    if (!new_segments) {
        return false;
    }

    // Copy segments before split point
    for (size_t i = 0; i < seg_index; i++) {
        new_segments[i] = self->segments[i];
    }

    // Insert split segments
    new_segments[seg_index] = left;
    new_segments[seg_index + 1] = right;

    // Copy segments after split point
    for (size_t i = seg_index + 1; i < self->segment_count; i++) {
        new_segments[i + 1] = self->segments[i];
    }

    out_curve->segments = new_segments;
    out_curve->segment_count = self->segment_count + 1;
    return true;
}

/// Trim a curve from an input ordinate in the specified direction
/// TRIM_BEFORE: keeps everything after the ordinate
/// TRIM_AFTER: keeps everything before the ordinate
static inline bool bezier_curve_trimmed_from_input_ordinate(
    const BezierCurve* self,
    Ordinate ordinate,
    TrimDirection direction,
    BezierCurve* out_curve
) {
    // Check if ordinate is outside curve bounds
    ContinuousInterval extents;
    if (!bezier_curve_extents_input(self, &extents)) {
        bezier_curve_init(out_curve);
        return true;
    }

    // If trimming before and ordinate is at or before start, return copy
    if (direction == TRIM_BEFORE && ordinate_lteq(ordinate, extents.start)) {
        return bezier_curve_clone(self, out_curve);
    }

    // If trimming after and ordinate is at or after end, return copy
    if (direction == TRIM_AFTER && ordinate_gteq(ordinate, extents.end)) {
        return bezier_curve_clone(self, out_curve);
    }

    // Find segment containing the ordinate
    size_t seg_index = bezier_curve_find_segment_index(self, ordinate);
    if (seg_index == (size_t)-1) {
        return false;  // Out of bounds
    }

    const BezierSegment* seg_to_split = &self->segments[seg_index];

    // Check if ordinate is a boundary point
    if (ordinate_eql_approx(seg_to_split->p0.in, ordinate) ||
        ordinate_eql_approx(seg_to_split->p3.in, ordinate)) {
        return bezier_curve_clone(self, out_curve);
    }

    // Find u and split the segment
    double unorm = bezier_segment_findU_input(seg_to_split, ordinate);
    BezierSegment left, right;
    if (!bezier_segment_split_at(seg_to_split, unorm, &left, &right)) {
        bezier_curve_init(out_curve);
        return true;  // Empty curve
    }

    // Calculate how many segments we need
    size_t new_count;
    if (direction == TRIM_BEFORE) {
        // Keep right split + segments after
        new_count = 1 + (self->segment_count - seg_index - 1);
    } else {
        // Keep segments before + left split
        new_count = seg_index + 1;
    }

    // Allocate new segments
    BezierSegment* new_segments = (BezierSegment*)malloc(
        new_count * sizeof(BezierSegment)
    );
    if (!new_segments) {
        return false;
    }

    if (direction == TRIM_BEFORE) {
        // Keep right split segment
        new_segments[0] = right;
        // Copy segments after the split
        for (size_t i = seg_index + 1; i < self->segment_count; i++) {
            new_segments[i - seg_index] = self->segments[i];
        }
    } else {  // TRIM_AFTER
        // Copy segments before the split
        for (size_t i = 0; i < seg_index; i++) {
            new_segments[i] = self->segments[i];
        }
        // Keep left split segment
        new_segments[seg_index] = left;
    }

    out_curve->segments = new_segments;
    out_curve->segment_count = new_count;
    return true;
}

/// Trim a curve to fit within the specified input bounds
/// Returns a copy trimmed to fit within [bounds.start, bounds.end]
static inline bool bezier_curve_trimmed_in_input_space(
    const BezierCurve* self,
    ContinuousInterval bounds,
    BezierCurve* out_curve
) {
    // First trim from the front (keep everything after bounds.start)
    BezierCurve front_trimmed;
    if (!bezier_curve_trimmed_from_input_ordinate(
        self,
        bounds.start,
        TRIM_BEFORE,
        &front_trimmed
    )) {
        return false;
    }

    // Then trim from the back (keep everything before bounds.end)
    bool success = bezier_curve_trimmed_from_input_ordinate(
        &front_trimmed,
        bounds.end,
        TRIM_AFTER,
        out_curve
    );

    bezier_curve_deinit(&front_trimmed);
    return success;
}

/// Helper function to check if ordinate is between min and max
static inline bool _is_between(Ordinate ord, Ordinate min, Ordinate max) {
    return ordinate_gteq(ord, min) && ordinate_lteq(ord, max);
}

/// Split a curve at each input ordinate in the array
/// Returns a new curve with segments split at all specified ordinates
static inline bool bezier_curve_split_at_each_input_ordinate(
    const BezierCurve* self,
    const Ordinate* ordinates,
    size_t ordinate_count,
    BezierCurve* out_curve
) {
    if (ordinate_count == 0) {
        return bezier_curve_clone(self, out_curve);
    }

    // Start with a copy of the segments
    size_t capacity = self->segment_count * 2;  // Initial capacity estimate
    BezierSegment* result_segments = (BezierSegment*)malloc(
        capacity * sizeof(BezierSegment)
    );
    if (!result_segments) {
        return false;
    }

    size_t result_count = 0;
    for (size_t i = 0; i < self->segment_count; i++) {
        result_segments[result_count++] = self->segments[i];
    }

    // Process each segment
    size_t current_index = 0;
    while (current_index < result_count) {
        bool did_split = false;

        for (size_t ord_idx = 0; ord_idx < ordinate_count; ord_idx++) {
            Ordinate ordinate = ordinates[ord_idx];
            const BezierSegment* seg = &result_segments[current_index];

            // Get segment extents
            ControlPoint extents[2];
            bezier_segment_extents(seg, extents);

            // Check if ordinate is within this segment
            if (_is_between(ordinate, extents[0].in, extents[1].in)) {
                double u = bezier_segment_findU_input(seg, ordinate);

                // Only split if not at an endpoint
                if (u > 0.000001 && u < 1.0 - 0.000001) {
                    BezierSegment left, right;
                    if (!bezier_segment_split_at(seg, u, &left, &right)) {
                        continue;
                    }

                    // Ensure capacity
                    if (result_count + 1 >= capacity) {
                        capacity *= 2;
                        BezierSegment* new_segments = (BezierSegment*)realloc(
                            result_segments,
                            capacity * sizeof(BezierSegment)
                        );
                        if (!new_segments) {
                            free(result_segments);
                            return false;
                        }
                        result_segments = new_segments;
                    }

                    // Shift segments to make room
                    for (size_t i = result_count; i > current_index; i--) {
                        result_segments[i] = result_segments[i - 1];
                    }

                    // Insert split segments
                    result_segments[current_index] = left;
                    result_segments[current_index + 1] = right;
                    result_count++;

                    did_split = true;
                    break;  // Move to next segment after splitting
                }
            }
        }

        if (!did_split) {
            current_index++;
        }
    }

    // Trim to exact size
    if (result_count < capacity) {
        BezierSegment* trimmed = (BezierSegment*)realloc(
            result_segments,
            result_count * sizeof(BezierSegment)
        );
        if (trimmed) {
            result_segments = trimmed;
        }
    }

    out_curve->segments = result_segments;
    out_curve->segment_count = result_count;
    return true;
}
