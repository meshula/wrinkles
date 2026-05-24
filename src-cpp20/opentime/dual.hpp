#pragma once
#include "ordinate.hpp"
#include <type_traits>
#include <iostream>
#include <cmath>

// Automatic differentiation with dual numbers
// Math on duals automatically computes derivatives.
//
// Ported from wrinkles/src/opentime/dual.zig

// ============================================================================
// Type trait to detect if a type is a dual
// ============================================================================

template<typename T>
struct is_dual : std::false_type {};

template<typename T>
inline constexpr bool is_dual_v = is_dual<T>::value;

// ============================================================================
// DualOf - Generic dual number wrapper
// ============================================================================

template<typename T>
struct DualOf;

// Specialization for numeric types (float, double, etc.)
template<typename T>
    requires std::is_floating_point_v<T>
struct DualOf<T> {
    using BaseType = T;
    static constexpr bool __IS_DUAL = true;

    T r = 0;  // real component
    T i = 0;  // infinitesimal component

    // ---- Construction ----

    constexpr DualOf() = default;
    constexpr DualOf(T r_, T i_ = 0) : r(r_), i(i_) {}

    // Initialize with i = 0
    static constexpr DualOf init(T r_) noexcept {
        return DualOf{r_, 0};
    }

    static constexpr DualOf init_ri(T r_, T i_) noexcept {
        return DualOf{r_, i_};
    }

    // ---- Unary Operations ----

    constexpr DualOf neg() const noexcept {
        return {-r, -i};
    }

    // ---- Binary Arithmetic ----

    // Addition: handles both dual and scalar RHS
    template<typename RHS>
    constexpr DualOf add(RHS const& rhs) const noexcept {
        if constexpr (is_dual_v<RHS>) {
            return {r + rhs.r, i + rhs.i};
        } else {
            return {r + rhs, i};
        }
    }

    // Subtraction: handles both dual and scalar RHS
    template<typename RHS>
    constexpr DualOf sub(RHS const& rhs) const noexcept {
        if constexpr (is_dual_v<RHS>) {
            return {r - rhs.r, i - rhs.i};
        } else {
            return {r - rhs, i};
        }
    }

    // Multiplication: handles both dual and scalar RHS
    template<typename RHS>
    constexpr DualOf mul(RHS const& rhs) const noexcept {
        if constexpr (is_dual_v<RHS>) {
            // (a + bε)(c + dε) = ac + (ad + bc)ε
            return {r * rhs.r, r * rhs.i + i * rhs.r};
        } else {
            return {r * rhs, i * rhs};
        }
    }

    // Division: handles both dual and scalar RHS
    template<typename RHS>
    constexpr DualOf div(RHS const& rhs) const noexcept {
        if constexpr (is_dual_v<RHS>) {
            // (a + bε) / (c + dε) = a/c + ((bc - ad)/c²)ε
            return {
                r / rhs.r,
                (rhs.r * i - r * rhs.i) / (rhs.r * rhs.r)
            };
        } else {
            return {r / rhs, i / rhs};
        }
    }

    // ---- Advanced Operations ----

    constexpr DualOf sqrt() const noexcept {
        // d/dx sqrt(x) = 1/(2*sqrt(x))
        // So: sqrt(r + iε) = sqrt(r) + (i/(2*sqrt(r)))ε
        return {std::sqrt(r), i / (2 * std::sqrt(r))};
    }

    constexpr DualOf pow(T exponent) const noexcept {
        // d/dx x^n = n*x^(n-1)
        // So: (r + iε)^n = r^n + (i * n * r^(n-1))ε
        return {
            std::pow(r, exponent),
            i * exponent * std::pow(r, exponent - 1)
        };
    }

    constexpr DualOf cos() const noexcept {
        // d/dx cos(x) = -sin(x)
        // So: cos(r + iε) = cos(r) + (-i*sin(r))ε
        return {std::cos(r), -i * std::sin(r)};
    }

    constexpr DualOf acos() const noexcept {
        // d/dx acos(x) = -1/sqrt(1 - x²)
        // So: acos(r + iε) = acos(r) + (-i/sqrt(1 - r²))ε
        return {
            std::acos(r),
            -i / std::sqrt(1 - r * r)
        };
    }

