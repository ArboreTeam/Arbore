# Documentation Arbore

Cette section regroupe la documentation technique de l'application Arbore, rédigée en **Markdown + Mermaid** afin de vivre à côté du code source et d'être rendue nativement par GitHub.

> 🗂️ **Tracker** : [Issue #141](https://github.com/ArboreTeam/Arbore/issues/141) suit l'avancement des phases de documentation.

## Guide de lecture

La documentation est découpée en cinq vues complémentaires. Selon l'information recherchée :

| Information recherchée | Emplacement |
|---|---|
| Vue d'ensemble (acteurs et systèmes externes) | [`architecture/01-context.md`](architecture/01-context.md) |
| Briques techniques déployées | [`architecture/02-containers.md`](architecture/02-containers.md) |
| Détail des modules internes d'un container | `architecture/03-components-*.md` *(Phase 2)* |
| Schéma de données MongoDB | `architecture/04-data-model.md` *(Phase 2)* |
| Enchaînement des écrans côté utilisateur | `flows/*.md` *(Phase 3)* |
| États discrets d'une fonctionnalité | `state-machines/*.md` *(Phase 3)* |
| Détail d'un écran principal (hero screen) | `screens/*.md` *(Phase 4)* |
| Justification d'un choix d'architecture | `decisions/*.md` *(Phase 5)* |
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

## Outils et statut

- **Markdown + Mermaid** — rendu natif GitHub, diff-able, aucun outillage externe.
- **Sémantique C4 portée par `flowchart`.** La syntaxe `C4Context` / `C4Container` native de Mermaid est officiellement marquée comme [`experimental`](https://mermaid.js.org/syntax/c4.html) et produit des **chevauchements d'arêtes** dès que le graphe dépasse une dizaine d'éléments. La convention adoptée dans cette documentation utilise `flowchart` avec des labels préfixés `[Person]`, `[Container]`, `[System Ext]`, etc. Cette approche préserve la sémantique C4 tout en bénéficiant du moteur de layout mature de Mermaid. La décision est tracée dans l'ADR `0001-mermaid-for-docs.md` (Phase 5).
- **MADR** — voir [adr.github.io/madr](https://adr.github.io/madr/) pour le format complet.

## Documents legacy

Les fichiers suivants précèdent la mise en place de cette structure et sont conservés à titre de référence. Ils seront migrés ou supprimés au fil des sprints :

- `AR_CAMERA_BLACK_SCREEN_FIX.md`
- `CI-CD.md`
- `DEBUG_MODE_VISUAL_SUMMARY.md`, `DEBUG_THUMBNAIL_MODE.md`
- `TROUBLESHOOTING.md`
- `BETA_TEST_PLAN_Arbore_simple_v2_2026-05-02.{pdf,docx}`
