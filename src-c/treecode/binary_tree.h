// binary_tree.h - Binary tree with treecode addressing
// Ported from src/treecode/binary_tree.zig
//
// A BinaryTree where nodes are addressed using Treecode paths.
// This enables O(1) path existence checks and efficient navigation.
//
// This is a monomorphic implementation - for full generic usage,
// see the Zig source. In practice, only one node type is used.

#pragma once

#include "treecode.h"
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

//=============================================================================
// Node type definition
//=============================================================================

// Forward declaration - users can define their own node types
// For now, we'll use a simple test node type
typedef struct BinaryTreeNode BinaryTreeNode;

// Simple test node type (can be replaced with domain-specific types)
typedef enum {
    NODE_LABEL_A = 0,
    NODE_LABEL_B,
    NODE_LABEL_C,
    NODE_LABEL_D,
    NODE_LABEL_E,
} NodeLabel;

struct BinaryTreeNode {
    NodeLabel label;
};

// Hash function for nodes (required)
static inline TreecodeHash binary_tree_node_hash(const BinaryTreeNode* node) {
    return (TreecodeHash)node->label;
}

//=============================================================================
// Tree data structures
//=============================================================================

/// Index type for nodes in the tree
typedef size_t BinaryTreeNodeIndex;

/// Graph information (parent/children/treecode) for a node
typedef struct {
    /// Address in the tree (owned by the tree)
    Treecode code;
    /// Index of parent node (if present)
    BinaryTreeNodeIndex parent_index;
    bool has_parent;
    /// Indices of children [left, right]
    BinaryTreeNodeIndex child_indices[2];
    bool has_children[2];
} BinaryTreeData;

/// A binary tree with treecode addressing
typedef struct {
    /// The nodes in the tree
    BinaryTreeNode* nodes;
    size_t node_count;
    size_t node_capacity;

    /// Tree data (parent/child/treecode) for each node
    BinaryTreeData* tree_data;
    size_t tree_data_count;
    size_t tree_data_capacity;

    /// Simple hash map: hash -> index
    /// (In production, use a proper hash table)
    TreecodeHash* map_keys;
    BinaryTreeNodeIndex* map_values;
    size_t map_count;
    size_t map_capacity;

    /// Allocator
    Treecode_Allocator* allocator;
} BinaryTree;

//=============================================================================
// Initialization and cleanup
//=============================================================================

/// Initialize an empty binary tree
static inline bool binary_tree_init(
    BinaryTree* tree,
    Treecode_Allocator* allocator
) {
    tree->nodes = NULL;
    tree->node_count = 0;
    tree->node_capacity = 0;

    tree->tree_data = NULL;
    tree->tree_data_count = 0;
    tree->tree_data_capacity = 0;

    tree->map_keys = NULL;
    tree->map_values = NULL;
    tree->map_count = 0;
    tree->map_capacity = 0;

    tree->allocator = allocator;
    return true;
}

/// Free all tree resources
static inline void binary_tree_deinit(BinaryTree* tree) {
    // Free all treecodes
    for (size_t i = 0; i < tree->tree_data_count; i++) {
        treecode_deinit(&tree->tree_data[i].code, tree->allocator);
    }

    if (tree->nodes) {
        tree->allocator->free(
            tree->allocator->ctx,
            tree->nodes,
            tree->node_capacity * sizeof(BinaryTreeNode)
        );
    }

    if (tree->tree_data) {
        tree->allocator->free(
            tree->allocator->ctx,
            tree->tree_data,
            tree->tree_data_capacity * sizeof(BinaryTreeData)
        );
    }

    if (tree->map_keys) {
        tree->allocator->free(
            tree->allocator->ctx,
            tree->map_keys,
            tree->map_capacity * sizeof(TreecodeHash)
        );
    }

    if (tree->map_values) {
        tree->allocator->free(
            tree->allocator->ctx,
            tree->map_values,
            tree->map_capacity * sizeof(BinaryTreeNodeIndex)
        );
    }
}

//=============================================================================
// Internal helpers
//=============================================================================

// Simple linear probe hash map lookup
static inline bool binary_tree_map_get(
    const BinaryTree* tree,
    TreecodeHash key,
    BinaryTreeNodeIndex* out_value
) {
    if (tree->map_count == 0) return false;

    size_t start = (size_t)(key % tree->map_capacity);
    for (size_t i = 0; i < tree->map_capacity; i++) {
        size_t idx = (start + i) % tree->map_capacity;
        if (tree->map_keys[idx] == key) {
            *out_value = tree->map_values[idx];
            return true;
        }
        if (tree->map_keys[idx] == 0 && i > 0) {
            // Empty slot (assuming 0 is not a valid hash)
            return false;
        }
    }
    return false;
}

