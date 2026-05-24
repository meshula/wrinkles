#include "bezier_curve.hpp"
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
// ─── BEZIER SEGMENT TESTS ────────────────────────────────────────────────────
//

// Test: Basic segment construction
TEST_CASE(test_segment_construction) {
    auto seg = BezierSegment{
        ControlPoint::init(ControlPoint_BaseType{0.0, 0.0}),
        ControlPoint::init(ControlPoint_BaseType{1.0, 1.0}),
        ControlPoint::init(ControlPoint_BaseType{2.0, 2.0}),
        ControlPoint::init(ControlPoint_BaseType{3.0, 3.0})
    };

    REQUIRE(seg.p0.in.eql_approx(Ordinate::init(0.0)));
    REQUIRE(seg.p3.in.eql_approx(Ordinate::init(3.0)));
}

// Test: init_identity
TEST_CASE(test_segment_init_identity) {
    auto seg = BezierSegment::init_identity(
        Ordinate::init(0.0),
        Ordinate::init(1.0)
    );

    // For identity, in == out at endpoints
    REQUIRE(seg.p0.in.eql_approx(seg.p0.out));
    REQUIRE(seg.p3.in.eql_approx(seg.p3.out));
    REQUIRE(seg.p0.in.eql_approx(Ordinate::init(0.0)));
    REQUIRE(seg.p3.in.eql_approx(Ordinate::init(1.0)));
}

// Test: init_from_start_end
TEST_CASE(test_segment_init_from_start_end) {
    auto start = ControlPoint::init(ControlPoint_BaseType{0.0, 0.0});
    auto end = ControlPoint::init(ControlPoint_BaseType{10.0, 20.0});

    auto seg = BezierSegment::init_from_start_end(start, end);

    REQUIRE(seg.p0.in.eql_approx(start.in));
    REQUIRE(seg.p0.out.eql_approx(start.out));
    REQUIRE(seg.p3.in.eql_approx(end.in));
    REQUIRE(seg.p3.out.eql_approx(end.out));

    // p1 should be 1/3 of the way from start to end
    auto expected_p1 = lerp(1.0 / 3.0, start, end);
    expectControlPointEqual(seg.p1, expected_p1);
}

// Test: points() and set_points()
TEST_CASE(test_segment_points) {
    auto seg = BezierSegment::init_identity(
        Ordinate::init(0.0),
        Ordinate::init(1.0)
    );

    auto pts = seg.points();
    REQUIRE(pts.size() == 4);
    REQUIRE(pts[0].in.eql_approx(seg.p0.in));
    REQUIRE(pts[3].in.eql_approx(seg.p3.in));

    // Test set_points
    auto new_pts = std::array<ControlPoint, 4>{
        ControlPoint::init(ControlPoint_BaseType{1.0, 1.0}),
        ControlPoint::init(ControlPoint_BaseType{2.0, 2.0}),
        ControlPoint::init(ControlPoint_BaseType{3.0, 3.0}),
        ControlPoint::init(ControlPoint_BaseType{4.0, 4.0})
    };
    seg.set_points(new_pts);

    REQUIRE(seg.p0.in.eql_approx(Ordinate::init(1.0)));
    REQUIRE(seg.p3.in.eql_approx(Ordinate::init(4.0)));
}

// Test: eval_at on linear segment
TEST_CASE(test_segment_eval_at_linear) {
    // Create a linear segment from (0,0) to (10,20)
    auto seg = BezierSegment::init_from_start_end(
        ControlPoint::init(ControlPoint_BaseType{0.0, 0.0}),
        ControlPoint::init(ControlPoint_BaseType{10.0, 20.0})
    );

    // At u=0, should be at start
    auto result = seg.eval_at(Ordinate::init(0.0));
    REQUIRE(result.in.eql_approx(Ordinate::init(0.0)));
    REQUIRE(result.out.eql_approx(Ordinate::init(0.0)));

    // At u=0.5, should be at midpoint
    result = seg.eval_at(Ordinate::init(0.5));
    REQUIRE(result.in.eql_approx(Ordinate::init(5.0)));
    REQUIRE(result.out.eql_approx(Ordinate::init(10.0)));

    // At u=1, should be at end
    result = seg.eval_at(Ordinate::init(1.0));
    REQUIRE(result.in.eql_approx(Ordinate::init(10.0)));
    REQUIRE(result.out.eql_approx(Ordinate::init(20.0)));
}

// Test: eval_at on identity segment
TEST_CASE(test_segment_eval_at_identity) {
    auto seg = BezierSegment::IDENT_ZERO_ONE();

    // At any u, in should equal out for identity
    for (double u : {0.0, 0.25, 0.5, 0.75, 1.0}) {
        auto result = seg.eval_at(Ordinate::init(u));
        REQUIRE(result.in.eql_approx(result.out));
    }
}

// Test: split_at
TEST_CASE(test_segment_split_at) {
    auto seg = BezierSegment::init_from_start_end(
        ControlPoint::init(ControlPoint_BaseType{0.0, 0.0}),
        ControlPoint::init(ControlPoint_BaseType{10.0, 20.0})
    );

    auto split = seg.split_at(0.5);
    REQUIRE(split.has_value());

    auto& [left, right] = *split;

    // Left segment should start at original start
    REQUIRE(left.p0.in.eql_approx(seg.p0.in));
    REQUIRE(left.p0.out.eql_approx(seg.p0.out));

    // Right segment should end at original end
    REQUIRE(right.p3.in.eql_approx(seg.p3.in));
    REQUIRE(right.p3.out.eql_approx(seg.p3.out));

    // Left end should equal right start (continuity)
    REQUIRE(left.p3.in.eql_approx(right.p0.in));
    REQUIRE(left.p3.out.eql_approx(right.p0.out));

    // Split point should be at u=0.5 on original
    auto split_point = seg.eval_at(Ordinate::init(0.5));
    REQUIRE(left.p3.in.eql_approx(split_point.in));
    REQUIRE(left.p3.out.eql_approx(split_point.out));
}

// Test: split_at with invalid u
TEST_CASE(test_segment_split_at_invalid) {
    auto seg = BezierSegment::IDENT_ZERO_ONE();

    // u < 0 should return nullopt
    auto split = seg.split_at(-0.1);
    REQUIRE(!split.has_value());

    // u >= 1 should return nullopt
    split = seg.split_at(1.0);
    REQUIRE(!split.has_value());

    split = seg.split_at(1.5);
    REQUIRE(!split.has_value());
}

// Test: Bezier collection construction
TEST_CASE(test_bezier_construction) {
    std::vector<BezierSegment> segments = {
        BezierSegment::init_identity(Ordinate::init(0.0), Ordinate::init(1.0)),
        BezierSegment::init_identity(Ordinate::init(1.0), Ordinate::init(2.0))
    };

    auto bez = Bezier{segments};
    REQUIRE(bez.segment_count() == 2);
    REQUIRE(!bez.empty());
}

// Test: Empty Bezier
TEST_CASE(test_bezier_empty) {
    auto bez = Bezier{};
    REQUIRE(bez.empty());
    REQUIRE(bez.segment_count() == 0);
}

//
// ─── MAIN ───────────────────────────────────────────────────────────────────
//
int main() {
    return tinytest::run_all();
}
