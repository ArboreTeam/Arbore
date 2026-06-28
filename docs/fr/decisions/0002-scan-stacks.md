# ADR 0002 — Stack de scan double : RoomPlan (LiDAR) + tracé périmètre (non-LiDAR)

- **Statut** : Accepted
- **Date** : 2026-04-15
- **Décideurs** : Équipe Arbore

## Contexte

L'application doit permettre à l'utilisateur de **capturer son espace** (jardin, balcon, intérieur) afin d'y placer des plantes 3D en réalité augmentée. Plusieurs technologies sont disponibles sur iOS pour réaliser cette capture, avec des contraintes différentes en termes de devices supportés, qualité du résultat, et durée du scan.

Le parc d'utilisateurs cible inclut **tous les iPhone à partir de l'iPhone 11** (iOS 17+), ce qui comprend :

- Les **iPhone Pro / Pro Max / iPad Pro** récents (iPhone 12 Pro+) équipés d'un **capteur LiDAR**, qui ouvre l'accès aux API Apple `ARKit.meshWithClassification` et `RoomPlan`.
- Les **iPhone non-Pro** (iPhone 11 à 15 non-Pro), qui n'ont pas de LiDAR et doivent se contenter du tracking visuel ARKit.

Le wizard de création de jardin propose donc à l'utilisateur de choisir sa méthode de scan via l'étape `scanMethod` (cf. `Views/GardenSteps/ScanMethodSelectionView.swift`).

## Décision

L'application maintient **deux stacks de scan parallèles**, sélectionnées au runtime selon le device :

- **`gardenPerimeter` (non-LiDAR, défaut universel)** — `ARViewContainerMeasure` utilise les raycasts ARKit pour permettre à l'utilisateur de tracer manuellement le **polygone du sol** point par point. Aucun mesh 3D n'est construit ; seul un `[SIMD3<Float>]` représentant le périmètre est sauvegardé. Marche sur **tous les iPhones** ciblés.

- **`roomScan` (LiDAR uniquement)** — `LiDARScanWizardView` utilise `RoomPlan.RoomCaptureSession` pour produire un modèle structuré (murs, sols, portes, fenêtres). La carte est grisée dans le wizard si `RoomCaptureSession.isSupported == false`.

Apple **ObjectCapture** (`PhotogrammetrySession`, iOS 17+, Area mode iOS 18+) n'est **pas intégrée à ce stade** mais reste en candidate forte pour étendre le scan non-LiDAR à une vraie reconstruction 3D dense. Cette extension fait l'objet de l'issue #140.

## Conséquences

### Positives

- Tous les iPhones du parc cible peuvent utiliser l'application sans dégradation fonctionnelle.
- Les utilisateurs LiDAR bénéficient d'une qualité de scan supérieure (murs et meubles classifiés).
- Le wizard expose explicitement le choix à l'utilisateur via `ScanMethodSelectionView`, ce qui rend le compromis lisible.

### Négatives

- Le codebase porte **deux flows AR distincts**, ce qui double la surface de maintenance (cf. issue #81 : unifier les five AR view containers dupliqués).
- Le rendu visuel diffère sensiblement entre les deux methods, ce qui peut surprendre l'utilisateur qui change de device.
- Le scan non-LiDAR reste limité au polygone du sol, sans information sur les obstacles 3D, ce qui interdit certaines features futures (snap automatique des plantes à un mur, par exemple).

### Neutres

- Les deux méthodes produisent des données différentes côté `GardenLocalStore` (`boundaryPoints: [SIMD3<Float>]` versus `worldmap_{id}.arworldmap` LiDAR). La couche AR consomme les deux indifféremment via les paramètres de `GardenARPlacementView`.
- ObjectCapture, si intégrée plus tard (#140), apporterait un troisième stack — mais l'expérience utilisateur prévue (scan dédié 30-60 s + processing 1-2 min) serait suffisamment différente pour cohabiter avec les deux existants plutôt que les remplacer.

## Alternatives considérées

- **ARKit `sceneReconstruction = .meshWithClassification` uniquement (LiDAR-only)** — écarté car réserverait l'app aux iPhone Pro, ce qui amputerait drastiquement le parc utilisateurs.
- **ObjectCapture pour tous (non-LiDAR universel)** — écarté à court terme parce que l'UX du scan ObjectCapture (30-60 s de capture + 1-2 min de processing) est trop lourde pour le flow de création de jardin actuel. Reste candidate pour des features secondaires (cf. issue #140).
- **Modèles ML custom de monocular depth (Depth Anything V2, MiDaS)** — pressentis dans l'issue #97 mais hors scope court terme : conversion CoreML non triviale, latence on-device incertaine, et le scan polygone du sol suffit pour l'objectif actuel (placer des plantes en AR sur un terrain plan).
- **Pas de scan du tout, l'utilisateur place « à l'œil »** — écarté car la mesure du périmètre apporte une vraie utilité métier (surface affichée, suggestion AI calibrée).

## Liens

- [Issue #139 — validation roomScan end-to-end](https://github.com/ArboreTeam/Arbore/issues/139)
- [Issue #140 — Scene-to-scene ICP registration (où ObjectCapture est candidat)](https://github.com/ArboreTeam/Arbore/issues/140)
- [Issue #97 — Pipeline neural Depth Anything V2 (alternative future)](https://github.com/ArboreTeam/Arbore/issues/97)
- [Apple — RoomPlan documentation](https://developer.apple.com/documentation/roomplan)
- [Apple — Object Capture documentation](https://developer.apple.com/documentation/realitykit/realitykit-object-capture/)
