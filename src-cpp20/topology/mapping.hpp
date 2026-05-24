#pragma once
#include "mapping_empty.hpp"
#include "mapping_affine.hpp"
#include "mapping_curve_linear.hpp"
#include "../curve/linear_curve.hpp"
#include <variant>
#include <vector>
#include <optional>

// Polymorphic Mapping variant
//
// A Mapping is a polymorphic container for a function that maps from an
// "input" space to an "output" space. Mappings can be joined with other
// mappings via function composition to build new transformations via common
// spaces.
//
// Ported from wrinkles/src/topology/mapping.zig

// Type aliases for convenience
using Ordinate = OrdinateImpl<double>;
using ContinuousInterval = ContinuousIntervalImpl<Ordinate>;
using ProjectionResult = ProjectionResultImpl<Ordinate>;

/// Polymorphic mapping type that can hold any mapping variant
using Mapping = std::variant<
    MappingEmpty,
    MappingAffine,
    MappingCurveLinearMonotonic
>;

// ============================================================================
// Polymorphic Operations on Mapping
// ============================================================================

/// Project an ordinate from input space to output space
inline ProjectionResult project_instantaneous_cc(
    Mapping const& mapping,
    Ordinate const& input_ordinate
) noexcept {
    return std::visit(
        [&input_ordinate](auto const& m) {
            return m.project_instantaneous_cc(input_ordinate);
        },
        mapping
    );
}

/// Project an ordinate from output space back to input space
inline ProjectionResult project_instantaneous_cc_inv(
    Mapping const& mapping,
    Ordinate const& output_ordinate
) noexcept {
    return std::visit(
        [&output_ordinate](auto const& m) {
            return m.project_instantaneous_cc_inv(output_ordinate);
        },
        mapping
    );
}

/// Get input bounds of the mapping
inline ContinuousInterval input_bounds(
    Mapping const& mapping
) noexcept {
    return std::visit(
        [](auto const& m) {
            return m.input_bounds();
        },
        mapping
    );
}

/// Get output bounds of the mapping
inline ContinuousInterval output_bounds(
    Mapping const& mapping
) noexcept {
    return std::visit(
        [](auto const& m) {
            return m.output_bounds();
        },
        mapping
    );
}

/// Clone (deep copy) the mapping
inline Mapping clone(
    Mapping const& mapping
) {
    return std::visit(
        [](auto const& m) -> Mapping {
            return m.clone();
        },
        mapping
    );
}

/// Shrink the mapping to the target input interval
inline std::optional<Mapping> shrink_to_input_interval(
    Mapping const& mapping,
    ContinuousInterval const& target_interval
) {
    return std::visit(
        [&target_interval](auto const& m) -> std::optional<Mapping> {
            using MappingType = std::decay_t<decltype(m)>;

            if constexpr (std::is_same_v<MappingType, MappingEmpty>) {
                auto result = m.shrink_to_input_interval(target_interval);
                if (result.has_value()) {
                    return Mapping{*result};
                }
                return std::nullopt;
            } else if constexpr (std::is_same_v<MappingType, MappingAffine>) {
                auto result = m.shrink_to_input_interval(target_interval);
                if (result.has_value()) {
                    return Mapping{*result};
                }
                return std::nullopt;
            } else {
                // MappingCurveLinearMonotonic
                return Mapping{m.shrink_to_input_interval(target_interval)};
            }
        },
        mapping
    );
}

/// Shrink the mapping to the target output interval
inline Mapping shrink_to_output_interval(
    Mapping const& mapping,
    ContinuousInterval const& target_interval
) {
    return std::visit(
        [&target_interval](auto const& m) -> Mapping {
            return m.shrink_to_output_interval(target_interval);
        },
        mapping
    );
}

/// Split the mapping at a point in its input space
inline std::array<Mapping, 2> split_at_input_point(
    Mapping const& mapping,
    Ordinate const& pt_input
) {
    return std::visit(
        [&pt_input](auto const& m) -> std::array<Mapping, 2> {
            auto [left, right] = m.split_at_input_point(pt_input);
            return {Mapping{left}, Mapping{right}};
        },
        mapping
    );
}

/// Split the mapping at multiple points in its input space
inline std::vector<Mapping> split_at_input_points(
    Mapping const& mapping,
    std::vector<Ordinate> const& input_points
) {
    return std::visit(
        [&input_points](auto const& m) -> std::vector<Mapping> {
            using MappingType = std::decay_t<decltype(m)>;

            if constexpr (std::is_same_v<MappingType, MappingEmpty>) {
                // Empty mapping just returns itself
                return {Mapping{m}};
            } else if constexpr (std::is_same_v<MappingType, MappingAffine>) {
                auto results = m.split_at_input_points(input_points);
                std::vector<Mapping> mappings;
                mappings.reserve(results.size());
                for (auto const& r : results) {
                    mappings.push_back(Mapping{r});
                }
                return mappings;
            } else {
                // MappingCurveLinearMonotonic - not implemented yet
                // For now just return the mapping unchanged
                return {Mapping{m}};
            }
        },
        mapping
    );
}

