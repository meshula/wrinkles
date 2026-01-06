#!/usr/bin/env python3
"""
wrinkles_format_comparisons.py - Compare performance and correctness across timeline file formats.

Compares .otio, .ziggy, .tlb, and .tlfb formats using hyperfine benchmarks.
"""

import subprocess
import argparse
import json
import sys
import tempfile
from pathlib import Path
from datetime import datetime


def log(msg: str) -> None:
    """Print timestamped log message."""
    timestamp = datetime.now().strftime("%H:%M:%S")
    print(f"[{timestamp}] {msg}", file=sys.stderr)


def run_cmd(cmd: list[str], capture: bool = True, check: bool = True) -> subprocess.CompletedProcess:
    """Execute shell command and return result."""
    log(f"Running: {' '.join(cmd)}")
    return subprocess.run(
        cmd,
        capture_output=capture,
        text=True,
        check=check,
    )


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Compare performance and correctness across timeline file formats"
    )
    parser.add_argument(
        "--test-files-dir",
        type=Path,
        default=Path("test_files_ziggy"),
        help="Directory containing test files (default: test_files_ziggy)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Output file for results (default: stdout)",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Skip the zig build step",
    )
    parser.add_argument(
        "--warmup",
        type=int,
        default=3,
        help="Hyperfine warmup runs (default: 3)",
    )
    parser.add_argument(
        "--runs",
        type=int,
        default=10,
        help="Hyperfine benchmark runs (default: 10)",
    )
    return parser.parse_args()


# Project root directory
PROJECT_ROOT = Path(__file__).parent.resolve()

# Binary paths
OTIOCAT = PROJECT_ROOT / "zig-out" / "bin" / "otiocat"
HIERARCHY_VIEW = PROJECT_ROOT / "zig-out" / "bin" / "otio_hierarchy_view"
MEASURE_TIMELINE = PROJECT_ROOT / "zig-out" / "bin" / "otio_measure_timeline"

# Format directories
FORMAT_DIRS = {
    "ziggy": PROJECT_ROOT / "test_files_ziggy",
    "tlb": PROJECT_ROOT / "test_files_binary",
    "tlfb": PROJECT_ROOT / "test_files_tlfb",
    "otio": PROJECT_ROOT / "test_files",
}

# Format extensions
FORMAT_EXT = {
    "ziggy": ".ziggy",
    "tlb": ".tlb",
    "tlfb": ".tlfb",
    "otio": ".otio",
}


def build_release() -> bool:
    """Build the project in ReleaseFast mode."""
    log("Building project with ReleaseFast optimization...")
    try:
        run_cmd(["zig", "build", "-Doptimize=ReleaseFast"])
        log("Build successful")
        return True
    except subprocess.CalledProcessError as e:
        log(f"Build failed: {e}")
        return False


def verify_binaries() -> bool:
    """Verify required binaries exist."""
    missing = []
    for name, path in [("otiocat", OTIOCAT), ("otio_hierarchy_view", HIERARCHY_VIEW)]:
        if not path.exists():
            missing.append(name)
    if missing:
        log(f"Missing binaries: {', '.join(missing)}")
        return False
    log("All required binaries found")
    return True


def discover_test_files(base_dir: Path) -> dict[str, dict[str, Path]]:
    """
    Find matching files across formats.

    Returns dict mapping basename to dict of format -> path.
    Example: {"good_dino": {"ziggy": Path(...), "tlb": Path(...), ...}}
    """
    test_files = {}

    # Start with ziggy files as the base
    ziggy_dir = FORMAT_DIRS["ziggy"]
    if not ziggy_dir.exists():
        log(f"Ziggy directory not found: {ziggy_dir}")
        return test_files

    for ziggy_file in ziggy_dir.glob("*.ziggy"):
        basename = ziggy_file.stem
        test_files[basename] = {"ziggy": ziggy_file}

        # Look for corresponding files in other formats
        for fmt, ext in FORMAT_EXT.items():
            if fmt == "ziggy":
                continue
            fmt_dir = FORMAT_DIRS[fmt]
            fmt_file = fmt_dir / f"{basename}{ext}"
            if fmt_file.exists():
                test_files[basename][fmt] = fmt_file

    log(f"Discovered {len(test_files)} test file sets")
    for name, formats in test_files.items():
        log(f"  {name}: {', '.join(formats.keys())}")

    return test_files


