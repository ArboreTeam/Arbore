# Screen — Plant catalog

The catalog lets the user **browse and filter** the plant reference set, and shows for each plant a **compatibility badge** with their garden (based on the collected profile). It is also the entry point to AR placement.

Files: `PlantCatalogView.swift` (screen + filters), `PlantCatalogContext.swift` (filter dimensions + `PlantSuitabilityEvaluator`), `PlantCatalogPreferenceViews.swift` (preferences/filters UI).

## Two distinct mechanisms

1. **Filtering** — the user narrows the list along catalog dimensions.
2. **Compatibility evaluation** — each plant is scored against the **garden profile** (`GardenWizardDTO`) and gets a level.

> ⚠️ This catalog scoring (`PlantSuitabilityEvaluator`, based on `GardenWizardDTO`) is **distinct** from the wizard's suggestion scoring (`GardenSuggestionEngine`). Both coexist today — consolidation still to be decided (see audit #319).

## Filter dimensions

Defined in `PlantCatalogContext.swift`, each a filterable `enum`:

| Dimension | Examples |
|---|---|
| `PlantCatalogGoal` | goal (decorative, vegetable garden, air-purifying…) |
| `PlantCatalogKind` | type (tree, flower, succulent…) |
| `PlantCatalogColor` | dominant color |
| `PlantCatalogAppearance` / `PlantCatalogHabit` | habit / silhouette |
| `PlantCatalogScale` / `PlantCatalogSize` | size class |
| `PlantCatalogCareLevel` | care requirement |

The garden style (former wizard step) is meant to live **here, as a filter**, rather than as a step in the creation flow.

## Compatibility evaluation (`PlantSuitabilityEvaluator`)

The evaluator aggregates several **criteria**, each producing a score, then derives an overall level:

| Criterion | Based on (profile / plant flags) |
|---|---|
| Space (`appendSpaceCriterion`) | `wizard.spaceType` (interior/balcony/terrace/garden) |
| Sunlight (`appendSunlightCriterion`) | `wizard.siteProfile.sunlight` vs the plant's tolerances |
| Safety (`appendSafetyCriteria`) | `wizard.safety` vs `flags.toxicToPets` / `toxicToChildren` |
| Planting (`appendPlantingCriterion`) | `conditionalAnswers.plantingMode == .containers` |
| Drainage (`appendDrainageCriterion`) | `conditionalAnswers.drainage` vs `flags.humidityLoving` |
| Wind (`appendWindCriterion`) | `conditionalAnswers.windExposure` / `siteProfile.wind` |
| Humidity (`appendHumidityCriterion`) | `conditionalAnswers.indoorHumidity` |
| Heat (`appendHeatCriterion`) | `conditionalAnswers.nearbyHeat` |
| Height (`appendHeightCriterion`) | `siteProfile.availableHeight` |

Level (`PlantSuitabilityLevel`): `unsuitable` → `neutral` → `suitable` → `verySuitable`. A **critical** criterion (e.g. toxic while the user has pets) pulls the level down. Each criterion carries a localized reason shown to the user.

> Criteria only apply when the matching profile data is present: an incomplete profile scores on fewer criteria (possibly none → no badge), and never crashes.

## Key points

- **Decoupled from the wizard UI**: the evaluator reads the **DTO** (`GardenWizardDTO`), not the wizard's screen state — so it is independent of the active creation flow.
- **Plant data**: compatibility relies on the plant record's `flags` (toxicity, humidity-loving…) and the catalog's LOD/botanical schema.
- **Known duplication**: two scoring systems (`PlantSuitabilityEvaluator` catalog vs `GardenSuggestionEngine` wizard) — kept in place until the flow is frozen (see #319).

## Out of scope for this view

- AR plant placement is documented in [`garden-ar-placement.md`](garden-ar-placement.md).
- Plant record generation (AI Generator) and 3D LOD are in [`../3d-lod-architecture.md`](../3d-lod-architecture.md).
