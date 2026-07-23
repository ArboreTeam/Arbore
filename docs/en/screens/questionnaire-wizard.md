# Per-screen spec — `QuestionnaireView` (creation wizard)

## Purpose

`QuestionnaireView` takes the user from space selection directly to AR placement, with no intermediate suggestion screen. Visible progress has four levels: space selection followed by each of the three conditional questions. Measurement, optional exposure, and location remain contextual sub-flows, with no recap page.

Main implementation: `Views/GardenSteps/QuestionnaireView.swift`.

## Entry and exits

| Action | Destination |
|---|---|
| “Create a garden” from Home | `GardenWizardView`, first `spaceType` step. |
| **Continue** after choosing a space | System camera prompt if needed, then direct scan. |
| Location confirmation | `essentialQuestions` step. |
| Third question confirmed | `GardenARPlacementView` with the already-created garden. |
| Back from the first step or X | `dismiss()` to Home. |

## Flow

```mermaid
flowchart TB
    space["1 — Choose the space"]
    permission["Camera prompt if needed"]
    scan["Automatic scan<br/>RoomPlan or tracing"]
    exposure["In-camera exposure<br/>except garden"]
    location["Fresh location"]
    questions["2 to 4 — 3 conditional questions"]
    placement["AR placement"]

    space --> permission --> scan
    scan -->|room, balcony, terrace| exposure --> location
    scan -->|garden| location
    location --> questions --> placement
```

`visibleSteps` contains only:

```swift
[.spaceType, .essentialQuestions]
```

## Automatic method selection

- Room and `RoomCaptureSession.isSupported == true`: `roomScan`.
- Every other case: `gardenPerimeter`.
- “Change method” appears in the camera only for a RoomPlan-compatible room.

The `ScanMethodSelectionView` page no longer exists. The **Continue** CTA in `SpaceTypeStepView` sets `state.scanMethod`, directly requests system permission when status is `.notDetermined`, then opens the AR full-screen cover. `GardenAnalysisAuthorizationFlowView` is only a denial-recovery screen with access to Settings.

## Sub-flows

### Measurement and creation

`ARViewContainerMeasure` traces the floor outline. `LiDARScanWizardView` uses RoomPlan. Once dimensions are confirmed, no extra verification is requested. The scan saves the WorldMap and measurements, then creates the garden through `POST /gardens` with `plants: []`.

### Exposure

For a room, balcony, or terrace, `GardenExposureCaptureOverlay` appears without closing the camera. The user aims at the main light source and confirms. A garden skips this capture.

### Location

After the camera closes, `GardenLocationCaptureView` requests a new approximate location for every garden. `state.location` is always reset before creation. Manual city entry and continuing without location remain available. The value is added to the garden through `PUT /gardens/:id`.

The resolved wizard snapshot (approximate location, exposure, orientation, and inferred sunlight) is also written as a per-garden JSON file by `ArboreUi/ArboreUi/Views/GardenLocalStore.swift`. When the 2D plan opens, captured values missing from the server response are restored from that snapshot, displayed immediately, then sent back to the backend. An existing remote value, especially a manual correction, always remains authoritative.

### Conditional questions

`EssentialQuestionsStepView` is split into three internal mini-screens. Each one strictly reuses the `SpaceTypeStepView` structure: a title, a short instruction, four large cards in a 2 × 2 grid, then “Continue” and “Back.” No question-specific indicator, label, or secondary CTA is added. Global progress moves from 1/4 on space selection to 2/4, 3/4, and 4/4 on the questions.

- Garden: planting mode, drainage after rain, safety.
- Balcony / terrace: wind, existing pots or a new composition, safety.
- Room: air humidity, nearby heating, safety.

Every question includes “I don’t know.” All answers are optional and the CTA stays active without a selection. For safety, “Pets” and “Young children” may be selected together so the grid stays at four cards. “Back” returns to the previous question; from the first one, it reopens location. Unknown values are not serialized. Known answers populate `wizard.conditionalAnswers`, while safety uses the existing `wizard.safety` field. The questions save waits for the location save so an older snapshot cannot erase the latest one, without blocking the screen while the user reads it.

### Direct placement

Confirming the third question opens `GardenARPlacementView` directly with `existingGardenId`. The user can select and place plants with the existing AR tools. Final confirmation updates the garden through `PUT /gardens/:id`, then opens its 2D plan directly in the Garden tab. The editable `GardenSpaceProfileView` groups measured, inferred, and declared data there without adding another wizard step.

## Edge cases

| Situation | Behavior |
|---|---|
| Camera already authorized | The scan opens directly. |
| First camera request | The iOS prompt appears over the space-selection screen. |
| Camera denied | Recovery screen with a Settings shortcut. |
| Location denied | Manual city or continue without location; no old position is reused. |
| Unknown or skipped question | No field is fabricated; AR placement remains available. |
| Saving questions unavailable | Answers stay in memory and are sent again with final placement. |
| Backend unavailable after tracing | Inline message and retry remain available. |
| Method change | The current camera closes and the other engine opens; only for a RoomPlan-compatible room. |

## Dependencies

- `AVFoundation`: camera status and request.
- `RoomPlan`: availability and 3D scan.
- `CoreLocation`: one-shot approximate location.
- `CoreMotion` and ARKit: orientation and light during exposure.
- `GardenAPI` / `NetworkManager`: garden creation and updates.
- Full flow: [`../flows/garden-creation.md`](../flows/garden-creation.md).
