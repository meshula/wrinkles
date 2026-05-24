#include "mapping_curve_linear.hpp"
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
// ─── MAPPING CURVE LINEAR TESTS ──────────────────────────────────────────────
//

// Test: init_knots with identity mapping
TEST_CASE(test_init_knots_identity) {
    std::vector<ControlPoint> knots = {
        {Ordinate::init(0.0), Ordinate::init(0.0)},
        {Ordinate::init(10.0), Ordinate::init(10.0)}
    };

    auto mcl = MappingCurveLinearMonotonic::init_knots(knots);

    // Test identity projection
    auto result = mcl.project_instantaneous_cc(Ordinate::init(2.0));
    REQUIRE(!result.is_out_of_bounds());
    REQUIRE(result.ordinate().eql(Ordinate::init(2.0)));
}

// Test: Projection through piecewise linear curve
TEST_CASE(test_projection_piecewise) {
    std::vector<ControlPoint> knots = {
        {Ordinate::init(0.0), Ordinate::init(0.0)},
        {Ordinate::init(10.0), Ordinate::init(10.0)},
        {Ordinate::init(20.0), Ordinate::init(30.0)},
        {Ordinate::init(30.0), Ordinate::init(30.0)},
        {Ordinate::init(40.0), Ordinate::init(0.0)},
        {Ordinate::init(50.0), Ordinate::init(-10.0)}
    };

    auto mcl = MappingCurveLinearMonotonic::init_knots(knots);

    // Test various points
    struct TestCase {
        double input;
        double expected_output;
        bool should_fail;
    };

    std::vector<TestCase> tests = {
        {-1.0, 0.0, true},   // Out of bounds
        {0.0, 0.0, false},   // At start
        {5.0, 5.0, false},   // First segment (slope 1)
        {15.0, 20.0, false}, // Second segment (slope 2)
        {25.0, 30.0, false}, // Third segment (flat)
        {26.0, 30.0, false}, // Still flat
        {45.0, -5.0, false}, // Fifth segment (negative slope)
    };

    for (auto const& test : tests) {
        auto result = mcl.project_instantaneous_cc(Ordinate::init(test.input));

        if (test.should_fail) {
            REQUIRE(result.is_out_of_bounds());
        } else {
            REQUIRE(!result.is_out_of_bounds());
            REQUIRE(result.ordinate().eql_approx(Ordinate::init(test.expected_output)));
        }
    }
}

// Test: Inverse projection
TEST_CASE(test_inverse_projection) {
    std::vector<ControlPoint> knots = {
        {Ordinate::init(0.0), Ordinate::init(0.0)},
        {Ordinate::init(10.0), Ordinate::init(20.0)}
    };

    auto mcl = MappingCurveLinearMonotonic::init_knots(knots);

    // Forward: input=5 -> output=10
    auto forward = mcl.project_instantaneous_cc(Ordinate::init(5.0));
    REQUIRE(!forward.is_out_of_bounds());
    REQUIRE(forward.ordinate().eql(Ordinate::init(10.0)));

    // Inverse: output=10 -> input=5
    auto inverse = mcl.project_instantaneous_cc_inv(Ordinate::init(10.0));
    REQUIRE(!inverse.is_out_of_bounds());
    REQUIRE(inverse.ordinate().eql(Ordinate::init(5.0)));
}

// Test: input_bounds
TEST_CASE(test_input_bounds) {
    std::vector<ControlPoint> knots = {
        {Ordinate::init(5.0), Ordinate::init(10.0)},
        {Ordinate::init(15.0), Ordinate::init(30.0)}
    };

    auto mcl = MappingCurveLinearMonotonic::init_knots(knots);
    auto bounds = mcl.input_bounds();

    REQUIRE(bounds.start.eql(Ordinate::init(5.0)));
    REQUIRE(bounds.end.eql(Ordinate::init(15.0)));
}

// Test: output_bounds
TEST_CASE(test_output_bounds) {
    std::vector<ControlPoint> knots = {
        {Ordinate::init(0.0), Ordinate::init(5.0)},
        {Ordinate::init(10.0), Ordinate::init(25.0)}
    };

    auto mcl = MappingCurveLinearMonotonic::init_knots(knots);
    auto bounds = mcl.output_bounds();

    REQUIRE(bounds.start.eql(Ordinate::init(5.0)));
    REQUIRE(bounds.end.eql(Ordinate::init(25.0)));
}

// Test: clone
TEST_CASE(test_clone) {
    std::vector<ControlPoint> knots = {
        {Ordinate::init(0.0), Ordinate::init(0.0)},
        {Ordinate::init(10.0), Ordinate::init(10.0)}
    };

    auto mcl1 = MappingCurveLinearMonotonic::init_knots(knots);
    auto mcl2 = mcl1.clone();

    // Verify they produce same results
    auto result1 = mcl1.project_instantaneous_cc(Ordinate::init(5.0));
    auto result2 = mcl2.project_instantaneous_cc(Ordinate::init(5.0));

    REQUIRE(!result1.is_out_of_bounds());
    REQUIRE(!result2.is_out_of_bounds());
    REQUIRE(result1.ordinate().eql(result2.ordinate()));
}

