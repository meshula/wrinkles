#pragma once
#include "../opentime/ordinate.hpp"
#include "../opentime/dual.hpp"
#include <iostream>
#include <cmath>
#include <type_traits>

// Control Point implementation
//
// A control point maps a single instantaneous input ordinate to a single
// instantaneous output ordinate.
//
// Ported from wrinkles/src/curve/control_point.zig

// ============================================================================
// ControlPointOf - Generic control point type
// ============================================================================

template<typename T>
struct ControlPointOf {
    using OrdinateType = T;
    using ControlPointType = ControlPointOf<T>;

    T in{};   // input ordinate
    T out{};  // output ordinate

    // ---- Constants ----

    static constexpr ControlPointType ZERO() noexcept {
        if constexpr (requires { T::ZERO(); }) {
            return ControlPointType{T::ZERO(), T::ZERO()};
        } else {
            return ControlPointType{0, 0};
        }
    }

    static constexpr ControlPointType ONE() noexcept {
        if constexpr (requires { T::ONE(); }) {
            return ControlPointType{T::ONE(), T::ONE()};
        } else {
            return ControlPointType{1, 1};
        }
    }

    // ---- Construction ----

    constexpr ControlPointOf() = default;
    constexpr ControlPointOf(T in_, T out_) : in(in_), out(out_) {}

    // Initialize from a base type control point
    template<typename U>
    static constexpr ControlPointType init(ControlPointOf<U> const& from) noexcept {
        if constexpr (std::is_same_v<U, T>) {
            return from;
        } else if constexpr (requires { T::init(from.in); }) {
            return ControlPointType{
                T::init(from.in),
                T::init(from.out)
            };
        } else {
            return ControlPointType{
                static_cast<T>(from.in),
                static_cast<T>(from.out)
            };
        }
    }

    // ---- Polymorphic Arithmetic Operations ----

    // Multiplication: handles both ControlPoint and scalar RHS
    template<typename RHS>
    constexpr ControlPointType mul(RHS const& rhs) const noexcept {
        if constexpr (std::is_same_v<RHS, ControlPointType>) {
            return mul_cp(rhs);
        } else {
            return mul_num(rhs);
        }
    }

    // Multiply with scalar
    template<typename U>
    constexpr ControlPointType mul_num(U const& val) const noexcept {
        if constexpr (requires { in.mul(val); }) {
            return {in.mul(val), out.mul(val)};
        } else {
            return {in * val, out * val};
        }
    }

    // Multiply with ControlPoint
    constexpr ControlPointType mul_cp(ControlPointType const& rhs) const noexcept {
        if constexpr (requires { in.mul(rhs.in); }) {
            return {rhs.in.mul(in), rhs.out.mul(out)};
        } else {
            return {rhs.in * in, rhs.out * out};
        }
    }

    // Division: handles both ControlPoint and scalar RHS
    template<typename RHS>
    constexpr ControlPointType div(RHS const& rhs) const noexcept {
        if constexpr (std::is_same_v<RHS, ControlPointType>) {
            return div_cp(rhs);
        } else {
            return div_num(rhs);
        }
    }

    // Divide by scalar
    template<typename U>
    constexpr ControlPointType div_num(U const& val) const noexcept {
        if constexpr (requires { in.div(val); }) {
            return {in.div(val), out.div(val)};
        } else {
            return {in / val, out / val};
        }
    }

    // Divide by ControlPoint
    constexpr ControlPointType div_cp(ControlPointType const& rhs) const noexcept {
        if constexpr (requires { in.div(rhs.in); }) {
            return {in.div(rhs.in), out.div(rhs.out)};
        } else {
            return {in / rhs.in, out / rhs.out};
        }
    }

    // Addition: handles both ControlPoint and scalar RHS
    template<typename RHS>
    constexpr ControlPointType add(RHS const& rhs) const noexcept {
        // Use type info to distinguish struct from scalar
        if constexpr (std::is_class_v<RHS> || std::is_same_v<RHS, ControlPointType>) {
            return add_cp(rhs);
        } else {
            return add_num(rhs);
        }
    }

