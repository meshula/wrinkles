#!/usr/bin/env python
#
# SPDX-License-Identifier: Apache-2.0
# Copyright Contributors to the wrinkles project

"""Example script that reads a timeline and prints a summary of its structure,
similar to OpenTimelineIO's summarize_timing.py example.

Demo:

% summarize_timeline.py -i timeline.otio
============================================================
Timeline: My Timeline
============================================================

Track 0: Video
----------------------------------------
  [0] Clip: shot_001
  [1] Gap
  [2] Clip: shot_002
...
"""

from __future__ import annotations

import argparse
import sys

import wrinkles as otio2


def parse_args() -> argparse.Namespace:
    """Parse arguments out of sys.argv."""
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        '-i',
        '--input',
        type=str,
        required=True,
        help='Timeline file to read (supports .otio, .tla, .tlb, .tlz)'
    )
    return parser.parse_args()


def _summarize_timeline(timeline: otio2.Timeline) -> None:
    """Print a summary of a timeline's structure."""

    print(f"{'=' * 60}")
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

            if isinstance(item, otio2.Clip):
                clip_count += 1
                print(f"  [{item_idx}] Clip: {item_name}")
            elif isinstance(item, otio2.Gap):
                gap_count += 1
                print(f"  [{item_idx}] Gap")
            elif isinstance(item, otio2.Warp):
                print(f"  [{item_idx}] Warp: {item_name}")
                # Warps can have children
                if len(item) > 0:
                    for child_idx, child in enumerate(item):
                        child_type = type(child).__name__
                        child_name = child.name or "(unnamed)"
                        print(f"      [{child_idx}] {child_type}: {child_name}")
            elif isinstance(item, otio2.Transition):
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


def main() -> None:
    args = parse_args()

    try:
        timeline = otio2.read_from_file(args.input)
        _summarize_timeline(timeline)
    except IOError as e:
        print(f"Error reading file: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
