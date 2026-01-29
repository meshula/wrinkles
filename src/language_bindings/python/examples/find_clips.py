#!/usr/bin/env python
#
# SPDX-License-Identifier: Apache-2.0
# Copyright Contributors to the wrinkles project

"""Example script that reads a timeline and finds all clips,
optionally filtering by name.

Demo:

% find_clips.py -i timeline.otio
Timeline: My Timeline
Found 5 clip(s):
  1. shot_001
  2. shot_002
  ...

% find_clips.py -i timeline.otio -s shot_001
Timeline: My Timeline
Found 1 clip(s):
  1. shot_001
"""

from __future__ import annotations

import argparse
import sys
from typing import Any, Optional

import wrinkles as otio2


def parse_args() -> argparse.Namespace:
    """Parse arguments out of sys.argv."""
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawTextHelpFormatter,
    )
    # @TODO: verify that .tlc shouldn't be mentioned here
    parser.add_argument(
        '-i',
        '--input',
        type=str,
        required=True,
        help='Timeline file to read (supports .otio, .tla, .tlb, .tlz)'
    )
    parser.add_argument(
        '-s',
        '--search',
        type=str,
        default=None,
        help='Optional search term to filter clips by name (case-insensitive)'
    )
    return parser.parse_args()


def _find_all_clips(
    container: Any,
    clips: Optional[list[otio2.Clip]] = None
) -> list[otio2.Clip]:
    """Recursively find all clips in a container."""
    if clips is None:
        clips = []

    try:
        for item in container:
            if isinstance(item, otio2.Clip):
                clips.append(item)
            elif isinstance(item, (otio2.Track, otio2.Stack, otio2.Warp)):
                # Container types - recurse into them
                _find_all_clips(item, clips)
    except TypeError:
        # Not iterable
        pass

    return clips


def main() -> None:
    args = parse_args()

    try:
        timeline = otio2.read_from_file(args.input)

        print(f"Timeline: {timeline.name}")
        print()

        # Find all clips
        clips = _find_all_clips(timeline.tracks)

        # Filter by search term if provided
        if args.search:
            clips = [
                c for c in clips
                if c.name and args.search.lower() in c.name.lower()
            ]

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


if __name__ == '__main__':
    main()
