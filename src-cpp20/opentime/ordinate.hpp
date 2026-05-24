#pragma once
#include <cmath>
#include <limits>
#include <type_traits>
#include <iostream>
#include <concepts>

template<typename T>
concept arithmetic = std::integral<T> || std::floating_point<T>;

// Lightweight Ordinate wrapper.
// Specialize the concrete Ordinate type with a using/typedef:
//   using Ordinate = OrdinateImpl<double>;
// or
//   using Ordinate = OrdinateImpl<MyADScalar>;

template<typename T>
requires (!std::is_reference_v<T>)
struct OrdinateImpl {
    using BaseType = T;
    using OrdinateType = OrdinateImpl<T>;

    T v;

    // Constants
    static constexpr OrdinateType ZERO()    noexcept { return OrdinateType{T(0)}; }
    static constexpr OrdinateType ONE()     noexcept { return OrdinateType{T(1)}; }
    static OrdinateType INF()               noexcept { return OrdinateType{std::numeric_limits<T>::infinity()}; }
    static OrdinateType INF_NEG()           noexcept { return OrdinateType{-std::numeric_limits<T>::infinity()}; }
    static OrdinateType NaN()               noexcept { return OrdinateType{std::numeric_limits<T>::quiet_NaN()}; }
    // Default epsilon; you can override by directly using Ordinate::EPSILON() if you pick an AD scalar that has its own epsilon semantics.
    static OrdinateType EPSILON()           noexcept { return OrdinateType{static_cast<T>(1e-6)}; }

    // Constructors
    constexpr OrdinateImpl() = default;
    constexpr explicit OrdinateImpl(T vv) noexcept : v(vv) {}

    // Construct from arithmetic (int/float) like Zig's init
    template<std::integral I>
    static constexpr OrdinateType init_from_int(I x) noexcept {
        return OrdinateType{static_cast<T>(x)};
    }
    template<std::floating_point F>
    static constexpr OrdinateType init_from_float(F x) noexcept {
        return OrdinateType{static_cast<T>(x)};
    }
    template<typename U>
    static constexpr OrdinateType init(U x) noexcept {
        if constexpr (std::is_same_v<std::decay_t<U>, OrdinateType>) {
            return x;
        } else if constexpr (std::integral<std::remove_cv_t<std::remove_reference_t<U>>>) {
            return init_from_int(x);
        } else if constexpr (std::floating_point<std::remove_cv_t<std::remove_reference_t<U>>>) {
            return init_from_float(x);
        } else {
            static_assert(std::is_arithmetic_v<U>, "Ordinate can only be constructed from integral or floating types (or Ordinate).");
            return OrdinateType{static_cast<T>(x)};
        }
    }

    // as<Target>() like Zig's as()
    template<typename Target>
    constexpr Target as() const noexcept {
        if constexpr (std::is_floating_point_v<Target>) {
            return static_cast<Target>(v);
        } else if constexpr (std::is_integral_v<Target>) {
            return static_cast<Target>(v);
        } else {
            static_assert(std::is_arithmetic_v<Target>, "Ordinate::as<Target> only supports float or int targets");
        }
    }

    // formatting
    friend std::ostream& operator<<(std::ostream& os, OrdinateType const& o) {
        os << o.v;
        return os;
    }

    // unary ops
    constexpr OrdinateType neg() const noexcept { return OrdinateType{ -v }; }
    OrdinateType sqrt() const noexcept { 
        using std::sqrt; // allow ADL to find custom sqrt functions on non arithmetic types
        return OrdinateType{ sqrt(v) }; }
    constexpr OrdinateType abs() const noexcept { if constexpr (std::is_floating_point_v<T>) return OrdinateType{ std::fabs(v) }; else return OrdinateType{ v < T(0) ? -v : v }; }
    constexpr OrdinateType normalized() const noexcept { return *this; }

