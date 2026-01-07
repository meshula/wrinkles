#!/usr/bin/env python3
"""
Convert OpenTimelineIO JSON files to TLA format.

Usage:
    python otio_to_ziggy.py input.otio output.tla
"""

import json
import sys
from typing import Any, Dict, List, Optional


def is_discrete_rate(rate) -> bool:
    """Check if a rate should be treated as discrete.

    Args:
        rate: The rate value to check

    Returns:
        True if rate is an integer > 1, False otherwise
    """
    if rate is None:
        return False
    # Rate must be an integer and not equal to 1
    return isinstance(rate, (int, float)) and rate == int(rate) and rate != 1


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


def convert_media_reference(media_ref: Dict[str, Any], discrete_rate: Optional[int] = None) -> Dict[str, Any]:
    """Convert OTIO MediaReference to Ziggy format.

    The available_range from the OTIO MediaReference is converted to media.bounds_s.

    Args:
        media_ref: The OTIO media reference dictionary
        discrete_rate: If provided, use this as the sample rate and convert bounds to discrete
    """
    schema_type = media_ref.get("OTIO_SCHEMA")

    if schema_type == "ExternalReference.1":
        # External reference with URI
        target_url = media_ref.get("target_url", "")
        available_range = media_ref.get("available_range")

        result = {
            "data_reference": {
                "uri": {
                    "target_uri": target_url
                }
            },
            "domain": {"picture": {}},  # Domain as union
            # interpolating defaults to "default_from_domain" and is omitted
        }

        # Add discrete partition if we have a discrete rate
        if discrete_rate is not None:
            result["discrete_partition"] = {
                "sample_rate_hz": {"Int": discrete_rate},
                "start_index": 0
            }

        # Convert available_range to media.bounds_s if it exists
        if available_range:
            # Check if available_range can use discrete bounds
            # Only use discrete if both start_time and duration have the same rate as discrete_rate
            start_time = available_range.get("start_time", {})
            duration = available_range.get("duration", {})
            start_rate = start_time.get("rate")
            duration_rate = duration.get("rate")

            can_use_discrete = (
                discrete_rate is not None and
                start_rate == discrete_rate and
                duration_rate == discrete_rate
            )

            if can_use_discrete:
                # Use discrete bounds (sample indices)
                start_index = int(start_time.get("value", 0))
                end_index = start_index + int(duration.get("value", 0))

                result["bounds_s"] = {"discrete": [start_index, end_index]}
            else:
                # Use continuous bounds (time in seconds)
                interval = time_range_to_continuous_interval(available_range)
                result["bounds_s"] = {"continuous": interval}

        return result
    elif schema_type == "MissingReference.1":
        # Missing/null reference
        result = {
            "data_reference": {"null": {}},
            "domain": {"picture": {}},
            # interpolating defaults to "default_from_domain" and is omitted
        }

        # Add discrete partition if we have a discrete rate
        if discrete_rate is not None:
            result["discrete_partition"] = {
                "sample_rate_hz": {"Int": discrete_rate},
                "start_index": 0
            }

        return result
    else:
        # Default to null reference
        result = {
            "data_reference": {"null": {}},
            "domain": {"picture": {}},
            # interpolating defaults to "default_from_domain" and is omitted
        }

        # Add discrete partition if we have a discrete rate
        if discrete_rate is not None:
            result["discrete_partition"] = {
                "sample_rate_hz": {"Int": discrete_rate},
                "start_index": 0
            }

        return result


