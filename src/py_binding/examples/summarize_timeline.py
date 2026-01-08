#!/usr/bin/env python3
"""
Summarize Timeline - Wrinkles Python Bindings Example

This example demonstrates reading an OTIO file and summarizing its structure,
similar to OpenTimelineIO's summarize_timing.py example.

Usage:
    python summarize_timeline.py <path_to_otio_file>
"""

import sys
import wrinkles


def summarize_timeline(filepath):
    """Read a timeline and print a summary of its structure."""

    # Read the timeline
    print(f"Reading: {filepath}")
    timeline = wrinkles.read_from_file(filepath)

    print(f"\n{'=' * 60}")
    print(f"Timeline: {timeline.name}")
    print(f"{'=' * 60}")

    # Count items by type
    track_count = 0
    clip_count = 0
    gap_count = 0

    # Iterate through tracks
    for track_idx, track in enumerate(timeline.tracks):
        track_count += 1
        print(f"\nTrack {track_idx}: {track.name or '(unnamed)'}")
        print("-" * 40)

        # Iterate through track contents
        for item_idx, item in enumerate(track):
            item_type = type(item).__name__
            item_name = item.name or "(unnamed)"

            if isinstance(item, wrinkles.Clip):
                clip_count += 1
                print(f"  [{item_idx}] Clip: {item_name}")
            elif isinstance(item, wrinkles.Gap):
                gap_count += 1
                print(f"  [{item_idx}] Gap")
            elif isinstance(item, wrinkles.Warp):
                print(f"  [{item_idx}] Warp: {item_name}")
                # Warps can have children
                if len(item) > 0:
                    for child_idx, child in enumerate(item):
                        child_type = type(child).__name__
                        child_name = child.name or "(unnamed)"
                        print(f"      [{child_idx}] {child_type}: {child_name}")
            elif isinstance(item, wrinkles.Transition):
                print(f"  [{item_idx}] Transition: {item_name}")
            else:
                print(f"  [{item_idx}] {item_type}: {item_name}")

    # Print summary
    print(f"\n{'=' * 60}")
    print("Summary:")
    print(f"  Tracks: {track_count}")
    print(f"  Clips: {clip_count}")
    print(f"  Gaps: {gap_count}")
    print(f"{'=' * 60}")


def main():
    if len(sys.argv) < 2:
        print("Usage: python summarize_timeline.py <path_to_otio_file>")
        print("\nExample:")
        print("  python summarize_timeline.py ../../sample_otio_files/multiple_track.otio")
        sys.exit(1)

    filepath = sys.argv[1]

    try:
        summarize_timeline(filepath)
    except IOError as e:
        print(f"Error reading file: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