// Test: shrink_to_input_interval
TEST_CASE(test_shrink_to_input_interval) {
    std::vector<ControlPoint> knots = {
        {Ordinate::init(0.0), Ordinate::init(0.0)},
        {Ordinate::init(10.0), Ordinate::init(10.0)},
        {Ordinate::init(20.0), Ordinate::init(20.0)}
    };

    auto mcl = MappingCurveLinearMonotonic::init_knots(knots);

    // Shrink to [5, 15]
    auto target = ContinuousInterval{Ordinate::init(5.0), Ordinate::init(15.0)};
    auto result = mcl.shrink_to_input_interval(target);

    auto result_bounds = result.input_bounds();
    REQUIRE(result_bounds.start.eql(Ordinate::init(5.0)));
    REQUIRE(result_bounds.end.eql(Ordinate::init(15.0)));

    // Verify projection still works
    auto proj = result.project_instantaneous_cc(Ordinate::init(10.0));
    REQUIRE(!proj.is_out_of_bounds());
    REQUIRE(proj.ordinate().eql(Ordinate::init(10.0)));
}

// Test: shrink_to_output_interval
TEST_CASE(test_shrink_to_output_interval) {
    std::vector<ControlPoint> knots = {
        {Ordinate::init(0.0), Ordinate::init(0.0)},
        {Ordinate::init(10.0), Ordinate::init(10.0)},
        {Ordinate::init(20.0), Ordinate::init(30.0)}
    };

    auto mcl = MappingCurveLinearMonotonic::init_knots(knots);

    // Shrink to output [5, 25]
    auto target = ContinuousInterval{Ordinate::init(5.0), Ordinate::init(25.0)};
    auto result = mcl.shrink_to_output_interval(target);

    auto result_output_bounds = result.output_bounds();
    REQUIRE(result_output_bounds.start.eql_approx(Ordinate::init(5.0)));
    REQUIRE(result_output_bounds.end.eql_approx(Ordinate::init(25.0)));
}

// Test: split_at_input_point on knot
TEST_CASE(test_split_at_knot) {
    std::vector<ControlPoint> knots = {
        {Ordinate::init(0.0), Ordinate::init(0.0)},
        {Ordinate::init(10.0), Ordinate::init(10.0)},
        {Ordinate::init(20.0), Ordinate::init(20.0)}
    };

    auto mcl = MappingCurveLinearMonotonic::init_knots(knots);

    auto [left, right] = mcl.split_at_input_point(Ordinate::init(10.0));

    // Check left segment
    auto left_bounds = left.input_bounds();
    REQUIRE(left_bounds.start.eql(Ordinate::init(0.0)));
    REQUIRE(left_bounds.end.eql(Ordinate::init(10.0)));

    // Check right segment
    auto right_bounds = right.input_bounds();
    REQUIRE(right_bounds.start.eql(Ordinate::init(10.0)));
    REQUIRE(right_bounds.end.eql(Ordinate::init(20.0)));
}

// Test: split_at_input_point between knots
TEST_CASE(test_split_between_knots) {
    std::vector<ControlPoint> knots = {
        {Ordinate::init(0.0), Ordinate::init(0.0)},
        {Ordinate::init(20.0), Ordinate::init(20.0)}
    };

    auto mcl = MappingCurveLinearMonotonic::init_knots(knots);

    auto [left, right] = mcl.split_at_input_point(Ordinate::init(10.0));

    // Check left segment
    auto left_result = left.project_instantaneous_cc(Ordinate::init(10.0));
    REQUIRE(!left_result.is_out_of_bounds());
    REQUIRE(left_result.ordinate().eql(Ordinate::init(10.0)));

    // Check right segment
    auto right_result = right.project_instantaneous_cc(Ordinate::init(10.0));
    REQUIRE(!right_result.is_out_of_bounds());
    REQUIRE(right_result.ordinate().eql(Ordinate::init(10.0)));
}

// Test: Stream output
TEST_CASE(test_stream_output) {
    std::vector<ControlPoint> knots = {
        {Ordinate::init(0.0), Ordinate::init(0.0)},
        {Ordinate::init(10.0), Ordinate::init(10.0)}
    };

    auto mcl = MappingCurveLinearMonotonic::init_knots(knots);

    std::ostringstream oss;
    oss << mcl;

    REQUIRE(oss.str().length() > 0);
}

//
// ─── MAIN ────────────────────────────────────────────────────────────────────
//
int main() {
    return tinytest::run_all();
}
