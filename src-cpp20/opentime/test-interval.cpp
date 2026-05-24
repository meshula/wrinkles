#include "interval.hpp"
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
// ─── INTERVAL TESTS (ported from Zig) ─────────────────────────────────────
//
using Ordinate = OrdinateImpl<double>;
using Interval = ContinuousIntervalImpl<Ordinate>;

TEST_CASE(test_is_infinite) {
    auto cti = Interval{}; // Default: start=0, end=INF
    REQUIRE(cti.is_infinite());

    cti.end = Ordinate::init(2);
    REQUIRE(!cti.is_infinite());

    cti.start = Ordinate::INF();
    REQUIRE(cti.is_infinite());
}

TEST_CASE(test_extend) {
    struct TestCase {
        Interval fst;
        Interval snd;
        Interval expected;
    };

    TestCase tests[] = {
        { Interval::init(0, 10), Interval::init(8, 12), Interval::init(0, 12) },
        { Interval::init(0, 10), Interval::init(-2, 9), Interval::init(-2, 10) },
        { Interval::init(0, 10), Interval::init(-2, 12), Interval::init(-2, 12) },
        { Interval::init(0, 2), Interval::init(4, 12), Interval::init(0, 12) },
    };

    for (auto const& t : tests) {
        auto measured = extend(t.fst, t.snd);
        REQUIRE(measured.start.eql(t.expected.start));
        REQUIRE(measured.end.eql(t.expected.end));
    }
}

TEST_CASE(test_any_overlap) {
    struct TestCase {
        Interval fst;
        Interval snd;
        bool expected;
    };

    TestCase tests[] = {
        { Interval::init(0, 10), Interval::init(8, 12), true },
        { Interval::init(0, 10), Interval::init(-2, 9), true },
        { Interval::init(0, 10), Interval::init(-2, 12), true },
        { Interval::init(0, 4), Interval::init(5, 12), false },
        { Interval::init(0, 4), Interval::init(-2, 0), false },
    };

    for (auto const& t : tests) {
        auto measured = any_overlap(t.fst, t.snd);
        REQUIRE(measured == t.expected);
    }
}

TEST_CASE(test_intersect_contained) {
    auto int1 = Interval::init(0, 10);
    auto int2 = Interval::init(1, 3);
    auto res_opt = intersect(int1, int2);

    REQUIRE(res_opt.has_value());
    auto res = *res_opt;
    REQUIRE(res.start.eql(int2.start));
    REQUIRE(res.end.eql(int2.end));
}

TEST_CASE(test_intersect_infinite) {
    auto int1 = Interval::INF();
    auto int2 = Interval::init(1, 3);
    auto res_opt = intersect(int1, int2);

    REQUIRE(res_opt.has_value());
    auto res = *res_opt;
    REQUIRE(res.start.eql(int2.start));
    REQUIRE(res.end.eql(int2.end));
}

TEST_CASE(test_intersect_disjoint) {
    auto int1 = Interval::init(0, 4);
    auto int2 = Interval::init(5, 10);
    auto res_opt = intersect(int1, int2);

    REQUIRE(!res_opt.has_value());
}

TEST_CASE(test_duration_and_from_start_duration) {
    auto ival = Interval::init(10, 20);
    REQUIRE(ival.duration().eql(Ordinate::init(10)));

    auto reconstructed = Interval::from_start_duration(ival.start, ival.duration());
    REQUIRE(reconstructed == ival);
}

TEST_CASE(test_overlaps) {
    auto ival = Interval::init(10, 20);

    REQUIRE(!ival.overlaps(Ordinate::init(0)));   // Before
    REQUIRE(ival.overlaps(Ordinate::init(10)));   // At start (inclusive)
    REQUIRE(ival.overlaps(Ordinate::init(15)));   // Middle
    REQUIRE(!ival.overlaps(Ordinate::init(20)));  // At end (exclusive)
    REQUIRE(!ival.overlaps(Ordinate::init(30)));  // After
}

TEST_CASE(test_is_instant) {
    auto not_instant = Interval::init(0.0, 0.1);
    REQUIRE(!not_instant.is_instant());

    auto collapsed = Interval::init(10, 10);
    REQUIRE(collapsed.is_instant());
}

TEST_CASE(test_constants) {
    auto inf_interval = Interval::INF();
    REQUIRE(inf_interval.start.is_inf());
    REQUIRE(inf_interval.start.lt(0));  // INF_NEG
    REQUIRE(inf_interval.end.is_inf());
    REQUIRE(inf_interval.end.gt(0));    // INF

    auto zero_interval = Interval::ZERO();
    REQUIRE(zero_interval.start.eql(Ordinate::ZERO()));
    REQUIRE(zero_interval.end.eql(Ordinate::ZERO()));
    REQUIRE(zero_interval.is_instant());
}

TEST_CASE(test_default_construction) {
    auto default_interval = Interval{};
    REQUIRE(default_interval.start.eql(Ordinate::ZERO()));
    REQUIRE(default_interval.end.is_inf());
    REQUIRE(default_interval.is_infinite());
}

TEST_CASE(test_from_start_duration_validation) {
    bool threw = false;
    try {
        auto bad = Interval::from_start_duration(Ordinate::init(0), Ordinate::init(0));
    } catch (std::invalid_argument const&) {
        threw = true;
    }
    REQUIRE(threw);

    threw = false;
    try {
        auto bad = Interval::from_start_duration(Ordinate::init(0), Ordinate::init(-1));
    } catch (std::invalid_argument const&) {
        threw = true;
    }
    REQUIRE(threw);
}

TEST_CASE(test_overlaps_instant_point) {
    // Test instant interval (collapsed to a point)
    auto instant = Interval::init(5, 5);
    auto normal = Interval::init(0, 10);

    // Instant point should overlap with normal interval containing it
    REQUIRE(any_overlap(instant, normal));
    REQUIRE(any_overlap(normal, instant));

    // Instant point at interval boundary
    auto boundary_instant = Interval::init(0, 0);
    REQUIRE(any_overlap(boundary_instant, normal));

    // Two identical instant points
    auto instant2 = Interval::init(5, 5);
    REQUIRE(any_overlap(instant, instant2));
}

//
// ─── MAIN ──────────────────────────────────────────────────────────────────
//
int main() {
    return tinytest::run_all();
}
