// control_point.h - Control point implementation for 2D curves
// Ported from src/curve/control_point.zig
//
// A control point maps a single input ordinate to a single output ordinate.
// This is a monomorphic implementation using opentime Ordinate.

#pragma once

#include "../opentime/ordinate.h"
#include "../opentime/dual.h"
#include <math.h>
#include <stdbool.h>

//=============================================================================
// ControlPoint type
//=============================================================================

/// A control point maps an input ordinate to an output ordinate
typedef struct {
    /// Input ordinate
    Ordinate in;
    /// Output ordinate
    Ordinate out;
} ControlPoint;

/// Dual control point for automatic differentiation
typedef struct {
    /// Input dual ordinate
    Dual_Ord in;
    /// Output dual ordinate
    Dual_Ord out;
} Dual_CP;

//=============================================================================
// Constants
//=============================================================================

/// Zero control point (0, 0)
static inline ControlPoint control_point_zero(void) {
    return (ControlPoint){
        .in = ordinate_init(0.0),
        .out = ordinate_init(0.0)
    };
}

/// One control point (1, 1)
static inline ControlPoint control_point_one(void) {
    return (ControlPoint){
        .in = ordinate_init(1.0),
        .out = ordinate_init(1.0)
    };
}

/// Zero dual control point (0, 0) with zero derivatives
static inline Dual_CP dual_cp_zero(void) {
    return (Dual_CP){
        .in = dual_ord_init(ORDINATE_ZERO),
        .out = dual_ord_init(ORDINATE_ZERO)
    };
}

//=============================================================================
// Initialization
//=============================================================================

/// Initialize a control point from double values
static inline ControlPoint control_point_init(double in, double out) {
    return (ControlPoint){
        .in = ordinate_init(in),
        .out = ordinate_init(out)
    };
}

/// Initialize a dual control point from a regular control point (with zero derivatives)
static inline Dual_CP dual_cp_init(ControlPoint cp) {
    return (Dual_CP){
        .in = dual_ord_init(cp.in),
        .out = dual_ord_init(cp.out)
    };
}

//=============================================================================
// Arithmetic operations
//=============================================================================

/// Multiply control point by a scalar
static inline ControlPoint control_point_mul_scalar(
    ControlPoint self,
    double val
) {
    return (ControlPoint){
        .in = ordinate_mul(self.in, ordinate_init(val)),
        .out = ordinate_mul(self.out, ordinate_init(val))
    };
}

/// Multiply control point by another control point (component-wise)
static inline ControlPoint control_point_mul(
    ControlPoint self,
    ControlPoint rhs
) {
    return (ControlPoint){
        .in = ordinate_mul(self.in, rhs.in),
        .out = ordinate_mul(self.out, rhs.out)
    };
}

/// Divide control point by a scalar
static inline ControlPoint control_point_div_scalar(
    ControlPoint self,
    double val
) {
    return (ControlPoint){
        .in = ordinate_div(self.in, ordinate_init(val)),
        .out = ordinate_div(self.out, ordinate_init(val))
    };
}

/// Divide control point by another control point (component-wise)
static inline ControlPoint control_point_div(
    ControlPoint self,
    ControlPoint rhs
) {
    return (ControlPoint){
        .in = ordinate_div(self.in, rhs.in),
        .out = ordinate_div(self.out, rhs.out)
    };
}

/// Add two control points
static inline ControlPoint control_point_add(
    ControlPoint self,
    ControlPoint rhs
) {
    return (ControlPoint){
        .in = ordinate_add(self.in, rhs.in),
        .out = ordinate_add(self.out, rhs.out)
    };
}

/// Add scalar to control point
static inline ControlPoint control_point_add_scalar(
    ControlPoint self,
    double rhs
) {
    Ordinate rhs_ord = ordinate_init(rhs);
    return (ControlPoint){
        .in = ordinate_add(self.in, rhs_ord),
        .out = ordinate_add(self.out, rhs_ord)
    };
}

/// Subtract two control points
static inline ControlPoint control_point_sub(
    ControlPoint self,
    ControlPoint rhs
) {
    return (ControlPoint){
        .in = ordinate_sub(self.in, rhs.in),
        .out = ordinate_sub(self.out, rhs.out)
    };
}

/// Subtract scalar from control point
static inline ControlPoint control_point_sub_scalar(
    ControlPoint self,
    double rhs
) {
    Ordinate rhs_ord = ordinate_init(rhs);
    return (ControlPoint){
        .in = ordinate_sub(self.in, rhs_ord),
        .out = ordinate_sub(self.out, rhs_ord)
    };
}

//=============================================================================
// Geometric operations
//=============================================================================

/// Compute distance from this point to another point
static inline Ordinate control_point_distance(
    ControlPoint self,
    ControlPoint rhs
) {
    ControlPoint diff = control_point_sub(rhs, self);
    Ordinate in_sq = ordinate_mul(diff.in, diff.in);
    Ordinate out_sq = ordinate_mul(diff.out, diff.out);
    Ordinate sum = ordinate_add(in_sq, out_sq);
    return ordinate_sqrt(sum);
}

/// Compute the normalized vector for the point
static inline ControlPoint control_point_normalized(ControlPoint self) {
    ControlPoint zero = control_point_zero();
    Ordinate d = control_point_distance(self, zero);
    return (ControlPoint){
        .in = ordinate_div(self.in, d),
        .out = ordinate_div(self.out, d)
    };
}

//=============================================================================
// Comparison
//=============================================================================

/// Check if two control points are equal within epsilon
static inline bool control_point_equal(
    ControlPoint lhs,
    ControlPoint rhs
) {
    return ordinate_eql(lhs.in, rhs.in)
        && ordinate_eql(lhs.out, rhs.out);
}
