// dual.h - Automatic differentiation with dual numbers
// Ported from src/opentime/dual.zig
//
// Note: This is a simplified version focusing on Dual_Ord (dual ordinates).
// The full generic dual type system from Zig is simplified for C.

#pragma once

#include "ordinate.h"

// Dual number with Ordinate as inner type
// r = real component, i = infinitesimal component (derivative)
typedef struct {
    Ordinate r;  // Real component
    Ordinate i;  // Infinitesimal component (derivative)
} Dual_Ord;

//-----------------------------------------------------------------------------
// Construction
//-----------------------------------------------------------------------------

// Initialize dual with i = 0
static inline Dual_Ord dual_ord_init(Ordinate r) {
    return (Dual_Ord){ .r = r, .i = ORDINATE_ZERO };
}

// Initialize dual from double with i = 0
static inline Dual_Ord dual_ord_init_d(double r) {
    return (Dual_Ord){ .r = ordinate_init(r), .i = ORDINATE_ZERO };
}

// Initialize dual with both components
static inline Dual_Ord dual_ord_init_ri(Ordinate r, Ordinate i) {
    return (Dual_Ord){ .r = r, .i = i };
}

//-----------------------------------------------------------------------------
// Unary operators
//-----------------------------------------------------------------------------

// Negation
static inline Dual_Ord dual_ord_neg(Dual_Ord self) {
    return (Dual_Ord){ .r = ordinate_neg(self.r), .i = ordinate_neg(self.i) };
}

// Square root: derivative is i / (2 * sqrt(r))
static inline Dual_Ord dual_ord_sqrt(Dual_Ord self) {
    Ordinate sqrt_r = ordinate_sqrt(self.r);
    return (Dual_Ord){
        .r = sqrt_r,
        .i = ordinate_div(self.i, ordinate_mul_d(sqrt_r, 2.0))
    };
}

// Cosine: derivative is -i * sin(r)
static inline Dual_Ord dual_ord_cos(Dual_Ord self) {
    return (Dual_Ord){
        .r = ordinate_init(cos(self.r.v)),
        .i = ordinate_mul(ordinate_neg(self.i), ordinate_init(sin(self.r.v)))
    };
}

// Arccosine: derivative is -i / sqrt(1 - r^2)
static inline Dual_Ord dual_ord_acos(Dual_Ord self) {
    double r_sq = self.r.v * self.r.v;
    return (Dual_Ord){
        .r = ordinate_init(acos(self.r.v)),
        .i = ordinate_div(
            ordinate_neg(self.i),
            ordinate_init(sqrt(1.0 - r_sq))
        )
    };
}

//-----------------------------------------------------------------------------
// Binary operators - dual + dual
//-----------------------------------------------------------------------------

// Addition
static inline Dual_Ord dual_ord_add(Dual_Ord self, Dual_Ord rhs) {
    return (Dual_Ord){
        .r = ordinate_add(self.r, rhs.r),
        .i = ordinate_add(self.i, rhs.i)
    };
}

// Addition with ordinate (scalar)
static inline Dual_Ord dual_ord_add_ord(Dual_Ord self, Ordinate rhs) {
    return (Dual_Ord){
        .r = ordinate_add(self.r, rhs),
        .i = self.i
    };
}

// Subtraction
static inline Dual_Ord dual_ord_sub(Dual_Ord self, Dual_Ord rhs) {
    return (Dual_Ord){
        .r = ordinate_sub(self.r, rhs.r),
        .i = ordinate_sub(self.i, rhs.i)
    };
}

// Subtraction with ordinate (scalar)
static inline Dual_Ord dual_ord_sub_ord(Dual_Ord self, Ordinate rhs) {
    return (Dual_Ord){
        .r = ordinate_sub(self.r, rhs),
        .i = self.i
    };
}

// Multiplication: (a + bi)(c + di) = ac + (ad + bc)i
static inline Dual_Ord dual_ord_mul(Dual_Ord self, Dual_Ord rhs) {
    return (Dual_Ord){
        .r = ordinate_mul(self.r, rhs.r),
        .i = ordinate_add(
            ordinate_mul(self.r, rhs.i),
            ordinate_mul(self.i, rhs.r)
        )
    };
}

// Multiplication with ordinate (scalar)
static inline Dual_Ord dual_ord_mul_ord(Dual_Ord self, Ordinate rhs) {
    return (Dual_Ord){
        .r = ordinate_mul(self.r, rhs),
        .i = ordinate_mul(self.i, rhs)
    };
}

// Division: (a + bi)/(c + di) = (ac + bd)/(c^2 + d^2) + ((bc - ad)/(c^2 + d^2))i
// Simplified for dual numbers: (a + bi)/(c + di) = a/c + ((c*b - a*d)/c^2)i
static inline Dual_Ord dual_ord_div(Dual_Ord self, Dual_Ord rhs) {
    Ordinate r_sq = ordinate_mul(rhs.r, rhs.r);
    return (Dual_Ord){
        .r = ordinate_div(self.r, rhs.r),
        .i = ordinate_div(
            ordinate_sub(
                ordinate_mul(rhs.r, self.i),
                ordinate_mul(self.r, rhs.i)
            ),
            r_sq
        )
    };
}

// Division with ordinate (scalar)
static inline Dual_Ord dual_ord_div_ord(Dual_Ord self, Ordinate rhs) {
    return (Dual_Ord){
        .r = ordinate_div(self.r, rhs),
        .i = ordinate_div(self.i, rhs)
    };
}

// Power: derivative is i * (y-1) * r^(y-1)
static inline Dual_Ord dual_ord_pow(Dual_Ord self, double y) {
    return (Dual_Ord){
        .r = ordinate_pow(self.r, y),
        .i = ordinate_mul(
            ordinate_mul_d(self.i, y - 1.0),
            ordinate_pow(self.r, y - 1.0)
        )
    };
}

//-----------------------------------------------------------------------------
// Comparisons (compare real parts only)
//-----------------------------------------------------------------------------

static inline bool dual_ord_lt(Dual_Ord self, Dual_Ord rhs) {
    return ordinate_lt(self.r, rhs.r);
}

static inline bool dual_ord_gt(Dual_Ord self, Dual_Ord rhs) {
    return ordinate_gt(self.r, rhs.r);
}

static inline bool dual_ord_eql(Dual_Ord self, Dual_Ord rhs) {
    return ordinate_eql(self.r, rhs.r) && ordinate_eql(self.i, rhs.i);
}
