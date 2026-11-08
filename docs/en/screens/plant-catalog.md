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
| `PlantCatalogGoal` | design goal: add color, create privacy, cover a wall, attract pollinators, edible/aromatic, focal point… |
| `PlantCatalogKind` | type: green plant, flowering, cactus/succulent, palm, fern, orchid, tree, shrub, perennial, annual, grass, groundcover, climbing, edible/aromatic |
| `PlantCatalogColor` | dominant color: white, yellow, orange, red, pink, purple, blue, green, **silver**, **brown**, dark |
| `PlantCatalogAppearance` / `PlantCatalogHabit` | habit: upright, spreading, climbing, trailing |
| `PlantCatalogScale` / `PlantCatalogSize` | size class: compact, balanced, statement |
| `PlantCatalogCareLevel` | care requirement: minimal, regular |

The garden style (former wizard step) is meant to live **here, as a filter**, rather than as a step in the creation flow.

## Where the dimensions come from (#792)

**They are read, no longer inferred.** Each dimension maps to a stored field of
`botanicalProfile`, as a closed, sourced value.

Until #792, seven `PlantCatalogContext` functions derived them by matching
keywords against the plant's **translated description**. Three measured
consequences:

- `size()` depended on the **display language** — the same plant could be
  `large` in French and `unknown` in German;
- `isFlowering()` read `flags.flowering`, then, if the flag was `false`, fell
  back to prose: a description mentioning "flower" was enough to declare the
  plant flowering, and the flag's `false` asserted nothing;
- the `size()` keyword list contained `"mini "` **with a trailing space**, a
  guard added after the fact against false matches.

Those functions are deleted. The criterion's guard is one command:

```sh
grep -rn "containsAny\|searchableText" ArboreUi/ArboreUi/   # must stay empty
```

**Three dimensions return nothing today**, for lack of a closed source, and
that is deliberate: `colors` (no source in the corpus), the `variegated` /
`evergreen` / `fragrant` appearances, and the `upright` / `spreading` habits.
They used to be **guessed** — the "upright habit" filter actually returned the
whole catalogue, because `.upright` was inserted by default when nothing was
found. Offering a choice no data can answer is worse than not offering it:
that is the doctrine already applied to `FilterView.difficultyOptions`, to be
extended here.

## The numeric bounds live in one place (#793)

`Models/PlantThresholds.swift` holds the numbers that decide what is shown and
what is recommended. Each is named and carries the reason for its value beside
it.

It exists because the duplication had already produced a **user-visible**
defect: the filter defined "little watering" as 10 days and up, while the
suitability evaluator was satisfied by 7. A plant with a 7-to-8-day interval was
therefore announced as a **good choice** by the recommendation and **hidden** by
the filter.

| group | bounds |
|---|---|
| `Light` | shade up to 3 h, full sun from 6 h |
| `Watering` | often ≤ 3 d · moderate 4–9 d · little ≥ 10 d |
| `Scoring` | the suggestion engine's six weights |

The three watering buckets **partition** the line: every interval falls into
exactly one bucket, with no gap and no overlap. That is the precondition for the
filter and the evaluator to say the same thing about the same plant.

The light bounds were copied in **four** places, one of them added with a
comment that *asked* for consistency while copying the numbers. A comment does
not hold an invariant; a test does.

`testCeQueLEvaluateurAppelleUnBonChoixLeFiltreLeMontre` asserts the
**agreement**, not the value: the bound can be rejudged without the test
failing, but what the evaluator calls a good choice, the filter must show. It
was confronted with the defect before being kept — with 7 reintroduced on one
side and 10 on the other, it fails.

### The diversity rule no longer depends on language

"At most two plants of the same nature per suggestion" grouped on the free-text
`plant.type`, normalised by two hardcoded **French** strings. For an
English-only record — 877 of 1021 — the normalisation did nothing. The rule now
reads `kinds`, and groups on the first nature **in vocabulary order**: a `Set`'s
order is not stable between runs, and a suggestion must be reproducible.

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
- 3D LOD is documented in [`../3d-lod-architecture.md`](../3d-lod-architecture.md).
