// test_bezier_curve.c - Tests for Bezier curve functionality
// Ported from src/curve/bezier_curve.zig tests

#include "../bezier_curve.h"
#include "../../opentime/tests/test_harness.h"
#include <math.h>

TEST(bezier_segment_init_identity) {
    BezierSegment seg = bezier_segment_init_identity(
        ordinate_init(0.0),
        ordinate_init(1.0)
    );

    // Identity: input == output at all control points
    EXPECT_TRUE(ordinate_eql(seg.p0.in, seg.p0.out));
    EXPECT_TRUE(ordinate_eql(seg.p3.in, seg.p3.out));

    // Linear segment: p1 at 1/3, p2 at 2/3
    EXPECT_TRUE(ordinate_eql_approx(seg.p1.in, ordinate_init(1.0/3.0)));
    EXPECT_TRUE(ordinate_eql_approx(seg.p2.in, ordinate_init(2.0/3.0)));
}

TEST(bezier_segment_init_from_start_end) {
    ControlPoint start = control_point_init(0.0, 0.0);
    ControlPoint end = control_point_init(1.0, 2.0);

    BezierSegment seg = bezier_segment_init_from_start_end(start, end);

    // Verify endpoints
    EXPECT_TRUE(ordinate_eql(seg.p0.in, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql(seg.p0.out, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql(seg.p3.in, ordinate_init(1.0)));
    EXPECT_TRUE(ordinate_eql(seg.p3.out, ordinate_init(2.0)));

    // Linear segment: p1 and p2 on the line
    EXPECT_TRUE(ordinate_eql_approx(seg.p1.in, ordinate_init(1.0/3.0)));
    EXPECT_TRUE(ordinate_eql_approx(seg.p1.out, ordinate_init(2.0/3.0)));
}

TEST(bezier_segment_eval_at_identity) {
    // Identity segment [0,1] -> [0,1]
    BezierSegment seg = bezier_segment_init_identity(
        ordinate_init(0.0),
        ordinate_init(1.0)
    );

    // Evaluate at u=0.5
    ControlPoint result = bezier_segment_eval_at(&seg, ordinate_init(0.5));

    // For identity, expect 0.5 -> 0.5
    EXPECT_TRUE(ordinate_eql_approx(result.in, ordinate_init(0.5)));
    EXPECT_TRUE(ordinate_eql_approx(result.out, ordinate_init(0.5)));
}

TEST(bezier_segment_eval_at_boundaries) {
    ControlPoint start = control_point_init(0.0, 0.0);
    ControlPoint end = control_point_init(1.0, 2.0);
    BezierSegment seg = bezier_segment_init_from_start_end(start, end);

    // At u=0, should return p0
    ControlPoint result0 = bezier_segment_eval_at(&seg, ordinate_init(0.0));
    EXPECT_TRUE(ordinate_eql_approx(result0.in, seg.p0.in));
    EXPECT_TRUE(ordinate_eql_approx(result0.out, seg.p0.out));

    // At u=1, should return p3
    ControlPoint result1 = bezier_segment_eval_at(&seg, ordinate_init(1.0));
    EXPECT_TRUE(ordinate_eql_approx(result1.in, seg.p3.in));
    EXPECT_TRUE(ordinate_eql_approx(result1.out, seg.p3.out));
}

TEST(bezier_segment_eval_at_linear) {
    // Linear segment: (0,0) -> (1,2)
    ControlPoint start = control_point_init(0.0, 0.0);
    ControlPoint end = control_point_init(1.0, 2.0);
    BezierSegment seg = bezier_segment_init_from_start_end(start, end);

    // At u=0.5, expect (0.5, 1.0) for linear
    ControlPoint result = bezier_segment_eval_at(&seg, ordinate_init(0.5));
    EXPECT_TRUE(ordinate_eql_approx(result.in, ordinate_init(0.5)));
    EXPECT_TRUE(ordinate_eql_approx(result.out, ordinate_init(1.0)));
}

TEST(bezier_segment_eval_at_dual) {
    // Identity segment [0,1] -> [0,1]
    BezierSegment seg = bezier_segment_init_identity(
        ordinate_init(0.0),
        ordinate_init(1.0)
    );

    // Evaluate at u=0.5 with derivative = 1.0
    Dual_Ord u = dual_ord_init_ri(ordinate_init(0.5), ordinate_init(1.0));
    Dual_CP result = bezier_segment_eval_at_dual(&seg, u);

    // Real part should be 0.5
    EXPECT_TRUE(ordinate_eql_approx(result.in.r, ordinate_init(0.5)));
    EXPECT_TRUE(ordinate_eql_approx(result.out.r, ordinate_init(0.5)));

    // Derivative should be non-zero (automatic differentiation working)
    EXPECT_TRUE(!ordinate_eql(result.in.i, ORDINATE_ZERO));
}

TEST(bezier_segment_findU_input_identity) {
    BezierSegment seg = bezier_segment_init_identity(
        ordinate_init(0.0),
        ordinate_init(1.0)
    );

    // For identity linear segment, findU should return the input value
    double u = bezier_segment_findU_input(&seg, ordinate_init(0.5));
    EXPECT_TRUE(fabs(u - 0.5) < 0.01);

    // At boundaries
    double u0 = bezier_segment_findU_input(&seg, ordinate_init(0.0));
    EXPECT_TRUE(fabs(u0 - 0.0) < 0.01);

    double u1 = bezier_segment_findU_input(&seg, ordinate_init(1.0));
    EXPECT_TRUE(fabs(u1 - 1.0) < 0.01);
}

TEST(bezier_segment_findU_output_linear) {
    // Linear segment: (0,0) -> (1,2)
    ControlPoint start = control_point_init(0.0, 0.0);
    ControlPoint end = control_point_init(1.0, 2.0);
    BezierSegment seg = bezier_segment_init_from_start_end(start, end);

    // Find u where output = 1.0
    // For linear (0,0)->(1,2), output=1.0 should be at u=0.5
    double u = bezier_segment_findU_output(&seg, ordinate_init(1.0));
    EXPECT_TRUE(fabs(u - 0.5) < 0.01);
}

TEST(bezier_segment_split_at) {
    BezierSegment seg = bezier_segment_init_identity(
        ordinate_init(0.0),
        ordinate_init(1.0)
    );

    BezierSegment left, right;
    bool success = bezier_segment_split_at(&seg, 0.5, &left, &right);

    EXPECT_TRUE(success);

    // Left segment should go from 0 to 0.5
    EXPECT_TRUE(ordinate_eql_approx(left.p0.in, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql_approx(left.p3.in, ordinate_init(0.5)));

    // Right segment should go from 0.5 to 1.0
    EXPECT_TRUE(ordinate_eql_approx(right.p0.in, ordinate_init(0.5)));
    EXPECT_TRUE(ordinate_eql_approx(right.p3.in, ordinate_init(1.0)));

    // The split point should match
    EXPECT_TRUE(ordinate_eql_approx(left.p3.in, right.p0.in));
    EXPECT_TRUE(ordinate_eql_approx(left.p3.out, right.p0.out));
}

TEST(bezier_segment_split_at_boundaries) {
    BezierSegment seg = bezier_segment_init_identity(
        ordinate_init(0.0),
        ordinate_init(1.0)
    );

    BezierSegment left, right;

    // Split at value < epsilon should fail
    bool success_low = bezier_segment_split_at(&seg, 0.000001, &left, &right);
    EXPECT_FALSE(success_low);

    // Split at >= 1.0 should fail
    bool success_high = bezier_segment_split_at(&seg, 1.0, &left, &right);
    EXPECT_FALSE(success_high);

    // Valid split at 0.25
    bool success_valid = bezier_segment_split_at(&seg, 0.25, &left, &right);
    EXPECT_TRUE(success_valid);
}

TEST(bezier_segment_extents) {
    ControlPoint start = control_point_init(0.0, 1.0);
    ControlPoint end = control_point_init(2.0, 3.0);
    BezierSegment seg = bezier_segment_init_from_start_end(start, end);

    ControlPoint extents[2];
    bezier_segment_extents(&seg, extents);

    // Min extents
    EXPECT_TRUE(ordinate_eql(extents[0].in, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql(extents[0].out, ordinate_init(1.0)));

    // Max extents
    EXPECT_TRUE(ordinate_eql(extents[1].in, ordinate_init(2.0)));
    EXPECT_TRUE(ordinate_eql(extents[1].out, ordinate_init(3.0)));
}

TEST(bezier_curve_init_deinit) {
    BezierCurve curve;
    bezier_curve_init(&curve);
    EXPECT_EQ(0, curve.segment_count);
    EXPECT_TRUE(curve.segments == NULL);
    bezier_curve_deinit(&curve);
}

TEST(bezier_curve_init_from_segments) {
    BezierSegment segments[] = {
        bezier_segment_init_identity(ordinate_init(0.0), ordinate_init(1.0)),
        bezier_segment_init_identity(ordinate_init(1.0), ordinate_init(2.0))
    };

    BezierCurve curve;
    EXPECT_TRUE(bezier_curve_init_from_segments(&curve, segments, 2));
    EXPECT_EQ(2, curve.segment_count);
    EXPECT_TRUE(curve.segments != NULL);

    // Verify segments were copied
    EXPECT_TRUE(ordinate_eql(curve.segments[0].p0.in, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql(curve.segments[1].p0.in, ordinate_init(1.0)));

    bezier_curve_deinit(&curve);
}

TEST(bezier_curve_clone) {
    BezierSegment segments[] = {
        bezier_segment_init_identity(ordinate_init(0.0), ordinate_init(1.0))
    };

    BezierCurve original;
    EXPECT_TRUE(bezier_curve_init_from_segments(&original, segments, 1));

    BezierCurve clone;
    EXPECT_TRUE(bezier_curve_clone(&original, &clone));
    EXPECT_EQ(original.segment_count, clone.segment_count);
    EXPECT_TRUE(original.segments != clone.segments);  // Different memory

    bezier_curve_deinit(&original);
    bezier_curve_deinit(&clone);
}

TEST(bezier_curve_find_segment_index) {
    BezierSegment segments[] = {
        bezier_segment_init_identity(ordinate_init(0.0), ordinate_init(1.0)),
        bezier_segment_init_identity(ordinate_init(1.0), ordinate_init(2.0)),
        bezier_segment_init_identity(ordinate_init(2.0), ordinate_init(3.0))
    };

    BezierCurve curve;
    EXPECT_TRUE(bezier_curve_init_from_segments(&curve, segments, 3));

    // Find segments
    EXPECT_EQ(0, bezier_curve_find_segment_index(&curve, ordinate_init(0.5)));
    EXPECT_EQ(1, bezier_curve_find_segment_index(&curve, ordinate_init(1.5)));
    EXPECT_EQ(2, bezier_curve_find_segment_index(&curve, ordinate_init(2.5)));

    // Out of range
    size_t not_found = bezier_curve_find_segment_index(&curve, ordinate_init(10.0));
    EXPECT_EQ((size_t)-1, not_found);

    bezier_curve_deinit(&curve);
}

TEST(bezier_curve_output_at_input) {
    // Create a curve with one identity segment [0,1] -> [0,1]
    BezierSegment segments[] = {
        bezier_segment_init_identity(ordinate_init(0.0), ordinate_init(1.0))
    };

    BezierCurve curve;
    EXPECT_TRUE(bezier_curve_init_from_segments(&curve, segments, 1));

    // For identity, input = output
    Ordinate out = bezier_curve_output_at_input(&curve, ordinate_init(0.5));
    EXPECT_TRUE(ordinate_eql_approx(out, ordinate_init(0.5)));

    bezier_curve_deinit(&curve);
}

TEST(bezier_curve_extents_input) {
    BezierSegment segments[] = {
        bezier_segment_init_identity(ordinate_init(0.0), ordinate_init(1.0)),
        bezier_segment_init_identity(ordinate_init(1.0), ordinate_init(3.0))
    };

    BezierCurve curve;
    EXPECT_TRUE(bezier_curve_init_from_segments(&curve, segments, 2));

    ContinuousInterval interval;
    EXPECT_TRUE(bezier_curve_extents_input(&curve, &interval));

    EXPECT_TRUE(ordinate_eql(interval.start, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql(interval.end, ordinate_init(3.0)));

    bezier_curve_deinit(&curve);
}

TEST(bezier_curve_extents_output) {
    // Non-identity segments with different output ranges
    ControlPoint start1 = control_point_init(0.0, 2.0);
    ControlPoint end1 = control_point_init(1.0, 5.0);
    BezierSegment segments[] = {
        bezier_segment_init_from_start_end(start1, end1)
    };

    BezierCurve curve;
    EXPECT_TRUE(bezier_curve_init_from_segments(&curve, segments, 1));

    ContinuousInterval interval;
    EXPECT_TRUE(bezier_curve_extents_output(&curve, &interval));

    EXPECT_TRUE(ordinate_eql(interval.start, ordinate_init(2.0)));
    EXPECT_TRUE(ordinate_eql(interval.end, ordinate_init(5.0)));

    bezier_curve_deinit(&curve);
}

TEST(bezier_segment_to_hodograph_conversion) {
    // Create an identity segment
    BezierSegment seg = bezier_segment_init_identity(
        ordinate_init(0.0),
        ordinate_init(1.0)
    );

    // Convert to hodograph format
    HodoBezierSegment hodo_seg = bezier_segment_to_hodograph(&seg);

    // Check conversion
    EXPECT_EQ(3, hodo_seg.order);
    EXPECT_TRUE(fabsf(hodo_seg.p[0].x - 0.0f) < 0.001f);
    EXPECT_TRUE(fabsf(hodo_seg.p[0].y - 0.0f) < 0.001f);
    EXPECT_TRUE(fabsf(hodo_seg.p[3].x - 1.0f) < 0.001f);
    EXPECT_TRUE(fabsf(hodo_seg.p[3].y - 1.0f) < 0.001f);

    // Convert back
    BezierSegment seg_back = bezier_segment_from_hodograph(&hodo_seg);

    // Check round-trip
    EXPECT_TRUE(ordinate_eql_approx(seg_back.p0.in, seg.p0.in));
    EXPECT_TRUE(ordinate_eql_approx(seg_back.p0.out, seg.p0.out));
    EXPECT_TRUE(ordinate_eql_approx(seg_back.p3.in, seg.p3.in));
    EXPECT_TRUE(ordinate_eql_approx(seg_back.p3.out, seg.p3.out));
}

TEST(bezier_segment_split_on_critical_points_linear) {
    // Linear segment should not split
    BezierSegment seg = bezier_segment_init_identity(
        ordinate_init(0.0),
        ordinate_init(1.0)
    );

    size_t count = 0;
    BezierSegment* segments = bezier_segment_split_on_critical_points(&seg, &count);

    EXPECT_TRUE(segments != NULL);
    EXPECT_EQ(1, count); // Linear should not split

    free(segments);
}

TEST(bezier_segment_split_on_critical_points_scurve) {
    // S-curve with inflection point at u~0.5
    // This curve goes from (0,0) to (1,1) with control points creating an S shape
    BezierSegment seg = bezier_segment_init(
        0.0, 0.0,  // p0
        0.0, 1.0,  // p1 - pulls up
        1.0, 0.0,  // p2 - pulls down
        1.0, 1.0   // p3
    );

    size_t count = 0;
    BezierSegment* segments = bezier_segment_split_on_critical_points(&seg, &count);

    EXPECT_TRUE(segments != NULL);
    // S-curve should have at least one inflection point, so count > 1
    EXPECT_TRUE(count > 1);

    // Verify segments are connected
    for (size_t i = 0; i < count - 1; i++) {
        EXPECT_TRUE(ordinate_eql_approx(segments[i].p3.in, segments[i+1].p0.in));
        EXPECT_TRUE(ordinate_eql_approx(segments[i].p3.out, segments[i+1].p0.out));
    }

    // Verify endpoints are preserved
    EXPECT_TRUE(ordinate_eql_approx(segments[0].p0.in, seg.p0.in));
    EXPECT_TRUE(ordinate_eql_approx(segments[0].p0.out, seg.p0.out));
    EXPECT_TRUE(ordinate_eql_approx(segments[count-1].p3.in, seg.p3.in));
    EXPECT_TRUE(ordinate_eql_approx(segments[count-1].p3.out, seg.p3.out));

    free(segments);
}

TEST(bezier_segment_split_on_critical_points_upsidedown_u) {
    // Upside-down U shape with extrema
    BezierSegment seg = bezier_segment_init(
        0.0, 0.0,    // p0
        0.333, 1.0,  // p1 - pulls up
        0.666, 1.0,  // p2 - pulls up
        1.0, 0.0     // p3
    );

    size_t count = 0;
    BezierSegment* segments = bezier_segment_split_on_critical_points(&seg, &count);

    EXPECT_TRUE(segments != NULL);
    // Should have extrema, so count > 1
    EXPECT_TRUE(count > 1);

    free(segments);
}

TEST(bezier_segment_is_approximately_linear_identity) {
    // Identity segment is perfectly linear
    BezierSegment seg = bezier_segment_init_identity(
        ordinate_init(0.0),
        ordinate_init(1.0)
    );

    EXPECT_TRUE(bezier_segment_is_approximately_linear(&seg, 0.01));
    EXPECT_TRUE(bezier_segment_is_approximately_linear(&seg, 0.000001));
}

TEST(bezier_segment_is_approximately_linear_scurve) {
    // S-curve is NOT linear
    BezierSegment seg = bezier_segment_init(
        0.0, 0.0,  // p0
        0.0, 1.0,  // p1
        1.0, 0.0,  // p2
        1.0, 1.0   // p3
    );

    // Should NOT be linear even with loose tolerance
    EXPECT_FALSE(bezier_segment_is_approximately_linear(&seg, 0.01));
}

TEST(bezier_segment_linearize_identity) {
    // Identity segment should linearize to just endpoints
    BezierSegment seg = bezier_segment_init_identity(
        ordinate_init(0.0),
        ordinate_init(1.0)
    );

    size_t count = 0;
    ControlPoint* points = bezier_segment_linearize(&seg, 0.01, &count);

    EXPECT_TRUE(points != NULL);
    EXPECT_EQ(2, count);  // Just start and end

    // Verify endpoints
    EXPECT_TRUE(ordinate_eql_approx(points[0].in, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql_approx(points[0].out, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql_approx(points[1].in, ordinate_init(1.0)));
    EXPECT_TRUE(ordinate_eql_approx(points[1].out, ordinate_init(1.0)));

    free(points);
}

TEST(bezier_segment_linearize_scurve_coarse) {
    // S-curve with coarse tolerance
    BezierSegment seg = bezier_segment_init(
        0.0, 0.0,
        0.0, 1.0,
        1.0, 0.0,
        1.0, 1.0
    );

    size_t count = 0;
    ControlPoint* points = bezier_segment_linearize(&seg, 0.1, &count);

    EXPECT_TRUE(points != NULL);
    EXPECT_TRUE(count > 2);  // Should need some subdivision

    // Verify endpoints are preserved
    EXPECT_TRUE(ordinate_eql_approx(points[0].in, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql_approx(points[0].out, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql_approx(points[count-1].in, ordinate_init(1.0)));
    EXPECT_TRUE(ordinate_eql_approx(points[count-1].out, ordinate_init(1.0)));

    free(points);
}

TEST(bezier_segment_linearize_scurve_fine) {
    // S-curve with fine tolerance should need more points
    BezierSegment seg = bezier_segment_init(
        0.0, 0.0,
        0.0, 1.0,
        1.0, 0.0,
        1.0, 1.0
    );

    size_t coarse_count = 0;
    ControlPoint* coarse_points = bezier_segment_linearize(&seg, 0.1, &coarse_count);

    size_t fine_count = 0;
    ControlPoint* fine_points = bezier_segment_linearize(&seg, 0.01, &fine_count);

    EXPECT_TRUE(coarse_points != NULL);
    EXPECT_TRUE(fine_points != NULL);

    // Finer tolerance should produce more points
    EXPECT_TRUE(fine_count >= coarse_count);

    free(coarse_points);
    free(fine_points);
}

TEST(bezier_curve_linearize_empty) {
    // Empty curve should linearize to empty
    BezierCurve curve;
    bezier_curve_init(&curve);

    LinearCurve_Monotonic linear;
    EXPECT_TRUE(bezier_curve_linearize(&curve, 0.01, &linear));
    EXPECT_EQ(0, linear.knot_count);

    linear_curve_monotonic_deinit(&linear);
    bezier_curve_deinit(&curve);
}

TEST(bezier_curve_linearize_single_segment) {
    // Single identity segment
    BezierSegment segments[] = {
        bezier_segment_init_identity(ordinate_init(0.0), ordinate_init(1.0))
    };

    BezierCurve curve;
    EXPECT_TRUE(bezier_curve_init_from_segments(&curve, segments, 1));

    LinearCurve_Monotonic linear;
    EXPECT_TRUE(bezier_curve_linearize(&curve, 0.01, &linear));

    EXPECT_TRUE(linear.knot_count >= 2);  // At least start and end

    // Verify extents
    EXPECT_TRUE(ordinate_eql_approx(linear.knots[0].in, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql_approx(linear.knots[linear.knot_count-1].in, ordinate_init(1.0)));

    linear_curve_monotonic_deinit(&linear);
    bezier_curve_deinit(&curve);
}

TEST(bezier_curve_linearize_multi_segment) {
    // Multiple segments
    BezierSegment segments[] = {
        bezier_segment_init_identity(ordinate_init(0.0), ordinate_init(1.0)),
        bezier_segment_init_identity(ordinate_init(1.0), ordinate_init(2.0))
    };

    BezierCurve curve;
    EXPECT_TRUE(bezier_curve_init_from_segments(&curve, segments, 2));

    LinearCurve_Monotonic linear;
    EXPECT_TRUE(bezier_curve_linearize(&curve, 0.01, &linear));

    EXPECT_TRUE(linear.knot_count >= 3);  // At least start, middle, end

    // Verify endpoints
    EXPECT_TRUE(ordinate_eql_approx(linear.knots[0].in, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql_approx(linear.knots[linear.knot_count-1].in, ordinate_init(2.0)));

    // Verify knots are in increasing order (monotonic)
    for (size_t i = 1; i < linear.knot_count; i++) {
        EXPECT_TRUE(ordinate_gteq(linear.knots[i].in, linear.knots[i-1].in));
    }

    linear_curve_monotonic_deinit(&linear);
    bezier_curve_deinit(&curve);
}

TEST(bezier_segment_can_project) {
    // half: maps [-0.5, 0.5] input to [-0.25, 0.25] output
    ControlPoint half_start = control_point_init(-0.5, -0.25);
    ControlPoint half_end = control_point_init(0.5, 0.25);
    BezierSegment half = bezier_segment_init_from_start_end(half_start, half_end);

    // double: maps [-0.5, 0.5] input to [-1, 1] output
    ControlPoint double_start = control_point_init(-0.5, -1.0);
    ControlPoint double_end = control_point_init(0.5, 1.0);
    BezierSegment double_seg = bezier_segment_init_from_start_end(double_start, double_end);

    // double can project half (half's output [-0.25, 0.25] is within double's input [-0.5, 0.5])
    EXPECT_TRUE(bezier_segment_can_project(&double_seg, &half));

    // half cannot project double (double's output [-1, 1] exceeds half's input [-0.5, 0.5])
    EXPECT_FALSE(bezier_segment_can_project(&half, &double_seg));
}

TEST(bezier_segment_project_segment) {
    // half: maps [-0.5, 0.5] input to [-0.25, 0.25] output
    ControlPoint half_start = control_point_init(-0.5, -0.25);
    ControlPoint half_end = control_point_init(0.5, 0.25);
    BezierSegment half = bezier_segment_init_from_start_end(half_start, half_end);

    // double: maps [-0.5, 0.5] input to [-1, 1] output
    ControlPoint double_start = control_point_init(-0.5, -1.0);
    ControlPoint double_end = control_point_init(0.5, 1.0);
    BezierSegment double_seg = bezier_segment_init_from_start_end(double_start, double_end);

    // Project half through double
    BezierSegment result = bezier_segment_project_segment(&double_seg, &half);

    // Test a few points along the projected segment
    for (int i = 0; i <= 100; i++) {
        double u = i / 100.0;
        ControlPoint pt = bezier_segment_eval_at(&result, ordinate_init(u));

        // At u=0, input=-0.5, and the composition should give u-0.5 = -0.5
        // At u=1, input=0.5, and the composition should give u-0.5 = 0.5
        double expected = u - 0.5;
        EXPECT_TRUE(fabs(pt.out.v - expected) < 0.01);
    }
}

TEST(bezier_segment_output_at_input) {
    // Identity segment [0,1] -> [0,1]
    BezierSegment seg = bezier_segment_init_identity(
        ordinate_init(0.0),
        ordinate_init(1.0)
    );

    // Test output at various inputs
    Ordinate out_0 = bezier_segment_output_at_input(&seg, ordinate_init(0.0));
    EXPECT_TRUE(ordinate_eql_approx(out_0, ordinate_init(0.0)));

    Ordinate out_05 = bezier_segment_output_at_input(&seg, ordinate_init(0.5));
    EXPECT_TRUE(ordinate_eql_approx(out_05, ordinate_init(0.5)));

    Ordinate out_1 = bezier_segment_output_at_input(&seg, ordinate_init(1.0));
    EXPECT_TRUE(ordinate_eql_approx(out_1, ordinate_init(1.0)));
}

TEST(bezier_curve_project_affine_identity) {
    // Create a simple curve
    BezierSegment segments[] = {
        bezier_segment_init_identity(ordinate_init(0.0), ordinate_init(1.0))
    };

    BezierCurve curve;
    EXPECT_TRUE(bezier_curve_init_from_segments(&curve, segments, 1));

    // Identity transform (offset=0, scale=1)
    AffineTransform1D identity = {
        .offset = ordinate_init(0.0),
        .scale = ordinate_init(1.0)
    };

    BezierCurve result;
    EXPECT_TRUE(bezier_curve_project_affine(&curve, identity, &result));

    // Segment count should be unchanged
    EXPECT_EQ(curve.segment_count, result.segment_count);

    // For identity transform, input coordinates should be unchanged
    EXPECT_TRUE(ordinate_eql_approx(result.segments[0].p0.in, curve.segments[0].p0.in));
    EXPECT_TRUE(ordinate_eql_approx(result.segments[0].p3.in, curve.segments[0].p3.in));

    bezier_curve_deinit(&curve);
    bezier_curve_deinit(&result);
}

TEST(bezier_curve_project_affine_scale) {
    // Create a curve [0,1] -> [0,1]
    BezierSegment segments[] = {
        bezier_segment_init_identity(ordinate_init(0.0), ordinate_init(1.0))
    };

    BezierCurve curve;
    EXPECT_TRUE(bezier_curve_init_from_segments(&curve, segments, 1));

    // Scale by 2
    AffineTransform1D scale = {
        .offset = ordinate_init(0.0),
        .scale = ordinate_init(2.0)
    };

    BezierCurve result;
    EXPECT_TRUE(bezier_curve_project_affine(&curve, scale, &result));

    // Input coordinates should be scaled
    EXPECT_TRUE(ordinate_eql_approx(result.segments[0].p0.in, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql_approx(result.segments[0].p3.in, ordinate_init(2.0)));

    // Output coordinates should be unchanged
    EXPECT_TRUE(ordinate_eql_approx(result.segments[0].p0.out, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql_approx(result.segments[0].p3.out, ordinate_init(1.0)));

    bezier_curve_deinit(&curve);
    bezier_curve_deinit(&result);
}

TEST(bezier_curve_project_affine_offset) {
    // Create a curve [0,1] -> [0,1]
    BezierSegment segments[] = {
        bezier_segment_init_identity(ordinate_init(0.0), ordinate_init(1.0))
    };

    BezierCurve curve;
    EXPECT_TRUE(bezier_curve_init_from_segments(&curve, segments, 1));

    // Offset by 10
    AffineTransform1D offset = {
        .offset = ordinate_init(10.0),
        .scale = ordinate_init(1.0)
    };

    BezierCurve result;
    EXPECT_TRUE(bezier_curve_project_affine(&curve, offset, &result));

    // Input coordinates should be offset
    EXPECT_TRUE(ordinate_eql_approx(result.segments[0].p0.in, ordinate_init(10.0)));
    EXPECT_TRUE(ordinate_eql_approx(result.segments[0].p3.in, ordinate_init(11.0)));

    bezier_curve_deinit(&curve);
    bezier_curve_deinit(&result);
}

TEST(bezier_curve_split_at_input_ordinate) {
    // Create curve with 2 segments: [0,1] and [1,2]
    BezierSegment segments[] = {
        bezier_segment_init_identity(ordinate_init(0.0), ordinate_init(1.0)),
        bezier_segment_init_identity(ordinate_init(1.0), ordinate_init(2.0))
    };

    BezierCurve curve;
    EXPECT_TRUE(bezier_curve_init_from_segments(&curve, segments, 2));

    // Split at 0.5 (in first segment)
    BezierCurve result;
    EXPECT_TRUE(bezier_curve_split_at_input_ordinate(&curve, ordinate_init(0.5), &result));

    // Should have 3 segments now (split first segment)
    EXPECT_EQ(3, result.segment_count);

    // Verify extents are preserved
    ContinuousInterval orig_ext, result_ext;
    EXPECT_TRUE(bezier_curve_extents_input(&curve, &orig_ext));
    EXPECT_TRUE(bezier_curve_extents_input(&result, &result_ext));
    EXPECT_TRUE(ordinate_eql_approx(orig_ext.start, result_ext.start));
    EXPECT_TRUE(ordinate_eql_approx(orig_ext.end, result_ext.end));

    bezier_curve_deinit(&curve);
    bezier_curve_deinit(&result);
}

TEST(bezier_curve_trimmed_from_input_ordinate_before) {
    // Create identity curve [0,2]
    BezierSegment segments[] = {
        bezier_segment_init_identity(ordinate_init(0.0), ordinate_init(2.0))
    };

    BezierCurve curve;
    EXPECT_TRUE(bezier_curve_init_from_segments(&curve, segments, 1));

    // Trim before 1.0 (keep [1.0, 2.0])
    BezierCurve result;
    EXPECT_TRUE(bezier_curve_trimmed_from_input_ordinate(
        &curve,
        ordinate_init(1.0),
        TRIM_BEFORE,
        &result
    ));

    // Check extents
    ContinuousInterval ext;
    EXPECT_TRUE(bezier_curve_extents_input(&result, &ext));
    EXPECT_TRUE(ordinate_eql_approx(ext.start, ordinate_init(1.0)));
    EXPECT_TRUE(ordinate_eql_approx(ext.end, ordinate_init(2.0)));

    bezier_curve_deinit(&curve);
    bezier_curve_deinit(&result);
}

TEST(bezier_curve_trimmed_from_input_ordinate_after) {
    // Create identity curve [0,2]
    BezierSegment segments[] = {
        bezier_segment_init_identity(ordinate_init(0.0), ordinate_init(2.0))
    };

    BezierCurve curve;
    EXPECT_TRUE(bezier_curve_init_from_segments(&curve, segments, 1));

    // Trim after 1.0 (keep [0.0, 1.0])
    BezierCurve result;
    EXPECT_TRUE(bezier_curve_trimmed_from_input_ordinate(
        &curve,
        ordinate_init(1.0),
        TRIM_AFTER,
        &result
    ));

    // Check extents
    ContinuousInterval ext;
    EXPECT_TRUE(bezier_curve_extents_input(&result, &ext));
    EXPECT_TRUE(ordinate_eql_approx(ext.start, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql_approx(ext.end, ordinate_init(1.0)));

    bezier_curve_deinit(&curve);
    bezier_curve_deinit(&result);
}

TEST(bezier_curve_trimmed_in_input_space) {
    // Create identity curve [0,3]
    BezierSegment segments[] = {
        bezier_segment_init_identity(ordinate_init(0.0), ordinate_init(3.0))
    };

    BezierCurve curve;
    EXPECT_TRUE(bezier_curve_init_from_segments(&curve, segments, 1));

    // Trim to [0.5, 2.5]
    ContinuousInterval bounds = {
        .start = ordinate_init(0.5),
        .end = ordinate_init(2.5)
    };

    BezierCurve result;
    EXPECT_TRUE(bezier_curve_trimmed_in_input_space(&curve, bounds, &result));

    // Check extents
    ContinuousInterval ext;
    EXPECT_TRUE(bezier_curve_extents_input(&result, &ext));
    EXPECT_TRUE(ordinate_eql_approx(ext.start, ordinate_init(0.5)));
    EXPECT_TRUE(ordinate_eql_approx(ext.end, ordinate_init(2.5)));

    bezier_curve_deinit(&curve);
    bezier_curve_deinit(&result);
}

TEST(bezier_curve_split_at_each_input_ordinate) {
    // Create identity curve [0,3]
    BezierSegment segments[] = {
        bezier_segment_init_identity(ordinate_init(0.0), ordinate_init(3.0))
    };

    BezierCurve curve;
    EXPECT_TRUE(bezier_curve_init_from_segments(&curve, segments, 1));

    // Split at 1.0 and 2.0
    Ordinate split_points[] = {
        ordinate_init(1.0),
        ordinate_init(2.0)
    };

    BezierCurve result;
    EXPECT_TRUE(bezier_curve_split_at_each_input_ordinate(&curve, split_points, 2, &result));

    // Should have 3 segments now
    EXPECT_EQ(3, result.segment_count);

    // Verify extents are preserved
    ContinuousInterval orig_ext, result_ext;
    EXPECT_TRUE(bezier_curve_extents_input(&curve, &orig_ext));
    EXPECT_TRUE(bezier_curve_extents_input(&result, &result_ext));
    EXPECT_TRUE(ordinate_eql_approx(orig_ext.start, result_ext.start));
    EXPECT_TRUE(ordinate_eql_approx(orig_ext.end, result_ext.end));

    bezier_curve_deinit(&curve);
    bezier_curve_deinit(&result);
}

OPENTIME_TEST_MAIN()
