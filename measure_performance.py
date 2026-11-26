#!/usr/bin/env python3

"""
measure_performance.py - Measure read/write performance for timeline formats.

Measures:
- File sizes (total, timeline data, metadata)
- Read performance (with and without metadata)
- Write performance (with and without metadata)
- Baseline read time for the OTIO v1 (python) otiocat, where .otio files exist
"""

import os
import shutil
import subprocess
import struct
import time
import tempfile
import sys
from pathlib import Path
from datetime import datetime

PROJECT_ROOT = Path(__file__).parent.resolve()
OTIOCAT = PROJECT_ROOT / "zig-out" / "bin" / "otiocat"

# Public sample files, always measured.
BUILTIN_TEST_FILES = [
    ("premiere_example", PROJECT_ROOT / "otio_sample_data" / "premiere_example"),
    ("screening_example", PROJECT_ROOT / "otio_sample_data" / "screening_example"),
]

# Optional, gitignored list of additional (e.g. non-public) files to measure.
# Format: one `name  path` per line, where path is the base path without an
# extension (.otio/.tla/.tlb are appended).  Relative paths are resolved
# against the repo root.  Blank lines and `#` comments are ignored.
LOCAL_TEST_FILES_LIST = PROJECT_ROOT / "measure_performance.local.txt"


def load_local_test_files(list_path: Path) -> list:
    """Read additional test files from the local (gitignored) list file."""
    if not list_path.exists():
        return []

    entries = []
    with open(list_path) as f:
        for line_num, line in enumerate(f, start=1):
            line = line.split('#', 1)[0].strip()
            if not line:
                continue

            parts = line.split(None, 1)
            if len(parts) != 2:
                print(
                    f"{list_path.name}:{line_num}: expected `name path`, "
                    f"got: {line!r}",
                    file=sys.stderr,
                )
                continue

            name, path_str = parts
            path = Path(path_str.strip()).expanduser()
            if not path.is_absolute():
                path = PROJECT_ROOT / path
            entries.append((name, path))

    return entries


def find_python_otiocat() -> list:
    """Locate the OTIO v1 (python) otiocat command.

    Uses $PY_OTIOCAT if set, otherwise `otiocat` on the PATH, otherwise
    falls back to running the console module with this interpreter.
    Returns None if none can be found.
    """
    env_path = os.environ.get("PY_OTIOCAT")
    if env_path:
        return [env_path]

    on_path = shutil.which("otiocat")
    if on_path:
        return [on_path]

    import importlib.util
    try:
        if importlib.util.find_spec("opentimelineio"):
            return [sys.executable, "-m", "opentimelineio.console.otiocat"]
    except ModuleNotFoundError:
        pass
    return None


PY_OTIOCAT = find_python_otiocat()


def get_python_otio_version() -> str:
    """Return the version of the opentimelineio python package."""
    try:
        import opentimelineio as otio
    except ImportError:
        return "not found"
    return getattr(otio, 'OTIO_VERSION', None) or otio.__version__


def get_binary_file_breakdown(filepath: Path) -> dict:
    """Read the header of a TLB file to get metadata offset."""
    with open(filepath, 'rb') as f:
        magic = f.read(4)
        version = struct.unpack('>I', f.read(4))[0]
        metadata_offset = struct.unpack('>Q', f.read(8))[0]

    total_size = filepath.stat().st_size
    header_size = 16

    # Timeline data is from byte 16 to metadata_offset
    # Metadata is from metadata_offset to end of file
    # Note: metadata_offset of 0 means metadata is not separated (TLB case)
    if metadata_offset == 0:
        # All data is timeline data, no separate metadata section
        timeline_size = total_size - header_size
        metadata_size = 0
    else:
        timeline_size = metadata_offset - header_size if metadata_offset > header_size else total_size - header_size
        metadata_size = total_size - metadata_offset if metadata_offset < total_size else 0

    return {
        'magic': magic.decode('ascii', errors='replace'),
        'version': version,
        'total': total_size,
        'header': header_size,
        'timeline': timeline_size,
        'metadata': metadata_size,
        'metadata_offset': metadata_offset,
    }


def format_size(bytes_val: int) -> str:
    """Format size in human-readable format."""
    if bytes_val < 1024:
        return f"{bytes_val}B"
    elif bytes_val < 1024 * 1024:
        return f"{bytes_val / 1024:.1f}KB"
    else:
        return f"{bytes_val / (1024 * 1024):.2f}MB"


