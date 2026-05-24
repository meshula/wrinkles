#pragma once
#include "../opentime/interval.hpp"
#include "../opentime/projection_result.hpp"
#include <array>
#include <optional>

// Type aliases for convenience
using Ordinate = OrdinateImpl<double>;
using ContinuousInterval = ContinuousIntervalImpl<Ordinate>;
using ProjectionResult = ProjectionResultImpl<Ordinate>;

// MappingEmpty: A mapping that maps to no values
//
// Ported from wrinkles/src/topology/mapping_empty.zig

/// Regardless what the input ordinate is, there is no value mapped to it.
/// The empty mapping always returns OutOfBounds for projection operations.
struct MappingEmpty {
    /// Represents the input range (and effective output range) of the mapping
    ContinuousInterval defined_range = ContinuousInterval::ZERO();

    // ---- Construction ----

    constexpr MappingEmpty() = default;

    constexpr MappingEmpty(ContinuousInterval range)
        : defined_range(range) {}

    static constexpr MappingEmpty init(ContinuousInterval range) noexcept {
        return MappingEmpty{range};
    }

    // ---- Projection Operations ----

    /// Project an ordinate from input to output space
    /// Always returns OutOfBounds for empty mappings
    constexpr ProjectionResult project_instantaneous_cc(
        Ordinate const& /* ord */
    ) const noexcept {
        return ProjectionResult::out_of_bounds();
    }

    /// Project an ordinate from output to input space
    /// Always returns OutOfBounds for empty mappings
    constexpr ProjectionResult project_instantaneous_cc_inv(
        Ordinate const& /* ord */
    ) const noexcept {
        return ProjectionResult::out_of_bounds();
    }

    // ---- Bounds Operations ----

    /// Get input bounds of the mapping
    constexpr ContinuousInterval input_bounds() const noexcept {
        return defined_range;
    }

    /// Get output bounds of the mapping
    constexpr ContinuousInterval output_bounds() const noexcept {
        return defined_range;
    }

    // ---- Transformation Operations ----

    /// Clone (deep copy) this mapping
    constexpr MappingEmpty clone() const noexcept {
        return *this;
    }

    /// Return inverted mapping (for empty, returns self)
    constexpr MappingEmpty inverted() const noexcept {
        return *this;
    }

    /// Shrink the mapping to the target input interval
    /// Returns nullopt if there is no intersection
    constexpr std::optional<MappingEmpty> shrink_to_input_interval(
        ContinuousInterval const& target_range
    ) const noexcept {
        auto maybe_new_range = intersect(defined_range, target_range);
        if (maybe_new_range.has_value()) {
            return MappingEmpty{*maybe_new_range};
        }
        return std::nullopt;
    }

    /// For the empty mapping, return self - no output interval to shrink
    constexpr MappingEmpty shrink_to_output_interval(
        ContinuousInterval const& /* target_range */
    ) const noexcept {
        return *this;
    }

    /// Split the empty mapping at a point in its input space
    /// Returns two empty mappings with the defined range split at the point
    constexpr std::array<MappingEmpty, 2> split_at_input_point(
        Ordinate const& pt
    ) const noexcept {
        return {
            MappingEmpty{
                ContinuousInterval{defined_range.start, pt}
            },
            MappingEmpty{
                ContinuousInterval{pt, defined_range.end}
            }
        };
    }

    // ---- Stream Output ----

    friend std::ostream& operator<<(std::ostream& os, MappingEmpty const& m) {
        os << "MappingEmpty{" << m.defined_range << "}";
        return os;
    }
};

// ============================================================================
// Constants
// ============================================================================

/// Empty mapping with zero range
inline constexpr MappingEmpty EMPTY_INF = MappingEmpty{ContinuousInterval::ZERO()};
