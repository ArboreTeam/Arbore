# Architecture LOD des modèles 3D (catalogue → léger → lourd)

## Objectif

Les modèles Meshy bruts pèsent 30–130 MB (trop lourd pour le mobile). On sert
désormais **3 niveaux de détail** par plante :

| Niveau | Format | Taille | Quand |
|---|---|---|---|
| **PNG** | thumbnail | ~0,5 MB | Catalogue (cartes) — jamais de 3D |
| **LIGHT** | `.usdz` optimisé | ~2–6 MB | Placement AR initial (téléchargement + affichage rapides) |
| **HEAVY** | `.usdz` specimen | 12–130 MB | Chargé en fond pendant la visu AR, **swap** puis le léger est libéré |

Résultat : le catalogue est instantané (PNG), le placement AR est rapide (léger),
et l'utilisateur finit par voir le vrai specimen haute définition sans attente.

## État actuel (audité)

- **Catalogue** : `PlantCard.swift` charge `{baseURL}/models/thumbnails/{plant.id}.png`
  (cache disque `PlantThumbnailCache`, fallback génération on-device via
  `PlantThumbnailGenerator` qui télécharge le USDZ). → Le browsing ne charge pas
  de 3D. ✅
- **Modèle 3D** : `Plant.getModelURL()` → `ModelCacheManager` télécharge le USDZ
  (cache disque par nom de fichier, `URLSession.shared.download`). Utilisé en AR
  et pour la génération de thumbnail.
- **Backend** : `GET /models/:filename` sert le USDZ depuis `models/` ;
  `GET /models/thumbnails/:filename` sert les PNG depuis `THUMBNAILS_DIR`.
  `Plant.modelURL` = nom de fichier.

## Architecture cible

### Stockage VPS (déployé par rsync, hors git)
```
ArboreBackend/models/
├── <Name>.usdz            LIGHT (servi par défaut)
├── heavy/<Name>.usdz      HEAVY (vrai specimen)
└── thumbnails/<id>.png    PNG catalogue
```
Light et heavy **partagent le même nom de fichier** → pas besoin d'une 2e URL en
base, juste un préfixe de route.

### A. Backend (`ArboreBackend/main.go`)
1. Nouvelle route `GET /models/heavy/:filename` — identique à `/models/:filename`
   mais sert depuis `models/heavy/` (réutiliser le handler existant en
   paramétrant le sous-dossier ; même validation regex du filename).
2. (optionnel) Exposer `hasHeavy` sur le Plant : soit un champ `HasHeavy *bool`,
   soit dérivé au runtime (`os.Stat(models/heavy/<modelURL>)`). Recommandé :
   champ booléen renseigné à l'import (évite un `os.Stat` par plante).
3. `Plant.modelURL` reste le **nom du fichier léger** (inchangé).

### B. Schéma (`Plant`)
- Ajouter `HasHeavy *bool` (`json/bson:"hasHeavy,omitempty"`) — committable, comme
  `source`/`flags`. nil/false = pas de heavy (l'app reste sur le léger).
- iOS `Plant.swift` : `let hasHeavy: Bool?`. Web : `hasHeavy?: boolean`.

### C. iOS — le cœur du LOD

**`ModelCacheManager`** : ajouter un paramètre de niveau.
```swift
enum ModelLOD { case light, heavy }
func getModelURL(for filename: String, lod: ModelLOD = .light,
                 forceDownload: Bool = false) async throws -> URL
// light → {baseURL}/models/<filename> ; heavy → {baseURL}/models/heavy/<filename>
// cache disque séparé (suffixe _heavy), téléchargement heavy annulable (Task).
```

**Vue de placement AR** (RealityKit — `ARViewContainerMeasure` / la vue qui pose
la plante) :
1. Au placement : `getModelURL(lod:.light)` → `ModelEntity` → ajouter à un
   `AnchorEntity` à la position du hit-test. Garder une réf `placed[entityID]`.
2. Si `plant.hasHeavy == true`, lancer une `Task` de fond :
   `getModelURL(lod:.heavy)` → charger le `ModelEntity` lourd.
3. À la réussite, sur le main actor : copier le `transform` du léger sur le lourd,
   `anchor.addChild(heavy)` puis `light.removeFromParent()` → le `ModelEntity`
   léger est désalloué → RealityKit libère son mesh/textures.
4. **Annulation** : si la plante est retirée / la scène change avant la fin,
   `task.cancel()` (et annuler le `URLSession` download).
5. Mémoire : `AppDelegate` libère déjà les caches RealityKit sur memory warning ;
   après swap, ne garder de réf forte que sur le lourd. Optionnel : éviction du
   fichier léger du cache disque sous pression mémoire.

**Garde-fous** : si `hasHeavy` faux ou download heavy échoue → on **reste sur le
léger** (jamais de régression visuelle). Le swap ne doit pas “sauter” : matcher
exactement transform + échelle (les 2 USDZ ont le même `upAxis` et sont cadrés
pareil par Meshy/optimisation).

### D. Thumbnails
Déjà **pré-rendus** pour les 124 plantes (`render_thumbnails.py`). À déployer dans
`models/thumbnails/<id>.png`. ⚠️ Nommés par `plant.id` → re-render avec les `_id`
**prod** au moment de l'import prod (les ids test ≠ prod). Bénéfice : aucun device
ne subit la grosse 1ère génération.

### E. Déploiement (rsync, local → prod, overwrite)
```bash
# code (schéma + route) via git/deploy.sh ; modèles via rsync (hors git)
rsync -avz Plant3DGenerator/opti_output/     fedora@VPS:…/ArboreBackend/models/
rsync -avz Plant3DGenerator/output/ _legacy/heavy/  fedora@VPS:…/ArboreBackend/models/heavy/
rsync -avz <thumbnails prod>                 fedora@VPS:…/ArboreBackend/models/thumbnails/
```
- Clé SSH : `~/.ssh/epitech` (`fedora@79.137.92.154`).
- `models/*.usdz` + `thumbnails/` sont **gitignorés** (déjà fait).

### F. Réconciliation données prod (priorité botanic)
À l'import prod : pour les **12 plantes en doublon** (Monstera, Pilea, Ficus…),
**supprimer le doc + modèle legacy** et garder la version botanic (règle “botanic
prioritaire”). Les 26 legacy uniques restent. Net : 38 legacy → 26 conservées + 98
botanic = **124 plantes** en prod.

## Séquencement
1. Schéma `hasHeavy` (backend Go + iOS + web) — commit dans PR #288.
2. Route backend `/models/heavy/:filename`.
3. iOS : `ModelCacheManager` LOD + swap RealityKit dans la vue AR + annulation.
4. Merger/déployer PR #288 (code).
5. rsync des modèles (light/heavy) + re-render thumbnails avec ids prod.
6. Import prod des 98 botanic + suppression des 12 legacy en doublon.
7. QA : catalogue (PNG), placement AR (léger rapide → swap lourd), mémoire OK.

## Risques / notes
- **Swap visible** : si le cadrage léger/lourd diffère légèrement, l'utilisateur
  peut voir un “pop”. Mitiger : fondu (opacité) sur 0,2 s au swap.
- **Réseau lent** : le heavy peut ne jamais finir — c'est OK, le léger reste.
- **Mémoire** : ne jamais garder léger **et** lourd longtemps ; libérer le léger
  juste après le swap.
- **Legacy heavy** : pour les 26 legacy, “heavy” = textures 4K (même mesh lowpoly)
  → le swap améliore surtout la résolution de texture, pas la géométrie. OK.
