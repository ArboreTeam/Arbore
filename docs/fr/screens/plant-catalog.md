# Écran — Catalogue de plantes

Le catalogue permet à l'utilisateur de **parcourir et filtrer** le référentiel de plantes, et affiche pour chaque plante un **badge de compatibilité** avec son jardin (selon le profil recueilli). Il sert aussi de point d'entrée au placement AR.

Fichiers : `PlantCatalogView.swift` (écran + filtres), `PlantCatalogContext.swift` (dimensions de filtre + `PlantSuitabilityEvaluator`), `PlantCatalogPreferenceViews.swift` (UI des préférences/filtres).

## Deux mécanismes distincts

1. **Filtrage** — l'utilisateur affine la liste selon des dimensions catalogue.
2. **Évaluation de compatibilité** — chaque plante est notée par rapport au **profil de jardin** (`GardenWizardDTO`) et reçoit un niveau.

> ⚠️ Ce scoring catalogue (`PlantSuitabilityEvaluator`, basé sur `GardenWizardDTO`) est **distinct** du scoring de suggestion du wizard (`GardenSuggestionEngine`). Les deux coexistent aujourd'hui — consolidation à trancher (cf. audit #319).

## Dimensions de filtre

Définies dans `PlantCatalogContext.swift`, chacune un `enum` filtrable :

| Dimension | Exemples |
|---|---|
| `PlantCatalogGoal` | objectif d'aménagement : ajouter de la couleur, créer de l'intimité, couvrir un mur, attirer les pollinisateurs, aromatique/comestible, point focal… |
| `PlantCatalogKind` | type : plante verte, fleurie, cactus/succulente, palmier, fougère, orchidée, arbre, arbuste, vivace, annuelle, graminée, couvre-sol, grimpante, aromatique/comestible |
| `PlantCatalogColor` | couleur dominante (blanc, jaune, orange, rouge, rose, violet, bleu, vert, sombre) |
| `PlantCatalogAppearance` / `PlantCatalogHabit` | port : dressé, étalé, grimpant, retombant |
| `PlantCatalogScale` / `PlantCatalogSize` | gabarit : compact, équilibré, imposant |
| `PlantCatalogCareLevel` | exigence d'entretien : minimal, régulier |

Le style de jardin (ancien step wizard) a vocation à vivre **ici, comme filtre**, plutôt que comme étape du parcours.

## D'où viennent les dimensions (#792)

**Elles sont lues, plus déduites.** Chaque dimension correspond à un champ
stocké de `botanicalProfile`, en valeur close et sourcée.

Jusqu'à #792, sept fonctions de `PlantCatalogContext` les dérivaient en
cherchant des mots-clés dans la **description traduite** de la fiche. Trois
conséquences mesurées :

- `size()` dépendait de la **langue affichée** — la même plante pouvait être
  `large` en français et `unknown` en allemand ;
- `isFlowering()` lisait `flags.flowering`, puis, si le drapeau était `false`,
  retombait sur la prose : une description mentionnant « fleur » suffisait donc
  à déclarer la plante fleurie, et le `false` du drapeau n'affirmait rien ;
- la liste de mots-clés de `size()` contenait `"mini "` **avec une espace**, un
  garde-fou ajouté après coup contre les faux appariements.

Ces fonctions sont supprimées. La garde du critère tient en une commande :

```sh
grep -rn "containsAny\|searchableText" ArboreUi/ArboreUi/   # doit rester vide
```

**Trois dimensions ne renvoient rien aujourd'hui**, faute de source close, et
c'est volontaire : `colors` (aucune source dans le corpus), les apparences
`variegated` / `evergreen` / `fragrant`, et les ports `upright` / `spreading`.
Elles étaient auparavant **devinées** — le filtre « port dressé » renvoyait en
réalité tout le catalogue, parce que `.upright` était inséré par défaut quand
rien n'avait été trouvé. Proposer un choix auquel aucune donnée ne peut
répondre est pire que ne pas le proposer : c'est la doctrine déjà appliquée à
`FilterView.difficultyOptions`, à étendre ici.

## Évaluation de compatibilité (`PlantSuitabilityEvaluator`)

L'évaluateur agrège plusieurs **critères**, chacun produisant un score, puis en déduit un niveau global :

| Critère | Basé sur (profil / flags plante) |
|---|---|
| Espace (`appendSpaceCriterion`) | `wizard.spaceType` (intérieur/balcon/terrasse/jardin) |
| Lumière (`appendSunlightCriterion`) | `wizard.siteProfile.sunlight` vs tolérances de la plante |
| Sécurité (`appendSafetyCriteria`) | `wizard.safety` vs `flags.toxicToPets` / `toxicToChildren` |
| Plantation (`appendPlantingCriterion`) | `conditionalAnswers.plantingMode == .containers` |
| Drainage (`appendDrainageCriterion`) | `conditionalAnswers.drainage` vs `flags.humidityLoving` |
| Vent (`appendWindCriterion`) | `conditionalAnswers.windExposure` / `siteProfile.wind` |
| Humidité (`appendHumidityCriterion`) | `conditionalAnswers.indoorHumidity` |
| Chaleur (`appendHeatCriterion`) | `conditionalAnswers.nearbyHeat` |
| Hauteur (`appendHeightCriterion`) | `siteProfile.availableHeight` |

Niveau (`PlantSuitabilityLevel`) : `unsuitable` → `neutral` → `suitable` → `verySuitable`. Un critère **critique** (ex. toxique alors que l'utilisateur a des animaux) tire le niveau vers le bas. Chaque critère porte une raison localisée affichée à l'utilisateur.

> Les critères ne s'appliquent que si la donnée de profil correspondante est présente : un profil incomplet donne un score sur moins de critères (voire aucun → pas de badge), sans jamais planter.

## Points clés

- **Découplé du wizard UI** : l'évaluateur lit le **DTO** (`GardenWizardDTO`), pas l'état d'écran du wizard — donc indépendant du parcours de création actif.
- **Données plante** : la compatibilité s'appuie sur les `flags` de la fiche plante (toxicité, amour de l'humidité…) et le schéma LOD/botanique du catalogue.
- **Doublon connu** : deux systèmes de scoring (`PlantSuitabilityEvaluator` catalogue vs `GardenSuggestionEngine` wizard) — laissés en place le temps de figer le parcours (cf. #319).

## Hors-scope de cette vue

- Le placement AR des plantes est documenté dans [`garden-ar-placement.md`](garden-ar-placement.md).
- Le LOD 3D est documenté dans [`../3d-lod-architecture.md`](../3d-lod-architecture.md).
