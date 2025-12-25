#!/usr/bin/env python3
"""
Convert OpenTimelineIO JSON files to Ziggy format.

Usage:
    python otio_to_ziggy.py input.otio output.ziggy
"""

import json
import sys
from typing import Any, Dict, List, Optional


def rational_time_to_float(rational_time: Dict[str, Any]) -> float:
    """Convert OTIO RationalTime to float seconds."""
    if rational_time.get("OTIO_SCHEMA") != "RationalTime.1":
        raise ValueError(f"Expected RationalTime.1, got {rational_time.get('OTIO_SCHEMA')}")

    value = rational_time["value"]
    rate = rational_time["rate"]
    return float(value) / float(rate)


def time_range_to_continuous_interval(time_range: Dict[str, Any]) -> List[float]:
    """Convert OTIO TimeRange to Ziggy ContinuousInterval [start, end]."""
    if time_range.get("OTIO_SCHEMA") != "TimeRange.1":
        raise ValueError(f"Expected TimeRange.1, got {time_range.get('OTIO_SCHEMA')}")

    start = rational_time_to_float(time_range["start_time"])
    duration = rational_time_to_float(time_range["duration"])

    return [start, start + duration]


def convert_media_reference(media_ref: Dict[str, Any]) -> Dict[str, Any]:
    """Convert OTIO MediaReference to Ziggy format."""
    schema_type = media_ref.get("OTIO_SCHEMA")

    if schema_type == "ExternalReference.1":
        # External reference with URI
        target_url = media_ref.get("target_url", "")
        available_range = media_ref.get("available_range")

        bounds_s = None
        if available_range:
            bounds_s = time_range_to_continuous_interval(available_range)

        return {
            "data_reference": {
                "uri": {
                    "target_uri": target_url
                }
            },
            "bounds_s": bounds_s,
            "domain": "picture",  # Default to picture
            "discrete_partition": {
                "sample_rate_hz": {"Int": 24},  # Default 24fps
                "start_index": 0
            },
            "interpolating": "snap"
        }
    elif schema_type == "MissingReference.1":
        # Missing/null reference
        return {
            "data_reference": {"null": {}},
            "bounds_s": None,
            "domain": "picture",
            "discrete_partition": None,
            "interpolating": "snap"
        }
    else:
        # Default to null reference
        return {
            "data_reference": {"null": {}},
            "bounds_s": None,
            "domain": "picture",
            "discrete_partition": None,
            "interpolating": "snap"
        }


def convert_clip(clip: Dict[str, Any]) -> Dict[str, Any]:
    """Convert OTIO Clip to Ziggy format."""
    name = clip.get("name")
    media_reference = clip.get("media_reference", {})
    source_range = clip.get("source_range")

    bounds_s = None
    if source_range:
        bounds_s = time_range_to_continuous_interval(source_range)

    return {
        "name": name,
        "bounds_s": bounds_s,
        "media": convert_media_reference(media_reference)
    }


def convert_gap(gap: Dict[str, Any]) -> Dict[str, Any]:
    """Convert OTIO Gap to Ziggy format."""
    name = gap.get("name")
    source_range = gap.get("source_range")

    if not source_range:
        # Default gap duration
        bounds_s = {"start": {"v": 0.0}, "end": {"v": 1.0}}
    else:
        bounds_s = time_range_to_continuous_interval(source_range)

    return {
        "name": name,
        "bounds_s": bounds_s
    }


def convert_composable(item: Dict[str, Any]) -> Dict[str, Any]:
    """Convert OTIO composable item (Clip, Gap, Track, etc.) to Ziggy format."""
    schema_type = item.get("OTIO_SCHEMA")

    if schema_type == "Clip.1":
        return {"clip": convert_clip(item)}
    elif schema_type == "Gap.1":
        return {"gap": convert_gap(item)}
    elif schema_type == "Track.1":
        return {"track": convert_track(item)}
    elif schema_type == "Stack.1":
        return {"stack": convert_stack(item)}
    else:
        # Unknown type, convert to gap
        print(f"Warning: Unknown composable type {schema_type}, converting to gap")
        return {"gap": {"name": item.get("name"), "bounds_s": {"start": {"v": 0.0}, "end": {"v": 1.0}}}}


