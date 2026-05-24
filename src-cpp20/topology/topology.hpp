#pragma once
#include "mapping.hpp"
#include <vector>
#include <optional>
#include <algorithm>
#include <set>

// Topology - Sequence of monotonic mappings
//
// A Topology binds regions of a one dimensional space to a sequence of right
// met monotonic mappings, separated by a list of end points. There are
// implicit "Empty" mappings outside of the end points which map to no values
// before and after the mappings contained by the Topology.
//
// Ported from wrinkles/src/topology/root.zig

// Type aliases for convenience
using Ordinate = OrdinateImpl<double>;
using ContinuousInterval = ContinuousIntervalImpl<Ordinate>;
using ProjectionResult = ProjectionResultImpl<Ordinate>;

/// A Topology is a sequence of mappings
struct Topology {
    std::vector<Mapping> mappings;

    // ---- Construction ----

    Topology() = default;

    explicit Topology(std::vector<Mapping> const& in_mappings)
        : mappings(in_mappings) {}

    explicit Topology(std::vector<Mapping>&& in_mappings)
        : mappings(std::move(in_mappings)) {}

    /// Initialize from a vector of mappings
    static Topology init(std::vector<Mapping> const& in_mappings) {
        if (in_mappings.empty()) {
            return Topology{};
        }
        return Topology{in_mappings};
    }

    /// Initialize from a linear monotonic curve
    static Topology init_from_linear_monotonic(LinearMonotonic const& crv) {
        std::vector<Mapping> mappings;
        mappings.push_back(Mapping{MappingCurveLinearMonotonic::init_curve(crv)});
        return Topology{std::move(mappings)};
    }

    /// Initialize from an affine mapping
    static Topology init_affine(MappingAffine const& aff) {
        std::vector<Mapping> mappings;
        mappings.push_back(Mapping{aff});
        return Topology{std::move(mappings)};
    }

    /// Build a topology with a single identity mapping over the specified range
    static Topology init_identity(ContinuousInterval const& range) {
        std::vector<Mapping> mappings;
        mappings.push_back(Mapping{MappingAffine{
            range,
            AffineTransform1D::IDENTITY()
        }});
        return Topology{std::move(mappings)};
    }

    /// Build a topology with a single identity mapping with an infinite range
    static Topology init_identity_infinite() {
        std::vector<Mapping> mappings;
        mappings.push_back(Mapping{MappingAffine{}});
        return Topology{std::move(mappings)};
    }

    // ---- Bounds Operations ----

    /// Get input bounds of the topology
    ContinuousInterval input_bounds() const noexcept {
        if (mappings.empty()) {
            return ContinuousInterval::ZERO();
        }
        return ContinuousInterval{
            ::input_bounds(mappings.front()).start,
            ::input_bounds(mappings.back()).end
        };
    }

    /// Get output bounds of the topology
    ContinuousInterval output_bounds() const noexcept {
        if (mappings.empty()) {
            return ContinuousInterval::ZERO();
        }

        std::optional<ContinuousInterval> bounds;

        for (auto const& m : mappings) {
            // Skip empty mappings
            if (std::holds_alternative<MappingEmpty>(m)) {
                continue;
            }

            auto m_bounds = ::output_bounds(m);

            if (bounds.has_value()) {
                bounds = extend(*bounds, m_bounds);
            } else {
                bounds = m_bounds;
            }
        }

        return bounds.value_or(ContinuousInterval::INF());
    }

    /// Get end points in input space
    std::vector<Ordinate> end_points_input() const {
        if (mappings.empty()) {
            return {};
        }

        std::vector<Ordinate> result;
        result.reserve(mappings.size() + 1);

        result.push_back(::input_bounds(mappings.front()).start);

        for (auto const& m : mappings) {
            result.push_back(::input_bounds(m).end);
        }

        return result;
    }

    /// Get unique end points in output space (ascending sort)
    std::vector<Ordinate> end_points_output() const {
        std::set<Ordinate, decltype([](Ordinate const& a, Ordinate const& b) {
            return a.lt(b);
        })> unique_points;

        for (auto const& m : mappings) {
            auto bounds = ::output_bounds(m);
            unique_points.insert(bounds.start);
            unique_points.insert(bounds.end);
        }

        return std::vector<Ordinate>(unique_points.begin(), unique_points.end());
    }