    // ---- Comparison (on real component only) ----

    template<typename RHS>
    constexpr bool lt(RHS const& rhs) const noexcept {
        if constexpr (is_dual_v<RHS>) {
            return r < rhs.r;
        } else {
            return r < rhs;
        }
    }

    template<typename RHS>
    constexpr bool gt(RHS const& rhs) const noexcept {
        if constexpr (is_dual_v<RHS>) {
            return r > rhs.r;
        } else {
            return r > rhs;
        }
    }

    // ---- Stream Output ----

    friend std::ostream& operator<<(std::ostream& os, DualOf const& d) {
        os << "Dual(" << d.r << " + " << d.i << "ε)";
        return os;
    }
};

// Mark the numeric dual as a dual type
template<typename T>
    requires std::is_floating_point_v<T>
struct is_dual<DualOf<T>> : std::true_type {};

// ============================================================================
// DualOf specialization for struct types (e.g., OrdinateImpl)
// ============================================================================

template<typename T>
    requires std::is_class_v<T> && (!std::is_floating_point_v<T>)
struct DualOf<T> {
    using BaseType = T;
    using DualType = DualOf<T>;
    static constexpr bool __IS_DUAL = true;

    T r = T::ZERO();  // real component
    T i = T::ZERO();  // infinitesimal component

    // ---- Constants ----

    static constexpr DualType ZERO_ZERO() noexcept {
        return DualType{T::ZERO(), T::ZERO()};
    }

    static constexpr DualType ONE_ZERO() noexcept {
        return DualType{T::ONE(), T::ZERO()};
    }

    static constexpr DualType EPSILON() noexcept {
        return DualType{T::EPSILON(), T::ZERO()};
    }

    // ---- Construction ----

    constexpr DualOf() = default;
    constexpr DualOf(T r_, T i_) : r(r_), i(i_) {}

    // Polymorphic init: handles DualType, T, or convertible types
    template<typename U>
    static constexpr DualType init(U const& r_) noexcept {
        if constexpr (std::is_same_v<U, DualType>) {
            return r_;
        } else if constexpr (std::is_same_v<U, T>) {
            return DualType{r_, T::ZERO()};
        } else {
            return DualType{T::init(r_), T::ZERO()};
        }
    }

    template<typename U, typename V>
    static constexpr DualType init_ri(U const& r_, V const& i_) noexcept {
        T r_base;
        if constexpr (std::is_same_v<U, T>) {
            r_base = r_;
        } else {
            r_base = T::init(r_);
        }

        T i_base;
        if constexpr (std::is_same_v<V, T>) {
            i_base = i_;
        } else {
            i_base = T::init(i_);
        }

        return DualType{r_base, i_base};
    }

    // ---- Unary Operations ----

    constexpr DualType neg() const noexcept {
        return {r.neg(), i.neg()};
    }

    // ---- Binary Arithmetic ----

    template<typename RHS>
    constexpr DualType add(RHS const& rhs) const noexcept {
        if constexpr (is_dual_v<RHS>) {
            return {r.add(rhs.r), i.add(rhs.i)};
        } else if constexpr (std::is_same_v<RHS, T>) {
            return {r.add(rhs), i};
        } else {
            return {r.add(rhs), i};
        }
    }

    template<typename RHS>
    constexpr DualType sub(RHS const& rhs) const noexcept {
        if constexpr (is_dual_v<RHS>) {
            return {r.sub(rhs.r), i.sub(rhs.i)};
        } else if constexpr (std::is_same_v<RHS, T>) {
            return {r.sub(rhs), i};
        } else {
            return {r.sub(rhs), i};
        }
    }

    template<typename RHS>
    constexpr DualType mul(RHS const& rhs) const noexcept {
        if constexpr (is_dual_v<RHS>) {
            // (a + bε)(c + dε) = ac + (ad + bc)ε
            return {
                r.mul(rhs.r),
                r.mul(rhs.i).add(i.mul(rhs.r))
            };
        } else {
            return {r.mul(rhs), i.mul(rhs)};
        }
    }

