#include "ordinate.hpp"
#include <iostream>
#include <cmath>
#include <string_view>
#include <vector>
#include <typeinfo>
#include <tuple> // Added for consistency with original macro attempt
#include <type_traits> // Necessary for std::type_identity (used in fixed macro)
#include <cxxabi.h> // for demangling type names (optional on non-GNU compilers)

// Assuming OrdinateImpl<T> is available via ordinate.hpp

//
// ─── MINI HARNESS (Catch2 style) ─────────────────────────────────────────────
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
        std::string msg; failure(std::string m): msg(std::move(m)) {}
        const char* what() const noexcept override { return msg.c_str(); }
    };

    inline void require(bool cond, std::string_view expr, std::string_view file, int line) {
        if (!cond)
            throw failure(std::string(file) + ":" + std::to_string(line) + ": REQUIRE failed: " + std::string(expr));
    }

    template<typename A, typename B>
    inline void require_approx(A const& a, B const& b, double eps,
                               std::string_view expr, std::string_view file, int line) {
        double ad = static_cast<double>(a);
        double bd = static_cast<double>(b);
        if (!(std::fabs(ad - bd) <= eps))
            throw failure(std::string(file) + ":" + std::to_string(line) +
                          ": REQUIRE_APPROX failed: " + std::string(expr) +
                          " (|a-b|=" + std::to_string(std::fabs(ad - bd)) +
                          " > eps=" + std::to_string(eps) + ")");
    }

    inline int run_all() {
        int passed = 0, failed = 0;
        for (auto& [name, fn] : registry::tests) {
            try {
                fn();
                std::cout << "[ OK ] " << name << "\n";
                ++passed;
            } catch (failure const& e) {
                std::cout << "[FAIL] " << name << "\n       " << e.what() << "\n";
                ++failed;
            } catch (std::exception const& e) {
                std::cout << "[EXC ] " << name << " — " << e.what() << "\n";
                ++failed;
            }
        }
        std::cout << "\nTests passed: " << passed << " / " << (passed + failed) << "\n";
        return failed == 0 ? 0 : 1;
    }

    // Helper for demangling type names
    template<typename T>
    std::string type_name() {
        int status = 0;
        char* realname = abi::__cxa_demangle(typeid(T).name(), nullptr, nullptr, &status);
        std::string s = (status == 0) ? realname : typeid(T).name();
        std::free(realname);
        return s;
    }
}

#define TEST_CASE(name) \
    static void name(); \
    static ::tinytest::registrar name##_reg{#name, name}; \
    static void name()

#define REQUIRE(expr) ::tinytest::require((expr), #expr, __FILE__, __LINE__)
#define REQUIRE_APPROX(a,b,eps) ::tinytest::require_approx((a),(b),(eps), #a " ≈ " #b, __FILE__, __LINE__)

//
// ─── TEMPLATED TEST FACILITY (FIXED) ────────────────────────────────────────
//

// Helper structure to wrap the list of types
template<typename...> struct TypeList {};

// FIX: New TEMPLATE_TEST_CASE implementation using TypeList and nested lambda unfolding
#define TEMPLATE_TEST_CASE(name, ...) \
    template<typename OrdinateT> static void name##_impl(); \
    static void name() { \
        using namespace tinytest; \
        /* Lambda containing the actual test runner logic */ \
        auto run_test_for_type = []<typename Scalar>() { \
            std::cout << "  Running for type: " << type_name<Scalar>() << "\n"; \
            name##_impl<Scalar>(); \
        }; \
        /* Inner lambda uses a template parameter pack 'Types' to unpack the TypeList */ \
        /* It is immediately called with the macro's arguments wrapped in TypeList */ \
        [run_test_for_type]<typename... Types>(TypeList<Types...>) { \
            /* The pack 'Types' can now be safely expanded element-wise */ \
            (run_test_for_type.template operator()<Types>(), ...); \
        }(TypeList<__VA_ARGS__>{}); \
    } \
    static ::tinytest::registrar name##_reg{#name, name}; \
    template<typename OrdinateT> static void name##_impl()

