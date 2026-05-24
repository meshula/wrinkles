#pragma once
#include "treecode.hpp"
#include <vector>
#include <optional>
#include <stdexcept>

// Map: Bidirectional mapping of Treecode to graph nodes
//
// Ported from wrinkles/src/treecode/map.zig

// ============================================================================
// Type Definitions
// ============================================================================

using NodeIndex = size_t;

// ============================================================================
// Map Template Class
// ============================================================================

/// Bidirectional map of `Treecode` to a parameterized `GraphNodeType`.
/// This allows:
/// * Random access by path of GraphNodeTypes in a hierarchy
/// * Fetching of a path from one GraphNodeType to another by walking
///   along the Treecodes
/// * Depth-first iteration through the graph
template<typename GraphNodeType>
class Map {
public:
    // ---- Nested Types ----

    /// A pair of space and code along a path within the Map
    struct PathNode {
        GraphNodeType space;
        Treecode code;
        std::optional<NodeIndex> parent_index = std::nullopt;
        std::array<std::optional<NodeIndex>, 2> child_indices = {std::nullopt, std::nullopt};

        PathNode() = default;
        PathNode(
            GraphNodeType space_,
            Treecode code_,
            std::optional<NodeIndex> parent_index_ = std::nullopt
        ) : space(std::move(space_)),
            code(std::move(code_)),
            parent_index(parent_index_) {}
    };

    /// Encoding of the end points of a path between GraphNodeTypes in the Map
    struct PathEndPoints {
        GraphNodeType source;
        GraphNodeType destination;
    };

    // Forward declaration for PathIterator
    class PathIterator;

private:
    // ---- Internal Types ----

    struct PathEndPointIndices {
        NodeIndex source;
        NodeIndex destination;
    };

    // ---- Member Data ----

    /// Hash map specialization for GraphNodeType (requires std::hash support)
    std::unordered_map<GraphNodeType, NodeIndex> map_space_to_index;

    /// Mapping of Treecode to NodeIndex
    TreecodeHashMap<NodeIndex> map_code_to_index;

    /// Storage for all nodes
    std::vector<PathNode> nodes;

public:
    // ---- Construction ----

    Map() = default;

    // RAII - no explicit deinit needed, destructors handle cleanup

    // ---- Node Operations ----

    /// Add a PathNode to the map and return the newly created index
    NodeIndex put(PathNode node) {
        NodeIndex new_index = nodes.size();

        // Update parent's child indices if this node has a parent
        if (node.parent_index.has_value()) {
            NodeIndex parent_idx = *node.parent_index;

            if (parent_idx >= nodes.size()) {
                throw std::runtime_error("Invalid parent index");
            }

            Treecode const& parent_code = nodes[parent_idx].code;
            LeftOrRight dir = parent_code.next_step_towards(node.code);
            nodes[parent_idx].child_indices[static_cast<size_t>(dir)] = new_index;
        }

        // Add to both maps before adding to nodes vector
        // (to ensure we can use the treecode/space references)
        map_code_to_index[node.code] = new_index;
        map_space_to_index[node.space] = new_index;

        // Add node to storage
        nodes.push_back(std::move(node));

        return new_index;
    }

    /// Get GraphNodeType from Treecode
    std::optional<GraphNodeType> get_space(Treecode const& code) const {
        auto it = map_code_to_index.find(code);
        if (it != map_code_to_index.end()) {
            return nodes[it->second].space;
        }
        return std::nullopt;
    }

    /// Get Treecode from GraphNodeType
    std::optional<Treecode> get_code(GraphNodeType const& space) const {
        auto it = map_space_to_index.find(space);
        if (it != map_space_to_index.end()) {
            return nodes[it->second].code;
        }
        return std::nullopt;
    }

    /// Get NodeIndex from Treecode
    std::optional<NodeIndex> fetch_index_by_code(Treecode const& code) const {
        auto it = map_code_to_index.find(code);
        if (it != map_code_to_index.end()) {
            return it->second;
        }
        return std::nullopt;
    }

