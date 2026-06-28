# Stratégie de test

Cette section documente les **suites de tests** d'Arbore (front et back), ce qu'elles couvrent et comment les exécuter. Trois suites coexistent, alignées sur les trois containers logiciels :

| Suite | Cible | Outillage | Document |
|---|---|---|---|
| Tests iOS | App iOS (front) | XCTest + XCUITest | [`ios.md`](ios.md) |
| Tests Backend | API Go (back) | `go test` + testify | [`backend.md`](backend.md) |
| Tests Web | Front web Next.js | Vitest + Testing Library | [`web.md`](web.md) |

## Philosophie

La pyramide de tests d'Arbore est volontairement **épaisse à la base** sur les composants à risque algorithmique ou sécuritaire, et fine au sommet :

- **Unitaires déterministes** — toute la chaîne de reconstruction 3D / morphing AR (TSDF, Voxel, Marching Cubes, Mean Value Coordinates, classifieur de surfaces, calibration de profondeur) est testée en pur Swift, sans ARKit ni réseau. Côté backend, la sécurité (chiffrement AES-GCM, révocation Apple, ownership des routes) est couverte par des routers Gin mockés.
- **Intégration** — un sous-ensemble de tests iOS frappe le **vrai backend** et **Firebase** (création/suppression d'utilisateur de test, export RGPD, synchronisation des consentements). Ils se neutralisent proprement (`XCTSkip`) si le backend est injoignable.
- **Bout-en-bout / UI** — tests de démarrage XCUITest (l'app atteint un état interactif quel que soit l'état de session).

## Exécution rapide

| Cible | Commande |
|---|---|
| Backend (Go) | `make test-backend` ou `cd ArboreBackend && go test -race -coverprofile=coverage.out ./...` |
| Backend (lint) | `cd ArboreBackend && golangci-lint run --config=../.golangci.yml --timeout=5m ./...` |
| iOS (toute la suite) | `cd ArboreUi && xcodebuild test -workspace ArboreUi.xcworkspace -scheme ArboreUi -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2'` |
| iOS (une suite) | ajouter `-only-testing:ArboreUiTests/TSDFGridTests` (ou utiliser le menu `ci-ui-local.sh`) |
| Web (Vitest) | `cd web && npm test` (ou `npm run test:watch`) |
| Smoke CI local | `./ci-local.sh` (Go + lint + build iOS) |

## Intégration continue

Le workflow `.github/workflows/ci.yml` orchestre les tests, avec des jobs **filtrés par chemin** (un job ne tourne que si son périmètre a changé) :

| Job | Périmètre | Contenu |
|---|---|---|
| `backend` | `ArboreBackend/**`, `.golangci.yml` | `go vet`, `go test -race -coverprofile`, upload Codecov, `golangci-lint`, cross-build linux/amd64 + darwin/arm64. |
| `ios_ui` | `ArboreUi/**` | Build + `xcodebuild test` (simulateur iPhone 16 Pro / iOS 18.2), parsing `.xcresult` (CLI/txt/html/JUnit). |
| `ios_ar` | `ArboreARkit/**` | Build + tests du projet AR (`continue-on-error`). |
| `ai_generator` | `AiGenerator/**` | `black` / `flake8` / `mypy` + `pytest`. |
| `security` | PR / main | Scan Trivy (système de fichiers). |
| `build_summary` | toujours | Agrège les résultats et échoue si un job requis a échoué. |

Le workflow `.github/workflows/docs.yml` valide en plus la documentation (syntaxe Mermaid, liens internes, drift des chemins de code) — voir [`../README.md`](../README.md).

## Couverture et limites connues

- La couverture backend est **publiée sur Codecov** mais **aucun seuil bloquant** n'est imposé à ce jour.
- Les tests **web (Vitest) ne tournent pas encore en CI** — ils s'exécutent localement. `npm run test:coverage` nécessite l'installation d'un provider de couverture (`@vitest/coverage-v8`) ; aucun seuil n'est configuré.
- La version Go déclarée dans `ArboreBackend/go.mod` (`go 1.24.1`) et la variable `GO_VERSION` du CI doivent être maintenues alignées.
- Les tests d'intégration iOS dépendent du backend de test (DB `arbore_test`, routée par `ARBORE_API_KEY_TEST`) ; ils sont **skippés** automatiquement si `/health` ne répond pas.

Ces points sont des axes d'amélioration suivis côté CI, listés ici pour transparence.