// Simple linear probe hash map insert
static inline bool binary_tree_map_put(
    BinaryTree* tree,
    TreecodeHash key,
    BinaryTreeNodeIndex value
) {
    // Grow if needed (load factor > 0.7)
    if (tree->map_count >= tree->map_capacity * 7 / 10) {
        size_t new_capacity = tree->map_capacity == 0 ? 16 : tree->map_capacity * 2;

        TreecodeHash* new_keys = tree->allocator->alloc(
            tree->allocator->ctx,
            new_capacity * sizeof(TreecodeHash)
        );
        BinaryTreeNodeIndex* new_values = tree->allocator->alloc(
            tree->allocator->ctx,
            new_capacity * sizeof(BinaryTreeNodeIndex)
        );

        if (!new_keys || !new_values) return false;

        memset(new_keys, 0, new_capacity * sizeof(TreecodeHash));
        memset(new_values, 0, new_capacity * sizeof(BinaryTreeNodeIndex));

        // Rehash existing entries
        for (size_t i = 0; i < tree->map_capacity; i++) {
            if (tree->map_keys[i] != 0) {
                size_t start = (size_t)(tree->map_keys[i] % new_capacity);
                for (size_t j = 0; j < new_capacity; j++) {
                    size_t idx = (start + j) % new_capacity;
                    if (new_keys[idx] == 0) {
                        new_keys[idx] = tree->map_keys[i];
                        new_values[idx] = tree->map_values[i];
                        break;
                    }
                }
            }
        }

        if (tree->map_keys) {
            tree->allocator->free(
                tree->allocator->ctx,
                tree->map_keys,
                tree->map_capacity * sizeof(TreecodeHash)
            );
        }
        if (tree->map_values) {
            tree->allocator->free(
                tree->allocator->ctx,
                tree->map_values,
                tree->map_capacity * sizeof(BinaryTreeNodeIndex)
            );
        }

        tree->map_keys = new_keys;
        tree->map_values = new_values;
        tree->map_capacity = new_capacity;
    }

    // Insert
    size_t start = (size_t)(key % tree->map_capacity);
    for (size_t i = 0; i < tree->map_capacity; i++) {
        size_t idx = (start + i) % tree->map_capacity;
        if (tree->map_keys[idx] == 0 || tree->map_keys[idx] == key) {
            if (tree->map_keys[idx] == 0) tree->map_count++;
            tree->map_keys[idx] = key;
            tree->map_values[idx] = value;
            return true;
        }
    }
    return false;
}

//=============================================================================
// Tree operations
//=============================================================================

/// Ensure capacity for additional nodes
static inline bool binary_tree_ensure_capacity(
    BinaryTree* tree,
    size_t additional
) {
    size_t needed = tree->node_count + additional;

    if (needed > tree->node_capacity) {
        size_t new_capacity = tree->node_capacity == 0 ? 16 : tree->node_capacity;
        while (new_capacity < needed) new_capacity *= 2;

        BinaryTreeNode* new_nodes = tree->allocator->realloc(
            tree->allocator->ctx,
            tree->nodes,
            tree->node_capacity * sizeof(BinaryTreeNode),
            new_capacity * sizeof(BinaryTreeNode)
        );
        if (!new_nodes) return false;
        tree->nodes = new_nodes;
        tree->node_capacity = new_capacity;
    }

    if (needed > tree->tree_data_capacity) {
        size_t new_capacity = tree->tree_data_capacity == 0 ? 16 : tree->tree_data_capacity;
        while (new_capacity < needed) new_capacity *= 2;

        BinaryTreeData* new_data = tree->allocator->realloc(
            tree->allocator->ctx,
            tree->tree_data,
            tree->tree_data_capacity * sizeof(BinaryTreeData),
            new_capacity * sizeof(BinaryTreeData)
        );
        if (!new_data) return false;
        tree->tree_data = new_data;
        tree->tree_data_capacity = new_capacity;
    }

    return true;
}

