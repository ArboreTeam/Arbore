# Per-screen spec — `QuestionnaireView` (wizard de création)

## Objectif

`QuestionnaireView` conduit l'utilisateur du choix de l'espace au placement AR avec **trois écrans visibles** : `spaceType`, `essentialQuestions`, puis `aiSuggestion`. La mesure, l'exposition éventuelle et la localisation restent des sous-flows contextuels, sans page de récapitulatif.

Implémentation principale : `Views/GardenSteps/QuestionnaireView.swift`.

## Entrée et sorties

| Action | Destination |
|---|---|
| « Créer un jardin » depuis la Home | `GardenWizardView`, première étape `spaceType`. |
| **Continuer** après le choix de l'espace | Prompt système caméra si nécessaire, puis scan direct. |
| Validation de la localisation | Étape `essentialQuestions`. |
| Questions validées ou « Répondre plus tard » | Étape `aiSuggestion`. |
| **Placer mes plantes en AR** | `GardenARPlacementView` avec le jardin déjà créé. |
| Retour depuis la première étape ou X | `dismiss()` vers la Home. |

## Flux

```mermaid
flowchart TB
    space["1 — Choisir l'espace"]
    permission["Prompt caméra si nécessaire"]
    scan["Scan automatique<br/>RoomPlan ou tracé"]
    exposure["Exposition en caméra<br/>sauf jardin"]
    location["Localisation fraîche"]
    questions["2 — 3 questions conditionnelles"]
    ai["3 — Suggestions de plantes"]
    placement["Placement AR"]

    space --> permission --> scan
    scan -->|pièce, balcon, terrasse| exposure --> location
    scan -->|jardin| location
    location --> questions --> ai --> placement
```

`visibleSteps` ne contient que :

```swift
[.spaceType, .essentialQuestions, .aiSuggestion]
```

## Choix automatique de la méthode

- Pièce et `RoomCaptureSession.isSupported == true` : `roomScan`.
- Tous les autres cas : `gardenPerimeter`.
- « Changer de méthode » apparaît dans la caméra uniquement pour une pièce compatible RoomPlan.

La page `ScanMethodSelectionView` n'existe plus. Le CTA **Continuer** de `SpaceTypeStepView` pose `state.scanMethod`, demande directement l'autorisation système si son état est `.notDetermined`, puis ouvre la full-screen cover AR. `GardenAnalysisAuthorizationFlowView` est uniquement un écran de récupération après refus, avec accès aux Réglages.

## Sous-flows

### Mesure et création

`ARViewContainerMeasure` trace le contour au sol. `LiDARScanWizardView` utilise RoomPlan. Après validation des dimensions, aucune vérification supplémentaire n'est demandée. Le scan enregistre la WorldMap et les mesures, puis crée le jardin avec `POST /gardens` et `plants: []`.

### Exposition

Pour une pièce, un balcon ou une terrasse, `GardenExposureCaptureOverlay` apparaît sans fermer la caméra. L'utilisateur vise la source lumineuse principale et confirme. Un jardin ignore cette capture.

### Localisation

Après fermeture de la caméra, `GardenLocationCaptureView` demande une nouvelle localisation approximative pour chaque jardin. `state.location` est toujours réinitialisé avant une création. La ville manuelle et la poursuite sans localisation restent disponibles. La valeur est ajoutée au jardin par `PUT /gardens/:id`.

### Questions conditionnelles

`EssentialQuestionsStepView` tient sur une page et affiche trois cartes compactes :

- Jardin : mode de plantation, drainage après pluie, sécurité.
- Balcon / terrasse : vent, pots existants ou nouvelle composition, sécurité.
- Pièce : humidité de l'air, chauffage proche, sécurité.

Chaque carte possède « Je ne sais pas ». Toutes les réponses sont facultatives et le CTA reste actif avec zéro, une, deux ou trois réponses. Les valeurs inconnues ne sont pas sérialisées. Les réponses connues alimentent `wizard.conditionalAnswers`, tandis que la sécurité alimente le champ existant `wizard.safety`. Elles sont sauvegardées avant la suggestion, sans bloquer l'utilisateur si le réseau échoue.

### Suggestion et placement

`AISuggestionStepView` utilise le catalogue et les mesures disponibles. Son CTA ouvre `GardenARPlacementView` avec `existingGardenId`; la validation finale met à jour le jardin par `PUT /gardens/:id`, puis ouvre directement son plan 2D dans l'onglet Jardin. La fiche éditable `GardenSpaceProfileView` y regroupe les données mesurées, déduites ou déclarées sans ajouter d'étape au wizard.

## Cas limites

| Situation | Comportement |
|---|---|
| Caméra déjà autorisée | Le scan s'ouvre directement. |
| Première demande caméra | Le prompt iOS apparaît sur l'écran de choix de l'espace. |
| Caméra refusée | Écran de récupération avec ouverture des Réglages. |
| Localisation refusée | Ville manuelle ou poursuite sans localisation ; aucune ancienne position n'est reprise. |
| Question inconnue ou ignorée | Aucun champ n'est inventé ; la suggestion continue avec les données disponibles. |
| Enregistrement des questions indisponible | Les réponses restent en mémoire et seront renvoyées lors du placement final. |
| Backend indisponible après le tracé | Message inline et nouvelle tentative possible. |
| Changement de méthode | L'ancienne caméra se ferme et l'autre moteur s'ouvre ; uniquement pour une pièce compatible RoomPlan. |

## Dépendances

- `AVFoundation` : statut et demande caméra.
- `RoomPlan` : disponibilité et scan 3D.
- `CoreLocation` : localisation ponctuelle approximative.
- `CoreMotion` et ARKit : orientation et luminosité lors de l'exposition.
- `GardenAPI` / `NetworkManager` : création et mises à jour du jardin.
- Détail du flux : [`../flows/garden-creation.md`](../flows/garden-creation.md).
