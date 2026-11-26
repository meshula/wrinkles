// otiocat.cpp - C++ Implementation
//
// Universal timeline format converter - reads and displays timeline files.
// Note: Write functionality requires C API extensions not yet implemented.

#include <iostream>
#include <string>
#include <algorithm>
#include "opentimelineio.hpp"

void print_usage() {
    std::cerr << R"(
otiocat_cpp - Universal timeline format viewer/converter

Reads timeline files in various formats and displays information about them.

Supported input formats:
  .otio   OpenTimelineIO JSON format
  .ziggy  Ziggy text format
  .tlb    Binary FlatBuffers based format

Usage:
  otiocat_cpp [options] <input>

Arguments:
  <input>   Path to the source timeline file

Options:
  -h, --help         Print this message and exit
  -v, --verbose      Show detailed timeline information

Examples:
  otiocat_cpp timeline.otio           # Display timeline info
  otiocat_cpp -v timeline.otio        # Verbose output
)";
}

std::string get_extension(const std::string& path) {
    auto pos = path.rfind('.');
    if (pos == std::string::npos) return "";
    std::string ext = path.substr(pos);
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
    return ext;
}

void print_timeline_summary(const otio::Timeline& tl, bool verbose) {
    std::cout << "Timeline: " << tl.name().value_or("(unnamed)") << "\n";
    std::cout << "  Tracks: " << tl.track_count() << "\n";

    size_t total_clips = 0;
    size_t total_gaps = 0;
    size_t total_transitions = 0;

    for (size_t i = 0; i < tl.track_count(); ++i) {
        auto track = tl.track_at(i);

        if (verbose) {
            std::cout << "\n  Track " << i << ": "
                      << track.name().value_or("(unnamed)") << "\n";
            auto bounds = track.bounds();
            if (bounds) {
                std::cout << "    Bounds: " << bounds->start.as_float() << "s - "
                          << bounds->end.as_float() << "s\n";
            }
            std::cout << "    Children: " << track.child_count() << "\n";
        }

        for (size_t j = 0; j < track.child_count(); ++j) {
            auto child = track.child_at(j);
            switch (child.type()) {
                case otio::ComposableType::Clip:
                    total_clips++;
                    if (verbose) {
                        auto* clip = child.as_clip();
                        std::cout << "      Clip: " << clip->name().value_or("(unnamed)");
                        auto bounds = clip->bounds();
                        if (bounds) {
                            std::cout << " [" << bounds->start.as_float() << "s - "
                                      << bounds->end.as_float() << "s]";
                        }
                        auto media = clip->media();
                        if (media.is_uri()) {
                            std::cout << "\n        Media: " << media.target_uri;
                        }
                        std::cout << "\n";
                    }
                    break;
                case otio::ComposableType::Gap:
                    total_gaps++;
                    if (verbose) {
                        auto* gap = child.as_gap();
                        std::cout << "      Gap: " << gap->name().value_or("(unnamed)");
                        auto bounds = gap->bounds();
                        if (bounds) {
                            std::cout << " [" << bounds->start.as_float() << "s - "
                                      << bounds->end.as_float() << "s]";
                        }
                        std::cout << "\n";
                    }
                    break;
                case otio::ComposableType::Transition:
                    total_transitions++;
                    if (verbose) {
                        auto* trans = child.as_transition();
                        std::cout << "      Transition: " << trans->name().value_or("(unnamed)")
                                  << " (kind: " << trans->kind() << ")\n";
                    }
                    break;
                default:
                    break;
            }
        }
    }

    std::cout << "\nSummary:\n";
    std::cout << "  Total clips: " << total_clips << "\n";
    std::cout << "  Total gaps: " << total_gaps << "\n";
    std::cout << "  Total transitions: " << total_transitions << "\n";
}

int main(int argc, char* argv[]) {
    std::string input_path;
    bool verbose = false;

    // Parse arguments
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];

        if (arg == "-h" || arg == "--help") {
            print_usage();
            return 0;
        } else if (arg == "-v" || arg == "--verbose") {
            verbose = true;
        } else if (arg[0] == '-') {
            std::cerr << "Unknown option: " << arg << "\n";
            print_usage();
            return 1;
        } else if (input_path.empty()) {
            input_path = arg;
        } else {
            std::cerr << "Too many arguments.\n";
            print_usage();
            return 1;
        }
    }

    if (input_path.empty()) {
        std::cerr << "Error: No input file specified.\n";
        print_usage();
        return 1;
    }

    // @TODO: add .tlc support?

    // Validate extension
    std::string input_ext = get_extension(input_path);
    if (
            input_ext != ".otio" 
            && input_ext != ".tlb" 
            && input_ext != ".tla"
            && input_ext != ".tlz"
    ) 
    {
        std::cerr << "Error: Unsupported input format: " << input_ext << "\n";
        std::cerr << "Use .otio, .tla, .tlb, or .tlz \n";
        return 1;
    }

    try {
        std::cout << "Reading: " << input_path << "\n\n";
        otio::Timeline tl = otio::read_from_file(input_path);

        print_timeline_summary(tl, verbose);

        return 0;

    } catch (const otio::FileNotFoundError& e) {
        std::cerr << "Error: File not found: " << input_path << "\n";
        return 1;
    } catch (const otio::ParseError& e) {
        std::cerr << "Error: Failed to parse " << input_path << ": "
                  << e.what() << "\n";
        return 1;
    } catch (const otio::OtioError& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
}
