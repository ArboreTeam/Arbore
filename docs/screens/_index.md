# Per-screen specs — Index

Cette section regroupe les **per-screen specs** des écrans qualifiés de « hero screens » : écrans complexes, business-critical, ou qui concentrent assez de logique pour mériter une documentation dédiée.

Les écrans simples (un bouton, une navigation, une liste statique) ne disposent **pas** de per-screen spec — ils sont décrits en une ligne dans les flows [`../flows/`](../flows/) lorsque c'est pertinent.

## Critères de promotion en hero screen

Un écran devient hero screen, et donc cible d'une per-screen spec, lorsqu'**au moins deux** des critères suivants sont remplis :

- L'écran porte une **machine d'états** explicite (plusieurs phases distinctes avec transitions).
- Le fichier dépasse **1 000 lignes** de code.
- L'écran appelle **plus de deux endpoints backend** distincts.
- L'écran combine **plusieurs frameworks Apple** (ARKit + SceneKit + SwiftUI, par exemple).
- L'écran est mentionné dans **au moins trois issues GitHub** ouvertes ou closes (signal qu'il concentre de la dette ou des bugs récurrents).
- L'écran porte un **contrat de sécurité ou de RGPD** spécifique.

## Hero screens documentés

| Écran | Fichier | Critères remplis |
|---|---|---|
| `GardenARPlacementView` | [`garden-ar-placement.md`](garden-ar-placement.md) | Machine d'états (`RelocationPhase`), 3 300 LOC, 3 frameworks (ARKit + SceneKit + SwiftUI), ≥ 5 issues (#96, #111, #113, #114, #123, #124, #136, #138). |
| Wizard de création de jardin | [`questionnaire-wizard.md`](questionnaire-wizard.md) | 10 étapes avec skip rules, `POST /gardens` + branching vers deux flows AR distincts, ≥ 3 issues (#139, #21, #97). |
| `PersonalDetailsView` | [`personal-details.md`](personal-details.md) | `PATCH /users/me` + mise à jour Firebase `displayName`, machine d'états save (idle → saving → success/error), issue #138. |

## Hero screens non-documentés (à promouvoir si nécessaire)

Les écrans suivants sont en limite mais ne sont pas encore documentés. Ils seront promus si leur complexité augmente ou si plusieurs bugs s'y concentrent :

- `LiDARScanWizardView` — single screen mais RoomPlan + transition vers `GardenARPlacementView`. Suivi par l'issue #139.
- `ARViewContainerMeasure` — single screen, principalement pour le tracé périmètre non-LiDAR.
- `SignUpView` — flow critique (#137) mais le détail est déjà dans [`../flows/auth-signup.md`](../flows/auth-signup.md).
- `CatalogueView` et `PlantCatalogView` — listings avec filtres mais sans logique complexe.

## Structure d'une per-screen spec

Chaque hero screen suit la structure suivante :

1. **Purpose** — une à deux phrases expliquant la raison d'être de l'écran.
2. **Entry points** — qui peut router vers cet écran et avec quels paramètres.
3. **Exit points** — où la navigation repart selon les actions utilisateur.
4. **Screen-level flow** — diagramme Mermaid (`flowchart` ou `stateDiagram-v2`) de l'enchaînement intra-écran.
5. **Widgets** — sous-sections par widget significatif, avec mini state diagram si nécessaire.
6. **Edge cases** — comportement en cas de loading, empty state, erreur, mode offline, permissions iOS refusées.
7. **Dependencies** — APIs backend appelées, états partagés (`@EnvironmentObject`, `@StateObject` externe), permissions iOS, frameworks Apple utilisés.

Cette structure est inspirée des design systems Shopify Polaris et Material Design 3, adaptée au contexte iOS natif.
