#include "topology.hpp"
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
// ─── TOPOLOGY TESTS ──────────────────────────────────────────────────────────
//

// Test: Empty topology
TEST_CASE(test_empty_topology) {
    auto topo = EMPTY;
    REQUIRE(topo.mappings.empty());

    auto bounds = topo.input_bounds();
    REQUIRE(bounds.start.eql(Ordinate::init(0.0)));
    REQUIRE(bounds.end.eql(Ordinate::init(0.0)));
}

// Test: init_identity
TEST_CASE(test_init_identity) {
    auto topo = Topology::init_identity(
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}
    );

    REQUIRE(topo.mappings.size() == 1);
    REQUIRE(std::holds_alternative<MappingAffine>(topo.mappings[0]));

    auto bounds = topo.input_bounds();
    REQUIRE(bounds.start.eql(Ordinate::init(0.0)));
    REQUIRE(bounds.end.eql(Ordinate::init(10.0)));

    // Test identity projection
    auto result = topo.project_instantaneous_cc(Ordinate::init(5.0));
    REQUIRE(!result.is_out_of_bounds());
    REQUIRE(result.ordinate().eql(Ordinate::init(5.0)));
}

// Test: init_affine
TEST_CASE(test_init_affine) {
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(5.0), Ordinate::init(2.0)}
    };

    auto topo = Topology::init_affine(affine);

    REQUIRE(topo.mappings.size() == 1);

    // Test projection: f(3) = 2*3 + 5 = 11
    auto result = topo.project_instantaneous_cc(Ordinate::init(3.0));
    REQUIRE(!result.is_out_of_bounds());
    REQUIRE(result.ordinate().eql(Ordinate::init(11.0)));
}

// Test: init_from_linear_monotonic
TEST_CASE(test_init_from_linear_monotonic) {
    std::vector<ControlPoint> knots = {
        {Ordinate::init(0.0), Ordinate::init(0.0)},
        {Ordinate::init(10.0), Ordinate::init(20.0)}
    };

    auto curve = LinearMonotonic{knots};
    auto topo = Topology::init_from_linear_monotonic(curve);

    REQUIRE(topo.mappings.size() == 1);
    REQUIRE(std::holds_alternative<MappingCurveLinearMonotonic>(topo.mappings[0]));

    // Test projection: f(5) = 10
    auto result = topo.project_instantaneous_cc(Ordinate::init(5.0));
    REQUIRE(!result.is_out_of_bounds());
    REQUIRE(result.ordinate().eql(Ordinate::init(10.0)));
}

// Test: input_bounds and output_bounds
TEST_CASE(test_bounds) {
    std::vector<Mapping> mappings;
    mappings.push_back(Mapping{MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(2.0)}
    }});
    mappings.push_back(Mapping{MappingAffine{
        ContinuousInterval{Ordinate::init(10.0), Ordinate::init(20.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(3.0)}
    }});

    auto topo = Topology{std::move(mappings)};

    auto in_bounds = topo.input_bounds();
    REQUIRE(in_bounds.start.eql(Ordinate::init(0.0)));
    REQUIRE(in_bounds.end.eql(Ordinate::init(20.0)));

    auto out_bounds = topo.output_bounds();
    REQUIRE(out_bounds.start.eql(Ordinate::init(0.0)));
    REQUIRE(out_bounds.end.eql(Ordinate::init(60.0))); // 20 * 3
}

// Test: end_points_input
TEST_CASE(test_end_points_input) {
    std::vector<Mapping> mappings;
    mappings.push_back(Mapping{MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D::IDENTITY()
    }});
    mappings.push_back(Mapping{MappingAffine{
        ContinuousInterval{Ordinate::init(10.0), Ordinate::init(20.0)},
        AffineTransform1D::IDENTITY()
    }});

    auto topo = Topology{std::move(mappings)};

    auto endpoints = topo.end_points_input();
    REQUIRE(endpoints.size() == 3); // start, middle, end
    REQUIRE(endpoints[0].eql(Ordinate::init(0.0)));
    REQUIRE(endpoints[1].eql(Ordinate::init(10.0)));
    REQUIRE(endpoints[2].eql(Ordinate::init(20.0)));
}

// Test: project_instantaneous_cc
TEST_CASE(test_project_instantaneous_cc) {
    auto topo = Topology::init_identity(
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}
    );

    // In bounds
    auto result = topo.project_instantaneous_cc(Ordinate::init(5.0));
    REQUIRE(!result.is_out_of_bounds());
    REQUIRE(result.ordinate().eql(Ordinate::init(5.0)));

    // Out of bounds
    result = topo.project_instantaneous_cc(Ordinate::init(15.0));
    REQUIRE(result.is_out_of_bounds());
}

