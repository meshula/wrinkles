#include "schema.hpp"
#include <iostream>
#include <cassert>
#include <cmath>

using namespace otio;

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

// Helper to compare intervals
bool approx_equal(ContinuousInterval const& a, ContinuousInterval const& b) {
    return approx_equal(a.start, b.start) && approx_equal(a.end, b.end);
}

int main() {
    std::cout << "Running OpenTimelineIO Schema Tests\n";
    std::cout << "====================================\n\n";

    // ========================================================================
    // Test 1: ExternalReference construction
    // ========================================================================
    TEST("ExternalReference construction")
        ExternalReference ref{"file:///path/to/media.mov"};
        assert(ref.target_uri == "file:///path/to/media.mov");
    END_TEST()

    // ========================================================================
    // Test 2: MediaReference with external reference
    // ========================================================================
    TEST("MediaReference with external reference")
        MediaReference media;
        media.ref = ExternalReference{"file:///test.mov"};
        media.bounds_s = ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        };

        assert(media.bounds_s.has_value());
        assert(approx_equal(media.bounds_s->start, Ordinate::init(0.0)));
        assert(approx_equal(media.bounds_s->end, Ordinate::init(10.0)));
        assert(!media.interpolating);
    END_TEST()

    // ========================================================================
    // Test 3: Gap construction and duration
    // ========================================================================
    TEST("Gap construction and duration")
        Gap gap{Ordinate::init(5.0)};

        auto bounds = gap.bounds_of(SpaceLabel::presentation);
        assert(approx_equal(bounds.start, Ordinate::ZERO()));
        assert(approx_equal(bounds.end, Ordinate::init(5.0)));
        assert(approx_equal(bounds.duration(), Ordinate::init(5.0)));
    END_TEST()

    // ========================================================================
    // Test 4: Gap with name
    // ========================================================================
    TEST("Gap with name")
        Gap gap{"my_gap", Ordinate::init(3.0)};

        assert(gap.name.has_value());
        assert(*gap.name == "my_gap");
        assert(approx_equal(gap.duration_seconds, Ordinate::init(3.0)));
    END_TEST()

    // ========================================================================
    // Test 5: Gap topology is identity
    // ========================================================================
    TEST("Gap topology is identity")
        Gap gap{Ordinate::init(10.0)};
        auto topo = gap.topology();

        // Project through identity
        auto result = topo.project_instantaneous_cc(Ordinate::init(5.0));
        assert(!result.is_out_of_bounds());
        assert(approx_equal(result.ordinate(), Ordinate::init(5.0)));
    END_TEST()

    // ========================================================================
    // Test 6: Gap spaces
    // ========================================================================
    TEST("Gap spaces")
        Gap gap{Ordinate::init(1.0)};
        auto spaces = gap.spaces();

        assert(spaces.size() == 1);
        assert(spaces[0].label == SpaceLabel::presentation);
    END_TEST()

    // ========================================================================
    // Test 7: Clip construction
    // ========================================================================
    TEST("Clip construction")
        Clip clip{"my_clip"};

        assert(clip.name.has_value());
        assert(*clip.name == "my_clip");
        assert(!clip.bounds_s.has_value());
    END_TEST()

    // ========================================================================
    // Test 8: Clip with bounds
    // ========================================================================
    TEST("Clip with bounds")
        auto bounds = ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        };
        Clip clip{"clip_with_bounds", bounds};

        assert(clip.name.has_value());
        assert(clip.bounds_s.has_value());
        assert(approx_equal(*clip.bounds_s, bounds));
    END_TEST()

    // ========================================================================
    // Test 9: Clip topology
    // ========================================================================
    TEST("Clip topology")
        auto bounds = ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(20.0)
        };
        Clip clip{"test_clip", bounds};

        auto topo = clip.topology();
        auto result = topo.project_instantaneous_cc(Ordinate::init(10.0));

        assert(!result.is_out_of_bounds());
        assert(approx_equal(result.ordinate(), Ordinate::init(10.0)));
    END_TEST()

    // ========================================================================
    // Test 10: Clip bounds_of presentation space
    // ========================================================================
    TEST("Clip bounds_of presentation space")
        auto bounds = ContinuousInterval{
            Ordinate::init(5.0),
            Ordinate::init(15.0)
        };
        Clip clip{"test", bounds};

        auto presentation_bounds = clip.bounds_of(SpaceLabel::presentation);
        assert(approx_equal(presentation_bounds, bounds));
    END_TEST()

    // ========================================================================
    // Test 11: Clip bounds_of media space
    // ========================================================================
    TEST("Clip bounds_of media space")
        auto bounds = ContinuousInterval{
            Ordinate::init(5.0),
            Ordinate::init(15.0)
        };
        Clip clip{"test", bounds};

        auto media_bounds = clip.bounds_of(SpaceLabel::media);
        assert(approx_equal(media_bounds, bounds));
    END_TEST()

    // ========================================================================
    // Test 12: Clip spaces
    // ========================================================================
    TEST("Clip spaces")
        Clip clip{"test"};
        auto spaces = clip.spaces();

        assert(spaces.size() == 2);
        assert(spaces[0].label == SpaceLabel::presentation);
        assert(spaces[1].label == SpaceLabel::media);
    END_TEST()

    // ========================================================================
    // Test 13: Track construction
    // ========================================================================
    TEST("Track construction")
        Track track{"my_track"};

        assert(track.name.has_value());
        assert(*track.name == "my_track");
        assert(track.children.empty());
    END_TEST()

    // ========================================================================
    // Test 14: Track with single clip
    // ========================================================================
    TEST("Track with single clip")
        Clip clip1{"clip1", ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        }};

        Track track{"track1"};
        track.append_child(&clip1);

        assert(track.children.size() == 1);

        auto bounds = track.bounds_of(SpaceLabel::presentation);
        assert(approx_equal(bounds.start, Ordinate::init(0.0)));
        assert(approx_equal(bounds.end, Ordinate::init(10.0)));
    END_TEST()

    // ========================================================================
    // Test 15: Track with multiple clips (sequential)
    // ========================================================================
    TEST("Track with multiple clips (sequential)")
        Clip clip1{"clip1", ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        }};

        Clip clip2{"clip2", ContinuousInterval{
            Ordinate::init(10.0),
            Ordinate::init(20.0)
        }};

        Track track{"track1"};
        track.append_child(&clip1);
        track.append_child(&clip2);

        assert(track.children.size() == 2);

        auto bounds = track.bounds_of(SpaceLabel::presentation);
        assert(approx_equal(bounds.start, Ordinate::init(0.0)));
        assert(approx_equal(bounds.end, Ordinate::init(20.0)));
    END_TEST()

    // ========================================================================
    // Test 16: Track with gap
    // ========================================================================
    TEST("Track with gap")
        Gap gap{Ordinate::init(5.0)};

        Clip clip{"clip1", ContinuousInterval{
            Ordinate::init(5.0),
            Ordinate::init(15.0)
        }};

        Track track{"track_with_gap"};
        track.append_child(&gap);
        track.append_child(&clip);

        assert(track.children.size() == 2);

        auto bounds = track.bounds_of(SpaceLabel::presentation);
        assert(approx_equal(bounds.start, Ordinate::init(0.0)));
        assert(approx_equal(bounds.end, Ordinate::init(15.0)));
    END_TEST()

    // ========================================================================
    // Test 17: Track topology
    // ========================================================================
    TEST("Track topology")
        Clip clip1{"clip1", ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        }};

        Track track{"track1"};
        track.append_child(&clip1);

        auto topo = track.topology();
        auto result = topo.project_instantaneous_cc(Ordinate::init(5.0));

        assert(!result.is_out_of_bounds());
        assert(approx_equal(result.ordinate(), Ordinate::init(5.0)));
    END_TEST()

    // ========================================================================
    // Test 18: Track spaces
    // ========================================================================
    TEST("Track spaces")
        Track track{"test"};
        auto spaces = track.spaces();

        assert(spaces.size() == 2);
        assert(spaces[0].label == SpaceLabel::presentation);
        assert(spaces[1].label == SpaceLabel::intrinsic);
    END_TEST()

    // ========================================================================
    // Test 19: Stack construction
    // ========================================================================
    TEST("Stack construction")
        Stack stack{"my_stack"};

        assert(stack.name.has_value());
        assert(*stack.name == "my_stack");
        assert(stack.children.empty());
    END_TEST()

    // ========================================================================
    // Test 20: Stack with single track
    // ========================================================================
    TEST("Stack with single track")
        Clip clip{"clip1", ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        }};

        Track track{"track1"};
        track.append_child(&clip);

        Stack stack{"stack1"};
        stack.append_child(&track);

        assert(stack.children.size() == 1);

        auto bounds = stack.bounds_of(SpaceLabel::presentation);
        assert(approx_equal(bounds.start, Ordinate::init(0.0)));
        assert(approx_equal(bounds.end, Ordinate::init(10.0)));
    END_TEST()

    // ========================================================================
    // Test 21: Stack with multiple tracks (parallel)
    // ========================================================================
    TEST("Stack with multiple tracks (parallel)")
        Clip clip1{"clip1", ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        }};

        Clip clip2{"clip2", ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(15.0)
        }};

        Track track1{"track1"};
        track1.append_child(&clip1);

        Track track2{"track2"};
        track2.append_child(&clip2);

        Stack stack{"stack1"};
        stack.append_child(&track1);
        stack.append_child(&track2);

        assert(stack.children.size() == 2);

        // Stack extends to cover both tracks
        auto bounds = stack.bounds_of(SpaceLabel::presentation);
        assert(approx_equal(bounds.start, Ordinate::init(0.0)));
        assert(approx_equal(bounds.end, Ordinate::init(15.0)));
    END_TEST()

    // ========================================================================
    // Test 22: Stack topology
    // ========================================================================
    TEST("Stack topology")
        Clip clip{"clip1", ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        }};

        Track track{"track1"};
        track.append_child(&clip);

        Stack stack{"stack1"};
        stack.append_child(&track);

        auto topo = stack.topology();
        auto result = topo.project_instantaneous_cc(Ordinate::init(5.0));

        assert(!result.is_out_of_bounds());
        assert(approx_equal(result.ordinate(), Ordinate::init(5.0)));
    END_TEST()

    // ========================================================================
    // Test 23: Stack spaces
    // ========================================================================
    TEST("Stack spaces")
        Stack stack{"test"};
        auto spaces = stack.spaces();

        assert(spaces.size() == 2);
        assert(spaces[0].label == SpaceLabel::presentation);
        assert(spaces[1].label == SpaceLabel::intrinsic);
    END_TEST()

    // ========================================================================
    // Test 24: Timeline construction
    // ========================================================================
    TEST("Timeline construction")
        Timeline timeline{"my_timeline"};

        assert(timeline.name.has_value());
        assert(*timeline.name == "my_timeline");
    END_TEST()

    // ========================================================================
    // Test 25: Timeline with tracks
    // ========================================================================
    TEST("Timeline with tracks")
        Clip clip{"clip1", ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        }};

        Track track{"track1"};
        track.append_child(&clip);

        Stack stack{"tracks"};
        stack.append_child(&track);

        Timeline timeline{"timeline1", stack};

        auto bounds = timeline.bounds_of(SpaceLabel::presentation);
        assert(approx_equal(bounds.start, Ordinate::init(0.0)));
        assert(approx_equal(bounds.end, Ordinate::init(10.0)));
    END_TEST()

    // ========================================================================
    // Test 26: Timeline topology
    // ========================================================================
    TEST("Timeline topology")
        Clip clip{"clip1", ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        }};

        Track track{"track1"};
        track.append_child(&clip);

        Stack stack{"tracks"};
        stack.append_child(&track);

        Timeline timeline{"timeline1", stack};

        auto topo = timeline.topology();
        auto result = topo.project_instantaneous_cc(Ordinate::init(5.0));

        assert(!result.is_out_of_bounds());
        assert(approx_equal(result.ordinate(), Ordinate::init(5.0)));
    END_TEST()

    // ========================================================================
    // Test 27: Timeline spaces
    // ========================================================================
    TEST("Timeline spaces")
        Timeline timeline{"test"};
        auto spaces = timeline.spaces();

        assert(spaces.size() == 2);
        assert(spaces[0].label == SpaceLabel::presentation);
        assert(spaces[1].label == SpaceLabel::intrinsic);
    END_TEST()

    // ========================================================================
    // Test 28: ComposedValueRef with Clip
    // ========================================================================
    TEST("ComposedValueRef with Clip")
        Clip clip{"test_clip", ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        }};

        ComposedValueRef ref = &clip;

        auto name = detail::get_name(ref);
        assert(name.has_value());
        assert(*name == "test_clip");
    END_TEST()

    // ========================================================================
    // Test 29: ComposedValueRef with Gap
    // ========================================================================
    TEST("ComposedValueRef with Gap")
        Gap gap{"test_gap", Ordinate::init(5.0)};

        ComposedValueRef ref = &gap;

        auto name = detail::get_name(ref);
        assert(name.has_value());
        assert(*name == "test_gap");
    END_TEST()

    // ========================================================================
    // Test 30: detail::get_topology with Clip
    // ========================================================================
    TEST("detail::get_topology with Clip")
        Clip clip{"test", ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        }};

        ComposedValueRef ref = &clip;
        auto topo = detail::get_topology(ref);

        auto result = topo.project_instantaneous_cc(Ordinate::init(5.0));
        assert(!result.is_out_of_bounds());
        assert(approx_equal(result.ordinate(), Ordinate::init(5.0)));
    END_TEST()

    // ========================================================================
    // Test 31: detail::get_bounds_of with Clip
    // ========================================================================
    TEST("detail::get_bounds_of with Clip")
        auto bounds = ContinuousInterval{
            Ordinate::init(5.0),
            Ordinate::init(15.0)
        };
        Clip clip{"test", bounds};

        ComposedValueRef ref = &clip;
        auto result_bounds = detail::get_bounds_of(ref, SpaceLabel::presentation);

        assert(approx_equal(result_bounds, bounds));
    END_TEST()

    // ========================================================================
    // Test 32: detail::get_spaces with Track
    // ========================================================================
    TEST("detail::get_spaces with Track")
        Track track{"test"};

        ComposedValueRef ref = &track;
        auto spaces = detail::get_spaces(ref);

        assert(spaces.size() == 2);
        assert(spaces[0].label == SpaceLabel::presentation);
        assert(spaces[1].label == SpaceLabel::intrinsic);
    END_TEST()

    // ========================================================================
    // Test 33: Warp construction
    // ========================================================================
    TEST("Warp construction")
        Clip clip{"child_clip", ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        }};

        auto transform = Topology::init_identity(ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        });

        Warp warp{&clip, transform};

        assert(!warp.interpolating);
        assert(!warp.name.has_value());
    END_TEST()

    // ========================================================================
    // Test 34: Warp topology
    // ========================================================================
    TEST("Warp topology")
        Clip clip{"child_clip", ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        }};

        auto transform = Topology::init_identity(ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        });

        Warp warp{&clip, transform};

        auto topo = warp.topology();
        auto result = topo.project_instantaneous_cc(Ordinate::init(5.0));

        assert(!result.is_out_of_bounds());
        assert(approx_equal(result.ordinate(), Ordinate::init(5.0)));
    END_TEST()

    // ========================================================================
    // Test 35: Warp spaces
    // ========================================================================
    TEST("Warp spaces")
        Clip clip{"child_clip", ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        }};

        auto transform = Topology::init_identity(ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        });

        Warp warp{&clip, transform};
        auto spaces = warp.spaces();

        assert(spaces.size() == 1);
        assert(spaces[0].label == SpaceLabel::presentation);
    END_TEST()

    // ========================================================================
    // Summary
    // ========================================================================
    std::cout << "\n====================================\n";
    std::cout << "Tests passed: " << tests_passed << "/" << tests_run << "\n";

    if (tests_passed == tests_run) {
        std::cout << "All tests PASSED!\n";
        return 0;
    } else {
        std::cout << "Some tests FAILED!\n";
        return 1;
    }
}
