#pragma once
#include "ordinate.hpp"
#include "interval.hpp"
#include <variant>
#include <stdexcept>
#include <iostream>

// ProjectionResult: Result of a projection operation
// Can be:
//   - SuccessOrdinate: Single point result
//   - SuccessInterval: Range result
//   - OutOfBounds: Projection failed (out of bounds)

// Custom exceptions matching Zig error types
struct NotAnOrdinateResult : std::exception {
    const char* what() const noexcept override {
        return "ProjectionResult is not an ordinate";
    }
};

struct NotAnIntervalResult : std::exception {
    const char* what() const noexcept override {
        return "ProjectionResult is not an interval";
    }
};

struct OutOfBoundsError : std::exception {
    const char* what() const noexcept override {
        return "ProjectionResult is out of bounds";
    }
};

// Marker type for OutOfBounds variant
struct OutOfBoundsTag {};

template<typename OrdinateT>
struct ProjectionResultImpl {
    using Ordinate = OrdinateT;
    using Interval = ContinuousIntervalImpl<Ordinate>;
    using ResultType = ProjectionResultImpl<Ordinate>;

    // Variant holding the three possible states
    std::variant<Ordinate, Interval, OutOfBoundsTag> value;

    // Constructors for each variant
    static constexpr ResultType success_ordinate(Ordinate ord) noexcept {
        return ResultType{ std::variant<Ordinate, Interval, OutOfBoundsTag>(ord) };
    }

    static constexpr ResultType success_interval(Interval intv) noexcept {
        return ResultType{ std::variant<Ordinate, Interval, OutOfBoundsTag>(intv) };
    }

    static constexpr ResultType out_of_bounds() noexcept {
        return ResultType{ std::variant<Ordinate, Interval, OutOfBoundsTag>(OutOfBoundsTag{}) };
    }

    // Type queries
    constexpr bool is_ordinate() const noexcept {
        return std::holds_alternative<Ordinate>(value);
    }

    constexpr bool is_interval() const noexcept {
        return std::holds_alternative<Interval>(value);
    }

    constexpr bool is_out_of_bounds() const noexcept {
        return std::holds_alternative<OutOfBoundsTag>(value);
    }

    // Accessor methods (throw on wrong type, matching Zig error semantics)
    Ordinate ordinate() const {
        if (is_out_of_bounds()) {
            throw OutOfBoundsError{};
        }
        if (!is_ordinate()) {
            throw NotAnOrdinateResult{};
        }
        return std::get<Ordinate>(value);
    }

    Interval interval() const {
        if (is_out_of_bounds()) {
            throw OutOfBoundsError{};
        }
        if (!is_interval()) {
            throw NotAnIntervalResult{};
        }
        return std::get<Interval>(value);
    }

    // Safe accessors returning std::optional
    std::optional<Ordinate> ordinate_safe() const noexcept {
        if (is_ordinate()) {
            return std::get<Ordinate>(value);
        }
        return std::nullopt;
    }

    std::optional<Interval> interval_safe() const noexcept {
        if (is_interval()) {
            return std::get<Interval>(value);
        }
        return std::nullopt;
    }

    // Stream output
    friend std::ostream& operator<<(std::ostream& os, ResultType const& result) {
        std::visit([&os](auto&& arg) {
            using T = std::decay_t<decltype(arg)>;
            if constexpr (std::is_same_v<T, Ordinate>) {
                os << "ProjResult{ .ordinate = " << arg << " }";
            } else if constexpr (std::is_same_v<T, Interval>) {
                os << "ProjResult{ .interval = " << arg << " }";
            } else if constexpr (std::is_same_v<T, OutOfBoundsTag>) {
                os << "ProjResult{ .OutOfBounds }";
            }
        }, result.value);
        return os;
    }
};

// Convenience constant
template<typename OrdinateT>
inline constexpr auto OUTOFBOUNDS = ProjectionResultImpl<OrdinateT>::out_of_bounds();