// Test: project_instantaneous_cc_inv
TEST_CASE(test_project_instantaneous_cc_inv) {
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(2.0)}
    };

    auto topo = Topology::init_affine(affine);

    // f(5) = 10, so f^-1(10) = 5
    auto results = topo.project_instantaneous_cc_inv(Ordinate::init(10.0));
    REQUIRE(results.size() == 1);
    REQUIRE(results[0].eql(Ordinate::init(5.0)));

    // Out of bounds
    results = topo.project_instantaneous_cc_inv(Ordinate::init(30.0));
    REQUIRE(results.empty());
}

// Test: clone
TEST_CASE(test_clone) {
    auto topo1 = Topology::init_identity(
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}
    );

    auto topo2 = topo1.clone();

    REQUIRE(topo2.mappings.size() == topo1.mappings.size());

    auto result1 = topo1.project_instantaneous_cc(Ordinate::init(5.0));
    auto result2 = topo2.project_instantaneous_cc(Ordinate::init(5.0));

    REQUIRE(result1.ordinate().eql(result2.ordinate()));
}

// Test: trim_in_input_space - no trim
TEST_CASE(test_trim_in_input_space_no_trim) {
    auto topo = Topology::init_identity(
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}
    );

    auto trimmed = topo.trim_in_input_space(
        ContinuousInterval{Ordinate::init(-1.0), Ordinate::init(11.0)}
    );

    auto bounds = trimmed.input_bounds();
    REQUIRE(bounds.start.eql(Ordinate::init(0.0)));
    REQUIRE(bounds.end.eql(Ordinate::init(10.0)));
}

// Test: trim_in_input_space - trim left
TEST_CASE(test_trim_in_input_space_left) {
    auto topo = Topology::init_identity(
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}
    );

    auto trimmed = topo.trim_in_input_space(
        ContinuousInterval{Ordinate::init(3.0), Ordinate::init(11.0)}
    );

    auto bounds = trimmed.input_bounds();
    REQUIRE(bounds.start.eql(Ordinate::init(3.0)));
    REQUIRE(bounds.end.eql(Ordinate::init(10.0)));
}

// Test: trim_in_input_space - trim right
TEST_CASE(test_trim_in_input_space_right) {
    auto topo = Topology::init_identity(
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}
    );

    auto trimmed = topo.trim_in_input_space(
        ContinuousInterval{Ordinate::init(-1.0), Ordinate::init(7.0)}
    );

    auto bounds = trimmed.input_bounds();
    REQUIRE(bounds.start.eql(Ordinate::init(0.0)));
    REQUIRE(bounds.end.eql(Ordinate::init(7.0)));
}

// Test: trim_in_input_space - trim both sides
TEST_CASE(test_trim_in_input_space_both) {
    auto topo = Topology::init_identity(
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}
    );

    auto trimmed = topo.trim_in_input_space(
        ContinuousInterval{Ordinate::init(3.0), Ordinate::init(7.0)}
    );

    auto bounds = trimmed.input_bounds();
    REQUIRE(bounds.start.eql(Ordinate::init(3.0)));
    REQUIRE(bounds.end.eql(Ordinate::init(7.0)));
}

// Test: split_at_input_points
TEST_CASE(test_split_at_input_points) {
    auto topo = Topology::init_affine(MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(4.0), Ordinate::init(2.0)}
    });

    std::vector<Ordinate> split_points = {
        Ordinate::init(2.0),
        Ordinate::init(5.0),
        Ordinate::init(8.0)
    };

    auto split_topo = topo.split_at_input_points(split_points);

    // Should have 4 segments: [0,2], [2,5], [5,8], [8,10]
    REQUIRE(split_topo.mappings.size() == 4);
}

// Test: inverted
TEST_CASE(test_inverted) {
    auto affine = MappingAffine{
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)},
        AffineTransform1D{Ordinate::init(0.0), Ordinate::init(2.0)}
    };

    auto topo = Topology::init_affine(affine);

    auto inverted_topos = topo.inverted();
    REQUIRE(inverted_topos.size() >= 1);

    auto const& inv_topo = inverted_topos[0];

    // Original: f(5) = 10
    auto forward = topo.project_instantaneous_cc(Ordinate::init(5.0));
    REQUIRE(forward.ordinate().eql(Ordinate::init(10.0)));

    // Inverted: f^-1(10) = 5
    auto backward = inv_topo.project_instantaneous_cc(Ordinate::init(10.0));
    REQUIRE(!backward.is_out_of_bounds());
    REQUIRE(backward.ordinate().eql(Ordinate::init(5.0)));
}

// Test: Stream output
TEST_CASE(test_stream_output) {
    auto topo = Topology::init_identity(
        ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}
    );

    std::ostringstream oss;
    oss << topo;

    REQUIRE(oss.str().length() > 0);
}

//
// ─── MAIN ────────────────────────────────────────────────────────────────────
//
int main() {
    return tinytest::run_all();
}
