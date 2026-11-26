// test_binary_tree.c - Tests for binary tree functionality
// Ported from src/treecode/binary_tree.zig tests

#include "../binary_tree.h"
#include "../../opentime/tests/test_harness.h"

TEST(binary_tree_build_and_path) {
    //
    // Builds Tree:
    //
    // A
    // |\
    // B
    // |\
    // C D
    //   |\
    //     E
    //

    Treecode_Allocator* alloc = &TREECODE_STD_ALLOCATOR;
    BinaryTree tree;
    EXPECT_TRUE(binary_tree_init(&tree, alloc));

    // Root node A
    BinaryTreeNode node_a = { .label = NODE_LABEL_A };
    Treecode root_code;
    EXPECT_TRUE(treecode_init(&root_code, alloc));

    BinaryTreeData data_a = {
        .code = root_code,
        .has_parent = false,
        .has_children = {false, false}
    };

    EXPECT_TRUE(binary_tree_put(&tree, node_a, data_a));
    treecode_deinit(&root_code, alloc);

    BinaryTreeNodeIndex root_index = 0;

    // Node B (left child of A)
    BinaryTreeNode node_b = { .label = NODE_LABEL_B };
    Treecode b_code;
    EXPECT_TRUE(treecode_init(&b_code, alloc));
    EXPECT_TRUE(treecode_append(&b_code, alloc, TREECODE_LEFT));

    BinaryTreeData data_b = {
        .code = b_code,
        .parent_index = root_index,
        .has_parent = true,
        .has_children = {false, false}
    };

    EXPECT_TRUE(binary_tree_put(&tree, node_b, data_b));
    BinaryTreeNodeIndex b_index = 1;
    treecode_deinit(&b_code, alloc);

    // Node C (left child of B)
    BinaryTreeNode node_c = { .label = NODE_LABEL_C };
    Treecode c_code;
    EXPECT_TRUE(treecode_init(&c_code, alloc));
    EXPECT_TRUE(treecode_append(&c_code, alloc, TREECODE_LEFT));
    EXPECT_TRUE(treecode_append(&c_code, alloc, TREECODE_LEFT));

    BinaryTreeData data_c = {
        .code = c_code,
        .parent_index = b_index,
        .has_parent = true,
        .has_children = {false, false}
    };

    EXPECT_TRUE(binary_tree_put(&tree, node_c, data_c));
    BinaryTreeNodeIndex c_index = 2;
    treecode_deinit(&c_code, alloc);

    // Node E first (right child of D, but D not yet added)
    BinaryTreeNode node_e = { .label = NODE_LABEL_E };
    Treecode e_code;
    EXPECT_TRUE(treecode_init(&e_code, alloc));
    EXPECT_TRUE(treecode_append(&e_code, alloc, TREECODE_LEFT));
    EXPECT_TRUE(treecode_append(&e_code, alloc, TREECODE_RIGHT));
    EXPECT_TRUE(treecode_append(&e_code, alloc, TREECODE_RIGHT));

    BinaryTreeData data_e = {
        .code = e_code,
        .has_parent = false,  // Parent not set yet
        .has_children = {false, false}
    };

    EXPECT_TRUE(binary_tree_put(&tree, node_e, data_e));
    BinaryTreeNodeIndex e_index = 3;
    treecode_deinit(&e_code, alloc);

    // Node D (right child of B, parent of E)
    BinaryTreeNode node_d = { .label = NODE_LABEL_D };
    Treecode d_code;
    EXPECT_TRUE(treecode_init(&d_code, alloc));
    EXPECT_TRUE(treecode_append(&d_code, alloc, TREECODE_LEFT));
    EXPECT_TRUE(treecode_append(&d_code, alloc, TREECODE_RIGHT));

    BinaryTreeData data_d = {
        .code = d_code,
        .parent_index = b_index,
        .has_parent = true,
        .has_children = {false, true},
        .child_indices = {0, e_index}
    };

    EXPECT_TRUE(binary_tree_put(&tree, node_d, data_d));
    BinaryTreeNodeIndex d_index = 4;

    // Update E's parent pointer
    tree.tree_data[e_index].parent_index = d_index;
    tree.tree_data[e_index].has_parent = true;

    treecode_deinit(&d_code, alloc);

    // Verify child pointers
    EXPECT_TRUE(tree.tree_data[d_index].has_children[1]);
    EXPECT_EQ(e_index, tree.tree_data[d_index].child_indices[1]);

    // Test path A -> C
    {
        BinaryTreePathEndpoints endpoints = {
            .source = root_index,
            .destination = c_index
        };

        size_t path_length;
        BinaryTreeNodeIndex* path = binary_tree_path(&tree, endpoints, &path_length);
        EXPECT_TRUE(path != NULL);
        EXPECT_EQ(3, path_length);
        EXPECT_EQ(root_index, path[0]);
        EXPECT_EQ(b_index, path[1]);
        EXPECT_EQ(c_index, path[2]);

        alloc->free(alloc->ctx, path, path_length * sizeof(BinaryTreeNodeIndex));
    }

    // Test path A -> E
    {
        BinaryTreePathEndpoints endpoints = {
            .source = root_index,
            .destination = e_index
        };

        size_t path_length;
        BinaryTreeNodeIndex* path = binary_tree_path(&tree, endpoints, &path_length);
        EXPECT_TRUE(path != NULL);
        EXPECT_EQ(4, path_length);
        EXPECT_EQ(root_index, path[0]);
        EXPECT_EQ(b_index, path[1]);
        EXPECT_EQ(d_index, path[2]);
        EXPECT_EQ(e_index, path[3]);

        alloc->free(alloc->ctx, path, path_length * sizeof(BinaryTreeNodeIndex));
    }

    // Test path B -> E
    {
        BinaryTreePathEndpoints endpoints = {
            .source = b_index,
            .destination = e_index
        };

        size_t path_length;
        BinaryTreeNodeIndex* path = binary_tree_path(&tree, endpoints, &path_length);
        EXPECT_TRUE(path != NULL);
        EXPECT_EQ(3, path_length);
        EXPECT_EQ(b_index, path[0]);
        EXPECT_EQ(d_index, path[1]);
        EXPECT_EQ(e_index, path[2]);

        alloc->free(alloc->ctx, path, path_length * sizeof(BinaryTreeNodeIndex));
    }

    // Test path E -> B (reversed)
    {
        BinaryTreePathEndpoints endpoints = {
            .source = e_index,
            .destination = b_index
        };

        size_t path_length;
        BinaryTreeNodeIndex* path = binary_tree_path(&tree, endpoints, &path_length);
        EXPECT_TRUE(path != NULL);
        EXPECT_EQ(3, path_length);
        EXPECT_EQ(e_index, path[0]);
        EXPECT_EQ(d_index, path[1]);
        EXPECT_EQ(b_index, path[2]);

        alloc->free(alloc->ctx, path, path_length * sizeof(BinaryTreeNodeIndex));
    }

    // Test single node path E -> E
    {
        BinaryTreePathEndpoints endpoints = {
            .source = e_index,
            .destination = e_index
        };

        size_t path_length;
        BinaryTreeNodeIndex* path = binary_tree_path(&tree, endpoints, &path_length);
        EXPECT_TRUE(path != NULL);
        EXPECT_EQ(1, path_length);
        EXPECT_EQ(e_index, path[0]);

        alloc->free(alloc->ctx, path, path_length * sizeof(BinaryTreeNodeIndex));
    }

    binary_tree_deinit(&tree);
}

