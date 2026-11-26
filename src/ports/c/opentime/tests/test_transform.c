// test_transform.c - Tests for affine transform type
// Ported from src/opentime/transform.zig tests

#include "../opentime.h"
#include "test_harness.h"

TEST(transform_offset) {
    ContinuousInterval cti = continuous_interval_init((ContinuousInterval_InnerType){ .start = 10, .end = 20 });

    AffineTransform1D xform = {
        .offset = ordinate_init(10),
        .scale = ordinate_init(1)
    };

    ContinuousInterval result = affine_transform_1d_applied_to_interval(xform, cti);

    EXPECT_FLOAT_EQ(20.0, result.start.v, OPENTIME_EPSILON_F);
    EXPECT_FLOAT_EQ(30.0, result.end.v, OPENTIME_EPSILON_F);

    Ordinate result_duration = continuous_interval_duration(result);
    EXPECT_FLOAT_EQ(10.0, result_duration.v, OPENTIME_EPSILON_F);

    Ordinate cti_duration = continuous_interval_duration(cti);
    EXPECT_FLOAT_EQ(cti_duration.v, result_duration.v, OPENTIME_EPSILON_F);

    // Test transform on transform
    AffineTransform1D result_xform = affine_transform_1d_applied_to_transform(xform, xform);
    EXPECT_FLOAT_EQ(20.0, result_xform.offset.v, OPENTIME_EPSILON_F);
    EXPECT_FLOAT_EQ(1.0, result_xform.scale.v, OPENTIME_EPSILON_F);
}

TEST(transform_scale) {
    ContinuousInterval cti = continuous_interval_init((ContinuousInterval_InnerType){ .start = 10, .end = 20 });

    AffineTransform1D xform = {
        .offset = ordinate_init(10),
        .scale = ordinate_init(2)
    };

    ContinuousInterval result = affine_transform_1d_applied_to_interval(xform, cti);

    EXPECT_FLOAT_EQ(30.0, result.start.v, OPENTIME_EPSILON_F);
    EXPECT_FLOAT_EQ(50.0, result.end.v, OPENTIME_EPSILON_F);

    Ordinate result_duration = continuous_interval_duration(result);
    Ordinate cti_duration = continuous_interval_duration(cti);
    Ordinate expected_duration = ordinate_mul(cti_duration, xform.scale);

    EXPECT_FLOAT_EQ(expected_duration.v, result_duration.v, OPENTIME_EPSILON_F);

    // Test transform on transform
    AffineTransform1D result_xform = affine_transform_1d_applied_to_transform(xform, xform);
    EXPECT_FLOAT_EQ(30.0, result_xform.offset.v, OPENTIME_EPSILON_F);
    EXPECT_FLOAT_EQ(4.0, result_xform.scale.v, OPENTIME_EPSILON_F);
}

TEST(transform_invert) {
    AffineTransform1D xform = {
        .offset = ordinate_init(10),
        .scale = ordinate_init(2)
    };

    EXPECT_FALSE(ordinate_eql_d(xform.scale, 0));

    AffineTransform1D inverted = affine_transform_1d_inverted(xform);
    EXPECT_FALSE(ordinate_eql_d(inverted.scale, 0));

    // Test that xform * inverted = identity
    AffineTransform1D identity = affine_transform_1d_applied_to_transform(xform, inverted);

    EXPECT_FLOAT_EQ(0.0, identity.offset.v, OPENTIME_EPSILON_F);
    EXPECT_FLOAT_EQ(1.0, identity.scale.v, OPENTIME_EPSILON_F);

    // Test roundtrip through transform
    Ordinate pt = ordinate_init(10);
    Ordinate transformed = affine_transform_1d_applied_to_ordinate(xform, pt);
    Ordinate roundtrip = affine_transform_1d_applied_to_ordinate(inverted, transformed);

    EXPECT_FLOAT_EQ(pt.v, roundtrip.v, OPENTIME_EPSILON_F);
}

TEST(transform_applied_to_bounds) {
    AffineTransform1D xform = {
        .offset = ordinate_init(10),
        .scale = ordinate_init(-1)
    };

    ContinuousInterval bounds = {
        .start = ordinate_init(10),
        .end = ordinate_init(20)
    };

    ContinuousInterval result = affine_transform_1d_applied_to_bounds(xform, bounds);

    // Even with negative scale, start should be < end
    EXPECT_TRUE(ordinate_lt(result.start, result.end));
}

OPENTIME_TEST_MAIN()
