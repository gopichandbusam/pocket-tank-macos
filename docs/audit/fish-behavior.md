# Fish/model behavior audit

## Finding

A real inherited asynchronous delivery race loses decisions: after inference finishes for fish 0, polling fish 1 can start another inference while the single response slot still belongs to fish 0. A fast worker overwrites the unread response with fish 1's result. The tank resets fish 0's request timer when requesting, so its next decision may wait until a state change or the 45-second idle ceiling. This is a delivery defect, not bad model weights.

A logging-only copy of the real advisor emitted `MAILBOX_OVERWRITE old=0 new=1` with the user's copied tank and real model. A direct real-model regression failed with `response=1 fish1_pending=0`. A deterministic model-stub test failed because the second dispatch occurred before consuming the first response. The minimal fix in `sim/advisor_llm.c` adds `g_resp_fish < 0` to dispatch; both regressions then passed. Independent review found a second consequence of blocking dispatch: selling the last fish during an in-flight inference could leave an old-generation response at an index that is never polled again, blocking every future dispatch. The wrapper now discards any old-generation response before delivery/dispatch. The expanded public test reproduces failure before this fix and passes unread retention, removed-in-flight, reindexed-in-flight and removed-completed cases after it (20 repeated sets passed). No model, save layout or common fish rules changed.

The user's quiet-fish report also has ordinary contributing behavior. Their copied tank's saved manual-off setting makes `night=true` on the first tick. Fish B chooses reef inspection and rest at night, while Fish A chooses following. Daylight changes the goal mix. Both fish moved and received decisions in all completed observation cases; no permanent physical movement stall was reproduced. This is evidence against an always-stuck fish in this saved sample, not proof against every possible stall.

## Measurements

Each case runs the actual common tank/progression physics at 60 simulation ticks per second, paced with 16ms waits, in separate headless processes with explicit isolated `POCKET_TANK_SAVE` paths. A local aquarium snapshot was copied into a private test fixture (excluded from Git). Normal boot recovery applies elapsed sleep, recorded in each log (initial matrix 168 seconds). Fresh tanks use seed4321. Daylight cases force the light on only in the isolated process. “Travel” is summed frame-to-frame center movement, not straight-line displacement. Stress ended at zero in these cases.

| Before fix, 60 simulation seconds | Fish | Travel px | X/Y span px | Requests / delivered model responses | End goal |
| --- | --- | ---: | --- | --- | --- |
| live trained, saved night | Fish A | 618.7 | 205.5 / 160.3 | 3 / 2 | follow_friend |
| live trained, saved night | Fish B | 344.5 | 120.1 / 75.8 | 5 / 5 | rest |
| live trained, forced daylight | Fish A | 721.9 | 179.4 / 190.3 | 3 / 2 | visit_bubbles |
| live trained, forced daylight | Fish B | 420.5 | 119.9 / 80.4 | 3 / 3 | explore |
| fresh trained, daylight | Seeded fish C | 464.0 | 144.7 / 64.7 | 8 / 7 | explore |
| fresh trained, daylight | Fish A | 439.5 | 143.0 / 38.8 | 4 / 4 | explore |
| live rules, daylight | Fish A | 615.1 | 246.6 / 195.3 | 5 / n/a | follow_friend |
| live rules, daylight | Fish B | 1494.0 | 260.7 / 143.6 | 3 / n/a | dart_play |
| live rules, saved night | Fish A | 509.2 | 179.8 / 159.8 | 4 / n/a | rest |
| live rules, saved night | Fish B | 647.3 | 259.1 / 164.8 | 3 / n/a | rest |
| fresh rules, daylight | Seeded fish C | 767.9 | 317.7 / 184.8 | 4 / n/a | explore |
| fresh rules, daylight | Fish A | 648.0 | 178.0 / 203.9 | 6 / n/a | explore |

The initial matrix used concurrent processes, so it is a motion/starvation stress comparison rather than a latency benchmark. A further 90-second live daylight run before the fix traveled 883.0px (Fish A) and 852.0px (Fish B), with 3/4 and 9/9 decisions delivered respectively. That run began alone, with a separate instrumentation run overlapping its later portion; it is not a latency benchmark. An instrumented pre-fix live60s run proves one overwritten response, Fish A1/2 vs Fish B4/4 delivered.

After the guard, the instrumented live daylight60s run logged **no overwrite**, and delivered **3/3 decisions to each fish**. Fish A traveled502.7px, spanning202.9×163.8px, energy5.15; Fish B414.4px, spanning126.3×99.5px, energy7.60. Both ended exploring with two goal changes each. Sampled decoding and changed elapsed boot time mean these runs should not be read as identical trajectories or a controlled model-quality score.

## Reproduction and limits

- `python3 mac/tests/test_advisor_mailbox.py` compiles the actual pthread/dispatch wrapper with a deterministic isolated inference stub; PASS after guard. It uses no saves, preferences, GUI, or model bytes.
- `work/audit/fish/test_mailbox.c` tests the same sequencing with the real trained model; `mailbox-before.log` FAIL and `mailbox-after.log` PASS.
- `fish_probe.c`, `run_cases.py`, `check_motion.py`, CSV/log files and `motion-summary.json` preserve per-second fish position, speed/target, hunger/energy/stress/boredom, request age, goal, request count, response delivery observations (a mutex-protected mailbox check immediately before polling), and goal changes. The locked check can theoretically race a pre-fix overwrite between check and consumption; the deterministic sequencing test and explicit worker overwrite log establish the bug independently of those counts. `advisor_llm_instrumented.c` is a temporary logging-only copy; canonical common/model stay unchanged.
- Rules comparison is explicitly selected by the probe, not a product `--nollm` flag (which did not exist at audit start). The app's inherited L key is a separate manual toggle. Real rendering/UI and final app smoke are independently tested by the other audit agents.

The guard prevents loss of already-completed decisions; it does not promise every fish will continuously roam. Rest and slower landmark inspection are legitimate trained goals, especially with the light off. Longer observation, different saves, and broader model-quality scoring remain possible follow-up work; no retraining is justified by this audit.
