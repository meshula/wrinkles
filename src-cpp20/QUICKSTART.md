# C++20 Wrinkles Quick Start

Get up and running with the C++20 Wrinkles implementation in 5 minutes.

## Installation

1. **Clone the repository** (if you haven't already)
2. **Verify you have C++20 support:**
   ```bash
   clang++ --version  # Should be 12+ or GCC 10+
   ```

3. **Dependencies are already included:**
   - RapidJSON is in `../libs/rapidjson/`
   - All other code is header-only

## Run All Tests

```bash
cd src-cpp20

# Test each module
cd opentime && make test && cd ..
cd curve && make test && cd ..
cd topology && make test && cd ..
cd opentimelineio && make test && cd ..
```

Expected output: **152/152 tests passing** ✓

## 30-Second Examples

### 1. Time Math

```cpp
#include "opentime/ordinate.hpp"
#include "opentime/interval.hpp"

using Ordinate = OrdinateImpl<double>;
using Interval = ContinuousIntervalImpl<Ordinate>;

int main() {
    // Create a 10-second interval
    Interval range{
        Ordinate::init(0.0),
        Ordinate::init(10.0)
    };

    // Check if 5.0 seconds is in range
    bool in_range = range.contains(Ordinate::init(5.0));

    // Get duration
    auto duration = range.duration();

    return 0;
}
```

Compile: `clang++ -std=c++20 -I. example.cpp`

### 2. Time Remapping (Speed Changes)

```cpp
#include "curve/linear.hpp"

int main() {
    // Create speed ramp: normal -> 2x -> slow down
    LinearMonotonic remap{{
        {0.0, 0.0},     // Start
        {10.0, 20.0},   // 2x speed for first 10 seconds
        {20.0, 25.0}    // 0.5x speed for next 10 seconds
    }};

    // What's the output time at input time 15?
    auto result = remap.output_at_input(Ordinate::init(15.0));
    // result ≈ 22.5 seconds

    return 0;
}
```

Compile: `clang++ -std=c++20 -I. example.cpp`

### 3. Create and Save a Timeline

```cpp
#include "opentimelineio/schema.hpp"
#include "opentimelineio/json.hpp"

using namespace otio;

int main() {
    // Create a 10-second clip
    Clip clip{"my_shot", ContinuousInterval{
        Ordinate::init(0.0),
        Ordinate::init(10.0)
    }};

    // Add to a track
    Track track{"video"};
    track.append_child(&clip);

    // Add track to timeline
    Stack stack{"tracks"};
    stack.append_child(&track);

    Timeline timeline{"my_edit", stack};

    // Save to file
    json::write_to_file(timeline, "my_timeline.otio");

    return 0;
}
```

Compile: `clang++ -std=c++20 -I. -I../libs/rapidjson/include example.cpp`

### 4. Load and Query a Timeline

```cpp
#include "opentimelineio/json.hpp"
#include <iostream>

using namespace otio;

int main() {
    // Load timeline
    auto timeline = json::read_from_file("my_timeline.otio");

    // Get info
    std::cout << "Timeline: " << *timeline->name << "\n";

    auto bounds = timeline->bounds_of(SpaceLabel::presentation);
    std::cout << "Duration: " << bounds.duration().v << " seconds\n";

    return 0;
}
```

## Common Tasks

### Convert Between Time Spaces

```cpp
#include "opentimelineio/temporal_hierarchy.hpp"

// Build projection map
auto map = temporal::build_temporal_map(timeline);

// Project from one space to another
auto result = temporal::project_ordinate(
    map,
    source_space,
    destination_space,
    Ordinate::init(5.0)
);

if (result.has_value()) {
    std::cout << "Projected time: " << result->v << "\n";
}
```

### Build a Multi-Track Timeline

```cpp
// Video track
Clip video1{"video_clip", interval1};
Track video_track{"video"};
video_track.append_child(&video1);

// Audio track
Clip audio1{"audio_clip", interval2};
Track audio_track{"audio"};
audio_track.append_child(&audio1);

// Stack them (parallel)
Stack stack{"tracks"};
stack.append_child(&video_track);
stack.append_child(&audio_track);

Timeline timeline{"my_edit", stack};
```

### Sequential Editing (Clips One After Another)

```cpp
Track track{"video"};

// Add clips - they automatically play sequentially
track.append_child(&clip1);  // 0-10 seconds
track.append_child(&clip2);  // 10-20 seconds
track.append_child(&clip3);  // 20-30 seconds
```

### Add Gaps (Black Frames)

```cpp
Track track{"video"};

track.append_child(&clip1);                      // Clip
track.append_child(&gap);                         // Gap
track.append_child(&clip2);                      // Another clip
```

## Project Structure for Your Code

```
my_project/
├── main.cpp
├── Makefile
└── wrinkles/                # Git submodule or copy
    └── src-cpp20/
        ├── opentime/
        ├── curve/
        ├── topology/
        └── opentimelineio/
```

**Makefile:**
```makefile
CXX = clang++
CXXFLAGS = -std=c++20 -Wall -Wextra
INCLUDES = -I./wrinkles/src-cpp20 -I./wrinkles/libs/rapidjson/include

my_program: main.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) -o $@ $<
```

## Troubleshooting

### "No such file or directory" errors
- Check include paths: `-I./wrinkles/src-cpp20`
- For OTIO: also add `-I./wrinkles/libs/rapidjson/include`

### "std::variant" or C++20 errors
- Ensure `-std=c++20` flag is set
- Update compiler: Clang 12+ or GCC 10+

### Linker errors
- This is a header-only library - no linking needed!
- Just include the headers you need

### RapidJSON not found
- Only needed for OpenTimelineIO module
- Install: `git clone https://github.com/Tencent/rapidjson.git` to `libs/`
- Or: already in wrinkles/libs/rapidjson/

## Next Steps

1. **Read the full README.md** for detailed documentation
2. **Look at test files** in each module for more examples
3. **Check the original Zig code** in `../src/` for reference implementations
4. **Explore the source code** - it's well-commented!

## Quick API Reference

### Most Used Types

```cpp
// Time
using Ordinate = OrdinateImpl<double>;
using Interval = ContinuousIntervalImpl<Ordinate>;

// Curves
LinearMonotonic curve{{...}};
BezierCurve bezier{...};

// Transformations
Topology topo = Topology::init_affine(...);

// Timeline
Clip clip{"name", interval};
Gap gap{duration};
Track track{"name"};
Stack stack{"name"};
Timeline timeline{"name", stack};

// Projections
auto map = temporal::build_temporal_map(timeline);
auto result = temporal::project_ordinate(map, src, dst, time);
```

### Most Used Functions

```cpp
// Time operations
auto duration = interval.duration();
bool contains = interval.contains(ord);
auto overlap = interval.overlaps(other);

// Curve operations
auto result = curve.output_at_input(time);
auto bounds = curve.bounds();

// Topology operations
auto result = topo.project_instantaneous_cc(time);
auto trimmed = topo.trim_in_input_space(interval);

// Timeline operations
auto bounds = timeline.bounds_of(SpaceLabel::presentation);
auto topo = clip.topology();
json::write_to_file(timeline, "file.otio");
auto loaded = json::read_from_file("file.otio");
```

## Help & Support

- **Documentation**: See README.md in this directory
- **Examples**: Look at test-*.cpp files in each module
- **Source code**: All headers are commented
- **Original implementation**: `../src/` (Zig code)

Happy timeline wrangling! 🎬
