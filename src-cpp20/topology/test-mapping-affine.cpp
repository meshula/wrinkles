#include "mapping_affine.hpp"
#include <iostream>
#include <sstream>
#include <string_view>
#include <cmath>

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
// ─── MAPPING AFFINE TESTS ────────────────────────────────────────────────────
//

// Test: Default construction (identity)
TEST_CASE(test_default_construction) {
    auto affine = MappingAffine{};

    // Should have infinite bounds
    REQUIRE(affine.input_bounds_val.is_infinite());

    // Should be identity transform
    REQUIRE(affine.input_to_output_xform.offset.eql(Ordinate::init(0.0)));
    REQUIRE(affine.input_to_output_xform.scale.eql(Ordinate::init(1.0)));
}

// Test: INFINITE_IDENTITY constant
TEST_CASE(test_infinite_identity) {
    // Test identity projection
    auto result = INFINITE_IDENTITY.project_instantaneous_cc(Ordinate::init(12.0));
    REQUIRE(!result.is_out_of_bounds());
    REQUIRE(result.ordinate().eql(Ordinate::init(12.0)));

    // Test another value
    result = INFINITE_IDENTITY.project_instantaneous_cc(Ordinate::init(-5.5));
    REQUIRE(!result.is_out_of_bounds());
    REQUIRE(result.ordinate().eql(Ordinate::init(-5.5)));
}

// Test: Non-identity affine transformation
TEST_CASE(test_non_identity) {
    // Create mapping: f(x) = 4*x + 2, for x in [3, 6]
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(3.0), Ordinate::init(6.0)},
        AffineTransform1D{Ordinate::init(2.0), Ordinate::init(4.0)}
    };

    // Test projection at start of range: f(3) = 4*3 + 2 = 14
    auto result = affine.project_instantaneous_cc(Ordinate::init(3.0));
    REQUIRE(!result.is_out_of_bounds());
    REQUIRE(result.ordinate().eql(Ordinate::init(14.0)));

    // Test projection at mid-range: f(4.5) = 4*4.5 + 2 = 20
    result = affine.project_instantaneous_cc(Ordinate::init(4.5));
    REQUIRE(!result.is_out_of_bounds());
    REQUIRE(result.ordinate().eql(Ordinate::init(20.0)));

    // Test projection at end of range: f(6) = 4*6 + 2 = 26
    result = affine.project_instantaneous_cc(Ordinate::init(6.0));
    REQUIRE(!result.is_out_of_bounds());
    REQUIRE(result.ordinate().eql(Ordinate::init(26.0)));
}

// Test: Projection out of bounds
TEST_CASE(test_projection_out_of_bounds) {
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(5.0), Ordinate::init(2.0)}
    };

    // Before range
    auto result = affine.project_instantaneous_cc(Ordinate::init(-1.0));
    REQUIRE(result.is_out_of_bounds());

    // After range (but not at end point)
    result = affine.project_instantaneous_cc(Ordinate::init(10.1));
    REQUIRE(result.is_out_of_bounds());
}

// Test: Inverse projection
TEST_CASE(test_inverse_projection) {
    // Create mapping: f(x) = 2*x + 4, for x in [0, 10]
    // So output range is [4, 24]
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(4.0), Ordinate::init(2.0)}
    };

    // Inverse at start: f^-1(4) = (4 - 4) / 2 = 0
    auto result = affine.project_instantaneous_cc_inv(Ordinate::init(4.0));
    REQUIRE(!result.is_out_of_bounds());
    REQUIRE(result.ordinate().eql(Ordinate::init(0.0)));

    // Inverse at mid: f^-1(14) = (14 - 4) / 2 = 5
    result = affine.project_instantaneous_cc_inv(Ordinate::init(14.0));
    REQUIRE(!result.is_out_of_bounds());
    REQUIRE(result.ordinate().eql(Ordinate::init(5.0)));

    // Inverse at end: f^-1(24) = (24 - 4) / 2 = 10
    result = affine.project_instantaneous_cc_inv(Ordinate::init(24.0));
    REQUIRE(!result.is_out_of_bounds());
    REQUIRE(result.ordinate().eql(Ordinate::init(10.0)));
}

// Test: Inverse projection out of bounds
TEST_CASE(test_inverse_projection_out_of_bounds) {
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(4.0), Ordinate::init(2.0)}
    };
    // Output range is [4, 24]

    // Before output range
    auto result = affine.project_instantaneous_cc_inv(Ordinate::init(3.0));
    REQUIRE(result.is_out_of_bounds());

    // After output range
    result = affine.project_instantaneous_cc_inv(Ordinate::init(25.0));
    REQUIRE(result.is_out_of_bounds());
}

// Test: input_bounds
TEST_CASE(test_input_bounds) {
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(5.0), Ordinate::init(15.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(1.0)}
    };

    auto bounds = affine.input_bounds();
    REQUIRE(bounds.start.eql(Ordinate::init(5.0)));
    REQUIRE(bounds.end.eql(Ordinate::init(15.0)));
}

// Test: output_bounds
TEST_CASE(test_output_bounds) {
    // f(x) = 3*x + 10, for x in [0, 10]
    // Output: [10, 40]
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(10.0), Ordinate::init(3.0)}
    };

    auto bounds = affine.output_bounds();
    REQUIRE(bounds.start.eql(Ordinate::init(10.0)));
    REQUIRE(bounds.end.eql(Ordinate::init(40.0)));
}

