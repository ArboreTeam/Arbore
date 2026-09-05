# Flow — Creating a garden (wizard)

This document describes the **flow for creating a new garden** by the user, from the wizard intro all the way to the final save of the placement. The reference code is `Views/GardenSteps/QuestionnaireView.swift`, which drives the wizard's `TabView`.

## Overview

The wizard is made up of a variable number of steps (between 8 and 9 depending on user choices), implemented as a non-pageable SwiftUI `TabView` whose selection is governed by the `GardenWizardStep` enum. The list of steps actually displayed is computed by the `visibleSteps` computed property.

The **garden scan** happens at the `scanMethod` step (before the AI suggestion): tapping the primary CTA directly opens the AR tracing view, which calls `POST /gardens` at the end of the trace to create the garden in the database along with its boundary. After the scan, the camera closes and the user can provide a location for this specific garden; when available, that location triggers backend-side climate enrichment. The wizard then takes over again and presents the `aiSuggestion` step, which can consume the real `state.measuredArea` / `state.measuredPerimeter` measurements and the climate profile for its ranking. The final CTA of the `aiSuggestion` step opens `GardenARPlacementView` on the brand-new garden in `.create` mode and triggers auto-placement of the selected plants.

## Diagram

```mermaid
flowchart TB
    start_node([Tap Create a garden<br/>from Home])

    intro["Step 1 — Intro"]
    style_step["Step 2 — Style"]
    spaceType["Step 3 — Space type"]
    exposure["Step 4 — Exposure"]
    maintenance["Step 5 — Maintenance"]
    safety["Step 6 — Safety"]
    soil["Step 7 — Soil<br/>(spaceType garden only)"]
    scan["Step 8 — Scan method<br/>perimeter vs roomScan"]

    trace_ar["fullScreenCover AR<br/>ARViewContainerMesure or LiDARScanWizardView<br/>user traces + validates"]
    post_garden["POST /gardens<br/>boundary + wizard + plants: []"]
    location["Garden location<br/>approximate position, city, or skip"]
    climate["POST /climate/profile<br/>regional climate + frost + coast"]
    update_garden["PUT /gardens/:id<br/>wizard.location + wizard.siteProfile"]
    ai["Step 9 — AI Suggestion<br/>plant selection (area-aware)"]
    placement["fullScreenCover<br/>GardenARPlacementView (.create + existingGardenId)"]
    auto_place["AI auto-placement<br/>+ manual adjustment"]
    put_garden["PUT /gardens/:id<br/>plants positions"]

    home([Back to Home])

    start_node --> intro --> style_step --> spaceType
    spaceType -->|indoor or balcony| exposure
    spaceType -->|garden| exposure
    exposure --> maintenance --> safety
    safety -->|garden| soil --> scan
    safety -->|otherwise| scan

    scan -->|tap Start scan| trace_ar
    trace_ar --> post_garden
    post_garden --> location
    location --> climate
    climate --> update_garden
    update_garden -->|back to wizard| ai
    ai -->|tap Place my plants in AR| placement
    placement --> auto_place
    auto_place -->|tap Validate and save| put_garden
    put_garden --> home

    classDef step  fill:#1168BD,stroke:#0B4884,color:#fff
    classDef cond  fill:#2E7D32,stroke:#1B5E20,color:#fff
    classDef ar    fill:#6A1B9A,stroke:#4A148C,color:#fff
    classDef io    fill:#999,stroke:#666,color:#fff
    class intro,style_step,spaceType,exposure,maintenance,safety,soil,scan,location,ai step
    class post_garden,climate,update_garden,put_garden cond
    class trace_ar,placement,auto_place ar
    class start_node,home io
```

## Skip rules and conditions

The `visibleSteps` computed property in `QuestionnaireView.swift` implements the logic:

```swift
private var visibleSteps: [GardenWizardStep] {
    var steps: [GardenWizardStep] = [.intro, .style, .spaceType, .exposure, .maintenance, .safety]
    if state.spaceType == .garden {
        steps.append(.soil)
    }
    steps.append(contentsOf: [.scanMethod, .aiSuggestion])
    return steps
}
```

Consequence:

| User choice | Steps displayed |
|---|---|
| `spaceType == .indoor` or `.balcony` | intro · style · spaceType · exposure · maintenance · safety · scanMethod · aiSuggestion (8 steps) |
| `spaceType == .garden` | intro · style · spaceType · exposure · maintenance · safety · **soil** · scanMethod · aiSuggestion (9 steps) |

The `soil` step only makes sense in open ground — it is the only skip rule to date.

## Step-by-step details

### Step 1 — Intro

