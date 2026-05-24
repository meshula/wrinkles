#include "map.hpp"
#include <iostream>
#include <sstream>
#include <string_view>

//
// ─── MINIMAL TEST HARNESS ────────────────────────────────────────────────────
//
namespace tinytest {
    using test_fn = void(*)();
    struct registry {
        static inline std::vector<std::pair<std::string_view, test_fn>> tests;
        static void add(std::string_view name, test_fn fn) { tests.emplace_back(name, fn); }
    };

    struct registrar {
        registrar(std::string_view name, test_fn fn) { registry::add(name, fn); }
    };

    struct failure : std::exception {
        std::string msg;
        failure(std::string m): msg(std::move(m)) {}
        const char* what() const noexcept override { return msg.c_str(); }
    };

    inline void require(bool cond, std::string_view expr, std::string_view file, int line) {
        if (!cond) {
            throw failure(std::string(file) + ":" + std::to_string(line) + ": REQUIRE failed: " + std::string(expr));
        }
    }

    inline int run_all() {
        int passed = 0, failed = 0;
        for (auto& [name, fn] : registry::tests) {
            try {
                fn();
                std::cout << "[ OK ] " << name << "\n";
                ++passed;
            } catch (failure const& e) {
                std::cerr << "[FAIL] " << name << ": " << e.what() << "\n";
                ++failed;
            } catch (std::exception const& e) {
                std::cerr << "[FAIL] " << name << ": unexpected exception: " << e.what() << "\n";
                ++failed;
            }
        }
        std::cout << "\nTests passed: " << passed << " / " << (passed + failed) << "\n";
        return failed == 0 ? 0 : 1;
    }
}

#define TEST_CASE(name) \
    static void name(); \
    static ::tinytest::registrar name##_reg{#name, name}; \
    static void name()

#define REQUIRE(expr) ::tinytest::require((expr), #expr, __FILE__, __LINE__)

// Use int as GraphNodeType for simplicity
using TestMap = Map<int>;
using TestPathNode = TestMap::PathNode;

//
// ─── MAP TESTS ───────────────────────────────────────────────────────────────
//

// Test: Basic map construction
TEST_CASE(test_map_construction) {
    TestMap map;
    REQUIRE(map.empty());
    REQUIRE(map.size() == 0);
}

// Test: Put root node
TEST_CASE(test_put_root) {
    TestMap map;

    auto root_code = Treecode::init();
    TestPathNode root_node{42, root_code.clone()};

    NodeIndex root_idx = map.put(std::move(root_node));

    REQUIRE(root_idx == 0);
    REQUIRE(map.size() == 1);
    REQUIRE(!map.empty());
    REQUIRE(map.root() == 42);
}

// Test: Bidirectional lookup
TEST_CASE(test_bidirectional_lookup) {
    TestMap map;

    auto code = Treecode::init_word(0b1011);
    TestPathNode node{100, code.clone()};

    map.put(std::move(node));

    // Lookup by code
    auto space_opt = map.get_space(code);
    REQUIRE(space_opt.has_value());
    REQUIRE(*space_opt == 100);

    // Lookup by space
    auto code_opt = map.get_code(100);
    REQUIRE(code_opt.has_value());
    REQUIRE(code_opt->eql(code));
}

// Test: Lookup non-existent entries
TEST_CASE(test_lookup_nonexistent) {
    TestMap map;

    auto code = Treecode::init_word(0b1011);
    TestPathNode node{100, code.clone()};
    map.put(std::move(node));

    // Lookup with different code
    auto other_code = Treecode::init_word(0b1101);
    auto space_opt = map.get_space(other_code);
    REQUIRE(!space_opt.has_value());

    // Lookup with different space
    auto code_opt = map.get_code(999);
    REQUIRE(!code_opt.has_value());
}

// Test: fetch_index operations
TEST_CASE(test_fetch_index) {
    TestMap map;

    auto code = Treecode::init_word(0b1011);
    TestPathNode node{100, code.clone()};

    NodeIndex idx = map.put(std::move(node));

    // Fetch by code
    auto idx_by_code = map.fetch_index_by_code(code);
    REQUIRE(idx_by_code.has_value());
    REQUIRE(*idx_by_code == idx);

    // Fetch by space
    auto idx_by_space = map.fetch_index_by_space(100);
    REQUIRE(idx_by_space.has_value());
    REQUIRE(*idx_by_space == idx);
}