def convert_clip(clip: Dict[str, Any]) -> Dict[str, Any]:
    """Convert OTIO Clip to Ziggy format.

    The source_range from the OTIO Clip is converted to clip.bounds_s.
    The available_range from the MediaReference is converted to media.bounds_s.
    """
    name = clip.get("name")
    media_reference = clip.get("media_reference", {})
    source_range = clip.get("source_range")

    # Check if we should use discrete bounds for the clip
    # Use discrete when the source_range has an integer rate > 1
    discrete_rate = None
    if source_range:
        start_time = source_range.get("start_time", {})
        duration = source_range.get("duration", {})
        start_rate = start_time.get("rate")
        duration_rate = duration.get("rate")

        # Only use discrete if both rates are the same and discrete
        if (start_rate is not None and duration_rate is not None and
            start_rate == duration_rate and
            is_discrete_rate(start_rate)):
            discrete_rate = int(start_rate)

    result = {
        "media": convert_media_reference(media_reference, discrete_rate)
    }

    # Only add name if it exists
    if name is not None:
        result["name"] = name

    # Only add bounds_s if source_range exists
    if source_range:
        if discrete_rate is not None:
            # Use discrete bounds (sample indices)
            start_time = source_range["start_time"]
            duration = source_range["duration"]

            start_index = int(start_time["value"])
            end_index = start_index + int(duration["value"])

            result["bounds_s"] = {"discrete": [start_index, end_index]}
        else:
            # Use continuous bounds (time in seconds)
            interval = time_range_to_continuous_interval(source_range)
            result["bounds_s"] = {"continuous": interval}

    return result


def convert_gap(gap: Dict[str, Any]) -> Dict[str, Any]:
    """Convert OTIO Gap to Ziggy format."""
    name = gap.get("name")
    source_range = gap.get("source_range")

    if not source_range:
        # Default gap duration - Gap uses [2]Float directly, not Bounds union
        bounds_s = [0.0, 1.0]
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
        return {"gap": {"name": item.get("name"), "bounds_s": [0.0, 1.0]}}


def convert_track(track: Dict[str, Any]) -> Dict[str, Any]:
    """Convert OTIO Track to Ziggy format."""
    name = track.get("name")
    children = track.get("children", [])
    source_range = track.get("source_range")

    converted_children = []
    for child in children:
        converted_children.append(convert_composable(child))

    result = {
        "name": name,
        "children": converted_children
    }

    # Add bounds if source_range exists
    # Always use continuous bounds for Track (no discrete partition context)
    if source_range:
        interval = time_range_to_continuous_interval(source_range)
        result["bounds_s"] = {"continuous": interval}

    return result


def convert_stack(stack: Dict[str, Any]) -> Dict[str, Any]:
    """Convert OTIO Stack to Ziggy format."""
    name = stack.get("name")
    children = stack.get("children", [])
    source_range = stack.get("source_range")

    converted_children = []
    for child in children:
        converted_children.append(convert_composable(child))

    result = {
        "name": name,
        "children": converted_children
    }

    # Add bounds if source_range exists
    # Always use continuous bounds for Stack (no discrete partition context)
    if source_range:
        interval = time_range_to_continuous_interval(source_range)
        result["bounds_s"] = {"continuous": interval}

    return result


def collect_rates_from_time_range(time_range: Optional[Dict[str, Any]], rates: set):
    """Collect all rates from a TimeRange."""
    if not time_range:
        return

    start_time = time_range.get("start_time", {})
    duration = time_range.get("duration", {})

    start_rate = start_time.get("rate")
    duration_rate = duration.get("rate")

    if start_rate is not None:
        rates.add(start_rate)
    if duration_rate is not None:
        rates.add(duration_rate)


def collect_all_rates(obj: Any, rates: set):
    """Recursively collect all rates from OTIO structure."""
    if isinstance(obj, dict):
        schema_type = obj.get("OTIO_SCHEMA", "")

        # Check for TimeRange and RationalTime
        if schema_type == "TimeRange.1":
            collect_rates_from_time_range(obj, rates)
        elif schema_type == "RationalTime.1":
            rate = obj.get("rate")
            if rate is not None:
                rates.add(rate)

        # Recurse into all dict values
        for value in obj.values():
            collect_all_rates(value, rates)
    elif isinstance(obj, list):
        # Recurse into all list items
        for item in obj:
            collect_all_rates(item, rates)


