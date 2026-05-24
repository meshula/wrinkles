#pragma once
#include "schema.hpp"
#include "rapidjson/document.h"
#include "rapidjson/writer.h"
#include "rapidjson/stringbuffer.h"
#include "rapidjson/filereadstream.h"
#include "rapidjson/filewritestream.h"
#include "rapidjson/prettywriter.h"
#include <fstream>
#include <memory>
#include <cstdio>

// OpenTimelineIO JSON Serialization/Deserialization
//
// Provides functions to convert OTIO schema types to/from JSON using RapidJSON.
// Supports reading and writing OTIO files.

namespace otio {
namespace json {

// ============================================================================
// JSON Serialization (to_json)
// ============================================================================

/// Serialize an Ordinate to JSON
inline void to_json(rapidjson::Value& j, Ordinate const& ord, rapidjson::Document::AllocatorType& allocator) {
    j.SetDouble(ord.v);
}

/// Serialize a ContinuousInterval to JSON object
inline void to_json(rapidjson::Value& j, ContinuousInterval const& interval, rapidjson::Document::AllocatorType& allocator) {
    j.SetObject();
    rapidjson::Value start_val;
    to_json(start_val, interval.start, allocator);
    j.AddMember("start", start_val, allocator);

    rapidjson::Value end_val;
    to_json(end_val, interval.end, allocator);
    j.AddMember("end", end_val, allocator);
}

/// Serialize ExternalReference to JSON
inline void to_json(rapidjson::Value& j, ExternalReference const& ref, rapidjson::Document::AllocatorType& allocator) {
    j.SetObject();
    j.AddMember("OTIO_SCHEMA", "ExternalReference.1", allocator);
    rapidjson::Value uri(ref.target_uri.c_str(), allocator);
    j.AddMember("target_url", uri, allocator);
}

/// Serialize MediaReference to JSON
inline void to_json(rapidjson::Value& j, MediaReference const& media, rapidjson::Document::AllocatorType& allocator) {
    j.SetObject();

    // Serialize the media data reference
    std::visit([&](auto const& ref_data) {
        using T = std::decay_t<decltype(ref_data)>;
        if constexpr (std::is_same_v<T, ExternalReference>) {
            rapidjson::Value ref_val;
            to_json(ref_val, ref_data, allocator);
            j.AddMember("media_reference", ref_val, allocator);
        } else if constexpr (std::is_same_v<T, EmptyReference>) {
            j.AddMember("media_reference", rapidjson::Value().SetNull(), allocator);
        }
        // SignalReference not yet implemented
    }, media.ref);

    // Serialize bounds if present
    if (media.bounds_s.has_value()) {
        rapidjson::Value bounds_val;
        to_json(bounds_val, *media.bounds_s, allocator);
        j.AddMember("available_range", bounds_val, allocator);
    }
}

/// Serialize Clip to JSON
inline void to_json(rapidjson::Value& j, Clip const& clip, rapidjson::Document::AllocatorType& allocator) {
    j.SetObject();
    j.AddMember("OTIO_SCHEMA", "Clip.2", allocator);

    // Name
    if (clip.name.has_value()) {
        rapidjson::Value name_val(clip.name->c_str(), allocator);
        j.AddMember("name", name_val, allocator);
    } else {
        j.AddMember("name", rapidjson::Value().SetNull(), allocator);
    }

    // Source range (bounds_s)
    if (clip.bounds_s.has_value()) {
        rapidjson::Value range_val;
        to_json(range_val, *clip.bounds_s, allocator);
        j.AddMember("source_range", range_val, allocator);
    } else {
        j.AddMember("source_range", rapidjson::Value().SetNull(), allocator);
    }

    // Media reference
    rapidjson::Value media_val;
    to_json(media_val, clip.media, allocator);
    j.AddMember("media_reference", media_val, allocator);
}

/// Serialize Gap to JSON
inline void to_json(rapidjson::Value& j, Gap const& gap, rapidjson::Document::AllocatorType& allocator) {
    j.SetObject();
    j.AddMember("OTIO_SCHEMA", "Gap.1", allocator);

    // Name
    if (gap.name.has_value()) {
        rapidjson::Value name_val(gap.name->c_str(), allocator);
        j.AddMember("name", name_val, allocator);
    } else {
        j.AddMember("name", rapidjson::Value().SetNull(), allocator);
    }

    // Duration as source_range
    ContinuousInterval range{Ordinate::ZERO(), gap.duration_seconds};
    rapidjson::Value range_val;
    to_json(range_val, range, allocator);
    j.AddMember("source_range", range_val, allocator);
}

/// Serialize Track to JSON
inline void to_json(rapidjson::Value& j, Track const& track, rapidjson::Document::AllocatorType& allocator);

/// Serialize Stack to JSON
inline void to_json(rapidjson::Value& j, Stack const& stack, rapidjson::Document::AllocatorType& allocator);

/// Serialize ComposedValueRef to JSON
inline void to_json(rapidjson::Value& j, ComposedValueRef const& ref, rapidjson::Document::AllocatorType& allocator) {
    std::visit([&](auto const* ptr) {
        using T = std::decay_t<decltype(*ptr)>;
        if constexpr (std::is_same_v<T, Clip>) {
            to_json(j, *ptr, allocator);
        } else if constexpr (std::is_same_v<T, Gap>) {
            to_json(j, *ptr, allocator);
        } else if constexpr (std::is_same_v<T, Track>) {
            to_json(j, *ptr, allocator);
        } else if constexpr (std::is_same_v<T, Stack>) {
            to_json(j, *ptr, allocator);
        }
        // Warp and Timeline handled separately as needed
    }, ref);
}

/// Serialize Track to JSON (implementation)
inline void to_json(rapidjson::Value& j, Track const& track, rapidjson::Document::AllocatorType& allocator) {
    j.SetObject();
    j.AddMember("OTIO_SCHEMA", "Track.1", allocator);

    // Name
    if (track.name.has_value()) {
        rapidjson::Value name_val(track.name->c_str(), allocator);
        j.AddMember("name", name_val, allocator);
    } else {
        j.AddMember("name", rapidjson::Value().SetNull(), allocator);
    }

    // Children
    rapidjson::Value children_array(rapidjson::kArrayType);
    for (auto const& child : track.children) {
        rapidjson::Value child_val;
        to_json(child_val, child, allocator);
        children_array.PushBack(child_val, allocator);
    }
    j.AddMember("children", children_array, allocator);
}

/// Serialize Stack to JSON (implementation)
inline void to_json(rapidjson::Value& j, Stack const& stack, rapidjson::Document::AllocatorType& allocator) {
    j.SetObject();
    j.AddMember("OTIO_SCHEMA", "Stack.1", allocator);

    // Name
    if (stack.name.has_value()) {
        rapidjson::Value name_val(stack.name->c_str(), allocator);
        j.AddMember("name", name_val, allocator);
    } else {
        j.AddMember("name", rapidjson::Value().SetNull(), allocator);
    }

    // Children
    rapidjson::Value children_array(rapidjson::kArrayType);
    for (auto const& child : stack.children) {
        rapidjson::Value child_val;
        to_json(child_val, child, allocator);
        children_array.PushBack(child_val, allocator);
    }
    j.AddMember("children", children_array, allocator);
}

/// Serialize Timeline to JSON
inline void to_json(rapidjson::Value& j, Timeline const& timeline, rapidjson::Document::AllocatorType& allocator) {
    j.SetObject();
    j.AddMember("OTIO_SCHEMA", "Timeline.1", allocator);

    // Name
    if (timeline.name.has_value()) {
        rapidjson::Value name_val(timeline.name->c_str(), allocator);
        j.AddMember("name", name_val, allocator);
    } else {
        j.AddMember("name", rapidjson::Value().SetNull(), allocator);
    }

    // Tracks (serialized as Stack)
    rapidjson::Value tracks_val;
    to_json(tracks_val, timeline.tracks, allocator);
    j.AddMember("tracks", tracks_val, allocator);
}

// ============================================================================
// JSON Deserialization (from_json)
// ============================================================================

/// Deserialize an Ordinate from JSON
inline Ordinate from_json_ordinate(rapidjson::Value const& j) {
    if (j.IsDouble()) {
        return Ordinate::init(j.GetDouble());
    } else if (j.IsInt()) {
        return Ordinate::init(static_cast<double>(j.GetInt()));
    }
    throw std::runtime_error("Expected number for Ordinate");
}

/// Deserialize a ContinuousInterval from JSON
inline ContinuousInterval from_json_interval(rapidjson::Value const& j) {
    if (!j.IsObject()) {
        throw std::runtime_error("Expected object for ContinuousInterval");
    }

    auto start = from_json_ordinate(j["start"]);
    auto end = from_json_ordinate(j["end"]);

    return ContinuousInterval{start, end};
}

/// Deserialize ExternalReference from JSON
inline ExternalReference from_json_external_reference(rapidjson::Value const& j) {
    if (!j.IsObject()) {
        throw std::runtime_error("Expected object for ExternalReference");
    }

    std::string uri;
    if (j.HasMember("target_url") && j["target_url"].IsString()) {
        uri = j["target_url"].GetString();
    }

    return ExternalReference{uri};
}

/// Deserialize MediaReference from JSON
inline MediaReference from_json_media_reference(rapidjson::Value const& j) {
    MediaReference media;

    if (!j.IsObject()) {
        return media;
    }

    // Media reference data
    if (j.HasMember("media_reference")) {
        auto const& ref_val = j["media_reference"];
        if (!ref_val.IsNull() && ref_val.IsObject()) {
            if (ref_val.HasMember("OTIO_SCHEMA")) {
                std::string schema = ref_val["OTIO_SCHEMA"].GetString();
                if (schema.find("ExternalReference") != std::string::npos) {
                    media.ref = from_json_external_reference(ref_val);
                }
            }
        }
    }

    // Available range (bounds_s)
    if (j.HasMember("available_range") && !j["available_range"].IsNull()) {
        media.bounds_s = from_json_interval(j["available_range"]);
    }

    return media;
}

/// Forward declarations for recursive types
inline std::unique_ptr<Clip> from_json_clip(rapidjson::Value const& j);
inline std::unique_ptr<Gap> from_json_gap(rapidjson::Value const& j);
inline std::unique_ptr<Track> from_json_track(rapidjson::Value const& j);
inline std::unique_ptr<Stack> from_json_stack(rapidjson::Value const& j);

/// Deserialize ComposedValueRef from JSON (returns unique_ptr to manage lifetime)
inline ComposedValueRef from_json_composed(rapidjson::Value const& j,
                                           std::vector<std::unique_ptr<Clip>>& clips,
                                           std::vector<std::unique_ptr<Gap>>& gaps,
                                           std::vector<std::unique_ptr<Track>>& tracks,
                                           std::vector<std::unique_ptr<Stack>>& stacks) {
    if (!j.IsObject() || !j.HasMember("OTIO_SCHEMA")) {
        throw std::runtime_error("Expected object with OTIO_SCHEMA");
    }

    std::string schema = j["OTIO_SCHEMA"].GetString();

    if (schema.find("Clip") != std::string::npos) {
        clips.push_back(from_json_clip(j));
        return clips.back().get();
    } else if (schema.find("Gap") != std::string::npos) {
        gaps.push_back(from_json_gap(j));
        return gaps.back().get();
    } else if (schema.find("Track") != std::string::npos) {
        tracks.push_back(from_json_track(j));
        return tracks.back().get();
    } else if (schema.find("Stack") != std::string::npos) {
        stacks.push_back(from_json_stack(j));
        return stacks.back().get();
    }

    throw std::runtime_error("Unknown OTIO_SCHEMA: " + schema);
}

/// Deserialize Clip from JSON
inline std::unique_ptr<Clip> from_json_clip(rapidjson::Value const& j) {
    auto clip = std::make_unique<Clip>();

    // Name
    if (j.HasMember("name") && !j["name"].IsNull() && j["name"].IsString()) {
        clip->name = j["name"].GetString();
    }

    // Source range (bounds_s)
    if (j.HasMember("source_range") && !j["source_range"].IsNull()) {
        clip->bounds_s = from_json_interval(j["source_range"]);
    }

    // Media reference
    if (j.HasMember("media_reference") && !j["media_reference"].IsNull()) {
        clip->media = from_json_media_reference(j["media_reference"]);
    }

    return clip;
}

/// Deserialize Gap from JSON
inline std::unique_ptr<Gap> from_json_gap(rapidjson::Value const& j) {
    auto gap = std::make_unique<Gap>();

    // Name
    if (j.HasMember("name") && !j["name"].IsNull() && j["name"].IsString()) {
        gap->name = j["name"].GetString();
    }

    // Source range gives us the duration
    if (j.HasMember("source_range") && !j["source_range"].IsNull()) {
        auto range = from_json_interval(j["source_range"]);
        gap->duration_seconds = range.duration();
    }

    return gap;
}

/// Deserialize Track from JSON
inline std::unique_ptr<Track> from_json_track(rapidjson::Value const& j) {
    auto track = std::make_unique<Track>();

    // Name
    if (j.HasMember("name") && !j["name"].IsNull() && j["name"].IsString()) {
        track->name = j["name"].GetString();
    }

    // Note: Children will be populated by the caller to manage lifetime properly

    return track;
}

/// Deserialize Stack from JSON
inline std::unique_ptr<Stack> from_json_stack(rapidjson::Value const& j) {
    auto stack = std::make_unique<Stack>();

    // Name
    if (j.HasMember("name") && !j["name"].IsNull() && j["name"].IsString()) {
        stack->name = j["name"].GetString();
    }

    // Note: Children will be populated by the caller to manage lifetime properly

    return stack;
}

/// Deserialize Timeline from JSON
inline std::unique_ptr<Timeline> from_json_timeline(rapidjson::Value const& j) {
    auto timeline = std::make_unique<Timeline>();

    // Name
    if (j.HasMember("name") && !j["name"].IsNull() && j["name"].IsString()) {
        timeline->name = j["name"].GetString();
    }

    // Tracks (deserialized as Stack) will be populated by caller

    return timeline;
}

// ============================================================================
// File I/O
// ============================================================================

/// Write Timeline to JSON string
inline std::string to_json_string(Timeline const& timeline, bool pretty = true) {
    rapidjson::Document doc;
    doc.SetObject();
    auto& allocator = doc.GetAllocator();

    to_json(doc, timeline, allocator);

    rapidjson::StringBuffer buffer;
    if (pretty) {
        rapidjson::PrettyWriter<rapidjson::StringBuffer> writer(buffer);
        doc.Accept(writer);
    } else {
        rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
        doc.Accept(writer);
    }

    return std::string(buffer.GetString());
}

/// Write Timeline to JSON file
inline bool write_to_file(Timeline const& timeline, std::string const& filename) {
    std::string json_str = to_json_string(timeline, true);

    std::ofstream file(filename);
    if (!file.is_open()) {
        return false;
    }

    file << json_str;
    file.close();

    return true;
}

/// Read Timeline from JSON string
inline std::unique_ptr<Timeline> from_json_string(std::string const& json_str) {
    rapidjson::Document doc;
    doc.Parse(json_str.c_str());

    if (doc.HasParseError()) {
        throw std::runtime_error("JSON parse error");
    }

    // Storage for objects to manage lifetime
    std::vector<std::unique_ptr<Clip>> clips;
    std::vector<std::unique_ptr<Gap>> gaps;
    std::vector<std::unique_ptr<Track>> tracks;
    std::vector<std::unique_ptr<Stack>> stacks;

    auto timeline = from_json_timeline(doc);

    // Parse tracks if present
    if (doc.HasMember("tracks") && !doc["tracks"].IsNull()) {
        auto const& tracks_json = doc["tracks"];

        if (tracks_json.HasMember("children") && tracks_json["children"].IsArray()) {
            auto const& children_array = tracks_json["children"];

            for (rapidjson::SizeType i = 0; i < children_array.Size(); i++) {
                auto child_ref = from_json_composed(children_array[i], clips, gaps, tracks, stacks);

                // Handle Track children recursively
                if (auto* track_ptr = std::get_if<Track*>(&child_ref)) {
                    Track* track = *track_ptr;
                    auto const& track_json = children_array[i];

                    if (track_json.HasMember("children") && track_json["children"].IsArray()) {
                        auto const& track_children = track_json["children"];
                        for (rapidjson::SizeType j = 0; j < track_children.Size(); j++) {
                            auto track_child = from_json_composed(track_children[j], clips, gaps, tracks, stacks);
                            track->append_child(track_child);
                        }
                    }
                }

                timeline->tracks.append_child(child_ref);
            }
        }
    }

    // Keep objects alive by moving them into the Timeline (need to extend Timeline to own objects)
    // For now, this is a limitation - objects must outlive the Timeline

    return timeline;
}

/// Read Timeline from JSON file
inline std::unique_ptr<Timeline> read_from_file(std::string const& filename) {
    std::ifstream file(filename);
    if (!file.is_open()) {
        throw std::runtime_error("Could not open file: " + filename);
    }

    std::string json_str((std::istreambuf_iterator<char>(file)),
                         std::istreambuf_iterator<char>());
    file.close();

    return from_json_string(json_str);
}

} // namespace json
} // namespace otio
