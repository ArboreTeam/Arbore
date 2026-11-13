# Stratégie de test

Cette section documente les **suites de tests** d'Arbore (front et back), ce qu'elles couvrent et comment les exécuter. Trois suites coexistent, alignées sur les trois containers logiciels :

| Suite | Cible | Outillage | Document |
|---|---|---|---|
| Tests iOS | App iOS (front) | XCTest + XCUITest | [`ios.md`](ios.md) |
| Tests Backend | API Go (back) | `go test` + testify | [`backend.md`](backend.md) |
| Tests Web | Front web Next.js | Vitest + Testing Library | [`web.md`](web.md) |
| Tests Python | Scripts de maintenance, ouvrier et **rendu** des vignettes | `unittest` | voir ci-dessous |

> **La suite Python n'était pas listée ici** jusqu'au 2026-11-03. Elle compte
> **89 tests** dans `scripts/test_*.py`. Elle couvre l'ouvrier de vignettes
> (type d'exception de sa boucle, routes visées, agent annoncé, relevé des
> mesures) et, depuis #725, le **rendu** lui-même : `rendre.py` est chargé avec
> `bpy` et `mathutils` simulés, ce qui permet d'éprouver sans Blender le
> cadrage, les conversions de couleur, le repère Y-up → Z-up et la
> normalisation d'échelle de #718.
>
> Les constantes y sont traitées comme du **contrat** : un ciel trop clair ou
> un marqueur décalé d'un octet font refuser la vignette par l'app, en
> silence. C'est la catégorie de défaut qui a coûté 123 vignettes le
> 30 octobre.
>
> ```sh
> python3 -I -m unittest discover -s scripts -p 'test_*.py'
> ```
>
> Elle a un job CI depuis le 2026-11-03 : **`🐍 Outillage (Python)`**, filtré
> sur `scripts/**` et `vignettes/**`. Jusque-là aucun workflow ne mentionnait
> `unittest` — des tests qui passaient en quelques millisecondes, et que
> personne n'aurait vu casser.

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
| iOS (toute la suite) | `cd ArboreUi && xcodebuild test -workspace ArboreUi.xcworkspace -scheme ArboreUi -destination 'platform=iOS Simulator,name=iPhone 16 Pro'` |
| iOS (une suite) | ajouter `-only-testing:ArboreUiTests/TSDFGridTests` (ou utiliser le menu `ci-ui-local.sh`) |
| Web (Vitest) | `cd web && npm test` (ou `npm run test:watch`) |
| Web (couverture) | `cd web && npm run test:coverage` |
| Python (outillage) | `python3 -I -m unittest discover -s scripts -p 'test_*.py'` |
| iOS (couverture) | la couverture est **collectée par le schéma** ; la lire avec `xcrun xccov view --report --only-targets <bundle>.xcresult` |
| Smoke CI local | `./ci-local.sh` (Go + lint + build iOS) |

## Intégration continue

Le workflow `.github/workflows/ci.yml` orchestre les tests, avec des jobs **filtrés par chemin** (un job ne tourne que si son périmètre a changé) :

| Job | Périmètre | Contenu |
|---|---|---|
| `backend` | `ArboreBackend/**`, `.golangci.yml` | `go vet`, `go test -race -coverprofile`, upload Codecov, `golangci-lint`, **`govulncheck` (bloquant)**, cross-build linux/amd64 + darwin/arm64. |
| `ios_ui` | `ArboreUi/**` | Build + `xcodebuild test` (simulateur iPhone 16 Pro / iOS 18.2), **couverture** (`-enableCodeCoverage`, résumé + 20 fichiers les moins couverts), parsing `.xcresult` (CLI/txt/html/JUnit). |
| `ios_ar` | `ArboreARkit/**` | Build + tests du projet AR (`continue-on-error`). |
| `🌱 Web (Next.js)` | `web/**` | `typecheck`, `lint`, `npm run test:coverage`, résumé de couverture, `npm run build`. |
| `🐍 Outillage (Python)` | `scripts/**`, `vignettes/**` | `python3 -m unittest discover -s scripts`. Aucune dépendance à installer. |
| `security` | PR / main | Trivy (système de fichiers), en deux passes : un **rapport SARIF complet** vers l'onglet Security (non bloquant, pour la visibilité) puis un **gate bloquant en CRITICAL** (`--ignore-unfixed`). |
| `build_summary` | toujours | Agrège les résultats et échoue si un job requis a échoué. |

Le workflow `.github/workflows/docs.yml` valide en plus la documentation (syntaxe Mermaid, liens internes, drift des chemins de code) — voir [`../README.md`](../README.md).

## Couverture : les quatre chiffres

