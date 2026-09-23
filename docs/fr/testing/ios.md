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
| `ArboreUi/ArboreUiTests/PerimeterTracingTests.swift` | Tracé du périmètre du jardin : quatre points posés en diagonale deviennent quand même une frontière valide (réordonnancement automatique), un point trop proche d'un existant est rejeté, `undo` retire bien le dernier point **posé** et non le dernier de l'ordre calculé. |
| `ArboreUi/ArboreUiTests/PlacementReliabilityTests.swift` | Fiabilité du placement : la géométrie existante est plaçable sans délai de stabilité, un plan estimé exige une courte stabilisation avant validation, un tracking dégradé ou une surface incompatible bloquent le placement. |
| `ArboreUi/ArboreUiTests/PlantPlacementCompatibilityTests.swift` | Modes de placement d'une plante : seuls sol/mur/plafond existent, les plantes retombantes nommées au catalogue autorisent le plafond, les grimpantes et retombantes le mur, une plante de sol ordinaire ni l'un ni l'autre — et les drapeaux structurés suffisent à ouvrir les modes spéciaux. |

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
| `ArboreUi/ArboreUiTests/AIProcessingPreferenceTests.swift` | Réglage « Traitement IA » (#549) : sans valeur enregistrée on suit le défaut du projet, une valeur explicite est respectée, la clé est bien celle de l'écran Confidentialité, et — point central — **le réglage n'est pas consigné dans le registre des consentements** (c'est une préférence de fonctionnalité, pas un consentement RGPD) alors que les vrais consentements, eux, y restent consignés. |
| `ArboreUi/ArboreUiTests/PlantHealthScannerTests.swift` | Logique pure du scan de santé : descriptions d'erreurs non vides et icônes distinctes par cas, `llmError` embarquant son message, validateur de luminosité (image sombre rejetée / image claire acceptée), colorimétrie (vert = sain, brun ≠ vert), et décodage du contrat `/diagnose` (forme normalisée, champs optionnels tolérés, **maladie sans nom = échec de décodage**). |
| `ArboreUi/ArboreUiTests/LocalDataOwnershipTests.swift` | Propriété des données locales : un identifiant inconnu n'a pas de propriétaire, `forget` est idempotent, rien n'est visible sans session, une revendication sans session n'écrit rien, la déconnexion efface l'état de consentement **et rien d'autre** — les fichiers de scène restent sur disque. |
| `ArboreUi/ArboreUiTests/SentryAnonymisationTests.swift` | Anonymisation Sentry : sans consentement aucun identifiant ne subsiste, l'adresse IP est **remplacée et non effacée** (constante entre deux événements), l'identifiant d'installation est retiré, l'UUID du binaire est conservé ; même avec consentement ni e-mail ni nom ne partent ; les traces réseau ne passent qu'avec consentement ; le SDK reste éteint pendant les tests. |
| `ArboreUi/ArboreUiTests/GuestAccessTests.swift` | Parcours invité : reconnaissance des cas `accountRequired` / `emailNotVerified`, un compte banni n'est pas confondu avec un invité, les corps malformés retombent proprement **sans divulguer d'interne**, les codes correspondent au contrat backend, et les chaînes invité sont traduites. |
| `ArboreUi/ArboreUiTests/PlantThumbnailDecodingTests.swift` | Cache de vignettes (`PlantThumbnailCache`) : une image préparée expose ses pixels sans attendre le rendu, réduction aux besoins de la carte sans agrandir une petite vignette, des octets invalides rendent `nil` plutôt que de planter, une seconde lecture rend la même instance, et une réécriture remplace l'image en mémoire. |
| `ArboreUi/ArboreUiTests/PlantCatalogTraitsCacheTests.swift` | Mémoïsation des traits du catalogue : relire les mêmes plantes est un ordre de grandeur plus rapide, le résultat mémoïsé est identique au résultat calculé, et deux plantes de même `id` mais de drapeaux différents ne partagent pas leurs traits. |
| `ArboreUi/ArboreUiTests/GardenMapPerformanceTests.swift` | Rendu de la carte du jardin : un symbole n'est rastérisé qu'une fois, les deux tailles sont des entrées distinctes, la variante est stable pour une même plante, le nom prime sur l'index pour les cactus, la reconnaissance ignore les accents, et le cache est borné. |

## Tests catalogue, données botaniques & localisation

Ces fichiers protègent le **contrat de données** du catalogue : ce qui est affiché,
ce qui est filtré, et ce qui est traduit. Leur règle commune est qu'une donnée
**absente** ne doit jamais être devinée — ni transformée en valeur par défaut, ni
faire disparaître une plante.

| Fichier | Couvre |
|---|---|
| `ArboreUi/ArboreUiTests/PlantCatalogContextTests.swift` | Recommandation de plantes selon le contexte du jardin : un jardin ombragé recommande une plante tolérante à l'ombre, **une plante toxique n'est jamais recommandée** quand la sûreté animale est demandée, les données inconnues restent marquées « à vérifier », préférences en OU dans un groupe et ET entre groupes, conflit de température = exclusion dure avant classement, jardin côtier récompensant la tolérance au sel, exigence de pot excluant une plante de balcon. |
| `ArboreUi/ArboreUiTests/PlantCareDifficultyTests.swift` | Difficulté d'entretien et toxicité : une donnée absente donne **« inconnu »** et non un niveau par défaut, la difficulté explicite prime sur les drapeaux, les trois niveaux sont reconnus dans les quatre langues, « exigeant » est testé avant « facile », le repli ne produit jamais « intermédiaire », une toxicité inconnue est exclue d'un filtre de sûreté, et le profil botanique prime sur les drapeaux. |
| `ArboreUi/ArboreUiTests/PlantTranslationDecodingTests.swift` | Décodage des traductions : une langue incomplète **ne fait pas disparaître la plante**, le repli anglais reste disponible après rejet, une traduction au texte vide est conservée pour ses données structurées, les sections riches survivent au décodage par langue, un bloc mal formé n'emporte pas la fiche. |
| `ArboreUi/ArboreUiTests/LocalizationCoverageTests.swift` | Garde-fou de localisation (#578) : chaque clé critique — dont `AI_DISCLAIMER` et `AI_DISCLAIMER_SCAN` — est définie dans les **quatre** langues (fr/en/es/de), et les traductions ne sont pas de simples copies du français. |
| `ArboreUi/ArboreUiTests/PlantThumbnailRenderingTests.swift` | Rendu des vignettes : l'URL distante embarque la version de design pour contourner le cache CDN, le cadrage recule la caméra pour une plante large et tient compte de la profondeur quand elle est inclinée, et le détecteur hérité rejette une vignette sans marqueur de design courant. |
| `ArboreUi/ArboreUiTests/GardenLocationDTOTests.swift` | DTO de localisation du jardin : la position de l'appareil est **arrondie avant encodage**, une ville saisie manuellement ne contient aucune coordonnée, round-trip du profil de site (métadonnées et zones), une estimation d'ensoleillement n'est pas fabriquée à partir d'une lumière instantanée, et un profil manuel distant reste prioritaire pendant la réparation. |
| `ArboreUi/ArboreUiTests/ArboreNotificationPlannerTests.swift` | Planification des rappels : format des identifiants, la date n'est pas décalée sans signal, chaud + sec avance de deux jours, la pluie en extérieur recule d'un jour, et les rappels (arrosage, entretien, fin de projet) portent le bon identifiant, la bonne catégorie et un corps de repli. |

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