def get_file_sizes(test_files: dict[str, dict[str, Path]]) -> dict[str, dict[str, int]]:
    """Get file sizes for all test files."""
    sizes = {}
    for name, formats in test_files.items():
        sizes[name] = {}
        for fmt, path in formats.items():
            sizes[name][fmt] = path.stat().st_size
    return sizes


def run_hyperfine(
    commands: dict[str, str],
    warmup: int,
    runs: int,
    export_json: Path,
) -> dict[str, dict]:
    """
    Run hyperfine benchmark on multiple commands.

    Returns dict mapping command name to timing results.
    """
    cmd = [
        "hyperfine",
        "--warmup", str(warmup),
        "--runs", str(runs),
        "--export-json", str(export_json),
    ]

    for name, command in commands.items():
        cmd.extend(["--command-name", name, command])

    try:
        run_cmd(cmd)
    except subprocess.CalledProcessError as e:
        log(f"Hyperfine failed: {e}")
        return {}

    with open(export_json) as f:
        data = json.load(f)

    results = {}
    for result in data.get("results", []):
        name = result["command"]
        results[name] = {
            "mean": result["mean"],
            "stddev": result["stddev"],
            "min": result["min"],
            "max": result["max"],
            "median": result.get("median", result["mean"]),
        }

    return results


def benchmark_read_performance(
    test_files: dict[str, dict[str, Path]],
    warmup: int,
    runs: int,
) -> dict[str, dict[str, dict]]:
    """
    Benchmark read performance for each format.

    Measures time to read and convert each format to ziggy output.
    Returns dict mapping file name to format timing results.
    """
    log("Benchmarking read performance...")
    results = {}

    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir = Path(tmpdir)

        for name, formats in test_files.items():
            log(f"  Benchmarking {name}...")
            commands = {}

            for fmt, path in formats.items():
                out_file = tmpdir / f"{name}_{fmt}.ziggy"
                commands[fmt] = f"{OTIOCAT} {path} {out_file}"

            if len(commands) < 2:
                log(f"    Skipping {name}: need at least 2 formats")
                continue

            json_out = tmpdir / f"{name}_read.json"
            results[name] = run_hyperfine(commands, warmup, runs, json_out)

    return results


def benchmark_write_performance(
    test_files: dict[str, dict[str, Path]],
    warmup: int,
    runs: int,
) -> dict[str, dict[str, dict]]:
    """
    Benchmark write performance (ziggy -> binary formats).

    Measures time to convert ziggy to TLB and TLFB.
    Returns dict mapping file name to format timing results.
    """
    log("Benchmarking write performance...")
    results = {}

    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir = Path(tmpdir)

        for name, formats in test_files.items():
            if "ziggy" not in formats:
                continue

            log(f"  Benchmarking {name}...")
            ziggy_path = formats["ziggy"]
            commands = {}

            # Ziggy -> TLB
            tlb_out = tmpdir / f"{name}.tlb"
            commands["ziggy→tlb"] = f"{OTIOCAT} {ziggy_path} {tlb_out}"

            # Ziggy -> TLFB
            tlfb_out = tmpdir / f"{name}.tlfb"
            commands["ziggy→tlfb"] = f"{OTIOCAT} {ziggy_path} {tlfb_out}"

            json_out = tmpdir / f"{name}_write.json"
            results[name] = run_hyperfine(commands, warmup, runs, json_out)

    return results