TEST(binary_tree_root_node) {
    Treecode_Allocator* alloc = &TREECODE_STD_ALLOCATOR;
    BinaryTree tree;
    EXPECT_TRUE(binary_tree_init(&tree, alloc));

    // Empty tree
    EXPECT_TRUE(binary_tree_root_node(&tree) == NULL);

    // Add root
    BinaryTreeNode node_a = { .label = NODE_LABEL_A };
    Treecode root_code;
    EXPECT_TRUE(treecode_init(&root_code, alloc));

    BinaryTreeData data_a = {
        .code = root_code,
        .has_parent = false,
        .has_children = {false, false}
    };

    EXPECT_TRUE(binary_tree_put(&tree, node_a, data_a));
    treecode_deinit(&root_code, alloc);

    // Check root
    BinaryTreeNode* root = binary_tree_root_node(&tree);
    EXPECT_TRUE(root != NULL);
    EXPECT_EQ(NODE_LABEL_A, root->label);

    binary_tree_deinit(&tree);
}

TEST(binary_tree_index_lookup) {
    Treecode_Allocator* alloc = &TREECODE_STD_ALLOCATOR;
    BinaryTree tree;
    EXPECT_TRUE(binary_tree_init(&tree, alloc));

    // Add a few nodes
    BinaryTreeNode node_a = { .label = NODE_LABEL_A };
    Treecode code_a;
    EXPECT_TRUE(treecode_init(&code_a, alloc));
    BinaryTreeData data_a = {
        .code = code_a,
        .has_parent = false,
        .has_children = {false, false}
    };
    EXPECT_TRUE(binary_tree_put(&tree, node_a, data_a));
    treecode_deinit(&code_a, alloc);

    BinaryTreeNode node_b = { .label = NODE_LABEL_B };
    Treecode code_b;
    EXPECT_TRUE(treecode_init(&code_b, alloc));
    EXPECT_TRUE(treecode_append(&code_b, alloc, TREECODE_LEFT));
    BinaryTreeData data_b = {
        .code = code_b,
        .parent_index = 0,
        .has_parent = true,
        .has_children = {false, false}
    };
    EXPECT_TRUE(binary_tree_put(&tree, node_b, data_b));
    treecode_deinit(&code_b, alloc);

    // Lookup by node
    BinaryTreeNodeIndex index;
    EXPECT_TRUE(binary_tree_index_for_node(&tree, &node_a, &index));
    EXPECT_EQ(0, index);

    EXPECT_TRUE(binary_tree_index_for_node(&tree, &node_b, &index));
    EXPECT_EQ(1, index);

    // Lookup non-existent node
    BinaryTreeNode node_z = { .label = NODE_LABEL_E };
    EXPECT_FALSE(binary_tree_index_for_node(&tree, &node_z, &index));

    binary_tree_deinit(&tree);
}

TEST(binary_tree_code_lookup) {
    Treecode_Allocator* alloc = &TREECODE_STD_ALLOCATOR;
    BinaryTree tree;
    EXPECT_TRUE(binary_tree_init(&tree, alloc));

    // Add nodes
    BinaryTreeNode node_a = { .label = NODE_LABEL_A };
    Treecode code_a;
    EXPECT_TRUE(treecode_init(&code_a, alloc));
    BinaryTreeData data_a = {
        .code = code_a,
        .has_parent = false,
        .has_children = {false, false}
    };
    EXPECT_TRUE(binary_tree_put(&tree, node_a, data_a));

    // Get code from node
    Treecode* retrieved = binary_tree_code_from_node(&tree, &node_a);
    EXPECT_TRUE(retrieved != NULL);
    EXPECT_EQ(0, retrieved->code_length);

    // Cleanup
    treecode_deinit(&code_a, alloc);
    binary_tree_deinit(&tree);
}

OPENTIME_TEST_MAIN()
