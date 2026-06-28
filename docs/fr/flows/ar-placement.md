# Flux — Placement AR (création et réouverture)

Ce document décrit le **flux complet d'ouverture de la vue AR** qui permet à l'utilisateur de placer des plantes en réalité augmentée. Deux entrées principales : la création d'un jardin neuf (depuis le wizard) et la réouverture d'un jardin existant (depuis la Home). Le code de référence est `ARGarden/GardenARPlacementView.swift`.

## Vue d'ensemble

| Mode | Entrée | Comportement |
|---|---|---|
| `.create` | Sortie du wizard → `ARViewContainerMeasure` (perimeter) **ou** `LiDARScanWizardView` (LiDAR) | Démarre une session ARKit fraîche, l'utilisateur place les plantes manuellement, sauvegarde finale via `Valider`. |
| `.reopen` | Tap sur une carte jardin de la Home | Tente de relocaliser la `ARWorldMap` sauvegardée. En cas d'échec, le manual replace (#111) prend le relais. |

Le pivot entre ces deux modes est porté par la machine d'états [`RelocationPhase`](../state-machines/relocation-phase.md) documentée séparément.

## Diagramme

```mermaid
flowchart TB
    home([Tap sur carte jardin Home])
    wizard([Sortie wizard<br/>bouton Placer mes plantes en AR])

    open["GardenARPlacementView.onAppear"]
    detect_mode{mode ?}

    create_flow["Mode .create<br/>session ARKit fraîche<br/>boundary connue depuis wizard"]
    place_create["Utilisateur place les plantes<br/>via picker catalogue + tap au sol"]

    reopen_flow["Mode .reopen<br/>charge worldmap arworldmap"]
    arkit_reloc["ARKit relocalize la WorldMap"]
    reloc_result{relocalize OK ?}

    load_normal["loadGardenFromDisk<br/>plantes restaurées via ARAnchor"]

    manual["RelocationPhase.scanning<br/>coaching overlay + bouton<br/>Replacer manuellement"]
    user_choice{choix utilisateur}
    trace["RelocationPhase.tracingBoundary"]
    morph["RelocationPhase.morphingPreview"]
    adjust["RelocationPhase.adjusting"]

    save["captureCurrentState<br/>+ archivedData WorldMap<br/>+ PUT /gardens.plants"]
    dismiss([Retour Home])

    home --> open
    wizard --> open
    open --> detect_mode

    detect_mode -->|create| create_flow
    create_flow --> place_create
    place_create --> save

    detect_mode -->|reopen| reopen_flow
    reopen_flow --> arkit_reloc
    arkit_reloc --> reloc_result

    reloc_result -->|OK mapped| load_normal
    load_normal --> save

    reloc_result -->|KO limited| manual
    manual --> user_choice
    user_choice -->|tap Replacer manuellement| trace
    user_choice -->|tap X| dismiss
    trace --> morph
    morph -->|confirmer placement| adjust
    morph -->|annuler| trace
    adjust --> save

    save --> dismiss

    classDef startN fill:#08427B,stroke:#073B6F,color:#fff
    classDef state  fill:#1168BD,stroke:#0B4884,color:#fff
    classDef cond   fill:#2E7D32,stroke:#1B5E20,color:#fff
    classDef ar     fill:#6A1B9A,stroke:#4A148C,color:#fff
    classDef endN   fill:#999,stroke:#666,color:#fff
    class home,wizard startN
    class open,create_flow,reopen_flow,load_normal,save state
    class detect_mode,reloc_result,user_choice cond
    class place_create,manual,trace,morph,adjust ar
    class dismiss endN
```

## Mode `.create` — création nouvelle session

L'entrée se fait depuis la sortie du wizard (cf. [`garden-creation.md`](garden-creation.md)). La vue AR reçoit déjà :

- `selectedPlants: [Plant]` — set de plantes choisies par l'utilisateur.
- `boundaryPoints: [SIMD3<Float>]` — polygone du sol tracé en non-LiDAR.
- `measurementWorldMapId: String?` — UUID renseigné si le scan a été fait en LiDAR (la WorldMap a déjà été sauvegardée par `LiDARScanWizardView` au chemin `worldmap_{measurementWorldMapId}.arworldmap`).
- `mode: .create`.

**Comportement** :

1. `ARSession` démarrée fraîchement (pas de relocalisation à tenter).
2. La boundary est dessinée au sol en cylindres bleus.
3. L'utilisateur ouvre le **picker catalogue** via le bouton **+**, tape sur le sol pour placer une plante, peut drag/scale/rotate.
4. Bouton **Valider** : la WorldMap actuelle est archivée, le `scene_{id}.json` est écrit, et `PUT /gardens/:id` envoie l'état des plantes au backend.
5. Retour Home avec feedback de succès.

À ce stade, `RelocationPhase` reste à sa valeur initiale `.scanning` mais aucun overlay manual replace n'apparaît — la machine n'est pas pertinente en mode `.create`.

## Mode `.reopen` — réouverture jardin existant

L'entrée se fait depuis la Home, tap sur une carte jardin. La vue AR reçoit :

- `existingGardenId: String` — ID du jardin Mongo.
- `mode: .reopen`.

**Comportement** :

1. `onAppear` charge en parallèle :
   - La WorldMap depuis disque (`GardenLocalStore.worldMapURL(for: id)`).
   - Le scene JSON (positions des plantes) depuis disque.