Welcome screen. Describes in two sentences what the wizard will offer and invites the user to get started. No user input. The `GardenWizardState` remains blank.

### Step 2 — Style

Choice among several aesthetic styles (modern, zen, wild, Mediterranean, etc.). Sets `state.style`.

### Step 3 — Space type

Three options: `indoor`, `balcony`, `garden`. Sets `state.spaceType`. **This is the step that determines whether `soil` will be displayed later on.**

### Step 4 — Exposure

Full sun, partial shade, shade. Sets `state.exposure`.

### Step 5 — Maintenance

Low, medium, high. Sets `state.maintenance`.

### Step 6 — Safety

Multiple selection: children, animals, allergies. Sets `state.safetySelections`.

### Step 7 — Soil *(conditional)*

Appears only if `state.spaceType == .garden`. Soil type that will feed into the later AI ranking.

### Step 8 — Scan method

`ScanMethodStepView` component. Two cards:

- **Trace my garden on the ground** (`gardenPerimeter`) — available on all iPhones.
- **Scan the room in 3D** (`roomScan`) — grayed out if `RoomCaptureSession.isSupported == false`.

Sets `state.scanMethod`. The primary CTA **"Start scan"** directly opens the corresponding AR view (not just a plain `Continue`).

#### Sub-flow AR trace (perimeter)

When the user lands in `ARViewContainerMesure`:

1. The ARSession starts and a centered reticle shows whether a horizontal floor is available.
2. The user aims at each edge of the space and taps **Add a point**. The point is placed with a raycast at the center of the screen; duplicate placements within 12 cm are rejected.
3. Points and segments are visible directly in the camera. From three vertices onward, their cyclic order is recalculated and crossing edges are removed automatically, including when rectangle corners were placed in diagonal order.
4. The panel shows the live point count, area, and perimeter. **Undo** removes the point that was actually placed last, **Start over** clears the outline, and **Plan** opens the top view.
5. On tapping **Confirm boundary**:
   1. For a room, balcony, or terrace, tracing controls disappear while the camera stays open. The user aims at the main window, outside, or the most open side, then taps **Set this exposure**. Arbore records the horizontal direction in the AR frame, the available magnetic heading, and the instantaneous ambient light.
   2. For a garden, this capture is skipped: exposure can later be estimated from its location and geometry.
   3. The current ARKit WorldMap is saved to disk under `tempGardenId`.
   4. A `scene_{tempGardenId}.json` file is written with `plants: []`, the boundary, the area, and the perimeter.
   5. `POST /gardens` is called with `name`, `wizard` (including `lightExposure` when available), `plants: []`, and `thumbnailKey`.
   6. If the server returns an `id` different from `tempGardenId`, both local files are migrated to the new id.
   7. The camera closes. `GardenLocationCaptureView` requests a new approximate position, a manually entered city, or allows skipping. The result is copied to `state.location`, sent to `POST /climate/profile` when available, then persisted with `wizard.siteProfile` through `PUT /gardens/:id`.
   8. The wizard calls `goToNext()` → `aiSuggestion` step.

#### Sub-flow LiDAR scan (roomScan)

Symmetrical to the perimeter flow, in `LiDARScanWizardView`:

1. RoomPlan captures the room in 3D.
2. On tapping **Scan complete**, the WorldMap is saved and the area / perimeter are extracted from the `CapturedRoom`.
3. `POST /gardens` then file migration, identically.
4. `state.createdGardenId` is set (the 2D boundary stays empty for LiDAR), back to the wizard.

### Step 9 — AI Suggestion

