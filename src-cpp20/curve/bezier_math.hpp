#pragma once
#include "control_point.hpp"
#include "generic_curve.hpp"
#include "../opentime/dual.hpp"
#include <type_traits>
#include <limits>
#include <cmath>

// Bezier Math components to use with curves
//
// Ported from wrinkles/src/curve/bezier_math.zig

// ============================================================================
// Type Definitions
// ============================================================================

// U_TYPE is the parameter type for bezier curves (normalized parameter in [0,1])
using U_TYPE = Ordinate::BaseType;  // typically double

// ============================================================================
// Basic Interpolation Functions
// ============================================================================

/// Linear interpolation from a to b by amount u, where u ∈ [0, 1]
/// Formula: a * (1 - u) + b * u
template<typename U, typename T>
constexpr T lerp(U const& u, T const& a, T const& b) noexcept {
    // For types with method-based operations (Ordinate, ControlPoint, etc.)
    if constexpr (requires { a.mul(u); }) {
        // Check if u is also a method-based type
        if constexpr (requires { u.neg(); }) {
            // Both a and u are method-based types
            auto one_minus_u = u.neg().add(1.0);
            return a.mul(one_minus_u).add(b.mul(u));
        } else {
            // a is method-based but u is primitive
            return a.mul(1.0 - u).add(b.mul(u));
        }
    } else {
        // For primitive types (float, double)
        return a * (1.0 - u) + b * u;
    }
}

/// Inverse linear interpolation: find u such that lerp(u, a, b) = v
/// Formula: (v - a) / (b - a)
template<typename V, typename T>
constexpr T invlerp(V const& v, T const& a, T const& b) noexcept {
    // Check if a and b are equal
    if constexpr (requires { a.eql(b); }) {
        if (a.eql(b)) {
            return a;
        }
        // (v - a) / (b - a)
        return v.sub(a).div(b.sub(a));
    } else {
        // For primitive types
        if (a == b) {
            return a;
        }
        return (v - a) / (b - a);
    }
}

// ============================================================================
// Control Point Interpolation
// ============================================================================

/// Evaluate output at a given input coordinate between two control points
/// This performs linear interpolation in the output space based on
/// where the input t falls between fst.in and snd.in
inline Ordinate output_at_input_between(
    Ordinate const& t,
    ControlPoint const& fst,
    ControlPoint const& snd
) noexcept {
    auto u = invlerp(t, fst.in, snd.in);
    return lerp(u, fst.out, snd.out);
}

/// Evaluate input at a given output coordinate between two control points
/// This performs linear interpolation in the input space based on
/// where the output v falls between fst.out and snd.out
inline Ordinate input_at_output_between(
    Ordinate const& v,
    ControlPoint const& fst,
    ControlPoint const& snd
) noexcept {
    auto u = invlerp(v, fst.out, snd.out);
    return lerp(u, fst.in, snd.in);
}

// ============================================================================
// Bezier Evaluation Functions
// ============================================================================

/// Evaluate a 1D cubic Bezier whose first point is 0
/// Formula: u³*p4 - 3*u²*(1-u)*p3 + 3*u*(1-u)²*p2
/// Where (1-u) is represented as zmo (zero-minus-one)
inline Ordinate _bezier0(
    Ordinate const& unorm,
    Ordinate const& p2,
    Ordinate const& p3,
    Ordinate const& p4
) noexcept {
    // u³*p4 - 3*u²*zmo*p3 + 3*u*zmo²*p2
    auto u = unorm;
    auto zmo = unorm.sub(1.0);  // (u - 1)

    auto u_sq = u.mul(u);
    auto u_cubed = u_sq.mul(u);
    auto zmo_sq = zmo.mul(zmo);

    return u_cubed.mul(p4)
        .sub(p3.mul(u_sq).mul(zmo).mul(3.0))
        .add(p2.mul(3.0).mul(u).mul(zmo_sq));
}

/// Evaluate a 1D cubic Bezier with dual numbers (for automatic differentiation)
inline Dual_Ord _bezier0_dual(
    Dual_Ord const& unorm,
    Ordinate const& p2,
    Ordinate const& p3,
    Ordinate const& p4
) noexcept {
    // Same formula as _bezier0 but with dual numbers
    auto u = unorm;
    auto zmo = unorm.add(Dual_Ord::init(-1.0));

    auto u_sq = u.mul(u);
    auto u_cubed = u_sq.mul(u);
    auto zmo_sq = zmo.mul(zmo);

    auto p2_dual = Dual_Ord::init(p2);
    auto p3_dual = Dual_Ord::init(p3);
    auto p4_dual = Dual_Ord::init(p4);

    return u_cubed.mul(p4_dual)
        .sub(p3_dual.mul(u_sq).mul(zmo).mul(3.0))
        .add(p2_dual.mul(3.0).mul(u).mul(zmo_sq));
}

