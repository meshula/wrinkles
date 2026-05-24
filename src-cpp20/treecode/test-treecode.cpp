#include "treecode.hpp"
#include <iostream>
#include <sstream>
#include <string_view>
#include <stdexcept>

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

//
// ─── TREECODE TESTS ──────────────────────────────────────────────────────────
//

// Test: Basic initialization
TEST_CASE(test_init) {
    auto tc = Treecode::init();
    REQUIRE(tc.words.size() == 1);
    REQUIRE(tc.words[0] == MARKER);
    REQUIRE(tc.code_length() == 0);
}

// Test: Initialize from word
TEST_CASE(test_init_word) {
    auto tc = Treecode::init_word(0b1011);
    REQUIRE(tc.words.size() == 1);
    REQUIRE(tc.words[0] == 0b1011);
    REQUIRE(tc.code_length() == 3);  // 3 bits after marker
}

// Test: Clone
TEST_CASE(test_clone) {
    auto tc1 = Treecode::init_word(0b1011);
    auto tc2 = tc1.clone();

    REQUIRE(tc1.eql(tc2));
    REQUIRE(tc2.words[0] == tc1.words[0]);

    // Modify tc2 to ensure it's a deep copy
    tc2.append(LeftOrRight::Left);
    REQUIRE(!tc1.eql(tc2));
}

// Test: Code length for various patterns
TEST_CASE(test_code_length) {
    // Empty treecode (just marker)
    auto tc = Treecode::init();
    REQUIRE(tc.code_length() == 0);

    // Single bit path
    tc = Treecode::init_word(0b10);  // marker + 1 bit
    REQUIRE(tc.code_length() == 1);

    // Three bit path
    tc = Treecode::init_word(0b1011);  // marker + 3 bits
    REQUIRE(tc.code_length() == 3);

    // Eight bit path
    tc = Treecode::init_word(0b111001101);  // marker + 8 bits
    REQUIRE(tc.code_length() == 8);
}

// Test: Append single word
TEST_CASE(test_append_single_word) {
    auto tc = Treecode::init();

    // Append right
    tc.append(LeftOrRight::Right);
    REQUIRE(tc.code_length() == 1);
    REQUIRE(tc.words[0] == 0b11);  // marker + right (1)

    // Append left
    tc.append(LeftOrRight::Left);
    REQUIRE(tc.code_length() == 2);
    REQUIRE(tc.words[0] == 0b101);  // marker + right + left (10)

    // Append right again
    tc.append(LeftOrRight::Right);
    REQUIRE(tc.code_length() == 3);
    REQUIRE(tc.words[0] == 0b1101);  // marker + right + left + right (110)
}

// Test: Append to empty treecode should throw
TEST_CASE(test_append_empty_throws) {
    auto tc = Treecode{};  // Default constructor - empty

    bool threw = false;
    try {
        tc.append(LeftOrRight::Left);
    } catch (std::runtime_error const&) {
        threw = true;
    }

    REQUIRE(threw);
}

// Test: Equality
TEST_CASE(test_eql) {
    auto tc1 = Treecode::init_word(0b1011);
    auto tc2 = Treecode::init_word(0b1011);
    auto tc3 = Treecode::init_word(0b1101);

    REQUIRE(tc1.eql(tc2));
    REQUIRE(!tc1.eql(tc3));

    // Test with different vector sizes but same value
    auto tc4 = Treecode::init_word(0b1);
    tc4.words.resize(3, 0);  // Pad with zeros
    auto tc5 = Treecode::init();
    REQUIRE(tc4.eql(tc5));
}

// Test: is_prefix_of basic cases
TEST_CASE(test_is_prefix_of_basic) {
    // Empty path is prefix of anything
    auto empty = Treecode::init();
    auto path = Treecode::init_word(0b1011);
    REQUIRE(empty.is_prefix_of(path));
    REQUIRE(empty.is_prefix_of(empty));

    // Same path is prefix of itself
    auto tc1 = Treecode::init_word(0b1011);
    auto tc2 = Treecode::init_word(0b1011);
    REQUIRE(tc1.is_prefix_of(tc2));
}

// Test: is_prefix_of parent-child relationship
TEST_CASE(test_is_prefix_of_parent_child) {
    // 0b1101 should be prefix of 0b00101 (0b1101 with extra 0 appended)
    auto parent = Treecode::init_word(0b1101);
    auto child = Treecode::init_word(0b10101);

    REQUIRE(parent.is_prefix_of(child));
    REQUIRE(!child.is_prefix_of(parent));  // Child is not prefix of parent

    // 0b10 is not prefix of 0b1
    auto longer = Treecode::init_word(0b10);
    auto shorter = Treecode::init();
    REQUIRE(!longer.is_prefix_of(shorter));
}

