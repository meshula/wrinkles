#include "bezier_math.hpp"
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
// ─── BEZIER MATH TESTS ───────────────────────────────────────────────────────
//

// Test: lerp with primitive types
TEST_CASE(test_lerp_primitive) {
    double a = 0.0;
    double b = 10.0;
    double u = 0.5;

    double result = lerp(u, a, b);
    REQUIRE_APPROX(result, 5.0, 0.00001);
}

// Test: lerp with Ordinate
TEST_CASE(test_lerp_ordinate) {
    auto a = Ordinate::init(0.0);
    auto b = Ordinate::init(10.0);
    auto u = Ordinate::init(0.5);

    auto result = lerp(u, a, b);
    REQUIRE(result.eql_approx(Ordinate::init(5.0)));
}

// Test: lerp with ControlPoint
TEST_CASE(test_lerp_control_point) {
    auto a = ControlPoint_BaseType{0.0, 0.0};
    auto b = ControlPoint_BaseType{10.0, 20.0};
    double u = 0.5;

    auto result = lerp(u, a, b);
    REQUIRE_APPROX(result.in, 5.0, 0.00001);
    REQUIRE_APPROX(result.out, 10.0, 0.00001);
}

// Test: invlerp with primitive types
TEST_CASE(test_invlerp_primitive) {
    double a = 0.0;
    double b = 10.0;
    double v = 5.0;

    double u = invlerp(v, a, b);
    REQUIRE_APPROX(u, 0.5, 0.00001);
}

// Test: invlerp with Ordinate
TEST_CASE(test_invlerp_ordinate) {
    auto a = Ordinate::init(0.0);
    auto b = Ordinate::init(10.0);
    auto v = Ordinate::init(5.0);

    auto u = invlerp(v, a, b);
    REQUIRE(u.eql_approx(Ordinate::init(0.5)));
}

// Test: output_at_input_between
TEST_CASE(test_output_at_input_between) {
    auto fst = ControlPoint::init(ControlPoint_BaseType{0.0, 0.0});
    auto snd = ControlPoint::init(ControlPoint_BaseType{10.0, 20.0});
    auto t = Ordinate::init(5.0);

    auto result = output_at_input_between(t, fst, snd);
    REQUIRE(result.eql_approx(Ordinate::init(10.0)));
}

// Test: input_at_output_between
TEST_CASE(test_input_at_output_between) {
    auto fst = ControlPoint::init(ControlPoint_BaseType{0.0, 0.0});
    auto snd = ControlPoint::init(ControlPoint_BaseType{10.0, 20.0});
    auto v = Ordinate::init(10.0);

    auto result = input_at_output_between(v, fst, snd);
    REQUIRE(result.eql_approx(Ordinate::init(5.0)));
}

// Test: _bezier0 basic evaluation
TEST_CASE(test_bezier0_basic) {
    // At u=0, bezier should be 0
    auto u = Ordinate::init(0.0);
    auto p2 = Ordinate::init(3.0);
    auto p3 = Ordinate::init(6.0);
    auto p4 = Ordinate::init(10.0);

    auto result = _bezier0(u, p2, p3, p4);
    REQUIRE(result.eql_approx(Ordinate::ZERO()));
}

// Test: _bezier0 at u=1
TEST_CASE(test_bezier0_at_one) {
    // At u=1, bezier should be p4
    auto u = Ordinate::init(1.0);
    auto p2 = Ordinate::init(3.0);
    auto p3 = Ordinate::init(6.0);
    auto p4 = Ordinate::init(10.0);

    auto result = _bezier0(u, p2, p3, p4);
    REQUIRE(result.eql_approx(p4));
}

// Test: actual_order - linear
TEST_CASE(test_actual_order_linear) {
    // Linear: all points on a line
    auto p0 = Ordinate::init(0.0);
    auto p1 = Ordinate::init(1.0);
    auto p2 = Ordinate::init(2.0);
    auto p3 = Ordinate::init(3.0);

    auto order = actual_order(p0, p1, p2, p3);
    REQUIRE(order == 1);
}

// Test: actual_order - cubic
TEST_CASE(test_actual_order_cubic) {
    // Cubic: general bezier
    auto p0 = Ordinate::init(0.0);
    auto p1 = Ordinate::init(1.0);
    auto p2 = Ordinate::init(4.0);
    auto p3 = Ordinate::init(10.0);

    auto order = actual_order(p0, p1, p2, p3);
    REQUIRE(order == 3);
}

//
// ─── MAIN ───────────────────────────────────────────────────────────────────
//
int main() {
    return tinytest::run_all();
}
