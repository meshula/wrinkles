#!/usr/bin/env python3
"""
Find Clips - Wrinkles Python Bindings Example

This example demonstrates finding all clips in a timeline,
similar to OpenTimelineIO's conform.py example.

Usage:
    python find_clips.py <path_to_otio_file> [search_term]
"""

import sys
import wrinkles


def find_all_clips(container, clips=None):
    """Recursively find all clips in a container."""
    if clips is None:
        clips = []

    try:
        for item in container:
            if isinstance(item, wrinkles.Clip):
                clips.append(item)
            elif isinstance(item, (wrinkles.Track, wrinkles.Stack, wrinkles.Warp)):
                # Container types - recurse into them
                find_all_clips(item, clips)
    except TypeError:
        # Not iterable
        pass

    return clips


def main():
    if len(sys.argv) < 2:
        print("Usage: python find_clips.py <path_to_otio_file> [search_term]")
        print("\nExample:")
        print("  python find_clips.py ../../sample_otio_files/multiple_track.otio")
        print("  python find_clips.py ../../sample_otio_files/multiple_track.otio Clip-001")
        sys.exit(1)

    filepath = sys.argv[1]
    search_term = sys.argv[2] if len(sys.argv) > 2 else None

    try:
        timeline = wrinkles.read_from_file(filepath)

        print(f"Timeline: {timeline.name}")
        print()

        # Find all clips
        clips = find_all_clips(timeline.tracks)

        # Filter by search term if provided
        if search_term:
            clips = [c for c in clips if c.name and search_term.lower() in c.name.lower()]

        print(f"Found {len(clips)} clip(s):")
        print("-" * 40)

        for i, clip in enumerate(clips):
            print(f"  {i + 1}. {clip.name or '(unnamed)'}")

    except IOError as e:
        print(f"Error reading file: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
