// ordinate.h - Ordinate type and support math for opentime
// Ported from src/opentime/ordinate.zig

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include "util.h"

// Ordinate type - a continuous number line coordinate
// Uses f64 (double) as the inner type, mirroring Zig's Ordinate = OrdinateOf(f64)
typedef struct {
    double v;  // Value of the ordinate
} Ordinate;

// Constants
static const Ordinate ORDINATE_ZERO = { .v = 0.0 };
static const Ordinate ORDINATE_ONE = { .v = 1.0 };
#define ORDINATE_INF ((Ordinate){ .v = HUGE_VAL })
#define ORDINATE_INF_NEG ((Ordinate){ .v = -HUGE_VAL })
#define ORDINATE_NAN ((Ordinate){ .v = ((double)NAN) })
#define ORDINATE_EPSILON ((Ordinate){ .v = OPENTIME_EPSILON_F })

//-----------------------------------------------------------------------------
// Construction
//-----------------------------------------------------------------------------

// Initialize ordinate from double
static inline Ordinate ordinate_init(double value) {
    return (Ordinate){ .v = value };
}

// Initialize ordinate from int
static inline Ordinate ordinate_init_i(int value) {
    return (Ordinate){ .v = (double)value };
}

//-----------------------------------------------------------------------------
// Type conversion
//-----------------------------------------------------------------------------

// Convert to double
static inline double ordinate_as_double(Ordinate self) {
    return self.v;
}

// Convert to int
static inline int ordinate_as_int(Ordinate self) {
    return (int)self.v;
}

//-----------------------------------------------------------------------------
// Unary operators
//-----------------------------------------------------------------------------

// Negate
static inline Ordinate ordinate_neg(Ordinate self) {
    return (Ordinate){ .v = -self.v };
}

// Square root
static inline Ordinate ordinate_sqrt(Ordinate self) {
    return (Ordinate){ .v = sqrt(self.v) };
}

// Absolute value
static inline Ordinate ordinate_abs(Ordinate self) {
    return (Ordinate){ .v = fabs(self.v) };
}

//-----------------------------------------------------------------------------
// Binary operators (ordinate op ordinate)
//-----------------------------------------------------------------------------

// Addition
static inline Ordinate ordinate_add(Ordinate self, Ordinate rhs) {
    return (Ordinate){ .v = self.v + rhs.v };
}

// Addition with double
static inline Ordinate ordinate_add_d(Ordinate self, double rhs) {
    return (Ordinate){ .v = self.v + rhs };
}

// Subtraction
static inline Ordinate ordinate_sub(Ordinate self, Ordinate rhs) {
    return (Ordinate){ .v = self.v - rhs.v };
}

// Subtraction with double
static inline Ordinate ordinate_sub_d(Ordinate self, double rhs) {
    return (Ordinate){ .v = self.v - rhs };
}

// Multiplication
static inline Ordinate ordinate_mul(Ordinate self, Ordinate rhs) {
    return (Ordinate){ .v = self.v * rhs.v };
}

// Multiplication with double
static inline Ordinate ordinate_mul_d(Ordinate self, double rhs) {
    return (Ordinate){ .v = self.v * rhs };
}

// Division
static inline Ordinate ordinate_div(Ordinate self, Ordinate rhs) {
    return (Ordinate){ .v = self.v / rhs.v };
}

// Division with double
static inline Ordinate ordinate_div_d(Ordinate self, double rhs) {
    return (Ordinate){ .v = self.v / rhs };
}

//-----------------------------------------------------------------------------
// Binary macros
//-----------------------------------------------------------------------------

// Power
static inline Ordinate ordinate_pow(Ordinate self, double exp) {
    return (Ordinate){ .v = pow(self.v, exp) };
}

// Minimum
static inline Ordinate ordinate_min(Ordinate self, Ordinate rhs) {
    return (Ordinate){ .v = fmin(self.v, rhs.v) };
}

// Minimum with double
static inline Ordinate ordinate_min_d(Ordinate self, double rhs) {
    return (Ordinate){ .v = fmin(self.v, rhs) };
}

// Maximum
static inline Ordinate ordinate_max(Ordinate self, Ordinate rhs) {
    return (Ordinate){ .v = fmax(self.v, rhs.v) };
}

// Maximum with double
static inline Ordinate ordinate_max_d(Ordinate self, double rhs) {
    return (Ordinate){ .v = fmax(self.v, rhs) };
}

//-----------------------------------------------------------------------------
// Binary tests / comparisons
//-----------------------------------------------------------------------------

// Strict equality
static inline bool ordinate_eql(Ordinate self, Ordinate rhs) {
    return self.v == rhs.v;
}

// Equality with double
static inline bool ordinate_eql_d(Ordinate self, double rhs) {
    return self.v == rhs;
}

// Approximate equality
static inline bool ordinate_eql_approx(Ordinate self, Ordinate rhs) {
    return (self.v < rhs.v + OPENTIME_EPSILON_F) &&
           (self.v > rhs.v - OPENTIME_EPSILON_F);
}

// Approximate equality with double
static inline bool ordinate_eql_approx_d(Ordinate self, double rhs) {
    return (self.v < rhs + OPENTIME_EPSILON_F) &&
           (self.v > rhs - OPENTIME_EPSILON_F);
}

// Less than
static inline bool ordinate_lt(Ordinate self, Ordinate rhs) {
    return self.v < rhs.v;
}

// Less than with double
static inline bool ordinate_lt_d(Ordinate self, double rhs) {
    return self.v < rhs;
}

// Less than or equal
static inline bool ordinate_lteq(Ordinate self, Ordinate rhs) {
    return self.v <= rhs.v;
}

// Less than or equal with double
static inline bool ordinate_lteq_d(Ordinate self, double rhs) {
    return self.v <= rhs;
}

// Greater than
static inline bool ordinate_gt(Ordinate self, Ordinate rhs) {
    return self.v > rhs.v;
}

// Greater than with double
static inline bool ordinate_gt_d(Ordinate self, double rhs) {
    return self.v > rhs;
}

// Greater than or equal
static inline bool ordinate_gteq(Ordinate self, Ordinate rhs) {
    return self.v >= rhs.v;
}

// Greater than or equal with double
static inline bool ordinate_gteq_d(Ordinate self, double rhs) {
    return self.v >= rhs;
}

//-----------------------------------------------------------------------------
// Special value tests
//-----------------------------------------------------------------------------

// Is infinite
static inline bool ordinate_is_inf(Ordinate self) {
    return isinf(self.v);
}

// Is finite
static inline bool ordinate_is_finite(Ordinate self) {
    return isfinite(self.v);
}

// Is NaN
static inline bool ordinate_is_nan(Ordinate self) {
    return isnan(self.v);
}

//-----------------------------------------------------------------------------
// Utility functions for sorting
//-----------------------------------------------------------------------------

// Comparison function for qsort (ascending)
static inline int ordinate_cmp_asc(const void* a, const void* b) {
    const Ordinate* ord_a = (const Ordinate*)a;
    const Ordinate* ord_b = (const Ordinate*)b;
    if (ord_a->v < ord_b->v) return -1;
    if (ord_a->v > ord_b->v) return 1;
    return 0;
}
