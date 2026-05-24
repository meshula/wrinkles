#include "dual.hpp"
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
                std::cout << "[FAIL] " << name << "\n" << "       " << e.what() << "\n";
                ++failed;
            } catch (std::exception const& e) {
                std::cout << "[EXC ] " << name << " — " << e.what() << "\n";
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
// ─── DUAL TESTS (ported from Zig) ───────────────────────────────────────────
//
using Ordinate = OrdinateImpl<double>;

// ============================================================================
// Phase 1 Tests: Basic Arithmetic
// ============================================================================

TEST_CASE(test_dual_float_add_float) {
    // From Zig: test "Dual: float + float"
    auto result = 1.0 + 3.0;
    REQUIRE(result == 4.0);
}

TEST_CASE(test_dual_add_float) {
    // From Zig: test "Dual: dual + float"
    auto x = Dual_Ord::init_ri(Ordinate::init(3), Ordinate::ONE());
    auto three = Dual_Ord::init(3.0);
    auto result = x.add(three);

    REQUIRE(result.r.eql(Ordinate::init(6)));
    REQUIRE(result.i.eql(Ordinate::ONE()));
}

TEST_CASE(test_dual_mul_float) {
    // From Zig: test "Dual: * float"
    auto x = Dual_Ord::init_ri(Ordinate::init(3), Ordinate::init(1));
    auto result = x.mul(3.0);

    REQUIRE(result.r.eql(Ordinate::init(9)));
    REQUIRE(result.i.eql(Ordinate::init(3)));
}

TEST_CASE(test_binary_operators_dual_ord) {
    // From Zig: test "Dual: binary operator test"
    const double r1 = 8.0;
    const double r2 = 2.0;

    struct TestCase {
        std::string op;
        double exp_r;
        double exp_i;
    };

    TestCase tests[] = {
        {"add", 10.0, 1.0},
        {"sub", 6.0,  1.0},
        {"mul", 16.0, 2.0},
        {"div", 4.0,  0.5},
    };

    for (auto const& t : tests) {
        auto x = Dual_Ord::init_ri(r1, 1.0);
        Dual_Ord x2, x3;

        if (t.op == "add") {
            x2 = x.add(Dual_Ord::init(r2));
            x3 = x.add(r2);
        } else if (t.op == "sub") {
            x2 = x.sub(Dual_Ord::init(r2));
            x3 = x.sub(r2);
        } else if (t.op == "mul") {
            x2 = x.mul(Dual_Ord::init(r2));
            x3 = x.mul(r2);
        } else if (t.op == "div") {
            x2 = x.div(Dual_Ord::init(r2));
            x3 = x.div(r2);
        }

        // Check dual-dual operation
        REQUIRE_APPROX(x2.r.as<double>(), t.exp_r, 1e-9);
        REQUIRE_APPROX(x2.i.as<double>(), t.exp_i, 1e-9);

        // Check dual-scalar operation
        REQUIRE_APPROX(x3.r.as<double>(), t.exp_r, 1e-9);
        REQUIRE_APPROX(x3.i.as<double>(), t.exp_i, 1e-9);
    }
}

TEST_CASE(test_unary_neg) {
    // From Zig: test "Dual: unary operator test" (neg part)
    const double r1 = 16.0;
    
    auto x = Dual_Ord::init_ri(r1, 1.0);
    auto x2 = x.neg();

    REQUIRE_APPROX(x2.r.as<double>(), -16.0, 1e-9);
    REQUIRE_APPROX(x2.i.as<double>(), -1.0, 1e-9);
}

TEST_CASE(test_dual_numeric_type_basic) {
    // Test DualOf<double> basic operations
    using DualDouble = DualOf<double>;

    auto x = DualDouble::init_ri(3.0, 1.0);
    auto y = DualDouble::init(2.0);

    auto sum = x.add(y);
    REQUIRE_APPROX(sum.r, 5.0, 1e-9);
    REQUIRE_APPROX(sum.i, 1.0, 1e-9);

    auto diff = x.sub(y);
    REQUIRE_APPROX(diff.r, 1.0, 1e-9);
    REQUIRE_APPROX(diff.i, 1.0, 1e-9);

    auto prod = x.mul(y);
    REQUIRE_APPROX(prod.r, 6.0, 1e-9);
    REQUIRE_APPROX(prod.i, 2.0, 1e-9);

    auto quot = x.div(y);
    REQUIRE_APPROX(quot.r, 1.5, 1e-9);
    REQUIRE_APPROX(quot.i, 0.5, 1e-9);
}

TEST_CASE(test_dual_numeric_type_dual_dual_operations) {
    // Test DualOf<double> with dual-dual operations
    using DualDouble = DualOf<double>;

    auto x = DualDouble::init_ri(8.0, 1.0);
    auto y = DualDouble::init_ri(2.0, 0.5);

    auto sum = x.add(y);
    REQUIRE_APPROX(sum.r, 10.0, 1e-9);
    REQUIRE_APPROX(sum.i, 1.5, 1e-9);

    auto diff = x.sub(y);
    REQUIRE_APPROX(diff.r, 6.0, 1e-9);
    REQUIRE_APPROX(diff.i, 0.5, 1e-9);

    // (8 + ε)(2 + 0.5ε) = 16 + (8*0.5 + 1*2)ε = 16 + 6ε
    auto prod = x.mul(y);
    REQUIRE_APPROX(prod.r, 16.0, 1e-9);
    REQUIRE_APPROX(prod.i, 6.0, 1e-9);

    // (8 + ε) / (2 + 0.5ε) = 8/2 + ((2*1 - 8*0.5)/(2*2))ε = 4 + (-2/4)ε = 4 - 0.5ε
    auto quot = x.div(y);
    REQUIRE_APPROX(quot.r, 4.0, 1e-9);
    REQUIRE_APPROX(quot.i, -0.5, 1e-9);
}

TEST_CASE(test_is_dual_trait) {
    // Verify our type trait works
    REQUIRE(is_dual_v<Dual_Ord>);
    REQUIRE(is_dual_v<DualOf<double>>);
    REQUIRE(!is_dual_v<double>);
    REQUIRE(!is_dual_v<Ordinate>);
}

//

// ============================================================================
// Phase 3 Tests: Advanced Operations
// ============================================================================

TEST_CASE(test_dual_ord_sqrt_3_4_5_triangle) {
    // From Zig: test "Dual: Dual_Ord sqrt (3-4-5 triangle)"
    // sqrt(3² + 4²) = sqrt(25) = 5
    // With i=1: derivative is 1/(2*sqrt(25)) = 1/10 = 0.1
    auto d = Dual_Ord::init_ri(
        Ordinate::init(3*3 + 4*4),  // 25
        Ordinate::ONE()              // infinitesimal = 1
    );

    auto result = d.sqrt();

    REQUIRE_APPROX(result.r.as<double>(), 5.0, 1e-9);
    REQUIRE_APPROX(result.i.as<double>(), 0.1, 1e-9);
}

TEST_CASE(test_unary_sqrt_numeric) {
    // From Zig: test "Dual: unary operator test" (sqrt part)
    const double r1 = 16.0;
    
    auto x = Dual_Ord::init_ri(r1, 1.0);
    auto x2 = x.sqrt();

    // sqrt(16) = 4
    REQUIRE_APPROX(x2.r.as<double>(), 4.0, 1e-9);
    // derivative: 1/(2*sqrt(16)) = 1/8 = 0.125
    REQUIRE_APPROX(x2.i.as<double>(), 1.0/(std::sqrt(16.0) * 2.0), 1e-9);
}

TEST_CASE(test_pow_operations) {
    // From Zig: test "Dual: pow"
    struct TestCase {
        double x;
        double exp;
        double exp_r;
        double exp_i;
    };

    TestCase tests[] = {
        {
            .x = 4.0,
            .exp = 0.5,  // sqrt
            .exp_r = 2.0,
            .exp_i = 0.25
        },
        {
            .x = 4.0,
            .exp = 3.0,
            .exp_r = 64.0,
            .exp_i = 48.0
        },
    };

    for (auto const& t : tests) {
        auto x = Dual_Ord::init_ri(t.x, 1.0);
        auto x2 = x.pow(t.exp);

        REQUIRE_APPROX(x2.r.as<double>(), t.exp_r, 1e-9);
        REQUIRE_APPROX(x2.i.as<double>(), t.exp_i, 1e-9);
    }
}

TEST_CASE(test_pow_double_numeric) {
    // Test pow() on DualOf<double>
    using DualDouble = DualOf<double>;

    auto x = DualDouble::init_ri(2.0, 1.0);
    auto x_cubed = x.pow(3.0);

    // 2³ = 8
    REQUIRE_APPROX(x_cubed.r, 8.0, 1e-9);
    // derivative: 3 * 2² = 12
    REQUIRE_APPROX(x_cubed.i, 12.0, 1e-9);
}

// ─── MAIN ──────────────────────────────────────────────────────────────────
//
int main() {
    return tinytest::run_all();
}