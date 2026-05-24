#pragma once
#include "../opentime/interval.hpp"
#include "../opentime/projection_result.hpp"
#include "../curve/linear_curve.hpp"
#include "../curve/control_point.hpp"
#include <vector>
#include <optional>

// MappingCurveLinearMonotonic: Linear curve-based mapping
//
// Ported from wrinkles/src/topology/mapping_curve_linear.zig

// Type aliases for convenience
using Ordinate = OrdinateImpl<double>;
using ContinuousInterval = ContinuousIntervalImpl<Ordinate>;
using ProjectionResult = ProjectionResultImpl<Ordinate>;
using ControlPoint = ControlPointOf<Ordinate>;
using LinearMonotonic = LinearOf<ControlPoint>::Monotonic;

/// A linear mapping from input to output based on a monotonic piecewise linear curve
struct MappingCurveLinearMonotonic {
    LinearMonotonic input_to_output_curve;

    // ---- Construction ----

    MappingCurveLinearMonotonic() = default;

    MappingCurveLinearMonotonic(LinearMonotonic curve)
        : input_to_output_curve(std::move(curve)) {}

    static MappingCurveLinearMonotonic init_knots(
        std::vector<ControlPoint> const& knots
    ) {
        return MappingCurveLinearMonotonic{LinearMonotonic{knots}};
    }

    static MappingCurveLinearMonotonic init_curve(
        LinearMonotonic const& crv
    ) {
        return MappingCurveLinearMonotonic{crv.clone()};
    }

    // ---- Projection Operations ----

    /// Project an ordinate from input to output space
    ProjectionResult project_instantaneous_cc(
        Ordinate const& input_ordinate
    ) const noexcept {
        return input_to_output_curve.output_at_input(input_ordinate);
    }

    /// Project an ordinate from output space back to input space
    /// Simplified inverse projection - finds input for given output
    ProjectionResult project_instantaneous_cc_inv(
        Ordinate const& output_ordinate
    ) const noexcept {
        // Search through knots to find segment containing output
        auto const& knots = input_to_output_curve.knots;

        if (knots.empty()) {
            return ProjectionResult::out_of_bounds();
        }

        // Check if output is at endpoints
        if (output_ordinate.eql(knots.front().out)) {
            return ProjectionResult::success_ordinate(knots.front().in);
        }
        if (output_ordinate.eql(knots.back().out)) {
            return ProjectionResult::success_ordinate(knots.back().in);
        }

        // Search for segment containing output
        for (size_t i = 0; i < knots.size() - 1; ++i) {
            auto const& k1 = knots[i];
            auto const& k2 = knots[i + 1];

            // Check if output is within this segment's output range
            bool in_range;
            if (k1.out.lt(k2.out)) {
                in_range = k1.out.lteq(output_ordinate) && output_ordinate.lteq(k2.out);
            } else {
                in_range = k2.out.lteq(output_ordinate) && output_ordinate.lteq(k1.out);
            }

            if (in_range) {
                // Interpolate to find input
                auto t = invlerp(output_ordinate, k1.out, k2.out);
                auto input = lerp(t, k1.in, k2.in);
                return ProjectionResult::success_ordinate(input);
            }
        }

        return ProjectionResult::out_of_bounds();
    }

    // ---- Bounds Operations ----

    /// Get input bounds of the mapping
    ContinuousInterval input_bounds() const noexcept {
        return input_to_output_curve.extents_input();
    }

    /// Get output bounds of the mapping
    ContinuousInterval output_bounds() const noexcept {
        return input_to_output_curve.extents_output();
    }

    // ---- Transformation Operations ----

    /// Clone (deep copy) this mapping
    MappingCurveLinearMonotonic clone() const {
        return MappingCurveLinearMonotonic{input_to_output_curve.clone()};
    }

    /// Shrink the mapping to the target input interval
    /// Returns a new mapping with curve trimmed to the interval
    MappingCurveLinearMonotonic shrink_to_input_interval(
        ContinuousInterval const& target_interval
    ) const {
        // Find intersection with our bounds
        auto our_bounds = input_bounds();
        auto maybe_new_bounds = intersect(our_bounds, target_interval);

        if (!maybe_new_bounds.has_value()) {
            // No intersection - return empty curve
            return MappingCurveLinearMonotonic{LinearMonotonic{}};
        }

        auto new_bounds = *maybe_new_bounds;
        std::vector<ControlPoint> new_knots;

        // Add knot at start if needed
        if (!new_bounds.start.eql(input_to_output_curve.knots.front().in)) {
            auto output = input_to_output_curve.output_at_input(new_bounds.start);
            if (!output.is_out_of_bounds()) {
                new_knots.push_back(ControlPoint{new_bounds.start, output.ordinate()});
            }
        }

        // Add knots within the range
        for (auto const& knot : input_to_output_curve.knots) {
            if (knot.in.gteq(new_bounds.start) && knot.in.lteq(new_bounds.end)) {
                new_knots.push_back(knot);
            }
        }

        // Add knot at end if needed
        if (!new_bounds.end.eql(input_to_output_curve.knots.back().in)) {
            auto output = input_to_output_curve.output_at_input(new_bounds.end);
            if (!output.is_out_of_bounds()) {
                new_knots.push_back(ControlPoint{new_bounds.end, output.ordinate()});
            }
        }

        return MappingCurveLinearMonotonic{LinearMonotonic{std::move(new_knots)}};
    }

