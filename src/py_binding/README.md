# Wrinkles Python Bindings

Python bindings for the wrinkles temporal hierarchy library, providing access to
OpenTimelineIO-compatible timeline structures and temporal projection capabilities.

## For OpenTimelineIO Users

Wrinkles is a prototype for OTIO v2 with improved temporal math. Key differences:

| OTIO v1 | Wrinkles (OTIO v2 prototype) |
|---------|------------------------------|
| `import opentimelineio as otio` | `import wrinkles as otio2` |
| `otio.adapters.read_from_file()` | `otio2.read_from_file()` |
| `RationalTime` for all time values | Continuous `float` ordinates + explicit discrete info |
| Linear time effects only | Non-linear time warps via bezier curves |
| Manual time calculations | `ProjectionOperator` for temporal projections |

**Try it with your existing .otio files** - Wrinkles can read OTIO v1 JSON files directly:

```python
import wrinkles as otio2

# Load your existing OTIO file
timeline = otio2.read_from_file("path/to/your/project.otio")

# Convert to the new text format
otio2.write_to_file(timeline, "project.tla")
```

## Prerequisites

Before building the Python bindings, you must first build the C library:

```bash
# From the project root
zig build
```

This creates `libopentimelineio_c` in `zig-out/lib/`.

## Installation

### Development Install (Recommended)

Install in editable mode for development:

```bash
cd src/py_binding
pip install -e ".[dev]"
```

### Standard Install

```bash
cd src/py_binding
pip install .
```

## Quick Start

```python
import wrinkles as otio2

# Read a timeline (supports .otio, .tla, .tlb, .tlfb, .tlz)
timeline = otio2.read_from_file("project.otio")

# Access structure
print(f"Timeline: {timeline.name}")
for track in timeline.tracks:
    print(f"  Track: {track.name}")
    for item in track:
        print(f"    {type(item).__name__}: {item.name}")

# Write to a different format
otio2.write_to_file(timeline, "project.tla")

# Build projection operators for temporal math
projections = otio2.build_projection_map(timeline)
for proj in projections:
    result = proj.project_cc(0.0)
    print(f"Projected: {result}")
```

## API Reference

### Schema Types

- `Timeline` - Top-level timeline container
- `Stack` - Container where children play simultaneously
- `Track` - Container where children play sequentially
- `Clip` - Media reference with timing information
- `Gap` - Empty space in a track
- `Warp` - Time-warping container (retiming effects)
- `Transition` - Transition between adjacent items

### Functions

- `read_from_file(path)` - Read a timeline from file
- `write_to_file(timeline, path)` - Write a timeline to file
- `build_projection_map(timeline)` - Build projection operators for temporal math

### Domain Constants

- `DOMAIN_TIME` - General time domain
- `DOMAIN_PICTURE` - Video/picture domain
- `DOMAIN_AUDIO` - Audio domain
- `DOMAIN_METADATA` - Metadata domain

## Running Tests

```bash
cd src/py_binding
pytest tests/
```

Or with coverage:

```bash
pytest tests/ --cov=wrinkles
```

## Example Scripts

The `examples/` directory contains example scripts demonstrating common operations:

| Script | Description |
|--------|-------------|
| `find_clips.py` | Find all clips in a timeline, optionally filtering by name |
| `summarize_timeline.py` | Print a summary of timeline structure |
| `traverse_hierarchy.py` | Traverse and print the full timeline hierarchy |
| `sample_requirements.py` | Analyze media samples needed for playback using `TemporalProjectionBuilder` |

### Running Examples

All examples use `argparse` for command line arguments. You can use the sample
files included with wrinkles or your own `.otio` files from OpenTimelineIO:

```bash
# Using wrinkles sample files
python examples/find_clips.py -i ../../sample_otio_files/multiple_track.otio

# Using OpenTimelineIO sample files (if you have OTIO cloned alongside wrinkles)
python examples/find_clips.py -i ../../../OpenTimelineIO/tests/sample_data/screening_example.otio

# Find all clips
python examples/find_clips.py -i ../../sample_otio_files/multiple_track.otio

# Find clips matching a search term
python examples/find_clips.py -i timeline.otio -s shot_001

# Summarize timeline structure
python examples/summarize_timeline.py -i timeline.otio

# Traverse hierarchy
python examples/traverse_hierarchy.py -i timeline.otio

# Analyze sample requirements
python examples/sample_requirements.py -i timeline.otio

# Get help for any script
python examples/find_clips.py --help
```

## Supported File Formats

| Extension | Description |
|-----------|-------------|
| `.otio` | OpenTimelineIO v1 JSON (read-only) |
| `.tla` | Human-readable text format (Ziggy) |
| `.tlb` | Binary CBOR format |
| `.tlfb` | FlatBuffers binary format |
| `.tlz` | ZIP bundle with media references |

## Troubleshooting

### Library not found

If you get an error about `libopentimelineio_c` not being found:

1. Ensure you've built the Zig project first: `zig build`
2. Check that `zig-out/lib/libopentimelineio_c.*` exists
3. On Linux, you may need to set `LD_LIBRARY_PATH`:
   ```bash
   export LD_LIBRARY_PATH=$PWD/../../zig-out/lib:$LD_LIBRARY_PATH
   ```

### Import errors

If imports fail after installation, try reinstalling:

```bash
pip uninstall wrinkles
pip install -e .
```
