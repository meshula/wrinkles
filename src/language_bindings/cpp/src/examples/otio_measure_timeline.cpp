// otio_measure_timeline.cpp - C++ Implementation
//
// Measure and analyze the temporal structure of an OpenTimelineIO file.

#include <iostream>
#include <string>
#include <vector>
#include <iomanip>
#include "opentimelineio.hpp"

void print_usage() {
    std::cerr << R"(
Measure and analyze the temporal structure of an OpenTimelineIO file.

usage:
  otio_measure_timeline_cpp [options] path/to/somefile.otio

options:
  -h --help    print this message and exit
)";
}

int main(int argc, char* argv[]) {
    std::vector<std::string> files;

    // Parse arguments
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "-h" || arg == "--help") {
            print_usage();
            return 0;
        } else {
            files.push_back(arg);
        }
    }

    if (files.empty()) {
        std::cerr << "Error: No input files specified.\n";
        print_usage();
        return 1;
    }

    for (const auto& filepath : files) {
        try {
            std::cout << "Reading: " << filepath << "\n";

            otio::Timeline tl = otio::read_from_file(filepath);

            // Basic timeline info
            std::cout << "Timeline: " << tl.name().value_or("(unnamed)")
                      << " has " << tl.track_count() << " tracks\n";
            std::cout << "Tracks:\n";

            // Enumerate tracks and their children
            size_t total_items = 0;
            for (size_t track_idx = 0; track_idx < tl.track_count(); ++track_idx) {
                auto track_ref = tl.track_at(track_idx);
                size_t child_count = track_ref.child_count();
                total_items += child_count;

                std::cout << "  Track " << track_idx << ": "
                          << track_ref.name().value_or("(unnamed)")
                          << " has " << child_count << " children\n";

                // List children
                for (size_t child_idx = 0; child_idx < child_count; ++child_idx) {
                    auto child = track_ref.child_at(child_idx);
                    std::cout << "    Child " << child_idx << ": "
                              << child.type_name() << "."
                              << child.name().value_or("(unnamed)") << "\n";
                }
            }

            std::cout << "Total items: " << total_items << "\n\n";

            // Build projection topology
            std::cout << "Building Projection Topology...\n";
            otio::TemporalProjectionBuilder projector(tl);

            std::cout << "Projection map has " << projector.segment_count()
                      << " segments\n";

            std::cout << std::fixed << std::setprecision(3);

            // Show segment details
            for (size_t seg = 0; seg < projector.segment_count(); ++seg) {
                auto bounds = projector.segment_bounds(seg);
                size_t op_count = projector.operator_count(seg);

                std::cout << "  Segment [" << seg << "]: "
                          << bounds.start.as_float() << "s - "
                          << bounds.end.as_float() << "s"
                          << " (" << op_count << " operators)\n";

                // Show operators mapping to media
                for (size_t op_idx = 0; op_idx < op_count; ++op_idx) {
                    auto proj_op = projector.operator_at(seg, op_idx);
                    auto dest = proj_op.destination();

                    if (auto* clip = dest.as_clip()) {
                        auto dest_topo = proj_op.topology();
                        auto dest_bounds = dest_topo.output_bounds();
                        std::cout << "    -> " << clip->name().value_or("(unnamed)");
                        if (dest_bounds) {
                            std::cout << " [" << dest_bounds->start.as_float()
                                      << "s - " << dest_bounds->end.as_float() << "s]";

                            // Show discrete indices if available
                            auto discrete = clip->discrete_partition();
                            if (discrete) {
                                size_t start_idx = discrete->index_at(dest_bounds->start);
                                size_t end_idx = discrete->index_at(dest_bounds->end);
                                std::cout << " (frames " << start_idx
                                          << " - " << end_idx << ")";
                            }
                        }
                        std::cout << "\n";
                    }
                }
            }

            std::cout << "\n";

        } catch (const otio::OtioError& e) {
            std::cerr << "Error: " << e.what() << "\n";
            return 1;
        }
    }

    return 0;
}