def benchmark_tool_performance(
    test_files: dict[str, dict[str, Path]],
    warmup: int,
    runs: int,
) -> dict[str, dict[str, dict]]:
    """
    Benchmark tool execution speed across formats.

    Measures otio_hierarchy_view performance.
    Returns dict mapping file name to format timing results.
    """
    log("Benchmarking tool performance...")
    results = {}

    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir = Path(tmpdir)

        for name, formats in test_files.items():
            log(f"  Benchmarking {name}...")
            commands = {}

            for fmt, path in formats.items():
                commands[fmt] = f"{HIERARCHY_VIEW} {path}"

            if len(commands) < 2:
                continue

            json_out = tmpdir / f"{name}_tool.json"
            results[name] = run_hyperfine(commands, warmup, runs, json_out)

    return results


def compare_otiocat_output(
    test_files: dict[str, dict[str, Path]],
) -> dict[str, dict]:
    """
    Verify identical ziggy output from all formats.

    Converts each format to ziggy and compares file contents.
    Returns dict with pass/fail status and any differences.
    """
    log("Comparing otiocat output across formats...")
    results = {}

    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir = Path(tmpdir)

        for name, formats in test_files.items():
            log(f"  Comparing {name}...")
            outputs = {}

            # Convert each format to ziggy
            for fmt, path in formats.items():
                out_file = tmpdir / f"{name}_{fmt}.ziggy"
                try:
                    run_cmd([str(OTIOCAT), str(path), str(out_file)])
                    outputs[fmt] = out_file
                except subprocess.CalledProcessError as e:
                    log(f"    Failed to convert {fmt}: {e}")
                    outputs[fmt] = None

            # Compare outputs
            valid_outputs = {k: v for k, v in outputs.items() if v is not None}
            if len(valid_outputs) < 2:
                results[name] = {"status": "SKIP", "reason": "Not enough valid outputs"}
                continue

            reference_fmt = list(valid_outputs.keys())[0]
            reference_content = valid_outputs[reference_fmt].read_text()
            all_match = True
            differences = []

            for fmt, path in valid_outputs.items():
                if fmt == reference_fmt:
                    continue
                content = path.read_text()
                if content != reference_content:
                    all_match = False
                    differences.append(f"{reference_fmt} vs {fmt}")

            results[name] = {
                "status": "PASS" if all_match else "FAIL",
                "differences": differences,
                "formats_tested": list(valid_outputs.keys()),
            }

    return results


def compare_hierarchy_output(
    test_files: dict[str, dict[str, Path]],
) -> dict[str, dict]:
    """
    Verify identical hierarchy view from all formats.

    Runs otio_hierarchy_view on each format and compares text output.
    Returns dict with pass/fail status.
    """
    log("Comparing hierarchy view output across formats...")
    results = {}

    for name, formats in test_files.items():
        log(f"  Comparing {name}...")
        outputs = {}

        for fmt, path in formats.items():
            try:
                result = run_cmd([str(HIERARCHY_VIEW), str(path)])
                # Skip the first line which may contain the file path
                lines = result.stdout.strip().split("\n")
                outputs[fmt] = "\n".join(lines[1:]) if len(lines) > 1 else ""
            except subprocess.CalledProcessError as e:
                log(f"    Failed for {fmt}: {e}")
                outputs[fmt] = None

        valid_outputs = {k: v for k, v in outputs.items() if v is not None}
        if len(valid_outputs) < 2:
            results[name] = {"status": "SKIP", "reason": "Not enough valid outputs"}
            continue

        reference_fmt = list(valid_outputs.keys())[0]
        reference_content = valid_outputs[reference_fmt]
        all_match = True
        differences = []

        for fmt, content in valid_outputs.items():
            if fmt == reference_fmt:
                continue
            if content != reference_content:
                all_match = False
                differences.append(f"{reference_fmt} vs {fmt}")

        results[name] = {
            "status": "PASS" if all_match else "FAIL",
            "differences": differences,
            "formats_tested": list(valid_outputs.keys()),
        }

    return results


