# macOS changes

The simulation and trained model originate from [mediacutlet/pocket-tank](https://github.com/mediacutlet/pocket-tank), baseline `c57960535d85a3432387b34e4a2c456a7f06be64`. The MIT license and upstream attribution are preserved. The original device README is retained in `docs/UPSTREAM_README.md`.

## Native desktop integration

- Standalone Apple Silicon `.app` and drag-to-Applications DMG; model, tokenizer, graphics, sound bank and runtime libraries bundled.
- Floating aquarium, proportional resizing, standard close controls and native menus.
- Small info button and scrollable Instructions window following system light/dark appearance.
- Native Feed, Light, Milestones, Sound, floating and transparency controls. Transparency persists; Instructions remains readable.
- Save-on-quit, show/hide shortcuts, isolated diagnostic modes and a native confirmation-based uninstaller.
- Keyboard/mouse input is gated to the active aquarium window; unattended smoke tests avoid stealing typing from other apps.
- Build provenance records source/resource hashes inside the signed app.

## Bugs found and corrected in the simulator

- **Lost AI decisions:** the asynchronous simulator wrapper could dispatch the next inference before its prior response was consumed. The next result overwrote the unread result. Dispatch now waits for an empty response slot. The trained weights and shared fish rules remain unchanged.
- **Save loss on write failure:** the simulator used direct truncating writes. It now writes a checked temporary file in the same directory, flushes/syncs/closes it, then atomically replaces the snapshot. Errors retain the previous save.
- **Stale fish roster:** completed results for removed/reindexed fish are discarded regardless of their old index, preventing a stalled model after selling a fish during inference.
- **Hidden damaged bundles:** packaged apps use only their own model/tokenizer/sounds; relative CLI resource fallback cannot mask missing app resources.
- **Silent failed shutdown save:** the aquarium now stays open with Retry Save / Keep Tank Open choices. Automated diagnostics return failure without displaying a blocking modal.

No new fish fields, migrations, persistent data layout, model weights, tokenizer, or device firmware changes. The original 1688-byte save format remains compatible.

## Next improvements, in priority order

1. An accessible brain/fish status indicator: AI vs rules, last delivered decision, current goal and why a fish is resting.
2. Battery-aware rendering and reduced work while hidden or minimized, verified using visible-window profiles before choosing thresholds.
3. Broader macOS/Intel support and reproducible runtime dependencies, followed by Developer ID signing and notarization for public downloads.
4. Clear desktop settings separating everyday care from inherited simulator/developer shortcuts and fake device battery/update pages.
5. Backup/restore and stronger semantic validation of corrupted saves. An inherited loader accepts some non-finite floating-point values; this port has not changed the shared save contract to address that yet.

See the audit reports for measurements, tests and limits. Constant motion is not a health criterion: fish naturally rest at night and vary goals with energy, hunger and personality.
