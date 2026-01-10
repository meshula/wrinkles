#!/usr/bin/env python
#
# SPDX-License-Identifier: Apache-2.0
# Copyright Contributors to the wrinkles project

"""Example script that traverses the entire timeline hierarchy,
printing indented structure similar to the C test output.

Demo:

% traverse_hierarchy.py -i timeline.otio
timeline 'My Timeline'
  stack 'tracks'
    track 'Video'
      clip 'shot_001'
      gap
      clip 'shot_002'
"""

from __future__ import annotations

import argparse
import sys
from typing import Any

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
        help='Timeline file to read (supports .otio, .tla, .tlb, .tlfb, .tlz)'
    )
    return parser.parse_args()


def _print_item(item: Any, indent: int = 0) -> None:
    """Recursively print a composition item and its children."""
    prefix = "  " * indent

    item_type = item.type_name
    item_name = item.name or ""

    # Print the item
    if item_name:
        print(f"{prefix}{item_type} '{item_name}'")
    else:
        print(f"{prefix}{item_type}")

    # If this item has children, print them recursively
    try:
        child_count = len(item)
        for i in range(child_count):
            child = item[i]
            _print_item(child, indent + 1)
    except TypeError:
        # Item doesn't support len() - it's a leaf node
        pass


def main() -> None:
    args = parse_args()

    try:
        # Read with context manager for automatic cleanup
        with otio2.read_from_file(args.input) as timeline:
            _print_item(timeline)
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
