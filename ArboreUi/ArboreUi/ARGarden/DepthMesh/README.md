# DepthMesh — visualisation 3D du monde via depth ML (non-LiDAR)

Module qui reconstruit un **maillage 3D approximatif** de l'environnement sur les
iPhones **sans LiDAR**, en utilisant un modèle CoreML de prédiction de
profondeur monoculaire (Depth Anything V2 Small). Affiche le mesh en overlay
debug avec **couleur par hauteur** et **séparation des surfaces** (connected
components) — équivalent visuel du Scene Mesh de Meta Quest.

> **Scope** : non-LiDAR uniquement. Les iPhone Pro continuent d'utiliser
> `ARMeshAnchor` natif qui est plus précis et gratuit en CPU.

## Architecture

```
ARFrame.capturedImage  (CVPixelBuffer, 1920×1440-ish)
        │
        ▼
   DepthPredictor                ← CoreML : DepthAnythingV2SmallF16
        │  CVPixelBuffer (518×686, mono, inverse depth)
        ▼
   DepthMesher                   ← back-projection via camera intrinsics
        │  [vertices, triangles, world-space]
        ▼
   DepthMeshVizRenderer          ← height-based hue + connected components
        │  SCNGeometry (per-vertex color)
        ▼
   GardenARPlacementView         ← debug toggle dans la topBar
```

## Setup (one-time)

### 1. Télécharger le modèle

```sh
./scripts/fetch-depth-model.sh
```

Le modèle (~50MB) est gitignored (`*.mlpackage/`). Il atterit dans
`ArboreUi/ArboreUi/ARGarden/DepthMesh/Models/DepthAnythingV2SmallF16.mlpackage`.

### 2. Ajouter le `.mlpackage` au projet Xcode

Xcode 16 + PBXFileSystemSynchronizedRootGroup ne picke pas les
`.mlpackage` automatiquement — ce sont des bundles. Tu dois :

1. Ouvrir `ArboreUi.xcodeproj`
2. Drag-and-drop le dossier `Models/` depuis le Finder dans le navigator
3. Cocher "Copy items if needed" + ajouter au target `ArboreUi`
4. Vérifier dans **Build Phases → Copy Bundle Resources** que le
   `.mlpackage` est listé.
5. Build : Xcode va le compiler en `.mlmodelc` automatiquement.

À l'exécution, le wrapper `DepthPredictor` cherche le modèle dans le
bundle via `Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlmodelc")`.
Si absent → `DepthPredictor.init()` lève une erreur, le toggle debug
reste désactivé (graceful degradation).

## Performance & throttling

| Étape          | Coût observé (iPhone 15 Pro, ANE) |
|----------------|-----------------------------------|
| Predict depth  | ~30ms                             |
| Mesh extract   | ~5ms (downsampled 4×)             |
| Color + CC     | ~10ms                             |
| **Total**      | **~45ms / frame**                 |

On throttle à **2 Hz** (500ms entre passes) pour ne pas tuer la session
AR. La feature est OFF par défaut, opt-in via toggle debug.

## Limitations

1. **Pas de scale métrique absolue**. Depth Anything V2 prédit du
   *relative inverse depth*. On calibre en utilisant la hauteur de la
   caméra par rapport à `ARPlaneAnchor.horizontal` (le sol détecté).
   Précision ~±10cm.
2. **Pas de fusion temporelle**. Chaque frame régénère un mesh
   indépendant — pas de TSDF, donc des flickers entre frames.
3. **Bords flous**. Les transitions de profondeur (silhouettes
   d'objets) sont lissées par le modèle ; les contours sont mous.
4. **Sky / fenêtres lointaines**. Le modèle peut prédire des valeurs
   aberrantes — on filtre via un threshold de depth max (10m).

## Références

- Modèle : https://huggingface.co/apple/coreml-depth-anything-v2-small
- Paper : Depth Anything V2 (Yang et al., 2024) — arxiv 2406.09414
- Exemple Swift : https://github.com/huggingface/coreml-examples/tree/main/depth-anything-example
