__doc__ = """ Convert files to ziggy """

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
    args = _parsed_args()

    for fname in args.input_files:
        new_name = os.path.abspath(
            os.path.join(
                args.output_dir,
                os.path.basename(fname) + ".ziggy",
            )
        )
        cmd = f"zig-out/bin/otio_dump_ziggy {fname} {new_name}"
        print(cmd)

        subprocess.run(cmd.split(" "))

if __name__ == "__main__":
    main()