    /// Shrink the mapping to the target output interval
    /// Projects target back to input space, then trims
    MappingCurveLinearMonotonic shrink_to_output_interval(
        ContinuousInterval const& target_output_interval
    ) const {
        std::vector<ControlPoint> new_knots;
        auto const& knots = input_to_output_curve.knots;

        if (knots.empty()) {
            return MappingCurveLinearMonotonic{LinearMonotonic{}};
        }

        // Find knots within output range and add trimmed endpoints
        for (size_t i = 0; i < knots.size(); ++i) {
            auto const& knot = knots[i];

            // Check if this knot's output is within target range
            if (knot.out.gteq(target_output_interval.start) &&
                knot.out.lteq(target_output_interval.end)) {
                new_knots.push_back(knot);
            }

            // Check for segment crossings with target boundaries
            if (i < knots.size() - 1) {
                auto const& next_knot = knots[i + 1];

                // Check if segment crosses start boundary
                if ((knot.out.lt(target_output_interval.start) && next_knot.out.gt(target_output_interval.start)) ||
                    (knot.out.gt(target_output_interval.start) && next_knot.out.lt(target_output_interval.start))) {
                    auto t = invlerp(target_output_interval.start, knot.out, next_knot.out);
                    auto input = lerp(t, knot.in, next_knot.in);
                    new_knots.insert(new_knots.begin(), ControlPoint{input, target_output_interval.start});
                }

                // Check if segment crosses end boundary
                if ((knot.out.lt(target_output_interval.end) && next_knot.out.gt(target_output_interval.end)) ||
                    (knot.out.gt(target_output_interval.end) && next_knot.out.lt(target_output_interval.end))) {
                    auto t = invlerp(target_output_interval.end, knot.out, next_knot.out);
                    auto input = lerp(t, knot.in, next_knot.in);
                    new_knots.push_back(ControlPoint{input, target_output_interval.end});
                }
            }
        }

        return MappingCurveLinearMonotonic{LinearMonotonic{std::move(new_knots)}};
    }

    /// Split the linear mapping at a point in its input space
    std::array<MappingCurveLinearMonotonic, 2> split_at_input_point(
        Ordinate const& pt_input
    ) const {
        std::vector<ControlPoint> left_knots;
        std::vector<ControlPoint> right_knots;

        auto const& start_knots = input_to_output_curve.knots;

        for (size_t k_ind = 1; k_ind < start_knots.size(); ++k_ind) {
            auto const& k = start_knots[k_ind];

            if (k.in.eql(pt_input)) {
                // Split point is exactly at a knot
                left_knots.insert(left_knots.end(), start_knots.begin(), start_knots.begin() + k_ind + 1);
                right_knots.insert(right_knots.end(), start_knots.begin() + k_ind, start_knots.end());
                break;
            }

            if (k.in.gt(pt_input)) {
                // Split point is between knots - need to interpolate
                auto output_result = input_to_output_curve.output_at_input(pt_input);
                if (!output_result.is_out_of_bounds()) {
                    auto new_knot = ControlPoint{pt_input, output_result.ordinate()};

                    left_knots.insert(left_knots.end(), start_knots.begin(), start_knots.begin() + k_ind);
                    left_knots.push_back(new_knot);

                    right_knots.push_back(new_knot);
                    right_knots.insert(right_knots.end(), start_knots.begin() + k_ind, start_knots.end());
                }
                break;
            }
        }

        return {
            MappingCurveLinearMonotonic{LinearMonotonic{std::move(left_knots)}},
            MappingCurveLinearMonotonic{LinearMonotonic{std::move(right_knots)}}
        };
    }

    // ---- Stream Output ----

    friend std::ostream& operator<<(std::ostream& os, MappingCurveLinearMonotonic const& m) {
        os << "MappingCurveLinearMonotonic{knots=" << m.input_to_output_curve.knots.size() << "}";
        return os;
    }
};