    // binary ops with another Ordinate
    constexpr OrdinateType add(OrdinateType rhs) const noexcept { return OrdinateType{ v + rhs.v }; }
    constexpr OrdinateType sub(OrdinateType rhs) const noexcept { return OrdinateType{ v - rhs.v }; }
    constexpr OrdinateType mul(OrdinateType rhs) const noexcept { return OrdinateType{ v * rhs.v }; }
    constexpr OrdinateType div(OrdinateType rhs) const noexcept { return OrdinateType{ v / rhs.v }; }

    // binary ops with arithmetic types (int/float) - create an Ordinate and operate
    template<std::integral I>
    constexpr OrdinateType add(I rhs) const noexcept { return add(init_from_int(rhs)); }
    template<std::floating_point F>
    OrdinateType add(F rhs) const noexcept { return add(init_from_float(rhs)); }

    template<std::integral I>
    constexpr OrdinateType sub(I rhs) const noexcept { return sub(init_from_int(rhs)); }
    template<std::floating_point F>
    OrdinateType sub(F rhs) const noexcept { return sub(init_from_float(rhs)); }

    template<std::integral I>
    constexpr OrdinateType mul(I rhs) const noexcept { return mul(init_from_int(rhs)); }
    template<std::floating_point F>
    OrdinateType mul(F rhs) const noexcept { return mul(init_from_float(rhs)); }

    template<std::integral I>
    constexpr OrdinateType div(I rhs) const noexcept { return div(init_from_int(rhs)); }
    template<std::floating_point F>
    OrdinateType div(F rhs) const noexcept { return div(init_from_float(rhs)); }

    // In OrdinateType pow(ExpT exp), we dispatch based on ExpT:
    // 1. If ExpT is floating point, we use ADL/std::pow.
    // 2. Otherwise, we try to use T::pow(ExpT) if it exists.
    // 3. Otherwise, we static_assert.
    template<typename ExpT>
    OrdinateType pow(ExpT exp) const noexcept {
        using std::pow;

        // 1. If the exponent is a floating-point type, we check the base type T.
        if constexpr (std::is_floating_point_v<ExpT>) {
            
            // 1a. If the base type T is also a standard floating point (e.g., float, double).
            if constexpr (std::is_floating_point_v<T>) {
                // Use std::pow and cast the result back to T (e.g., double result to float T)
                // This handles the narrowing conversion error for float/double.
                return OrdinateType{ static_cast<T>(pow(v, exp)) };
            } 
            // 1b. If the base type T is a custom type (like Dual).
            else if constexpr (requires { pow(v, exp); }) { 
                // We rely on unqualified 'pow(v, exp)' to find the custom friend function 
                // via ADL. This branch is now prioritized over implicit conversion 
                // to 'double' for custom types.
                return OrdinateType{ pow(v, exp) }; 
            } else {
                 static_assert(false, "Custom type T does not have a non-member overload for pow(T, ExpT) callable via ADL for a floating-point exponent.");
                 return OrdinateType{ T(0) };
            }
        }
        // 2. If the exponent is a custom type, check if the underlying base type T has a member 'pow'.
        else if constexpr (requires { v.pow(exp); }) {
            return OrdinateType{ v.pow(exp) };
        }
        // 3. Otherwise, static_assert to fail compilation.
        else {
             static_assert(std::is_floating_point_v<ExpT> || requires { v.pow(exp); }, 
                           "OrdinateType::pow(ExpT exp): Exponent is not floating-point, and BaseType T does not provide a custom pow(ExpT) method.");
             return OrdinateType{ T(0) };
        }
    }

    // min/max - for Ordinate or arithmetic
    constexpr OrdinateType min(OrdinateType rhs) const noexcept { return OrdinateType{ v < rhs.v ? v : rhs.v }; }
    template<arithmetic U> OrdinateType min(U rhs) const noexcept { return min(init(rhs)); }

    constexpr OrdinateType max(OrdinateType rhs) const noexcept { return OrdinateType{ v > rhs.v ? v : rhs.v }; }
    template<arithmetic U> OrdinateType max(U rhs) const noexcept { return max(init(rhs)); }