Mesurés le **2026-11-03** sur `dev` (#725). Deux d'entre eux n'existaient
jusque-là **nulle part** : ni le schéma iOS ni la CI ne demandaient de
couverture, et le provider web n'était pas installé.

| Zone | Couverture | Tests | Où elle est mesurée |
|---|---|---|---|
| **iOS** (`ArboreUi.app`) | **6,94 %** — 6 164 / 88 850 lignes | 335 passés, 26 sautés | `ios_ui`, résumé du job |
| **Backend Go** | **52,7 %** (principal 51,1 %, middleware 63,9 %) | 355 | `backend`, puis Codecov |
| **Web** | **32,5 %** — 1 237 / 3 811 instructions | 280 | `🌱 Web`, résumé du job |
| **Python** (`scripts/`) | non mesurée | 89 | `🐍 Outillage`, exécution seule |

**Le chiffre du web se lit avec une précaution.** Sans `coverage.all`, v8 ne
compte que les fichiers que les tests **chargent** : les 140 fichiers
qu'aucun test n'importe sortent du dénominateur, et le rapport annonce alors
**91,6 %**. `vitest.config.mts` pose donc `all: true` — un chiffre faux dans
ce sens-là est pire que pas de chiffre, il dit que le travail est fait.

### Le cliquet

Les trois zones mesurées portent un **plancher**, et c'est un cliquet : la CI
échoue si la couverture **descend**, jamais parce qu'elle n'atteint pas un
chiffre choisi d'avance.

Le sens compte. Un objectif du type « 80 % » serait arbitraire et
invérifiable — personne ne peut dire pourquoi 80 plutôt que 70 —, et on
l'atteint très bien en testant ce qui est facile. « Ne pas reculer » se
justifie tout seul, se mesure exactement, et n'oblige à aucun test de
complaisance.

Les planchers vivent **au même endroit**, `.github/couverture-planchers.json`,
qui fait foi — ce tableau en est une copie de lecture, et c'est ce fichier
qu'il faut croire :

| zone | plancher | mesure du 2026-11-03 |
|---|---|---|
| Go | 52,7 % | 53,4 % (2026-11-04) |
| Web | 32,0 % | 32,5 % |
| iOS | 6,5 % | 6,9 % |

Ils sont légèrement **sous** les mesures, pour absorber le bruit : un fichier
supprimé ou une branche morte retirée font bouger un dénominateur sans que
personne n'ait rien cassé.

**Quand une PR fait monter la couverture, elle relève le plancher.** C'est ce
geste qui fait du cliquet un cliquet ; sans lui le terrain gagné se reperd en
silence. Les jobs affichent la marge à chaque exécution et suggèrent de
relever dès qu'elle dépasse un point, justement pour qu'on y pense.

La suite **Python** n'a pas de plancher : ses 89 tests s'exécutent, mais aucun
outil ne mesure ce qu'ils couvrent. Un plancher sur un chiffre qui n'existe
pas n'aurait aucun sens.

Côté web, seules les **instructions** sont gardées. Branches et fonctions sont
affichées mais pas verrouillées : elles bougent pour des raisons qui ne disent
rien de l'effort de test — un `if` ajouté dans un fichier déjà couvert fait
baisser le taux de branches sans qu'aucun test n'ait disparu.

### Ce que la répartition dit

Elle n'est pas « il manque des tests partout ». Côté iOS, les
**mathématiques** de l'AR sont testées — TSDF, voxels, marching cubes,
coordonnées de valeur moyenne, calibration — c'est la partie difficile et elle
l'est bien. Ce qui ne l'est pas, c'est la **vue** : `ARGarden` est à 0 % sur
14 749 lignes, dont 10 513 pour le seul `GardenARPlacementView.swift`.

Côté web, `lib/generator` est à 91,7 % et les pages applicatives à 0 % : la
couverture suit où le travail est allé.

Les manques qui comptent, avec l'ordre proposé, sont dans #725.

## Autres limites connues
- La version Go déclarée dans `ArboreBackend/go.mod` (**`go 1.26.10`**) et la variable `GO_VERSION` du CI (**`1.27.4`**) doivent rester compatibles : le mécanisme de toolchain télécharge la version déclarée si le runner en porte une plus ancienne, sans cache, et la version affichée n'est alors pas celle utilisée (audit #338 constat 6). Un `GO_VERSION` **plus récent** que `go.mod`, le cas actuel, ne déclenche pas ce téléchargement. Cette page a annoncé `go 1.25.12` et `testing/backend.md` `go 1.25.14`, aucune des deux n'étant la bonne : un numéro recopié en prose se périme en silence.
- **Seuil des scans de sécurité** : le gate Trivy bloque en **CRITICAL** seulement. Il existe aujourd'hui des vulnérabilités **HIGH** dans les `package-lock.json` (`brace-expansion`, `sharp`/libvips) — bloquer en HIGH casserait la CI. Dependabot surveille désormais npm (`web/`, `Plant3DGenerator/`) et Docker en plus de Go, Python et les actions ; le seuil doit être resserré sur HIGH une fois ces PR passées.
- Les tests d'intégration iOS dépendent du backend de test (DB `arbore_test`, routée par `ARBORE_API_KEY_TEST`) ; ils sont **skippés** automatiquement si `/health` ne répond pas.

Ces points sont des axes d'amélioration suivis côté CI, listés ici pour transparence.