// Test: Parent-child relationships
TEST_CASE(test_parent_child) {
    TestMap map;

    // Create root
    auto root_code = Treecode::init();
    TestPathNode root_node{0, root_code.clone()};
    NodeIndex root_idx = map.put(std::move(root_node));

    // Create child (append Right to root)
    auto child_code = root_code.clone();
    child_code.append(LeftOrRight::Right);
    TestPathNode child_node{1, child_code.clone(), root_idx};
    NodeIndex child_idx = map.put(std::move(child_node));

    // Verify parent has child registered
    auto const& root_from_map = map.get_node(root_idx);
    REQUIRE(root_from_map.child_indices[1].has_value());  // Right = 1
    REQUIRE(*root_from_map.child_indices[1] == child_idx);
    REQUIRE(!root_from_map.child_indices[0].has_value());  // Left = 0

    // Verify child has parent
    auto const& child_from_map = map.get_node(child_idx);
    REQUIRE(child_from_map.parent_index.has_value());
    REQUIRE(*child_from_map.parent_index == root_idx);
}

// Test: Build a small tree
TEST_CASE(test_build_tree) {
    TestMap map;

    // Root
    auto root_code = Treecode::init();
    NodeIndex root_idx = map.put(TestPathNode{0, root_code.clone()});

    // Left child (0b10 = marker + 0)
    auto left_code = root_code.clone();
    left_code.append(LeftOrRight::Left);
    NodeIndex left_idx = map.put(TestPathNode{1, left_code.clone(), root_idx});

    // Right child (0b11 = marker + 1)
    auto right_code = root_code.clone();
    right_code.append(LeftOrRight::Right);
    NodeIndex right_idx = map.put(TestPathNode{2, right_code.clone(), root_idx});

    // Verify tree structure
    REQUIRE(map.size() == 3);

    auto const& root = map.get_node(root_idx);
    REQUIRE(root.child_indices[0] == left_idx);
    REQUIRE(root.child_indices[1] == right_idx);

    auto const& left = map.get_node(left_idx);
    REQUIRE(left.parent_index == root_idx);
    REQUIRE(left.space == 1);

    auto const& right = map.get_node(right_idx);
    REQUIRE(right.parent_index == root_idx);
    REQUIRE(right.space == 2);
}

// Test: Iterator from root
TEST_CASE(test_iterator_from_root) {
    TestMap map;

    // Build simple tree: root with two children
    auto root_code = Treecode::init();
    NodeIndex root_idx = map.put(TestPathNode{0, root_code.clone()});

    auto left_code = root_code.clone();
    left_code.append(LeftOrRight::Left);
    map.put(TestPathNode{1, left_code.clone(), root_idx});

    auto right_code = root_code.clone();
    right_code.append(LeftOrRight::Right);
    map.put(TestPathNode{2, right_code.clone(), root_idx});

    // Iterate and collect spaces
    auto iter = map.iter();
    std::vector<int> visited;

    while (auto node_opt = iter.next()) {
        visited.push_back(node_opt->space);
    }

    REQUIRE(visited.size() == 3);
    REQUIRE(visited[0] == 0);  // Root
    // Order depends on traversal: left before right (depth-first)
    REQUIRE(visited[1] == 1);  // Left child
    REQUIRE(visited[2] == 2);  // Right child
}

// Test: Iterator from specific node
TEST_CASE(test_iterator_from_node) {
    TestMap map;

    // Build tree
    auto root_code = Treecode::init();
    NodeIndex root_idx = map.put(TestPathNode{0, root_code.clone()});

    auto left_code = root_code.clone();
    left_code.append(LeftOrRight::Left);
    NodeIndex left_idx = map.put(TestPathNode{1, left_code.clone(), root_idx});

    // Add child to left
    auto left_left_code = left_code.clone();
    left_left_code.append(LeftOrRight::Left);
    map.put(TestPathNode{3, left_left_code.clone(), left_idx});

    auto right_code = root_code.clone();
    right_code.append(LeftOrRight::Right);
    map.put(TestPathNode{2, right_code.clone(), root_idx});

    // Iterate from left child (space = 1)
    auto iter = map.iter_from(1);
    std::vector<int> visited;

    while (auto node_opt = iter.next()) {
        visited.push_back(node_opt->space);
    }

    REQUIRE(visited.size() == 2);  // Should visit node 1 and its child 3
    REQUIRE(visited[0] == 1);
    REQUIRE(visited[1] == 3);
}

