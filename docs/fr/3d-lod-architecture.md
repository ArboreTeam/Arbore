# Architecture LOD des modèles 3D (catalogue → léger → lourd)

Cette vue décrit le système de **niveau de détail (LOD)** des modèles 3D de plantes, tel qu'il est **implémenté** dans l'app iOS et le backend. Elle complète la vue composants ([`architecture/03-components-ios.md`](architecture/03-components-ios.md), [`architecture/03-components-backend.md`](architecture/03-components-backend.md)) et la décision [ADR 0006](decisions/0006-ar-quality-adaptive.md) sur la qualité AR adaptative.

## Objectif

Les modèles 3D haute définition sont trop lourds pour être chargés tels quels sur mobile. Le catalogue sert donc **trois niveaux de représentation** par plante :

| Niveau | Format | Taille indicative | Quand |
|---|---|---|---|
| **PNG** | thumbnail | ~0,5 MB | Catalogue (cartes) — jamais de 3D |
| **LIGHT** | `.usdz` optimisé | ~2–6 MB | Placement AR initial (téléchargement + affichage rapides) |
| **HEAVY** | `.usdz` haute définition | plus volumineux | Chargé en fond pendant la visualisation AR, **swap** puis le léger est libéré |

Résultat : le catalogue est instantané (PNG), le placement AR est rapide (léger), et l'utilisateur finit par voir le specimen haute définition sans attente perceptible.

## Comportement runtime

- **Catalogue** : `ArboreUi/ArboreUi/Views/PlantCard.swift` charge le thumbnail PNG via `GET /models/thumbnails/{id}.png` (cache disque `PlantThumbnailCache`, repli par génération on-device `PlantThumbnailGenerator`). Le browsing ne charge **aucune** 3D.
- **Modèle 3D** : `ArboreUi/ArboreUi/Services/ModelCacheManager.swift` télécharge le USDZ (cache disque par nom de fichier), utilisé en AR et pour la génération de thumbnail.
- **Backend** : `GET /models/:filename` (protégé) sert le USDZ depuis `./models/` ; le paramètre `?lod=heavy` bascule la lecture vers `./models/heavy/`. `GET /models/thumbnails/:filename` (public) sert les PNG.

## Contrat backend (`ArboreBackend/main.go`)

- **Une seule route** sert les deux niveaux : `GET /models/:filename` pour le léger, `GET /models/:filename?lod=heavy` pour le lourd (le sous-dossier `./models/heavy/`). Un segment de route statique dédié (`/models/heavy/:filename`) a été volontairement écarté car il entrerait en collision avec le wildcard `:filename` du routeur.
- **Même nom de fichier** pour le léger et le lourd : pas besoin d'une seconde URL en base, juste le paramètre de LOD.
- Validation de sécurité identique pour les deux : rejet de `..` / `/` / `\`, extension `.usdz` exigée, `Content-Type: model/vnd.usdz+zip`.

## Schéma `Plant`

- `Plant.hasHeavy` (`*bool`, `json/bson:"hasHeavy,omitempty"`) indique qu'une variante lourde existe. `nil`/`false` = pas de lourd (l'app reste sur le léger).
- iOS : `let hasHeavy: Bool?` (`ArboreUi/ArboreUi/Models/Plant.swift`). Web : `hasHeavy?: boolean` (`web/lib/api.ts`).
- Le champ est persisté dans la scène locale (`PersistedPlant.hasHeavy`) : à la réouverture d'un jardin, le download lourd peut être re-déclenché.

## iOS — cœur du LOD

`ModelCacheManager` expose un niveau de LOD :

```swift
enum ModelLOD { case light, heavy }
func getModelURL(for filename: String, lod: ModelLOD = .light,
                 forceDownload: Bool = false) async throws -> URL
// light → {baseURL}/models/<filename> ; heavy → {baseURL}/models/<filename>?lod=heavy
// cache disque séparé (heavy isolé), téléchargement heavy annulable (Task).
```

Dans la vue de placement AR (`ArboreUi/ArboreUi/ARGarden/GardenARPlacementView.swift`) :

1. Au placement : `getModelURL(lod:.light)` → entité légère ajoutée à l'ancre à la position du hit-test.
2. Si `plant.hasHeavy == true`, une `Task` de fond charge le modèle lourd (`lod:.heavy`).
3. À la réussite, sur le main actor : copier le `transform` du léger sur le lourd, ajouter le lourd, retirer le léger → la mémoire du léger est libérée.
4. **Annulation** : si la plante est retirée / la scène change avant la fin, `task.cancel()` (et annulation du download).
5. **Garde-fous** : si `hasHeavy` faux ou si le download lourd échoue → on **reste sur le léger** (jamais de régression visuelle). Le swap matche exactement transform + échelle pour éviter tout « saut ».

## LOD adaptatif (thermique + budget + distance)

`ArboreUi/ArboreUi/ARGarden/Quality/PlantLODPolicy.swift` et l'évaluateur dans `GardenARPlacementView` (`evaluateLOD`, throttlé ~4 Hz) décident léger/lourd par une **chaîne de précédence** (les gates globaux ne peuvent que *réduire* le détail) :

1. **Thermique (global)** — `ProcessInfo.thermalState` + Low Power Mode : `.nominal`/`.fair` → budget plein ; `.serious`/LowPower → tout léger sauf la plante sélectionnée + annulation des downloads lourds ; `.critical` → tout léger. Downgrade immédiat à chaud ; re-upgrade seulement après une période stable au frais (cooldown).
2. **Budget K (global)** — `DeviceCapabilities.tier` : K=1 (appareils anciens) / 2 (modernes). Seules les K plantes les plus proches + la sélectionnée passent lourd ; le surplus est downgradé. Une stickiness évite le ping-pong entre plantes équidistantes.
3. **Distance (par plante)** — exprimée en **taille à l'écran** : lourd tant que `distance < 2,9 × hauteur`, avec hystérésis 20 % et clamp [0,6 ; 4,5] m.

Le swap est **réversible** (`swapModel(to:)` léger↔lourd) ; un download lourd en cours est traité comme lourd pour ne pas être annulé au moindre jitter. Tout est **fail-safe** (toute erreur laisse le modèle courant). Ce système complète `ARGarden/Quality/` (qui gère `environmentTexturing` + bannière thermique) sans le dupliquer.

## Risques / notes

- **Swap visible** : si le cadrage léger/lourd diffère légèrement, l'utilisateur peut percevoir un « pop ». Mitigation : léger fondu d'opacité au swap.
- **Réseau lent** : le lourd peut ne jamais finir — c'est acceptable, le léger reste affiché.
- **Mémoire** : ne jamais conserver léger **et** lourd longtemps ; libérer le léger juste après le swap. `AppDelegate` libère déjà les caches RealityKit sur memory warning.

## Hors-scope de cette vue

- Le stockage et le déploiement des fichiers `.usdz`/PNG sur le VPS (gitignorés) relèvent de [`operations/vps-bootstrap.md`](operations/vps-bootstrap.md).
- Le schéma `Plant` complet est documenté dans [`architecture/04-data-model.md`](architecture/04-data-model.md).
