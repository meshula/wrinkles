// test_harness.h - Minimal C test framework for opentime
// Ported from LabDb9 C++ test harness to pure C
#pragma once

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdarg.h>

//-----------------------------------------------------------------------------
// Test Framework Macros
//-----------------------------------------------------------------------------
#define AXIOM(x, msg) \
    if (!(x)) { \
        fprintf(stderr, "FAILED: %s at %s:%d\n", msg, __FILE__, __LINE__); \
        exit(1); \
    }

#define TEST_START(name) \
    printf("\n=== Testing: %s ===\n", name);

#define TEST_SUCCESS(name) \
    printf("PASSED: %s\n", name);

#define TEST_SECTION(desc) \
    printf("  > %s\n", desc);

//-----------------------------------------------------------------------------
// Global test state
//-----------------------------------------------------------------------------
typedef struct {
    const char* current_test;
    bool current_test_passed;
    int tests_run;
    int tests_passed;
    int assertions_run;
    int assertions_passed;
    char** failures;
    size_t failure_count;
    size_t failure_capacity;
    int verbosity; // 0=minimal, 1=normal, 2=verbose
} TestState;

// Global test state instance
static TestState g_state = {0};

//-----------------------------------------------------------------------------
// Helper functions
//-----------------------------------------------------------------------------
static void add_failure(const char* msg) {
    if (g_state.failure_count >= g_state.failure_capacity) {
        size_t new_capacity = g_state.failure_capacity == 0 ? 16 : g_state.failure_capacity * 2;
        char** new_failures = (char**)realloc(g_state.failures, new_capacity * sizeof(char*));
        if (!new_failures) {
            fprintf(stderr, "Failed to allocate memory for test failures\n");
            exit(1);
        }
        g_state.failures = new_failures;
        g_state.failure_capacity = new_capacity;
    }
    g_state.failures[g_state.failure_count++] = strdup(msg);
}

