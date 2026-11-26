// transform.h - 1D Affine transformation implementation
// Ported from src/opentime/transform.zig

#pragma once

#include "ordinate.h"
#include "interval.h"

// Affine transformation in 1D
// Represents a homogenous-coordinates transform matrix:
//     | Scale | Offset |
//     |   0   |   1    | (Implicit)
//
// Transform order: scale then offset
// y = T(x) = (x * Scale + Offset)
typedef struct {
    Ordinate offset;
    Ordinate scale;
} AffineTransform1D;

//-----------------------------------------------------------------------------
// Constants
//-----------------------------------------------------------------------------

#define AFFINE_TRANSFORM_1D_IDENTITY \
    ((AffineTransform1D){ .offset = ORDINATE_ZERO, .scale = ORDINATE_ONE })

//-----------------------------------------------------------------------------
// Methods
//-----------------------------------------------------------------------------

// Transform an ordinate: ord * scale + offset
static inline Ordinate affine_transform_1d_applied_to_ordinate(
    AffineTransform1D self,
    Ordinate ord
) {
    // ord * scale + offset
    return ordinate_add(
        ordinate_mul(ord, self.scale),
        self.offset
    );
}

// Transform an interval by transforming its endpoints
static inline ContinuousInterval affine_transform_1d_applied_to_interval(
    AffineTransform1D self,
    ContinuousInterval cint
) {
    return (ContinuousInterval){
        .start = affine_transform_1d_applied_to_ordinate(self, cint.start),
        .end = affine_transform_1d_applied_to_ordinate(self, cint.end)
    };
}

// Transform bounds, ensuring start < end even if scale is negative
static inline ContinuousInterval affine_transform_1d_applied_to_bounds(
    AffineTransform1D self,
    ContinuousInterval bnds
) {
    if (ordinate_lt_d(self.scale, 0.0)) {
        return (ContinuousInterval){
            .start = affine_transform_1d_applied_to_ordinate(self, bnds.end),
            .end = affine_transform_1d_applied_to_ordinate(self, bnds.start)
        };
    }

    return affine_transform_1d_applied_to_interval(self, bnds);
}

// Transform a transform (composition)
static inline AffineTransform1D affine_transform_1d_applied_to_transform(
    AffineTransform1D self,
    AffineTransform1D rhs
) {
    return (AffineTransform1D){
        .offset = affine_transform_1d_applied_to_ordinate(self, rhs.offset),
        .scale = ordinate_mul(rhs.scale, self.scale)
    };
}

// Return the inverse of this transform
// Assumes that scale is non-zero
//
// Because AffineTransform1D is a 2x2 matrix:
//     | scale offset |
//     |   0     1    |
//
// The inverse is:
//     | 1/scale -offset/scale |
//     |   0           1       |
static inline AffineTransform1D affine_transform_1d_inverted(
    AffineTransform1D self
) {
    assert(!ordinate_eql(self.scale, ORDINATE_ZERO));

    return (AffineTransform1D){
        .offset = ordinate_div(ordinate_neg(self.offset), self.scale),
        .scale = ordinate_div(ORDINATE_ONE, self.scale)
    };
}
