#!/usr/bin/env python3

"""update the modules from zig-gamedev"""

import argparse
import glob
import os
import shutil
import tempfile


def _parse_args():
    """ parse arguments out of sys.argv """
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument(
        '-d',
        '--dryrun',
        action="store_true",
        default=False,
        help="Print instead of doing"
    )
    parser.add_argument(
        '-p',
        '--path',
        default=None,
        required=True,
        help="Path to cloned zig-gamedev"
    )
    return parser.parse_args()


def main():
    path_root = os.path.dirname(__file__)
    args = _parse_args()

    if not os.path.exists(args.path):
        raise RuntimeError(f"Path doesn't exist: {args.path}")

    dirs_to_update = [d for d in glob.glob("*") if os.path.isdir(d)]

    print(f"Found directories: {dirs_to_update}")
    with tempfile.TemporaryDirectory("zig-gamedev-update") as tmpdir:
        print(f"making temp directory for current code: {tmpdir}")

        for d in dirs_to_update:
            destination_path = os.path.join(path_root, d)

            to_path_tmp = os.path.join(tmpdir, d)
            print(f"Moving {destination_path} to {to_path_tmp}")
            shutil.move(destination_path, to_path_tmp)

            from_path = os.path.join(args.path, "libs", d)
            if not os.path.exists(from_path):
                print(
                    f"WARNING: skipping {from_path}, does not exist in source"
                )
                continue

            print(f"Copying {from_path} to {destination_path}")
            shutil.copytree(from_path, destination_path)

    print("Done.")


if __name__ == "__main__":
    main()
