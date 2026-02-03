// otio_hierarchy_view.cpp - C++ Implementation
//
// Display an ASCII diagram of the hierarchy of an OpenTimelineIO file.

#include <iostream>
#include <string>
#include <vector>
#include <iomanip>
#include <sstream>
#include "opentimelineio.hpp"

// Tree drawing characters
struct TreeChars {
    const char* branch;
    const char* last;
    const char* vertical;
    const char* space;
    const char* header_line;

    static TreeChars unicode() {
        return {
            "\xe2\x94\x9c\xe2\x94\x80\xe2\x94\x80 ",  // ├──
            "\xe2\x94\x94\xe2\x94\x80\xe2\x94\x80 ",  // └──
            "\xe2\x94\x82   ",                        // │
            "    ",
            "\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90"  // ═══...
        };
    }

    static TreeChars ascii() {
        return {
            "+-- ",
            "+-- ",
            "|   ",
            "    ",
            "==================================================="
        };
    }
};

// Format bounds with optional discrete info
std::string format_bounds(const std::optional<otio::ContinuousInterval>& bounds,
                          const std::optional<otio::SampleIndexGenerator>& discrete) {
    if (!bounds) return "";

    std::ostringstream ss;
    ss << std::fixed << std::setprecision(2);
    ss << " [" << bounds->start.as_float() << "s - "
       << bounds->end.as_float() << "s]";

    if (discrete) {
        size_t start_idx = discrete->index_at(bounds->start);
        size_t end_idx = discrete->index_at(bounds->end);
        ss << " (" << start_idx << " - " << end_idx << " @ "
           << discrete->sample_rate_hz << ")";
    }

    return ss.str();
}

// Recursive hierarchy renderer
void render_item(const otio::ComposableRef& item,
                 const std::string& prefix,
                 bool is_last,
                 const TreeChars& chars,
                 bool show_metadata) {
    const char* connector = is_last ? chars.last : chars.branch;
    std::string child_prefix = prefix + (is_last ? chars.space : chars.vertical);

    std::string name = item.name().value_or("(unnamed)");

    switch (item.type()) {
        case otio::ComposableType::Timeline: {
            std::cout << prefix << connector << "Timeline: " << name << "\n";
            size_t count = item.child_count();
            for (size_t i = 0; i < count; ++i) {
                render_item(item.child_at(i), child_prefix,
                           i == count - 1, chars, show_metadata);
            }
            break;
        }

        case otio::ComposableType::Stack: {
            std::cout << prefix << connector << "Stack: " << name << "\n";
            size_t count = item.child_count();
            for (size_t i = 0; i < count; ++i) {
                render_item(item.child_at(i), child_prefix,
                           i == count - 1, chars, show_metadata);
            }
            break;
        }

        case otio::ComposableType::Track: {
            auto* track = item.as_track();
            auto bounds_str = format_bounds(track->bounds(), std::nullopt);
            std::cout << prefix << connector << "Track: " << name
                      << bounds_str << " (" << item.child_count() << " children)\n";

            size_t count = item.child_count();
            for (size_t i = 0; i < count; ++i) {
                render_item(item.child_at(i), child_prefix,
                           i == count - 1, chars, show_metadata);
            }
            break;
        }

        case otio::ComposableType::Clip: {
            auto* clip = item.as_clip();
            auto bounds_str = format_bounds(clip->bounds(),
                                           clip->discrete_partition());
            std::cout << prefix << connector << "Clip: " << name
                      << bounds_str << "\n";

            // Show media reference
            const auto media = clip->media();
            std::cout << child_prefix << "    media: ";
            if (media.is_uri()) {
                std::cout << media.target_uri;
            } else if (media.is_signal()) {
                std::cout << "(signal)";
            } else {
                std::cout << "(no media)";
            }
            std::cout << "\n";
            break;
        }

        case otio::ComposableType::Gap: {
            auto* gap = item.as_gap();
            auto bounds_str = format_bounds(gap->bounds(), std::nullopt);
            std::cout << prefix << connector << "Gap: " << name
                      << bounds_str << "\n";
            break;
        }

        case otio::ComposableType::Warp: {
            std::cout << prefix << connector << "Warp: " << name << "\n";
            auto* warp = item.as_warp();
            render_item(warp->child(), child_prefix, true, chars, show_metadata);
            break;
        }

        case otio::ComposableType::Transition: {
            auto* trans = item.as_transition();
            std::cout << prefix << connector << "Transition: " << name
                      << " (kind: " << trans->kind() << ")\n";
            break;
        }

        default:
            std::cout << prefix << connector << "(unknown)\n";
            break;
    }
}

void print_usage() {
    std::cerr << R"(
Display an ASCII diagram of the hierarchy of an OpenTimelineIO file.

usage:
  otio_hierarchy_view_cpp [options] path/to/somefile.otio

options:
  -h --help           print this message and exit
  -a --ascii          use ASCII characters instead of Unicode box-drawing
  -m --show-metadata  display metadata present on clips
)";
}

int main(int argc, char* argv[]) {
    std::vector<std::string> files;
    bool use_ascii = false;
    bool show_metadata = false;

    // Parse arguments
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "-h" || arg == "--help") {
            print_usage();
            return 0;
        } else if (arg == "-a" || arg == "--ascii") {
            use_ascii = true;
        } else if (arg == "-m" || arg == "--show-metadata") {
            show_metadata = true;
        } else {
            files.push_back(arg);
        }
    }

    if (files.empty()) {
        std::cerr << "Error: No input files specified.\n";
        print_usage();
        return 1;
    }

    TreeChars chars = use_ascii ? TreeChars::ascii() : TreeChars::unicode();

    for (const auto& filepath : files) {
        try {
            std::cout << "\n" << chars.header_line << "\n";
            std::cout << " Timeline Hierarchy: " << filepath << "\n";
            std::cout << chars.header_line << "\n\n";

            otio::Timeline tl = otio::read_from_file(filepath);

            std::cout << "Timeline: " << tl.name().value_or("(unnamed)") << "\n";
            std::cout << "\xe2\x94\x82\n";  // │
            std::cout << "\xe2\x94\x94\xe2\x94\x80\xe2\x94\x80 Stack: (tracks)\n";  // └── Stack: (tracks)

            size_t track_count = tl.track_count();
            for (size_t i = 0; i < track_count; ++i) {
                render_item(tl.track_at(i), "    ", i == track_count - 1,
                           chars, show_metadata);
            }

            std::cout << "\n";
        } catch (const otio::OtioError& e) {
            std::cerr << "Error reading '" << filepath << "': " << e.what() << "\n";
        }
    }

    return 0;
}