def measure_read_time(filepath: Path, runs: int = 5, skip_metadata: bool = False) -> float:
    """Measure read time using otiocat to convert to /dev/null equivalent."""
    with tempfile.TemporaryDirectory() as tmpdir:
        out_file = Path(tmpdir) / "out.tla"

        # Build command
        cmd = [str(OTIOCAT)]
        if skip_metadata:
            cmd.append("--no-metadata")
        cmd.extend([str(filepath), str(out_file)])

        times = []
        for _ in range(runs):
            start = time.perf_counter()
            subprocess.run(cmd, capture_output=True, check=True)
            elapsed = time.perf_counter() - start
            times.append(elapsed)

        # Return median time
        times.sort()
        return times[len(times) // 2]


def measure_python_otiocat_read_time(filepath: Path, runs: int = 5) -> float:
    """Measure baseline read time: OTIO v1 (python) `otiocat file > /dev/null`."""
    cmd = PY_OTIOCAT + [str(filepath)]

    times = []
    for _ in range(runs):
        start = time.perf_counter()
        subprocess.run(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            check=True,
        )
        elapsed = time.perf_counter() - start
        times.append(elapsed)

    # Return median time
    times.sort()
    return times[len(times) // 2]


def measure_write_time(src_filepath: Path, dst_ext: str, runs: int = 5, skip_metadata: bool = False) -> float:
    """Measure write time for a specific format."""
    with tempfile.TemporaryDirectory() as tmpdir:
        out_file = Path(tmpdir) / f"out{dst_ext}"

        # Build command
        cmd = [str(OTIOCAT)]
        if skip_metadata:
            cmd.append("--no-metadata")
        cmd.extend([str(src_filepath), str(out_file)])

        times = []
        for _ in range(runs):
            # Remove output file if it exists
            if out_file.exists():
                out_file.unlink()

            start = time.perf_counter()
            subprocess.run(cmd, capture_output=True, check=True)
            elapsed = time.perf_counter() - start
            times.append(elapsed)

        # Return median time
        times.sort()
        return times[len(times) // 2]


def format_time(seconds: float) -> str:
    """Format time in human-readable format."""
    if seconds < 0.001:
        return f"{seconds * 1_000_000:.1f}us"
    elif seconds < 1:
        return f"{seconds * 1000:.1f}ms"
    else:
        return f"{seconds:.2f}s"


def anonymize_test_files(entries: list) -> list:
    """Replace the names of (possibly non-public) local test files with
    generic `production_N` labels so the report is safe to publish."""
    return [
        (f"production_{i}", path)
        for i, (_, path) in enumerate(entries, start=1)
    ]


def parse_args():
    import argparse
    parser = argparse.ArgumentParser(
        description="Measure read/write performance for timeline formats."
    )
    parser.add_argument(
        "--anonymize",
        action="store_true",
        help=(
            "hide the names of files from the local test file list and the "
            "path to the python otiocat, for reports that get checked in"
        ),
    )
    return parser.parse_args()


def main():
    args = parse_args()

    if PY_OTIOCAT is None:
        baseline_desc = "not found"
    elif args.anonymize:
        baseline_desc = "python otiocat"
    else:
        baseline_desc = ' '.join(PY_OTIOCAT)

    print(f"# Performance Measurements")
    print(f"")
    print(f"- **Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"- **Platform:** {sys.platform}")
    print(f"- **Build:** ReleaseFast")
    print(f"- **OTIO v1 baseline:** {baseline_desc}")
    print(f"- **OTIO v1 version:** {get_python_otio_version()}")
    if LOCAL_TEST_FILES_LIST.exists():
        print(f"- **Local test files:** `{LOCAL_TEST_FILES_LIST.name}`")
    else:
        print(
            f"- **Local test files:** none "
            f"(`{LOCAL_TEST_FILES_LIST.name}` not found)"
        )
    print(f"")

    # Test files: local (non-public) list first, then built-in public samples
    local_test_files = load_local_test_files(LOCAL_TEST_FILES_LIST)
    if args.anonymize:
        local_test_files = anonymize_test_files(local_test_files)
    test_files = local_test_files + BUILTIN_TEST_FILES

    # File sizes section
    print("## File Sizes")
    print("")
    print("| File | Format | Total | Timeline Data | Metadata |")
    print("|------|--------|-------|---------------|----------|")

    for name, base_path in test_files:
        for ext in ['.otio', '.tla', '.tlb']:
            filepath = Path(str(base_path) + ext)
            if not filepath.exists():
                continue

            total_size = filepath.stat().st_size

            if ext in ['.tlb']:
                breakdown = get_binary_file_breakdown(filepath)
                timeline_str = format_size(breakdown['timeline'])
                metadata_str = format_size(breakdown['metadata'])
            else:
                timeline_str = "-"
                metadata_str = "-"

            print(f"| {name} | {ext} | {format_size(total_size)} | {timeline_str} | {metadata_str} |")

    print("")

    # Baseline read performance (OTIO v1, python otiocat)
    baselines = {}
    print("## Baseline Read Performance (OTIO v1, python)")
    print("")
    print("Time for `otiocat <file>.otio > /dev/null` (median of 5 runs).")
    print("")
    if PY_OTIOCAT is None:
        print("Python otiocat not found (set $PY_OTIOCAT); skipping baseline.")
    else:
        print("| File | Format | Size | Read Time |")
        print("|------|--------|------|-----------|")
        for name, base_path in test_files:
            otio_path = Path(str(base_path) + '.otio')
            if not otio_path.exists():
                continue
            otio_size = format_size(otio_path.stat().st_size)

            try:
                baseline = measure_python_otiocat_read_time(otio_path, runs=5)
                baselines[name] = baseline
                print(f"| {name} | .otio | {otio_size} | {format_time(baseline)} |")
            except Exception as e:
                print(f"| {name} | .otio | {otio_size} | ERROR |")
                print(f"  Error: {e}", file=sys.stderr)

    print("")

    # Read performance section
    print("## Read Performance")
    print("")
    print("Time to read and convert to TLA format (median of 5 runs).")
    print("\"vs OTIO v1\" is the speedup of the with-metadata read relative to")
    print("the python otiocat baseline above (higher is faster).")
    print("")
    print("| File | Format | Size | With Metadata | Without Metadata | Speedup | vs OTIO v1 |")
    print("|------|--------|------|---------------|------------------|---------|------------|")

    for name, base_path in test_files:
        for ext in ['.tla', '.tlb']:
            filepath = Path(str(base_path) + ext)
            if not filepath.exists():
                continue
            size = format_size(filepath.stat().st_size)

            try:
                time_with = measure_read_time(filepath, runs=5, skip_metadata=False)
                time_without = measure_read_time(filepath, runs=5, skip_metadata=True)
                speedup = time_with / time_without if time_without > 0 else 0

                baseline = baselines.get(name)
                if baseline is not None and time_with > 0:
                    vs_v1 = f"{baseline / time_with:.2f}x"
                else:
                    vs_v1 = "-"

                print(f"| {name} | {ext} | {size} | {format_time(time_with)} | {format_time(time_without)} | {speedup:.2f}x | {vs_v1} |")
            except Exception as e:
                print(f"| {name} | {ext} | {size} | ERROR | ERROR | - | - |", file=sys.stderr)
                print(f"  Error: {e}", file=sys.stderr)

    print("")

    # Write performance section
    print("## Write Performance")
    print("")
    print("Time to write from TLA source (median of 5 runs).")
    print("\"Target Size\" is the size of the existing (with-metadata) target")
    print("file next to the source, if there is one.")
    print("")
    print("| File | Target | Source Size | Target Size | With Metadata | Without Metadata | Speedup |")
    print("|------|--------|-------------|-------------|---------------|------------------|---------|")

    for name, base_path in test_files:
        tla_path = Path(str(base_path) + '.tla')
        if not tla_path.exists():
            continue

        source_size = format_size(tla_path.stat().st_size)

        for target_ext in ['.tlb']:
            target_path = Path(str(base_path) + target_ext)
            if target_path.exists():
                target_size = format_size(target_path.stat().st_size)
            else:
                target_size = "-"

            try:
                time_with = measure_write_time(tla_path, target_ext, runs=5, skip_metadata=False)
                time_without = measure_write_time(tla_path, target_ext, runs=5, skip_metadata=True)
                speedup = time_with / time_without if time_without > 0 else 0

                print(f"| {name} | {target_ext} | {source_size} | {target_size} | {format_time(time_with)} | {format_time(time_without)} | {speedup:.2f}x |")
            except Exception as e:
                print(f"| {name} | {target_ext} | {source_size} | {target_size} | ERROR | ERROR | - |", file=sys.stderr)
                print(f"  Error: {e}", file=sys.stderr)

    print("")


if __name__ == "__main__":
    main()
