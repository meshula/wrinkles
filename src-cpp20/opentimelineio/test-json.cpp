#include "json.hpp"
#include <iostream>
#include <cassert>
#include <cmath>

using namespace otio;
using namespace otio::json;

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
    std::cout << "Running OpenTimelineIO JSON Tests\n";
    std::cout << "===================================\n\n";

    // ========================================================================
    // Test 1: Serialize Ordinate to JSON
    // ========================================================================
    TEST("Serialize Ordinate to JSON")
        rapidjson::Document doc;
        doc.SetObject();
        auto& allocator = doc.GetAllocator();

        Ordinate ord = Ordinate::init(42.5);
        rapidjson::Value val;
        to_json(val, ord, allocator);

        assert(val.IsDouble());
        assert(approx_equal(val.GetDouble(), 42.5));
    END_TEST()

    // ========================================================================
    // Test 2: Deserialize Ordinate from JSON
    // ========================================================================
    TEST("Deserialize Ordinate from JSON")
        rapidjson::Document doc;
        doc.Parse("42.5");

        auto ord = from_json_ordinate(doc);
        assert(approx_equal(ord, Ordinate::init(42.5)));
    END_TEST()

    // ========================================================================
    // Test 3: Serialize ContinuousInterval to JSON
    // ========================================================================
    TEST("Serialize ContinuousInterval to JSON")
        rapidjson::Document doc;
        doc.SetObject();
        auto& allocator = doc.GetAllocator();

        ContinuousInterval interval{Ordinate::init(0.0), Ordinate::init(10.0)};
        rapidjson::Value val;
        to_json(val, interval, allocator);

        assert(val.IsObject());
        assert(val.HasMember("start"));
        assert(val.HasMember("end"));
        assert(approx_equal(val["start"].GetDouble(), 0.0));
        assert(approx_equal(val["end"].GetDouble(), 10.0));
    END_TEST()

    // ========================================================================
    // Test 4: Deserialize ContinuousInterval from JSON
    // ========================================================================
    TEST("Deserialize ContinuousInterval from JSON")
        rapidjson::Document doc;
        doc.Parse("{\"start\": 5.0, \"end\": 15.0}");

        auto interval = from_json_interval(doc);
        assert(approx_equal(interval.start, Ordinate::init(5.0)));
        assert(approx_equal(interval.end, Ordinate::init(15.0)));
    END_TEST()

    // ========================================================================
    // Test 5: Serialize ExternalReference to JSON
    // ========================================================================
    TEST("Serialize ExternalReference to JSON")
        rapidjson::Document doc;
        doc.SetObject();
        auto& allocator = doc.GetAllocator();

        ExternalReference ref{"file:///path/to/media.mov"};
        rapidjson::Value val;
        to_json(val, ref, allocator);

        assert(val.IsObject());
        assert(val.HasMember("OTIO_SCHEMA"));
        assert(val.HasMember("target_url"));
        assert(std::string(val["target_url"].GetString()) == "file:///path/to/media.mov");
    END_TEST()

    // ========================================================================
    // Test 6: Serialize Clip to JSON
    // ========================================================================
    TEST("Serialize Clip to JSON")
        rapidjson::Document doc;
        doc.SetObject();
        auto& allocator = doc.GetAllocator();

        Clip clip{"test_clip", ContinuousInterval{
            Ordinate::init(0.0),
            Ordinate::init(10.0)
        }};

        rapidjson::Value val;
        to_json(val, clip, allocator);

        assert(val.IsObject());
        assert(val.HasMember("OTIO_SCHEMA"));
        assert(val.HasMember("name"));
        assert(val.HasMember("source_range"));
        assert(std::string(val["name"].GetString()) == "test_clip");
    END_TEST()

    // ========================================================================
    // Test 7: Deserialize Clip from JSON
    // ========================================================================
    TEST("Deserialize Clip from JSON")
        const char* json = R"({
            "OTIO_SCHEMA": "Clip.2",
            "name": "my_clip",
            "source_range": {"start": 0.0, "end": 10.0},
            "media_reference": null
        })";

        rapidjson::Document doc;
        doc.Parse(json);

        auto clip = from_json_clip(doc);

        assert(clip->name.has_value());
        assert(*clip->name == "my_clip");
        assert(clip->bounds_s.has_value());
        assert(approx_equal(clip->bounds_s->start, Ordinate::init(0.0)));
        assert(approx_equal(clip->bounds_s->end, Ordinate::init(10.0)));
    END_TEST()

    // ========================================================================
    // Test 8: Serialize Gap to JSON
    // ========================================================================
    TEST("Serialize Gap to JSON")
        rapidjson::Document doc;
        doc.SetObject();
        auto& allocator = doc.GetAllocator();

        Gap gap{"test_gap", Ordinate::init(5.0)};

        rapidjson::Value val;
        to_json(val, gap, allocator);

        assert(val.IsObject());
        assert(val.HasMember("OTIO_SCHEMA"));
        assert(val.HasMember("name"));
        assert(val.HasMember("source_range"));
        assert(std::string(val["name"].GetString()) == "test_gap");
    END_TEST()

    // ========================================================================
    // Test 9: Deserialize Gap from JSON
    // ========================================================================
    TEST("Deserialize Gap from JSON")
        const char* json = R"({
            "OTIO_SCHEMA": "Gap.1",
            "name": "my_gap",
            "source_range": {"start": 0.0, "end": 5.0}
        })";

        rapidjson::Document doc;
        doc.Parse(json);

        auto gap = from_json_gap(doc);

        assert(gap->name.has_value());
        assert(*gap->name == "my_gap");
        assert(approx_equal(gap->duration_seconds, Ordinate::init(5.0)));
    END_TEST()

    // ========================================================================
    // Test 10: Serialize Track to JSON
    // ========================================================================
    TEST("Serialize Track to JSON")
        rapidjson::Document doc;
        doc.SetObject();
        auto& allocator = doc.GetAllocator();

        Clip clip1{"clip1", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}};
        Gap gap{Ordinate::init(5.0)};

        Track track{"my_track"};
        track.append_child(&clip1);
        track.append_child(&gap);

        rapidjson::Value val;
        to_json(val, track, allocator);

        assert(val.IsObject());
        assert(val.HasMember("OTIO_SCHEMA"));
        assert(val.HasMember("name"));
        assert(val.HasMember("children"));
        assert(val["children"].IsArray());
        assert(val["children"].Size() == 2);
    END_TEST()

    // ========================================================================
    // Test 11: Serialize Stack to JSON
    // ========================================================================
    TEST("Serialize Stack to JSON")
        rapidjson::Document doc;
        doc.SetObject();
        auto& allocator = doc.GetAllocator();

        Clip clip1{"clip1", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}};
        Track track1{"track1"};
        track1.append_child(&clip1);

        Clip clip2{"clip2", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(15.0)}};
        Track track2{"track2"};
        track2.append_child(&clip2);

        Stack stack{"my_stack"};
        stack.append_child(&track1);
        stack.append_child(&track2);

        rapidjson::Value val;
        to_json(val, stack, allocator);

        assert(val.IsObject());
        assert(val.HasMember("OTIO_SCHEMA"));
        assert(val.HasMember("name"));
        assert(val.HasMember("children"));
        assert(val["children"].IsArray());
        assert(val["children"].Size() == 2);
    END_TEST()

    // ========================================================================
    // Test 12: Serialize Timeline to JSON
    // ========================================================================
    TEST("Serialize Timeline to JSON")
        rapidjson::Document doc;
        doc.SetObject();
        auto& allocator = doc.GetAllocator();

        Clip clip{"clip1", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}};
        Track track{"track1"};
        track.append_child(&clip);

        Stack stack{"tracks"};
        stack.append_child(&track);

        Timeline timeline{"my_timeline", stack};

        rapidjson::Value val;
        to_json(val, timeline, allocator);

        assert(val.IsObject());
        assert(val.HasMember("OTIO_SCHEMA"));
        assert(val.HasMember("name"));
        assert(val.HasMember("tracks"));
        assert(std::string(val["name"].GetString()) == "my_timeline");
    END_TEST()

    // ========================================================================
    // Test 13: Timeline to JSON string
    // ========================================================================
    TEST("Timeline to JSON string")
        Clip clip{"clip1", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}};
        Track track{"track1"};
        track.append_child(&clip);

        Stack stack{"tracks"};
        stack.append_child(&track);

        Timeline timeline{"my_timeline", stack};

        std::string json_str = to_json_string(timeline);

        // Verify it's valid JSON by parsing it back
        rapidjson::Document doc;
        doc.Parse(json_str.c_str());

        assert(!doc.HasParseError());
        assert(doc.HasMember("OTIO_SCHEMA"));
        assert(doc.HasMember("name"));
    END_TEST()

    // ========================================================================
    // Test 14: Write Timeline to file
    // ========================================================================
    TEST("Write Timeline to file")
        Clip clip{"clip1", ContinuousInterval{Ordinate::init(0.0), Ordinate::init(10.0)}};
        Track track{"track1"};
        track.append_child(&clip);

        Stack stack{"tracks"};
        stack.append_child(&track);

        Timeline timeline{"test_timeline", stack};

        bool success = write_to_file(timeline, "/tmp/test_timeline.otio");
        assert(success);

        // Verify file exists and has content
        std::ifstream file("/tmp/test_timeline.otio");
        assert(file.is_open());
        std::string content((std::istreambuf_iterator<char>(file)),
                           std::istreambuf_iterator<char>());
        assert(!content.empty());
        file.close();
    END_TEST()

    // ========================================================================
    // Test 15: Round-trip: Timeline to JSON and back
    // ========================================================================
    TEST("Round-trip: Timeline to JSON and back")
        // Create a simple timeline
        Clip clip{"original_clip", ContinuousInterval{Ordinate::init(5.0), Ordinate::init(15.0)}};
        Track track{"original_track"};
        track.append_child(&clip);

        Stack stack{"tracks"};
        stack.append_child(&track);

        Timeline original{"original_timeline", stack};

        // Serialize to JSON
        std::string json_str = to_json_string(original);

        // Write to file
        write_to_file(original, "/tmp/roundtrip_test.otio");

        // Read back
        auto loaded = read_from_file("/tmp/roundtrip_test.otio");

        // Verify
        assert(loaded->name.has_value());
        assert(*loaded->name == "original_timeline");
    END_TEST()

    // ========================================================================
    // Summary
    // ========================================================================
    std::cout << "\n===================================\n";
    std::cout << "Tests passed: " << tests_passed << "/" << tests_run << "\n";

    if (tests_passed == tests_run) {
        std::cout << "All tests PASSED!\n";
        return 0;
    } else {
        std::cout << "Some tests FAILED!\n";
        return 1;
    }
}
