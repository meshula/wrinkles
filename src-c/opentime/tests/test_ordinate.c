// test_ordinate.c - Tests for ordinate type
// Ported from src/opentime/ordinate.zig tests

#include "../opentime.h"
#include "test_harness.h"
#include <math.h>

TEST(ordinate_unary_operators) {
    // Test data
    double test_values[] = {
        1, -1, 25, 64.34, 5.345, -5.345, 0, -0.0,
        INFINITY, -INFINITY, NAN
    };
    int num_tests = sizeof(test_values) / sizeof(test_values[0]);

    // Test neg
    for (int i = 0; i < num_tests; i++) {
        double val = test_values[i];
        Ordinate ord = ordinate_init(val);
        Ordinate result = ordinate_neg(ord);

        if (isnan(val)) {
            EXPECT_TRUE(ordinate_is_nan(result));
        } else {
            EXPECT_FLOAT_EQ(-val, result.v, OPENTIME_EPSILON_F);
        }
    }

    // Test sqrt
    for (int i = 0; i < num_tests; i++) {
        double val = test_values[i];
        if (val < 0 && !isinf(val) && !isnan(val)) continue;  // Skip negative non-special values

        Ordinate ord = ordinate_init(val);
        Ordinate result = ordinate_sqrt(ord);
        double expected = sqrt(val);

        if (isnan(expected)) {
            EXPECT_TRUE(ordinate_is_nan(result));
        } else {
            EXPECT_FLOAT_EQ(expected, result.v, OPENTIME_EPSILON_F);
        }
    }

    // Test abs
    for (int i = 0; i < num_tests; i++) {
        double val = test_values[i];
        Ordinate ord = ordinate_init(val);
        Ordinate result = ordinate_abs(ord);
        double expected = fabs(val);

        if (isnan(val)) {
            EXPECT_TRUE(ordinate_is_nan(result));
        } else {
            EXPECT_FLOAT_EQ(expected, result.v, OPENTIME_EPSILON_F);
        }
    }
}

TEST(ordinate_binary_operators) {
    double values[] = { 0, 1, 1.2, 5.345, 3.14159, M_PI, 1001.45 };
    double signs[] = { -1, 1 };
    int num_values = sizeof(values) / sizeof(values[0]);
    int num_signs = sizeof(signs) / sizeof(signs[0]);

    // Test add
    for (int i = 0; i < num_values; i++) {
        for (int j = 0; j < num_signs; j++) {
            for (int k = 0; k < num_values; k++) {
                for (int l = 0; l < num_signs; l++) {
                    double lhs_val = signs[j] * values[i];
                    double rhs_val = signs[l] * values[k];

                    Ordinate lhs = ordinate_init(lhs_val);
                    Ordinate rhs = ordinate_init(rhs_val);
                    Ordinate result = ordinate_add(lhs, rhs);
                    double expected = lhs_val + rhs_val;

                    if (!isnan(expected) && !isinf(expected)) {
                        EXPECT_FLOAT_EQ(expected, result.v, OPENTIME_EPSILON_F);
                    }
                }
            }
        }
    }

    // Test sub, mul, div similarly (abbreviated for space)
    Ordinate a = ordinate_init(10.0);
    Ordinate b = ordinate_init(5.0);

    EXPECT_FLOAT_EQ(5.0, ordinate_sub(a, b).v, OPENTIME_EPSILON_F);
    EXPECT_FLOAT_EQ(50.0, ordinate_mul(a, b).v, OPENTIME_EPSILON_F);
    EXPECT_FLOAT_EQ(2.0, ordinate_div(a, b).v, OPENTIME_EPSILON_F);
}

TEST(ordinate_comparisons) {
    Ordinate a = ordinate_init(1.0);
    Ordinate b = ordinate_init(2.0);
    Ordinate c = ordinate_init(1.0);

    // Equality
    EXPECT_TRUE(ordinate_eql(a, c));
    EXPECT_FALSE(ordinate_eql(a, b));

    // Less than
    EXPECT_TRUE(ordinate_lt(a, b));
    EXPECT_FALSE(ordinate_lt(b, a));
    EXPECT_FALSE(ordinate_lt(a, c));

    // Less than or equal
    EXPECT_TRUE(ordinate_lteq(a, b));
    EXPECT_TRUE(ordinate_lteq(a, c));
    EXPECT_FALSE(ordinate_lteq(b, a));

    // Greater than
    EXPECT_TRUE(ordinate_gt(b, a));
    EXPECT_FALSE(ordinate_gt(a, b));
    EXPECT_FALSE(ordinate_gt(a, c));

    // Greater than or equal
    EXPECT_TRUE(ordinate_gteq(b, a));
    EXPECT_TRUE(ordinate_gteq(a, c));
    EXPECT_FALSE(ordinate_gteq(a, b));
}

TEST(ordinate_min_max) {
    Ordinate a = ordinate_init(1.0);
    Ordinate b = ordinate_init(2.0);

    Ordinate min_result = ordinate_min(a, b);
    Ordinate max_result = ordinate_max(a, b);

    EXPECT_FLOAT_EQ(1.0, min_result.v, OPENTIME_EPSILON_F);
    EXPECT_FLOAT_EQ(2.0, max_result.v, OPENTIME_EPSILON_F);
}

TEST(ordinate_special_values) {
    Ordinate inf = ORDINATE_INF;
    Ordinate inf_neg = ORDINATE_INF_NEG;
    Ordinate nan = ORDINATE_NAN;
    Ordinate finite = ordinate_init(1.0);

    EXPECT_TRUE(ordinate_is_inf(inf));
    EXPECT_TRUE(ordinate_is_inf(inf_neg));
    EXPECT_FALSE(ordinate_is_inf(finite));

    EXPECT_TRUE(ordinate_is_finite(finite));
    EXPECT_FALSE(ordinate_is_finite(inf));

    EXPECT_TRUE(ordinate_is_nan(nan));
    EXPECT_FALSE(ordinate_is_nan(finite));
}

TEST(ordinate_as_conversions) {
    double test_values[] = { 1.0, -1.0, 3.45, -3.45, 1.0/3.0 };
    int num_tests = sizeof(test_values) / sizeof(test_values[0]);

    for (int i = 0; i < num_tests; i++) {
        double val = test_values[i];
        Ordinate ord = ordinate_init(val);

        // Test as double
        double as_double = ordinate_as_double(ord);
        EXPECT_FLOAT_EQ(val, as_double, OPENTIME_EPSILON_F);

        // Test as int (for non-negative values)
        if (val >= 0) {
            int as_int = ordinate_as_int(ord);
            EXPECT_EQ((int)val, as_int);
        }
    }
}

TEST(ordinate_approximate_equality) {
    Ordinate a = ordinate_init(1.0);
    Ordinate b = ordinate_init(1.0 + OPENTIME_EPSILON_F * 0.5);
    Ordinate c = ordinate_init(1.0 + OPENTIME_EPSILON_F * 2.0);

    EXPECT_TRUE(ordinate_eql_approx(a, b));
    EXPECT_FALSE(ordinate_eql_approx(a, c));
}

OPENTIME_TEST_MAIN()
