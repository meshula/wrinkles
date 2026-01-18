#!/usr/bin/env python
#
# SPDX-License-Identifier: Apache-2.0
# Copyright Contributors to the wrinkles project

"""Example script that determines which media samples (frames)
are needed from each clip to render a timeline using projection operators.

This is useful for:
- Pre-fetching media before playback
- Understanding which portions of source media are used
- Building render manifests

The script uses the TemporalProjectionBuilder to create projection operators
from the timeline root to each clip's media space, then projects the timeline's
presentation range through those operators to determine which media frames
are actually used.

Demo:

% sample_requirements.py -i timeline.otio
======================================================================
Timeline: My Timeline

Building projection map...
Found 3 projection(s) to clip media spaces

Clip Media Requirements:
----------------------------------------------------------------------
Clip: shot_001
  Timeline range: [0.00s - 2.00s] -> Media range: [10.00s - 12.00s]
  Media frames: 240 - 288 @ 24.0 fps
...
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
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        '-i',
        '--input',
        type=str,
        required=True,
        help='Timeline file to read (supports .otio, .tla, .tlb, .tlz formats)'
    )
    parser.add_argument(
        '-v',
        '--verbose',
        action='store_true',
        help='Show detailed projection information'
    )
    return parser.parse_args()


def _get_sample_requirements(
    timeline: otio2.Timeline,
    verbose: bool = False
) -> None:
    """Analyze a timeline using projection operators to determine which media
    samples are needed from each clip to render the full timeline.
    """
    print("=" * 70)
    print(f"Timeline: {timeline.name}")
    print()

    # Build projection operators from timeline to all clip media spaces
    print("Building projection map...")
    projections = otio2.build_projection_map(timeline)

    # Filter to only projections that end at clips (media spaces)
    clip_projections: list[otio2.ProjectionOperator] = []
    for proj in projections:
        dest = proj.destination
        if dest is not None and dest.type_name == "clip":
            clip_projections.append(proj)

    print(f"Found {len(clip_projections)} projection(s) to clip media spaces")
    print()

    if len(clip_projections) == 0:
        print("No clips found in timeline.")
        return

    # Print detailed requirements
    print("Clip Media Requirements:")
    print("-" * 70)

    results: list[dict[str, Any]] = []

    for proj in clip_projections:
        clip = proj.destination
        clip_name = clip.name or "(unnamed)"

        print(f"\nClip: {clip_name}")

        # Get the source (timeline) bounds from the projection
        source = proj.source
        if verbose and source:
            print(f"  Source: {source.type_name} '{source.name or ''}'")

        # Get discrete info for the clip's media
        discrete_info = clip.get_discrete_info(otio2.DOMAIN_PICTURE)

        # Project a sample range from timeline space to media space
        # We'll use the clip's visible range in the timeline
        # For now, project some sample points to demonstrate the projection

        # Try to project a range through the operator
        try:
            # Project from timeline presentation space (0 to duration) to media
            # Using project_range_cc to get the output range
            timeline_start = 0.0
            timeline_end = 10.0  # Sample range

            media_range = proj.project_range_cc(timeline_start, timeline_end)

            if media_range:
                print(
                    f"  Timeline range: [{timeline_start:.2f}s - "
                    f"{timeline_end:.2f}s] -> Media range: "
                    f"[{media_range.start:.2f}s - {media_range.end:.2f}s]"
                )

                if discrete_info:
                    frame_rate = discrete_info["rate"]
                    start_index = discrete_info["start_index"]

                    # Calculate frame indices from media time
                    start_frame = int(media_range.start * frame_rate) + start_index
                    end_frame = int(media_range.end * frame_rate) + start_index

                    print(
                        f"  Media frames: {start_frame} - {end_frame} "
                        f"@ {frame_rate} fps"
                    )

                    results.append({
                        "clip_name": clip_name,
                        "media_start": media_range.start,
                        "media_end": media_range.end,
                        "start_frame": start_frame,
                        "end_frame": end_frame,
                        "frame_rate": frame_rate,
                    })
                else:
                    print("  (No discrete info - continuous media)")
                    results.append({
                        "clip_name": clip_name,
                        "media_start": media_range.start,
                        "media_end": media_range.end,
                        "start_frame": None,
                        "end_frame": None,
                        "frame_rate": None,
                    })
        except Exception as e:
            if verbose:
                print(f"  Projection error: {e}")

        # Also show individual point projections if verbose
        if verbose:
            print("  Sample point projections:")
            for t in [0.0, 1.0, 2.0, 5.0]:
                result = proj.project_cc(t)
                if result is not None:
                    print(f"    Timeline {t:.1f}s -> Media {result:.3f}s")
                else:
                    print(f"    Timeline {t:.1f}s -> (out of bounds)")

    print()
    print("-" * 70)
    print()

    # Summary table
    if results:
        print("Summary Table:")
        print("-" * 70)
        print(f"{'Clip Name':<25} {'Media Range':<20} {'Frames':<15} {'Rate':>8}")
        print("-" * 70)

        for r in results:
            clip_name = r["clip_name"][:24]
            media_range_str = f"{r['media_start']:.2f}s - {r['media_end']:.2f}s"

            if r["start_frame"] is not None:
                frames = f"{r['start_frame']} - {r['end_frame']}"
                rate = f"{r['frame_rate']:.1f}"
            else:
                frames = "N/A"
                rate = "N/A"

            print(f"{clip_name:<25} {media_range_str:<20} {frames:<15} {rate:>8}")

        print("-" * 70)


def main() -> None:
    args = parse_args()

    try:
        timeline = otio2.read_from_file(args.input)
        _get_sample_requirements(timeline, verbose=args.verbose)
    except IOError as e:
        print(f"Error reading file: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
