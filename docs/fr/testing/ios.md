# Tests iOS (front)

Les tests de l'application iOS vivent dans deux cibles : `ArboreUi/ArboreUiTests/` (unitaires + intégration, XCTest) et `ArboreUi/ArboreUiUITests/` (XCUITest). Ils combinent des **tests purs déterministes** (mathématiques de reconstruction 3D / morphing, sans ARKit ni réseau) et des **tests d'intégration** qui frappent le vrai backend et Firebase.

## Tests unitaires — pipeline AR / reconstruction 3D

Ces fichiers n'instancient que des types Swift simples (`@testable import ArboreUi`, `XCTest`, `simd`) : rapides et déterministes.

| Fichier | Couvre |
|---|---|
| `ArboreUi/ArboreUiTests/MarchingCubesTests.swift` | `MarchingCubes.extractMesh(...)` : grille vide, coins tous positifs/négatifs, un coin négatif (3 sommets), plan SDF, filtrage `minWeight`. |
| `ArboreUi/ArboreUiTests/TSDFGridTests.swift` | Intégration SDF en moyenne pondérée, troncature, résistance aux outliers, cap `maxWeight`, vote de catégorie, carving pondéré, couleur, `snapshot()`/`clear()`, et **thread-safety** (`test_concurrentIntegrate_isThreadSafe`). |
| `ArboreUi/ArboreUiTests/VoxelGridTests.swift` | Insert/lookup, quantification voxel, indépendance du `snapshot()`, éviction FIFO + tombstones, filtres de bruit (`minObservations`/`minNeighbors`), vote majoritaire, thread-safety. |
| `ArboreUi/ArboreUiTests/MeanValueCoordinatesTests.swift` | Coordonnées MVC pour le morphing de jardin : somme à 1, poids uniformes au centre, one-hot au sommet, mélange linéaire sur arête, stabilité numérique près d'un sommet, `signedArea`. |
| `ArboreUi/ArboreUiTests/DistortionAnalyzerTests.swift` | `DistortionAnalyzer.score(...)` (identité, équivariance d'échelle), seuils `severity` (.ok/.moderate/.severe), `cardinalZone`. |
| `ArboreUi/ArboreUiTests/GardenMorpherTests.swift` | `GardenMorpher.morph(...)` : identité, mise à l'échelle, translation, delta de sol, winding inversé, snap hors-polygone, repli sur incompatibilité de sommets, perf (`measure {}`). |
| `ArboreUi/ArboreUiTests/SurfaceClassifierTests.swift` | Classifieur heuristique non-LiDAR : mur, sol (tolérance ±10 cm), plafond, étagère vs table, rebord de fenêtre. |
| `ArboreUi/ArboreUiTests/SceneUnderstandingControllerTests.swift` | `effectiveThrottleSeconds(for:)` (scaling thermique) et `shouldIntegrateForMotion(...)` (gating au mouvement). |
| `ArboreUi/ArboreUiTests/DepthCalibrationTests.swift` | `DepthCalibration.fitAffine(...)` (récupération affine LS, round-trip métrique, robustesse outlier) et la variante RANSAC `fitAffineRANSAC(...)`. |

## Tests réseau, cache & vie privée (unitaires + intégration)

Les classes d'intégration live sont désactivées par défaut. Elles exigent
`ARBORE_RUN_LIVE_INTEGRATION_TESTS=1`, un hôte de test signé (accès Keychain),
Firebase et le backend de test. L'absence du flag produit un `XCTSkip` explicite
au lieu de créer des comptes sur la production pendant une suite locale.

| Fichier | Couvre |
|---|---|
| `ArboreUi/ArboreUiTests/NetworkManagerTests.swift` | **Unitaire** : singleton, validité `AppConfig.baseURL`/`apiKey`, `HTTPMethod`, cas `NetworkError`, décodage Codable (`UserResponse`, `BackendConsent`, `User`…). **Intégration** : crée un utilisateur Firebase de test, `POST /users`, puis `/health`, `/plants`, `/users/:uid`, `/consents`, suppression self-authz. |
| `ArboreUi/ArboreUiTests/RGPDEndpointsIntegrationTests.swift` | RGPD : `GET /users/export` (200 + structure), export sans Authorization → 401, `DELETE /users` en cascade (compteurs gardens/consents), delete sans auth → 401. |
| `ArboreUi/ArboreUiTests/ModelCacheManagerTests.swift` | **Unitaire** : `ModelCacheError`, répertoire de cache, `getCacheSize()`/`clearCache()`, `getModelURL(for:"")` → `.invalidModelURL`. **Intégration** : download + cache d'un USDZ, 2ᵉ appel via cache, modèle inexistant → 404, download non authentifié refusé. |
| `ArboreUi/ArboreUiTests/PrivacySettingsViewTests.swift` | Enregistrement local des changements de consentement (`consent_<type>_lastChanged`, historique), décodage `BackendConsent`, présence `AppConfig.privacyPolicyVersion`. Intégration : sync push/pull des consentements, anciennes routes insécures → 404, `/plants` exige le token Firebase. |
| `ArboreUi/ArboreUiTests/FirebaseConfigDiagnosticTests.swift` | Diagnostics CI : secrets `AppConfig` chargés (pas de placeholder), `FirebaseApp.configure()`, connectivité Firebase (création/suppression d'un utilisateur diagnostic), connectivité backend `/health`. |

## Tests UI (XCUITest)

| Fichier | Couvre |
|---|---|
| `ArboreUi/ArboreUiUITests/ArboreUiUITests.swift` | Smoke de démarrage (#66), **agnostique à l'état** : l'app démarre et atteint un état interactif (foreground, au moins un contrôle tappable, écran login ou onglet Accueil), plus `test_launchPerformance` ; screenshot en `tearDown`. |
| `ArboreUi/ArboreUiUITests/ArboreUiUITestsLaunchTests.swift` | Test de lancement généré par Xcode (`testLaunch()` + capture d'écran « Launch Screen »). |

> `ArboreUi/ArboreUiTests/ArboreUiTests.swift` est un placeholder utilisant le nouveau framework `Testing` ; les tests substantiels utilisent XCTest. Le projet `ArboreARkit` dispose aussi de cibles de tests (placeholders) buildées en CI avec `continue-on-error`.

## Exécution

```sh
# Toute la suite (simulateur)
cd ArboreUi && xcodebuild test \
  -workspace ArboreUi.xcworkspace -scheme ArboreUi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2' \
  -resultBundlePath build/TestResults.xcresult

# Intégrations Firebase/backend (hôte signé, environnement de test uniquement)
ARBORE_RUN_LIVE_INTEGRATION_TESTS=1 xcodebuild test \
  -workspace ArboreUi.xcworkspace -scheme ArboreUi \
  -destination 'platform=iOS,id=<UDID_APPAREIL>' \
  -only-testing:ArboreUiTests/NetworkManagerIntegrationTests \
  -only-testing:ArboreUiTests/ModelCacheManagerIntegrationTests \
  -only-testing:ArboreUiTests/PrivacySettingsIntegrationTests \
  -only-testing:ArboreUiTests/RGPDEndpointsIntegrationTests

# Une suite ciblée
cd ArboreUi && xcodebuild test \
  -workspace ArboreUi.xcworkspace -scheme ArboreUi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2' \
  -only-testing:ArboreUiTests/TSDFGridTests

# Menu interactif local
./ci-ui-local.sh
```

En CI (`.github/workflows/ci.yml`, job `ios_ui`), les secrets (`GoogleService-Info.plist`, `Secrets.xcconfig`) sont reconstruits depuis les secrets GitHub Actions, et — si `ARBORE_API_KEY_TEST` est fourni — les écritures sont routées vers la base `arbore_test` (#159). Les résultats sont parsés depuis le `.xcresult` (xcresultparser) en formats CLI/txt/html/JUnit.

## Limites connues

- Les tests d'intégration dépendent du backend de test et de Firebase ; ils sont
  **skippés** sans opt-in explicite ou si `/health` ne répond pas. Ne pas activer
  le flag contre la production dans la CI courante.
- Pas de couverture E2E déterministe pour les parcours login → jardin → plante (hors-scope actuel des tests UI).
- Caméra, RoomPlan, ARKit, localisation réelle et comportement thermique doivent
  être validés sur appareils physiques avec la
  [matrice P1](p1-appareils-physiques.md).
