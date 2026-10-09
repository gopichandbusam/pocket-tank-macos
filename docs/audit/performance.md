# Pocket Tank macOS resource profile

This profile measures the rebuilt final Pocket Tank macOS bundle (bundle version 1.3, build 4) during one 90-second, visible, normal-speed run on this Apple Silicon Mac.

| Measure | Median after 10-second startup warm-up | p95 | Observed range |
|---|---:|---:|---:|
| CPU, percent of one core | 9.26% | 11.25% | 3.96–12.74% |
| Physical footprint | 214.58 MiB | 214.63 MiB | 210.22–216.77 MiB |
| Resident memory | 130.25 MiB | 130.27 MiB | 129.86–133.81 MiB |
| Process task CPU-energy rate | 0.0179 W | 0.0688 W | 0.0150–0.0961 W |

The process stayed live through the full smoke interval: 90 `proc_pid_rusage` samples covered 89.35 seconds, and the smoke diagnostic recorded 90.013 seconds. CPU is expressed as a percentage of one fully occupied core, so 100% means one core. After excluding the first ten seconds, 79 one-second CPU intervals and energy intervals and 80 memory readings remained. The portable helper's first sample begins as the app starts, so the timestamp span is just under the requested 90-second sampling duration.

The collector checks that the process is live before accepting each sample. XNU's `ri_user_time` and `ri_system_time` are Mach-time ticks, not nanoseconds; the CPU conversion uses this host's `mach_timebase_info` ratio (125/3 ns per tick). This conversion was separately cross-checked against `ps` accumulated CPU time on a live Pocket Tank process: 9.78% versus 9.82% of one core over 7.03 seconds, with matching resident memory.

The energy number is the OS task-level `ri_energy_nj` CPU Recount counter converted to joules and divided by wall time. Its 0.018 W median and 0.069 W p95 describe the Pocket Tank process counter only. They are not whole-Mac power readings. The separate `ri_penergy_nj` counter tracks P-core task energy; it is not added to the `ri_energy_nj` result. A same-PID `ioreg` Metal `accumulatedGPUTime` counter rose from 67,609,666 to 1,862,902,166 raw units across an 80.12-second interval. Its property output does not show the unit, so I report the raw delta (1,795,292,500) without converting it to a GPU percentage or power. Device-wide `ioreg` utilization snapshots read 27% early and 0% late; these include other processes and are not attributable to Pocket Tank. `ioreg` provided no GPU energy/power value, and I could not collect `powermetrics` without superuser access. GPU watts and total Mac watts are unavailable; none are inferred from CPU utilization. See [XNU's Recount documentation](https://github.com/apple-oss-distributions/xnu/blob/main/doc/observability/recount.md) and Apple's [`rusage_info_current` reference](https://developer.apple.com/documentation/kernel/rusage_info_current).

The measured window rendered 5,129 frames with a native window, fixed 448×368 logical world, and loaded, active local model. The diagnostic reported 22 advisor asks. Fish progression ran at its normal 1× rate; this was not an inference stress test or an AI-on/AI-off comparison. The app's macOS bundle reports version 1.3, build 4. Its startup log separately reports the upstream engine release `v0.3.3 alpha`; these are distinct version fields.

For isolation, the final app was copied into a temporary audit bundle with a unique bundle identifier and ad-hoc re-signed. It was launched directly from within that copy in smoke mode, with `--fast 1 --mac-smoke-seconds 90 --mac-smoke-dir <run>/diagnostics`. The app wrote only to a private per-run copy of its save; smoke mode also suppressed preference writes. The app's input guard was enabled, and no user save or preference was changed. Public summary metadata omits save paths, save contents or hashes, stdout, and home-directory paths.

The earlier short 1.2 snapshots and erroneous CPU values that treated Mach ticks as nanoseconds are excluded from this report. The corrected machine-readable summary is in [`summary.csv`](performance/summary.csv) and [`summary.json`](performance/summary.json). The raw readings remain in the local audit workspace and are not included in the public summary.

```sh
pgrep -fl PocketTank
python3 mac/measure_resources.py --pid <PID> --seconds 90 \
  --output "$HOME/Desktop/pocket-tank-resources.csv"
```

Launch the copy of Pocket Tank you want to measure first, then choose its `PocketTank` process PID from `pgrep`. The read-only helper compiles a temporary sampler and writes a raw CSV plus a `.summary.json` sidecar next to the selected output. It does not launch the app, copy its save, alter preferences, or change the process. If the process exits early, the summary marks the sample incomplete and reports only rows gathered while that PID was live. The helper measures CPU, memory, and task CPU energy; its task-energy-derived watts are not GPU or whole-Mac power. The two GPU snapshots reported above were collected separately with `ioreg` and are not part of the helper's CSV.

The host was a MacBook Pro Mac17,8 with an Apple M5 Pro (18 CPU cores: 6 Super and 12 Performance), 48 GiB memory, running macOS 27.0.1 (26A434). The measurements describe this machine and this run; they are not a broader device compatibility or battery-life claim.