def verify_roundtrip(
    test_files: dict[str, dict[str, Path]],
) -> dict[str, dict]:
    """
    Verify format roundtrip integrity.

    Tests:
    - ziggy -> tlfb -> ziggy
    - ziggy -> tlb -> ziggy
    - Cross-format: tlfb -> tlb -> tlfb -> ziggy

    Returns dict with pass/fail status for each test.
    """
    log("Verifying roundtrip integrity...")
    results = {}

    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir = Path(tmpdir)

        for name, formats in test_files.items():
            if "ziggy" not in formats:
                continue

            log(f"  Testing {name}...")
            ziggy_path = formats["ziggy"]
            original_content = ziggy_path.read_text()
            tests = {}

            # Test: ziggy -> tlfb -> ziggy
            try:
                tlfb_temp = tmpdir / f"{name}_rt.tlfb"
                ziggy_from_tlfb = tmpdir / f"{name}_from_tlfb.ziggy"
                run_cmd([str(OTIOCAT), str(ziggy_path), str(tlfb_temp)])
                run_cmd([str(OTIOCAT), str(tlfb_temp), str(ziggy_from_tlfb)])
                tests["ziggy→tlfb→ziggy"] = (
                    "PASS" if ziggy_from_tlfb.read_text() == original_content else "FAIL"
                )
            except subprocess.CalledProcessError:
                tests["ziggy→tlfb→ziggy"] = "ERROR"

            # Test: ziggy -> tlb -> ziggy
            try:
                tlb_temp = tmpdir / f"{name}_rt.tlb"
                ziggy_from_tlb = tmpdir / f"{name}_from_tlb.ziggy"
                run_cmd([str(OTIOCAT), str(ziggy_path), str(tlb_temp)])
                run_cmd([str(OTIOCAT), str(tlb_temp), str(ziggy_from_tlb)])
                tests["ziggy→tlb→ziggy"] = (
                    "PASS" if ziggy_from_tlb.read_text() == original_content else "FAIL"
                )
            except subprocess.CalledProcessError:
                tests["ziggy→tlb→ziggy"] = "ERROR"

            # Cross-format test: tlfb -> tlb -> tlfb -> ziggy
            try:
                tlfb1 = tmpdir / f"{name}_cross.tlfb"
                tlb_cross = tmpdir / f"{name}_cross.tlb"
                tlfb2 = tmpdir / f"{name}_cross2.tlfb"
                ziggy_cross = tmpdir / f"{name}_cross.ziggy"

                run_cmd([str(OTIOCAT), str(ziggy_path), str(tlfb1)])
                run_cmd([str(OTIOCAT), str(tlfb1), str(tlb_cross)])
                run_cmd([str(OTIOCAT), str(tlb_cross), str(tlfb2)])
                run_cmd([str(OTIOCAT), str(tlfb2), str(ziggy_cross)])

                tests["cross-format"] = (
                    "PASS" if ziggy_cross.read_text() == original_content else "FAIL"
                )
            except subprocess.CalledProcessError:
                tests["cross-format"] = "ERROR"

            all_pass = all(v == "PASS" for v in tests.values())
            results[name] = {
                "status": "PASS" if all_pass else "FAIL",
                "tests": tests,
            }

    return results


def format_time(seconds: float) -> str:
    """Format time in human-readable format."""
    if seconds < 0.001:
        return f"{seconds * 1_000_000:.1f}µs"
    elif seconds < 1:
        return f"{seconds * 1000:.2f}ms"
    else:
        return f"{seconds:.3f}s"


def format_size(bytes_val: int) -> str:
    """Format size in human-readable format."""
    if bytes_val < 1024:
        return f"{bytes_val}B"
    elif bytes_val < 1024 * 1024:
        return f"{bytes_val / 1024:.1f}KB"
    else:
        return f"{bytes_val / (1024 * 1024):.2f}MB"