/// Add a node to the tree
static inline bool binary_tree_put(
    BinaryTree* tree,
    BinaryTreeNode node,
    BinaryTreeData tree_data  // treecode is owned by caller, will be cloned
) {
    if (!binary_tree_ensure_capacity(tree, 1)) {
        return false;
    }

    // Clone the treecode (tree takes ownership)
    Treecode code_copy;
    if (!treecode_clone(&tree_data.code, &code_copy, tree->allocator)) {
        return false;
    }

    // Add node
    BinaryTreeNodeIndex new_index = tree->node_count;
    tree->nodes[new_index] = node;
    tree->node_count++;

    // Add tree data
    tree_data.code = code_copy;  // Use the cloned treecode
    tree->tree_data[new_index] = tree_data;
    tree->tree_data_count++;

    // Add to map
    TreecodeHash hash = binary_tree_node_hash(&node);
    if (!binary_tree_map_put(tree, hash, new_index)) {
        return false;
    }

    // Connect parent pointer
    if (tree_data.has_parent) {
        BinaryTreeNodeIndex parent_index = tree_data.parent_index;
        Treecode* parent_code = &tree->tree_data[parent_index].code;
        Treecode_LorR dir = treecode_next_step_towards(parent_code, &code_copy);
        tree->tree_data[parent_index].child_indices[(int)dir] = new_index;
        tree->tree_data[parent_index].has_children[(int)dir] = true;
    }

    return true;
}

/// Get the root node (index 0)
static inline BinaryTreeNode* binary_tree_root_node(BinaryTree* tree) {
    if (tree->node_count == 0) return NULL;
    return &tree->nodes[0];
}

/// Find node index by node value
static inline bool binary_tree_index_for_node(
    const BinaryTree* tree,
    const BinaryTreeNode* node,
    BinaryTreeNodeIndex* out_index
) {
    TreecodeHash hash = binary_tree_node_hash(node);
    return binary_tree_map_get(tree, hash, out_index);
}

/// Get treecode for a node
static inline Treecode* binary_tree_code_from_node(
    BinaryTree* tree,
    const BinaryTreeNode* node
) {
    BinaryTreeNodeIndex index;
    if (binary_tree_index_for_node(tree, node, &index)) {
        return &tree->tree_data[index].code;
    }
    return NULL;
}

//=============================================================================
// Path operations
//=============================================================================

/// Path endpoints (by index)
typedef struct {
    BinaryTreeNodeIndex source;
    BinaryTreeNodeIndex destination;
} BinaryTreePathEndpoints;

/// Sort endpoints (parent first, then child)
/// Returns true if they were swapped
static inline bool binary_tree_sort_endpoints(
    const BinaryTree* tree,
    BinaryTreePathEndpoints* endpoints
) {
    const Treecode* source_code = &tree->tree_data[endpoints->source].code;
    const Treecode* dest_code = &tree->tree_data[endpoints->destination].code;

    if (!treecode_path_exists(source_code, dest_code)) {
        return false; // No path exists
    }

    // Swap if source is deeper than dest
    if (source_code->code_length > dest_code->code_length) {
        BinaryTreeNodeIndex temp = endpoints->source;
        endpoints->source = endpoints->destination;
        endpoints->destination = temp;
        return true;
    }

    return false;
}

/// Compute path from source to destination
/// Returns allocated array of indices (caller must free)
static inline BinaryTreeNodeIndex* binary_tree_path(
    const BinaryTree* tree,
    BinaryTreePathEndpoints endpoints,
    size_t* out_length
) {
    // Sort so source is parent of destination
    BinaryTreePathEndpoints sorted = endpoints;
    bool swapped = binary_tree_sort_endpoints(tree, &sorted);

    const Treecode* source_code = &tree->tree_data[sorted.source].code;
    const Treecode* dest_code = &tree->tree_data[sorted.destination].code;

    size_t length = dest_code->code_length - source_code->code_length + 1;

    BinaryTreeNodeIndex* path = tree->allocator->alloc(
        tree->allocator->ctx,
        length * sizeof(BinaryTreeNodeIndex)
    );
    if (!path) return NULL;

    // Fill path from destination backwards to source
    BinaryTreeNodeIndex current = sorted.destination;
    path[0] = sorted.source;

    for (size_t i = 0; i < length - 1; i++) {
        path[length - 1 - i] = current;
        if (tree->tree_data[current].has_parent) {
            current = tree->tree_data[current].parent_index;
        }
    }

    // Reverse if we swapped
    if (swapped) {
        for (size_t i = 0; i < length / 2; i++) {
            BinaryTreeNodeIndex temp = path[i];
            path[i] = path[length - 1 - i];
            path[length - 1 - i] = temp;
        }
    }

    *out_length = length;
    return path;
}
