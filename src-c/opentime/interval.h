// interval.h - Continuous Interval definition/implementation
// Ported from src/opentime/interval.zig

#pragma once

#include <stdbool.h>
#include <assert.h>
#include "ordinate.h"

// Right-open interval in a continuous metric space: [start, end)
typedef struct {
    Ordinate start;  // Start ordinate (inclusive)
    Ordinate end;    // End ordinate (exclusive)
} ContinuousInterval;

// Helper type for initialization from raw doubles
typedef struct {
    double start;
    double end;
} ContinuousInterval_InnerType;

//-----------------------------------------------------------------------------
// Constants
//-----------------------------------------------------------------------------

// [0, +inf)
#define CONTINUOUS_INTERVAL_ZERO_TO_INF_POS \
    ((ContinuousInterval){ .start = ORDINATE_ZERO, .end = ORDINATE_INF })

// [-inf, +inf)
#define CONTINUOUS_INTERVAL_INF_NEG_TO_POS \
    ((ContinuousInterval){ .start = ORDINATE_INF_NEG, .end = ORDINATE_INF })

//-----------------------------------------------------------------------------
// Construction
//-----------------------------------------------------------------------------

// Initialize interval from double values
static inline ContinuousInterval continuous_interval_init(ContinuousInterval_InnerType args) {
    return (ContinuousInterval){
        .start = ordinate_init(args.start),
        .end = ordinate_init(args.end)
    };
}

// Initialize from ordinates
static inline ContinuousInterval continuous_interval_from_ordinates(Ordinate start, Ordinate end) {
    return (ContinuousInterval){ .start = start, .end = end };
}

// Construct from start and duration
static inline ContinuousInterval continuous_interval_from_start_duration(
    Ordinate start,
    Ordinate duration
) {
    assert(ordinate_gteq_d(duration, 0.0));
    return (ContinuousInterval){
        .start = start,
        .end = ordinate_add(start, duration)
    };
}

//-----------------------------------------------------------------------------
// Methods
//-----------------------------------------------------------------------------

// Compute duration of the interval
static inline Ordinate continuous_interval_duration(ContinuousInterval self) {
    if (ordinate_is_inf(self.start) || ordinate_is_inf(self.end)) {
        return ORDINATE_INF;
    }
    return ordinate_sub(self.end, self.start);
}

// Check if ordinate is within the interval
static inline bool continuous_interval_overlaps(ContinuousInterval self, Ordinate ord) {
    bool is_instant = ordinate_eql(self.start, self.end);

    if (is_instant && ordinate_eql(self.start, ord)) {
        return true;
    }

    return ordinate_gteq(ord, self.start) && ordinate_lt(ord, self.end);
}

// Check if either endpoint is infinite
static inline bool continuous_interval_is_infinite(ContinuousInterval self) {
    return ordinate_is_inf(self.start) || ordinate_is_inf(self.end);
}

// Check if interval starts and ends at the same ordinate
static inline bool continuous_interval_is_instant(ContinuousInterval self) {
    return ordinate_eql(self.start, self.end);
}

//-----------------------------------------------------------------------------
// Interval operations
//-----------------------------------------------------------------------------

// Extend to span both intervals
static inline ContinuousInterval continuous_interval_extend(
    ContinuousInterval fst,
    ContinuousInterval snd
) {
    return (ContinuousInterval){
        .start = ordinate_min(fst.start, snd.start),
        .end = ordinate_max(fst.end, snd.end)
    };
}

// Check if there's any overlap between two intervals
static inline bool continuous_interval_any_overlap(
    ContinuousInterval fst,
    ContinuousInterval snd
) {
    bool fst_is_instant = continuous_interval_is_instant(fst);
    bool snd_is_instant = continuous_interval_is_instant(snd);

    // Handle instant intervals (point-like)
    if (fst_is_instant && ordinate_gteq(fst.start, snd.start) && ordinate_lt(fst.start, snd.end)) {
        return true;
    }
    if (snd_is_instant && ordinate_gteq(snd.start, fst.start) && ordinate_lt(snd.start, fst.end)) {
        return true;
    }
    if (fst_is_instant && snd_is_instant && ordinate_eql(fst.start, snd.start)) {
        return true;
    }

    // General case
    return ordinate_lt(fst.start, snd.end) && ordinate_gt(fst.end, snd.start);
}

// Intersect two intervals, returns true if intersection exists
static inline bool continuous_interval_intersect(
    ContinuousInterval fst,
    ContinuousInterval snd,
    ContinuousInterval* result
) {
    if (!continuous_interval_any_overlap(fst, snd)) {
        return false;
    }

    result->start = ordinate_max(fst.start, snd.start);
    result->end = ordinate_min(fst.end, snd.end);
    return true;
}