    /// Get NodeIndex from GraphNodeType
    std::optional<NodeIndex> fetch_index_by_space(GraphNodeType const& space) const {
        auto it = map_space_to_index.find(space);
        if (it != map_space_to_index.end()) {
            return it->second;
        }
        return std::nullopt;
    }

    /// Return the root space associated with the ROOT_CODE
    /// The root object should always be the first entry in the nodes list
    GraphNodeType const& root() const {
        if (nodes.empty()) {
            throw std::runtime_error("Map has no root node");
        }
        return nodes[0].space;
    }

    /// Get PathNode at index
    PathNode const& get_node(NodeIndex index) const {
        if (index >= nodes.size()) {
            throw std::runtime_error("Invalid node index");
        }
        return nodes[index];
    }

    /// Number of nodes in the map
    size_t size() const noexcept {
        return nodes.size();
    }

    /// Check if map is empty
    bool empty() const noexcept {
        return nodes.empty();
    }

    // ---- Path Sorting ----

    /// Check if endpoints need to be swapped (iteration always proceeds from
    /// parent to child). If needed, will swap endpoints in place and return
    /// true to indicate this happened.
    ///
    /// Returns error if there is no path between the endpoints or one of the
    /// endpoints is not present in the mapping.
    bool sort_endpoints(PathEndPoints& endpoints) const {
        auto source_code_opt = get_code(endpoints.source);
        if (!source_code_opt.has_value()) {
            throw std::runtime_error("Source not in map");
        }

        auto destination_code_opt = get_code(endpoints.destination);
        if (!destination_code_opt.has_value()) {
            throw std::runtime_error("Destination not in map");
        }

        Treecode const& source_code = *source_code_opt;
        Treecode const& destination_code = *destination_code_opt;

        // Check if path exists between source and destination
        if (!source_code.is_prefix_of(destination_code) &&
            !destination_code.is_prefix_of(source_code)) {
            throw std::runtime_error("No path between source and destination");
        }

        // If source is longer than destination, swap (iteration goes parent to child)
        if (source_code.code_length() > destination_code.code_length()) {
            std::swap(endpoints.source, endpoints.destination);
            return true;
        }

        return false;
    }

    /// Sort endpoint indices (internal version)
    bool sort_endpoint_indices(PathEndPointIndices& endpoints) const {
        Treecode const& source_code = nodes[endpoints.source].code;
        Treecode const& destination_code = nodes[endpoints.destination].code;

        // Check if path exists
        if (!source_code.is_prefix_of(destination_code) &&
            !destination_code.is_prefix_of(source_code)) {
            throw std::runtime_error("No path between source and destination");
        }

        // If source is longer than destination, swap
        if (source_code.code_length() > destination_code.code_length()) {
            std::swap(endpoints.source, endpoints.destination);
            return true;
        }

        return false;
    }

    // ---- Iterator ----

    /// Create an iterator starting from the root
    PathIterator iter() const {
        return PathIterator::init(*this);
    }

    /// Create an iterator starting from a specific source
    PathIterator iter_from(GraphNodeType const& source) const {
        return PathIterator::init_from(*this, source);
    }

    /// Create an iterator walking from source to destination
    PathIterator iter_from_to(PathEndPoints const& endpoints) const {
        return PathIterator::init_from_to(*this, endpoints);
    }

    // ============================================================================
    // PathIterator - Depth-first traversal through the Map
    // ============================================================================

    /// Walks across a Map by walking through the treecodes and finding the
    /// ones that are present in the Map.
    class PathIterator {
    private:
        std::vector<NodeIndex> stack;
        std::optional<NodeIndex> maybe_current;
        Map const* map;
        std::optional<NodeIndex> maybe_source;
        std::optional<NodeIndex> maybe_destination;

    public:
        // ---- Construction ----

