#!/usr/bin/env python3
"""
Sample Requirements - Wrinkles Python Bindings Example

This example demonstrates how to determine which media samples (frames)
are needed from each clip to render a timeline.

This is useful for:
- Pre-fetching media before playback
- Understanding which portions of source media are used
- Building render manifests

Usage:
    python sample_requirements.py <path_to_otio_file>
"""

import sys
import wrinkles


def find_all_clips_with_info(container, track_name=None, clips=None, timeline_offset=0.0):
    """
    Recursively find all clips in a container with their timeline positions.

    Returns a list of dicts with clip info including:
    - clip: the Clip object
    - track: name of the containing track
    - timeline_start: start time in timeline (presentation) space
    - timeline_end: end time in timeline (presentation) space
    """
    if clips is None:
        clips = []

    current_offset = timeline_offset

    try:
        for item in container:
            item_type = item.type_name

            if item_type == "track":
                # Tracks are sequential - items play one after another
                find_all_clips_with_info(
                    item,
                    track_name=item.name,
                    clips=clips,
                    timeline_offset=0.0  # Track children start at track's beginning
                )
            elif item_type == "stack":
                # Stacks are simultaneous - all children share the same time
                find_all_clips_with_info(
                    item,
                    track_name=track_name,
                    clips=clips,
                    timeline_offset=current_offset
                )
            elif item_type == "clip":
                # Get the clip's discrete info to find its duration
                discrete_info = item.get_discrete_info(wrinkles.DOMAIN_PICTURE)

                # For clips, we need to determine their duration in the timeline
                # This comes from their media bounds transformed by any time effects
                clips.append({
                    "clip": item,
                    "track": track_name,
                    "timeline_start": current_offset,
                    "discrete_info": discrete_info,
                })
            elif item_type == "gap":
                # Gaps take up time but have no media
                pass
            elif item_type == "warp":
                # Time warp - recurse into its child
                find_all_clips_with_info(
                    item,
                    track_name=track_name,
                    clips=clips,
                    timeline_offset=current_offset
                )

    except TypeError:
        # Not iterable
        pass

    return clips


def get_sample_requirements(filepath):
    """
    Analyze a timeline and determine which media samples are needed
    from each clip to render the full timeline.
    """
    print(f"Analyzing: {filepath}")
    print("=" * 70)
    print()

    # Read the timeline
    timeline = wrinkles.read_from_file(filepath)
    print(f"Timeline: {timeline.name}")
    print()

    # Find all clips with their timeline positions
    clips_info = find_all_clips_with_info(timeline.tracks)

    print(f"Found {len(clips_info)} clip(s) in timeline")
    print()

    # Print detailed requirements
    print("Clip Media Requirements:")
    print("-" * 70)

    for info in clips_info:
        clip = info["clip"]
        track = info["track"] or "(no track)"
        discrete_info = info["discrete_info"]

        print(f"\nClip: {clip.name or '(unnamed)'}")
        print(f"  Track: {track}")

        if discrete_info:
            frame_rate = discrete_info["rate"]
            start_index = discrete_info["start_index"]
            print(f"  Media frame rate: {frame_rate} fps")
            print(f"  Media start index: {start_index}")

            # The clip's media space is accessed via continuous_to_discrete
            # Media bounds represent what portion of the source is used
            sample_media_times = [0.0, 0.5, 1.0, 2.0]
            print(f"  Sample frame lookups:")
            for t in sample_media_times:
                frame = clip.continuous_to_discrete(t)
                print(f"    Media time {t:.1f}s -> Frame {frame}")
        else:
            print("  (No discrete info - continuous media)")

    print()
    print("-" * 70)
    print()

    # Summary table
    print("Summary Table:")
    print("-" * 70)
    print(f"{'Track':<15} {'Clip Name':<20} {'Frame Rate':>12} {'Start Idx':>10}")
    print("-" * 70)

    for info in clips_info:
        clip = info["clip"]
        track = (info["track"] or "-")[:14]
        clip_name = (clip.name or "(unnamed)")[:19]
        discrete_info = info["discrete_info"]

        if discrete_info:
            frame_rate = f"{discrete_info['rate']:.1f}"
            start_idx = str(discrete_info["start_index"])
        else:
            frame_rate = "N/A"
            start_idx = "N/A"

        print(f"{track:<15} {clip_name:<20} {frame_rate:>12} {start_idx:>10}")

    print("-" * 70)


def main():
    if len(sys.argv) < 2:
        print("Usage: python sample_requirements.py <path_to_otio_file>")
        print("\nThis script analyzes a timeline and shows which media samples")
        print("(frames) are needed from each clip to render the timeline.")
        print("\nExample:")
        print("  python sample_requirements.py ../../sample_otio_files/multiple_track.otio")
        sys.exit(1)

    filepath = sys.argv[1]

    try:
        get_sample_requirements(filepath)
    except IOError as e:
        print(f"Error reading file: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
