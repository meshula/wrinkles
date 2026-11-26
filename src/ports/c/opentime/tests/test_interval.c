// test_interval.c - Tests for continuous interval type
// Ported from src/opentime/interval.zig tests

#include "../opentime.h"
#include "test_harness.h"

TEST(interval_basic_operations) {
    ContinuousInterval ival = continuous_interval_init((ContinuousInterval_InnerType){ .start = 10, .end = 20 });

    // Test duration
    Ordinate duration = continuous_interval_duration(ival);
    EXPECT_FLOAT_EQ(10.0, duration.v, OPENTIME_EPSILON_F);

    // Test from_start_duration roundtrip
    ContinuousInterval ival2 = continuous_interval_from_start_duration(ival.start, duration);
    EXPECT_FLOAT_EQ(ival.start.v, ival2.start.v, OPENTIME_EPSILON_F);
    EXPECT_FLOAT_EQ(ival.end.v, ival2.end.v, OPENTIME_EPSILON_F);
}

TEST(interval_overlaps) {
    ContinuousInterval ival = continuous_interval_init((ContinuousInterval_InnerType){ .start = 10, .end = 20 });

    EXPECT_FALSE(continuous_interval_overlaps(ival, ordinate_init(0)));
    EXPECT_TRUE(continuous_interval_overlaps(ival, ordinate_init(10)));   // start is inclusive
    EXPECT_TRUE(continuous_interval_overlaps(ival, ordinate_init(15)));
    EXPECT_FALSE(continuous_interval_overlaps(ival, ordinate_init(20)));  // end is exclusive
    EXPECT_FALSE(continuous_interval_overlaps(ival, ordinate_init(30)));
}

TEST(interval_is_instant) {
    ContinuousInterval not_instant = continuous_interval_init((ContinuousInterval_InnerType){ .start = 0, .end = 0.1 });
    EXPECT_FALSE(continuous_interval_is_instant(not_instant));

    ContinuousInterval instant = continuous_interval_init((ContinuousInterval_InnerType){ .start = 10, .end = 10 });
    EXPECT_TRUE(continuous_interval_is_instant(instant));
}

TEST(interval_is_infinite) {
    ContinuousInterval infinite = CONTINUOUS_INTERVAL_ZERO_TO_INF_POS;
    EXPECT_TRUE(continuous_interval_is_infinite(infinite));

    ContinuousInterval finite = continuous_interval_init((ContinuousInterval_InnerType){ .start = 0, .end = 2 });
    EXPECT_FALSE(continuous_interval_is_infinite(finite));

    infinite.start = ordinate_init(0);
    infinite.end = ordinate_init(2);
    EXPECT_FALSE(continuous_interval_is_infinite(infinite));

    infinite.start = ORDINATE_INF_NEG;
    EXPECT_TRUE(continuous_interval_is_infinite(infinite));

    finite.start = ORDINATE_NAN;
    finite.end = ORDINATE_ONE;
    EXPECT_FALSE(continuous_interval_is_infinite(finite));
}

TEST(interval_extend) {
    ContinuousInterval fst = continuous_interval_init((ContinuousInterval_InnerType){ .start = 0, .end = 10 });
    ContinuousInterval snd = continuous_interval_init((ContinuousInterval_InnerType){ .start = 8, .end = 12 });

    ContinuousInterval result = continuous_interval_extend(fst, snd);

    EXPECT_FLOAT_EQ(0.0, result.start.v, OPENTIME_EPSILON_F);
    EXPECT_FLOAT_EQ(12.0, result.end.v, OPENTIME_EPSILON_F);

    // Test with gap
    fst = continuous_interval_init((ContinuousInterval_InnerType){ .start = 0, .end = 2 });
    snd = continuous_interval_init((ContinuousInterval_InnerType){ .start = 4, .end = 12 });
    result = continuous_interval_extend(fst, snd);

    EXPECT_FLOAT_EQ(0.0, result.start.v, OPENTIME_EPSILON_F);
    EXPECT_FLOAT_EQ(12.0, result.end.v, OPENTIME_EPSILON_F);
}

TEST(interval_any_overlap) {
    ContinuousInterval fst = continuous_interval_init((ContinuousInterval_InnerType){ .start = 0, .end = 10 });
    ContinuousInterval snd = continuous_interval_init((ContinuousInterval_InnerType){ .start = 8, .end = 12 });
    EXPECT_TRUE(continuous_interval_any_overlap(fst, snd));

    snd = continuous_interval_init((ContinuousInterval_InnerType){ .start = -2, .end = 9 });
    EXPECT_TRUE(continuous_interval_any_overlap(fst, snd));

    snd = continuous_interval_init((ContinuousInterval_InnerType){ .start = -2, .end = 12 });
    EXPECT_TRUE(continuous_interval_any_overlap(fst, snd));

    fst = continuous_interval_init((ContinuousInterval_InnerType){ .start = 0, .end = 4 });
    snd = continuous_interval_init((ContinuousInterval_InnerType){ .start = 5, .end = 12 });
    EXPECT_FALSE(continuous_interval_any_overlap(fst, snd));

    fst = continuous_interval_init((ContinuousInterval_InnerType){ .start = 0, .end = 4 });
    snd = continuous_interval_init((ContinuousInterval_InnerType){ .start = -2, .end = 0 });
    EXPECT_FALSE(continuous_interval_any_overlap(fst, snd));
}

TEST(interval_intersect) {
    ContinuousInterval fst = continuous_interval_init((ContinuousInterval_InnerType){ .start = 0, .end = 10 });
    ContinuousInterval snd = continuous_interval_init((ContinuousInterval_InnerType){ .start = 1, .end = 3 });
    ContinuousInterval result;

    EXPECT_TRUE(continuous_interval_intersect(fst, snd, &result));
    EXPECT_FLOAT_EQ(snd.start.v, result.start.v, OPENTIME_EPSILON_F);
    EXPECT_FLOAT_EQ(snd.end.v, result.end.v, OPENTIME_EPSILON_F);

    // Test with infinite interval
    fst = CONTINUOUS_INTERVAL_INF_NEG_TO_POS;
    snd = continuous_interval_init((ContinuousInterval_InnerType){ .start = 1, .end = 3 });
    EXPECT_TRUE(continuous_interval_intersect(fst, snd, &result));
    EXPECT_FLOAT_EQ(snd.start.v, result.start.v, OPENTIME_EPSILON_F);
    EXPECT_FLOAT_EQ(snd.end.v, result.end.v, OPENTIME_EPSILON_F);
}

OPENTIME_TEST_MAIN()