/// Find u such that B(u) == x for a monotonically nondecreasing
/// 1-D Bezier curve B(u) with control points (0, p1, p2, p3)
/// Uses iterative root finding (regula falsi method)
inline U_TYPE _findU(
    Ordinate const& x,
    Ordinate const& p1,
    Ordinate const& p2,
    Ordinate const& p3
) noexcept {
    const auto MAX_ABS_ERROR = Ordinate::init(
        std::numeric_limits<Ordinate::BaseType>::epsilon() * 2.0
    );
    constexpr uint8_t MAX_ITERATIONS = 45;

    // Early exits
    if (x.lteq(Ordinate::ZERO())) {
        return 0.0;
    }
    if (x.gteq(p3)) {
        return 1.0;
    }

    auto _u1 = Ordinate::ZERO();
    auto _u2 = Ordinate::ZERO();

    auto x1 = x.neg();  // bezier0(0, p1, p2, p3) - x = 0 - x
    auto x2 = p3.sub(x); // bezier0(1, p1, p2, p3) - x = p3 - x

    // Initial guess using regula falsi
    {
        const auto _u3 = Ordinate::ONE().sub(
            x2.div(x2.sub(x1))
        );
        const auto x3 = _bezier0(_u3, p1, p2, p3).sub(x);

        if (x3.eql(Ordinate::ZERO())) {
            return _u3.as<U_TYPE>();
        }

        if (x3.lt(Ordinate::ZERO())) {
            if (Ordinate::ONE().sub(_u3).lteq(MAX_ABS_ERROR)) {
                if (x2.lt(x3.neg())) {
                    return 1.0;
                }
                return _u3.as<U_TYPE>();
            }
            _u1 = Ordinate::ONE();
            x1 = x2;
        } else {
            _u1 = Ordinate::ZERO();
            x1 = x1.mul(x2).div(x2.add(x3));

            if (_u3.lteq(MAX_ABS_ERROR)) {
                if (x1.neg().lt(x3)) {
                    return 0.0;
                }
                return _u3.as<U_TYPE>();
            }
        }
        _u2 = _u3;
        x2 = x3;
    }

    // Iterative refinement
    for (uint8_t i = 0; i < MAX_ITERATIONS; ++i) {
        const auto _u3 = _u2.sub(
            x2.mul(_u2.sub(_u1).div(x2.sub(x1)))
        );
        const auto x3 = _bezier0(_u3, p1, p2, p3).sub(x);

        if (x3.eql(Ordinate::ZERO())) {
            return _u3.as<U_TYPE>();
        }

        if (x2.mul(x3).lteq(Ordinate::ZERO())) {
            _u1 = _u2;
            x1 = x2;
        } else {
            x1 = x1.mul(x2).div(x2.add(x3));
        }

        _u2 = _u3;
        x2 = x3;

        // Check convergence
        auto diff = (_u2.gt(_u1)) ? _u2.sub(_u1) : _u1.sub(_u2);
        if (diff.lteq(MAX_ABS_ERROR)) {
            break;
        }
    }

    // Return the better root
    auto abs_x1 = x1.lt(Ordinate::ZERO()) ? x1.neg() : x1;
    auto abs_x2 = x2.lt(Ordinate::ZERO()) ? x2.neg() : x2;

    if (abs_x1.lt(abs_x2)) {
        return _u1.as<U_TYPE>();
    }
    return _u2.as<U_TYPE>();
}

/// Calculate the actual order of a bezier curve
/// Returns 1 for linear, 2 for quadratic, 3 for cubic
/// Returns 0 if there's no solution (degenerate case)
inline uint8_t actual_order(
    Ordinate const& p0,
    Ordinate const& p1,
    Ordinate const& p2,
    Ordinate const& p3
) noexcept {
    // Compute coefficients
    // d = -p0 + 3*p1 - 3*p2 + p3
    auto d = p0.neg().add(p1.mul(3.0)).sub(p2.mul(3.0)).add(p3);

    // a = 3*p0 - 6*p1 + 3*p2
    auto a = p0.mul(3.0).sub(p1.mul(6.0)).add(p2.mul(3.0));

    // b = -3*p0 + 3*p1
    auto b = p0.neg().mul(3.0).add(p1.mul(3.0));

    // Check order based on coefficient magnitudes
    if (d.abs().lt(Ordinate::EPSILON())) {
        // Not cubic
        if (a.abs().lt(Ordinate::EPSILON())) {
            // Linear
            if (b.abs().lt(Ordinate::EPSILON())) {
                // Degenerate - no solution
                return 0;
            }
            return 1;
        }
        return 2; // Quadratic
    }

    return 3; // Cubic
}

// ============================================================================
// Slope Utilities
// ============================================================================

/// Calculate slope between two control points
/// Formula: (end.out - start.out) / (end.in - start.in)
inline Ordinate slope(
    ControlPoint const& start,
    ControlPoint const& end
) noexcept {
    return end.out.sub(start.out).div(end.in.sub(start.in));
}

/// Enum to represent the kind of slope between two points
enum class SlopeKind {
    flat,     // Horizontal or vertical line
    rising,   // Positive slope
    falling   // Negative slope
};

/// Compute the slope kind between two control points
inline SlopeKind compute_slope_kind(
    ControlPoint const& start,
    ControlPoint const& end
) noexcept {
    // Flat if inputs or outputs are equal
    if (start.in.eql(end.in) || start.out.eql(end.out)) {
        return SlopeKind::flat;
    }

    auto s = slope(start, end);

    if (s.gt(Ordinate::ZERO())) {
        return SlopeKind::rising;
    } else {
        return SlopeKind::falling;
    }
}

// ============================================================================
// Bezier Segment Structures (forward declaration for segment reduction)
// ============================================================================

// Forward declare Segment type for segment reduction functions
struct BezierSegment;

/// Reduce a segment from 4 points to 3 by linear interpolation
inline BezierSegment segment_reduce4(
    Ordinate const& u,
    BezierSegment const& segment
) noexcept;

/// Reduce a segment from 3 points to 2
inline BezierSegment segment_reduce3(
    Ordinate const& u,
    BezierSegment const& segment
) noexcept;

/// Reduce a segment from 2 points to 1
inline BezierSegment segment_reduce2(
    Ordinate const& u,
    BezierSegment const& segment
) noexcept;
