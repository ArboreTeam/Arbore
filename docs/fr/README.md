# Documentation Arbore — Français

Documentation technique de l'application Arbore, rédigée en **Markdown + Mermaid** afin de vivre à côté du code source et d'être rendue nativement par GitHub.

> 🌍 **Version anglaise** : voir [`../en/README.md`](../en/README.md). Le **français est la langue de référence** ; l'anglais en est un miroir complet. Index bilingue : [`../README.md`](../README.md).

## Guide de lecture

La documentation est découpée en vues complémentaires. Selon l'information recherchée :

| Information recherchée | Emplacement |
|---|---|
| Vue d'ensemble (acteurs et systèmes externes) | [`architecture/01-context.md`](architecture/01-context.md) |
| Briques techniques déployées (containers) | [`architecture/02-containers.md`](architecture/02-containers.md) |
| Modules internes côté iOS | [`architecture/03-components-ios.md`](architecture/03-components-ios.md) |
| Modules internes côté backend Go | [`architecture/03-components-backend.md`](architecture/03-components-backend.md) |
| Modules internes côté web Next.js | [`architecture/03-components-web.md`](architecture/03-components-web.md) |
| Schéma de données MongoDB | [`architecture/04-data-model.md`](architecture/04-data-model.md) |
| Architecture LOD des modèles 3D | [`3d-lod-architecture.md`](3d-lod-architecture.md) |
| Flow de signup avec rollback Firebase | [`flows/auth-signup.md`](flows/auth-signup.md) |
| Flow de création de jardin (wizard) | [`flows/garden-creation.md`](flows/garden-creation.md) |
| Flow de placement AR (création et réouverture) | [`flows/ar-placement.md`](flows/ar-placement.md) |
| Machine d'états du manual replacement (#111) | [`state-machines/relocation-phase.md`](state-machines/relocation-phase.md) |
| Index des hero screens | [`screens/_index.md`](screens/_index.md) |
| Per-screen spec — `GardenARPlacementView` | [`screens/garden-ar-placement.md`](screens/garden-ar-placement.md) |
| Per-screen spec — wizard de création | [`screens/questionnaire-wizard.md`](screens/questionnaire-wizard.md) |
| Per-screen spec — `PersonalDetailsView` | [`screens/personal-details.md`](screens/personal-details.md) |
| Per-screen spec — scan de santé des plantes | [`screens/plant-health-scan.md`](screens/plant-health-scan.md) |
| Per-screen spec — catalogue de plantes | [`screens/plant-catalog.md`](screens/plant-catalog.md) |
| Notifications locales (arrosage et soins) | [`architecture/notifications.md`](architecture/notifications.md) |
| Stratégie de test (front + back) | [`testing/_index.md`](testing/_index.md) |
| Tests iOS | [`testing/ios.md`](testing/ios.md) |
| Tests Backend (Go) | [`testing/backend.md`](testing/backend.md) |
| Tests Web (Vitest) | [`testing/web.md`](testing/web.md) |
| Observabilité (Sentry iOS + web) | [`operations/observability.md`](operations/observability.md) |
| Déploiement TestFlight (fastlane) | [`operations/testflight-deploy.md`](operations/testflight-deploy.md) |
| Provisionnement VPS (Docker · nginx · Mongo) | [`operations/vps-bootstrap.md`](operations/vps-bootstrap.md) |
| Index des décisions d'architecture (ADR) | [`decisions/_index.md`](decisions/_index.md) |
| Listing App Store (multilingue) | [`../appstore-listing.md`](../appstore-listing.md) |
| Définition d'un terme métier ou technique | [`glossary.md`](glossary.md) |

## Structure

```
docs/
├── README.md                  # index bilingue (sélecteur de langue)
├── appstore-listing.md        # listing App Store (multilingue, neutre)
├── fr/                        # documentation française (référence)
│   ├── README.md              # ce document
│   ├── architecture/          # vue STATIQUE (modèle C4 : context, containers, components, data)
│   ├── flows/                 # vue DYNAMIQUE (séquences, flowcharts)
│   ├── state-machines/        # vue COMPORTEMENTALE
│   ├── screens/               # per-screen specs (hero screens)
│   ├── testing/               # stratégie et suites de tests (front + back + web)
│   ├── operations/            # runbooks (déploiement, observabilité, VPS)
│   ├── decisions/             # Architecture Decision Records (format MADR)
│   ├── 3d-lod-architecture.md # LOD des modèles 3D
│   └── glossary.md            # vocabulaire du domaine
├── en/                        # miroir anglais (même arborescence)
└── legacy/                    # documents antérieurs, hors périmètre des règles
```

Les fichiers numérotés (`01-`, `02-`) suivent l'ordre de lecture recommandé. Les ADR (`0001-`, `0002-`) sont datés et **immuables** une fois acceptés : toute évolution donne lieu à un nouvel ADR qui supersede le précédent.

## Règles de rédaction

