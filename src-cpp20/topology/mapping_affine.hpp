#pragma once
#include "../opentime/interval.hpp"
#include "../opentime/projection_result.hpp"
#include "../opentime/transform.hpp"
#include <array>
#include <optional>
#include <vector>

// MappingAffine: Affine transformation mapping
//
// Ported from wrinkles/src/topology/mapping_affine.zig

// Type aliases for convenience
using Ordinate = OrdinateImpl<double>;
using ContinuousInterval = ContinuousIntervalImpl<Ordinate>;
using ProjectionResult = ProjectionResultImpl<Ordinate>;
using AffineTransform1D = AffineTransform1DImpl<Ordinate>;

/// An affine mapping from input to output space
/// Transforms ordinates via: f(x) = scale * x + offset
struct MappingAffine {
    /// Input bounds (defaults to infinite)
    ContinuousInterval input_bounds_val = ContinuousInterval::INF();

    /// Affine transformation (defaults to identity)
    AffineTransform1D input_to_output_xform = AffineTransform1D::IDENTITY();

    // ---- Construction ----

    constexpr MappingAffine() = default;

    constexpr MappingAffine(
        ContinuousInterval bounds,
        AffineTransform1D xform
    ) : input_bounds_val(bounds),
        input_to_output_xform(xform) {}

    static constexpr MappingAffine init(
        ContinuousInterval bounds,
        AffineTransform1D xform
    ) noexcept {
        return MappingAffine{bounds, xform};
    }

    // ---- Projection Operations ----

    /// Project an ordinate from input to output space
    /// Checks bounds, allowing projection of the end point
    constexpr ProjectionResult project_instantaneous_cc(
        Ordinate const& ordinate
    ) const noexcept {
        // Check if ordinate is within bounds or at the end point
        if (!input_bounds_val.overlaps(ordinate) &&
            !ordinate.eql(input_bounds_val.end)) {
            return ProjectionResult::out_of_bounds();
        }

        return ProjectionResult::success_ordinate(
            input_to_output_xform.applied_to_ordinate(ordinate)
        );
    }

    /// Project an ordinate from output space back to input space
    /// Checks output bounds, allowing projection of the end point
    constexpr ProjectionResult project_instantaneous_cc_inv(
        Ordinate const& output_ordinate
    ) const noexcept {
        auto out_bounds = output_bounds();

        // Check if ordinate is within output bounds or at the end point
        if (!out_bounds.overlaps(output_ordinate) &&
            !output_ordinate.eql(out_bounds.end)) {
            return ProjectionResult::out_of_bounds();
        }

        return ProjectionResult::success_ordinate(
            input_to_output_xform.inverted().applied_to_ordinate(output_ordinate)
        );
    }

    // ---- Bounds Operations ----

    /// Get input bounds of the mapping
    constexpr ContinuousInterval input_bounds() const noexcept {
        return input_bounds_val;
    }

    /// Get output bounds of the mapping
    /// Computed by applying the transform to the input bounds
    constexpr ContinuousInterval output_bounds() const noexcept {
        return input_to_output_xform.applied_to_interval(input_bounds_val);
    }

    // ---- Transformation Operations ----

    /// Clone (deep copy) this mapping
    constexpr MappingAffine clone() const noexcept {
        return *this;
    }

    /// Shrink the mapping to the target input interval
    /// Returns nullopt if there is no overlap
    constexpr std::optional<MappingAffine> shrink_to_input_interval(
        ContinuousInterval const& target_interval
    ) const noexcept {
        auto maybe_new_bounds = intersect(input_bounds_val, target_interval);
        if (!maybe_new_bounds.has_value()) {
            return std::nullopt;
        }

        return MappingAffine{*maybe_new_bounds, input_to_output_xform};
    }

    /// Shrink the mapping to the target output interval
    /// Projects the target back to input space, then intersects
    /// Returns empty interval if no overlap
    constexpr MappingAffine shrink_to_output_interval(
        ContinuousInterval const& target_output_interval
    ) const noexcept {
        // Project target output interval back to input space
        auto target_input_interval = input_to_output_xform.inverted().applied_to_bounds(
            target_output_interval
        );

        // Intersect with current input bounds
        auto maybe_new_bounds = intersect(input_bounds_val, target_input_interval);

        return MappingAffine{
            maybe_new_bounds.value_or(ContinuousInterval::ZERO()),
            input_to_output_xform
        };
    }

    /// Split the affine mapping at a point in its input space
    /// Returns two affine mappings with the same transform but split bounds
    constexpr std::array<MappingAffine, 2> split_at_input_point(
        Ordinate const& pt_input
    ) const noexcept {
        return {
            MappingAffine{
                ContinuousInterval{input_bounds_val.start, pt_input},
                input_to_output_xform
            },
            MappingAffine{
                ContinuousInterval{pt_input, input_bounds_val.end},
                input_to_output_xform
            }
        };
    }

    /// Split at multiple points within the bounds of the mapping
    /// Returns a vector of mappings split at the valid points
    std::vector<MappingAffine> split_at_input_points(
        std::vector<Ordinate> const& input_points
    ) const {
        std::vector<MappingAffine> result_mappings;

        // Find first valid point (within bounds, exclusive of endpoints)
        size_t first_pt_idx = input_points.size();
        for (size_t i = 0; i < input_points.size(); ++i) {
            auto const& pt = input_points[i];
            if (pt.gt(input_bounds_val.start) && pt.lt(input_bounds_val.end)) {
                first_pt_idx = i;
                break;
            }
        }

        // If no valid points, return this mapping unchanged
        if (first_pt_idx == input_points.size()) {
            result_mappings.push_back(*this);
            return result_mappings;
        }

        // Split at each valid point
        auto current_start = input_bounds_val.start;
        size_t current_end_idx = first_pt_idx;

        while (current_end_idx < input_points.size()) {
            auto current_end = input_points[current_end_idx];

            // If point is beyond our bounds, use our end instead and stop
            if (current_end.gt(input_bounds_val.end)) {
                current_end = input_bounds_val.end;
                current_end_idx = input_points.size();
            }

            result_mappings.push_back(
                MappingAffine{
                    ContinuousInterval{current_start, current_end},
                    input_to_output_xform
                }
            );

            current_start = current_end;
            current_end_idx += 1;
        }

        // Add final segment from last split point to end of bounds
        if (current_start.lt(input_bounds_val.end)) {
            result_mappings.push_back(
                MappingAffine{
                    ContinuousInterval{current_start, input_bounds_val.end},
                    input_to_output_xform
                }
            );
        }

        return result_mappings;
    }

    // ---- Stream Output ----

    friend std::ostream& operator<<(std::ostream& os, MappingAffine const& m) {
        os << "MappingAffine{bounds=" << m.input_bounds_val
           << ", xform=(offset=" << m.input_to_output_xform.offset
           << ", scale=" << m.input_to_output_xform.scale << ")}";
        return os;
    }
};

// ============================================================================
// Constants
// ============================================================================

/// Infinite identity mapping (maps all values to themselves)
inline const MappingAffine INFINITE_IDENTITY = MappingAffine{
    ContinuousInterval::INF(),
    AffineTransform1D::IDENTITY()
};
