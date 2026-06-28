# ADR 0003 — Relocalization strategy: ARWorldMap + manual replace fallback

- **Status**: Accepted
- **Date**: 2026-04-29
- **Deciders**: Arbore Team

## Context

When a user creates a garden in the app, the positions of the 3D plants are **anchored to the real world** through `ARAnchor`s. For those positions to be restored when the garden is reopened (potentially several days or weeks later), the AR session state must be serialized — `ARKit` provides **`ARWorldMap`** for this purpose.

The problem: relocalization against a saved `ARWorldMap` is not reliable. ARKit relies on **visual feature points** detected at creation time, and does not always manage to find them again if:

- The lighting has changed (day vs. night, weather, shadows).
- The environment has been altered (furniture moved, existing plants having grown).
- The device has changed (different camera, different calibration).

On a LiDAR device, the structural mesh of the room helps. On a non-LiDAR device, relocalization **fails regularly** (see issue #96), which would leave the user stuck on a coaching screen with no way out.

## Decision

The app adopts a **three-tier relocalization strategy** documented in [`../flows/ar-placement.md`](../flows/ar-placement.md):

1. **Tier 1 — `ARWorldMap.relocalize`**: the classic attempt when the AR session starts. If the lighting is compatible, relocalization succeeds within a few seconds and the plants are restored via their `ARAnchor`s.

2. **Tier 2 — Manual replacement (issue #111)**: if tier 1 does not succeed, the user can tap **"Replace manually"**. They retrace the garden perimeter, and the plant positions are **morphed automatically** using Mean Value Coordinates (Floater 2003) from the old perimeter to the new one. A per-plant distortion score warns the user about areas of strong deformation, and an `adjusting` mode lets them fine-tune positions manually before the final save.

3. **Tier 3 — Scene-to-scene ICP (issue #140, future)**: eventually, capturing a new 3D scene (LiDAR via `ARKit.meshWithClassification` or non-LiDAR via `ObjectCapture`) and **registering** it against the saved scene to compute a rigid transformation. The post-alignment RMS score would also serve as a similarity indicator to show the user ("your garden has changed"). This avenue still needs to be validated through a spike.

The neural depth + matching pipeline (issue #97) remains a candidate for a fourth tier **only** if tiers 1-3 prove insufficient in production.

## Consequences

### Positive

- The user is **never stuck** on an endless coaching screen: manual replace is immediately available.
- MVC morphing produces acceptable results even when the shape of the perimeter changes significantly between sessions.
- The strategy is **layered**: the least expensive option is tried first (ARWorldMap), degrading to the more expensive ones if needed (manual replace, then ICP).

### Negative

- The post-manual-replace user experience depends on the quality of the tracing and the morphing — plants can end up in areas of strong distortion, flagged in orange but requiring a manual adjustment.
- Manual replace only works if **the old perimeter** is readable from memory (loaded from `scene_{id}.json`). If that file does not exist (the case of a freshly installed device, see issue #114), even manual replace is impossible and the user sees the `gardenUnavailableView`.
- The tier-2 code has substantially increased the size of `GardenARPlacementView` (from ~2,000 to ~3,300 lines), worsening the technical debt of the god object (issue #124).

### Neutral

- MVC morphing is testable in isolation (pure math) and will be the subject of dedicated unit tests (issue #123).
- Tier 3 (scene-to-scene ICP) remains an architectural bet to confirm — adding it does not call tier 2 into question but offers a faster alternative for LiDAR users.

## Alternatives considered

- **Bet everything on `ARWorldMap.relocalize` and block the user on failure** — the initial approach, abandoned after negative tester feedback (issue #96).
- **Save plant positions as GPS coordinates** — ruled out because GPS accuracy (a few meters) is completely incompatible with the precise intra-garden placement the app needs.
- **Require a "reference pose" at the start of every session** — ruled out due to excessive UX friction (the user would have to stand exactly where they saved, which is rarely possible).
- **A backend that stores positions and has the user replace them from scratch** — ruled out because it would lose the whole point of AR: the position would be in an abstract frame of reference, not in the real world.

## Links

- [Issue #96 — Relocalization fails when the lighting changes](https://github.com/ArboreTeam/Arbore/issues/96)
- [Issue #111 — Manual replace with morphing (merged 2026-04-29)](https://github.com/ArboreTeam/Arbore/issues/111)
- [Issue #140 — Scene-to-scene ICP registration (future)](https://github.com/ArboreTeam/Arbore/issues/140)
- [Issue #97 — Neural depth + matching pipeline](https://github.com/ArboreTeam/Arbore/issues/97)
- [Issue #114 — Garden lost after app reinstall](https://github.com/ArboreTeam/Arbore/issues/114)
- [Apple — ARWorldMap documentation](https://developer.apple.com/documentation/arkit/arworldmap)
- [Floater, M. S. (2003). Mean value coordinates. *Computer Aided Geometric Design*.](https://www.cs.jhu.edu/~misha/Fall09/Floater03.pdf)
