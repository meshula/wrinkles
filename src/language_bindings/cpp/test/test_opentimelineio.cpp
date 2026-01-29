// test_opentimelineio.cpp - C++ Unit Tests
//
// Basic unit tests for the C++ OpenTimelineIO binding.

#include <iostream>
#include <cassert>
#include <cmath>
#include "opentimelineio.hpp"

// Test counter
static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) \
    std::cout << "  Testing " << #name << "... "; \
    try

#define TEST_END \
    std::cout << "PASSED\n"; \
    tests_passed++; \
    } catch (const std::exception& e) { \
        std::cout << "FAILED: " << e.what() << "\n"; \
        tests_failed++; \
    } catch (...) { \
        std::cout << "FAILED: unknown exception\n"; \
        tests_failed++; \
    }

#define ASSERT(cond) \
    if (!(cond)) { throw std::runtime_error("Assertion failed: " #cond); }

#define ASSERT_EQ(a, b) \
    if ((a) != (b)) { throw std::runtime_error("Assertion failed: " #a " == " #b); }

#define ASSERT_NEAR(a, b, eps) \
    if (std::fabs((a) - (b)) > (eps)) { throw std::runtime_error("Assertion failed: " #a " ~= " #b); }

// ============================================================================
// Ordinate Tests
// ============================================================================

void test_ordinate() {
    std::cout << "Ordinate Tests:\n";

    TEST(default_construction) {
        otio::Ordinate o;
        ASSERT_EQ(o.value, 0.0f);
    TEST_END

    TEST(value_construction) {
        otio::Ordinate o(3.14f);
        ASSERT_NEAR(o.value, 3.14f, 0.001f);
    TEST_END

    TEST(named_constructors) {
        ASSERT_EQ(otio::Ordinate::zero().value, 0.0f);
        ASSERT_EQ(otio::Ordinate::one().value, 1.0f);
        ASSERT(otio::Ordinate::inf().is_inf());
        ASSERT(otio::Ordinate::neg_inf().is_inf());
    TEST_END

    TEST(arithmetic) {
        otio::Ordinate a(2.0f);
        otio::Ordinate b(3.0f);
        ASSERT_EQ((a + b).value, 5.0f);
        ASSERT_EQ((b - a).value, 1.0f);
        ASSERT_EQ((a * b).value, 6.0f);
        ASSERT_EQ((b / a).value, 1.5f);
        ASSERT_EQ((-a).value, -2.0f);
    TEST_END

    TEST(comparison) {
        otio::Ordinate a(2.0f);
        otio::Ordinate b(3.0f);
        ASSERT(a < b);
        ASSERT(a <= b);
        ASSERT(b > a);
        ASSERT(b >= a);
        ASSERT(a == otio::Ordinate(2.0f));
        ASSERT(a != b);
    TEST_END
}

// ============================================================================
// ContinuousInterval Tests
// ============================================================================

void test_continuous_interval() {
    std::cout << "\nContinuousInterval Tests:\n";

    TEST(default_construction) {
        otio::ContinuousInterval i;
        ASSERT_EQ(i.start.value, 0.0f);
        ASSERT_EQ(i.end.value, 0.0f);
    TEST_END

    TEST(value_construction) {
        otio::ContinuousInterval i(1.0f, 5.0f);
        ASSERT_EQ(i.start.value, 1.0f);
        ASSERT_EQ(i.end.value, 5.0f);
    TEST_END

    TEST(duration) {
        otio::ContinuousInterval i(1.0f, 5.0f);
        ASSERT_EQ(i.duration().value, 4.0f);
    TEST_END

    TEST(from_start_duration) {
        auto i = otio::ContinuousInterval::from_start_duration(
            otio::Ordinate(2.0f),
            otio::Ordinate(3.0f)
        );
        ASSERT_EQ(i.start.value, 2.0f);
        ASSERT_EQ(i.end.value, 5.0f);
    TEST_END

    TEST(contains) {
        otio::ContinuousInterval i(1.0f, 5.0f);
        ASSERT(i.contains(otio::Ordinate(2.0f)));
        ASSERT(i.contains(otio::Ordinate(1.0f)));
        ASSERT(!i.contains(otio::Ordinate(5.0f)));  // half-open interval
        ASSERT(!i.contains(otio::Ordinate(0.0f)));
    TEST_END

    TEST(overlaps) {
        otio::ContinuousInterval a(1.0f, 5.0f);
        otio::ContinuousInterval b(3.0f, 7.0f);
        otio::ContinuousInterval c(6.0f, 8.0f);
        ASSERT(a.overlaps(b));
        ASSERT(b.overlaps(a));
        ASSERT(!a.overlaps(c));
    TEST_END
}

// ============================================================================
// Rational Tests
// ============================================================================

void test_rational() {
    std::cout << "\nRational Tests:\n";

    TEST(default_construction) {
        otio::Rational r;
        ASSERT_EQ(r.numerator, 0u);
        ASSERT_EQ(r.denominator, 1u);
    TEST_END

    TEST(value_construction) {
        otio::Rational r(24000, 1001);
        ASSERT_EQ(r.numerator, 24000u);
        ASSERT_EQ(r.denominator, 1001u);
    TEST_END

    TEST(named_constructors) {
        auto fps24 = otio::Rational::fps_24();
        ASSERT_EQ(fps24.numerator, 24u);
        ASSERT_EQ(fps24.denominator, 1u);

        auto fps23976 = otio::Rational::fps_23_976();
        ASSERT_EQ(fps23976.numerator, 24000u);
        ASSERT_EQ(fps23976.denominator, 1001u);
    TEST_END

    TEST(as_double) {
        otio::Rational r(24000, 1001);
        ASSERT_NEAR(r.as_double(), 23.976, 0.001);
    TEST_END

    TEST(equality) {
        otio::Rational a(24, 1);
        otio::Rational b(48, 2);
        ASSERT(a == b);  // equivalent fractions
    TEST_END
}

// ============================================================================
// SampleIndexGenerator Tests
// ============================================================================

void test_sample_index_generator() {
    std::cout << "\nSampleIndexGenerator Tests:\n";

    TEST(index_at) {
        otio::SampleIndexGenerator gen(otio::Rational::fps_24(), 0);
        ASSERT_EQ(gen.index_at(otio::Ordinate(0.0f)), 0u);
        ASSERT_EQ(gen.index_at(otio::Ordinate(1.0f)), 24u);
        ASSERT_EQ(gen.index_at(otio::Ordinate(0.5f)), 12u);
    TEST_END

    TEST(index_at_with_start_index) {
        otio::SampleIndexGenerator gen(otio::Rational::fps_24(), 100);
        ASSERT_EQ(gen.index_at(otio::Ordinate(0.0f)), 100u);
        ASSERT_EQ(gen.index_at(otio::Ordinate(1.0f)), 124u);
    TEST_END
}

// ============================================================================
// ComposableRef Tests
// ============================================================================

void test_composable_ref() {
    std::cout << "\nComposableRef Tests:\n";

    TEST(default_construction) {
        otio::ComposableRef ref;
        ASSERT(!ref.valid());
        ASSERT_EQ(ref.type(), otio::ComposableType::Error);
    TEST_END
}

// ============================================================================
// File I/O Tests (requires sample files)
// ============================================================================

void test_file_io(const char* sample_file) {
    std::cout << "\nFile I/O Tests:\n";

    TEST(read_timeline) {
        otio::Timeline tl = otio::read_from_file(sample_file);
        ASSERT(tl.valid());
    TEST_END

    TEST(timeline_has_tracks) {
        otio::Timeline tl = otio::read_from_file(sample_file);
        ASSERT(tl.track_count() > 0);
    TEST_END

    TEST(iterate_tracks) {
        otio::Timeline tl = otio::read_from_file(sample_file);
        size_t count = 0;
        for (auto track : tl) {
            ASSERT(track.valid());
            count++;
        }
        ASSERT_EQ(count, tl.track_count());
    TEST_END

    TEST(track_children) {
        otio::Timeline tl = otio::read_from_file(sample_file);
        for (auto track : tl) {
            for (auto child : track) {
                ASSERT(child.valid());
                // Type should be one of the valid types
                auto t = child.type();
                ASSERT(t == otio::ComposableType::Clip ||
                       t == otio::ComposableType::Gap ||
                       t == otio::ComposableType::Transition ||
                       t == otio::ComposableType::Warp);
            }
        }
    TEST_END

    TEST(move_semantics) {
        otio::Timeline tl1 = otio::read_from_file(sample_file);
        ASSERT(tl1.valid());

        otio::Timeline tl2 = std::move(tl1);
        ASSERT(tl2.valid());
        ASSERT(!tl1.valid());  // moved-from should be invalid
    TEST_END
}

// ============================================================================
// Projection Tests (requires sample files)
// ============================================================================

void test_projection(const char* sample_file) {
    std::cout << "\nProjection Tests:\n";

    TEST(build_projection) {
        otio::Timeline tl = otio::read_from_file(sample_file);
        otio::TemporalProjectionBuilder projector(tl);
        ASSERT(projector.valid());
    TEST_END

    TEST(segment_count) {
        otio::Timeline tl = otio::read_from_file(sample_file);
        otio::TemporalProjectionBuilder projector(tl);
        // Should have at least one segment if timeline has content
        ASSERT(projector.segment_count() > 0);
    TEST_END

    TEST(segment_bounds) {
        otio::Timeline tl = otio::read_from_file(sample_file);
        otio::TemporalProjectionBuilder projector(tl);

        for (size_t i = 0; i < projector.segment_count(); ++i) {
            auto bounds = projector.segment_bounds(i);
            // Duration should be positive (or zero for empty segments)
            ASSERT(bounds.duration().value >= 0.0f);
        }
    TEST_END

    TEST(operators) {
        otio::Timeline tl = otio::read_from_file(sample_file);
        otio::TemporalProjectionBuilder projector(tl);

        for (size_t i = 0; i < projector.segment_count(); ++i) {
            size_t op_count = projector.operator_count(i);
            for (size_t j = 0; j < op_count; ++j) {
                auto op = projector.operator_at(i, j);
                ASSERT(op.valid());
                ASSERT(op.destination().valid());
            }
        }
    TEST_END
}

// ============================================================================
// Main
// ============================================================================

int main(int argc, char* argv[]) {
    std::cout << "C++ OpenTimelineIO Binding Tests\n";
    std::cout << "================================\n\n";

    // Run value type tests (no file needed)
    test_ordinate();
    test_continuous_interval();
    test_rational();
    test_sample_index_generator();
    test_composable_ref();

    // Run file-based tests if a sample file is provided
    if (argc > 1) {
        test_file_io(argv[1]);
        test_projection(argv[1]);
    } else {
        std::cout << "\nSkipping file-based tests (no sample file provided).\n";
        std::cout << "Usage: " << argv[0] << " <sample.otio>\n";
    }

    // Summary
    std::cout << "\n================================\n";
    std::cout << "Results: " << tests_passed << " passed, " << tests_failed << " failed\n";

    return tests_failed > 0 ? 1 : 0;
}
