# Testing strategy

This section documents Arbore's **test suites** (front and back), what they cover, and how to run them. Three suites coexist, aligned with the three software containers:

| Suite | Target | Tooling | Document |
|---|---|---|---|
| iOS tests | iOS app (front) | XCTest + XCUITest | [`ios.md`](ios.md) |
| Backend tests | Go API (back) | `go test` + testify | [`backend.md`](backend.md) |
| Web tests | Next.js web front | Vitest + Testing Library | [`web.md`](web.md) |
| Python tests | Maintenance scripts, thumbnail worker and **renderer** | `unittest` | see below |

> **The Python suite was not listed here** until 2026-11-03. It holds **89
> tests** in `scripts/test_*.py`. It covers the thumbnail worker (the exception
> type of its loop, the routes it targets, the agent it announces, the relaying
> of phase measurements) and, since #725, the **renderer** itself: `rendre.py`
> is loaded with `bpy` and `mathutils` stubbed, which makes it possible to
> exercise the framing, the colour conversions, the Y-up → Z-up frame change
> and the #718 scale normalisation without Blender.
>
> Its constants are treated as a **contract**: a sky one shade too light, or a
> marker off by one byte, makes the app refuse the thumbnail in silence. That
> is the class of defect that cost 123 thumbnails on 30 October.
>
> ```sh
> python3 -I -m unittest discover -s scripts -p 'test_*.py'
> ```
>
> It has had a CI job since 2026-11-03: **`🐍 Outillage (Python)`**, filtered
> on `scripts/**` and `vignettes/**`. Until then no workflow mentioned
> `unittest` — tests passing in milliseconds that nobody would have seen
> break.

## Philosophy

Arbore's test pyramid is deliberately **thick at the base** for components carrying algorithmic or security risk, and thin at the top:

- **Deterministic unit tests** — the entire 3D reconstruction / AR morphing chain (TSDF, Voxel, Marching Cubes, Mean Value Coordinates, surface classifier, depth calibration) is tested in pure Swift, with no ARKit and no network. On the backend side, security (AES-GCM encryption, Apple revocation, route ownership) is covered with mocked Gin routers.
- **Integration** — a subset of iOS tests hits the **real backend** and **Firebase** (test user creation/deletion, GDPR export, consent synchronization). They bow out cleanly (`XCTSkip`) if the backend is unreachable.
- **End-to-end / UI** — XCUITest launch tests (the app reaches an interactive state regardless of session state).

## Quick run

| Target | Command |
|---|---|
| Backend (Go) | `make test-backend` or `cd ArboreBackend && go test -race -coverprofile=coverage.out ./...` |
| Backend (lint) | `cd ArboreBackend && golangci-lint run --config=../.golangci.yml --timeout=5m ./...` |
| iOS (full suite) | `cd ArboreUi && xcodebuild test -workspace ArboreUi.xcworkspace -scheme ArboreUi -destination 'platform=iOS Simulator,name=iPhone 16 Pro'` |
| iOS (single suite) | add `-only-testing:ArboreUiTests/TSDFGridTests` (or use the `ci-ui-local.sh` menu) |
| Web (Vitest) | `cd web && npm test` (or `npm run test:watch`) |
| Web (coverage) | `cd web && npm run test:coverage` |
| Python (tooling) | `python3 -I -m unittest discover -s scripts -p 'test_*.py'` |
| iOS (coverage) | coverage is **collected by the scheme**; read it with `xcrun xccov view --report --only-targets <bundle>.xcresult` |
| Local CI smoke | `./ci-local.sh` (Go + lint + iOS build) |

## Continuous integration

The `.github/workflows/ci.yml` workflow orchestrates the tests, with **path-filtered** jobs (a job runs only if its scope changed):

| Job | Scope | Content |
|---|---|---|
| `backend` | `ArboreBackend/**`, `.golangci.yml` | `go vet`, `go test -race -coverprofile`, Codecov upload, `golangci-lint`, **`govulncheck` (blocking)**, cross-build linux/amd64 + darwin/arm64. |
| `ios_ui` | `ArboreUi/**` | Build + `xcodebuild test` (iPhone 16 Pro / iOS 18.2 simulator), **coverage** (`-enableCodeCoverage`, summary + the 20 least covered files), `.xcresult` parsing (CLI/txt/html/JUnit). |
| `ios_ar` | `ArboreARkit/**` | Build + AR project tests (`continue-on-error`). |
| `🌱 Web (Next.js)` | `web/**` | `typecheck`, `lint`, `npm run test:coverage`, coverage summary, `npm run build`. |
| `🐍 Outillage (Python)` | `scripts/**`, `vignettes/**` | `python3 -m unittest discover -s scripts`. No dependency to install. |
| `security` | PR / main | Trivy (filesystem), in two passes: a **full SARIF report** to the Security tab (non-blocking, for visibility) then a **blocking gate on CRITICAL** (`--ignore-unfixed`). |
| `build_summary` | always | Aggregates results and fails if a required job failed. |