    // Add scalar
    template<typename U>
    constexpr ControlPointType add_num(U const& rhs) const noexcept {
        if constexpr (requires { in.add(rhs); }) {
            return {in.add(rhs), out.add(rhs)};
        } else {
            return {in + rhs, out + rhs};
        }
    }

    // Add ControlPoint
    constexpr ControlPointType add_cp(ControlPointType const& rhs) const noexcept {
        if constexpr (requires { in.add(rhs.in); }) {
            return {in.add(rhs.in), out.add(rhs.out)};
        } else {
            return {in + rhs.in, out + rhs.out};
        }
    }

    // Subtraction: handles both ControlPoint and scalar RHS
    template<typename RHS>
    constexpr ControlPointType sub(RHS const& rhs) const noexcept {
        // Use type info to distinguish struct from scalar
        if constexpr (std::is_class_v<RHS> || std::is_same_v<RHS, ControlPointType>) {
            return sub_cp(rhs);
        } else {
            return sub_num(rhs);
        }
    }

    // Subtract scalar
    template<typename U>
    constexpr ControlPointType sub_num(U const& rhs) const noexcept {
        if constexpr (requires { in.sub(rhs); }) {
            return {in.sub(rhs), out.sub(rhs)};
        } else {
            return {in - rhs, out - rhs};
        }
    }

    // Subtract ControlPoint
    constexpr ControlPointType sub_cp(ControlPointType const& rhs) const noexcept {
        if constexpr (requires { in.sub(rhs.in); }) {
            return {in.sub(rhs.in), out.sub(rhs.out)};
        } else {
            return {in - rhs.in, out - rhs.out};
        }
    }

    // ---- Distance and Normalization ----

    // Distance of this point from another point
    constexpr T distance(ControlPointType const& rhs) const noexcept {
        auto diff = rhs.sub(*this);

        if constexpr (requires { diff.in.mul(diff.in).add(diff.out.mul(diff.out)).sqrt(); }) {
            // For types with method-based operations
            return diff.in.mul(diff.in).add(diff.out.mul(diff.out)).sqrt();
        } else {
            // For primitive types
            return std::sqrt(diff.in * diff.in + diff.out * diff.out);
        }
    }

    // Compute the normalized vector for the point
    constexpr ControlPointType normalized() const noexcept {
        auto d = distance(ControlPointType{T{}, T{}});

        if constexpr (requires { in.div(d); }) {
            return {in.div(d), out.div(d)};
        } else {
            return {in / d, out / d};
        }
    }

    // ---- Stream Output ----

    friend std::ostream& operator<<(std::ostream& os, ControlPointType const& cp) {
        os << "ControlPoint(" << cp.in << ", " << cp.out << ")";
        return os;
    }
};

// ============================================================================
// Default ControlPoint Types
// ============================================================================

using Ordinate = OrdinateImpl<double>;
using ControlPoint_BaseType = ControlPointOf<double>;
using ControlPoint = ControlPointOf<Ordinate>;
using Dual_CP = DualOf<ControlPoint>;

// ============================================================================
// Test Helper Functions
// ============================================================================

// Check equality between two control points (for testing)
template<typename T>
inline void expectControlPointEqual(
    ControlPointOf<T> const& lhs,
    ControlPointOf<T> const& rhs
) {
    // For Ordinate types, use eql_approx
    if constexpr (requires { lhs.in.eql_approx(rhs.in); }) {
        if (!lhs.in.eql_approx(rhs.in) || !lhs.out.eql_approx(rhs.out)) {
            std::cerr << "Error: expected " << lhs << " got " << rhs << std::endl;
            throw std::runtime_error("ControlPoint equality check failed");
        }
    } else {
        // For primitive types
        constexpr double EPSILON = 0.00001;
        if (std::abs(lhs.in - rhs.in) > EPSILON || std::abs(lhs.out - rhs.out) > EPSILON) {
            std::cerr << "Error: expected " << lhs << " got " << rhs << std::endl;
            throw std::runtime_error("ControlPoint equality check failed");
        }
    }
}
