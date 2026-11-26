// projection_result.h - ProjectionResult implementation
// Ported from src/opentime/projection_result.zig

#pragma once

#include <stdbool.h>
#include "ordinate.h"
#include "interval.h"

// Enum for projection result type
typedef enum {
    PROJECTION_RESULT_SUCCESS_ORDINATE,
    PROJECTION_RESULT_SUCCESS_INTERVAL,
    PROJECTION_RESULT_OUT_OF_BOUNDS
} ProjectionResultType;

// Union containing the result of a projection
typedef struct {
    ProjectionResultType type;
    union {
        Ordinate ordinate;
        ContinuousInterval interval;
    } data;
} ProjectionResult;

//-----------------------------------------------------------------------------
// Construction
//-----------------------------------------------------------------------------

// Create success result with ordinate
static inline ProjectionResult projection_result_success_ordinate(Ordinate ord) {
    ProjectionResult result;
    result.type = PROJECTION_RESULT_SUCCESS_ORDINATE;
    result.data.ordinate = ord;
    return result;
}

// Create success result with interval
static inline ProjectionResult projection_result_success_interval(ContinuousInterval interval) {
    ProjectionResult result;
    result.type = PROJECTION_RESULT_SUCCESS_INTERVAL;
    result.data.interval = interval;
    return result;
}

// Create out of bounds result
static inline ProjectionResult projection_result_out_of_bounds(void) {
    ProjectionResult result;
    result.type = PROJECTION_RESULT_OUT_OF_BOUNDS;
    return result;
}

//-----------------------------------------------------------------------------
// Access methods
//-----------------------------------------------------------------------------

// Fetch ordinate result, returns true if successful
static inline bool projection_result_ordinate(ProjectionResult self, Ordinate* out) {
    if (self.type == PROJECTION_RESULT_SUCCESS_ORDINATE) {
        *out = self.data.ordinate;
        return true;
    }
    return false;
}

// Fetch interval result, returns true if successful
static inline bool projection_result_interval(ProjectionResult self, ContinuousInterval* out) {
    if (self.type == PROJECTION_RESULT_SUCCESS_INTERVAL) {
        *out = self.data.interval;
        return true;
    }
    return false;
}

// Check if result is out of bounds
static inline bool projection_result_is_out_of_bounds(ProjectionResult self) {
    return self.type == PROJECTION_RESULT_OUT_OF_BOUNDS;
}
