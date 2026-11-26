// lerp.h - Linear interpolation functions
// Ported from src/opentime/lerp.zig

#pragma once

#include "ordinate.h"
#include "dual.h"

// Linearly interpolate from 'a' to 'b' by amount 'u' [0, 1]
// Formula: (a * (1 - u)) + (b * u)
static inline Ordinate opentime_lerp(Ordinate u, Ordinate a, Ordinate b) {
    // (a * ((-u) + 1.0)) + (b * u)
    Ordinate one_minus_u = ordinate_sub_d(ordinate_neg(u), -1.0);  // 1.0 - u
    Ordinate a_scaled = ordinate_mul(a, one_minus_u);
    Ordinate b_scaled = ordinate_mul(b, u);
    return ordinate_add(a_scaled, b_scaled);
}

// Inverse linear interpolation - compute the 'u' for which lerp(u, a, b) == v
// Formula: (v - a) / (b - a)
static inline Ordinate opentime_invlerp(Ordinate v, Ordinate a, Ordinate b) {
    if (ordinate_eql(b, a)) {
        return a;
    }
    // (v - a) / (b - a)
    return ordinate_div(
        ordinate_sub(v, a),
        ordinate_sub(b, a)
    );
}

//=============================================================================
// Dual number lerp
//=============================================================================

// Linearly interpolate dual numbers from 'a' to 'b' by dual amount 'u'
// Formula: (a * (1 - u)) + (b * u)
// Derivatives propagate through automatically
static inline Dual_Ord opentime_lerp_dual(Dual_Ord u, Dual_Ord a, Dual_Ord b) {
    // (1.0 - u)
    Dual_Ord one_minus_u = dual_ord_sub_ord(dual_ord_init_d(1.0), u.r);
    one_minus_u.i = ordinate_neg(u.i);

    // a * (1 - u)
    Dual_Ord a_scaled = dual_ord_mul(a, one_minus_u);

    // b * u
    Dual_Ord b_scaled = dual_ord_mul(b, u);

    // (a * (1 - u)) + (b * u)
    return dual_ord_add(a_scaled, b_scaled);
}
