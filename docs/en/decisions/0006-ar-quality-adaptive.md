# ADR 0006 — Adaptive AR Quality Strategy (`environmentTexturing` + thermal observer)

- **Status**: Accepted
- **Date**: 2026-05-12
- **Deciders**: Arbore Team

## Context

The `ARWorldTrackingConfiguration.environmentTexturing = .automatic` mode keeps in memory an HDR cube map that is continuously updated from the camera feed. Memory cost: 50 to 100 MB per active session, plus a few milliseconds of GPU time per frame on A15. Benefit: realistic reflections on specular materials (pot ceramics, metal, glass).

For Arbore's use case (mostly matte plants, indoor scenes or gardens), the visual benefit is low and the memory cost non-negligible — the app regularly brushes up against the iOS jetsam threshold on devices with 3 GB of RAM (iPhone XR).

In its WWDC talks ("Designing for Adverse Network and Temperature Conditions", WWDC19), Apple recommends **proactively degrading expensive graphics options** when `ProcessInfo.thermalState` deteriorates. ARKit's `.automatic` mode manages *camera coverage* but **is not thermal-aware**.

Two source issues were consolidated: #80 (`environmentTexturing` config) and #82 (thermal state observer).

## Decision

A dedicated module `ArboreUi/ArboreUi/ARGarden/Quality/` groups together the adaptive strategy. Four loosely coupled components:

| File | Responsibility |
|---|---|
| `DeviceCapabilities.swift` | Detects the device tier via `ProcessInfo.physicalMemory` (4 GB threshold). No ARKit dependency. No hardcoded model strings. |
| `ARQuality.swift` | Enum `full / standard / lite`. `static var recommended` reads `DeviceCapabilities.tier` + `ProcessInfo.thermalState` to decide on the selected level. Exposes `environmentTexturing: ARWorldTrackingConfiguration.EnvironmentTexturing`. |
| `ARQualityObserver.swift` | Singleton, listens to `ProcessInfo.thermalStateDidChangeNotification` throughout the app's lifetime. Republishes business notifications `.arboreThermalCritical` and `.arboreThermalRecovered`. Started from `AppDelegate.didFinishLaunchingWithOptions`. |
| `ThermalStateBanner.swift` | Dismissable SwiftUI overlay, subscribes to the business notifications. Attached as `overlay(alignment: .top)` on `GardenARPlacementView`. |

The six sites that set `config.environmentTexturing = .automatic` now consume `ARQuality.recommended.environmentTexturing`.

`ARQuality.recommended` is **frozen for the entire duration of an AR session**. Changing `environmentTexturing` mid-session would require `session.run(config, options: [.resetTracking])`, which would invalidate the relocalized `ARWorldMap` — too costly a sacrifice for a user who has just scanned their garden. Dynamic degradations under thermal pressure go solely through the banner UI at this stage.

## Consequences

### Positive

- On legacy devices (< 4 GB RAM) or under tight thermal conditions (`.serious`/`.critical`), `environmentTexturing` automatically falls back to `.none`, which frees up 50-100 MB of RAM right from the start of the AR session.
- The user receives explicit visual feedback (banner) when the system reports critical thermal pressure, rather than a silent slowdown due to iOS throttling.
- The architecture isolates the decision in a single module, testable independently. No caller needs to read `ProcessInfo.thermalState` nor to know the device table.
- The global observer lives in `ARQualityObserver` only once (singleton); all UI components share the same notifications.

### Negative

- On a temporarily degraded device (`.fair` at startup, returning to `.nominal` after a few minutes), `ARQuality` will have frozen `.standard` for the entire session whereas Apple might have let `.automatic` keep running. This is a slight, deliberate over-caution.
- Six AR configuration sites have been modified, which couples these views to the `ARGarden/Quality/` module. The coupling is read-only (`ARQuality.recommended.environmentTexturing`) so it stays loose, but a future migration would need to remember to update all the sites.
- A user with no preference cannot force `.lite` to save battery. This case is covered by [issue #150](https://github.com/ArboreTeam/Arbore/issues/150) (Settings toggle, out of MVP scope).

### Neutral

- The 4 GB threshold is aligned with the practical limit observed for multi-object AR usage with PBR textures. It may evolve in a successor ADR if user feedback shows a different boundary.
- The business notifications (`.arboreThermalCritical` and `.arboreThermalRecovered`) are more stable over time than the system notification and allow a single threshold policy centralized in `ARQualityObserver`.

## Alternatives Considered

- **Change nothing, leave `.automatic` everywhere** — rejected because silent iOS throttling produces subtle degradations that cannot be explained to the user. Apple explicitly recommends observing the thermal state.
- **Disable `environmentTexturing` everywhere (`.none` forced)** — rejected because iPhone 12+ devices with 4+ GB of RAM can easily absorb the cost and benefit visually from the reflections.
- **Change `environmentTexturing` dynamically during the session** — rejected because of the loss of `ARWorldMap` relocalization that a `resetTracking` would impose. The user would lose their in-progress scan session.
- **Hardcode a table of iPhone models** (XS, XR, 11, 12, …) — rejected because the table would have to be maintained with each new generation. `ProcessInfo.physicalMemory` is a stable, declarative and future-proof proxy.
- **Immediately expose the "Battery saver mode" Settings toggle** — rejected for the MVP in order to keep the logic fully automatic. The toggle is tracked by issue #150 and will rely on a `UserDefaults` value read at the start of `ARQuality.recommended`.

## Links

- [Issue #80 — Switch environmentTexturing from `.automatic` to `.none`](https://github.com/ArboreTeam/Arbore/issues/80)
- [Issue #82 — Observe the thermal state and degrade AR quality](https://github.com/ArboreTeam/Arbore/issues/82)
- [Issue #150 — "Battery saver mode" Settings toggle](https://github.com/ArboreTeam/Arbore/issues/150)
- [PR #151 — Initial implementation of the `ARGarden/Quality/` module](https://github.com/ArboreTeam/Arbore/pull/151)
- [WWDC19 — Designing for Adverse Network and Temperature Conditions](https://developer.apple.com/videos/play/wwdc2019/422/)
- [Apple — `ProcessInfo.ThermalState`](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum)