def generate_report(
    file_sizes: dict[str, dict[str, int]],
    read_perf: dict[str, dict[str, dict]],
    write_perf: dict[str, dict[str, dict]],
    tool_perf: dict[str, dict[str, dict]],
    otiocat_comparison: dict[str, dict],
    hierarchy_comparison: dict[str, dict],
    roundtrip_results: dict[str, dict],
) -> str:
    """Generate markdown report with all results."""
    lines = []
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    lines.append("# Format Performance Comparison Report")
    lines.append("")
    lines.append(f"Generated: {timestamp}")
    lines.append("Build: ReleaseFast")
    lines.append("")

    # File Sizes
    lines.append("## File Sizes")
    lines.append("")
    lines.append("| File | OTIO | Ziggy | TLB | TLFB |")
    lines.append("|------|------|-------|-----|------|")
    for name, sizes in sorted(file_sizes.items()):
        otio = format_size(sizes.get("otio", 0)) if "otio" in sizes else "-"
        ziggy = format_size(sizes.get("ziggy", 0)) if "ziggy" in sizes else "-"
        tlb = format_size(sizes.get("tlb", 0)) if "tlb" in sizes else "-"
        tlfb = format_size(sizes.get("tlfb", 0)) if "tlfb" in sizes else "-"
        lines.append(f"| {name} | {otio} | {ziggy} | {tlb} | {tlfb} |")
    lines.append("")

    # Read Performance
    lines.append("## Read Performance")
    lines.append("")
    lines.append("| File | OTIO | Ziggy | TLB | TLFB | Fastest |")
    lines.append("|------|------|-------|-----|------|---------|")
    for name, results in sorted(read_perf.items()):
        times = {}
        for fmt in ["otio", "ziggy", "tlb", "tlfb"]:
            if fmt in results:
                times[fmt] = results[fmt]["mean"]

        row = [name]
        for fmt in ["otio", "ziggy", "tlb", "tlfb"]:
            if fmt in times:
                row.append(format_time(times[fmt]))
            else:
                row.append("-")

        if times:
            fastest = min(times, key=times.get)
            row.append(fastest.upper())
        else:
            row.append("-")

        lines.append("| " + " | ".join(row) + " |")
    lines.append("")

    # Write Performance
    lines.append("## Write Performance")
    lines.append("")
    lines.append("| File | Ziggy→TLB | Ziggy→TLFB | Ratio |")
    lines.append("|------|-----------|------------|-------|")
    for name, results in sorted(write_perf.items()):
        tlb_time = results.get("ziggy→tlb", {}).get("mean")
        tlfb_time = results.get("ziggy→tlfb", {}).get("mean")

        tlb_str = format_time(tlb_time) if tlb_time else "-"
        tlfb_str = format_time(tlfb_time) if tlfb_time else "-"

        if tlb_time and tlfb_time:
            ratio = f"{tlb_time / tlfb_time:.2f}x"
        else:
            ratio = "-"

        lines.append(f"| {name} | {tlb_str} | {tlfb_str} | {ratio} |")
    lines.append("")

    # Tool Performance
    if tool_perf:
        lines.append("## Tool Performance (hierarchy_view)")
        lines.append("")
        lines.append("| File | OTIO | Ziggy | TLB | TLFB | Fastest |")
        lines.append("|------|------|-------|-----|------|---------|")
        for name, results in sorted(tool_perf.items()):
            times = {}
            for fmt in ["otio", "ziggy", "tlb", "tlfb"]:
                if fmt in results:
                    times[fmt] = results[fmt]["mean"]

            row = [name]
            for fmt in ["otio", "ziggy", "tlb", "tlfb"]:
                if fmt in times:
                    row.append(format_time(times[fmt]))
                else:
                    row.append("-")

            if times:
                fastest = min(times, key=times.get)
                row.append(fastest.upper())
            else:
                row.append("-")

            lines.append("| " + " | ".join(row) + " |")
        lines.append("")

    # Correctness Verification
    lines.append("## Correctness Verification")
    lines.append("")
    lines.append("| Test | Status |")
    lines.append("|------|--------|")

    # otiocat consistency
    otiocat_pass = all(r["status"] == "PASS" for r in otiocat_comparison.values())
    lines.append(f"| otiocat output consistency | {'PASS' if otiocat_pass else 'FAIL'} |")

    # hierarchy consistency
    hierarchy_pass = all(r["status"] == "PASS" for r in hierarchy_comparison.values())
    lines.append(f"| hierarchy view consistency | {'PASS' if hierarchy_pass else 'FAIL'} |")

    # roundtrip
    roundtrip_pass = all(r["status"] == "PASS" for r in roundtrip_results.values())
    lines.append(f"| roundtrip integrity | {'PASS' if roundtrip_pass else 'FAIL'} |")
    lines.append("")

    # Detailed roundtrip results
    lines.append("### Roundtrip Details")
    lines.append("")
    for name, result in sorted(roundtrip_results.items()):
        lines.append(f"**{name}**: {result['status']}")
        if "tests" in result:
            for test, status in result["tests"].items():
                lines.append(f"  - {test}: {status}")
        lines.append("")

    # Summary
    lines.append("## Summary")
    lines.append("")

    # Find fastest read format
    if read_perf:
        all_times = {}
        for name, results in read_perf.items():
            for fmt, data in results.items():
                if fmt not in all_times:
                    all_times[fmt] = []
                all_times[fmt].append(data["mean"])

        avg_times = {fmt: sum(t) / len(t) for fmt, t in all_times.items() if t}
        if avg_times:
            fastest = min(avg_times, key=avg_times.get)
            slowest = max(avg_times, key=avg_times.get)
            speedup = avg_times[slowest] / avg_times[fastest]
            lines.append(f"- Fastest read format: **{fastest.upper()}** ({speedup:.1f}x faster than {slowest})")

    # Find smallest file format
    if file_sizes:
        all_sizes = {}
        for name, sizes in file_sizes.items():
            for fmt, size in sizes.items():
                if fmt not in all_sizes:
                    all_sizes[fmt] = []
                all_sizes[fmt].append(size)

        avg_sizes = {fmt: sum(s) / len(s) for fmt, s in all_sizes.items() if s}
        if avg_sizes:
            smallest = min(avg_sizes, key=avg_sizes.get)
            lines.append(f"- Smallest file format: **{smallest.upper()}**")

    all_pass = otiocat_pass and hierarchy_pass and roundtrip_pass
    lines.append(f"- All correctness tests: **{'PASS' if all_pass else 'FAIL'}**")
    lines.append("")

    return "\n".join(lines)


