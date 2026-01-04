#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright Contributors to the wrinkles project

"""
Convert OTIO files to Ziggy format.

Usage:
    python convert_files.py -d OUTPUT_DIR input1.otio input2.otio ...
"""

import argparse
import os
import subprocess


def _parsed_args():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument(
        "input_files",
        nargs='+',
        help="files to operate on",
    )
    parser.add_argument(
        "-d",
        "--output-dir",
        required=True,
        type=str,
        help="Output filename",
    )
    return parser.parse_args()


def main():
    """Main entry point for the script."""
    args = _parsed_args()

    for fname in args.input_files:
        # Construct output path
        new_name = os.path.abspath(
            os.path.join(
                args.output_dir,
                os.path.basename(fname) + ".ziggy",
            )
        )

        # Run conversion command
        cmd = f"zig-out/bin/otio_dump_ziggy {fname} {new_name}"
        print(cmd)

        subprocess.run(cmd.split(" "))


if __name__ == "__main__":
    main()
