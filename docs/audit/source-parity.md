# Source and resource parity audit

Audit baseline: upstream `c57960535d85a3432387b34e4a2c456a7f06be64` (v0.3.3 alpha). Root fetched origin/main during the audit and confirmed the same commit; there is no newer upstream delta to import. Canonical checkout: `PROJECT_ROOT`.

The Mac port initially changed tracked `sim/main.c` and `sim/Makefile` only. `common/`, `model/`, `assets/`, and `firmware/` remain byte-identical to baseline tracked files. Native AppKit bridge/resize sources were added under `sim/`; build/install/uninstall scripts and tests are in `mac/`. No model training, tokenizer changes, fish/save schema changes, or device firmware changes occurred.

The main changes enable the trained advisor by default, resolve bundled resources, use the app-support save path through native startup, add menus/instructions/window controls, suppress tank input behind native controls, and save on shutdown. Build defaults target the host architecture and link Cocoa. The test-only two-fish hold deadline was extended from 14 to 30 seconds to accommodate approach timing; no engine behavior changed there.

The audit subsequently identified and fixed an inherited asynchronous mailbox race in `sim/advisor_llm.c`: the next inference could overwrite an unread response. Dispatch now requires the response slot to be empty, and drops old-generation responses even when the removed fish index is no longer polled. Four deterministic regression cases cover unread delivery, in-flight removal/reindexing and an already-completed removed-fish response. Separately, the persistence verifier owns atomic file replacement in `sim/persist_port_sim.c`; main now keeps the aquarium open with a recoverable native error when shutdown saving fails. These fixes do not change save bytes or model weights.

## Resource hashes

`work/audit/fish/parity.py` compares original Git blob bytes, canonical source, root app, and `dist/Pocket Tank.app`. All four match for every row:

| Resource | SHA-256 |
| --- | --- |
| `model/out/model_q4.bin` | `50bed3e16a6b11f3496dde21d8784da9067f40ec9f0a77cf97f60a95acb80f6b` |
| `model/out/tokenizer.bin` | `50fb0d45f10c4ccabcf26f8a5ea52b81eb2fa8939cc429983638da26bd3d32a4` |
| `assets/sounds/sounds.bin` | `5b9b8d617ed0dc0ae444a732305adec3a95b69e1443a3a02eecbe6f71bdac9af` |

The compiled Mac app selects this same schema-v4 sampled model, not a replacement model. The per-fish probe confirms actual asynchronous model responses were consumed. Resource parity alone does not establish behavioral correctness: the wrapper race was present despite identical weights.

Evidence: `work/audit/fish/resource-parity.json`, `main-pre-audit.diff`, and the tracked Git diff. The canonical simulator was rebuilt after the fixes. `python3 mac/verify_source.py` verifies all 164 tracked core/model/asset/firmware files against the baseline, validates bundled source/resource provenance, compares the executable code sections with the canonical simulator and checks the deep signature. The final DMG is independently checked against that bundle. Packaged apps no longer fall back to external working-directory resources when a bundled resource is absent.

## Platform caveats / useful next quality-of-life work

1. Show an accessible per-fish “resting / exploring / following” status with a concise explanation of night/energy, so intentional quiet behavior is distinguishable from a stalled brain. Avoid forcing perpetual movement.
2. Keep developer cheat and firmware simulation shortcuts outside normal packaged-app use. The inherited `L` shortcut toggles to rules; a user can unintentionally turn the model off. Fake battery/firmware pages also remain inherited simulator UI.
3. Add an explicit diagnostic brain-mode indicator/export using an isolated save; report actual delivered decisions, not only requests or successful model loading.
4. The FreeRTOS device wrapper has the same unguarded dispatch shape (`firmware/main/advisor_llm_esp.c:115`). It is outside this Mac task and remains unchanged; propose the equivalent guard plus device regression to its owner rather than silently altering firmware.