    // comparisons
    constexpr bool eql(OrdinateType rhs) const noexcept { return v == rhs.v; }
    template<arithmetic U> constexpr bool eql(U rhs) const noexcept { return v == init(rhs).v; }

    // approximate equality uses EPSILON
    bool eql_approx(OrdinateType rhs) const noexcept {
        // handle NaN cases: consider NaN == NaN true to match zig behavior in tests
        if (is_nan() && rhs.is_nan()) return true;
        auto eps = EPSILON().v;
        return (v < rhs.v + eps) && (v > rhs.v - eps);
    }
    template<arithmetic U>
    bool eql_approx(U rhs) const noexcept { return eql_approx(init(rhs)); }

    constexpr bool lt(OrdinateType rhs) const noexcept { return v < rhs.v; }
    template<arithmetic U> constexpr bool lt(U rhs) const noexcept { return v < init(rhs).v; }

    constexpr bool lteq(OrdinateType rhs) const noexcept { return v <= rhs.v; }
    template<arithmetic U> constexpr bool lteq(U rhs) const noexcept { return v <= init(rhs).v; }

    constexpr bool gt(OrdinateType rhs) const noexcept { return v > rhs.v; }
    template<arithmetic U> constexpr bool gt(U rhs) const noexcept { return v > init(rhs).v; }

    constexpr bool gteq(OrdinateType rhs) const noexcept { return v >= rhs.v; }
    template<arithmetic U> constexpr bool gteq(U rhs) const noexcept { return v >= init(rhs).v; }

    // NaN/Inf/Finite checks
    bool is_nan() const noexcept {
        if constexpr (std::is_floating_point_v<T>) return std::isnan(v);
        else return false;
    }
    bool is_inf() const noexcept {
        if constexpr (std::is_floating_point_v<T>) return std::isinf(v);
        else return false;
    }
    bool is_finite() const noexcept {
        if constexpr (std::is_floating_point_v<T>) return std::isfinite(v);
        else return true;
    }
}; // OrdinateImpl

// Free helper wrappers that dispatch based on whether the type is Ordinate-like
template<typename A>
inline auto abs(A const& x) {
    if constexpr (requires { x.abs(); }) return x.abs();
    else return std::abs(x);
}

template<typename A, typename B>
inline auto min(A const& a, B const& b) {
    if constexpr (requires { a.min(b); }) return a.min(b);
    else return std::min(a, b);
}

template<typename A, typename B>
inline auto max(A const& a, B const& b) {
    if constexpr (requires { a.max(b); }) return a.max(b);
    else return std::max(a, b);
}

template<typename A, typename B>
inline bool eql(A const& a, B const& b) {
    if constexpr (requires { a.eql(b); }) return a.eql(b);
    else return a == b;
}

template<typename A, typename B>
inline bool eql_approx(A const& a, B const& b) {
    if constexpr (requires { a.eql_approx(b); }) return a.eql_approx(b);
    else {
        // fall back to approximate compare for floating types
        if constexpr (std::is_floating_point_v<std::decay_t<decltype(a)>> || std::is_floating_point_v<std::decay_t<decltype(b)>>) {
            double ad = static_cast<double>(a);
            double bd = static_cast<double>(b);
            double eps = 1e-6;
            return (ad < bd + eps) && (ad > bd - eps);
        } else {
            return a == b;
        }
    }
}

template<typename A, typename B>
inline bool lt(A const& a, B const& b) {
    if constexpr (requires { a.lt(b); }) return a.lt(b);
    else return a < b;
}
template<typename A, typename B>
inline bool lteq(A const& a, B const& b) {
    if constexpr (requires { a.lteq(b); }) return a.lteq(b);
    else return a <= b;
}
template<typename A, typename B>
inline bool gt(A const& a, B const& b) {
    if constexpr (requires { a.gt(b); }) return a.gt(b);
    else return a > b;
}
template<typename A, typename B>
inline bool gteq(A const& a, B const& b) {
    if constexpr (requires { a.gteq(b); }) return a.gteq(b);
    else return a >= b;
}