def convert_timeline(timeline: Dict[str, Any]) -> Dict[str, Any]:
    """Convert OTIO Timeline to Ziggy format."""
    name = timeline.get("name")
    tracks = timeline.get("tracks", {})

    # Collect all rates from the timeline
    rates = set()
    collect_all_rates(timeline, rates)

    # Determine if we should add presentation_space_discrete_partition
    # Only if all rates are the same and discrete (not 1)
    presentation_partition = None
    if len(rates) == 1:
        single_rate = next(iter(rates))
        if is_discrete_rate(single_rate):
            presentation_partition = {
                "sample_rate_hz": {"Int": int(single_rate)},
                "start_index": 0
            }

    # Convert tracks.children directly to timeline.children
    children = tracks.get("children", [])
    converted_children = []
    for child in children:
        converted_children.append(convert_composable(child))

    result = {
        "schema_version": 1,
        "children": converted_children,
        "presentation_space_discrete_partitions": {}
    }

    # Add presentation_space_discrete_partition if we have one
    if presentation_partition is not None:
        result["presentation_space_discrete_partitions"]["picture"] = presentation_partition

    # Only add name if it exists
    if name is not None:
        result["name"] = name

    return result


def is_union_value(value: Any, parent_field_name: str = None) -> bool:
    """Check if a dictionary represents a union value (single key with struct/empty dict value).

    Union variants in ziggy 0.1.0 format look like:
    - .variant = {} (empty struct)
    - .variant = {.field = value, ...} (struct with fields)

    NOT unions:
    - {"target_uri": "..."} (regular struct with single field - field name isn't a variant)
    - {"start": 0.0, "end": 1.0} (regular struct with multiple fields)
    - {"picture": {...}} when parent is presentation_space_discrete_partitions (struct field, not union)
    """
    if not isinstance(value, dict):
        return False
    if len(value) != 1:
        return False

    key = next(iter(value))
    val = value[key]

    # Known union variant names from the schema
    UNION_VARIANTS = {
        # Composable union
        "track", "clip", "gap", "warp", "transition", "stack",
        # MediaDataReference union
        "uri", "signal", "null",
        # SignalGenerator union
        "sine", "linear_ramp",
        # Domain union
        "time", "picture", "audio", "metadata", "other",
        # Bounds union
        "continuous", "discrete",
        # RateSpecifier union
        "Int", "Rat",
        # Mapping union
        "affine", "linear", "empty",
    }

    # Special case: "picture" and "audio" are struct fields in DiscretePartitionDomainMap,
    # not union variants, when they appear in presentation_space_discrete_partitions
    if parent_field_name == "presentation_space_discrete_partitions" and key in ("picture", "audio"):
        return False

    # If the key is a known union variant, it's a union
    return key in UNION_VARIANTS