/// Split the mapping at multiple points in its output space
inline std::vector<Mapping> split_at_output_points(
    Mapping const& mapping,
    std::vector<Ordinate> const& output_points
) {
    // Check if empty
    if (std::holds_alternative<MappingEmpty>(mapping)) {
        return {mapping};
    }

    // Project output points back to input space
    std::vector<Ordinate> input_points;
    input_points.reserve(output_points.size());

    auto out_bounds = output_bounds(mapping);

    for (auto const& o_p : output_points) {
        if (out_bounds.overlaps(o_p)) {
            auto result = project_instantaneous_cc_inv(mapping, o_p);
            if (!result.is_out_of_bounds()) {
                input_points.push_back(result.ordinate());
            }
        }
    }

    return split_at_input_points(mapping, input_points);
}

/// Invert the mapping (swap input and output spaces)
inline Mapping inverted(
    Mapping const& mapping
) {
    return std::visit(
        [](auto const& m) -> Mapping {
            using MappingType = std::decay_t<decltype(m)>;

            if constexpr (std::is_same_v<MappingType, MappingEmpty>) {
                return Mapping{m.clone()};
            } else if constexpr (std::is_same_v<MappingType, MappingAffine>) {
                return Mapping{MappingAffine{
                    m.output_bounds(),
                    m.input_to_output_xform.inverted()
                }};
            } else {
                // MappingCurveLinearMonotonic
                // For linear curves, swap input and output in each knot
                auto const& knots = m.input_to_output_curve.knots;
                std::vector<ControlPoint> inverted_knots;
                inverted_knots.reserve(knots.size());

                for (auto const& k : knots) {
                    inverted_knots.push_back(ControlPoint{k.out, k.in});
                }

                return Mapping{MappingCurveLinearMonotonic::init_knots(inverted_knots)};
            }
        },
        mapping
    );
}

/// Stream output for Mapping
inline std::ostream& operator<<(std::ostream& os, Mapping const& mapping) {
    std::visit(
        [&os](auto const& m) {
            os << m;
        },
        mapping
    );
    return os;
}

// ============================================================================
// Constants
// ============================================================================

inline const Mapping EMPTY_INF_MAPPING = Mapping{EMPTY_INF};

// ============================================================================
// Helper Functions for Join Operations
// ============================================================================

/// Join two linear curves: a->b and b->c produces a->c
/// This is a simplified implementation that projects knots through the second curve
inline LinearMonotonic join_linear_curves(
    LinearMonotonic const& a2b,
    LinearMonotonic const& b2c
) {
    // For each knot in a2b, project its output through b2c
    std::vector<ControlPoint> result_knots;
    result_knots.reserve(a2b.knots.size());

    for (auto const& a2b_knot : a2b.knots) {
        // Project the output of a2b through b2c
        auto b2c_output = b2c.output_at_input(a2b_knot.out);

        if (!b2c_output.is_out_of_bounds()) {
            result_knots.push_back(ControlPoint{
                a2b_knot.in,
                b2c_output.ordinate()
            });
        }
    }

    return LinearMonotonic{std::move(result_knots)};
}

// ============================================================================
// Join Operations
// ============================================================================

/// Join two affine mappings: a->b and b->c produces a->c
inline MappingAffine join_aff_aff(
    MappingAffine const& a2b,
    MappingAffine const& b2c
) noexcept {
    return MappingAffine{
        a2b.input_bounds(),
        b2c.input_to_output_xform.applied_to_transform(
            a2b.input_to_output_xform
        )
    };
}

/// Join affine mapping a->b with linear mapping b->c
/// Result is linear mapping a->c
inline MappingCurveLinearMonotonic join_aff_lin(
    MappingAffine const& a2b,
    MappingCurveLinearMonotonic const& b2c
) {
    // Linearize the affine mapping
    auto a2b_input_bounds = a2b.input_bounds();
    auto a2b_output_bounds = a2b.output_bounds();

    std::vector<ControlPoint> a2b_knots = {
        {a2b_input_bounds.start, a2b_output_bounds.start},
        {a2b_input_bounds.end, a2b_output_bounds.end}
    };

    auto a2b_linearized = MappingCurveLinearMonotonic::init_knots(a2b_knots);

    // Join the two linear curves
    auto result_curve = join_linear_curves(
        a2b_linearized.input_to_output_curve,
        b2c.input_to_output_curve
    );

    return MappingCurveLinearMonotonic::init_curve(result_curve);
}

