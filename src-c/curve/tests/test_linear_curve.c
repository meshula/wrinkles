// test_linear_curve.c - Tests for linear curve functionality
// Ported from src/curve/linear_curve.zig tests

#include "../linear_curve.h"
#include "../../opentime/tests/test_harness.h"
#include <math.h>

TEST(linear_curve_init_deinit) {
    LinearCurve curve;
    linear_curve_init(&curve);
    EXPECT_EQ(0, curve.knot_count);
    EXPECT_TRUE(curve.knots == NULL);
    linear_curve_deinit(&curve);
}

TEST(linear_curve_init_from_knots) {
    ControlPoint knots[] = {
        control_point_init(0.0, 0.0),
        control_point_init(1.0, 2.0),
        control_point_init(2.0, 4.0)
    };

    LinearCurve curve;
    EXPECT_TRUE(linear_curve_init_from_knots(&curve, knots, 3));
    EXPECT_EQ(3, curve.knot_count);
    EXPECT_TRUE(curve.knots != NULL);

    // Verify knots were copied
    EXPECT_TRUE(ordinate_eql(curve.knots[0].in, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql(curve.knots[1].in, ordinate_init(1.0)));
    EXPECT_TRUE(ordinate_eql(curve.knots[2].in, ordinate_init(2.0)));

    linear_curve_deinit(&curve);
}

TEST(linear_curve_init_identity) {
    ContinuousInterval interval = {
        .start = ordinate_init(0.0),
        .end = ordinate_init(10.0)
    };

    LinearCurve curve;
    EXPECT_TRUE(linear_curve_init_identity(&curve, interval));
    EXPECT_EQ(2, curve.knot_count);

    // Identity: input == output
    EXPECT_TRUE(ordinate_eql(curve.knots[0].in, curve.knots[0].out));
    EXPECT_TRUE(ordinate_eql(curve.knots[1].in, curve.knots[1].out));

    linear_curve_deinit(&curve);
}

TEST(linear_curve_clone) {
    ControlPoint knots[] = {
        control_point_init(0.0, 0.0),
        control_point_init(1.0, 2.0)
    };

    LinearCurve original;
    EXPECT_TRUE(linear_curve_init_from_knots(&original, knots, 2));

    LinearCurve clone;
    EXPECT_TRUE(linear_curve_clone(&original, &clone));
    EXPECT_EQ(original.knot_count, clone.knot_count);
    EXPECT_TRUE(original.knots != clone.knots);  // Different memory

    // Verify values match
    EXPECT_TRUE(ordinate_eql(clone.knots[0].in, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql(clone.knots[1].in, ordinate_init(1.0)));

    linear_curve_deinit(&original);
    linear_curve_deinit(&clone);
}

TEST(linear_curve_monotonic_extents) {
    ControlPoint knots[] = {
        control_point_init(0.0, 0.0),
        control_point_init(1.0, 2.0),
        control_point_init(2.0, 4.0)
    };

    LinearCurve_Monotonic curve;
    EXPECT_TRUE(linear_curve_monotonic_init_from_knots(&curve, knots, 3));

    ControlPoint extents[2];
    EXPECT_TRUE(linear_curve_monotonic_extents(&curve, extents));

    // Min
    EXPECT_TRUE(ordinate_eql(extents[0].in, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql(extents[0].out, ordinate_init(0.0)));

    // Max
    EXPECT_TRUE(ordinate_eql(extents[1].in, ordinate_init(2.0)));
    EXPECT_TRUE(ordinate_eql(extents[1].out, ordinate_init(4.0)));

    linear_curve_monotonic_deinit(&curve);
}

TEST(linear_curve_monotonic_extents_input) {
    ControlPoint knots[] = {
        control_point_init(1.0, 0.0),
        control_point_init(5.0, 10.0)
    };

    LinearCurve_Monotonic curve;
    EXPECT_TRUE(linear_curve_monotonic_init_from_knots(&curve, knots, 2));

    ContinuousInterval interval;
    EXPECT_TRUE(linear_curve_monotonic_extents_input(&curve, &interval));

    EXPECT_TRUE(ordinate_eql(interval.start, ordinate_init(1.0)));
    EXPECT_TRUE(ordinate_eql(interval.end, ordinate_init(5.0)));

    linear_curve_monotonic_deinit(&curve);
}

TEST(linear_curve_monotonic_output_at_input) {
    // Create a curve: (0,0) -> (1,2) -> (2,4)
    ControlPoint knots[] = {
        control_point_init(0.0, 0.0),
        control_point_init(1.0, 2.0),
        control_point_init(2.0, 4.0)
    };

    LinearCurve_Monotonic curve;
    EXPECT_TRUE(linear_curve_monotonic_init_from_knots(&curve, knots, 3));

    // Test at knots
    Ordinate out0 = linear_curve_monotonic_output_at_input(&curve, ordinate_init(0.0));
    EXPECT_TRUE(ordinate_eql_approx(out0, ordinate_init(0.0)));

    Ordinate out1 = linear_curve_monotonic_output_at_input(&curve, ordinate_init(1.0));
    EXPECT_TRUE(ordinate_eql_approx(out1, ordinate_init(2.0)));

    // Test at midpoint
    Ordinate out_mid = linear_curve_monotonic_output_at_input(&curve, ordinate_init(0.5));
    EXPECT_TRUE(ordinate_eql_approx(out_mid, ordinate_init(1.0)));

    linear_curve_monotonic_deinit(&curve);
}

TEST(linear_curve_monotonic_input_at_output) {
    // Create a curve: (0,0) -> (1,2) -> (2,4)
    ControlPoint knots[] = {
        control_point_init(0.0, 0.0),
        control_point_init(1.0, 2.0),
        control_point_init(2.0, 4.0)
    };

    LinearCurve_Monotonic curve;
    EXPECT_TRUE(linear_curve_monotonic_init_from_knots(&curve, knots, 3));

    // Test inverse: output=2.0 should give input=1.0
    Ordinate in = linear_curve_monotonic_input_at_output(&curve, ordinate_init(2.0));
    EXPECT_TRUE(ordinate_eql_approx(in, ordinate_init(1.0)));

    // Test inverse at midpoint: output=1.0 should give input=0.5
    Ordinate in_mid = linear_curve_monotonic_input_at_output(&curve, ordinate_init(1.0));
    EXPECT_TRUE(ordinate_eql_approx(in_mid, ordinate_init(0.5)));

    linear_curve_monotonic_deinit(&curve);
}

OPENTIME_TEST_MAIN()
