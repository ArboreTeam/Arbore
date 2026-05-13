# Documentation Arbore

Cette section regroupe la documentation technique de l'application Arbore, rédigée en **Markdown + Mermaid** afin de vivre à côté du code source et d'être rendue nativement par GitHub.

> 🗂️ **Tracker** : [Issue #141](https://github.com/ArboreTeam/Arbore/issues/141) a porté la mise en place de la documentation. Les cinq phases ont été livrées entre les PR #142 et #147 ; les mises à jour suivantes passent par les PRs de feature qui touchent un domaine documenté.

## Guide de lecture

La documentation est découpée en cinq vues complémentaires. Selon l'information recherchée :

| Information recherchée | Emplacement |
|---|---|
| Vue d'ensemble (acteurs et systèmes externes) | [`architecture/01-context.md`](architecture/01-context.md) |
| Briques techniques déployées | [`architecture/02-containers.md`](architecture/02-containers.md) |
| Détail des modules internes côté iOS | [`architecture/03-components-ios.md`](architecture/03-components-ios.md) |
| Détail des modules internes côté backend Go | [`architecture/03-components-backend.md`](architecture/03-components-backend.md) |
| Schéma de données MongoDB | [`architecture/04-data-model.md`](architecture/04-data-model.md) |
| Flow de signup avec rollback Firebase | [`flows/auth-signup.md`](flows/auth-signup.md) |
| Flow de création de jardin (wizard) | [`flows/garden-creation.md`](flows/garden-creation.md) |
| Flow de placement AR (création et réouverture) | [`flows/ar-placement.md`](flows/ar-placement.md) |
| Machine d'états du manual replacement (#111) | [`state-machines/relocation-phase.md`](state-machines/relocation-phase.md) |
| Index des hero screens | [`screens/_index.md`](screens/_index.md) |
| Per-screen spec — `GardenARPlacementView` | [`screens/garden-ar-placement.md`](screens/garden-ar-placement.md) |
| Per-screen spec — wizard de création | [`screens/questionnaire-wizard.md`](screens/questionnaire-wizard.md) |
| Per-screen spec — `PersonalDetailsView` | [`screens/personal-details.md`](screens/personal-details.md) |
| Index des décisions d'architecture | [`decisions/_index.md`](decisions/_index.md) |
| ADR 0001 — Mermaid + flowchart pour la doc | [`decisions/0001-mermaid-for-docs.md`](decisions/0001-mermaid-for-docs.md) |
| ADR 0002 — Stack de scan double (LiDAR / non-LiDAR) | [`decisions/0002-scan-stacks.md`](decisions/0002-scan-stacks.md) |
| ADR 0003 — Stratégie de relocalisation à trois étages | [`decisions/0003-relocation-strategy.md`](decisions/0003-relocation-strategy.md) |
| ADR 0004 — Firebase Auth comme provider | [`decisions/0004-firebase-auth.md`](decisions/0004-firebase-auth.md) |
| ADR 0005 — Self-authz via token uid | [`decisions/0005-self-authz-pattern.md`](decisions/0005-self-authz-pattern.md) |
| ADR 0006 — Qualité AR adaptative (environmentTexturing + thermal) | [`decisions/0006-ar-quality-adaptive.md`](decisions/0006-ar-quality-adaptive.md) |
| Définition d'un terme métier ou technique | [`glossary.md`](glossary.md) |

## Structure

```
docs/
├── README.md                  # ce document
├── architecture/              # vue STATIQUE (modèle C4)
├── flows/                     # vue DYNAMIQUE (séquences, flowcharts)
├── state-machines/            # vue COMPORTEMENTALE
├── screens/                   # per-screen specs (hero screens uniquement)
├── decisions/                 # Architecture Decision Records (format MADR)
└── glossary.md                # vocabulaire du domaine
```

Les fichiers numérotés (`01-`, `02-`) suivent l'ordre de lecture recommandé. Les ADRs (`0001-`, `0002-`) sont datés et **immuables** une fois acceptés : toute évolution donne lieu à un nouvel ADR qui supersede le précédent.

## Règles de rédaction

1. **Toute PR de code touchant à un domaine documenté doit mettre à jour la documentation correspondante dans la même PR.** Les PR purement documentaires ne sont autorisées que pendant les phases initiales d'écriture.
2. **Un sujet par fichier.** Trois niveaux de titres maximum.
3. **Contexte autour de chaque diagramme.** Précéder chaque diagramme de deux à trois lignes de contexte, le suivre de deux à trois lignes synthétisant les points clés. Un diagramme isolé n'est lisible que par son auteur.
4. **Modèle C4 limité aux niveaux Context, Container et Component.** Le niveau Code (UML de classes) est volontairement omis : le code source en tient lieu.
5. **Les per-screen specs sont réservés aux hero screens** (trois à cinq écrans maximum). Les écrans simples sont décrits en une ligne dans `flows/`.
6. **Les ADRs sont courts** (une page maximum), nommés `NNNN-kebab-case.md` et jamais modifiés après acceptation : créer un nouvel ADR pour superseder.
7. **En cas de problème de layout sur un diagramme Mermaid C4**, réordonner les déclarations d'éléments dans la source. La directive `Lay_U/D/L/R` n'est pas supportée à ce jour.

## Types de diagrammes Mermaid utilisés

| Besoin | Type Mermaid |
|---|---|
| Acteurs et systèmes externes (niveau C4 Context) | `flowchart TB` avec labels `[Person]` / `[System Ext]` |
| Applications et services déployés (niveau C4 Container) | `flowchart TB` avec labels `[Container]` |
| Modules internes d'un service (niveau C4 Component) | `flowchart TB` avec labels `[Component]` |
| Schéma de données relationnel | `erDiagram` |
| Enchaînement linéaire d'écrans | `flowchart TD` |
| Interaction entre acteurs dans le temps | `sequenceDiagram` |
| États discrets et transitions | `stateDiagram-v2` |

## Contrat CI

Toute PR ciblant `main` qui modifie un fichier sous `docs/`, ou un fichier source cité par la documentation (`ArboreUi/**/*.swift`, `ArboreBackend/**/*.go`), déclenche le workflow `.github/workflows/docs.yml`. Ce workflow exécute trois jobs en parallèle et bloque le merge si l'un d'eux échoue.

| Job | Outil | Cause d'échec |
|---|---|---|
| **Mermaid syntax** | [`@mermaid-js/mermaid-cli`](https://github.com/mermaid-js/mermaid-cli) | Un bloc ``` ```mermaid ``` ``` dans `docs/**/*.md` ne se rend pas (syntaxe invalide, mot-clé réservé utilisé comme node ID, caractère spécial non échappé). |
| **Internal links** | [`lycheeverse/lychee-action`](https://github.com/lycheeverse/lychee-action) en mode `--offline` | Un lien interne dans `docs/` pointe vers un fichier ou une ancre qui n'existe pas. Les liens externes restent en warning. |
| **Doc drift** | Script `.github/scripts/docs-drift-check.sh` | Un chemin code cité dans la documentation entre backticks (par exemple `` `Services/NetworkManager.swift` ``) ne correspond à aucun fichier du dépôt. Détecte les renommages et suppressions non répercutés. |

La logique de matching du drift est en **suffix match** : un chemin cité comme `Models/User.swift` est considéré valide si un fichier du dépôt y termine (par exemple `ArboreUi/ArboreUi/Models/User.swift`). Cela évite d'imposer le chemin complet depuis la racine dans la documentation.

Pour reproduire le check de drift localement avant d'ouvrir une PR :

```sh
bash .github/scripts/docs-drift-check.sh
```

## Outils et statut

- **Markdown + Mermaid** — rendu natif GitHub, diff-able, aucun outillage externe.
- **Sémantique C4 portée par `flowchart`.** La syntaxe `C4Context` / `C4Container` native de Mermaid est officiellement marquée comme [`experimental`](https://mermaid.js.org/syntax/c4.html) et produit des **chevauchements d'arêtes** dès que le graphe dépasse une dizaine d'éléments. La convention adoptée dans cette documentation utilise `flowchart` avec des labels préfixés `[Person]`, `[Container]`, `[System Ext]`, etc. Cette approche préserve la sémantique C4 tout en bénéficiant du moteur de layout mature de Mermaid. La décision est tracée dans l'[ADR 0001](decisions/0001-mermaid-for-docs.md).
- **MADR** — voir [adr.github.io/madr](https://adr.github.io/madr/) pour le format complet.

## Documents legacy

Les fichiers suivants précèdent la mise en place de cette structure et sont **isolés sous [`docs/legacy/`](legacy/)**. Ils restent accessibles pour référence historique mais n'entrent pas dans le périmètre des règles de rédaction décrites plus haut. Ils seront migrés vers la nouvelle arborescence ou supprimés au fil des sprints.

- [`legacy/AR_CAMERA_BLACK_SCREEN_FIX.md`](legacy/AR_CAMERA_BLACK_SCREEN_FIX.md) — notes du fix écran noir caméra AR
- [`legacy/CI-CD.md`](legacy/CI-CD.md) — documentation détaillée de la CI/CD historique
- [`legacy/DEBUG_MODE_VISUAL_SUMMARY.md`](legacy/DEBUG_MODE_VISUAL_SUMMARY.md), [`legacy/DEBUG_THUMBNAIL_MODE.md`](legacy/DEBUG_THUMBNAIL_MODE.md) — guides de debug thumbnails
- [`legacy/TROUBLESHOOTING.md`](legacy/TROUBLESHOOTING.md) — guide de dépannage CI
- `legacy/BETA_TEST_PLAN_Arbore_simple_v2_2026-05-02.pdf` / `.docx` — plan de test beta
