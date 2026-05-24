#include "mapping.hpp"
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
// ─── MAPPING TESTS ───────────────────────────────────────────────────────────
//

// Test: Polymorphic projection with affine mapping
TEST_CASE(test_polymorphic_projection_affine) {
    Mapping mapping = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(5.0), Ordinate::init(2.0)}
    };

    auto result = project_instantaneous_cc(mapping, Ordinate::init(3.0));
    REQUIRE(!result.is_out_of_bounds());
    REQUIRE(result.ordinate().eql(Ordinate::init(11.0))); // 2*3 + 5 = 11
}

// Test: Polymorphic projection with linear mapping
TEST_CASE(test_polymorphic_projection_linear) {
    std::vector<ControlPoint> knots = {
        {Ordinate::init(0.0), Ordinate::init(0.0)},
        {Ordinate::init(10.0), Ordinate::init(20.0)}
    };

    Mapping mapping = MappingCurveLinearMonotonic::init_knots(knots);

    auto result = project_instantaneous_cc(mapping, Ordinate::init(5.0));
    REQUIRE(!result.is_out_of_bounds());
    REQUIRE(result.ordinate().eql(Ordinate::init(10.0)));
}

// Test: Polymorphic projection with empty mapping
TEST_CASE(test_polymorphic_projection_empty) {
    Mapping mapping = MappingEmpty{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}
    };

    auto result = project_instantaneous_cc(mapping, Ordinate::init(5.0));
    REQUIRE(result.is_out_of_bounds());
}

// Test: Polymorphic inverse projection
TEST_CASE(test_polymorphic_inverse_projection) {
    Mapping mapping = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(2.0)}
    };

    auto result = project_instantaneous_cc_inv(mapping, Ordinate::init(10.0));
    REQUIRE(!result.is_out_of_bounds());
    REQUIRE(result.ordinate().eql(Ordinate::init(5.0)));
}

// Test: Polymorphic input_bounds
TEST_CASE(test_polymorphic_input_bounds) {
    Mapping mapping = MappingAffine{
        ContinuousInterval{Ordinate::init(5.0), Ordinate::init(15.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(1.0)}
    };

    auto bounds = input_bounds(mapping);
    REQUIRE(bounds.start.eql(Ordinate::init(5.0)));
    REQUIRE(bounds.end.eql(Ordinate::init(15.0)));
}

// Test: Polymorphic output_bounds
TEST_CASE(test_polymorphic_output_bounds) {
    Mapping mapping = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(10.0), Ordinate::init(3.0)}
    };

    auto bounds = output_bounds(mapping);
    REQUIRE(bounds.start.eql(Ordinate::init(10.0)));
    REQUIRE(bounds.end.eql(Ordinate::init(40.0)));
}

// Test: Polymorphic clone
TEST_CASE(test_polymorphic_clone) {
    Mapping mapping1 = MappingAffine{
        ContinuousInterval{Ordinate::init(1.0), Ordinate::init(5.0)},
        AffineTransform1D{Ordinate::init(2.0), Ordinate::init(3.0)}
    };

    auto mapping2 = clone(mapping1);

    auto result1 = project_instantaneous_cc(mapping1, Ordinate::init(2.0));
    auto result2 = project_instantaneous_cc(mapping2, Ordinate::init(2.0));

    REQUIRE(result1.ordinate().eql(result2.ordinate()));
}

// Test: Polymorphic shrink_to_input_interval
TEST_CASE(test_polymorphic_shrink_to_input_interval) {
    Mapping mapping = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(2.0)}
    };

    auto target = ContinuousInterval{Ordinate::init(5.0), Ordinate::init(15.0)};
    auto result_opt = shrink_to_input_interval(mapping, target);

    REQUIRE(result_opt.has_value());
    auto result_bounds = input_bounds(*result_opt);
    REQUIRE(result_bounds.start.eql(Ordinate::init(5.0)));
    REQUIRE(result_bounds.end.eql(Ordinate::init(10.0)));
}