def convert_track(track: Dict[str, Any]) -> Dict[str, Any]:
    """Convert OTIO Track to Ziggy format."""
    name = track.get("name")
    children = track.get("children", [])

    converted_children = []
    for child in children:
        converted_children.append(convert_composable(child))

    return {
        "name": name,
        "children": converted_children
    }


def convert_stack(stack: Dict[str, Any]) -> Dict[str, Any]:
    """Convert OTIO Stack to Ziggy format."""
    name = stack.get("name")
    children = stack.get("children", [])

    converted_children = []
    for child in children:
        converted_children.append(convert_composable(child))

    return {
        "name": name,
        "children": converted_children
    }


def convert_timeline(timeline: Dict[str, Any]) -> Dict[str, Any]:
    """Convert OTIO Timeline to Ziggy format."""
    name = timeline.get("name", "")
    tracks = timeline.get("tracks", {})

    # Convert tracks.children directly to timeline.children
    children = tracks.get("children", [])
    converted_children = []
    for child in children:
        converted_children.append(convert_composable(child))

    return {
        "name": name,
        "children": converted_children,
        "discrete_space_partitions": {
            "presentation": {
                "picture": None,
                "audio": None
            }
        }
    }


def format_ziggy_value(value: Any, indent: int = 0) -> str:
    """Format a Python value as Ziggy syntax."""
    ind = "    " * indent

    if value is None:
        return "null"
    elif isinstance(value, bool):
        return "true" if value else "false"
    elif isinstance(value, (int, float)):
        if isinstance(value, float):
            if value == float('inf'):
                return "inf"
            elif value == float('-inf'):
                return "-inf"
        return str(value)
    elif isinstance(value, str):
        return f'"{value}"'
    elif isinstance(value, dict):
        if not value:
            return "{}"

        lines = ["{"]
        for key, val in value.items():
            formatted_val = format_ziggy_value(val, indent + 1)
            lines.append(f"{ind}    .{key} = {formatted_val},")
        lines.append(f"{ind}}}")
        return "\n".join(lines)
    elif isinstance(value, list):
        if not value:
            return "[]"

        lines = ["["]
        for item in value:
            formatted_item = format_ziggy_value(item, indent + 1)
            lines.append(f"{ind}    {formatted_item},")
        lines.append(f"{ind}]")
        return "\n".join(lines)
    else:
        return str(value)


def convert_otio_to_ziggy(otio_data: Dict[str, Any]) -> str:
    """Convert OTIO JSON data to Ziggy format string."""
    schema_type = otio_data.get("OTIO_SCHEMA")

    if schema_type == "Timeline.1":
        ziggy_data = convert_timeline(otio_data)
    elif schema_type == "Clip.1":
        ziggy_data = convert_clip(otio_data)
    elif schema_type == "Track.1":
        ziggy_data = convert_track(otio_data)
    elif schema_type == "Gap.1":
        ziggy_data = convert_gap(otio_data)
    elif schema_type == "Warp.1":
        ziggy_data = convert_warp(otio_data)
    elif schema_type == "Transition.1":
        ziggy_data = convert_transition(otio_data)
    elif schema_type == "Stack.1":
        ziggy_data = convert_stack(otio_data)
    else:
        raise ValueError(f"Unsupported root schema type: {schema_type}")

    return format_ziggy_value(ziggy_data)


def main():
    if len(sys.argv) != 3:
        print("Usage: python otio_to_ziggy.py input.otio output.ziggy")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    # Read OTIO JSON file
    with open(input_file, 'r') as f:
        otio_data = json.load(f)

    # Convert to Ziggy format
    ziggy_output = convert_otio_to_ziggy(otio_data)

    # Write Ziggy file
    with open(output_file, 'w') as f:
        f.write(ziggy_output)

    print(f"Converted {input_file} to {output_file}")


if __name__ == "__main__":
    main()
