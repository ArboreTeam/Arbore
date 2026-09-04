# Arbore Documentation — English

Technical documentation for the Arbore application, written in **Markdown + Mermaid** so it lives next to the source code and renders natively on GitHub.

> 🌍 **French version**: see [`../fr/README.md`](../fr/README.md). **French is the source of truth**; English is a full mirror. Bilingual index: [`../README.md`](../README.md).

## Reading guide

The documentation is split into complementary views. Depending on what you are looking for:

| Looking for | Location |
|---|---|
| Big picture (actors and external systems) | [`architecture/01-context.md`](architecture/01-context.md) |
| Deployable technical building blocks (containers) | [`architecture/02-containers.md`](architecture/02-containers.md) |
| Internal modules — iOS | [`architecture/03-components-ios.md`](architecture/03-components-ios.md) |
| Internal modules — Go backend | [`architecture/03-components-backend.md`](architecture/03-components-backend.md) |
| Internal modules — Next.js web | [`architecture/03-components-web.md`](architecture/03-components-web.md) |
| MongoDB data model | [`architecture/04-data-model.md`](architecture/04-data-model.md) |
| 3D model LOD architecture | [`3d-lod-architecture.md`](3d-lod-architecture.md) |
| Signup flow with Firebase rollback | [`flows/auth-signup.md`](flows/auth-signup.md) |
| Garden creation flow (wizard) | [`flows/garden-creation.md`](flows/garden-creation.md) |
| AR placement flow (creation and re-open) | [`flows/ar-placement.md`](flows/ar-placement.md) |
| Manual replacement state machine (#111) | [`state-machines/relocation-phase.md`](state-machines/relocation-phase.md) |
| Hero-screen index | [`screens/_index.md`](screens/_index.md) |
| Per-screen spec — `GardenARPlacementView` | [`screens/garden-ar-placement.md`](screens/garden-ar-placement.md) |
| Per-screen spec — creation wizard | [`screens/questionnaire-wizard.md`](screens/questionnaire-wizard.md) |
| Per-screen spec — `PersonalDetailsView` | [`screens/personal-details.md`](screens/personal-details.md) |
| Per-screen spec — plant health scan | [`screens/plant-health-scan.md`](screens/plant-health-scan.md) |
| Per-screen spec — plant catalog | [`screens/plant-catalog.md`](screens/plant-catalog.md) |
| Local notifications (watering and care) | [`architecture/notifications.md`](architecture/notifications.md) |
| Testing strategy (front + back) | [`testing/_index.md`](testing/_index.md) |
| iOS tests | [`testing/ios.md`](testing/ios.md) |
| Backend tests (Go) | [`testing/backend.md`](testing/backend.md) |
| Web tests (Vitest) | [`testing/web.md`](testing/web.md) |
| Observability (Sentry iOS + web) | [`operations/observability.md`](operations/observability.md) |
| Botanical data audit | [`operations/botanical-data-audit.md`](operations/botanical-data-audit.md) |
| TestFlight deployment (fastlane) | [`operations/testflight-deploy.md`](operations/testflight-deploy.md) |
| VPS provisioning (Docker · nginx · Mongo) | [`operations/vps-bootstrap.md`](operations/vps-bootstrap.md) |
| Architecture Decision Records (ADR) index | [`decisions/_index.md`](decisions/_index.md) |
| App Store listing (multilingual) | [`../appstore-listing.md`](../appstore-listing.md) |
| Definition of a domain or technical term | [`glossary.md`](glossary.md) |

## Structure

```
docs/
├── README.md                  # bilingual index (language switcher)
├── appstore-listing.md        # App Store listing (multilingual, neutral)
├── fr/                        # French documentation (source of truth)
├── en/                        # English mirror (this tree)
│   ├── README.md              # this document
│   ├── architecture/          # STATIC view (C4: context, containers, components, data)
│   ├── flows/                 # DYNAMIC view (sequences, flowcharts)
│   ├── state-machines/        # BEHAVIOURAL view
│   ├── screens/               # per-screen specs (hero screens)
│   ├── testing/               # test strategy and suites (front + back + web)
│   ├── operations/            # runbooks (deploy, observability, VPS)
│   ├── decisions/             # Architecture Decision Records (MADR format)
│   ├── 3d-lod-architecture.md # 3D model LOD
│   └── glossary.md            # domain vocabulary
└── legacy/                    # earlier documents, outside the rules
```

Numbered files (`01-`, `02-`) follow the recommended reading order. ADRs (`0001-`, `0002-`) are dated and **immutable** once accepted: any change yields a new ADR that supersedes the previous one.

## Authoring rules

1. **Any code PR touching a documented area must update the matching documentation in the same PR**, in **French (source of truth) AND English** (the `../fr/` mirror).
2. **One topic per file.** Three heading levels maximum.
3. **Context around every diagram.** Two or three lines of context before, two or three lines of takeaways after. A standalone diagram is only readable by its author.
4. **C4 model limited to Context, Container and Component levels.** The Code level (UML class diagrams) is deliberately omitted: the source code stands in.
5. **Per-screen specs are reserved for hero screens** (three to five screens maximum). Simple screens are described in one line under `flows/`.
6. **ADRs are short** (one page max), named `NNNN-kebab-case.md` and never modified after acceptance: create a new ADR to supersede.
7. **For a layout issue on a C4 Mermaid diagram**, reorder the element declarations in the source. The `Lay_U/D/L/R` directive is not supported yet.

## Mermaid diagram types used

| Need | Mermaid type |
|---|---|
| Actors and external systems (C4 Context) | `flowchart TB` with `[Person]` / `[System Ext]` labels |
| Deployed applications and services (C4 Container) | `flowchart TB` with `[Container]` labels |
| Internal modules of a service (C4 Component) | `flowchart TB` with `[Component]` labels |
| Relational data schema | `erDiagram` |
| Linear screen sequence | `flowchart TD` |
| Actor interaction over time | `sequenceDiagram` |
| Discrete states and transitions | `stateDiagram-v2` |

## CI contract

Any PR targeting `main` that modifies a file under `docs/`, or a source file cited by the documentation (`ArboreUi/**/*.swift`, `ArboreBackend/**/*.go`), triggers the `.github/workflows/docs.yml` workflow. It runs three jobs in parallel and blocks the merge if any fails.

| Job | Tool | Failure cause |
|---|---|---|
| **Mermaid syntax** | [`@mermaid-js/mermaid-cli`](https://github.com/mermaid-js/mermaid-cli) | A ` ```mermaid ` block under `docs/**/*.md` fails to render (invalid syntax, reserved keyword as a node ID, unescaped special character). |
| **Internal links** | [`lycheeverse/lychee-action`](https://github.com/lycheeverse/lychee-action) in `--offline` mode | An internal link under `docs/` points to a missing file or anchor. |
| **Doc drift** | `.github/scripts/docs-drift-check.sh` | A code path cited in backticks (e.g. `Services/NetworkManager.swift`) matches no file in the repository. Detects renames and deletions. |

Drift matching is **suffix-based**: `Models/User.swift` is valid if a repo file ends with it (e.g. `ArboreUi/ArboreUi/Models/User.swift`). Reproduce locally:

```sh
bash .github/scripts/docs-drift-check.sh
```

## Tools and status

- **Markdown + Mermaid** — native GitHub rendering, diff-able, no external tooling.
- **C4 semantics carried by `flowchart`.** Mermaid's native `C4Context`/`C4Container` syntax is marked [`experimental`](https://mermaid.js.org/syntax/c4.html) and produces edge overlaps beyond a dozen elements. The convention adopted uses `flowchart` with `[Person]`, `[Container]`, `[System Ext]` prefixed labels. Decision tracked in [ADR 0001](decisions/0001-mermaid-for-docs.md).
- **MADR** — see [adr.github.io/madr](https://adr.github.io/madr/) for the full format.

## Legacy documents

The following files predate this structure and are isolated under [`../legacy/`](../legacy/). They remain available for historical reference but are outside the scope of the rules above.

- [`../legacy/AR_CAMERA_BLACK_SCREEN_FIX.md`](../legacy/AR_CAMERA_BLACK_SCREEN_FIX.md) — AR camera black-screen fix notes
- [`../legacy/CI-CD.md`](../legacy/CI-CD.md) — detailed historical CI/CD documentation
- [`../legacy/DEBUG_MODE_VISUAL_SUMMARY.md`](../legacy/DEBUG_MODE_VISUAL_SUMMARY.md), [`../legacy/DEBUG_THUMBNAIL_MODE.md`](../legacy/DEBUG_THUMBNAIL_MODE.md) — thumbnail debug guides
- [`../legacy/TROUBLESHOOTING.md`](../legacy/TROUBLESHOOTING.md) — CI troubleshooting guide