        /// Walk exhaustively, depth-first, starting from the root
        static PathIterator init(Map const& map_ref) {
            return init_from_index(map_ref, 0);
        }

        /// Start iteration from a specific source node
        static PathIterator init_from(
            Map const& map_ref,
            GraphNodeType const& source
        ) {
            auto start_index_opt = map_ref.fetch_index_by_space(source);
            if (!start_index_opt.has_value()) {
                throw std::runtime_error("Source not in map");
            }

            return init_from_index(map_ref, *start_index_opt);
        }

        /// An iterator that walks from the source node to the destination node
        static PathIterator init_from_to(
            Map const& map_ref,
            PathEndPoints endpoints
        ) {
            auto source_index_opt = map_ref.fetch_index_by_space(endpoints.source);
            if (!source_index_opt.has_value()) {
                throw std::runtime_error("Source not in map");
            }

            auto destination_index_opt = map_ref.fetch_index_by_space(endpoints.destination);
            if (!destination_index_opt.has_value()) {
                throw std::runtime_error("Destination not in map");
            }

            PathEndPointIndices endpoint_indices{
                *source_index_opt,
                *destination_index_opt
            };

            map_ref.sort_endpoint_indices(endpoint_indices);

            PathIterator iterator = init_from_index(map_ref, endpoint_indices.source);
            iterator.maybe_destination = endpoint_indices.destination;

            return iterator;
        }

        // ---- Iteration ----

        /// Get the next PathNode in the traversal
        /// Returns nullopt when iteration is complete
        std::optional<PathNode> next() {
            if (stack.empty()) {
                maybe_current = std::nullopt;
                return std::nullopt;
            }

            // Pop the current node from the stack
            maybe_current = stack.back();
            stack.pop_back();
            NodeIndex current_index = *maybe_current;

            // If we've reached the destination, stop
            if (maybe_destination.has_value() && current_index == *maybe_destination) {
                stack.clear();
                return map->nodes[current_index];
            }

            Treecode const& current_code = map->nodes[current_index].code;

            // Determine which children to visit
            if (maybe_destination.has_value()) {
                // If there's a destination, only walk in that direction
                Treecode const& dest_code = map->nodes[*maybe_destination].code;
                LeftOrRight next_step = current_code.next_step_towards(dest_code);

                auto const& child_indices = map->nodes[current_index].child_indices;
                auto child_opt = child_indices[static_cast<size_t>(next_step)];

                if (child_opt.has_value()) {
                    stack.push_back(*child_opt);
                } else {
                    throw std::runtime_error("Invalid graph: missing connection");
                }
            } else {
                // Walk exhaustively - visit both children
                auto const& child_indices = map->nodes[current_index].child_indices;

                // Push right child first, then left child
                // Since stack is LIFO, left child will be processed first
                if (child_indices[1].has_value()) {  // Right = 1
                    stack.push_back(*child_indices[1]);
                }
                if (child_indices[0].has_value()) {  // Left = 0
                    stack.push_back(*child_indices[0]);
                }
            }

            return map->nodes[current_index];
        }

        /// Get current node index
        std::optional<NodeIndex> current() const noexcept {
            return maybe_current;
        }

        /// Get source node index (if set)
        std::optional<NodeIndex> source() const noexcept {
            return maybe_source;
        }

        /// Get destination node index (if set)
        std::optional<NodeIndex> destination() const noexcept {
            return maybe_destination;
        }

    private:
        /// Internal constructor
        PathIterator(
            Map const* map_ptr,
            NodeIndex start_index
        ) : map(map_ptr),
            maybe_source(start_index)
        {
            stack.push_back(start_index);
        }

        /// Initialize from a specific index
        static PathIterator init_from_index(
            Map const& map_ref,
            NodeIndex start_index
        ) {
            if (start_index >= map_ref.nodes.size()) {
                throw std::runtime_error("Invalid start index");
            }

            return PathIterator(&map_ref, start_index);
        }
    };
};
