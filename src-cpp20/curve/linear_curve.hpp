#pragma once
#include "control_point.hpp"
#include "bezier_math.hpp"
#include "../opentime/interval.hpp"
#include "../opentime/projection_result.hpp"
#include <vector>
#include <optional>
#include <algorithm>

// Linear curves are made of right-met connected line segments
//
// Ported from wrinkles/src/curve/linear_curve.zig

// ============================================================================
// LinearOf - Piecewise linear curve template
// ============================================================================

template<typename ControlPointType>
struct LinearOf {
    using OrdinateType = typename ControlPointType::OrdinateType;
    using LinearType = LinearOf<ControlPointType>;
    using Interval = ContinuousIntervalImpl<OrdinateType>;
    using ProjectionResult = ProjectionResultImpl<OrdinateType>;

    std::vector<ControlPointType> knots;

    // ---- Construction ----

    constexpr LinearOf() = default;
    constexpr LinearOf(std::vector<ControlPointType> knots_) : knots(std::move(knots_)) {}

    // ========================================================================
    // Monotonic - Immutable monotonic form of the Linear curve
    // ========================================================================

    struct Monotonic {
        std::vector<ControlPointType> knots;

        // ---- Memory Management ----

        Monotonic() = default;
        Monotonic(std::vector<ControlPointType> knots_) : knots(std::move(knots_)) {}

        Monotonic clone() const {
            return Monotonic{knots};
        }

        // ---- Extents ----

        /// Compute both the input and output extents for the curve
        /// Returns [min, max] control points
        std::array<ControlPointType, 2> extents() const noexcept {
            if (knots.empty()) {
                return {ControlPointType::ZERO(), ControlPointType::ZERO()};
            }

            auto min = knots[0];
            auto max = knots[0];

            for (auto const& knot : {knots.front(), knots.back()}) {
                // Update min
                if constexpr (requires { knot.in.lt(min.in); }) {
                    if (knot.in.lt(min.in)) min.in = knot.in;
                    if (knot.out.lt(min.out)) min.out = knot.out;
                } else {
                    if (knot.in < min.in) min.in = knot.in;
                    if (knot.out < min.out) min.out = knot.out;
                }

                // Update max
                if constexpr (requires { knot.in.gt(max.in); }) {
                    if (knot.in.gt(max.in)) max.in = knot.in;
                    if (knot.out.gt(max.out)) max.out = knot.out;
                } else {
                    if (knot.in > max.in) max.in = knot.in;
                    if (knot.out > max.out) max.out = knot.out;
                }
            }

            return {min, max};
        }

        /// Compute input extents for the curve
        Interval extents_input() const noexcept {
            if (knots.empty()) {
                return Interval::ZERO();
            }

            auto fst = knots.front().in;
            auto lst = knots.back().in;

            if constexpr (requires { fst.lt(lst); }) {
                return Interval{
                    fst.lt(lst) ? fst : lst,
                    fst.gt(lst) ? fst : lst
                };
            } else {
                return Interval{
                    std::min(fst, lst),
                    std::max(fst, lst)
                };
            }
        }

        /// Compute output extents for the curve
        Interval extents_output() const noexcept {
            if (knots.empty()) {
                return Interval::ZERO();
            }

            auto fst = knots.front().out;
            auto lst = knots.back().out;

            if constexpr (requires { fst.lt(lst); }) {
                return Interval{
                    fst.lt(lst) ? fst : lst,
                    fst.gt(lst) ? fst : lst
                };
            } else {
                return Interval{
                    std::min(fst, lst),
                    std::max(fst, lst)
                };
            }
        }

        /// Get the slope kind of the curve
        SlopeKind slope_kind() const noexcept {
            if (knots.size() < 2) {
                return SlopeKind::flat;
            }
            return compute_slope_kind(knots.front(), knots.back());
        }

        // ---- Projection Operations ----

        /// Find the index of the knot with input ordinate less than or equal to input_ord
        /// Returns nullopt if out of bounds
        std::optional<size_t> nearest_smaller_knot_index_input(
            OrdinateType const& input_ord
        ) const noexcept {
            if (knots.empty()) {
                return std::nullopt;
            }

            size_t last_index = knots.size() - 1;

            // Check bounds
            if constexpr (requires { input_ord.lt(knots[0].in); }) {
                if (input_ord.lt(knots[0].in) || input_ord.gteq(knots[last_index].in)) {
                    return std::nullopt;
                }
            } else {
                if (input_ord < knots[0].in || input_ord >= knots[last_index].in) {
                    return std::nullopt;
                }
            }

            // Find the knot
            for (size_t i = 0; i < last_index; ++i) {
                bool in_range;
                if constexpr (requires { knots[i].in.lteq(input_ord); }) {
                    in_range = knots[i].in.lteq(input_ord) && input_ord.lt(knots[i + 1].in);
                } else {
                    in_range = (knots[i].in <= input_ord) && (input_ord < knots[i + 1].in);
                }

                if (in_range) {
                    return i;
                }
            }

            return std::nullopt;
        }

        /// Compute output ordinate at given input ordinate
        ProjectionResult output_at_input(
            OrdinateType const& input_ord
        ) const noexcept {
            auto slope = slope_kind();

            // Handle flat case
            if constexpr (requires { extents_input().overlaps(input_ord); }) {
                if (slope == SlopeKind::flat && extents_input().overlaps(input_ord)) {
                    auto self_ob = extents_output();
                    if (self_ob.is_instant()) {
                        return ProjectionResult::success_ordinate(self_ob.start);
                    }
                    return ProjectionResult::success_interval(self_ob);
                }
            }

            // Find the segment containing input_ord
            if (auto index = nearest_smaller_knot_index_input(input_ord)) {
                return ProjectionResult::success_ordinate(
                    output_at_input_between(
                        input_ord,
                        knots[*index],
                        knots[*index + 1]
                    )
                );
            }

            // Handle endpoints
            if (knots.size() > 0) {
                auto const& last_knot = knots.back();
                if constexpr (requires { input_ord.eql(last_knot.in); }) {
                    if (input_ord.eql(last_knot.in)) {
                        return ProjectionResult::success_ordinate(last_knot.out);
                    }
                    if (input_ord.eql(knots.front().in)) {
                        return ProjectionResult::success_ordinate(knots.front().out);
                    }
                } else {
                    if (input_ord == last_knot.in) {
                        return ProjectionResult::success_ordinate(last_knot.out);
                    }
                    if (input_ord == knots.front().in) {
                        return ProjectionResult::success_ordinate(knots.front().out);
                    }
                }
            }

            return ProjectionResult::out_of_bounds();
        }
    };
};

// ============================================================================
// Default Linear Type
// ============================================================================

using Linear = LinearOf<ControlPoint>;
