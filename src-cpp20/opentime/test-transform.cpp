#include "transform.hpp"
#include <iostream>
#include <cmath>
#include <string_view>

//
// ─── MINIMAL TEST HARNESS (Catch2 style) ──────────────────────────────────
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
// ─── TRANSFORM TESTS (ported from Zig) ────────────────────────────────────
//
using Ordinate = OrdinateImpl<double>;
using Interval = ContinuousIntervalImpl<Ordinate>;
using Transform = AffineTransform1DImpl<Ordinate>;

TEST_CASE(test_identity) {
    auto identity = Transform::IDENTITY();
    REQUIRE(identity.offset.eql(Ordinate::ZERO()));
    REQUIRE(identity.scale.eql(Ordinate::ONE()));

    auto ord = Ordinate::init(42);
    REQUIRE(identity.applied_to_ordinate(ord).eql(ord));
}

TEST_CASE(test_offset_transform) {
    // Zig test: "AffineTransform1D: offset test"
    auto cti = Interval::init(10, 20);

    auto xform = Transform{
        Ordinate::init(10),  // offset
        Ordinate::init(1)    // scale
    };

    auto result = xform.applied_to_interval(cti);

    REQUIRE(result.start.eql(Ordinate::init(20)));
    REQUIRE(result.end.eql(Ordinate::init(30)));
    REQUIRE(result.duration().eql(Ordinate::init(10)));
    REQUIRE(result.duration().eql(cti.duration()));

    // Transform composition: xform ∘ xform
    auto result_xform = xform.applied_to_transform(xform);
    REQUIRE(result_xform.offset.eql(Ordinate::init(20)));
    REQUIRE(result_xform.scale.eql(Ordinate::init(1)));
}

TEST_CASE(test_scale_transform) {
    // Zig test: "AffineTransform1D: scale test"
    auto cti = Interval::init(10, 20);

    auto xform = Transform{
        Ordinate::init(10),  // offset
        Ordinate::init(2)    // scale
    };

    auto result = xform.applied_to_interval(cti);

    REQUIRE(result.start.eql(Ordinate::init(30)));
    REQUIRE(result.end.eql(Ordinate::init(50)));
    REQUIRE(result.duration().eql(cti.duration().mul(xform.scale)));

    // Transform composition: xform ∘ xform
    auto result_xform = xform.applied_to_transform(xform);
    REQUIRE(result_xform.offset.eql(Ordinate::init(30)));
    REQUIRE(result_xform.scale.eql(Ordinate::init(4)));
}

TEST_CASE(test_invert) {
    // Zig test: "AffineTransform1D: invert test"
    auto xform = Transform{
        Ordinate::init(10),  // offset
        Ordinate::init(2)    // scale
    };

    // xform ∘ xform⁻¹ = identity
    auto identity = xform.applied_to_transform(xform.inverted());
    REQUIRE(identity.offset.eql_approx(Ordinate::ZERO()));
    REQUIRE(identity.scale.eql_approx(Ordinate::ONE()));

    // Round-trip test: xform⁻¹(xform(pt)) = pt
    auto pt = Ordinate::init(10);
    auto transformed = xform.applied_to_ordinate(pt);
    auto roundtrip = xform.inverted().applied_to_ordinate(transformed);
    REQUIRE(roundtrip.eql_approx(pt));
}

TEST_CASE(test_applied_to_bounds) {
    // Zig test: "AffineTransform1D: applied_to_bounds"
    auto xform = Transform{
        Ordinate::init(10),   // offset
        Ordinate::init(-1)    // negative scale
    };

    auto bounds = Interval{
        Ordinate::init(10),
        Ordinate::init(20)
    };

    auto result = xform.applied_to_bounds(bounds);

    // With negative scale, applied_to_bounds ensures start < end
    REQUIRE(result.start.lt(result.end));
}

TEST_CASE(test_applied_to_ordinate_formula) {
    // Test the core formula: y = x * scale + offset
    auto xform = Transform{
        Ordinate::init(5),   // offset
        Ordinate::init(3)    // scale
    };

    auto x = Ordinate::init(2);
    auto y = xform.applied_to_ordinate(x);
    
    // y = 2 * 3 + 5 = 11
    REQUIRE(y.eql(Ordinate::init(11)));
}

TEST_CASE(test_transform_composition_associativity) {
    // Test: (A ∘ B) ∘ C = A ∘ (B ∘ C)
    auto A = Transform{ Ordinate::init(1), Ordinate::init(2) };
    auto B = Transform{ Ordinate::init(3), Ordinate::init(4) };
    auto C = Transform{ Ordinate::init(5), Ordinate::init(6) };

    auto left = A.applied_to_transform(B).applied_to_transform(C);
    auto right = A.applied_to_transform(B.applied_to_transform(C));

    REQUIRE(left.offset.eql_approx(right.offset));
    REQUIRE(left.scale.eql_approx(right.scale));
}

TEST_CASE(test_interval_transform_endpoints) {
    // Verify interval transformation uses endpoint transformation
    auto xform = Transform{ Ordinate::init(10), Ordinate::init(2) };
    auto interval = Interval::init(5, 15);

    auto result = xform.applied_to_interval(interval);

    REQUIRE(result.start.eql(xform.applied_to_ordinate(interval.start)));
    REQUIRE(result.end.eql(xform.applied_to_ordinate(interval.end)));
}

TEST_CASE(test_negative_scale_flips_order) {
    auto xform = Transform{ Ordinate::init(0), Ordinate::init(-1) };
    auto interval = Interval::init(10, 20);

    // applied_to_interval does NOT correct order
    auto uncorrected = xform.applied_to_interval(interval);
    REQUIRE(uncorrected.start.gt(uncorrected.end));  // Flipped!

    // applied_to_bounds DOES correct order
    auto corrected = xform.applied_to_bounds(interval);
    REQUIRE(corrected.start.lt(corrected.end));  // Fixed!
}

TEST_CASE(test_scale_zero_edge_case) {
    // Edge case: scale = 0 (degenerate transform)
    auto xform = Transform{ Ordinate::init(5), Ordinate::init(0) };
    auto x = Ordinate::init(100);

    // y = 100 * 0 + 5 = 5 (all points collapse to offset)
    auto y = xform.applied_to_ordinate(x);
    REQUIRE(y.eql(Ordinate::init(5)));

    // Note: inverted() would divide by zero - not tested here
    // as Zig version also doesn't check this
}

TEST_CASE(test_default_construction) {
    auto xform = Transform{};
    REQUIRE(xform.offset.eql(Ordinate::ZERO()));
    REQUIRE(xform.scale.eql(Ordinate::ONE()));

    // Default should be identity
    auto ord = Ordinate::init(42);
    REQUIRE(xform.applied_to_ordinate(ord).eql(ord));
}

//
// ─── MAIN ──────────────────────────────────────────────────────────────────
//
int main() {
    return tinytest::run_all();
}
