#pragma once
#include "../opentime/interval.hpp"
#include "../opentime/ordinate.hpp"
#include "../opentime/projection_result.hpp"
#include "../topology/topology.hpp"
#include <variant>
#include <optional>
#include <string>
#include <ostream>

// OpenTimelineIO Core Types
//
// Core types for the OpenTimelineIO implementation, including space labels,
// composed value references, and projection operators.
//
// Ported from wrinkles/src/opentimelineio/core.zig

namespace otio {

// Type aliases
using Ordinate = OrdinateImpl<double>;
using ContinuousInterval = ContinuousIntervalImpl<Ordinate>;
using ProjectionResult = ProjectionResultImpl<Ordinate>;

// Forward declarations for schema types
struct Clip;
struct Gap;
struct Track;
struct Stack;
struct Warp;
struct Timeline;

// ============================================================================
// Space Labels
// ============================================================================

/// Used to identify spaces on objects in the hierarchy
enum class SpaceLabel : int8_t {
    presentation = 0,  // The space as presented (e.g., in the parent)
    intrinsic,         // The intrinsic/output space of the object
    media,             // The media space (for clips)
    child,             // Child space (for tracks)
};

inline std::ostream& operator<<(std::ostream& os, SpaceLabel label) {
    switch (label) {
        case SpaceLabel::presentation: os << "presentation"; break;
        case SpaceLabel::intrinsic: os << "intrinsic"; break;
        case SpaceLabel::media: os << "media"; break;
        case SpaceLabel::child: os << "child"; break;
    }
    return os;
}

// ============================================================================
// Composed Value Reference
// ============================================================================

/// A pointer to something in the composition hierarchy
/// Uses std::variant for type-safe polymorphism
using ComposedValueRef = std::variant<
    Clip*,
    Gap*,
    Track*,
    Stack*,
    Warp*,
    Timeline*
>;

// Helper functions for ComposedValueRef
namespace detail {
    /// Get the name of the referenced object
    inline std::optional<std::string> get_name(ComposedValueRef const& ref);

    /// Get topology of the referenced object
    inline Topology get_topology(ComposedValueRef const& ref);

    /// Get bounds of the referenced object in the specified space
    inline ContinuousInterval get_bounds_of(
        ComposedValueRef const& ref,
        SpaceLabel target_space
    );

} // namespace detail

// ============================================================================
// Space Reference
// ============================================================================

/// References a specific space on a specific object
struct SpaceReference {
    ComposedValueRef ref;
    SpaceLabel label;
    std::optional<size_t> child_index;

    SpaceReference(
        ComposedValueRef r,
        SpaceLabel l,
        std::optional<size_t> ci = std::nullopt
    ) : ref(r), label(l), child_index(ci) {}

    friend std::ostream& operator<<(std::ostream& os, SpaceReference const& sr) {
        os << "<SpaceRef:" << sr.label;
        if (sr.child_index.has_value()) {
            os << "." << *sr.child_index;
        }
        os << ">";
        return os;
    }
};

// ============================================================================
// Projection Operator
// ============================================================================

/// Combines a source, destination and transformation from source to destination
/// Allows continuous and discrete transformations
struct ProjectionOperator {
    SpaceReference source;
    SpaceReference destination;
    Topology src_to_dst_topo;

    ProjectionOperator(
        SpaceReference src,
        SpaceReference dst,
        Topology topo
    ) : source(std::move(src)),
        destination(std::move(dst)),
        src_to_dst_topo(std::move(topo)) {}

    /// Get source bounds
    ContinuousInterval source_bounds() const {
        return src_to_dst_topo.input_bounds();
    }

    /// Get destination bounds
    ContinuousInterval destination_bounds() const {
        return src_to_dst_topo.output_bounds();
    }

    /// Project a continuous ordinate to the continuous destination space
    ProjectionResult project_instantaneous_cc(
        Ordinate const& ordinate_in_source_space
    ) const {
        return src_to_dst_topo.project_instantaneous_cc(ordinate_in_source_space);
    }

    /// Stream output
    friend std::ostream& operator<<(std::ostream& os, ProjectionOperator const& po) {
        os << "ProjectionOperator{" << po.source << " -> " << po.destination << "}";
        return os;
    }
};

// ============================================================================
// Projection Operator Map
// ============================================================================

/// Collection of projection operators forming a complete mapping graph
struct ProjectionOperatorMap {
    std::vector<ProjectionOperator> operators;

    void add_operator(ProjectionOperator op) {
        operators.push_back(std::move(op));
    }

    size_t size() const {
        return operators.size();
    }

    /// Find operator that maps from source to destination
    std::optional<ProjectionOperator const*> find_operator(
        SpaceReference const& src,
        SpaceReference const& dst
    ) const {
        for (auto const& op : operators) {
            // Simple comparison - would need proper equality for SpaceReference
            if (op.source.label == src.label &&
                op.destination.label == dst.label) {
                return &op;
            }
        }
        return std::nullopt;
    }

    /// Stream output
    friend std::ostream& operator<<(std::ostream& os, ProjectionOperatorMap const& pom) {
        os << "ProjectionOperatorMap{operators=" << pom.operators.size() << "}";
        return os;
    }
};

} // namespace otio
