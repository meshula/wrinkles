// test_bezier_math.c - Tests for bezier mathematics
// Ported from src/curve/bezier_math.zig tests

#include "../bezier_math.h"
#include "../../opentime/tests/test_harness.h"
#include <math.h>

TEST(bezier_math_output_at_input_between) {
    ControlPoint p0 = control_point_init(0.0, 0.0);
    ControlPoint p1 = control_point_init(1.0, 2.0);

    // At t=0.5, output should be 1.0
    Ordinate t = ordinate_init(0.5);
    Ordinate result = output_at_input_between(t, p0, p1);
    Ordinate expected = ordinate_init(1.0);

    EXPECT_TRUE(ordinate_eql(result, expected));
}

TEST(bezier_math_input_at_output_between) {
    ControlPoint p0 = control_point_init(0.0, 0.0);
    ControlPoint p1 = control_point_init(1.0, 2.0);

    // At v=1.0, input should be 0.5
    Ordinate v = ordinate_init(1.0);
    Ordinate result = input_at_output_between(v, p0, p1);
    Ordinate expected = ordinate_init(0.5);

    EXPECT_TRUE(ordinate_eql(result, expected));
}

TEST(bezier_math_segment_reduce4) {
    // Create a simple cubic segment
    BezierSegment seg = {
        .p0 = control_point_init(0.0, 0.0),
        .p1 = control_point_init(1.0, 1.0),
        .p2 = control_point_init(2.0, 2.0),
        .p3 = control_point_init(3.0, 3.0)
    };

    // Reduce at u=0.5
    Ordinate u = ordinate_init(0.5);
    BezierSegment result = bezier_segment_reduce4(u, seg);

    // p0 should be lerp(0.5, seg.p0, seg.p1) = (0.5, 0.5)
    EXPECT_TRUE(ordinate_eql_approx(result.p0.in, ordinate_init(0.5)));
    EXPECT_TRUE(ordinate_eql_approx(result.p0.out, ordinate_init(0.5)));

    // p1 should be lerp(0.5, seg.p1, seg.p2) = (1.5, 1.5)
    EXPECT_TRUE(ordinate_eql_approx(result.p1.in, ordinate_init(1.5)));
    EXPECT_TRUE(ordinate_eql_approx(result.p1.out, ordinate_init(1.5)));

    // p2 should be lerp(0.5, seg.p2, seg.p3) = (2.5, 2.5)
    EXPECT_TRUE(ordinate_eql_approx(result.p2.in, ordinate_init(2.5)));
    EXPECT_TRUE(ordinate_eql_approx(result.p2.out, ordinate_init(2.5)));
}

TEST(bezier_math_bezier0_evaluation) {
    // Test bezier0 with cubic case
    // For a cubic Bezier: p0=0, p1=0, p2=0, p3=1
    // B(u) = u³ (since p1=p2=0)
    Ordinate p1 = ordinate_init(0.0);
    Ordinate p2 = ordinate_init(0.0);
    Ordinate p3 = ordinate_init(1.0);

    Ordinate u = ordinate_init(0.5);
    Ordinate result = bezier_evaluate_bezier0(u, p1, p2, p3);

    // B(0.5) = 0.5³ = 0.125
    EXPECT_TRUE(ordinate_eql_approx(result, ordinate_init(0.125)));
}

TEST(bezier_math_actual_order_linear) {
    // Linear: all points on a line
    Ordinate p0 = ordinate_init(0.0);
    Ordinate p1 = ordinate_init(1.0);
    Ordinate p2 = ordinate_init(2.0);
    Ordinate p3 = ordinate_init(3.0);

    int order = bezier_actual_order(p0, p1, p2, p3);
    EXPECT_EQ(1, order);
}

TEST(bezier_math_actual_order_cubic) {
    // Cubic: S-curve shape
    Ordinate p0 = ordinate_init(0.0);
    Ordinate p1 = ordinate_init(0.0);
    Ordinate p2 = ordinate_init(1.0);
    Ordinate p3 = ordinate_init(1.0);

    int order = bezier_actual_order(p0, p1, p2, p3);
    EXPECT_EQ(3, order);
}

TEST(bezier_math_findU_simple) {
    // Test findU with a cubic curve: B(u) = u³
    Ordinate p1 = ordinate_init(0.0);
    Ordinate p2 = ordinate_init(0.0);
    Ordinate p3 = ordinate_init(1.0);

    // For B(u) = u³, if we want x = 0.125, u should be ∛0.125 = 0.5
    Ordinate x = ordinate_init(0.125);
    double u = bezier_find_u(x, p1, p2, p3);

    EXPECT_TRUE(fabs(u - 0.5) < 0.001);
}

TEST(bezier_math_findU_boundaries) {
    // Test boundary conditions
    Ordinate p1 = ordinate_init(0.0);
    Ordinate p2 = ordinate_init(0.5);
    Ordinate p3 = ordinate_init(1.0);

    // At x=0, u should be 0
    double u0 = bezier_find_u(ordinate_init(0.0), p1, p2, p3);
    EXPECT_TRUE(fabs(u0 - 0.0) < 0.001);

    // At x=1, u should be 1
    double u1 = bezier_find_u(ordinate_init(1.0), p1, p2, p3);
    EXPECT_TRUE(fabs(u1 - 1.0) < 0.001);
}

TEST(bezier_math_dual_segment_reduce4) {
    // Create a simple dual cubic segment
    BezierSegment_Dual seg = {
        .p0 = { .in = dual_ord_init_d(0.0), .out = dual_ord_init_d(0.0) },
        .p1 = { .in = dual_ord_init_d(1.0), .out = dual_ord_init_d(1.0) },
        .p2 = { .in = dual_ord_init_d(2.0), .out = dual_ord_init_d(2.0) },
        .p3 = { .in = dual_ord_init_d(3.0), .out = dual_ord_init_d(3.0) }
    };

    // Reduce at u=0.5 (with derivative = 1)
    Dual_Ord u = dual_ord_init_ri(ordinate_init(0.5), ordinate_init(1.0));
    BezierSegment_Dual result = bezier_segment_reduce4_dual(u, seg);

    // p0 should be lerp(0.5, seg.p0, seg.p1) = (0.5, 0.5) for real parts
    EXPECT_TRUE(ordinate_eql_approx(result.p0.in.r, ordinate_init(0.5)));
    EXPECT_TRUE(ordinate_eql_approx(result.p0.out.r, ordinate_init(0.5)));

    // Derivatives should be non-zero (automatic differentiation working)
    EXPECT_TRUE(!ordinate_eql(result.p0.in.i, ORDINATE_ZERO));
}

TEST(bezier_math_bezier0_dual_evaluation) {
    // Test dual bezier0 evaluation
    Ordinate p1 = ordinate_init(0.0);
    Ordinate p2 = ordinate_init(0.0);
    Ordinate p3 = ordinate_init(1.0);

    // u=0.5 with derivative = 1
    Dual_Ord u = dual_ord_init_ri(ordinate_init(0.5), ordinate_init(1.0));
    Dual_Ord result = bezier_evaluate_bezier0_dual(u, p1, p2, p3);

    // Real part: B(0.5) = 0.5³ = 0.125
    EXPECT_TRUE(ordinate_eql_approx(result.r, ordinate_init(0.125)));

    // Derivative should be non-zero (dB/du at u=0.5)
    // For B(u) = u³, dB/du = 3u² = 3*0.25 = 0.75
    EXPECT_TRUE(ordinate_eql_approx(result.i, ordinate_init(0.75)));
}

OPENTIME_TEST_MAIN()