    template<typename RHS>
    constexpr DualType div(RHS const& rhs) const noexcept {
        if constexpr (is_dual_v<RHS>) {
            // (a + bε) / (c + dε) = a/c + ((cb - ad)/c²)ε
            return {
                r.div(rhs.r),
                rhs.r.mul(i).sub(r.mul(rhs.i)).div(rhs.r.mul(rhs.r))
            };
        } else {
            return {r.div(rhs), i.div(rhs)};
        }
    }

    // ---- Advanced Operations ----

    constexpr DualType sqrt() const noexcept {
        // d/dx sqrt(x) = 1/(2*sqrt(x))
        // So: sqrt(r + iε) = sqrt(r) + (i/(2*sqrt(r)))ε
        return {
            r.sqrt(),
            i.div(r.sqrt().mul(2))
        };
    }

    template<typename ExpType>
    constexpr DualType pow(ExpType const& exponent) const noexcept {
        // d/dx x^n = n*x^(n-1)
        // So: (r + iε)^n = r^n + (i * n * r^(n-1))ε
        return {
            r.pow(exponent),
            i.mul(exponent).mul(r.pow(exponent - 1))
        };
    }

    constexpr DualType cos() const noexcept {
        // d/dx cos(x) = -sin(x)
        // So: cos(r + iε) = cos(r) + (-i*sin(r))ε
        // Route through BaseType's as() to use std::cos/sin
        return {
            T::init(std::cos(r.template as<typename T::BaseType>())),
            i.neg().mul(T::init(std::sin(r.template as<typename T::BaseType>())))
        };
    }

    constexpr DualType acos() const noexcept {
        // d/dx acos(x) = -1/sqrt(1 - x²)
        // So: acos(r + iε) = acos(r) + (-i/sqrt(1 - r²))ε
        return {
            T::init(std::acos(r.template as<typename T::BaseType>())),
            i.neg().div(
                T::init(1.0).sub(r.mul(r)).sqrt()
            )
        };
    }

    // ---- Comparison (on real component only) ----

    template<typename RHS>
    constexpr bool eql(RHS const& rhs) const noexcept {
        if constexpr (is_dual_v<RHS>) {
            return r.eql(rhs.r);
        } else {
            return r.eql(rhs);
        }
    }

    constexpr bool eql_approx(DualType const& rhs) const noexcept {
        return (
            r.lt(EPSILON().add(rhs.r)) &&
            r.gt(EPSILON().neg().add(rhs.r))
        );
    }

    template<typename RHS>
    constexpr bool lt(RHS const& rhs) const noexcept {
        if constexpr (is_dual_v<RHS>) {
            return r.lt(rhs.r);
        } else {
            return r.lt(rhs);
        }
    }

    template<typename RHS>
    constexpr bool lteq(RHS const& rhs) const noexcept {
        if constexpr (is_dual_v<RHS>) {
            return r.lteq(rhs.r);
        } else {
            return r.lteq(rhs);
        }
    }

    template<typename RHS>
    constexpr bool gt(RHS const& rhs) const noexcept {
        if constexpr (is_dual_v<RHS>) {
            return r.gt(rhs.r);
        } else {
            return r.gt(rhs);
        }
    }

    template<typename RHS>
    constexpr bool gteq(RHS const& rhs) const noexcept {
        if constexpr (is_dual_v<RHS>) {
            return r.gteq(rhs.r);
        } else {
            return r.gteq(rhs);
        }
    }

    // ---- Stream Output ----

    friend std::ostream& operator<<(std::ostream& os, DualType const& d) {
        os << "Dual<" << typeid(T).name() << ">(" << d.r << " + " << d.i << "ε)";
        return os;
    }
};

// Mark the struct dual as a dual type
template<typename T>
    requires std::is_class_v<T> && (!std::is_floating_point_v<T>)
struct is_dual<DualOf<T>> : std::true_type {};

// ============================================================================
// Default dual type for opentime (matches Zig's Dual_Ord)
// ============================================================================

using Dual_Ord = DualOf<OrdinateImpl<double>>;