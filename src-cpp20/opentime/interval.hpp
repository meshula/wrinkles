#pragma once
#include "ordinate.hpp"
#include <optional>
#include <iostream>
#include <stdexcept>

// ContinuousInterval: Right-open interval [start, end) in a continuous metric space.
// Template parameter OrdinateT should be an Ordinate-like type (e.g., OrdinateImpl<double>).
template<typename OrdinateT>
struct ContinuousIntervalImpl {
    using IntervalType = ContinuousIntervalImpl<OrdinateT>;
    using Ordinate = OrdinateT;

    // Member data with defaults matching Zig: start=0, end=INF
    Ordinate start = Ordinate::ZERO();
    Ordinate end = Ordinate::INF();

    // Static constants
    static constexpr IntervalType INF() noexcept {
        return IntervalType{ Ordinate::INF_NEG(), Ordinate::INF() };
    }

    static constexpr IntervalType ZERO() noexcept {
        return IntervalType{ Ordinate::ZERO(), Ordinate::ZERO() };
    }

    // Default constructor
    constexpr ContinuousIntervalImpl() = default;

    // Direct construction from ordinates
    constexpr ContinuousIntervalImpl(Ordinate s, Ordinate e) noexcept
        : start(s), end(e) {}

    // init() factory matching Zig pattern - construct from base types
    template<typename T>
    static constexpr IntervalType init(T start_val, T end_val) noexcept {
        return IntervalType{
            Ordinate::init(start_val),
            Ordinate::init(end_val)
        };
    }

    // from_start_duration() factory
    static IntervalType from_start_duration(Ordinate start_val, Ordinate duration) {
        if (duration.lteq(0)) {
            throw std::invalid_argument("duration <= 0");
        }
        return IntervalType{ start_val, start_val.add(duration) };
    }

    // duration() - compute interval duration
    Ordinate duration() const noexcept {
        if (is_infinite()) {
            return Ordinate::INF();
        }
        return end.sub(start);
    }

    // overlaps() - check if ordinate is within interval [start, end)
    constexpr bool overlaps(Ordinate ord) const noexcept {
        return (
            (is_instant() && start.eql(ord))
            ||
            (ord.gteq(start) && ord.lt(end))
        );
    }

    // is_infinite() - check if either endpoint is infinite
    constexpr bool is_infinite() const noexcept {
        return start.is_inf() || end.is_inf();
    }

    // is_instant() - check if start == end (collapsed interval)
    constexpr bool is_instant() const noexcept {
        return start.eql(end);
    }

    // Stream output
    friend std::ostream& operator<<(std::ostream& os, IntervalType const& interval) {
        os << "c@[" << interval.start << ", " << interval.end << ")";
        return os;
    }

    // Equality for testing
    constexpr bool operator==(IntervalType const& other) const noexcept {
        return start.eql(other.start) && end.eql(other.end);
    }
};

// Free functions

// extend() - return interval spanning both arguments
template<typename OrdinateT>
constexpr ContinuousIntervalImpl<OrdinateT> extend(
    ContinuousIntervalImpl<OrdinateT> const& fst,
    ContinuousIntervalImpl<OrdinateT> const& snd
) noexcept {
    return {
        min(fst.start, snd.start),
        max(fst.end, snd.end)
    };
}

// any_overlap() - check if intervals have any overlap
template<typename OrdinateT>
constexpr bool any_overlap(
    ContinuousIntervalImpl<OrdinateT> const& fst,
    ContinuousIntervalImpl<OrdinateT> const& snd
) noexcept {
    bool const fst_is_instant = fst.is_instant();
    bool const snd_is_instant = snd.is_instant();

    return (
        // Case: fst is instant point within snd
        (fst_is_instant && fst.start.gteq(snd.start) && fst.start.lt(snd.end))
        ||
        // Case: snd is instant point within fst
        (snd_is_instant && snd.start.gteq(fst.start) && snd.start.lt(fst.end))
        ||
        // Case: both are instant at same point
        (fst_is_instant && snd_is_instant && fst.start.eql(snd.start))
        ||
        // General case: intervals overlap
        (fst.start.lt(snd.end) && fst.end.gt(snd.start))
    );
}

// intersect() - return intersection or nullopt if disjoint
template<typename OrdinateT>
constexpr std::optional<ContinuousIntervalImpl<OrdinateT>> intersect(
    ContinuousIntervalImpl<OrdinateT> const& fst,
    ContinuousIntervalImpl<OrdinateT> const& snd
) noexcept {
    if (!any_overlap(fst, snd)) {
        return std::nullopt;
    }

    return ContinuousIntervalImpl<OrdinateT>{
        max(fst.start, snd.start),
        min(fst.end, snd.end)
    };
}