// Test: Polymorphic split_at_input_point
TEST_CASE(test_polymorphic_split_at_input_point) {
    Mapping mapping = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(5.0), Ordinate::init(2.0)}
    };

    auto [left, right] = split_at_input_point(mapping, Ordinate::init(5.0));

    auto left_bounds = input_bounds(left);
    REQUIRE(left_bounds.start.eql(Ordinate::init(0.0)));
    REQUIRE(left_bounds.end.eql(Ordinate::init(5.0)));

    auto right_bounds = input_bounds(right);
    REQUIRE(right_bounds.start.eql(Ordinate::init(5.0)));
    REQUIRE(right_bounds.end.eql(Ordinate::init(10.0)));
}

// Test: Inverted affine mapping
TEST_CASE(test_inverted_affine) {
    Mapping mapping = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(4.0), Ordinate::init(2.0)}
    };

    auto inv = inverted(mapping);

    // Original: f(5) = 2*5 + 4 = 14
    auto forward = project_instantaneous_cc(mapping, Ordinate::init(5.0));
    REQUIRE(forward.ordinate().eql(Ordinate::init(14.0)));

    // Inverted: f^-1(14) = 5
    auto backward = project_instantaneous_cc(inv, Ordinate::init(14.0));
    REQUIRE(!backward.is_out_of_bounds());
    REQUIRE(backward.ordinate().eql(Ordinate::init(5.0)));
}

// Test: Inverted linear mapping
TEST_CASE(test_inverted_linear) {
    std::vector<ControlPoint> knots = {
        {Ordinate::init(0.0), Ordinate::init(0.0)},
        {Ordinate::init(10.0), Ordinate::init(20.0)}
    };

    Mapping mapping = MappingCurveLinearMonotonic::init_knots(knots);
    auto inv = inverted(mapping);

    // Original: f(5) = 10
    auto forward = project_instantaneous_cc(mapping, Ordinate::init(5.0));
    REQUIRE(forward.ordinate().eql(Ordinate::init(10.0)));

    // Inverted: f^-1(10) = 5
    auto backward = project_instantaneous_cc(inv, Ordinate::init(10.0));
    REQUIRE(!backward.is_out_of_bounds());
    REQUIRE(backward.ordinate().eql(Ordinate::init(5.0)));
}

// Test: join_aff_aff (affine + affine -> affine)
TEST_CASE(test_join_aff_aff) {
    // a->b: f(x) = 2x + 1, domain [0, 10]
    MappingAffine a2b{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(1.0), Ordinate::init(2.0)}
    };

    // b->c: g(x) = 3x + 5, domain [0, 25]
    MappingAffine b2c{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(25.0)},
        AffineTransform1D{Ordinate::init(5.0), Ordinate::init(3.0)}
    };

    auto result = join_aff_aff(a2b, b2c);

    // Composed: g(f(x)) = g(2x + 1) = 3(2x + 1) + 5 = 6x + 3 + 5 = 6x + 8
    // Test: f(2) = 5, g(5) = 20, so composed(2) should = 20
    auto proj = result.project_instantaneous_cc(Ordinate::init(2.0));
    REQUIRE(!proj.is_out_of_bounds());
    REQUIRE(proj.ordinate().eql(Ordinate::init(20.0)));
}

// Test: join with full Mapping variant (affine + affine)
TEST_CASE(test_join_mapping_aff_aff) {
    Mapping a2b = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(1.0), Ordinate::init(2.0)}
    };

    Mapping b2c = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(25.0)},
        AffineTransform1D{Ordinate::init(5.0), Ordinate::init(3.0)}
    };

    auto result = join(a2b, b2c);

    // Should get affine result
    REQUIRE(std::holds_alternative<MappingAffine>(result));

    auto proj = project_instantaneous_cc(result, Ordinate::init(2.0));
    REQUIRE(!proj.is_out_of_bounds());
    REQUIRE(proj.ordinate().eql(Ordinate::init(20.0)));
}

// Test: join affine + linear -> linear
TEST_CASE(test_join_mapping_aff_lin) {
    Mapping a2b = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(2.0)}
    };

    std::vector<ControlPoint> b2c_knots = {
        {Ordinate::init(0.0), Ordinate::init(0.0)},
        {Ordinate::init(20.0), Ordinate::init(40.0)}
    };

    Mapping b2c = MappingCurveLinearMonotonic::init_knots(b2c_knots);

    auto result = join(a2b, b2c);

    // Should get linear result
    REQUIRE(std::holds_alternative<MappingCurveLinearMonotonic>(result));

    // a2b: f(5) = 10, b2c: g(10) = 20, so composed(5) = 20
    auto proj = project_instantaneous_cc(result, Ordinate::init(5.0));
    REQUIRE(!proj.is_out_of_bounds());
    REQUIRE(proj.ordinate().eql(Ordinate::init(20.0)));
}