    // ---- Projection Operations ----

    /// Project an ordinate from input space to output space
    ProjectionResult project_instantaneous_cc(
        Ordinate const& input_ord
    ) const noexcept {
        auto ib = input_bounds();

        // Handle instant intervals
        if (ib.is_instant()) {
            if (ib.start.eql(input_ord)) {
                return ProjectionResult::success_interval(output_bounds());
            }
            return ProjectionResult::out_of_bounds();
        }

        // Find mapping that contains this ordinate
        for (auto const& m : mappings) {
            if (::input_bounds(m).overlaps(input_ord)) {
                return ::project_instantaneous_cc(m, input_ord);
            }
        }

        return ProjectionResult::out_of_bounds();
    }

    /// Project ordinate from output space to input space
    /// Returns vector of ordinates (may have multiple results due to non-monotonicity in reverse)
    std::vector<Ordinate> project_instantaneous_cc_inv(
        Ordinate const& output_ord
    ) const {
        std::vector<Ordinate> input_ordinates;

        for (auto const& m : mappings) {
            auto m_out_bounds = ::output_bounds(m);

            if (m_out_bounds.overlaps(output_ord) ||
                output_ord.eql(m_out_bounds.end)) {

                auto result = ::project_instantaneous_cc_inv(m, output_ord);
                if (!result.is_out_of_bounds()) {
                    input_ordinates.push_back(result.ordinate());
                }
            }
        }

        return input_ordinates;
    }

    // ---- Trimming Operations ----

    /// Trim the topology to the target input interval
    Topology trim_in_input_space(
        ContinuousInterval const& new_input_bounds
    ) const {
        auto ib = input_bounds();
        auto maybe_new_bounds = intersect(new_input_bounds, ib);

        if (!maybe_new_bounds.has_value()) {
            return Topology{};
        }

        auto bounds = *maybe_new_bounds;

        // No trimming needed
        if (bounds.start.lteq(ib.start) && bounds.end.gteq(ib.end)) {
            return clone();
        }

        // Clamp bounds to our range
        bounds.start = max(bounds.start, ib.start);
        bounds.end = min(bounds.end, ib.end);

        // Find which mappings need to be trimmed
        std::optional<size_t> maybe_left_map_ind;
        std::optional<size_t> maybe_right_map_ind;

        auto end_points = end_points_input();

        for (size_t left_ind = 0; left_ind < end_points.size() - 1; ++left_ind) {
            auto left_pt = end_points[left_ind];
            auto right_pt = end_points[left_ind + 1];

            if (left_pt.lt(bounds.start) && right_pt.gt(bounds.start)) {
                maybe_left_map_ind = left_ind;
            }

            if (left_pt.lt(bounds.end) && right_pt.gt(bounds.end)) {
                maybe_right_map_ind = left_ind;
            }
        }

        // Trim the same mapping on both sides
        if (maybe_left_map_ind.has_value() &&
            maybe_right_map_ind.has_value() &&
            maybe_left_map_ind == maybe_right_map_ind) {

            auto mapping_to_trim = mappings[*maybe_left_map_ind];

            // Split at left bound
            auto [left_discard, middle] = ::split_at_input_point(mapping_to_trim, bounds.start);

            // Split middle at right bound
            auto [result, right_discard] = ::split_at_input_point(middle, bounds.end);

            std::vector<Mapping> result_mappings;
            result_mappings.push_back(result);
            return Topology{std::move(result_mappings)};
        }

        // Either only one side is being trimmed, or different mappings
        std::vector<Mapping> trimmed_mappings;

        size_t middle_start = 0;
        size_t middle_end = mappings.size();

        // Trim left side
        if (maybe_left_map_ind.has_value()) {
            auto [left_discard, right] = split_at_input_point(
                mappings[*maybe_left_map_ind],
                bounds.start
            );
            trimmed_mappings.push_back(right);
            middle_start = *maybe_left_map_ind + 1;
        }

        // Copy middle mappings
        if (maybe_right_map_ind.has_value()) {
            middle_end = *maybe_right_map_ind;
        }

        for (size_t i = middle_start; i < middle_end; ++i) {
            trimmed_mappings.push_back(::clone(mappings[i]));
        }

        // Trim right side
        if (maybe_right_map_ind.has_value()) {
            auto [left, right_discard] = split_at_input_point(
                mappings[*maybe_right_map_ind],
                bounds.end
            );
            trimmed_mappings.push_back(left);
        }

        return Topology::init(trimmed_mappings);
    }

