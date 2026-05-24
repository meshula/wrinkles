#include "ordinate.hpp"
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
// ─── ORDINATE TESTS (ported from Zig) ───────────────────────────────────────
//
using Ordinate = OrdinateImpl<double>;

TEST_CASE(test_constants) {
    REQUIRE(Ordinate::ZERO().v == 0.0);
    REQUIRE(Ordinate::ONE().v == 1.0);
    REQUIRE(std::isinf(Ordinate::INF().v));
    REQUIRE(std::isinf(Ordinate::INF_NEG().v));
    REQUIRE(std::isnan(Ordinate::NaN().v));
    REQUIRE(Ordinate::EPSILON().v == 1e-6);
}

TEST_CASE(test_init_and_as) {
    auto a = Ordinate::init(3);
    REQUIRE(a.v == 3.0);

    auto b = Ordinate::init(2.5);
    REQUIRE(b.v == 2.5);

    auto i = b.as<int>();
    REQUIRE(i == 2);
    auto f = a.as<float>();
    REQUIRE_APPROX(f, 3.0f, 1e-9);
}

TEST_CASE(test_arithmetic) {
    auto a = Ordinate::init(2.0);
    auto b = Ordinate::init(3.0);
    REQUIRE(a.add(b).v == 5.0);
    REQUIRE(a.sub(b).v == -1.0);
    REQUIRE(a.mul(b).v == 6.0);
    REQUIRE(a.div(b).eql_approx(Ordinate::init(2.0/3.0)));
    REQUIRE(a.pow(3.0).v == 8.0);
}

TEST_CASE(test_abs_and_neg) {
    auto x = Ordinate::init(-5.0);
    REQUIRE(x.abs().v == 5.0);
    REQUIRE(x.neg().v == 5.0);
}

TEST_CASE(test_min_max) {
    auto a = Ordinate::init(2.0);
    auto b = Ordinate::init(3.0);
    REQUIRE(a.min(b).v == 2.0);
    REQUIRE(a.max(b).v == 3.0);
}

TEST_CASE(test_comparisons) {
    auto a = Ordinate::init(2.0);
    auto b = Ordinate::init(3.0);
    REQUIRE(a.lt(b));
    REQUIRE(b.gt(a));
    REQUIRE(a.lteq(b));
    REQUIRE(b.gteq(a));
    REQUIRE(a.eql(a));
    REQUIRE(!a.eql(b));
    REQUIRE(a.eql_approx(a.add(Ordinate::EPSILON().mul(0.9))));
}

TEST_CASE(test_nan_inf) {
    auto n = Ordinate::NaN();
    auto i = Ordinate::INF();
    auto j = Ordinate::INF_NEG();

    REQUIRE(n.is_nan());
    REQUIRE(i.is_inf());
    REQUIRE(j.is_inf());
    REQUIRE(i.is_finite() == false);
    REQUIRE(Ordinate::init(5.0).is_finite());
}

TEST_CASE(test_expression_chain) {
    auto a = Ordinate::init(3.0);
    auto b = Ordinate::init(4.0);
    auto expr = a.mul(b).add(b).sub(a).add(a.div(a)).add(Ordinate::ONE());
    REQUIRE(expr.eql(Ordinate::init(15.0)));
}

TEST_CASE(test_eql_approx_nan_nan_true) {
    auto nan1 = Ordinate::NaN();
    auto nan2 = Ordinate::NaN();
    REQUIRE(nan1.eql_approx(nan2)); // zig semantics: NaN == NaN in approx equality
}

TEST_CASE(test_sqrt_and_pow) {
    auto a = Ordinate::init(9.0);
    REQUIRE(a.sqrt().v == 3.0);
    REQUIRE(a.pow(0.5).v == 3.0);
}

//
// ─── MAIN ───────────────────────────────────────────────────────────────────
//
int main() {
    return tinytest::run_all();
}
