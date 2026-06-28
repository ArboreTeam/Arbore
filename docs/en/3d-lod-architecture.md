# LOD architecture for 3D models (catalog → light → heavy)

This view describes the **level of detail (LOD)** system for 3D plant models, as **implemented** in the iOS app and the backend. It complements the components view ([`architecture/03-components-ios.md`](architecture/03-components-ios.md), [`architecture/03-components-backend.md`](architecture/03-components-backend.md)) and decision [ADR 0006](decisions/0006-ar-quality-adaptive.md) on adaptive AR quality.

## Goal

High-definition 3D models are too heavy to be loaded as-is on mobile. The catalog therefore serves **three levels of representation** per plant:

| Level | Format | Indicative size | When |
|---|---|---|---|
| **PNG** | thumbnail | ~0.5 MB | Catalog (cards) — never any 3D |
| **LIGHT** | optimized `.usdz` | ~2–6 MB | Initial AR placement (fast download + display) |
| **HEAVY** | high-definition `.usdz` | larger | Loaded in the background during AR viewing, **swapped** in, then the light model is released |

Result: the catalog is instant (PNG), AR placement is fast (light), and the user ends up seeing the high-definition specimen with no perceptible wait.

## Runtime behavior

- **Catalog**: `ArboreUi/ArboreUi/Views/PlantCard.swift` loads the PNG thumbnail via `GET /models/thumbnails/{id}.png` (disk cache `PlantThumbnailCache`, fallback to on-device generation `PlantThumbnailGenerator`). Browsing loads **no** 3D at all.
- **3D model**: `ArboreUi/ArboreUi/Services/ModelCacheManager.swift` downloads the USDZ (disk cache keyed by file name), used in AR and for thumbnail generation.
- **Backend**: `GET /models/:filename` (protected) serves the USDZ from `./models/`; the `?lod=heavy` parameter switches the read to `./models/heavy/`. `GET /models/thumbnails/:filename` (public) serves the PNGs.

## Backend contract (`ArboreBackend/main.go`)

- **A single route** serves both levels: `GET /models/:filename` for light, `GET /models/:filename?lod=heavy` for heavy (the `./models/heavy/` subfolder). A dedicated static route segment (`/models/heavy/:filename`) was deliberately avoided because it would collide with the router's `:filename` wildcard.
- **Same file name** for light and heavy: no need for a second URL in the database, just the LOD parameter.
- Identical security validation for both: rejection of `..` / `/` / `\`, `.usdz` extension required, `Content-Type: model/vnd.usdz+zip`.

## `Plant` schema

- `Plant.hasHeavy` (`*bool`, `json/bson:"hasHeavy,omitempty"`) indicates that a heavy variant exists. `nil`/`false` = no heavy variant (the app stays on light).
- iOS: `let hasHeavy: Bool?` (`ArboreUi/ArboreUi/Models/Plant.swift`). Web: `hasHeavy?: boolean` (`web/lib/api.ts`).
- The field is persisted in the local scene (`PersistedPlant.hasHeavy`): when a garden is reopened, the heavy download can be re-triggered.

## iOS — core of the LOD

`ModelCacheManager` exposes a LOD level:

```swift
enum ModelLOD { case light, heavy }
func getModelURL(for filename: String, lod: ModelLOD = .light,
                 forceDownload: Bool = false) async throws -> URL
// light → {baseURL}/models/<filename> ; heavy → {baseURL}/models/<filename>?lod=heavy
// separate disk cache (heavy isolated), cancellable heavy download (Task).
```

In the AR placement view (`ArboreUi/ArboreUi/ARGarden/GardenARPlacementView.swift`):

1. On placement: `getModelURL(lod:.light)` → light entity added to the anchor at the hit-test position.
2. If `plant.hasHeavy == true`, a background `Task` loads the heavy model (`lod:.heavy`).
3. On success, on the main actor: copy the light model's `transform` onto the heavy one, add the heavy, remove the light → the light model's memory is released.
4. **Cancellation**: if the plant is removed / the scene changes before completion, `task.cancel()` (and the download is cancelled).
5. **Safeguards**: if `hasHeavy` is false or the heavy download fails → we **stay on light** (never a visual regression). The swap matches transform + scale exactly to avoid any "jump."

## Adaptive LOD (thermal + budget + distance)

`ArboreUi/ArboreUi/ARGarden/Quality/PlantLODPolicy.swift` and the evaluator in `GardenARPlacementView` (`evaluateLOD`, throttled at ~4 Hz) decide light/heavy through a **precedence chain** (the global gates can only *reduce* detail):

1. **Thermal (global)** — `ProcessInfo.thermalState` + Low Power Mode: `.nominal`/`.fair` → full budget; `.serious`/LowPower → everything light except the selected plant + cancellation of heavy downloads; `.critical` → everything light. Immediate downgrade when hot; re-upgrade only after a stable cool period (cooldown).
2. **Budget K (global)** — `DeviceCapabilities.tier`: K=1 (older devices) / 2 (modern). Only the K closest plants + the selected one go heavy; the surplus is downgraded. Stickiness prevents ping-ponging between equidistant plants.
3. **Distance (per plant)** — expressed as **on-screen size**: heavy as long as `distance < 2.9 × height`, with 20% hysteresis and a [0.6; 4.5] m clamp.

The swap is **reversible** (`swapModel(to:)` light↔heavy); an in-progress heavy download is treated as heavy so it is not cancelled at the slightest jitter. Everything is **fail-safe** (any error leaves the current model in place). This system complements `ARGarden/Quality/` (which handles `environmentTexturing` + thermal banner) without duplicating it.

## Risks / notes

- **Visible swap**: if the light/heavy framing differs slightly, the user may perceive a "pop." Mitigation: a slight opacity fade on swap.
- **Slow network**: the heavy model may never finish — that is acceptable, the light one stays displayed.
- **Memory**: never keep both light **and** heavy for long; release the light one right after the swap. `AppDelegate` already releases RealityKit caches on memory warning.

## Out of scope of this view

- Storage and deployment of the `.usdz`/PNG files on the VPS (gitignored) are covered in [`operations/vps-bootstrap.md`](operations/vps-bootstrap.md).
- The full `Plant` schema is documented in [`architecture/04-data-model.md`](architecture/04-data-model.md).