struct Dual {
    double val, d;
    Dual(double v=0, double d_=0): val(v), d(d_) {}

    // support static cast of Dual to int:
    explicit operator int() const { return static_cast<int>(val); }

    // support static cast of Dual to double:
    explicit operator double() const { return val; }

    // support static cast of Dual to float:
    explicit operator float() const { return static_cast<float>(val); }

    // support std::pow and std::sqrt
    friend Dual pow(Dual base, double exp) {
        double new_val = std::pow(base.val, exp);
        double new_d = exp * std::pow(base.val, exp - 1) * base.d;
        return Dual(new_val, new_d);
    }

    friend Dual sqrt(Dual x) {
        double new_val = std::sqrt(x.val);
        double new_d = (0.5 / new_val) * x.d;
        return Dual(new_val, new_d);
    }

    // equality operator
    bool operator==(Dual o) const { return val == o.val; }
    bool operator!=(Dual o) const { return val != o.val; }
    bool operator<(Dual o) const { return val < o.val; }
    bool operator<=(Dual o) const { return val <= o.val; }
    bool operator>(Dual o) const { return val > o.val; }
    bool operator>=(Dual o) const { return val >= o.val; }

    Dual operator+(Dual o) const { return {val+o.val, d+o.d}; }
    Dual operator-(Dual o) const { return {val-o.val, d-o.d}; }
    Dual operator*(Dual o) const { return {val*o.val, val*o.d + d*o.val}; }
    Dual operator/(Dual o) const { return {val/o.val, (d*o.val - val*o.d)/(o.val*o.val)}; }
};



//
// ─── TESTS ─────────────────────────────────────────────────────────────────
//
TEMPLATE_TEST_CASE(test_ordinate_suite, double, float, Dual) {
    using Ordinate = OrdinateImpl<OrdinateT>;

    auto zero = Ordinate::ZERO();
    REQUIRE(zero.v == OrdinateT(0));

    auto one = Ordinate::ONE();
    REQUIRE(one.v == OrdinateT(1));

    // basic init/as
    auto a = Ordinate::init(3);
    auto b = Ordinate::init(4);
    REQUIRE(a.v == OrdinateT(3));
    REQUIRE(b.v == OrdinateT(4));

    // Added 'template' keyword for dependent name resolution
    REQUIRE(a.template as<int>() == 3);
    REQUIRE_APPROX(a.template as<float>(), 3.0f, 1e-9);

    // arithmetic
    REQUIRE(a.add(b).v == OrdinateT(7));
    REQUIRE(a.sub(b).v == OrdinateT(-1));
    REQUIRE_APPROX(a.div(b).v, 3.0/4.0, 1e-9);

    // chain expr
    auto expr = a.mul(b).add(b).sub(a).add(a.div(a)).add(Ordinate::ONE());
    // Note: We only check the primary value (val) here, assuming OrdinateT(15.0) works for Dual
    REQUIRE(expr.eql(Ordinate::init(15.0))); 

    // comparisons
    REQUIRE(a.lt(b));
    REQUIRE(b.gt(a));
    // Check approximation logic (only for float/double, Dual comparison is more complex)
    if constexpr (!std::is_same_v<OrdinateT, Dual>) {
        REQUIRE(a.eql_approx(a.add(Ordinate::EPSILON().mul(0.5))));
    }

    // NaN/inf (only available for floating point types)
    if constexpr (std::is_floating_point_v<OrdinateT>) {
        auto nanv = Ordinate::NaN();
        REQUIRE(nanv.is_nan());
        auto infv = Ordinate::INF();
        REQUIRE(infv.is_inf());
    }

    // pow/sqrt
    auto c = Ordinate::init(9);
    REQUIRE_APPROX(c.sqrt().v, 3.0, 1e-9);
    REQUIRE_APPROX(c.pow(0.5).v, 3.0, 1e-9);
}

//
// ─── MAIN ───────────────────────────────────────────────────────────────────
//
int main() {
    return tinytest::run_all();
}