2. `ARSession` est démarrée avec `initialWorldMap` posée sur la WorldMap chargée → ARKit entre en mode **relocalisation**.
3. Le coaching overlay (composant `ScanningCoachingOverlay`) est affiché au bas de l'écran, **non-bloquant** : l'utilisateur voit la caméra et peut bouger son téléphone.
4. ARKit lance un thread de relocalisation qui tourne tant que `frame.camera.trackingState != .normal`.

À partir de là, deux chemins possibles.

### Chemin nominal : relocalisation réussie

`session(_:didUpdate:)` détecte que la WorldMap est passée en état `.mapped` :

1. `loadGardenFromDisk` est appelé. Il restaure :
   - Chaque plante via son `ARAnchor` lu dans la WorldMap (les ancres reprennent leur position exacte).
   - Les modèles USDZ depuis `ModelCacheManager` (déjà cachés sur disque, pas de re-téléchargement).
2. La vue passe en mode édition : l'utilisateur peut modifier les positions, ajouter/retirer des plantes via le picker.
3. À la validation, même flow de sauvegarde que `.create`.

Ce chemin est le plus rapide en UX (quelques secondes pour la relocalisation si l'éclairage est similaire).

### Chemin dégradé : relocalisation échoue

Si après quelques secondes la WorldMap reste en `.limited` (changement d'éclairage entre sessions, environnement modifié — cf. issue #96), le coaching overlay reste affiché avec le bouton **« Replacer manuellement »** accessible.

À ce moment, deux options pour l'utilisateur :

| Action | Effet |
|---|---|
| Continuer à attendre / bouger le téléphone | L'ARKit `relocalize` peut encore réussir si l'éclairage devient compatible. Si jamais, la machine reste à `.scanning`. |
| Tap **« Replacer manuellement »** | `enterManualReplacement()` → la machine [`RelocationPhase`](../state-machines/relocation-phase.md) bascule sur `.tracingBoundary` et le flux manuel prend le relais. |
| Tap X | Dismiss complet, retour Home sans modification du jardin. |

Une fois le manual replace lancé (`tracingBoundary` → `morphingPreview` → `adjusting`), la fin du flow rejoint le chemin de sauvegarde commun.

## Sauvegarde finale

Quelle que soit l'origine du flow (`create`, `reopen` nominal, `reopen` manual replace), la validation finale appelle `captureCurrentState` qui :

1. Itère sur les nodes de plante et lit leur transform 4×4. Pour chaque plante :
   - Si une override drag/teleport est présente dans `pendingDragTransform[uuid]`, l'utilise (issue #138 — garantit que le dernier geste utilisateur est persisté même si le `rebaseAnchorAtCurrentPosition` échoue silencieusement).
   - Sinon, lit le transform de l'`ARAnchor` associée.
   - En dernier recours, lit `node.simdWorldTransform` directement.
2. Archive la `ARWorldMap` actuelle via `NSKeyedArchiver` et l'écrit sur disque (`worldmap_{id}.arworldmap`).
3. Sérialise le scene JSON (positions, modèles, scales) et l'écrit sur disque (`scene_{id}.json`).
4. Émet un `PUT /gardens/:id` avec les positions actualisées (champ `plants[]` du document `gardens`).

Après la sauvegarde, `pendingDragTransform` est purgée et la vue se ferme.

## Cas particuliers

| Situation | Comportement |
|---|---|
| **Premier lancement, app fraîchement installée, jardin créé sur un ancien device** | Aucun fichier `worldmap_{id}.arworldmap` n'existe sur le nouvel appareil. La relocalisation est impossible. → Issue #114 : reconstruction depuis le backend, prévue Sprint 3+. |
| **Plante dont le modèle USDZ n'est pas téléchargé** | `ModelCacheManager` télécharge en tâche de fond. La plante apparaît en placeholder (sphère grise) puis est remplacée par le vrai modèle quand disponible. |
| **Permission caméra refusée** | iOS bloque l'ouverture d'`ARSession`. La vue affiche un état d'erreur avec un bouton pour ouvrir les Réglages. |
| **Device sans LiDAR ouvrant un jardin créé avec LiDAR** | La WorldMap LiDAR contient des plans hautement densifiés. La relocalisation reste possible mais avec une qualité dégradée. Pas de support spécial à ce jour. |
| **App backgroundée pendant 30+ secondes** | ARKit perd le tracking. Au retour, `session(_:didUpdate:)` détecte `.limited` et le coaching overlay peut réapparaître si l'on est en mode `.reopen`. |

## Gestes disponibles

| Geste | Effet |
|---|---|
| Tap sur une plante (mode `.adjusting` ou édition normale) | Sélectionne la plante, affiche l'anneau vert pulsant. |
| Tap sur le sol avec une plante sélectionnée | Téléporte la plante à la position raycast. |
| Long-press + drag | Déplace la plante en continu. |
| Pinch | Met à l'échelle (si autorisé pour la plante). |
| Two-finger rotate | Rotation autour de l'axe Y. |

## Hors-scope de ce flux

- Le détail de la machine d'états `RelocationPhase` (transitions, guards, comportement annuler) est documenté dans [`../state-machines/relocation-phase.md`](../state-machines/relocation-phase.md).
- Le détail mathématique du morphing MVC est dans `ManualReplacement/MeanValueCoordinates.swift` (math pure, testable isolément).
- Le **per-screen spec** complet de `GardenARPlacementView` (incluant l'inventaire de ses widgets internes et de ses overlays) sera ajouté en Phase 4 sous `docs/screens/garden-ar-placement.md`.
- La spec backend du save (`PUT /gardens/:id`) est dans [`../architecture/03-components-backend.md`](../architecture/03-components-backend.md).