//-----------------------------------------------------------------------------
// Core assertion macros
//-----------------------------------------------------------------------------
#define EXPECT_TRUE(condition) \
    do { \
        g_state.assertions_run++; \
        if (condition) { \
            g_state.assertions_passed++; \
        } else { \
            g_state.current_test_passed = false; \
            char buf[512]; \
            snprintf(buf, sizeof(buf), "%s: EXPECT_TRUE failed at %s:%d - %s", \
                     g_state.current_test, __FILE__, __LINE__, #condition); \
            add_failure(buf); \
            printf("  FAILED: %s (line %d)\n", #condition, __LINE__); \
        } \
    } while(0)

#define EXPECT_FALSE(condition) \
    do { \
        g_state.assertions_run++; \
        if (!(condition)) { \
            g_state.assertions_passed++; \
        } else { \
            g_state.current_test_passed = false; \
            char buf[512]; \
            snprintf(buf, sizeof(buf), "%s: EXPECT_FALSE failed at %s:%d - %s", \
                     g_state.current_test, __FILE__, __LINE__, #condition); \
            add_failure(buf); \
            printf("  FAILED: %s should be false (line %d)\n", #condition, __LINE__); \
        } \
    } while(0)

#define EXPECT_EQ(expected, actual) \
    do { \
        g_state.assertions_run++; \
        if ((expected) == (actual)) { \
            g_state.assertions_passed++; \
        } else { \
            g_state.current_test_passed = false; \
            char buf[512]; \
            snprintf(buf, sizeof(buf), "%s: EXPECT_EQ failed at %s:%d", \
                     g_state.current_test, __FILE__, __LINE__); \
            add_failure(buf); \
            printf("  FAILED: Expected != Actual (line %d)\n", __LINE__); \
        } \
    } while(0)

#define EXPECT_FLOAT_EQ(expected, actual, epsilon) \
    do { \
        g_state.assertions_run++; \
        double exp_val = (double)(expected); \
        double act_val = (double)(actual); \
        /* Handle special cases: both NaN, both +inf, both -inf */ \
        bool values_equal = false; \
        if (isnan(exp_val) && isnan(act_val)) { \
            values_equal = true; \
        } else if (isinf(exp_val) && isinf(act_val)) { \
            values_equal = (signbit(exp_val) == signbit(act_val)); \
        } else { \
            double diff = fabs(exp_val - act_val); \
            values_equal = (diff <= (epsilon)); \
        } \
        if (values_equal) { \
            g_state.assertions_passed++; \
        } else { \
            g_state.current_test_passed = false; \
            double diff = fabs(exp_val - act_val); \
            char buf[512]; \
            snprintf(buf, sizeof(buf), "%s: EXPECT_FLOAT_EQ failed at %s:%d - diff: %g > %g", \
                     g_state.current_test, __FILE__, __LINE__, diff, (double)(epsilon)); \
            add_failure(buf); \
            printf("  FAILED: Expected: %g, Got: %g, diff: %g > epsilon: %g (line %d)\n", \
                   exp_val, act_val, diff, (double)(epsilon), __LINE__); \
        } \
    } while(0)

#define EXPECT_GT(actual, threshold) \
    do { \
        g_state.assertions_run++; \
        if ((actual) > (threshold)) { \
            g_state.assertions_passed++; \
        } else { \
            g_state.current_test_passed = false; \
            char buf[512]; \
            snprintf(buf, sizeof(buf), "%s: EXPECT_GT failed at %s:%d", \
                     g_state.current_test, __FILE__, __LINE__); \
            add_failure(buf); \
            printf("  FAILED: Expected > threshold (line %d)\n", __LINE__); \
        } \
    } while(0)

#define EXPECT_LT(actual, threshold) \
    do { \
        g_state.assertions_run++; \
        if ((actual) < (threshold)) { \
            g_state.assertions_passed++; \
        } else { \
            g_state.current_test_passed = false; \
            char buf[512]; \
            snprintf(buf, sizeof(buf), "%s: EXPECT_LT failed at %s:%d", \
                     g_state.current_test, __FILE__, __LINE__); \
            add_failure(buf); \
            printf("  FAILED: Expected < threshold (line %d)\n", __LINE__); \
        } \
    } while(0)

#define EXPECT_LE(actual, threshold) \
    do { \
        g_state.assertions_run++; \
        if ((actual) <= (threshold)) { \
            g_state.assertions_passed++; \
        } else { \
            g_state.current_test_passed = false; \
            char buf[512]; \
            snprintf(buf, sizeof(buf), "%s: EXPECT_LE failed at %s:%d", \
                     g_state.current_test, __FILE__, __LINE__); \
            add_failure(buf); \
            printf("  FAILED: Expected <= threshold (line %d)\n", __LINE__); \
        } \
    } while(0)

//-----------------------------------------------------------------------------
// Test case structure
//-----------------------------------------------------------------------------
typedef void (*TestFunc)(void);

typedef struct {
    const char* name;
    TestFunc func;
} TestCase;

// Global test registry
static TestCase* g_tests = NULL;
static size_t g_test_count = 0;
static size_t g_test_capacity = 0;

//-----------------------------------------------------------------------------
// Test registration
//-----------------------------------------------------------------------------
static void register_test(const char* name, TestFunc func) {
    if (g_test_count >= g_test_capacity) {
        size_t new_capacity = g_test_capacity == 0 ? 16 : g_test_capacity * 2;
        TestCase* new_tests = (TestCase*)realloc(g_tests, new_capacity * sizeof(TestCase));
        if (!new_tests) {
            fprintf(stderr, "Failed to allocate memory for test registry\n");
            exit(1);
        }
        g_tests = new_tests;
        g_test_capacity = new_capacity;
    }
    g_tests[g_test_count].name = name;
    g_tests[g_test_count].func = func;
    g_test_count++;
}

#define TEST(test_name) \
    static void test_##test_name(void); \
    static void __attribute__((constructor)) register_##test_name(void) { \
        register_test(#test_name, test_##test_name); \
    } \
    static void test_##test_name(void)

//-----------------------------------------------------------------------------
// Test execution functions
//-----------------------------------------------------------------------------
static void run_test(const TestCase* test) {
    g_state.current_test = test->name;
    g_state.current_test_passed = true;
    g_state.tests_run++;

    printf("Running: %s\n", test->name);

    test->func();

    if (g_state.current_test_passed) {
        g_state.tests_passed++;
        printf("  PASSED\n");
    } else {
        printf("  FAILED\n");
    }

    printf("\n");
}

static int run_all_tests(void) {
    printf("OpenTime Test Runner - C Edition\n");
    printf("==================================\n\n");

    for (size_t i = 0; i < g_test_count; i++) {
        run_test(&g_tests[i]);
    }

    // Final report
    printf("Test Results:\n");
    printf("  Tests: %d/%d passed\n", g_state.tests_passed, g_state.tests_run);
    printf("  Assertions: %d/%d passed\n", g_state.assertions_passed, g_state.assertions_run);

    if (g_state.failure_count > 0) {
        printf("\nFailures:\n");
        for (size_t i = 0; i < g_state.failure_count; i++) {
            printf("  %s\n", g_state.failures[i]);
        }
    }

    bool all_passed = (g_state.tests_passed == g_state.tests_run);
    printf("\n%s\n", all_passed ? "ALL TESTS PASSED!" : "SOME TESTS FAILED");

    // Cleanup
    for (size_t i = 0; i < g_state.failure_count; i++) {
        free(g_state.failures[i]);
    }
    free(g_state.failures);
    free(g_tests);

    return all_passed ? 0 : 1;
}

// Main test runner macro
#define OPENTIME_TEST_MAIN() \
    int main(void) { \
        return run_all_tests(); \
    }