// Test: is_prefix_of non-related paths
TEST_CASE(test_is_prefix_of_non_related) {
    // 0b1101 is not prefix of 0b1010 (different paths)
    auto tc1 = Treecode::init_word(0b1101);
    auto tc2 = Treecode::init_word(0b1010);

    REQUIRE(!tc1.is_prefix_of(tc2));
    REQUIRE(!tc2.is_prefix_of(tc1));
}

// Test: Hash consistency
TEST_CASE(test_hash) {
    auto tc1 = Treecode::init_word(0b1011);
    auto tc2 = Treecode::init_word(0b1011);
    auto tc3 = Treecode::init_word(0b1101);

    // Equal treecodes should have same hash
    REQUIRE(tc1.hash() == tc2.hash());

    // Different treecodes should (likely) have different hash
    // Note: Hash collisions are possible but unlikely
    REQUIRE(tc1.hash() != tc3.hash());
}

// Test: next_step_towards
TEST_CASE(test_next_step_towards) {
    // 0b1 next step toward 0b11 should be Right
    auto start = Treecode::init();
    auto dest = Treecode::init_word(0b11);
    REQUIRE(start.next_step_towards(dest) == LeftOrRight::Right);

    // 0b101 next step toward 0b10101 should be Right
    // 0b101 = marker + path "01" (R,L)
    // 0b10101 = marker + path "0101" (R,L,R,L)
    // Next step after position 2 is bit 2 = 1 = Right
    start = Treecode::init_word(0b101);
    dest = Treecode::init_word(0b10101);
    REQUIRE(start.next_step_towards(dest) == LeftOrRight::Right);

    // 0b101 next step toward 0b111011101 should be Right
    start = Treecode::init_word(0b101);
    dest = Treecode::init_word(0b111011101);
    REQUIRE(start.next_step_towards(dest) == LeftOrRight::Right);
}

// Test: Multi-word treecode growth
TEST_CASE(test_multiword_growth) {
    auto tc = Treecode::init();

    // Append 70 bits to force multi-word usage
    for (int i = 0; i < 70; ++i) {
        tc.append((i % 2 == 0) ? LeftOrRight::Left : LeftOrRight::Right);
    }

    REQUIRE(tc.code_length() == 70);
    REQUIRE(tc.words.size() > 1);  // Should have grown beyond single word
}

// Test: Multi-word equality
TEST_CASE(test_multiword_eql) {
    auto tc1 = Treecode::init();
    auto tc2 = Treecode::init();

    // Build identical multi-word treecodes
    for (int i = 0; i < 70; ++i) {
        auto branch = (i % 2 == 0) ? LeftOrRight::Left : LeftOrRight::Right;
        tc1.append(branch);
        tc2.append(branch);
    }

    REQUIRE(tc1.eql(tc2));

    // Modify tc2 to make it different
    tc2.append(LeftOrRight::Right);
    REQUIRE(!tc1.eql(tc2));
}

// Test: Multi-word is_prefix_of
TEST_CASE(test_multiword_is_prefix_of) {
    auto parent = Treecode::init();

    // Build 65-bit path
    for (int i = 0; i < 65; ++i) {
        parent.append((i % 2 == 0) ? LeftOrRight::Left : LeftOrRight::Right);
    }

    auto child = parent.clone();
    child.append(LeftOrRight::Right);
    child.append(LeftOrRight::Left);

    REQUIRE(parent.is_prefix_of(child));
    REQUIRE(!child.is_prefix_of(parent));
}

// Test: TreecodeHash functor
TEST_CASE(test_treecode_hash_functor) {
    TreecodeHash hasher;

    auto tc1 = Treecode::init_word(0b1011);
    auto tc2 = Treecode::init_word(0b1011);

    REQUIRE(hasher(tc1) == hasher(tc2));
}

// Test: TreecodeEqual functor
TEST_CASE(test_treecode_equal_functor) {
    TreecodeEqual eq;

    auto tc1 = Treecode::init_word(0b1011);
    auto tc2 = Treecode::init_word(0b1011);
    auto tc3 = Treecode::init_word(0b1101);

    REQUIRE(eq(tc1, tc2));
    REQUIRE(!eq(tc1, tc3));
}

// Test: TreecodeHashMap usage
TEST_CASE(test_treecode_hashmap) {
    TreecodeHashMap<int> map;

    auto tc1 = Treecode::init_word(0b1011);
    auto tc2 = Treecode::init_word(0b1101);

    map[tc1] = 42;
    map[tc2] = 99;

    REQUIRE(map[tc1] == 42);
    REQUIRE(map[tc2] == 99);

    // Test retrieval with clone
    auto tc1_clone = tc1.clone();
    REQUIRE(map[tc1_clone] == 42);
}

// Test: Stream output
TEST_CASE(test_stream_output) {
    auto tc = Treecode::init_word(0b1011);
    std::ostringstream oss;
    oss << tc;

    REQUIRE(oss.str() == "0b1011");
}

//
// ─── MAIN ────────────────────────────────────────────────────────────────────
//
int main() {
    return tinytest::run_all();
}
