# Glossaire

Vocabulaire du domaine Arbore. Tout terme métier, technique iOS ou raccourci interne doit faire l'objet d'une entrée afin de permettre l'onboarding d'un nouveau développeur en moins de dix minutes.

Convention : ordre alphabétique, **terme** en gras, définition tenant en une à trois phrases.

---

## AR (Augmented Reality)

Réalité augmentée — superposition d'objets virtuels (plantes 3D) sur le flux caméra. Sur iOS, repose sur **ARKit** (tracking, plan detection) et sur **SceneKit** (rendu actuel) ou **RealityKit** (cible, cf. issue #83).

## ARWorldMap

Sérialisation **ARKit** de l'état d'une session AR (points caractéristiques et ancres). Sauvegardée sur disque par jardin (`worldmap_{id}.arworldmap`), elle est rechargée à la réouverture du jardin pour replacer les plantes aux mêmes coordonnées. Très sensible aux changements d'éclairage entre sessions (cf. issue #96).

## Anchor (ARAnchor)

Point fixe attaché à une position dans le monde réel, suivi par ARKit. Chaque plante placée se voit associer un `ARAnchor`. Les ancres sont sérialisées dans la WorldMap pour assurer la persistance entre sessions.

## Boundary

Polygone fermé au sol qui délimite la zone du jardin. Tracé par l'utilisateur en mode `gardenPerimeter` (non-LiDAR) ou dérivé du scan **RoomPlan** (LiDAR). Représenté en mémoire sous la forme `[SIMD3<Float>]`.

## C4 Model

Modèle d'architecture en quatre niveaux (**C**ontext, **C**ontainer, **C**omponent, **C**ode) défini par Simon Brown. Appliqué à Arbore dans `docs/architecture/`. Le niveau Code est volontairement omis : le code source en tient lieu.

## Hero screen

Écran principal et complexe qui justifie une documentation per-screen dédiée. Pour Arbore : `GardenARPlacementView`, `QuestionnaireView` et `PersonalDetailsView`. Les écrans simples (un bouton, une navigation) ne sont pas considérés comme hero screens et ne disposent pas de spec dédiée.

## ICP (Iterative Closest Point)

