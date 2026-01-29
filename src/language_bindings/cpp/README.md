# Wrinkles C++ Bindings

Modern C++17 wrapper around the wrinkles temporal hierarchy library, providing
idiomatic C++ access to OpenTimelineIO-compatible timeline structures and
temporal projection operations.

## For OpenTimelineIO Users

Wrinkles is a prototype for OTIO v2 with improved temporal math. Key differences
from the OTIO v1 C++ API:

| OTIO v1 C++ | Wrinkles C++ |
|-------------|--------------|
| `#include "opentimelineio/timeline.h"` | `#include "opentimelineio.hpp"` |
| `namespace opentimelineio` | `namespace otio` |
| `RationalTime` for time values | `otio::Ordinate` (continuous float) |
| `SerializableObject::Retainer<>` | RAII `Timeline` object |
| Manual time calculations | `ProjectionOperator` for temporal projections |
| Complex memory management | Automatic arena-based cleanup |

**Try it with your existing .otio files** - Wrinkles can read OTIO v1 JSON files:

```cpp
#include "opentimelineio.hpp"

// Load your existing OTIO file
auto timeline = otio::read_from_file("path/to/your/project.otio");

// Convert to the new text format
otio::write_to_file(timeline, "project.tla");
```

## Prerequisites

Before using the C++ bindings, you must first build the C library:

```bash
# From the project root
zig build
```

This creates `libopentimelineio_c` in `zig-out/lib/` and the C header in
`src/c_binding/opentimelineio_c.h`.

## Building

The C++ bindings are header-only. Include `opentimelineio.hpp` and link against
`libopentimelineio_c`.

### With Zig Build System

The project includes Zig build rules for C++ examples and tests:

```bash
# Run C++ unit tests
zig build test_cpp

# Build and run C++ examples
zig build run-otio_hierarchy_view_cpp -- timeline.otio
zig build run-otio_measure_timeline_cpp -- timeline.otio
zig build run-otiocat_cpp -- timeline.otio
```

### Manual Compilation

```bash
# Compile an example (Linux)
g++ -std=c++17 -I../cpp_binding/include -I../c_binding \
    -L../../zig-out/lib -lopentimelineio_c \
    -o my_program my_program.cpp

# Run (set library path)
LD_LIBRARY_PATH=../../zig-out/lib ./my_program
```

On macOS, use `DYLD_LIBRARY_PATH` instead of `LD_LIBRARY_PATH`.

## Quick Start

```cpp
#include <iostream>
#include "opentimelineio.hpp"

int main(int argc, char* argv[]) {
    // Read a timeline (supports .otio, .tla, .tlb, .tlz)
    auto timeline = otio::read_from_file("project.otio");

    std::cout << "Timeline: " << timeline.name().value_or("(unnamed)") << "\n";

    // Iterate over tracks
    for (const auto& track : timeline.tracks()) {
        std::cout << "  Track: " << track.name().value_or("(unnamed)") << "\n";

        // Iterate over track items
        for (const auto& item : track) {
            std::cout << "    " << item.type_name() << ": "
                      << item.name().value_or("(unnamed)") << "\n";
        }
    }

    // Build projection operators
    auto projections = timeline.build_projection_map();
    for (const auto& proj : projections) {
        auto result = proj.project_cc(otio::Ordinate(0.0f));
        if (result) {
            std::cout << "Projected to: " << result->value << "\n";
        }
    }

    return 0;
}
```

## API Overview

### Namespace

All types are in the `otio` namespace.

### Time Types

```cpp
// Single point in continuous time
otio::Ordinate ord(1.5f);
float value = ord.as_float();

// Named constructors
auto zero = otio::Ordinate::zero();
auto inf = otio::Ordinate::inf();

// Continuous interval [start, end)
otio::ContinuousInterval interval(
    otio::Ordinate(0.0f),  // start
    otio::Ordinate(10.0f)  // end
);
float duration = interval.duration().as_float();
```

### Schema Types

- `Timeline` - Top-level timeline container with RAII memory management
- `Stack` - Container where children play simultaneously
- `Track` - Container where children play sequentially
- `Clip` - Media reference with timing information
- `Gap` - Empty space in a track
- `Warp` - Time-warping container (retiming effects)
- `Transition` - Transition between adjacent items
- `CompositionItem` - Polymorphic handle to any composition item

### File Operations

```cpp
// Read from file
auto timeline = otio::read_from_file("project.otio");

// Write to file
otio::write_to_file(timeline, "output.tla");
```

### Iteration

All container types support range-based for loops and iterators:

```cpp
for (const auto& track : timeline.tracks()) {
    for (const auto& item : track) {
        // Process each item
    }
}
```

### Exception Handling

```cpp
try {
    auto timeline = otio::read_from_file("missing.otio");
} catch (const otio::FileNotFoundError& e) {
    std::cerr << "File not found: " << e.what() << "\n";
} catch (const otio::ParseError& e) {
    std::cerr << "Parse error: " << e.what() << "\n";
} catch (const otio::OtioError& e) {
    std::cerr << "Error: " << e.what() << "\n";
}
```

### Sample Index Generation

```cpp
// Get discrete info for a clip
auto discrete_info = clip.discrete_info(otio::Domain::Picture);
if (discrete_info) {
    // Convert continuous time to sample index
    size_t frame = discrete_info->index_at(otio::Ordinate(1.5f));
    std::cout << "Frame at 1.5s: " << frame << "\n";
}
```

## Example Programs

Example programs are located in `src/cpp_examples/`:

| Program | Description |
|---------|-------------|
| `otio_hierarchy_view.cpp` | Display timeline hierarchy as ASCII tree |
| `otio_measure_timeline.cpp` | Measure and display timeline durations |
| `otiocat.cpp` | Convert timelines between formats |

### Running Examples

You can use the sample files included with wrinkles or your own `.otio` files:

```bash
# Using wrinkles sample files
zig build run-otio_hierarchy_view_cpp -- ../../sample_otio_files/multiple_track.otio

# Using OpenTimelineIO sample files (if you have OTIO cloned alongside wrinkles)
zig build run-otio_hierarchy_view_cpp -- ../../../OpenTimelineIO/tests/sample_data/screening_example.otio

# Measure timeline durations
zig build run-otio_measure_timeline_cpp -- ../../sample_otio_files/multiple_track.otio

# Convert between formats
zig build run-otiocat_cpp -- input.otio output.tla
```

## Running Tests

```bash
zig build test_cpp
```

The test suite is in `test/test_opentimelineio.cpp`.

## File Structure

```
cpp_binding/
├── include/
│   └── opentimelineio.hpp   # Main header (include this)
├── src/
│   └── opentimelineio.cpp   # Implementation (linked by Zig build)
├── test/
│   └── test_opentimelineio.cpp  # Unit tests
└── README.md
```

## Supported File Formats

| Extension | Description |
|-----------|-------------|
| `.otio` | OpenTimelineIO v1 JSON (read-only) |
| `.tla` | Human-readable text format (Ziggy) |
| `.tlb` | FlatBuffers based Binary format |
| `.tlz` | ZIP bundle with media references |

## Requirements

- C++17 compiler (GCC 7+, Clang 5+, MSVC 2017+)
- Built `libopentimelineio_c` library
