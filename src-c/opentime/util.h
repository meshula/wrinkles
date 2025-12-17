// util.h - Utility functions and constants for opentime
// Ported from src/opentime/util.zig

#pragma once

#include <stdbool.h>

// Test precision constant
#define OPENTIME_EPSILON_F 1.0e-4

// Skip test helper (returns error code for skipped tests)
static inline bool skip_test(void) {
    return true;  // In C, we just return true to skip
}