def main() -> int:
    """Main entry point."""
    args = parse_args()

    log(f"Test files dir: {args.test_files_dir}")
    log(f"Warmup: {args.warmup}, Runs: {args.runs}")

    # Build unless skipped
    if not args.skip_build:
        if not build_release():
            log("Build failed, exiting")
            return 1

    # Verify binaries
    if not verify_binaries():
        log("Missing binaries, exiting")
        return 1

    # Discover test files
    test_files = discover_test_files(args.test_files_dir)
    if not test_files:
        log("No test files found, exiting")
        return 1

    # Get file sizes
    log("Getting file sizes...")
    file_sizes = get_file_sizes(test_files)

    # Run benchmarks
    read_perf = benchmark_read_performance(test_files, args.warmup, args.runs)
    write_perf = benchmark_write_performance(test_files, args.warmup, args.runs)
    tool_perf = benchmark_tool_performance(test_files, args.warmup, args.runs)

    # Run correctness comparisons
    otiocat_comparison = compare_otiocat_output(test_files)
    hierarchy_comparison = compare_hierarchy_output(test_files)
    roundtrip_results = verify_roundtrip(test_files)

    # Generate report
    report = generate_report(
        file_sizes,
        read_perf,
        write_perf,
        tool_perf,
        otiocat_comparison,
        hierarchy_comparison,
        roundtrip_results,
    )

    # Output report
    if args.output:
        args.output.write_text(report)
        log(f"Report written to {args.output}")
    else:
        print(report)

    log("Done!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
