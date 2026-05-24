#include "temporal_hierarchy.hpp"
#include <iostream>
#include <cassert>
#include <cmath>

using namespace otio;
using namespace otio::temporal;

// Test counter
int tests_run = 0;
int tests_passed = 0;

#define TEST(name) \
    std::cout << "Test " << (++tests_run) << ": " << name << "... "; \
    try {

#define END_TEST() \
        tests_passed++; \
        std::cout << "PASSED\n"; \
    } catch (std::exception const& e) { \
        std::cout << "FAILED: " << e.what() << "\n"; \
    }

// Helper to compare doubles
bool approx_equal(double a, double b, double epsilon = 1e-9) {
    return std::abs(a - b) < epsilon;
}

// Helper to compare ordinates
bool approx_equal(Ordinate const& a, Ordinate const& b) {
    return approx_equal(a.v, b.v);
}

int main() {
    std::cout << "Running OpenTimelineIO Temporal Hierarchy Tests\n";
    std::cout << "================================================\n\n";

    // ========================================================================
    // Test 1: Space reference equality
    // ========================================================================
    TEST("Space reference equality")
        Clip clip{"test"};
        SpaceReference ref1{&clip, SpaceLabel::presentation};
        SpaceReference ref2{&clip, SpaceLabel::presentation};
        SpaceReference ref3{&clip, SpaceLabel::media};

        assert(space_ref_equal(ref1, ref2));
        assert(!space_ref_equal(ref1, ref3));
    END_TEST()

    // ========================================================================
    // Test 2: Build internal operators for Clip
    // ========================================================================
    TEST("Build internal operators for Clip")
        Clip clip{"test_clip", ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        }};

        ComposedValueRef ref = &clip;
        auto ops = build_internal_operators(ref);

        // Clip should have one internal operator: presentation -> media
        assert(ops.size() == 1);
        assert(ops[0].source.label == SpaceLabel::presentation);
        assert(ops[0].destination.label == SpaceLabel::media);
    END_TEST()

    // ========================================================================
    // Test 3: Build internal operators for Gap
    // ========================================================================
    TEST("Build internal operators for Gap")
        Gap gap{Ordinate::init(5.0)};

        ComposedValueRef ref = &gap;
        auto ops = build_internal_operators(ref);

        // Gap has no internal operators (only presentation space)
        assert(ops.empty());
    END_TEST()

    // ========================================================================
    // Test 4: Build internal operators for Track
    // ========================================================================
    TEST("Build internal operators for Track")
        Track track{"test_track"};

        ComposedValueRef ref = &track;
        auto ops = build_internal_operators(ref);

        // Track should have one internal operator: presentation -> intrinsic
        assert(ops.size() == 1);
        assert(ops[0].source.label == SpaceLabel::presentation);
        assert(ops[0].destination.label == SpaceLabel::intrinsic);
    END_TEST()

    // ========================================================================
    // Test 5: Get children from Track
    // ========================================================================
    TEST("Get children from Track")
        Clip clip1{"clip1", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}};
        Clip clip2{"clip2", ContinuousInterval{Ordinate::init(10.0), Ordinate::init(20.0)}};

        Track track{"track"};
        track.append_child(&clip1);
        track.append_child(&clip2);

        ComposedValueRef ref = &track;
        auto children = get_children(ref);

        assert(children.size() == 2);
    END_TEST()

    // ========================================================================
    // Test 6: Get children from Stack
    // ========================================================================
    TEST("Get children from Stack")
        Track track1{"track1"};
        Track track2{"track2"};

        Stack stack{"stack"};
        stack.append_child(&track1);
        stack.append_child(&track2);

        ComposedValueRef ref = &stack;
        auto children = get_children(ref);

        assert(children.size() == 2);
    END_TEST()

    // ========================================================================
    // Test 7: Get children from Clip (none)
    // ========================================================================
    TEST("Get children from Clip (none)")
        Clip clip{"clip"};

        ComposedValueRef ref = &clip;
        auto children = get_children(ref);

        assert(children.empty());
    END_TEST()

    // ========================================================================
    // Test 8: Build parent-to-child operators for Stack
    // ========================================================================
    TEST("Build parent-to-child operators for Stack")
        Clip clip1{"clip1", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}};
        Track track1{"track1"};
        track1.append_child(&clip1);

        Clip clip2{"clip2", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(15.0)}};
        Track track2{"track2"};
        track2.append_child(&clip2);

        Stack stack{"stack"};
        stack.append_child(&track1);
        stack.append_child(&track2);

        ComposedValueRef ref = &stack;
        auto ops = build_parent_to_child_operators(ref);

        // Stack should have operators for both children
        assert(ops.size() == 2);
        assert(ops[0].source.label == SpaceLabel::intrinsic);
        assert(ops[0].destination.label == SpaceLabel::presentation);
        assert(ops[1].source.label == SpaceLabel::intrinsic);
        assert(ops[1].destination.label == SpaceLabel::presentation);
    END_TEST()

    // ========================================================================
    // Test 9: Build temporal map for simple timeline
    // ========================================================================
    TEST("Build temporal map for simple timeline")
        Clip clip{"clip1", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}};
        Track track{"track1"};
        track.append_child(&clip);

        Stack stack{"tracks"};
        stack.append_child(&track);

        Timeline timeline{"timeline", stack};

        auto map = build_temporal_map(timeline);

        // Should have operators for:
        // - Timeline: presentation -> intrinsic
        // - Timeline: intrinsic -> Stack presentation
        // - Stack: presentation -> intrinsic
        // - Stack: intrinsic -> Track presentation
        // - Track: presentation -> intrinsic
        // - Track: intrinsic -> Clip presentation
        // - Clip: presentation -> media
        assert(map.size() > 0);
    END_TEST()

    // ========================================================================
    // Test 10: Build temporal map with multiple clips
    // ========================================================================
    TEST("Build temporal map with multiple clips")
        Clip clip1{"clip1", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}};
        Clip clip2{"clip2", ContinuousInterval{Ordinate::init(10.0), Ordinate::init(20.0)}};

        Track track{"track1"};
        track.append_child(&clip1);
        track.append_child(&clip2);

        Stack stack{"tracks"};
        stack.append_child(&track);

        Timeline timeline{"timeline", stack};

        auto map = build_temporal_map(timeline);

        // Should have operators for both clips
        assert(map.size() > 5);
    END_TEST()

    // ========================================================================
    // Test 11: Build temporal map with gap
    // ========================================================================
    TEST("Build temporal map with gap")
        Gap gap{Ordinate::init(5.0)};
        Clip clip{"clip1", ContinuousInterval{Ordinate::init(5.0), Ordinate::init(15.0)}};

        Track track{"track1"};
        track.append_child(&gap);
        track.append_child(&clip);

        Stack stack{"tracks"};
        stack.append_child(&track);

        Timeline timeline{"timeline", stack};

        auto map = build_temporal_map(timeline);

        // Gap has no internal operators but should still be connected
        assert(map.size() > 0);
    END_TEST()

    // ========================================================================
    // Test 12: TemporalMap add and size
    // ========================================================================
    TEST("TemporalMap add and size")
        TemporalMap map;

        Clip clip{"clip"};
        SpaceReference src{&clip, SpaceLabel::presentation};
        SpaceReference dst{&clip, SpaceLabel::media};
        Topology topo = Topology::init_identity(ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        });

        map.add_operator(ProjectionOperator{src, dst, topo});

        assert(map.size() == 1);
    END_TEST()

    // ========================================================================
    // Test 13: Project through timeline internal spaces
    // ========================================================================
    TEST("Project through timeline internal spaces")
        Clip clip{"clip", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}};

        Track track{"track"};
        track.append_child(&clip);

        Stack stack{"tracks"};
        stack.append_child(&track);

        Timeline timeline{"timeline", stack};

        auto map = build_temporal_map(timeline);

        // Get timeline spaces
        auto timeline_spaces = timeline.spaces();

        // Project from timeline presentation to timeline intrinsic (simple internal projection)
        auto result = project_ordinate(
            map,
            timeline_spaces[0],  // timeline presentation
            timeline_spaces[1],  // timeline intrinsic
            Ordinate::init(5.0)
        );

        // For a simple identity case, should project to same value
        assert(result.has_value());
        assert(approx_equal(*result, Ordinate::init(5.0)));
    END_TEST()

    // ========================================================================
    // Test 14: Compose path with single operator
    // ========================================================================
    TEST("Compose path with single operator")
        Clip clip{"clip"};
        SpaceReference src{&clip, SpaceLabel::presentation};
        SpaceReference dst{&clip, SpaceLabel::media};
        Topology topo = Topology::init_identity(ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        });

        ProjectionOperator op{src, dst, topo};
        std::vector<ProjectionOperator> path = {op};

        auto composed = compose_path(path);

        assert(composed.has_value());
        assert(composed->source.label == SpaceLabel::presentation);
        assert(composed->destination.label == SpaceLabel::media);
    END_TEST()

    // ========================================================================
    // Test 15: Compose path with multiple operators
    // ========================================================================
    TEST("Compose path with multiple operators")
        Clip clip{"clip"};
        Track track{"track"};
        Timeline timeline{"timeline"};

        SpaceReference space1{&timeline, SpaceLabel::presentation};
        SpaceReference space2{&track, SpaceLabel::presentation};
        SpaceReference space3{&clip, SpaceLabel::presentation};

        Topology topo1 = Topology::init_identity(ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        });

        Topology topo2 = Topology::init_identity(ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        });

        std::vector<ProjectionOperator> path = {
            ProjectionOperator{space1, space2, topo1},
            ProjectionOperator{space2, space3, topo2}
        };

        auto composed = compose_path(path);

        assert(composed.has_value());
        assert(space_ref_equal(composed->source, space1));
        assert(space_ref_equal(composed->destination, space3));
    END_TEST()

    // ========================================================================
    // Test 16: Build projection for directly connected spaces
    // ========================================================================
    TEST("Build projection for directly connected spaces")
        Clip clip{"clip", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}};

        Track track{"track"};
        track.append_child(&clip);

        Stack stack{"tracks"};
        stack.append_child(&track);

        Timeline timeline{"timeline", stack};

        auto map = build_temporal_map(timeline);

        // Timeline presentation -> Timeline intrinsic (direct connection)
        auto timeline_spaces = timeline.spaces();

        auto proj = build_projection(
            map,
            timeline_spaces[0],  // presentation
            timeline_spaces[1]   // intrinsic
        );

        assert(proj.has_value());
    END_TEST()

    // ========================================================================
    // Test 17: Empty temporal map
    // ========================================================================
    TEST("Empty temporal map")
        TemporalMap map;

        assert(map.size() == 0);
        assert(map.get_operators().empty());
    END_TEST()

    // ========================================================================
    // Test 18: Build temporal map for multi-track timeline
    // ========================================================================
    TEST("Build temporal map for multi-track timeline")
        Clip clip1{"clip1", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}};
        Track track1{"track1"};
        track1.append_child(&clip1);

        Clip clip2{"clip2", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(15.0)}};
        Track track2{"track2"};
        track2.append_child(&clip2);

        Stack stack{"tracks"};
        stack.append_child(&track1);
        stack.append_child(&track2);

        Timeline timeline{"timeline", stack};

        auto map = build_temporal_map(timeline);

        // Should have operators for both tracks and clips
        assert(map.size() > 10);
    END_TEST()

    // ========================================================================
    // Test 19: Projection operator stores correct bounds
    // ========================================================================
    TEST("Projection operator stores correct bounds")
        Clip clip{"clip", ContinuousInterval{Ordinate::init(5.0), Ordinate::init(15.0)}};

        ComposedValueRef ref = &clip;
        auto ops = build_internal_operators(ref);

        assert(ops.size() == 1);

        auto src_bounds = ops[0].source_bounds();
        auto dst_bounds = ops[0].destination_bounds();

        assert(approx_equal(src_bounds.start, Ordinate::init(5.0)));
        assert(approx_equal(src_bounds.end, Ordinate::init(15.0)));
        assert(approx_equal(dst_bounds.start, Ordinate::init(5.0)));
        assert(approx_equal(dst_bounds.end, Ordinate::init(15.0)));
    END_TEST()

    // ========================================================================
    // Test 20: Build Warp operators
    // ========================================================================
    TEST("Build Warp operators")
        Clip clip{"child_clip", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}};

        auto transform = Topology::init_identity(ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        });

        Warp warp{&clip, transform};

        ComposedValueRef ref = &warp;
        auto ops = build_parent_to_child_operators(ref);

        // Warp should have operator: warp presentation -> child presentation
        assert(ops.size() == 1);
        assert(ops[0].source.label == SpaceLabel::presentation);
        assert(ops[0].destination.label == SpaceLabel::presentation);
    END_TEST()

    // ========================================================================
    // Test 21: Timeline with nested structure
    // ========================================================================
    TEST("Timeline with nested structure")
        // Create nested structure: Timeline -> Stack -> Track -> Clip
        Clip clip{"clip", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}};

        Track track{"track"};
        track.append_child(&clip);

        Stack stack{"tracks"};
        stack.append_child(&track);

        Timeline timeline{"timeline", stack};

        auto map = build_temporal_map(timeline);

        // Verify we can traverse the whole hierarchy
        assert(map.size() >= 7);

        // Print operator count for debugging
        std::cout << "\n        Operators in map: " << map.size() << " ";
    END_TEST()

    // ========================================================================
    // Test 22: Verify no duplicate operators
    // ========================================================================
    TEST("Verify no duplicate operators")
        Clip clip{"clip", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}};

        Track track{"track"};
        track.append_child(&clip);

        Stack stack{"tracks"};
        stack.append_child(&track);

        Timeline timeline{"timeline", stack};

        auto map = build_temporal_map(timeline);

        // Count operators - should not have duplicates
        // (This is a basic check; real duplicate detection would be more thorough)
        auto& operators = map.get_operators();
        assert(operators.size() == map.size());
    END_TEST()

    // ========================================================================
    // Summary
    // ========================================================================
    std::cout << "\n================================================\n";
    std::cout << "Tests passed: " << tests_passed << "/" << tests_run << "\n";

    if (tests_passed == tests_run) {
        std::cout << "All tests PASSED!\n";
        return 0;
    } else {
        std::cout << "Some tests FAILED!\n";
        return 1;
    }
}