The `.github/workflows/docs.yml` workflow additionally validates the documentation (Mermaid syntax, internal links, code-path drift) — see [`../README.md`](../README.md).

## Coverage: the four numbers

Measured on **2026-11-03** on `dev` (#725). Two of them existed **nowhere**
until then: neither the iOS scheme nor CI asked for coverage, and the web
provider was not installed.

| Area | Coverage | Tests | Where it is measured |
|---|---|---|---|
| **iOS** (`ArboreUi.app`) | **6.94%** — 6,164 / 88,850 lines | 335 passed, 26 skipped | `ios_ui`, job summary |
| **Go backend** | **52.7%** (main 51.1%, middleware 63.9%) | 355 | `backend`, then Codecov |
| **Web** | **32.5%** — 1,237 / 3,811 statements | 280 | `🌱 Web`, job summary |
| **Python** (`scripts/`) | not measured | 89 | `🐍 Outillage`, execution only |

**The web number comes with a caveat.** Without `coverage.all`, v8 only counts
the files the tests **load**: the 140 files no test imports drop out of the
denominator, and the report then claims **91.6%**. `vitest.config.mts`
therefore sets `all: true` — a number wrong in that direction is worse than no
number, because it says the work is done.

### The ratchet

The three measured areas carry a **floor**, and it is a ratchet: CI fails when
coverage **drops**, never because it falls short of a number picked in
advance.

The direction matters. A target like "80%" would be arbitrary and
unverifiable — nobody can say why 80 rather than 70 — and it is easily reached
by testing whatever is easy. "Do not go backwards" justifies itself, measures
exactly, and forces no token tests.

The floors live in **one place**, `.github/couverture-planchers.json`, which is
authoritative — this table is a reading copy, and that file is the one to
believe. One place also means raising them is a single edit:

| area | floor | measured 2026-11-03 |
|---|---|---|
| Go | 52.7% | 53.4% (2026-11-04) |
| Web | 32.0% | 32.5% |
| iOS | 6.5% | 6.9% |

They sit slightly **below** the measurements to absorb noise: a deleted file
or a dead branch removed moves a denominator without anyone having broken
anything.

**When a PR raises coverage, it raises the floor.** That gesture is what makes
the ratchet a ratchet; without it the ground gained is lost again in silence.
The jobs print the margin on every run and suggest raising the floor as soon
as it exceeds one point, precisely so it is not forgotten.

The **Python** suite has no floor: its 89 tests run, but no tool measures what
they cover. A floor on a number that does not exist would mean nothing.

On the web side, only **statements** are guarded. Branches and functions are
displayed but not locked: they move for reasons that say nothing about testing
effort — an `if` added to an already-covered file lowers the branch rate
without a single test having disappeared.

### What the distribution says

It is not "tests are missing everywhere". On iOS the AR **mathematics** are
tested — TSDF, voxels, marching cubes, mean value coordinates, calibration —
that is the hard part and it is done well. What is not tested is the **view**:
`ARGarden` sits at 0% over 14,749 lines, 10,513 of them in
`GardenARPlacementView.swift` alone.

On the web, `lib/generator` is at 91.7% and the application pages at 0%:
coverage follows where the work went.

The gaps that matter, with a proposed order, are in #725.

## Other known limitations

- Backend coverage is **published to Codecov** but **no blocking threshold** is enforced to date.
- The Go version declared in `ArboreBackend/go.mod` (**`go 1.26.10`**) and the CI's `GO_VERSION` variable (**`1.27.4`**) must stay compatible: the toolchain mechanism downloads the declared version when the runner carries an older one, without caching, and the displayed version is then not the one used (audit #338 finding 6). A `GO_VERSION` **newer** than `go.mod`, the current case, does not trigger that download. This page claimed `go 1.25.12` and `testing/backend.md` `go 1.25.14`, neither being right: a number copied into prose goes stale silently.
- **Security scan threshold**: the Trivy gate blocks on **CRITICAL** only. **HIGH** vulnerabilities currently exist in the `package-lock.json` files (`brace-expansion`, `sharp`/libvips) — blocking on HIGH would break CI. Dependabot now watches npm (`web/`, `Plant3DGenerator/`) and Docker in addition to Go, Python and actions; the threshold should be tightened to HIGH once those PRs have landed.
- The iOS integration tests depend on the test backend (`arbore_test` DB, routed by `ARBORE_API_KEY_TEST`); they are **skipped** automatically if `/health` does not respond.

These points are improvement areas tracked on the CI side, listed here for transparency.