// Test: Iterator from one node to another
TEST_CASE(test_iterator_from_to) {
    TestMap map;

    // Build tree: root -> left -> left_left
    auto root_code = Treecode::init();
    NodeIndex root_idx = map.put(TestPathNode{0, root_code.clone()});

    auto left_code = root_code.clone();
    left_code.append(LeftOrRight::Left);
    NodeIndex left_idx = map.put(TestPathNode{1, left_code.clone(), root_idx});

    auto left_left_code = left_code.clone();
    left_left_code.append(LeftOrRight::Left);
    map.put(TestPathNode{2, left_left_code.clone(), left_idx});

    // Also add a right child to root (should not be visited)
    auto right_code = root_code.clone();
    right_code.append(LeftOrRight::Right);
    map.put(TestPathNode{99, right_code.clone(), root_idx});

    // Iterate from root (0) to left_left (2)
    auto iter = map.iter_from_to(TestMap::PathEndPoints{0, 2});
    std::vector<int> visited;

    while (auto node_opt = iter.next()) {
        visited.push_back(node_opt->space);
    }

    REQUIRE(visited.size() == 3);  // root, left, left_left
    REQUIRE(visited[0] == 0);
    REQUIRE(visited[1] == 1);
    REQUIRE(visited[2] == 2);
}

// Test: sort_endpoints
TEST_CASE(test_sort_endpoints) {
    TestMap map;

    // Build simple path: root -> child
    auto root_code = Treecode::init();
    map.put(TestPathNode{0, root_code.clone()});

    auto child_code = root_code.clone();
    child_code.append(LeftOrRight::Right);
    map.put(TestPathNode{1, child_code.clone(), 0});

    // Create endpoints with child as source (should swap)
    TestMap::PathEndPoints endpoints{1, 0};  // child -> root

    bool swapped = map.sort_endpoints(endpoints);

    REQUIRE(swapped);
    REQUIRE(endpoints.source == 0);  // Now root is source
    REQUIRE(endpoints.destination == 1);  // And child is destination
}

// Test: sort_endpoints with already correct order
TEST_CASE(test_sort_endpoints_no_swap) {
    TestMap map;

    auto root_code = Treecode::init();
    map.put(TestPathNode{0, root_code.clone()});

    auto child_code = root_code.clone();
    child_code.append(LeftOrRight::Right);
    map.put(TestPathNode{1, child_code.clone(), 0});

    // Create endpoints with correct order
    TestMap::PathEndPoints endpoints{0, 1};  // root -> child

    bool swapped = map.sort_endpoints(endpoints);

    REQUIRE(!swapped);
    REQUIRE(endpoints.source == 0);
    REQUIRE(endpoints.destination == 1);
}

// Test: sort_endpoints with no path should throw
TEST_CASE(test_sort_endpoints_no_path) {
    TestMap map;

    // Create two separate nodes with no path between them
    auto code1 = Treecode::init_word(0b1011);
    map.put(TestPathNode{0, code1.clone()});

    auto code2 = Treecode::init_word(0b1101);
    map.put(TestPathNode{1, code2.clone()});

    TestMap::PathEndPoints endpoints{0, 1};

    bool threw = false;
    try {
        map.sort_endpoints(endpoints);
    } catch (std::runtime_error const&) {
        threw = true;
    }

    REQUIRE(threw);
}

// Test: Empty map root should throw
TEST_CASE(test_empty_map_root_throws) {
    TestMap map;

    bool threw = false;
    try {
        auto r = map.root();
        (void)r;  // Suppress unused variable warning
    } catch (std::runtime_error const&) {
        threw = true;
    }

    REQUIRE(threw);
}

// Test: get_node with invalid index should throw
TEST_CASE(test_get_node_invalid_throws) {
    TestMap map;

    auto root_code = Treecode::init();
    map.put(TestPathNode{0, root_code.clone()});

    bool threw = false;
    try {
        auto node = map.get_node(999);
        (void)node;
    } catch (std::runtime_error const&) {
        threw = true;
    }

    REQUIRE(threw);
}

//
// ─── MAIN ────────────────────────────────────────────────────────────────────
//
int main() {
    return tinytest::run_all();
}