    /// Trim in output space, inserting empty mappings where needed
    Topology trim_in_output_space(
        ContinuousInterval const& target_output_range
    ) const {
        auto ob = output_bounds();

        // No trimming needed
        if (target_output_range.start.lteq(ob.start) &&
            target_output_range.end.gteq(ob.end)) {
            return clone();
        }

        std::vector<Mapping> new_mappings;

        for (size_t m_ind = 0; m_ind < mappings.size(); ++m_ind) {
            auto const& m = mappings[m_ind];
            auto m_in_range = ::input_bounds(m);
            auto m_out_range = ::output_bounds(m);

            auto maybe_overlap = intersect(target_output_range, m_out_range);

            if (maybe_overlap.has_value()) {
                // Check if nothing needs to be trimmed
                if (m_out_range.start.gteq(target_output_range.start) &&
                    m_out_range.end.lteq(target_output_range.end)) {
                    new_mappings.push_back(::clone(m));
                    continue;
                }

                // Shrink the mapping
                auto shrunk_m = ::shrink_to_output_interval(m, target_output_range);
                auto shrunk_input_bounds = ::input_bounds(shrunk_m);

                // Add empty left if needed
                if (shrunk_input_bounds.start.gt(m_in_range.start) && m_ind > 0) {
                    new_mappings.push_back(Mapping{MappingEmpty{
                        ContinuousInterval{m_in_range.start, shrunk_input_bounds.start}
                    }});
                }

                // Add trimmed mapping if it has non-zero size
                if (shrunk_input_bounds.start.lt(shrunk_input_bounds.end)) {
                    new_mappings.push_back(shrunk_m);
                }

                // Add empty right if needed
                if (shrunk_input_bounds.end.lt(m_in_range.end) &&
                    m_ind < mappings.size() - 1) {
                    new_mappings.push_back(Mapping{MappingEmpty{
                        ContinuousInterval{shrunk_input_bounds.end, m_in_range.end}
                    }});
                }
            } else {
                // No intersection - replace with empty
                new_mappings.push_back(Mapping{MappingEmpty{m_in_range}});
            }
        }

        return Topology{std::move(new_mappings)};
    }

    // ---- Splitting Operations ----

    /// Split the topology at specified points in input domain
    Topology split_at_input_points(
        std::vector<Ordinate> const& input_points
    ) const {
        auto ib = input_bounds();

        // Early exit if no valid points
        if (input_points.empty() ||
            (input_points.front().gteq(ib.end)) ||
            (input_points.back().lteq(ib.start))) {
            return clone();
        }

        std::vector<Mapping> result_mappings;

        for (auto const& m : mappings) {
            auto new_results = ::split_at_input_points(m, input_points);
            result_mappings.insert(
                result_mappings.end(),
                new_results.begin(),
                new_results.end()
            );
        }

        return Topology{std::move(result_mappings)};
    }

