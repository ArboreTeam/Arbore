# ADR 0002 — Dual scan stack: RoomPlan (LiDAR) + perimeter tracing (non-LiDAR)

- **Status**: Accepted
- **Date**: 2026-04-15
- **UX update**: 2026-07-16
- **Deciders**: Arbore team

## Context

The application must let the user **capture their space** (garden, balcony, interior) in order to place 3D plants there in augmented reality. Several technologies are available on iOS to perform this capture, with different constraints in terms of supported devices, result quality, and scan duration.

The target user base includes **every iPhone from the iPhone 11 onward** (iOS 17+), which comprises:

- Recent **iPhone Pro / Pro Max / iPad Pro** (iPhone 12 Pro+) equipped with a **LiDAR sensor**, which unlocks access to the Apple `ARKit.meshWithClassification` and `RoomPlan` APIs.
- **Non-Pro iPhones** (iPhone 11 to 15 non-Pro), which have no LiDAR and must rely on ARKit visual tracking.

The garden creation wizard must choose between these engines without imposing a technical decision page on the user.

## Decision

The application maintains **two parallel scan stacks**, selected automatically at runtime according to the space and device:

- **`gardenPerimeter` (non-LiDAR, universal default)** — `ARViewContainerMeasure` uses ARKit raycasts to let the user manually trace the **floor polygon** point by point. No 3D mesh is built; only a `[SIMD3<Float>]` representing the perimeter is saved. Works on **all** targeted iPhones.

- **`roomScan` (LiDAR only)** — `LiDARScanWizardView` uses `RoomPlan.RoomCaptureSession` to produce a structured model (walls, floors, doors, windows). It is recommended automatically for a room when `RoomCaptureSession.isSupported == true`.

Perimeter tracing is selected in every other case. The `ScanMethodSelectionView` page has been removed: after space selection, the camera prompt and scan open directly. “Change method” remains available in the camera only for a room when both RoomPlan and tracing are usable.

Apple **ObjectCapture** (`PhotogrammetrySession`, iOS 17+, Area mode iOS 18+) is **not integrated at this stage** but remains a strong candidate for extending the non-LiDAR scan into a true dense 3D reconstruction. This extension is the subject of issue #140.

## Consequences

### Positive

- Every iPhone in the target base can use the application with no functional degradation.
- LiDAR users benefit from higher scan quality (classified walls and furniture).
- The user reaches the core value — measuring their space — with one fewer page.
- The method remains changeable in the only case where a real alternative exists.

### Negative

- The codebase carries **two distinct AR flows**, which doubles the maintenance surface (see issue #81: unify the five duplicated AR view containers).
- The visual rendering differs noticeably between the two methods, which may surprise a user who switches device.
- The technical difference between engines is less visible before launch; the in-camera option compensates for this on RoomPlan devices.
- The non-LiDAR scan stays limited to the floor polygon, with no information about 3D obstacles, which rules out certain future features (automatic snapping of plants to a wall, for example).

### Neutral

- The two methods produce different data on the `GardenLocalStore` side (`boundaryPoints: [SIMD3<Float>]` versus `worldmap_{id}.arworldmap` for LiDAR). The AR layer consumes both interchangeably via the parameters of `GardenARPlacementView`.
- ObjectCapture, if integrated later (#140), would add a third stack — but the planned user experience (dedicated 30-60 s scan + 1-2 min processing) would be different enough to coexist with the two existing ones rather than replace them.

## Alternatives considered

- **ARKit `sceneReconstruction = .meshWithClassification` only (LiDAR-only)** — rejected because it would restrict the app to Pro iPhones, which would drastically shrink the user base.
- **ObjectCapture for everyone (universal non-LiDAR)** — rejected in the short term because the ObjectCapture scan UX (30-60 s of capture + 1-2 min of processing) is too heavy for the current garden creation flow. Remains a candidate for secondary features (see issue #140).
- **Custom monocular depth ML models (Depth Anything V2, MiDaS)** — anticipated in issue #97 but out of short-term scope: non-trivial CoreML conversion, uncertain on-device latency, and the floor polygon scan is sufficient for the current goal (placing plants in AR on flat ground).
- **No scan at all, the user places "by eye"** — rejected because measuring the perimeter brings real business value (displayed surface area, calibrated AI suggestion).

## Links

- [Issue #139 — end-to-end roomScan validation](https://github.com/ArboreTeam/Arbore/issues/139)
- [Issue #140 — Scene-to-scene ICP registration (where ObjectCapture is a candidate)](https://github.com/ArboreTeam/Arbore/issues/140)
- [Issue #97 — Depth Anything V2 neural pipeline (future alternative)](https://github.com/ArboreTeam/Arbore/issues/97)
- [Apple — RoomPlan documentation](https://developer.apple.com/documentation/roomplan)
- [Apple — Object Capture documentation](https://developer.apple.com/documentation/realitykit/realitykit-object-capture/)
