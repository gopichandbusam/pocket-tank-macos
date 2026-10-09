#!/usr/bin/env python3
"""Sample live macOS process resources for Pocket Tank or another app PID.

The helper only reads proc_pid_rusage for the supplied PID. It does not launch,
copy, reconfigure, or write to the target process. The requested CSV is the raw
sample output; a privacy-minimized summary is written beside it.
"""

import argparse
import csv
import json
import math
import os
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path


def describe(values):
    values = sorted(values)
    if not values:
        return {"count": 0, "min": None, "median": None, "p95": None, "max": None}
    return {
        "count": len(values),
        "min": values[0],
        "median": statistics.median(values),
        "p95": values[math.ceil(0.95 * len(values)) - 1],
        "max": values[-1],
    }


def atomic_write(path, content, force):
    if path.exists() and not force:
        raise FileExistsError(f"refusing to overwrite {path}; pass --force to replace it")
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", newline="") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, path)
    except Exception:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", required=True, type=int, help="PID of the app process you want to sample")
    parser.add_argument("--seconds", type=int, default=90, help="sampling duration, 1 to 3600 seconds (default: 90)")
    parser.add_argument("--output", required=True, type=Path, help="new CSV output path; a .summary.json is written beside it")
    parser.add_argument("--warmup-seconds", type=float, default=10.0, help="exclude startup readings from summary (default: 10)")
    parser.add_argument("--force", action="store_true", help="replace existing CSV and summary files")
    args = parser.parse_args()

    if os.uname().sysname != "Darwin":
        parser.error("this sampler requires macOS (proc_pid_rusage)")
    if args.pid <= 0 or args.seconds < 1 or args.seconds > 3600:
        parser.error("PID must be positive and seconds must be 1–3600")
    if args.warmup_seconds < 0 or args.warmup_seconds >= args.seconds:
        parser.error("warm-up must be non-negative and shorter than the sampling duration")

    csv_path = args.output.expanduser().resolve()
    summary_path = csv_path.with_name(csv_path.stem + ".summary.json")
    if not args.force and (csv_path.exists() or summary_path.exists()):
        parser.error(f"output exists ({csv_path} or {summary_path}); choose new paths or pass --force")
    csv_path.parent.mkdir(parents=True, exist_ok=True)

    source = Path(__file__).with_name("resource_sampler.c")
    if not source.is_file():
        parser.error(f"sampler source is missing: {source.name}")
    with tempfile.TemporaryDirectory(prefix="pocket-tank-resource-sampler-") as temp_dir:
        binary = Path(temp_dir) / "resource_sampler"
        subprocess.run(
            ["clang", "-std=c11", "-Wall", "-Wextra", "-Werror", str(source), "-o", str(binary)],
            check=True,
        )
        result = subprocess.run(
            [str(binary), str(args.pid), "profile", str(args.seconds), str(csv_path)],
            text=True,
            capture_output=True,
        )

    if not csv_path.is_file():
        raise SystemExit(result.stderr or "sampler produced no CSV output")
    with csv_path.open(newline="") as stream:
        raw = list(csv.DictReader(stream))
    if not raw:
        raise SystemExit(result.stderr or "the process exited before the first live sample")
    rows = [{key: int(value) if key != "phase" else value for key, value in row.items()} for row in raw]
    started = rows[0]["timestamp_monotonic_ns"]
    cutoff = started + int(args.warmup_seconds * 1e9)
    retained = [row for row in rows if row["timestamp_monotonic_ns"] >= cutoff]
    if len(retained) < 2:
        raise SystemExit("too few live samples remain after warm-up")

    cpu_percent = []
    task_energy_watts = []
    for previous, current in zip(retained, retained[1:]):
        elapsed = (current["timestamp_monotonic_ns"] - previous["timestamp_monotonic_ns"]) / 1e9
        if elapsed <= 0:
            continue
        ticks = (
            current["user_cpu_mach_ticks"] + current["system_cpu_mach_ticks"]
            - previous["user_cpu_mach_ticks"] - previous["system_cpu_mach_ticks"]
        )
        cpu_ns = ticks * previous["timebase_numer"] / previous["timebase_denom"]
        cpu_percent.append(cpu_ns / (elapsed * 1e9) * 100)
        energy_delta = current["energy_nj"] - previous["energy_nj"]
        if energy_delta >= 0:
            task_energy_watts.append(energy_delta / 1e9 / elapsed)

    span = (rows[-1]["timestamp_monotonic_ns"] - started) / 1e9
    analysis_span = (retained[-1]["timestamp_monotonic_ns"] - retained[0]["timestamp_monotonic_ns"]) / 1e9
    summary = {
        "schema_version": 1,
        "pid": args.pid,
        "requested_seconds": args.seconds,
        "live_sample_count": len(rows),
        "live_sample_span_seconds": span,
        "complete": result.returncode == 0 and span >= args.seconds - 1.5,
        "sampler_exit_code": result.returncode,
        "sampler_message": result.stderr.strip() or None,
        "warmup_excluded_seconds": args.warmup_seconds,
        "analysis_span_seconds": analysis_span,
        "cpu_percent_of_one_core": describe(cpu_percent),
        "physical_footprint_mib": describe([row["phys_footprint_bytes"] / (1024 * 1024) for row in retained]),
        "resident_mib": describe([row["resident_bytes"] / (1024 * 1024) for row in retained]),
        "task_cpu_energy_rate_w": describe(task_energy_watts),
        "task_cpu_energy_j_over_analysis_window": (
            retained[-1]["energy_nj"] - retained[0]["energy_nj"]
        ) / 1e9,
        "cpu_counter_units": "Mach-time ticks converted using the sampled mach_timebase_info ratio",
        "energy_scope": "ri_energy_nj process task CPU Recount counter; derived watts are not whole-Mac power or GPU energy",
        "gpu_and_whole_system_power": "not measured by this process sampler",
        "output_csv": csv_path.name,
    }
    atomic_write(summary_path, json.dumps(summary, indent=2) + "\n", args.force)
    print(json.dumps(summary, indent=2))
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if not summary["complete"]:
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
