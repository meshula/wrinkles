#!/usr/bin/env python3
"""
Traverse Hierarchy - Wrinkles Python Bindings Example

This example demonstrates traversing the entire timeline hierarchy,
printing indented structure similar to the C test output.

Usage:
    python traverse_hierarchy.py <path_to_otio_file>
"""

import sys
import wrinkles


def print_item(item, indent=0):
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
            print_item(child, indent + 1)
    except TypeError:
        # Item doesn't support len() - it's a leaf node
        pass


def traverse_timeline(filepath):
    """Read a timeline and traverse its entire hierarchy."""

    print(f"Reading: {filepath}")
    print()

    # Read with context manager for automatic cleanup
    with wrinkles.read_from_file(filepath) as timeline:
        print_item(timeline)


def main():
    if len(sys.argv) < 2:
        print("Usage: python traverse_hierarchy.py <path_to_otio_file>")
        print("\nExample:")
        print("  python traverse_hierarchy.py ../../sample_otio_files/multiple_track.otio")
        sys.exit(1)

    filepath = sys.argv[1]

    try:
        traverse_timeline(filepath)
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
