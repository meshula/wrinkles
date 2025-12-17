// test_control_point.c - Tests for control point functionality
// Ported from src/curve/control_point.zig tests

#include "../control_point.h"
#include "../../opentime/tests/test_harness.h"
#include <math.h>

// Helper to check control point equality (uses EXPECT_TRUE from test harness)
#define expect_control_point_equal(lhs, rhs, test_name) \
    EXPECT_TRUE(control_point_equal(lhs, rhs))

TEST(control_point_add) {
    ControlPoint cp1 = control_point_init(0.0, 10.0);
    ControlPoint cp2 = control_point_init(20.0, -10.0);
    ControlPoint expected = control_point_init(20.0, 0.0);

    ControlPoint result = control_point_add(cp1, cp2);
    expect_control_point_equal(result, expected, "control_point_add");
}

TEST(control_point_sub) {
    ControlPoint cp1 = control_point_init(0.0, 10.0);
    ControlPoint cp2 = control_point_init(20.0, -10.0);
    ControlPoint expected = control_point_init(-20.0, 20.0);

    ControlPoint result = control_point_sub(cp1, cp2);
    expect_control_point_equal(result, expected, "control_point_sub");
}

TEST(control_point_mul) {
    ControlPoint cp1 = control_point_init(0.0, 10.0);
    double scale = -10.0;
    ControlPoint expected = control_point_init(0.0, -100.0);

    ControlPoint result = control_point_mul_scalar(cp1, scale);
    expect_control_point_equal(result, expected, "control_point_mul");
}

TEST(control_point_distance_345_triangle) {
    // 3-4-5 right triangle test
    ControlPoint a = control_point_init(3.0, -3.0);
    ControlPoint b = control_point_init(6.0, 1.0);

    Ordinate dist = control_point_distance(a, b);
    Ordinate expected = ordinate_init(5.0);

    EXPECT_TRUE(ordinate_eql(dist, expected));
}

TEST(control_point_constants) {
    ControlPoint zero = control_point_zero();
    ControlPoint one = control_point_one();

    EXPECT_TRUE(ordinate_eql(zero.in, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql(zero.out, ordinate_init(0.0)));
    EXPECT_TRUE(ordinate_eql(one.in, ordinate_init(1.0)));
    EXPECT_TRUE(ordinate_eql(one.out, ordinate_init(1.0)));
}

OPENTIME_TEST_MAIN()