Algorithme de registration entre deux nuages de points ou meshes. Calcule la transformation rigide (rotation et translation) qui minimise la distance entre correspondances. Pressenti pour la **scene-to-scene registration** (issue #140) en alternative à la reloc-pose ARWorldMap.

## Manual Replace

Flux de re-placement manuel des plantes activé lorsque la relocalisation ARWorldMap échoue. L'utilisateur retrace une nouvelle boundary ; les positions des plantes sont **morphées** via MVC pour suivre la nouvelle forme. Implémenté dans `GardenARPlacementView` (issue #111, mergée).

## MVC (Mean Value Coordinates)

Méthode mathématique (Floater, 2003) pour exprimer un point intérieur d'un polygone comme combinaison pondérée des sommets, puis reconstruire un point équivalent dans un autre polygone à l'aide des mêmes poids. Utilisée dans `GardenMorpher` pour morpher les positions des plantes entre old boundary et new boundary.

## ObjectCapture

API Apple (`PhotogrammetrySession`, iOS 17+, Area mode iOS 18+) qui produit un mesh 3D texturé à partir d'un ensemble de photos. Constitue l'alternative non-LiDAR à RoomPlan, pressentie pour le chemin non-LiDAR de l'issue #140.

## Per-screen spec

Document Markdown qui décrit en détail un seul écran principal (hero screen) : purpose, entry et exit points, widgets, edge cases et dépendances. La liste complète figure dans `docs/screens/_index.md` (Phase 4).

## PhotogrammetrySession

Voir [**ObjectCapture**](#objectcapture).

## Plant

Entrée du catalogue MongoDB : nom, type, image URLs, traductions multilingues, URL du modèle USDZ, indicateur `generated` (modèle issu de Meshy ou non) et `upAxis` (Y- ou Z-up). La structure complète est documentée dans `04-data-model.md` (Phase 2).

## RelocationPhase

Enum Swift défini dans `GardenARPlacementView` qui gère les cinq états du **manual replace** : `.scanning`, `.tracingBoundary`, `.morphingPreview`, `.adjusting` et `.completed`. Diagrammée dans `state-machines/relocation-phase.md` (Phase 3).

## RoomPlan

Framework Apple (iOS 16+, LiDAR uniquement) qui scanne une pièce en 3D et produit un modèle structuré (murs, sols, portes, fenêtres, meubles). Utilisé dans `LiDARScanWizardView` comme alternative au tracé périmètre. Vérifier le support du device via `RoomCaptureSession.isSupported`.

## scanMethod

Enum porté par `GardenWizardState` qui détermine la stratégie de scan : `.gardenPerimeter` (tracé 2D au sol, non-LiDAR) ou `.roomScan` (RoomPlan, LiDAR uniquement). Choisi à l'étape `.scanMethod` du wizard.

## ScreenSpec

Voir [**Per-screen spec**](#per-screen-spec).

## Sprint

Période d'environ un mois matérialisée par un GitHub Milestone. Sprint en cours : Sprint 3 (échéance 2026-06-14). Un sprint regroupe les issues à livrer dans la période.

## Token (Firebase ID Token)

Bearer token JWT signé par Firebase Auth, transmis par l'application iOS et le web dans l'en-tête `Authorization` de chaque requête au backend. Le backend le valide via le Firebase Admin SDK et en extrait l'`uid` Firebase.

## TestFlight

Plateforme Apple de distribution beta. Un build interne est déposé pour l'équipe ainsi que pour le reviewer Apple (compte `apple-review@arbore.app`). La diffusion publique TestFlight est suivie dans l'issue #15 (Sprint 4).

## USDZ

Format de modèle 3D Apple (archive ZIP contenant un fichier USD et ses textures). Tous les modèles de plantes du catalogue sont stockés au format USDZ dans `ArboreBackend/models/`, servis via l'endpoint `GET /models/:filename` et rendus en AR via SceneKit.

## VPS (Fedora)

Serveur unique qui héberge le backend Go et l'AI Generator Python via Docker Compose. L'accès SSH s'effectue via la connexion MCP `ssh-arbore-backend`. Détails dans [`02-containers.md`](architecture/02-containers.md).

## WorldMap

Voir [**ARWorldMap**](#arworldmap).

## Wizard

Flux de création de jardin en dix étapes (`GardenWizardStep`) : intro → style → spaceType → exposure → maintenance → safety → soil → aiSuggestion → scanMethod → summary. Implémenté sous forme de `TabView` dans `QuestionnaireView`. Cible d'une per-screen spec en Phase 4.

---

## Acronymes courts

| Acronyme | Sens |
|---|---|
| **ADR** | Architecture Decision Record |
| **AR** | Augmented Reality |
| **ATS** | App Transport Security (politique HTTPS iOS) |
| **CI/CD** | Continuous Integration / Continuous Delivery |
| **DoD** | Definition of Done |
| **ER** | Entity-Relationship (diagram) |
| **IAP** | In-App Purchase |
| **ICP** | Iterative Closest Point |
| **JWT** | JSON Web Token |
| **MADR** | Markdown Architectural Decision Records |
| **MVC** (math) | Mean Value Coordinates (algorithme de Floater) |
| **MVC** (GUI, non utilisé dans Arbore) | Model-View-Controller — mentionné pour éviter la confusion avec l'acronyme mathématique ci-dessus |
| **MVP** | Minimum Viable Product |
| **RGPD** | Règlement Général sur la Protection des Données |
| **SfM** | Structure from Motion (reconstruction 3D multi-vues) |
| **TSDF** | Truncated Signed Distance Field (représentation 3D volumétrique) |
| **USDZ** | Universal Scene Description Zipped (format 3D Apple) |
