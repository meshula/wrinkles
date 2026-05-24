#include "control_point.hpp"
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
// ─── CONTROL POINT TESTS ─────────────────────────────────────────────────────
//

// Test: ControlPoint addition
TEST_CASE(test_add) {
    auto cp1 = ControlPoint::init(ControlPoint_BaseType{0, 10});
    auto cp2 = ControlPoint::init(ControlPoint_BaseType{20, -10});
    auto expected = ControlPoint::init(ControlPoint_BaseType{20, 0});

    auto result = cp1.add(cp2);

    expectControlPointEqual(result, expected);
}

// Test: ControlPoint subtraction
TEST_CASE(test_sub) {
    auto cp1 = ControlPoint::init(ControlPoint_BaseType{0, 10});
    auto cp2 = ControlPoint::init(ControlPoint_BaseType{20, -10});
    auto expected = ControlPoint::init(ControlPoint_BaseType{-20, 20});

    auto result = cp1.sub(cp2);

    expectControlPointEqual(result, expected);
}

// Test: ControlPoint multiplication
TEST_CASE(test_mul) {
    auto cp1 = ControlPoint::init(ControlPoint_BaseType{0.0, 10.0});
    auto scale = -10.0;
    auto expected = ControlPoint::init(ControlPoint_BaseType{0.0, -100.0});

    auto mul_direct = cp1.mul_num(scale);
    auto mul_implicit = cp1.mul(scale);

    expectControlPointEqual(mul_direct, mul_implicit);
    expectControlPointEqual(expected, mul_implicit);
}

// Test: Distance calculation (3-4-5 triangle)
TEST_CASE(test_distance_345_triangle) {
    auto a = ControlPoint::init(ControlPoint_BaseType{3, -3});
    auto b = ControlPoint::init(ControlPoint_BaseType{6, 1});

    auto dist = a.distance(b);
    auto expected = Ordinate::init(5.0);

    REQUIRE(dist.eql_approx(expected));
}

// Test: ControlPoint with base type (double)
TEST_CASE(test_control_point_base_type) {
    auto cp1 = ControlPoint_BaseType{1.0, 2.0};
    auto cp2 = ControlPoint_BaseType{3.0, 4.0};

    auto result = cp1.add(cp2);
    auto expected = ControlPoint_BaseType{4.0, 6.0};

    expectControlPointEqual(result, expected);
}

// Test: Normalized vector
TEST_CASE(test_normalized) {
    auto cp = ControlPoint_BaseType{3.0, 4.0};
    auto normalized = cp.normalized();

    // Length should be 1.0
    auto length = normalized.distance(ControlPoint_BaseType{0.0, 0.0});
    REQUIRE(std::abs(length - 1.0) < 0.00001);

    // Direction should be preserved (3,4) -> (0.6, 0.8)
    REQUIRE(std::abs(normalized.in - 0.6) < 0.00001);
    REQUIRE(std::abs(normalized.out - 0.8) < 0.00001);
}

// Test: ControlPoint division
TEST_CASE(test_div) {
    auto cp1 = ControlPoint_BaseType{10.0, 20.0};
    auto scale = 2.0;
    auto expected = ControlPoint_BaseType{5.0, 10.0};

    auto result = cp1.div(scale);

    expectControlPointEqual(result, expected);
}

// Test: ControlPoint-to-ControlPoint multiplication
TEST_CASE(test_mul_cp) {
    auto cp1 = ControlPoint_BaseType{2.0, 3.0};
    auto cp2 = ControlPoint_BaseType{4.0, 5.0};
    auto expected = ControlPoint_BaseType{8.0, 15.0};

    auto result = cp1.mul_cp(cp2);

    expectControlPointEqual(result, expected);
}

// Test: ZERO and ONE constants
TEST_CASE(test_constants) {
    auto zero = ControlPoint::ZERO();
    auto one = ControlPoint::ONE();

    REQUIRE(zero.in.eql(Ordinate::ZERO()));
    REQUIRE(zero.out.eql(Ordinate::ZERO()));
    REQUIRE(one.in.eql(Ordinate::ONE()));
    REQUIRE(one.out.eql(Ordinate::ONE()));
}

//
// ─── MAIN ───────────────────────────────────────────────────────────────────
//
int main() {
    return tinytest::run_all();
}
