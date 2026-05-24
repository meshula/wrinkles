#include "linear_curve.hpp"
#include <iostream>
#include <cmath>
#include <string_view>

//
// ─── MINIMAL TEST HARNESS (Catch2 style) ─────────────────────────────────────
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

    template<typename A, typename B>
    inline void require_approx(A const& a, B const& b, double eps, std::string_view expr, std::string_view file, int line) {
        double ad = static_cast<double>(a);
        double bd = static_cast<double>(b);
        if (!(std::fabs(ad - bd) <= eps)) {
            throw failure(std::string(file) + ":" + std::to_string(line)
                + ": REQUIRE_APPROX failed: " + std::string(expr)
                + " (|a-b|=" + std::to_string(std::fabs(ad - bd)) + " > eps=" + std::to_string(eps) + ")");
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
#define REQUIRE_APPROX(a,b,eps) ::tinytest::require_approx((a),(b),(eps), #a " ≈ " #b, __FILE__, __LINE__)

//
// ─── LINEAR CURVE TESTS ──────────────────────────────────────────────────────
//

// Test: Basic construction
TEST_CASE(test_construction) {
    std::vector<ControlPoint> knots = {
        ControlPoint::init(ControlPoint_BaseType{0.0, 0.0}),
        ControlPoint::init(ControlPoint_BaseType{10.0, 20.0})
    };

    auto linear = Linear::Monotonic{knots};
    REQUIRE(linear.knots.size() == 2);
}

// Test: Extents input
TEST_CASE(test_extents_input) {
    std::vector<ControlPoint> knots = {
        ControlPoint::init(ControlPoint_BaseType{0.0, 0.0}),
        ControlPoint::init(ControlPoint_BaseType{10.0, 20.0})
    };

    auto linear = Linear::Monotonic{knots};
    auto ext = linear.extents_input();

    REQUIRE(ext.start.eql_approx(Ordinate::init(0.0)));
    REQUIRE(ext.end.eql_approx(Ordinate::init(10.0)));
}

// Test: Extents output
TEST_CASE(test_extents_output) {
    std::vector<ControlPoint> knots = {
        ControlPoint::init(ControlPoint_BaseType{0.0, 0.0}),
        ControlPoint::init(ControlPoint_BaseType{10.0, 20.0})
    };

    auto linear = Linear::Monotonic{knots};
    auto ext = linear.extents_output();

    REQUIRE(ext.start.eql_approx(Ordinate::init(0.0)));
    REQUIRE(ext.end.eql_approx(Ordinate::init(20.0)));
}

// Test: Extents (both input and output)
TEST_CASE(test_extents) {
    std::vector<ControlPoint> knots = {
        ControlPoint::init(ControlPoint_BaseType{0.0, 5.0}),
        ControlPoint::init(ControlPoint_BaseType{10.0, 15.0})
    };

    auto linear = Linear::Monotonic{knots};
    auto ext = linear.extents();

    REQUIRE(ext[0].in.eql_approx(Ordinate::init(0.0)));
    REQUIRE(ext[0].out.eql_approx(Ordinate::init(5.0)));
    REQUIRE(ext[1].in.eql_approx(Ordinate::init(10.0)));
    REQUIRE(ext[1].out.eql_approx(Ordinate::init(15.0)));
}

// Test: Slope kind - rising
TEST_CASE(test_slope_kind_rising) {
    std::vector<ControlPoint> knots = {
        ControlPoint::init(ControlPoint_BaseType{0.0, 0.0}),
        ControlPoint::init(ControlPoint_BaseType{10.0, 20.0})
    };

    auto linear = Linear::Monotonic{knots};
    auto slope = linear.slope_kind();

    REQUIRE(slope == SlopeKind::rising);
}

// Test: Slope kind - falling
TEST_CASE(test_slope_kind_falling) {
    std::vector<ControlPoint> knots = {
        ControlPoint::init(ControlPoint_BaseType{0.0, 20.0}),
        ControlPoint::init(ControlPoint_BaseType{10.0, 0.0})
    };

    auto linear = Linear::Monotonic{knots};
    auto slope = linear.slope_kind();

    REQUIRE(slope == SlopeKind::falling);
}

// Test: Slope kind - flat
TEST_CASE(test_slope_kind_flat) {
    std::vector<ControlPoint> knots = {
        ControlPoint::init(ControlPoint_BaseType{0.0, 10.0}),
        ControlPoint::init(ControlPoint_BaseType{10.0, 10.0})
    };

    auto linear = Linear::Monotonic{knots};
    auto slope = linear.slope_kind();

    REQUIRE(slope == SlopeKind::flat);
}

// Test: nearest_smaller_knot_index_input
TEST_CASE(test_nearest_smaller_knot_index_input) {
    std::vector<ControlPoint> knots = {
        ControlPoint::init(ControlPoint_BaseType{0.0, 0.0}),
        ControlPoint::init(ControlPoint_BaseType{5.0, 10.0}),
        ControlPoint::init(ControlPoint_BaseType{10.0, 20.0})
    };

    auto linear = Linear::Monotonic{knots};

    auto index = linear.nearest_smaller_knot_index_input(Ordinate::init(3.0));
    REQUIRE(index.has_value());
    REQUIRE(*index == 0);

    index = linear.nearest_smaller_knot_index_input(Ordinate::init(7.0));
    REQUIRE(index.has_value());
    REQUIRE(*index == 1);

    // Out of bounds
    index = linear.nearest_smaller_knot_index_input(Ordinate::init(-1.0));
    REQUIRE(!index.has_value());

    index = linear.nearest_smaller_knot_index_input(Ordinate::init(10.0));
    REQUIRE(!index.has_value());
}

// Test: output_at_input - simple linear interpolation
TEST_CASE(test_output_at_input_simple) {
    std::vector<ControlPoint> knots = {
        ControlPoint::init(ControlPoint_BaseType{0.0, 0.0}),
        ControlPoint::init(ControlPoint_BaseType{10.0, 20.0})
    };

    auto linear = Linear::Monotonic{knots};

    // Midpoint should give 10.0
    auto result = linear.output_at_input(Ordinate::init(5.0));
    REQUIRE(result.is_ordinate());
    REQUIRE(result.ordinate().eql_approx(Ordinate::init(10.0)));
}

// Test: output_at_input - multiple segments
TEST_CASE(test_output_at_input_multi_segment) {
    std::vector<ControlPoint> knots = {
        ControlPoint::init(ControlPoint_BaseType{0.0, 0.0}),
        ControlPoint::init(ControlPoint_BaseType{5.0, 10.0}),
        ControlPoint::init(ControlPoint_BaseType{10.0, 20.0})
    };

    auto linear = Linear::Monotonic{knots};

    // At 2.5, should be halfway between 0 and 10 = 5.0
    auto result = linear.output_at_input(Ordinate::init(2.5));
    REQUIRE(result.is_ordinate());
    REQUIRE(result.ordinate().eql_approx(Ordinate::init(5.0)));

    // At 7.5, should be halfway between 10 and 20 = 15.0
    result = linear.output_at_input(Ordinate::init(7.5));
    REQUIRE(result.is_ordinate());
    REQUIRE(result.ordinate().eql_approx(Ordinate::init(15.0)));
}

// Test: output_at_input - endpoint
TEST_CASE(test_output_at_input_endpoint) {
    std::vector<ControlPoint> knots = {
        ControlPoint::init(ControlPoint_BaseType{0.0, 0.0}),
        ControlPoint::init(ControlPoint_BaseType{10.0, 20.0})
    };

    auto linear = Linear::Monotonic{knots};

    // At start point
    auto result = linear.output_at_input(Ordinate::init(0.0));
    REQUIRE(result.is_ordinate());
    REQUIRE(result.ordinate().eql_approx(Ordinate::init(0.0)));

    // At end point
    result = linear.output_at_input(Ordinate::init(10.0));
    REQUIRE(result.is_ordinate());
    REQUIRE(result.ordinate().eql_approx(Ordinate::init(20.0)));
}

// Test: output_at_input - out of bounds
TEST_CASE(test_output_at_input_out_of_bounds) {
    std::vector<ControlPoint> knots = {
        ControlPoint::init(ControlPoint_BaseType{0.0, 0.0}),
        ControlPoint::init(ControlPoint_BaseType{10.0, 20.0})
    };

    auto linear = Linear::Monotonic{knots};

    // Before start
    auto result = linear.output_at_input(Ordinate::init(-1.0));
    REQUIRE(result.is_out_of_bounds());

    // After end
    result = linear.output_at_input(Ordinate::init(11.0));
    REQUIRE(result.is_out_of_bounds());
}

//
// ─── MAIN ───────────────────────────────────────────────────────────────────
//
int main() {
    return tinytest::run_all();
}
