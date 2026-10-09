# Pocket Tank for macOS 🐟

A pocket aquarium for your Mac: a small floating window with fish that grow, learn habits, make friends and choose what to do next using a tiny local language model.

This is an independent macOS adaptation of [mediacutlet/pocket-tank](https://github.com/mediacutlet/pocket-tank). The original project runs on ESP32 hardware. This fork keeps its shared aquarium engine, trained fish model, artwork, sound and MIT attribution, and adds a standalone desktop app.

**[Download the macOS alpha](https://github.com/gopichandbusam/pocket-tank-macos/releases/tag/mac-v1.3-alpha)** · [Mac changes](docs/MAC_CHANGES.md) · [Upstream project](https://github.com/mediacutlet/pocket-tank) · [Preserved upstream README](docs/UPSTREAM_README.md)

![Pocket Tank aquarium, shown in the upstream simulator](docs/media/sim-tank.png)

The aquarium images in this README come from the upstream simulator and show the shared rendering and care screens. The light/dark Instructions images below show the native Mac panel.

## Contents

- [Install and first launch](#install-and-first-launch)
- [Your floating Mac aquarium](#your-floating-mac-aquarium)
- [Care for your fish](#care-for-your-fish)
- [Growth, families and milestones](#growth-families-and-milestones)
- [Sand dollars and the shop](#sand-dollars-and-the-shop)
- [The local fish brain](#the-local-fish-brain)
- [How the app works](#how-the-app-works)
- [Saved state and uninstalling](#saved-state-and-uninstalling)
- [Measured Mac performance](#measured-mac-performance)
- [Build and verify](#build-and-verify)
- [Training and upstream documentation](#training-and-upstream-documentation)
- [Troubleshooting and current limits](#troubleshooting-and-current-limits)
- [What changed and what comes next](#what-changed-and-what-comes-next)
- [License and credits](#license-and-credits)

## Install and first launch

1. Download `Pocket.Tank.dmg` from the [release page](https://github.com/gopichandbusam/pocket-tank-macos/releases/tag/mac-v1.3-alpha). The release also contains source and checksums.
2. Open the DMG and drag **Pocket Tank.app → Applications**.
3. Open Pocket Tank. Follow the welcome screens to name your first pair of fish, choose their colors and place the bubble column.
4. Click **ⓘ** for the complete care instructions and desktop controls.

The downloadable **Mac 1.3 / build 4 alpha** is **Apple Silicon, macOS 27 or later**, tested on an M5 Pro with macOS 27.0.1. The app bundles the model and SDL runtime: no account, Homebrew, cloud inference or internet connection is needed to run the installed aquarium. Building from source has separate dependencies.

This build is ad-hoc signed, without Developer ID signing or notarization. macOS may block a downloaded copy. Review the source and release checksums; if you trust the download, use **System Settings → Privacy & Security → Open Anyway** when available. Do not disable system security globally. This is an independent alpha, not an official upstream Mac release.

The source builds for the host architecture. Intel Macs and older macOS versions have not been verified; the downloadable DMG is not a universal binary.

## Your floating Mac aquarium

Keep a little tank beside your work, or let it sit behind your other windows. Its title bar provides normal Mac dragging, proportional resizing and a standard close button.

<p><img src="docs/media/mac-instructions-light.png" width="300" alt="Native Mac Instructions panel in light appearance"> <img src="docs/media/mac-instructions-dark.png" width="300" alt="Native Mac Instructions panel in dark appearance"></p>

The **ⓘ Instructions** panel follows the Mac's light/dark appearance. It scrolls, resizes and closes independently, and contains:

| Control | What it does |
|---|---|
| **Feed** | Drops food into the aquarium. |
| **Light** | Changes the tank's light. The care settings also offer automatic light control. |
| **Milestones** | Opens the shared aquarium milestones interface. |
| **Sound** | Cycles the aquarium sound level. |
| **Float above other windows** | Keeps the aquarium above other apps. Turn it off for normal window ordering. |
| **Transparency** | Fades the aquarium from fully opaque to 20% opacity (0–80% transparency). |
| **Opaque** | Restores full opacity. |

The Instructions panel stays fully opaque so it remains readable while the aquarium is faded. Window size/position and transparency persist between launches. The tank starts floating when reopened; the floating toggle is not yet remembered. The tank's day/night lighting remains part of the simulation; it is separate from the Mac's system appearance.

Use the app menus for **Help → Instructions**, **Window → Show Tank**, and floating. **Command-1** shows the tank, **Command-H** hides it, and **Command-Q** saves and quits. Closing Instructions leaves the aquarium running. Closing the aquarium itself requests a save and exit.

The shared simulator also accepts inherited letter shortcuts while the aquarium owns keyboard focus. These include `F` for food and `L` to switch between the model and rules advisor. In ordinary use, prefer the visible controls; the `L` shortcut can accidentally switch the AI off. Other inherited developer shortcuts can alter your tank.

## Care for your fish

### Feed, watch and build trust

Click the water surface, drag down from near the top, or press **Feed** in Instructions to drop food. Let hunger guide feeding. Click a fish for its stats, then **MORE** for milestones, settings and upgrades. Click empty water to dismiss a card.

Hold the mouse still on the glass for about three seconds. Fish that trust you may swim over. Calm holds build trust, while meals from you count toward care and progression. Three quick clicks can startle them, so repeated clicking is not a way to summon a quiet fish.

The fish do not die. However, with automatic feeding off, leaving a fish starving in a lit, awake tank beyond its grace period slowly reduces trust. Feeding prevents further starvation penalties; calm holds can rebuild trust.

<p><img src="docs/media/sim-fish-card.png" width="280" alt="Fish statistics card"> <img src="docs/media/sim-stats-card.png" width="280" alt="Detailed fish statistics"></p>

### Clean the glass and trim the plants

Drag across algae to wipe the glass. Swipe sideways through tall plants to trim them at the height of your stroke. The **sponge** and **scissors** tools focus your gestures on cleaning or pruning; press **DONE** to put the tool away. Tools also return after their timeout.

Grass and algae are part of the living tank. Bought helpers can reduce maintenance, and keeping suitable grass supports family progression. They are not a reason to remove every plant or keep the whole pane spotless at every moment.

<p><img src="docs/media/sim-tools.png" width="280" alt="Sponge and scissors tools"> <img src="docs/media/sim-tool-done.png" width="280" alt="Done control while a care tool is active"></p>

### Light, sound and automatic care

Double-click the glass to switch the light in manual mode. The shared tank settings let you choose automatic feeding, automatic lights-out, brightness, sound and other care options. Light-off changes the palette and fish behavior; resting in the grass is normal.

The original local sound bank provides small feeding, movement and care cues. Use **Sound** in Instructions to cycle its level.

Some settings still use the inherited device interface. Screen brightness there affects the simulated aquarium, not your Mac's display brightness. The simulator's battery and firmware-update pages are not live Mac battery information or a Mac app updater.

## Growth, families and milestones

You begin with two fry. They become juveniles, adults and elders, gaining size and mature markings as they grow. The current source uses **30 minutes / 3 hours / 24 hours** of accumulated grown life for those stages. Time while the app runs counts fully, including with the tank light off; elapsed time restored after a saved absence contributes at a slower quarter rate, with the simulated absence capped at seven days.

The app accounts for elapsed wall-clock time when you quit and reopen a saved tank, including supported growth and upkeep. It is not an always-running background service when quit. Native Mac system sleep/wake handling has not been added, so do not treat leaving the process open during Mac sleep as a verified equivalent of closing and reopening it.

The desktop tank can hold **up to six fish**. New fry are earned through care and progression gates such as meals, trust, calm holds, growth, clean glass and suitable grass. The **NEW FRY / HOW** screens explain the next requirements rather than leaving you to guess. Later arrivals have parents and a family welcome, where you can name the new fish. Newborn colors and markings inherit from their parents.

Milestones record first meals, approaches, play, visits, following, growth and tank achievements. Newly earned badges get a visual marker; click a badge for its details. Personality and habits can shift with life in the tank, so two fish need not behave alike.

<p><img src="docs/media/sim-milestones.png" width="280" alt="Fish milestones"> <img src="docs/media/sim-fry-how.png" width="280" alt="Requirements for the next fry"></p>
<p><img src="docs/media/sim-birth-family.png" width="280" alt="A new fish's family welcome"> <img src="docs/media/sim-birth-name_new.png" width="280" alt="Naming a newborn fish"></p>

Fish cards also allow renaming and selling eligible fish. A sale requires confirmation and keeps at least the original minimum of two fish in the tank. Stage values are **5 / 15 / 30 / 60 sand dollars** for fry, juvenile, adult and elder. After a sale, another fry still requires additional care, including twelve further player feedings; selling does not immediately hand back a replacement.

## Sand dollars and the shop

Sand dollars are earned in the aquarium, with no purchases or real-money currency. The balance and ownership ledger are saved with the tank.

| Care or milestone | Sand dollars |
|---|---:|
| A player feeding | 2 |
| Reaching juvenile / adult / elder | 5 / 10 / 25 |
| A new fry arrives | 20 |
| A fish first reaches full trust | 15 |
| Each 100 algae colonies cleaned | 25 |
| Each 250 cm of grass trimmed, in the tank's virtual units | 25 |

Open the shop through the shared aquarium interface. It spans two pages and currently offers:

| Upgrade | Cost | What it adds |
|---|---:|---|
| **Sword plant** | 40 | Broad vertical leaves and additional cover. |
| **Snail** | 80 | A glass-grazing helper with its own activity tally. |
| **Castle** | 150 | Stone towers and an arch that fish can swim through. |
| **Coral** | 100 | A branching coral with a selectable color that grows over weeks. |
| **Reef cluster** | 240 | A rock-mounted reef with three looks, growth and a later bloom. |
| **Shrimp** | 180 | A small school that eats scraps and can grow from four to ten. |
| **Sea urchin** | 120 | A resident helper that grazes tall grass. |

Drag placeable decorations along the floor, choose their **DEPTH** where offered, and use color/look controls for the pieces that support them. **MOVE** lets you reposition them later. Resident cards show helper activity or growth progress. Shrimp growth depends on food, time and tank conditions; buying them does not instantly produce a school of ten.

Placeable pieces can be sold back with confirmation for **20%** of their purchase price. Snails and shrimp are permanent residents rather than sellable decorations. Selling a piece resets that piece; buying it again costs the full price.

<p><img src="docs/media/sim-shop.png" width="280" alt="First page of the aquarium shop"> <img src="docs/media/sim-shop2.png" width="280" alt="Second page of the aquarium shop"></p>
<p><img src="docs/media/sim-place-coral.png" width="280" alt="Placing and coloring coral"> <img src="docs/media/sim-shrimp-card.png" width="280" alt="Shrimp school progress card"></p>

## The local fish brain

The aquarium's brain is a small language model that reads a compact description of a fish's state and chooses a goal and urgency. It is a closed-vocabulary decision model, not a chat interface. It runs locally on the Mac's **CPU**, asynchronously from the animation loop.

| Shipped model property | Value |
|---|---|
| Parameters | Approximately **14.3 million** |
| Architecture | Dimension 384, 8 layers, 8 heads |
| Weight format | 4-bit quantized, about **7.56 MB** |
| Tokenizer | 54-token closed word vocabulary; shipped schema-v4 model |
| Input | Drives, personality, life stage, trust, boredom, nearby objects and recent activity |
| Output | A goal plus urgency |
| Network or cloud inference | None |

The original pipeline distilled a larger teacher model, `gemma4:26b`, into this small student. The exact trained weights and tokenizer shipped by the audited upstream baseline are retained here. Installing the app does not require the teacher, Ollama, a training environment or downloading another model.

A state looks roughly like this:

```text
zone 2 hunger 7 energy 5 stress 2 curiosity 8 bold 4 social 6 stage adult
trust 6 bored 3 food near 12 friend mid 3 bubble mid 10 reef far 7
wall clear last explore time day -> seek_food urgency 8
```

The active goals are:

| Goal | Typical behavior |
|---|---|
| `seek_food` | Swim toward food. |
| `follow_friend` | Follow another fish. |
| `inspect_reef` | Investigate the reef. |
| `visit_bubbles` | Visit the bubble column. |
| `explore` | Roam through the tank. |
| `rest` | Settle into a quiet place. |
| `dart_play` | Make a playful dart. |

Hunger, energy, stress, curiosity and boredom compete with personality, trust and surroundings. Choices are sampled from the model's distribution, so behavior has variety rather than a single repeated script. Quiet reef inspection, rest and hesitation can be legitimate decisions. Older training documents mention shadow fleeing; that is not an active feature of the shipped schema-v4 behavior.

The upstream README and [historical statistics](docs/stats.md) contain teacher-agreement scores, older tokenizer sizes and ESP32 latency measurements. Those belong to specific upstream model versions and hardware tests. They are **not fresh accuracy or latency measurements of this Mac release**.

## How the app works

The fish brain chooses intent; the simulation turns that intent into continuous movement. The model does not generate individual pixels or run once for every rendered frame.

| Layer | Responsibility | Main source |
|---|---|---|
| Simulation | Motion, steering, schooling, touch, food, vegetation and algae | [`common/tank.c`](common/tank.c) |
| Model | State encoding, tokenizer and quantized inference | [`common/llm/`](common/llm/) |
| Async advisor | Worker thread, request scheduling and per-fish response delivery | [`sim/advisor_llm.c`](sim/advisor_llm.c) |
| Progression | Growth, trust, arrivals, milestones, shop and save contents | [`common/progression.c`](common/progression.c) |
| Rendering and audio | Shared aquarium artwork and local sound | [`common/render.c`](common/render.c), [`assets/`](assets/) |
| Mac integration | AppKit menus/windows, native Instructions, resize and focus handling | [`sim/mac_shell.m`](sim/mac_shell.m), [`sim/mac_resize.m`](sim/mac_resize.m) |
| File persistence | Checked atomic replacement and wall-clock storage | [`sim/persist_port_sim.c`](sim/persist_port_sim.c) |
| Distribution | Bundled runtime, licenses, uninstaller, DMG and verification | [`mac/`](mac/) |

The aquarium retains a **448×368 logical world**, scaled to the window while preserving its proportions. SDL draws the shared renderer. The Mac uses a worker thread for model inference; it does not use the ESP32's second-core setup or a separate Metal/MPS model backend. Rendering may still create GPU activity independently of CPU inference.

## Saved state and uninstalling

Your aquarium lives outside the app:

```text
~/Library/Application Support/Pocket Tank/tank.sav
```

Names, growth, trust, families, milestones, currency and supported aquarium settings are part of the saved tank. Native window and transparency preferences use the macOS preferences domain `com.local.pockettank`. Replacing the `.app` preserves these files. To back up the tank, quit normally first, then copy `tank.sav` somewhere safe.

Normal **Command-Q**, aquarium window close and application quit requests save before exit. A failed shutdown save offers **Retry Save / Keep Tank Open**, so a permission or disk error is visible rather than silently discarded. The engine also performs event-driven and periodic saving while running.

The file port writes a temporary file beside the save, checks write/flush/sync/close results, then atomically replaces the previous snapshot. An interrupted write cannot truncate that previous snapshot. Abrupt process death can leave an unused temporary file; directory-entry durability through power loss is not guaranteed. Changes since the last successful save can still be lost after a force-quit or crash.

**Use one running copy at a time.** Single-instance coordination is not implemented; two copies using the same save can overwrite each other's progress.

The DMG includes **Uninstall Pocket Tank.app**. It displays and confirms its removal paths, moves recognized app copies to Trash, and optionally removes saved aquarium data and preferences. Keep the data option off if you plan to reinstall and continue your tank. The uninstaller was verified with isolated fixtures, not by deleting a live user installation.

## Measured Mac performance

One visible, normal-speed, 90-second run of Mac 1.3/build 4 was measured on an **M5 Pro MacBook Pro, 18 CPU cores, 48 GiB RAM, macOS 27.0.1**. The first ten seconds were excluded from the summary:

| Measurement | Median | p95 |
|---|---:|---:|
| CPU, percent of one fully occupied core | **9.26%** | 11.25% |
| Physical memory footprint | **214.58 MiB** | 214.63 MiB |
| Resident memory | **130.25 MiB** | 130.27 MiB |
| OS process task CPU-energy rate | **0.0179 W** | 0.0688 W |

The run rendered 5,129 frames in 90.013 seconds, about 57 fps, with an active local model and 22 advisor requests. This was a normal-use sample, not a model latency benchmark, a battery-life test or a compatibility test across Macs.

The energy figure comes from the operating system's **task CPU-energy counter**. It is not total app power, GPU watts or whole-Mac power. A same-process GPU counter increased, but its units were undocumented, so no app GPU percentage or GPU-power estimate is claimed. Administrator-only whole-system power sampling was not collected.

See the [full measurement method and limitations](docs/audit/performance.md), [CSV](docs/audit/performance/summary.csv) and [JSON](docs/audit/performance/summary.json). To sample your running copy without changing its tank:

```sh
pgrep -fl PocketTank
python3 mac/measure_resources.py --pid <PID> --seconds 90 \
  --output "$HOME/Desktop/pocket-tank-resources.csv"
```

Replace `<PID>` with the aquarium's process number. The helper measures CPU, memory and task CPU energy, and reports an incomplete sample if the process exits early. It does not measure GPU or total-system watts.

## Build and verify

### Build the Mac app and DMG

Requires macOS, Xcode Command Line Tools with Swift, Python 3, Git and SDL2 development files. For example, install the latter with `brew install sdl2`.

```sh
git clone https://github.com/gopichandbusam/pocket-tank-macos.git
cd pocket-tank-macos
bash mac/build.sh
```

The script fetches **LVGL v9.2.2** when absent, compiles the simulator for your host, runs engine selftests and Mac regressions, bundles the model, runtime dependencies and license notices, then produces:

```text
dist/Pocket Tank.app
dist/Uninstall Pocket Tank.app
dist/Pocket Tank.dmg
```

Build libraries must match your architecture. The packager derives minimum system requirements from the actual Mach-O binaries; building with a newer SDK does not establish compatibility with older systems. A clean build can need internet access for dependencies even though the packaged aquarium runs offline.

The release also includes a source ZIP with the LVGL source needed by that release. Its contents are pinned to the release commit; later README changes on `main` do not change the existing release archive.

### Run the source simulator

For a quick build, run `make -C sim -j8`. To launch the standalone simulator from its expected resource directory:

```sh
cd sim
./fishsim
```

On macOS this is the same aquarium engine with the Mac integration. Running a second copy without an isolated save path can collide with your normal aquarium; quit the regular app before interactive source testing.

### Run the audit checks

From the repository root:

```sh
make -C sim check
python3 mac/tests/test_advisor_mailbox.py
python3 mac/tests/test_persistence.py
python3 mac/verify_source.py
python3 mac/verify_dmg.py
```

The source/DMG verifiers require locally built artifacts, and upstream Git-object comparisons require a checkout with the baseline history. The regression suite checks unread model-reply delivery, removed-fish responses, atomic save failures and preservation of existing snapshots. Bundle checks inspect source/resource provenance, runtime closure, signatures and DMG contents.

The repository includes CI for engine checks and host-side Mac regressions/builds. The published verification evidence was collected locally; a workflow file is not evidence that a remote CI run passed. Native window interaction, signing/download behavior and energy measurements require a real Mac session.

### Repository layout

```text
common/       Shared simulation, model runtime, rendering and progression
model/        Training/export tools, schema and shipped model resources
assets/       Shared graphics and sound resources
sim/          Desktop simulator, Mac bridge and platform file ports
mac/          Packaging, uninstaller, profiling and regression checks
docs/         Care/design history, Mac changes, screenshots and audit reports
firmware/     Preserved upstream ESP32 firmware
installer/    Preserved upstream device/browser installer sources
dist/         Local build output (not committed)
work/         Local scratch/audit material (not committed)
```

## Training and upstream documentation

Training is optional development work. It is not part of installing or running the Mac aquarium, and this fork has not retrained or replaced the shipped model.

The inherited pipeline generates teacher-labeled aquarium states, trains a small student, exports quantized weights and evaluates decisions. Entry points include `model/gen_traces.py`, `model/train_tokenizer.py`, `model/train.py`, `model/export_q4.py` and `model/eval.py`. Training needs its own Python dependencies and access to a teacher you own or are authorized to use.

Historical documents include device setup and particular training machines. Treat those as upstream development notes, not Mac installation commands. ESP32 flashing, firmware OTA and hardware button instructions do not apply to the Mac app.

| Read more | What it covers |
|---|---|
| [Upstream README](https://github.com/mediacutlet/pocket-tank) | Original project, hardware, care features and model story. |
| [Preserved README](docs/UPSTREAM_README.md) | The upstream documentation retained with this fork. |
| [Model schema](model/schema.md) | State and decision encoding; includes historical schema context. |
| [Pipeline](docs/pipeline.md) | Teacher data, training, export and evaluation workflow. |
| [Historical statistics](docs/stats.md) | Versioned upstream model and hardware measurements. |
| [Progression design](docs/progression-next.md) | Growth, families and progression design/history. |
| [Audio](docs/AUDIO.md) | Local sound bank and playback design. |
| [Mac changes](docs/MAC_CHANGES.md) | Native integration and remaining desktop priorities. |
| [Source parity](docs/audit/source-parity.md) | Baseline comparison, resource hashes and packaging provenance. |
| [Fish behavior audit](docs/audit/fish-behavior.md) | Real model replies, motion and the response-delivery fixes. |
| [Adversarial verification](docs/audit/verification.md) | Tested failure cases, evidence and remaining gaps. |

## Troubleshooting and current limits

**A fish is quiet.** Check its energy, light and surroundings first. Resting, reef inspection and following can involve little movement. The shipped model is enabled by default, but the inherited `L` shortcut toggles the rules advisor. During the audit, an actual mailbox bug could lose replies; that and stale replies after a roster change were fixed. A live probe then confirmed both tested fish received model decisions and moved. This does not prove every possible state has ideal behavior.

**The app cannot save.** Keep it open using the save-error dialog, fix access or free space in the Application Support folder, then retry. Avoid force-quitting with unsaved changes. Back up a working save before manual edits.

**macOS blocks the download.** Check the release provenance and checksum, then use the available system approval flow for a trusted download. Developer ID signing and notarization remain outstanding.

**A setting looks like a device screen.** The engine still includes firmware-style pages and simulator shortcuts. Battery, rotation and firmware-update controls do not represent native Mac integrations. The native Instructions panel supplies the desktop controls described above.

**A damaged app is missing its model or assets.** Packaged apps require their bundled resources and report missing files. They do not silently use an unrelated model from the working directory. Reinstall a complete build.

Other limits include no single-instance save coordination, no verified Intel/older-macOS compatibility, no native Mac sleep/wake integration, and an inherited save loader that accepts some non-finite numbers in deliberately corrupted files. Atomic writes protect against truncation, not every kind of semantic corruption. No save schema changes were made in this port.

## What changed and what comes next

The audited upstream baseline is **`c57960535d85a3432387b34e4a2c456a7f06be64`**, engine **v0.3.3 alpha**. The Mac bundle's version number is separate. All 164 tracked files in the audited `common/`, `model/`, `assets/` and `firmware/` baseline remain byte-identical; platform fixes and additions live around that shared engine.

This fork adds native menus and windows, a system-themed instruction panel, floating/transparency controls, resizing, focus handling, Application Support storage, a drag-to-Applications DMG, an optional-data uninstaller and build provenance. It also fixes the desktop advisor mailbox, stale roster replies, unsafe truncating save writes, silent failed quit saves and damaged-bundle resource fallback.

The next quality-of-life priorities are documented in [Mac changes](docs/MAC_CHANGES.md):

- Visible per-fish goal and brain status, so resting is distinguishable from a stalled advisor.
- Lower rendering cost while hidden or minimized, and a battery-friendly frame-rate option.
- Single-instance coordination, save backups and stronger corrupted-save validation.
- Native Mac settings in place of inherited device pages and developer shortcuts.
- Verified sleep/wake behavior, more OS/architecture coverage, Developer ID signing and notarization.

These are proposed improvements, not features promised by the current download. Device deployment workflows are archived under `docs/upstream-workflows/`; this fork does not publish ESP32 firmware or the upstream website.

## License and credits

Pocket Tank is [MIT licensed](LICENSE). Credit for the original aquarium, trained model, shared renderer, art, sounds and device project belongs to [mediacutlet/pocket-tank](https://github.com/mediacutlet/pocket-tank). This repository adds the independent Mac adaptation and its desktop fixes.

LVGL and SDL retain their own license notices, which ship with the bundled runtime. Firmware, training scripts and original documentation are retained for attribution, auditability and future rebasing.