// Test: join linear + affine -> linear
TEST_CASE(test_join_mapping_lin_aff) {
    std::vector<ControlPoint> a2b_knots = {
        {Ordinate::init(0.0), Ordinate::init(0.0)},
        {Ordinate::init(10.0), Ordinate::init(20.0)}
    };

    Mapping a2b = MappingCurveLinearMonotonic::init_knots(a2b_knots);

    Mapping b2c = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(30.0)},
        AffineTransform1D{Ordinate::init(5.0), Ordinate::init(2.0)}
    };

    auto result = join(a2b, b2c);

    // Should get linear result
    REQUIRE(std::holds_alternative<MappingCurveLinearMonotonic>(result));

    // a2b: f(5) = 10, b2c: g(10) = 2*10 + 5 = 25, so composed(5) = 25
    auto proj = project_instantaneous_cc(result, Ordinate::init(5.0));
    REQUIRE(!proj.is_out_of_bounds());
    REQUIRE(proj.ordinate().eql(Ordinate::init(25.0)));
}

// Test: join linear + linear -> linear
TEST_CASE(test_join_mapping_lin_lin) {
    std::vector<ControlPoint> a2b_knots = {
        {Ordinate::init(0.0), Ordinate::init(0.0)},
        {Ordinate::init(10.0), Ordinate::init(10.0)}
    };

    std::vector<ControlPoint> b2c_knots = {
        {Ordinate::init(0.0), Ordinate::init(0.0)},
        {Ordinate::init(10.0), Ordinate::init(20.0)}
    };

    Mapping a2b = MappingCurveLinearMonotonic::init_knots(a2b_knots);
    Mapping b2c = MappingCurveLinearMonotonic::init_knots(b2c_knots);

    auto result = join(a2b, b2c);

    // Should get linear result
    REQUIRE(std::holds_alternative<MappingCurveLinearMonotonic>(result));

    // a2b: identity, b2c: 2x, so composed(5) = 10
    auto proj = project_instantaneous_cc(result, Ordinate::init(5.0));
    REQUIRE(!proj.is_out_of_bounds());
    REQUIRE(proj.ordinate().eql(Ordinate::init(10.0)));
}

// Test: join with empty mapping returns empty
TEST_CASE(test_join_with_empty) {
    Mapping a2b = MappingEmpty{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}
    };

    Mapping b2c = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(1.0)}
    };

    auto result = join(a2b, b2c);

    // Should get empty result
    REQUIRE(std::holds_alternative<MappingEmpty>(result));
}

// Test: join with no boundary overlap returns empty
TEST_CASE(test_join_no_overlap) {
    // a2b maps [0, 10] -> [0, 10]
    Mapping a2b = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(1.0)}
    };

    // b2c maps [20, 30] -> [20, 30] (no overlap with a2b output)
    Mapping b2c = MappingAffine{
        ContinuousInterval{Ordinate::init(20.0), Ordinate::init(30.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(1.0)}
    };

    auto result = join(a2b, b2c);

    // Should get empty result (no intersection in "b" space)
    REQUIRE(std::holds_alternative<MappingEmpty>(result));
}

// Test: join with identity mapping
TEST_CASE(test_join_with_identity) {
    Mapping identity = INFINITE_IDENTITY;

    Mapping mapping = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(3.0), Ordinate::init(2.0)}
    };

    auto result = join(identity, mapping);

    // Joining identity with mapping should give same result
    auto orig_proj = project_instantaneous_cc(mapping, Ordinate::init(5.0));
    auto result_proj = project_instantaneous_cc(result, Ordinate::init(5.0));

    REQUIRE(orig_proj.ordinate().eql(result_proj.ordinate()));
}

// Test: Stream output
TEST_CASE(test_stream_output) {
    Mapping mapping = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(5.0), Ordinate::init(2.0)}
    };

    std::ostringstream oss;
    oss << mapping;

    REQUIRE(oss.str().length() > 0);
}

//
// ─── MAIN ────────────────────────────────────────────────────────────────────
//
int main() {
    return tinytest::run_all();
}