def format_ziggy_value(value: Any, indent: int = 0, is_union: bool = False, parent_field: str = None) -> str:
    """Format a Python value as Ziggy syntax, omitting null values.

    Args:
        value: The value to format
        indent: Current indentation level
        is_union: True if this value should be formatted as a union (without outer braces)
        parent_field: Name of the parent struct field (for context-aware union detection)
    """
    ind = "    " * indent

    if value is None:
        return None  # Signal to skip this field
    elif isinstance(value, bool):
        return "true" if value else "false"
    elif isinstance(value, (int, float)):
        if isinstance(value, float):
            if value == float('inf'):
                return "inf"
            elif value == float('-inf'):
                return "-inf"
            # PATCHED: Always include decimal point for floats to ensure ziggy parser accepts them
            # Integer-looking floats would otherwise be output as "1" which historically
            # caused parsing failures with nested unions + f64 fields
            s = str(value)
            if '.' not in s and 'e' not in s.lower():
                s = s + '.0'
            return s
        return str(value)
    elif isinstance(value, str):
        return f'"{value}"'
    elif isinstance(value, dict):
        if not value:
            return "{}"

        # Check if this is a union value (single key that's a known variant)
        # Pass parent_field for context-aware detection
        if is_union_value(value, parent_field_name=parent_field):
            # Format as union: variant_name { fields }
            # Ziggy union syntax is "variant_name { .field = value, ... }"
            key = next(iter(value))
            val = value[key]
            formatted_val = format_ziggy_value(val, indent)
            return f"{key} {formatted_val}"

        # Regular struct
        lines = ["{"]
        for key, val in value.items():
            # Check if the value is a union (pass field name for context)
            if is_union_value(val, parent_field_name=key):
                # Union as struct field value: .field = variant_name { ... }
                union_key = next(iter(val))
                union_val = val[union_key]
                formatted_union_val = format_ziggy_value(union_val, indent + 1)
                lines.append(f"{ind}    .{key} = {union_key} {formatted_union_val},")
            else:
                formatted_val = format_ziggy_value(val, indent + 1, parent_field=key)
                # Skip null fields
                if formatted_val is not None:
                    lines.append(f"{ind}    .{key} = {formatted_val},")
        lines.append(f"{ind}}}")
        return "\n".join(lines)
    elif isinstance(value, list):
        if not value:
            return "[]"

        lines = ["["]
        for item in value:
            # Check if list items are unions
            formatted_item = format_ziggy_value(item, indent + 1, is_union=is_union_value(item))
            if formatted_item is not None:
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
        # Wrap clip in a Track and Timeline for complete schema
        wrapped_timeline = {
            "OTIO_SCHEMA": "Timeline.1",
            "name": otio_data.get("name"),
            "tracks": {
                "OTIO_SCHEMA": "Stack.1",
                "name": "tracks",
                "children": [
                    {
                        "OTIO_SCHEMA": "Track.1",
                        "name": "Track-001",
                        "children": [otio_data]
                    }
                ]
            }
        }
        ziggy_data = convert_timeline(wrapped_timeline)
    elif schema_type == "Track.1":
        # Wrap track in a Timeline for complete schema
        wrapped_timeline = {
            "OTIO_SCHEMA": "Timeline.1",
            "name": otio_data.get("name"),
            "tracks": {
                "OTIO_SCHEMA": "Stack.1",
                "name": "tracks",
                "children": [otio_data]
            }
        }
        ziggy_data = convert_timeline(wrapped_timeline)
    elif schema_type == "Gap.1":
        # Wrap gap in a Track and Timeline for complete schema
        wrapped_timeline = {
            "OTIO_SCHEMA": "Timeline.1",
            "name": otio_data.get("name"),
            "tracks": {
                "OTIO_SCHEMA": "Stack.1",
                "name": "tracks",
                "children": [
                    {
                        "OTIO_SCHEMA": "Track.1",
                        "name": "Track-001",
                        "children": [otio_data]
                    }
                ]
            }
        }
        ziggy_data = convert_timeline(wrapped_timeline)
    elif schema_type == "Warp.1":
        # Warp not supported yet, wrap in timeline
        print(f"Warning: Warp.1 not fully supported, wrapping in timeline", file=sys.stderr)
        wrapped_timeline = {
            "OTIO_SCHEMA": "Timeline.1",
            "name": otio_data.get("name"),
            "tracks": {
                "OTIO_SCHEMA": "Stack.1",
                "name": "tracks",
                "children": []
            }
        }
        ziggy_data = convert_timeline(wrapped_timeline)
    elif schema_type == "Transition.1":
        # Transition not supported yet, wrap in timeline
        print(f"Warning: Transition.1 not fully supported, wrapping in timeline", file=sys.stderr)
        wrapped_timeline = {
            "OTIO_SCHEMA": "Timeline.1",
            "name": otio_data.get("name"),
            "tracks": {
                "OTIO_SCHEMA": "Stack.1",
                "name": "tracks",
                "children": []
            }
        }
        ziggy_data = convert_timeline(wrapped_timeline)
    elif schema_type == "Stack.1":
        # Wrap stack in a Timeline for complete schema
        wrapped_timeline = {
            "OTIO_SCHEMA": "Timeline.1",
            "name": otio_data.get("name"),
            "tracks": otio_data
        }
        ziggy_data = convert_timeline(wrapped_timeline)
    else:
        raise ValueError(f"Unsupported root schema type: {schema_type}")

    return format_ziggy_value(ziggy_data)


def main():
    if len(sys.argv) != 3:
        print("Usage: python otio_to_ziggy.py input.otio output.tla")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    # Read OTIO JSON file
    with open(input_file, 'r') as f:
        otio_data = json.load(f)

    # Convert to TLA format (using Ziggy syntax)
    tla_output = convert_otio_to_ziggy(otio_data)

    # Write TLA file
    with open(output_file, 'w') as f:
        f.write(tla_output)

    print(f"Converted {input_file} to {output_file}")


if __name__ == "__main__":
    main()
