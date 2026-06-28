# Per-screen specs — Index

This section gathers the **per-screen specs** for screens qualified as "hero screens": complex, business-critical screens, or screens that concentrate enough logic to warrant dedicated documentation.

Simple screens (a button, a navigation step, a static list) do **not** have a per-screen spec — they are described in a single line in the flows [`../flows/`](../flows/) when relevant.

## Criteria for promotion to hero screen

A screen becomes a hero screen, and therefore a target for a per-screen spec, when **at least two** of the following criteria are met:

- The screen carries an explicit **state machine** (several distinct phases with transitions).
- The file exceeds **1,000 lines** of code.
- The screen calls **more than two distinct backend endpoints**.
- The screen combines **multiple Apple frameworks** (ARKit + SceneKit + SwiftUI, for example).
- The screen is mentioned in **at least three GitHub issues** (open or closed) — a signal that it concentrates debt or recurring bugs.
- The screen carries a specific **security or GDPR contract**.

## Documented hero screens

| Screen | File | Criteria met |
|---|---|---|
| `GardenARPlacementView` | [`garden-ar-placement.md`](garden-ar-placement.md) | State machine (`RelocationPhase`), 3,300 LOC, 3 frameworks (ARKit + SceneKit + SwiftUI), ≥ 5 issues (#96, #111, #113, #114, #123, #124, #136, #138). |
| Garden creation wizard | [`questionnaire-wizard.md`](questionnaire-wizard.md) | 10 steps with skip rules, `POST /gardens` + branching into two distinct AR flows, ≥ 3 issues (#139, #21, #97). |
| `PersonalDetailsView` | [`personal-details.md`](personal-details.md) | `PATCH /users/me` + Firebase `displayName` update, save state machine (idle → saving → success/error), issue #138. |

## Undocumented hero screens (to be promoted if needed)

The following screens are borderline but are not yet documented. They will be promoted if their complexity grows or if several bugs concentrate in them:

- `LiDARScanWizardView` — single screen but RoomPlan + transition to `GardenARPlacementView`. Tracked by issue #139.
- `ARViewContainerMeasure` — single screen, mainly for non-LiDAR perimeter tracing.
- `SignUpView` — critical flow (#137) but the details are already in [`../flows/auth-signup.md`](../flows/auth-signup.md).
- `CatalogueView` and `PlantCatalogView` — listings with filters but without complex logic.

## Structure of a per-screen spec

Each hero screen follows this structure:

1. **Purpose** — one or two sentences explaining the reason the screen exists.
2. **Entry points** — who can route to this screen and with what parameters.
3. **Exit points** — where navigation goes next depending on user actions.
4. **Screen-level flow** — Mermaid diagram (`flowchart` or `stateDiagram-v2`) of the intra-screen sequence.
5. **Widgets** — subsections per significant widget, with a mini state diagram if needed.
6. **Edge cases** — behavior on loading, empty state, error, offline mode, and denied iOS permissions.
7. **Dependencies** — backend APIs called, shared state (`@EnvironmentObject`, external `@StateObject`), iOS permissions, Apple frameworks used.

This structure is inspired by the Shopify Polaris and Material Design 3 design systems, adapted to the native iOS context.