// Test: clone
TEST_CASE(test_clone) {
    auto affine1 = MappingAffine{
        ContinuousInterval{Ordinate::init(1.0), Ordinate::init(5.0)},
        AffineTransform1D{Ordinate::init(2.0), Ordinate::init(3.0)}
    };

    auto affine2 = affine1.clone();

    REQUIRE(affine2.input_bounds_val.start.eql(affine1.input_bounds_val.start));
    REQUIRE(affine2.input_bounds_val.end.eql(affine1.input_bounds_val.end));
    REQUIRE(affine2.input_to_output_xform.offset.eql(affine1.input_to_output_xform.offset));
    REQUIRE(affine2.input_to_output_xform.scale.eql(affine1.input_to_output_xform.scale));
}

// Test: shrink_to_input_interval with intersection
TEST_CASE(test_shrink_to_input_interval) {
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(2.0)}
    };

    auto target = ContinuousInterval{Ordinate::init(5.0), Ordinate::init(15.0)};
    auto result = affine.shrink_to_input_interval(target);

    REQUIRE(result.has_value());
    REQUIRE(result->input_bounds_val.start.eql(Ordinate::init(5.0)));
    REQUIRE(result->input_bounds_val.end.eql(Ordinate::init(10.0)));

    // Transform should be unchanged
    REQUIRE(result->input_to_output_xform.scale.eql(Ordinate::init(2.0)));
}

// Test: shrink_to_input_interval with no intersection
TEST_CASE(test_shrink_to_input_interval_no_overlap) {
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(1.0)}
    };

    auto target = ContinuousInterval{Ordinate::init(20.0), Ordinate::init(30.0)};
    auto result = affine.shrink_to_input_interval(target);

    REQUIRE(!result.has_value());
}

// Test: shrink_to_output_interval
TEST_CASE(test_shrink_to_output_interval) {
    // f(x) = 2*x, for x in [0, 10]
    // Output range: [0, 20]
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(2.0)}
    };

    // Shrink to output [4, 12] -> should map back to input [2, 6]
    auto target = ContinuousInterval{Ordinate::init(4.0), Ordinate::init(12.0)};
    auto result = affine.shrink_to_output_interval(target);

    REQUIRE(result.input_bounds_val.start.eql(Ordinate::init(2.0)));
    REQUIRE(result.input_bounds_val.end.eql(Ordinate::init(6.0)));
}

// Test: shrink_to_output_interval with no overlap
TEST_CASE(test_shrink_to_output_interval_no_overlap) {
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(2.0)}
    };
    // Output range: [0, 20]

    // Target outside output range
    auto target = ContinuousInterval{Ordinate::init(30.0), Ordinate::init(40.0)};
    auto result = affine.shrink_to_output_interval(target);

    // Should return zero interval
    REQUIRE(result.input_bounds_val.start.eql(Ordinate::init(0.0)));
    REQUIRE(result.input_bounds_val.end.eql(Ordinate::init(0.0)));
}

// Test: split_at_input_point
TEST_CASE(test_split_at_input_point) {
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(5.0), Ordinate::init(2.0)}
    };

    auto [left, right] = affine.split_at_input_point(Ordinate::init(5.0));

    // Left segment: [0, 5]
    REQUIRE(left.input_bounds_val.start.eql(Ordinate::init(0.0)));
    REQUIRE(left.input_bounds_val.end.eql(Ordinate::init(5.0)));
    REQUIRE(left.input_to_output_xform.scale.eql(Ordinate::init(2.0)));

    // Right segment: [5, 10]
    REQUIRE(right.input_bounds_val.start.eql(Ordinate::init(5.0)));
    REQUIRE(right.input_bounds_val.end.eql(Ordinate::init(10.0)));
    REQUIRE(right.input_to_output_xform.scale.eql(Ordinate::init(2.0)));
}

// Test: split_at_input_points with no valid points
TEST_CASE(test_split_at_input_points_no_valid) {
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(10.0), Ordinate::init(20.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(1.0)}
    };

    // Points outside bounds
    std::vector<Ordinate> points = {
        Ordinate::init(5.0),
        Ordinate::init(25.0)
    };

    auto result = affine.split_at_input_points(points);

    // Should return single mapping unchanged
    REQUIRE(result.size() == 1);
    REQUIRE(result[0].input_bounds_val.start.eql(Ordinate::init(10.0)));
    REQUIRE(result[0].input_bounds_val.end.eql(Ordinate::init(20.0)));
}

// Test: split_at_input_points with valid points
TEST_CASE(test_split_at_input_points_valid) {
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(1.0)}
    };

    std::vector<Ordinate> points = {
        Ordinate::init(3.0),
        Ordinate::init(7.0)
    };

    auto result = affine.split_at_input_points(points);

    // Should have 3 segments: [0,3], [3,7], [7,10]
    REQUIRE(result.size() == 3);

    REQUIRE(result[0].input_bounds_val.start.eql(Ordinate::init(0.0)));
    REQUIRE(result[0].input_bounds_val.end.eql(Ordinate::init(3.0)));

    REQUIRE(result[1].input_bounds_val.start.eql(Ordinate::init(3.0)));
    REQUIRE(result[1].input_bounds_val.end.eql(Ordinate::init(7.0)));

    REQUIRE(result[2].input_bounds_val.start.eql(Ordinate::init(7.0)));
    REQUIRE(result[2].input_bounds_val.end.eql(Ordinate::init(10.0)));
}

// Test: Stream output
TEST_CASE(test_stream_output) {
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(5.0), Ordinate::init(2.0)}
    };

    std::ostringstream oss;
    oss << affine;

    // Just verify it doesn't crash
    REQUIRE(oss.str().length() > 0);
}

//
// ─── MAIN ────────────────────────────────────────────────────────────────────
//
int main() {
    return tinytest::run_all();
}
