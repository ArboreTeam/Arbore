# ADR 0003 — Stratégie de relocalisation : ARWorldMap + fallback manual replace

- **Statut** : Accepted
- **Date** : 2026-04-29
- **Décideurs** : Équipe Arbore

## Contexte

Lorsqu'un utilisateur crée un jardin dans l'application, les positions des plantes 3D sont **ancrées au monde réel** via des `ARAnchor`. Pour que ces positions soient restaurées lors de la réouverture du jardin (potentiellement plusieurs jours ou semaines plus tard), il faut sérialiser l'état de la session AR — `ARKit` propose pour cela les **`ARWorldMap`**.

Le problème : la relocalisation contre un `ARWorldMap` sauvegardé n'est pas fiable. ARKit se repose sur des **points caractéristiques visuels** détectés à la création, et ne parvient pas toujours à les retrouver si :

- L'éclairage a changé (jour vs nuit, météo, ombres).
- L'environnement a été modifié (meubles déplacés, plantes existantes ayant poussé).
- Le device a changé (caméra différente, calibration différente).

Sur un device LiDAR, la mesh structurelle de la pièce aide. Sur un device non-LiDAR, la relocalisation **échoue régulièrement** (cf. issue #96), ce qui laisserait l'utilisateur bloqué sur un écran de coaching sans solution.

## Décision

L'application adopte une **stratégie de relocalisation à trois étages** documentée dans [`../flows/ar-placement.md`](../flows/ar-placement.md) :

1. **Étage 1 — `ARWorldMap.relocalize`** : tentative classique au démarrage de la session AR. Si l'éclairage est compatible, la relocalisation réussit en quelques secondes et les plantes sont restaurées via leurs `ARAnchor`.

2. **Étage 2 — Manual replacement (issue #111)** : si l'étage 1 ne réussit pas, l'utilisateur peut tap sur **« Replacer manuellement »**. Il retrace le périmètre du jardin, et les positions des plantes sont **morphées automatiquement** via les Mean Value Coordinates (Floater 2003) de l'ancien périmètre vers le nouveau. Un score de distorsion par plante avertit l'utilisateur des zones de forte déformation, et un mode `adjusting` permet d'affiner manuellement les positions avant sauvegarde finale.

3. **Étage 3 — Scene-to-scene ICP (issue #140, futur)** : à terme, capturer une nouvelle scène 3D (LiDAR via `ARKit.meshWithClassification` ou non-LiDAR via `ObjectCapture`) et la **registrer** contre la scène sauvegardée pour calculer une transformation rigide. Le score RMS post-alignement servirait également d'indicateur de similarité à montrer à l'utilisateur (« ton jardin a changé »). Cette piste reste à valider via un spike.

Le pipeline neural depth + matching (issue #97) reste candidat à un quatrième étage **uniquement** si les étages 1-3 s'avèrent insuffisants en production.

## Conséquences

### Positives

- L'utilisateur n'est **jamais bloqué** sur un écran de coaching infini : la manual replace est immédiatement accessible.
- Le morphing MVC produit des résultats acceptables même lorsque la forme du périmètre change significativement entre sessions.
- La stratégie est **layered** : on tente le moins coûteux d'abord (ARWorldMap), on dégrade vers le plus coûteux si nécessaire (manual replace, puis ICP).

### Négatives

- L'expérience utilisateur post-manual-replace dépend de la qualité du tracé et du morphing — les plantes peuvent se retrouver en zones de forte distorsion, marquées en orange mais nécessitant un ajustement manuel.
- Le manual replace ne fonctionne que si **l'ancien périmètre** est lisible en mémoire (chargé depuis le `scene_{id}.json`). Si ce fichier n'existe pas (cas du device fraîchement installé, cf. issue #114), même la manual replace est impossible et l'utilisateur voit le `gardenUnavailableView`.
- Le code de l'étage 2 a substantiellement augmenté la taille de `GardenARPlacementView` (de ~2 000 à ~3 300 lignes), aggravant la dette technique du god object (issue #124).

### Neutres

- Le morphing MVC est testable isolément (math pure) et fera l'objet de tests unitaires dédiés (issue #123).
- L'étage 3 (ICP scene-to-scene) reste un parti pris architectural à confirmer — son ajout ne remet pas en cause l'étage 2 mais offre une alternative plus rapide pour les utilisateurs LiDAR.

## Alternatives considérées

- **Tout miser sur `ARWorldMap.relocalize` et bloquer l'utilisateur en cas d'échec** — l'approche initiale, abandonnée après les retours négatifs des testeurs (issue #96).
- **Sauvegarder les positions des plantes en coordonnées GPS** — écarté car la précision GPS (quelques mètres) est totalement incompatible avec le placement intra-jardin précis dont l'app a besoin.
- **Imposer une « pose de référence » au démarrage de chaque session** — écarté car friction UX trop importante (l'utilisateur devrait se replacer exactement à l'endroit où il avait sauvegardé, ce qui est rarement possible).
- **Backend qui stocke les positions et l'utilisateur les replace à zéro** — écarté car perdrait tout l'intérêt AR : la position serait dans un repère abstrait, pas dans le monde réel.

## Liens

- [Issue #96 — Relocalisation échoue si l'éclairage change](https://github.com/ArboreTeam/Arbore/issues/96)
- [Issue #111 — Manual replace avec morphing (mergée 2026-04-29)](https://github.com/ArboreTeam/Arbore/issues/111)
- [Issue #140 — Scene-to-scene ICP registration (futur)](https://github.com/ArboreTeam/Arbore/issues/140)
- [Issue #97 — Pipeline neural depth + matching](https://github.com/ArboreTeam/Arbore/issues/97)
- [Issue #114 — Garden lost after app reinstall](https://github.com/ArboreTeam/Arbore/issues/114)
- [Apple — ARWorldMap documentation](https://developer.apple.com/documentation/arkit/arworldmap)
- [Floater, M. S. (2003). Mean value coordinates. *Computer Aided Geometric Design*.](https://www.cs.jhu.edu/~misha/Fall09/Floater03.pdf)