/// Join linear mapping a->b with affine mapping b->c
/// Result is linear mapping a->c
inline MappingCurveLinearMonotonic join_lin_aff(
    MappingCurveLinearMonotonic const& a2b,
    MappingAffine const& b2c
) {
    // Transform each knot's output through the affine mapping
    std::vector<ControlPoint> a2c_knots;
    a2c_knots.reserve(a2b.input_to_output_curve.knots.size());

    for (auto const& k : a2b.input_to_output_curve.knots) {
        auto projected = b2c.project_instantaneous_cc(k.out);
        if (!projected.is_out_of_bounds()) {
            a2c_knots.push_back(ControlPoint{k.in, projected.ordinate()});
        }
    }

    return MappingCurveLinearMonotonic::init_knots(a2c_knots);
}

/// Join two linear mappings: a->b and b->c produces a->c
inline MappingCurveLinearMonotonic join_lin_lin(
    MappingCurveLinearMonotonic const& a2b,
    MappingCurveLinearMonotonic const& b2c
) {
    auto result_curve = join_linear_curves(a2b.input_to_output_curve, b2c.input_to_output_curve);
    return MappingCurveLinearMonotonic::init_curve(result_curve);
}

/// Join two mappings via their common coordinate system
/// Given a->b and b->c, produces a->c
/// Handles boundary conditions and type conversions
inline Mapping join(
    Mapping const& a2b,
    Mapping const& b2c
) {
    auto a2b_input = input_bounds(a2b);
    MappingEmpty empty_result{a2b_input};

    // Joining anything with empty results in empty
    if (std::holds_alternative<MappingEmpty>(a2b) ||
        std::holds_alternative<MappingEmpty>(b2c)) {
        return Mapping{empty_result};
    }

    // Manage boundary conditions - find intersection in "b" space
    auto a2b_b_bounds = output_bounds(a2b);
    auto b2c_b_bounds = input_bounds(b2c);

    auto maybe_b_intersection = intersect(a2b_b_bounds, b2c_b_bounds);

    // If no intersection in "b" space, result is empty
    if (!maybe_b_intersection.has_value()) {
        return Mapping{empty_result};
    }

    auto b_intersection = *maybe_b_intersection;

    // Trim both mappings to the common "b" space
    auto a2b_trimmed = shrink_to_output_interval(a2b, b_intersection);
    auto b2c_trimmed_opt = shrink_to_input_interval(b2c, b_intersection);

    if (!b2c_trimmed_opt.has_value()) {
        return Mapping{empty_result};
    }

    auto b2c_trimmed = *b2c_trimmed_opt;

    // Dispatch based on the types of the trimmed mappings
    return std::visit(
        [&empty_result](auto const& b2c_val, auto const& a2b_val) -> Mapping {
            using B2CType = std::decay_t<decltype(b2c_val)>;
            using A2BType = std::decay_t<decltype(a2b_val)>;

            // Handle empty cases (shouldn't reach here due to earlier checks)
            if constexpr (std::is_same_v<A2BType, MappingEmpty> ||
                          std::is_same_v<B2CType, MappingEmpty>) {
                return Mapping{empty_result};
            }
            // affine + affine -> affine
            else if constexpr (std::is_same_v<A2BType, MappingAffine> &&
                               std::is_same_v<B2CType, MappingAffine>) {
                return Mapping{join_aff_aff(a2b_val, b2c_val)};
            }
            // affine + linear -> linear
            else if constexpr (std::is_same_v<A2BType, MappingAffine> &&
                               std::is_same_v<B2CType, MappingCurveLinearMonotonic>) {
                return Mapping{join_aff_lin(a2b_val, b2c_val)};
            }
            // linear + affine -> linear
            else if constexpr (std::is_same_v<A2BType, MappingCurveLinearMonotonic> &&
                               std::is_same_v<B2CType, MappingAffine>) {
                return Mapping{join_lin_aff(a2b_val, b2c_val)};
            }
            // linear + linear -> linear
            else if constexpr (std::is_same_v<A2BType, MappingCurveLinearMonotonic> &&
                               std::is_same_v<B2CType, MappingCurveLinearMonotonic>) {
                return Mapping{join_lin_lin(a2b_val, b2c_val)};
            }
            else {
                return Mapping{empty_result};
            }
        },
        b2c_trimmed,
        a2b_trimmed
    );
}