    /// Split the topology at points in its output space
    Topology split_at_output_points(
        std::vector<Ordinate> const& output_points
    ) const {
        if (output_points.empty()) {
            return clone();
        }

        std::vector<Mapping> result_mappings;

        for (auto const& m : mappings) {
            if (std::holds_alternative<MappingEmpty>(m)) {
                result_mappings.push_back(::clone(m));
                continue;
            }

            auto m_bounds_in = ::input_bounds(m);
            auto m_bounds_out = ::output_bounds(m);

            // Find input points that map to the output points
            std::vector<Ordinate> input_points_in_bounds;

            for (auto const& out_pt : output_points) {
                if (m_bounds_out.overlaps(out_pt) &&
                    out_pt.gt(m_bounds_out.start) &&
                    out_pt.lt(m_bounds_out.end)) {

                    auto inv_result = ::project_instantaneous_cc_inv(m, out_pt);
                    if (!inv_result.is_out_of_bounds()) {
                        auto in_pt = inv_result.ordinate();

                        if (in_pt.gt(m_bounds_in.start) && in_pt.lt(m_bounds_in.end)) {
                            input_points_in_bounds.push_back(in_pt);
                        }
                    }
                }
            }

            // No valid input points - just append the mapping
            if (input_points_in_bounds.empty()) {
                result_mappings.push_back(::clone(m));
                continue;
            }

            // Sort input points
            std::sort(input_points_in_bounds.begin(), input_points_in_bounds.end(),
                [](Ordinate const& a, Ordinate const& b) { return a.lt(b); });

            // Split the mapping at each point
            auto splits = ::split_at_input_points(m, input_points_in_bounds);
            result_mappings.insert(
                result_mappings.end(),
                splits.begin(),
                splits.end()
            );
        }

        return Topology{std::move(result_mappings)};
    }

    // ---- Other Operations ----

    /// Clone (deep copy) this topology
    Topology clone() const {
        std::vector<Mapping> new_mappings;
        new_mappings.reserve(mappings.size());

        for (auto const& m : mappings) {
            new_mappings.push_back(::clone(m));
        }

        return Topology{std::move(new_mappings)};
    }

    /// Invert the topology
    /// Returns vector of topologies (may split due to discontinuities)
    std::vector<Topology> inverted() const {
        if (mappings.empty()) {
            return {Topology{}};
        }

        std::vector<Topology> result;
        std::vector<Mapping> current_mappings;
        std::optional<ContinuousInterval> maybe_input_range;

        for (auto const& m : mappings) {
            auto m_inverted = ::inverted(m);

            if (maybe_input_range.has_value()) {
                auto current_range = *maybe_input_range;

                if (intersect(current_range, ::input_bounds(m_inverted)).has_value() &&
                    !current_mappings.empty()) {
                    // Discontinuity - start new topology
                    result.push_back(Topology{std::move(current_mappings)});
                    current_mappings = {};
                }

                // Extend range
                maybe_input_range = extend(current_range, ::input_bounds(m_inverted));
                current_mappings.push_back(m_inverted);
            } else {
                current_mappings.push_back(m_inverted);
                maybe_input_range = ::input_bounds(m_inverted);
            }
        }

        // Add final topology
        if (!current_mappings.empty()) {
            result.push_back(Topology{std::move(current_mappings)});
        }

        return result;
    }

    /// Stream output
    friend std::ostream& operator<<(std::ostream& os, Topology const& topo) {
        os << "Topology{ mappings (" << topo.mappings.size() << "): [";

        for (size_t i = 0; i < topo.mappings.size(); ++i) {
            if (i > 0) {
                os << ", ";
            }
            auto const& m = topo.mappings[i];
            os << "(";

            // Print mapping type
            if (std::holds_alternative<MappingEmpty>(m)) {
                os << "empty";
            } else if (std::holds_alternative<MappingAffine>(m)) {
                os << "affine";
            } else if (std::holds_alternative<MappingCurveLinearMonotonic>(m)) {
                os << "linear";
            }

            os << ", " << ::input_bounds(m) << ")";
        }

        if (!topo.mappings.empty()) {
            os << "] -> output space: " << topo.output_bounds() << " }";
        } else {
            os << "] -> output space: (null) }";
        }

        return os;
    }
};

// ============================================================================
// Constants
// ============================================================================

/// An empty topology
inline const Topology EMPTY = Topology{};

/// Infinite identity topology
inline const Topology INFINITE_IDENTITY_TOPO = []() {
    std::vector<Mapping> mappings;
    mappings.push_back(Mapping{INFINITE_IDENTITY});
    return Topology{std::move(mappings)};
}();