1. **Toute PR de code touchant un domaine documenté doit mettre à jour la documentation correspondante dans la même PR**, en **français (référence) ET en anglais** (miroir `../en/`).
2. **Un sujet par fichier.** Trois niveaux de titres maximum.
3. **Contexte autour de chaque diagramme.** Deux à trois lignes de contexte avant, deux à trois lignes de synthèse après. Un diagramme isolé n'est lisible que par son auteur.
4. **Modèle C4 limité aux niveaux Context, Container et Component.** Le niveau Code (UML de classes) est volontairement omis : le code source en tient lieu.
5. **Les per-screen specs sont réservées aux hero screens** (trois à cinq écrans maximum). Les écrans simples sont décrits en une ligne dans `flows/`.
6. **Les ADR sont courts** (une page maximum), nommés `NNNN-kebab-case.md` et jamais modifiés après acceptation : créer un nouvel ADR pour superseder.
7. **En cas de problème de layout sur un diagramme Mermaid C4**, réordonner les déclarations d'éléments dans la source. La directive `Lay_U/D/L/R` n'est pas supportée à ce jour.

## Types de diagrammes Mermaid utilisés

| Besoin | Type Mermaid |
|---|---|
| Acteurs et systèmes externes (C4 Context) | `flowchart TB` avec labels `[Person]` / `[System Ext]` |
| Applications et services déployés (C4 Container) | `flowchart TB` avec labels `[Container]` |
| Modules internes d'un service (C4 Component) | `flowchart TB` avec labels `[Component]` |
| Schéma de données relationnel | `erDiagram` |
| Enchaînement linéaire d'écrans | `flowchart TD` |
| Interaction entre acteurs dans le temps | `sequenceDiagram` |
| États discrets et transitions | `stateDiagram-v2` |

## Contrat CI

Toute PR ciblant `main` qui modifie un fichier sous `docs/`, ou un fichier source cité par la documentation (`ArboreUi/**/*.swift`, `ArboreBackend/**/*.go`), déclenche le workflow `.github/workflows/docs.yml`. Ce workflow exécute trois jobs en parallèle et bloque le merge si l'un échoue.

| Job | Outil | Cause d'échec |
|---|---|---|
| **Mermaid syntax** | [`@mermaid-js/mermaid-cli`](https://github.com/mermaid-js/mermaid-cli) | Un bloc ` ```mermaid ` dans `docs/**/*.md` ne se rend pas (syntaxe invalide, mot-clé réservé comme node ID, caractère spécial non échappé). |
| **Internal links** | [`lycheeverse/lychee-action`](https://github.com/lycheeverse/lychee-action) en mode `--offline` | Un lien interne dans `docs/` pointe vers un fichier ou une ancre inexistante. |
| **Doc drift** | Script `.github/scripts/docs-drift-check.sh` | Un chemin de code cité entre backticks (ex. `Services/NetworkManager.swift`) ne correspond à aucun fichier du dépôt. Détecte renommages et suppressions. |

La logique de drift est en **suffix match** : `Models/User.swift` est valide si un fichier du dépôt y termine (ex. `ArboreUi/ArboreUi/Models/User.swift`). Reproduire localement :

```sh
bash .github/scripts/docs-drift-check.sh
```

## Outils et statut

- **Markdown + Mermaid** — rendu natif GitHub, diff-able, aucun outillage externe.
- **Sémantique C4 portée par `flowchart`.** La syntaxe `C4Context`/`C4Container` native de Mermaid est marquée [`experimental`](https://mermaid.js.org/syntax/c4.html) et produit des chevauchements d'arêtes au-delà d'une dizaine d'éléments. La convention adoptée utilise `flowchart` avec des labels préfixés `[Person]`, `[Container]`, `[System Ext]`. Décision tracée dans l'[ADR 0001](decisions/0001-mermaid-for-docs.md).
- **MADR** — voir [adr.github.io/madr](https://adr.github.io/madr/) pour le format complet.

## Documents legacy

Les fichiers suivants précèdent cette structure et sont isolés sous [`../legacy/`](../legacy/). Ils restent accessibles pour référence historique mais n'entrent pas dans le périmètre des règles ci-dessus.

- [`../legacy/AR_CAMERA_BLACK_SCREEN_FIX.md`](../legacy/AR_CAMERA_BLACK_SCREEN_FIX.md) — notes du fix écran noir caméra AR
- [`../legacy/CI-CD.md`](../legacy/CI-CD.md) — documentation détaillée de la CI/CD historique
- [`../legacy/DEBUG_MODE_VISUAL_SUMMARY.md`](../legacy/DEBUG_MODE_VISUAL_SUMMARY.md), [`../legacy/DEBUG_THUMBNAIL_MODE.md`](../legacy/DEBUG_THUMBNAIL_MODE.md) — guides de debug thumbnails
- [`../legacy/TROUBLESHOOTING.md`](../legacy/TROUBLESHOOTING.md) — guide de dépannage CI
