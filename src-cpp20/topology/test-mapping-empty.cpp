#include "mapping_empty.hpp"
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

//
// ─── MAPPING EMPTY TESTS ─────────────────────────────────────────────────────
//

// Test: Basic construction
TEST_CASE(test_construction) {
    auto empty = MappingEmpty{};
    REQUIRE(empty.defined_range.start.eql(Ordinate::init(0.0)));
    REQUIRE(empty.defined_range.end.eql(Ordinate::init(0.0)));
}

// Test: Construction with range
TEST_CASE(test_construction_with_range) {
    auto range = ContinuousInterval{
        Ordinate::init(-2.0),
        Ordinate::init(2.0)
    };
    auto empty = MappingEmpty{range};

    REQUIRE(empty.defined_range.start.eql(Ordinate::init(-2.0)));
    REQUIRE(empty.defined_range.end.eql(Ordinate::init(2.0)));
}

// Test: init static method
TEST_CASE(test_init) {
    auto range = ContinuousInterval{
        Ordinate::init(10.0),
        Ordinate::init(20.0)
    };
    auto empty = MappingEmpty::init(range);

    REQUIRE(empty.defined_range.start.eql(Ordinate::init(10.0)));
    REQUIRE(empty.defined_range.end.eql(Ordinate::init(20.0)));
}

// Test: EMPTY_INF constant
TEST_CASE(test_empty_inf) {
    REQUIRE(EMPTY_INF.defined_range.start.eql(Ordinate::init(0.0)));
    REQUIRE(EMPTY_INF.defined_range.end.eql(Ordinate::init(0.0)));
}

// Test: project_instantaneous_cc always returns OutOfBounds
TEST_CASE(test_project_instantaneous_cc) {
    auto empty = MappingEmpty::init(
        ContinuousInterval{Ordinate::init(-10.0), Ordinate::init(10.0)}
    );

    // Test various ordinates - all should return OutOfBounds
    for (double v = -10.0; v <= 10.0; v += 0.5) {
        auto result = empty.project_instantaneous_cc(Ordinate::init(v));
        REQUIRE(result.is_out_of_bounds());
    }
}

// Test: project_instantaneous_cc_inv always returns OutOfBounds
TEST_CASE(test_project_instantaneous_cc_inv) {
    auto empty = MappingEmpty::init(
        ContinuousInterval{Ordinate::init(-10.0), Ordinate::init(10.0)}
    );

    // Test various ordinates - all should return OutOfBounds
    for (double v = -10.0; v <= 10.0; v += 0.5) {
        auto result = empty.project_instantaneous_cc_inv(Ordinate::init(v));
        REQUIRE(result.is_out_of_bounds());
    }
}

// Test: input_bounds
TEST_CASE(test_input_bounds) {
    auto range = ContinuousInterval{
        Ordinate::init(-2.0),
        Ordinate::init(2.0)
    };
    auto empty = MappingEmpty{range};

    auto bounds = empty.input_bounds();
    REQUIRE(bounds.start.eql(Ordinate::init(-2.0)));
    REQUIRE(bounds.end.eql(Ordinate::init(2.0)));
}

// Test: output_bounds (same as input_bounds for empty)
TEST_CASE(test_output_bounds) {
    auto range = ContinuousInterval{
        Ordinate::init(-2.0),
        Ordinate::init(2.0)
    };
    auto empty = MappingEmpty{range};

    auto bounds = empty.output_bounds();
    REQUIRE(bounds.start.eql(Ordinate::init(-2.0)));
    REQUIRE(bounds.end.eql(Ordinate::init(2.0)));
}

// Test: clone
TEST_CASE(test_clone) {
    auto range = ContinuousInterval{
        Ordinate::init(5.0),
        Ordinate::init(15.0)
    };
    auto empty1 = MappingEmpty{range};
    auto empty2 = empty1.clone();

    REQUIRE(empty2.defined_range.start.eql(empty1.defined_range.start));
    REQUIRE(empty2.defined_range.end.eql(empty1.defined_range.end));
}

// Test: inverted (returns self for empty)
TEST_CASE(test_inverted) {
    auto range = ContinuousInterval{
        Ordinate::init(1.0),
        Ordinate::init(10.0)
    };
    auto empty = MappingEmpty{range};
    auto inverted = empty.inverted();

    REQUIRE(inverted.defined_range.start.eql(empty.defined_range.start));
    REQUIRE(inverted.defined_range.end.eql(empty.defined_range.end));
}

// Test: shrink_to_input_interval with intersection
TEST_CASE(test_shrink_to_input_interval_intersect) {
    auto empty = MappingEmpty::init(
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}
    );

    auto target = ContinuousInterval{Ordinate::init(5.0), Ordinate::init(15.0)};
    auto result = empty.shrink_to_input_interval(target);

    REQUIRE(result.has_value());
    REQUIRE(result->defined_range.start.eql(Ordinate::init(5.0)));
    REQUIRE(result->defined_range.end.eql(Ordinate::init(10.0)));
}

// Test: shrink_to_input_interval with no intersection
TEST_CASE(test_shrink_to_input_interval_no_intersect) {
    auto empty = MappingEmpty::init(
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}
    );

    auto target = ContinuousInterval{Ordinate::init(20.0), Ordinate::init(30.0)};
    auto result = empty.shrink_to_input_interval(target);

    REQUIRE(!result.has_value());
}

// Test: shrink_to_output_interval (returns self)
TEST_CASE(test_shrink_to_output_interval) {
    auto empty = MappingEmpty::init(
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}
    );

    auto target = ContinuousInterval{Ordinate::init(5.0), Ordinate::init(15.0)};
    auto result = empty.shrink_to_output_interval(target);

    // Should return unchanged
    REQUIRE(result.defined_range.start.eql(Ordinate::init(0.0)));
    REQUIRE(result.defined_range.end.eql(Ordinate::init(10.0)));
}

// Test: split_at_input_point
TEST_CASE(test_split_at_input_point) {
    auto empty = MappingEmpty::init(
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}
    );

    auto split_point = Ordinate::init(5.0);
    auto [left, right] = empty.split_at_input_point(split_point);

    // Left segment
    REQUIRE(left.defined_range.start.eql(Ordinate::init(0.0)));
    REQUIRE(left.defined_range.end.eql(Ordinate::init(5.0)));

    // Right segment
    REQUIRE(right.defined_range.start.eql(Ordinate::init(5.0)));
    REQUIRE(right.defined_range.end.eql(Ordinate::init(10.0)));
}

// Test: split_at_input_point at boundary
TEST_CASE(test_split_at_input_point_boundary) {
    auto empty = MappingEmpty::init(
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}
    );

    // Split at start
    auto [left1, right1] = empty.split_at_input_point(Ordinate::init(0.0));
    REQUIRE(left1.defined_range.start.eql(Ordinate::init(0.0)));
    REQUIRE(left1.defined_range.end.eql(Ordinate::init(0.0)));

    // Split at end
    auto [left2, right2] = empty.split_at_input_point(Ordinate::init(10.0));
    REQUIRE(right2.defined_range.start.eql(Ordinate::init(10.0)));
    REQUIRE(right2.defined_range.end.eql(Ordinate::init(10.0)));
}

// Test: Stream output
TEST_CASE(test_stream_output) {
    auto empty = MappingEmpty::init(
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}
    );

    std::ostringstream oss;
    oss << empty;
    // Just verify it doesn't crash - exact format may vary
    REQUIRE(oss.str().length() > 0);
}

//
// ─── MAIN ────────────────────────────────────────────────────────────────────
//
int main() {
    return tinytest::run_all();
}
