#pragma once
#include "schema.hpp"
#include <vector>
#include <queue>
#include <unordered_set>
#include <algorithm>

// OpenTimelineIO Temporal Hierarchy
//
// Builds projection operator maps from timeline structures.
// Creates a graph of transformations between all spaces in the hierarchy.
//
// Ported from wrinkles/src/opentimelineio/temporal_hierarchy.zig

namespace otio {
namespace temporal {

// ============================================================================
// Temporal Map
// ============================================================================

/// Represents a complete mapping graph for a timeline hierarchy
struct TemporalMap {
    ProjectionOperatorMap operators;

    /// Add an operator to the map
    void add_operator(ProjectionOperator op) {
        operators.add_operator(std::move(op));
    }

    /// Get number of operators
    size_t size() const {
        return operators.size();
    }

    /// Find operator connecting two spaces
    std::optional<ProjectionOperator const*> find_operator(
        SpaceReference const& src,
        SpaceReference const& dst
    ) const {
        return operators.find_operator(src, dst);
    }

    /// Get all operators
    std::vector<ProjectionOperator> const& get_operators() const {
        return operators.operators;
    }
};

// ============================================================================
// Space Reference Equality
// ============================================================================

/// Helper to check if two space references are equal
inline bool space_ref_equal(SpaceReference const& a, SpaceReference const& b) {
    // Compare labels
    if (a.label != b.label) {
        return false;
    }

    // Compare child indices
    if (a.child_index != b.child_index) {
        return false;
    }

    // Compare the actual object pointers in the variant
    return a.ref.index() == b.ref.index() &&
           std::visit([&](auto const* a_ptr) {
               return std::visit([&](auto const* b_ptr) -> bool {
                   using A_T = std::decay_t<decltype(*a_ptr)>;
                   using B_T = std::decay_t<decltype(*b_ptr)>;
                   if constexpr (std::is_same_v<A_T, B_T>) {
                       return a_ptr == b_ptr;
                   } else {
                       return false;
                   }
               }, b.ref);
           }, a.ref);
}

// ============================================================================
// Projection Operator Building
// ============================================================================

/// Build a projection operator for a single object's internal spaces
/// For example, Clip: presentation -> media
inline std::vector<ProjectionOperator> build_internal_operators(ComposedValueRef const& ref) {
    std::vector<ProjectionOperator> result;

    std::visit([&](auto const* ptr) {
        using T = std::decay_t<decltype(*ptr)>;

        if constexpr (std::is_same_v<T, Clip>) {
            // Clip has presentation and media spaces
            // presentation -> media is identity (same topology)
            auto spaces = ptr->spaces();
            if (spaces.size() >= 2) {
                auto topo = ptr->topology();
                result.push_back(ProjectionOperator{
                    spaces[0],  // presentation
                    spaces[1],  // media
                    topo
                });
            }
        }
        else if constexpr (std::is_same_v<T, Gap>) {
            // Gap only has presentation space, no internal operators
        }
        else if constexpr (std::is_same_v<T, Track> || std::is_same_v<T, Stack>) {
            // Track/Stack have presentation and intrinsic spaces
            auto spaces = ptr->spaces();
            if (spaces.size() >= 2) {
                auto topo = ptr->topology();
                result.push_back(ProjectionOperator{
                    spaces[0],  // presentation
                    spaces[1],  // intrinsic
                    topo
                });
            }
        }
        else if constexpr (std::is_same_v<T, Timeline>) {
            // Timeline delegates to its tracks (Stack)
            auto spaces = ptr->spaces();
            if (spaces.size() >= 2) {
                auto topo = ptr->topology();
                result.push_back(ProjectionOperator{
                    spaces[0],  // presentation
                    spaces[1],  // intrinsic
                    topo
                });
            }
        }
        else if constexpr (std::is_same_v<T, Warp>) {
            // Warp only has presentation space mapped through transform
            // The warp's transform maps parent presentation -> child presentation
        }
    }, ref);

    return result;
}

/// Build projection operators connecting parent to children
inline std::vector<ProjectionOperator> build_parent_to_child_operators(ComposedValueRef const& ref) {
    std::vector<ProjectionOperator> result;

    std::visit([&](auto const* ptr) {
        using T = std::decay_t<decltype(*ptr)>;

        if constexpr (std::is_same_v<T, Track>) {
            // Track children are sequential
            // Parent intrinsic space -> child presentation space
            auto parent_spaces = ptr->spaces();
            if (parent_spaces.size() < 2) return;

            auto parent_intrinsic = parent_spaces[1];  // intrinsic space

            for (size_t i = 0; i < ptr->children.size(); i++) {
                auto const& child = ptr->children[i];
                auto child_spaces = detail::get_spaces(child);

                if (child_spaces.empty()) continue;

                auto child_presentation = child_spaces[0];  // presentation space
                child_presentation.child_index = i;

                // Build topology from parent intrinsic to child presentation
                Topology parent_to_child_topo;

                if (i == 0) {
                    // First child: identity from start
                    auto child_bounds = detail::get_bounds_of(child, SpaceLabel::presentation);
                    parent_to_child_topo = Topology::init_identity(child_bounds);
                } else {
                    // Subsequent children: use transform_to_child
                    parent_to_child_topo = ptr->transform_to_child(child_presentation);
                }

                result.push_back(ProjectionOperator{
                    parent_intrinsic,
                    child_presentation,
                    parent_to_child_topo
                });
            }
        }
        else if constexpr (std::is_same_v<T, Stack>) {
            // Stack children are simultaneous (parallel)
            // Parent intrinsic space -> child presentation space (identity for all)
            auto parent_spaces = ptr->spaces();
            if (parent_spaces.size() < 2) return;

            auto parent_intrinsic = parent_spaces[1];  // intrinsic space

            for (size_t i = 0; i < ptr->children.size(); i++) {
                auto const& child = ptr->children[i];
                auto child_spaces = detail::get_spaces(child);

                if (child_spaces.empty()) continue;

                auto child_presentation = child_spaces[0];  // presentation space
                child_presentation.child_index = i;

                // All children share the same time space (identity mapping)
                auto child_bounds = detail::get_bounds_of(child, SpaceLabel::presentation);
                auto parent_to_child_topo = Topology::init_identity(child_bounds);

                result.push_back(ProjectionOperator{
                    parent_intrinsic,
                    child_presentation,
                    parent_to_child_topo
                });
            }
        }
        else if constexpr (std::is_same_v<T, Timeline>) {
            // Timeline contains a Stack (tracks)
            // Timeline intrinsic -> Stack presentation
            auto timeline_spaces = ptr->spaces();
            if (timeline_spaces.size() < 2) return;

            auto timeline_intrinsic = timeline_spaces[1];

            ComposedValueRef stack_ref = const_cast<Stack*>(&ptr->tracks);
            auto stack_spaces = detail::get_spaces(stack_ref);

            if (stack_spaces.empty()) return;

            auto stack_presentation = stack_spaces[0];

            auto topo = ptr->tracks.topology();

            result.push_back(ProjectionOperator{
                timeline_intrinsic,
                stack_presentation,
                topo
            });
        }
        else if constexpr (std::is_same_v<T, Warp>) {
            // Warp wraps a child with a transformation
            // Warp presentation -> child presentation (through transform)
            auto warp_spaces = ptr->spaces();
            if (warp_spaces.empty()) return;

            auto warp_presentation = warp_spaces[0];

            auto child_spaces = detail::get_spaces(ptr->child);
            if (child_spaces.empty()) return;

            auto child_presentation = child_spaces[0];

            result.push_back(ProjectionOperator{
                warp_presentation,
                child_presentation,
                ptr->transform.clone()
            });
        }
    }, ref);

    return result;
}

/// Get all children of a composed value
inline std::vector<ComposedValueRef> get_children(ComposedValueRef const& ref) {
    return std::visit([](auto const* ptr) -> std::vector<ComposedValueRef> {
        using T = std::decay_t<decltype(*ptr)>;

        if constexpr (std::is_same_v<T, Track> || std::is_same_v<T, Stack>) {
            return ptr->children;
        }
        else if constexpr (std::is_same_v<T, Timeline>) {
            return {const_cast<Stack*>(&ptr->tracks)};
        }
        else if constexpr (std::is_same_v<T, Warp>) {
            return {ptr->child};
        }
        else {
            return {};
        }
    }, ref);
}

// ============================================================================
// Temporal Map Building
// ============================================================================

/// Build a complete temporal map for a timeline hierarchy
/// Traverses the hierarchy and creates projection operators for all space connections
inline TemporalMap build_temporal_map(Timeline const& timeline) {
    TemporalMap map;

    // Queue for breadth-first traversal
    std::queue<ComposedValueRef> to_visit;

    // Set to track visited objects (by pointer)
    std::unordered_set<void const*> visited;

    // Start with the timeline
    ComposedValueRef timeline_ref = const_cast<Timeline*>(&timeline);
    to_visit.push(timeline_ref);

    while (!to_visit.empty()) {
        auto current = to_visit.front();
        to_visit.pop();

        // Get pointer for visited check
        void const* ptr = std::visit([](auto const* p) -> void const* {
            return static_cast<void const*>(p);
        }, current);

        if (visited.count(ptr) > 0) {
            continue;
        }
        visited.insert(ptr);

        // Build internal operators (e.g., presentation -> media for Clip)
        auto internal_ops = build_internal_operators(current);
        for (auto& op : internal_ops) {
            map.add_operator(std::move(op));
        }

        // Build parent-to-child operators
        auto parent_child_ops = build_parent_to_child_operators(current);
        for (auto& op : parent_child_ops) {
            map.add_operator(std::move(op));
        }

        // Add children to queue
        auto children = get_children(current);
        for (auto const& child : children) {
            to_visit.push(child);
        }
    }

    return map;
}

// ============================================================================
// Path Finding
// ============================================================================

/// Find a path of projection operators from source to destination
/// Returns a vector of operators that can be composed to map from src to dst
inline std::optional<std::vector<ProjectionOperator>> find_path(
    TemporalMap const& map,
    SpaceReference const& src,
    SpaceReference const& dst
) {
    // Simple breadth-first search for now
    // In a real implementation, this would use a proper graph search algorithm

    struct PathNode {
        SpaceReference space;
        std::vector<ProjectionOperator> path;
    };

    std::queue<PathNode> to_visit;
    std::unordered_set<size_t> visited;

    // Hash function for space references (simplified)
    auto space_hash = [](SpaceReference const& sr) -> size_t {
        size_t h = std::hash<int>{}(static_cast<int>(sr.label));
        if (sr.child_index.has_value()) {
            h ^= std::hash<size_t>{}(*sr.child_index) << 1;
        }
        return h;
    };

    to_visit.push(PathNode{src, {}});
    visited.insert(space_hash(src));

    while (!to_visit.empty()) {
        auto current = to_visit.front();
        to_visit.pop();

        // Check if we reached the destination
        if (space_ref_equal(current.space, dst)) {
            return current.path;
        }

        // Explore neighbors
        for (auto const& op : map.get_operators()) {
            // Check if this operator starts from current space
            if (space_ref_equal(op.source, current.space)) {
                size_t dst_hash = space_hash(op.destination);

                if (visited.count(dst_hash) == 0) {
                    visited.insert(dst_hash);

                    auto next_path = current.path;
                    next_path.push_back(op);

                    PathNode next{op.destination, next_path};

                    to_visit.push(next);
                }
            }
        }
    }

    return std::nullopt;  // No path found
}

/// Compose a path of projection operators into a single operator
inline std::optional<ProjectionOperator> compose_path(
    std::vector<ProjectionOperator> const& path
) {
    if (path.empty()) {
        return std::nullopt;
    }

    if (path.size() == 1) {
        return path[0];
    }

    // Compose all topologies in the path
    Topology composed = path[0].src_to_dst_topo.clone();

    for (size_t i = 1; i < path.size(); i++) {
        // Compose: composed = composed ∘ path[i]
        // This means: input -> composed -> path[i] -> output
        std::vector<Mapping> new_mappings;

        // For each mapping in composed output, compose with each mapping in path[i]
        for (auto const& m1 : composed.mappings) {
            for (auto const& m2 : path[i].src_to_dst_topo.mappings) {
                auto joined = join(m1, m2);
                if (!std::holds_alternative<MappingEmpty>(joined)) {
                    new_mappings.push_back(joined);
                }
            }
        }

        if (new_mappings.empty()) {
            new_mappings.push_back(MappingEmpty{});
        }

        composed = Topology::init(new_mappings);
    }

    return ProjectionOperator{
        path.front().source,
        path.back().destination,
        composed
    };
}

/// Project from one space to another through the temporal map
inline std::optional<ProjectionOperator> build_projection(
    TemporalMap const& map,
    SpaceReference const& src,
    SpaceReference const& dst
) {
    // First check for direct operator
    auto direct = map.find_operator(src, dst);
    if (direct.has_value()) {
        return **direct;
    }

    // Try to find a path
    auto path = find_path(map, src, dst);
    if (!path.has_value()) {
        return std::nullopt;
    }

    // Compose the path
    return compose_path(*path);
}

// ============================================================================
// Convenience Functions
// ============================================================================

/// Project an ordinate from one space to another
inline std::optional<Ordinate> project_ordinate(
    TemporalMap const& map,
    SpaceReference const& src,
    SpaceReference const& dst,
    Ordinate const& ord
) {
    auto proj = build_projection(map, src, dst);
    if (!proj.has_value()) {
        return std::nullopt;
    }

    auto result = proj->project_instantaneous_cc(ord);
    if (result.is_out_of_bounds()) {
        return std::nullopt;
    }

    return result.ordinate();
}

} // namespace temporal
} // namespace otio