`AISuggestionStepView` component. The **final** step of the wizard. Uses `GardenSuggestionEngine` to propose a plant selection tailored to the profile built up (and potentially to the measured surface — enrichment in progress, see issue #125). The user can:

- Accept the suggestion as is.
- Add / remove plants manually from the catalog.

The primary CTA **"Place X plants in AR"**:

1. Updates `aiSelectedPlants` from the accepted cards.
2. Calls `startFinalPlacement()`, which opens `GardenARPlacementView` in `.create` mode with `existingGardenId = state.createdGardenId`, `measurementWorldMapId = state.createdGardenId`, and the measured boundary.
3. The AR view loads the WorldMap from disk, starts a session, and auto-places the plants the moment tracking becomes stable.
4. On final validation, **`PUT /gardens/:id`** updates the existing garden with the plant positions (`POST` is avoided because the garden already exists).

### Space profile in the 2D plan

The recap is not a blocking wizard step. It lives permanently below the plan in `GardenSpaceProfileView` and always identifies the source (`measured`, `inferred`, `declared`, `regional estimate`) and confidence.

- Space type, area, perimeter, orientation, sunlight, soil type, location, wind, height, and plantable zones are shown.
- For a room, balcony, or terrace, the captured magnetic orientation becomes a measured value with medium confidence. When usable coordinates exist, Arbore may infer a broad sunlight range from orientation and hemisphere; it remains labelled as inferred with low confidence. A duration declared for a room replaces this estimate. Instantaneous ARKit light intensity is never converted into daily sunlight hours.
- Missing data stays “Measurement unavailable”; no default is presented as real data.
- Area and perimeter are corrected with “Measure the space again.” The scan replaces the local outline and persists `measurements.boundaryPoints`, `area`, and `perimeter` through `PUT /gardens/:id` so the plan stays consistent.
- Other values are corrected in a sheet persisted through `PUT /gardens/:id`.
- Plantable zones are polygons in the outline's coordinate frame. They can be drawn, renamed, excluded, or deleted and are overlaid on the 2D plan.

## Creating the garden in the database — recap

The historical `POST /gardens` happened **at the very end** of placement (in `GardenARPlacementView.handleValidateNotif`). The new flow triggers it **at the end of the trace** (`scanMethod` step), with `plants: []`. Consequences:

- The garden exists in the database as early as the `aiSuggestion` step, which would eventually enable an area-aware `aiSuggestion` step (issue #125).
- A user who dismisses after the trace but before placing plants leaves an orphan garden with `plants: []`. It will be visible from the Home and can be deleted manually.
- The save logic in `GardenARPlacementView.handleValidateNotif` picks `PUT` vs `POST` based on `existingGardenId` (and no longer based on `mode == .reopen`).

## Persistence during the wizard

`GardenWizardState` is a `@StateObject` that lives for the entire wizard session. **No disk persistence** of the preference fields (style, spaceType, etc.) until the trace is validated. If the user dismisses before the trace, the choices are lost.

**Starting from the validated trace**, the garden exists in the database. Preference choices, dimensions, and optional exposure are persisted through `POST /gardens`. After the camera closes, the location specific to this creation is added to the same `garden.wizard` through `PUT /gardens/:id`. When a city or approximate position is available, the client also calls `POST /climate/profile`: the backend performs coarse commune geocoding, uses a configured Météo-France station when possible, then returns a regional profile with historical temperatures, frost risk, wind, and coastal exposure. These writes are serialized so an older snapshot cannot finish last and erase the location or climate. Before each send, Arbore also materializes measured or inferred orientation, sunlight, and climate enrichment in `wizard.siteProfile`. The same resolved wizard is stored locally as a per-garden JSON snapshot by `ArboreUi/ArboreUi/Views/GardenLocalStore.swift`. The 2D plan restores only captured data missing from the server, displays it immediately, then repairs the remote document without overwriting an existing correction. The final placement update sends the complete wizard again and waits for intermediate writes to finish.

After creation, corrections made in the 2D profile are persisted in `wizard.siteProfile` through `PUT /gardens/:id`.

## Error cases

| Situation | Behavior |
|---|---|
| `POST /gardens` fails at the end of the trace (`scanMethod` step) | Inline error message in the trace fullScreenCover. The CONTINUE button stays available for retry. No garden is created until the POST has succeeded. |
| LiDAR selected on a device without LiDAR | Should not happen — the LiDAR card is grayed out. If a corrupted state nonetheless lets it through, `LiDARScanWizardView` shows a "3D scan unavailable" alert and stays on the screen. |
| Network connection dropped when tapping CONTINUE at the `scanMethod` step | The `POST /gardens` fails, inline message, retry possible. |
| Camera permission denied | Branching into AR is impossible. An iOS system modal appears when the AR view is opened. |
| Location denied or unavailable | The screen offers manual city entry or continuing without location. No previous location is reused. |
| Climate enrichment unavailable | The flow continues without blocking. The catalog engine keeps missing data as “to confirm.” |
| Location `PUT /gardens/:id` fails | The flow continues with the value kept in `GardenWizardState`; the final placement `PUT` retries persisting the complete wizard. |
| User dismisses after the trace but before placement | Orphan garden in the database with `plants: []`. Visible and deletable from the Home. |
| `PUT /gardens/:id` fails at the end of placement | Local files kept under the tempID. Error message. To retry. |

## Out of scope for this flow

- The **internal detail of AR placement** (raycasts, anchors, gestures, RelocationPhase state) is documented in [`ar-placement.md`](ar-placement.md).
- The **filtering and ranking** logic of `GardenSuggestionEngine` at the AI Suggestion step will be documented in a per-screen spec if the screen becomes a hero screen.
- The **exact schema** of the `gardens` document on the Mongo side is in [`../architecture/04-data-model.md`](../architecture/04-data-model.md).
