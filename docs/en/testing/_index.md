# Testing strategy

This section documents Arbore's **test suites** (front and back), what they cover, and how to run them. Three suites coexist, aligned with the three software containers:

| Suite | Target | Tooling | Document |
|---|---|---|---|
| iOS tests | iOS app (front) | XCTest + XCUITest | [`ios.md`](ios.md) |
| Backend tests | Go API (back) | `go test` + testify | [`backend.md`](backend.md) |
| Web tests | Next.js web front | Vitest + Testing Library | [`web.md`](web.md) |

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
| iOS (full suite) | `cd ArboreUi && xcodebuild test -workspace ArboreUi.xcworkspace -scheme ArboreUi -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2'` |
| iOS (single suite) | add `-only-testing:ArboreUiTests/TSDFGridTests` (or use the `ci-ui-local.sh` menu) |
| Web (Vitest) | `cd web && npm test` (or `npm run test:watch`) |
| Local CI smoke | `./ci-local.sh` (Go + lint + iOS build) |

## Continuous integration

The `.github/workflows/ci.yml` workflow orchestrates the tests, with **path-filtered** jobs (a job runs only if its scope changed):

| Job | Scope | Content |
|---|---|---|
| `backend` | `ArboreBackend/**`, `.golangci.yml` | `go vet`, `go test -race -coverprofile`, Codecov upload, `golangci-lint`, cross-build linux/amd64 + darwin/arm64. |
| `ios_ui` | `ArboreUi/**` | Build + `xcodebuild test` (iPhone 16 Pro / iOS 18.2 simulator), `.xcresult` parsing (CLI/txt/html/JUnit). |
| `ios_ar` | `ArboreARkit/**` | Build + AR project tests (`continue-on-error`). |
| `ai_generator` | `AiGenerator/**` | `black` / `flake8` / `mypy` + `pytest`. |
| `security` | PR / main | Trivy scan (filesystem). |
| `build_summary` | always | Aggregates results and fails if a required job failed. |

The `.github/workflows/docs.yml` workflow additionally validates the documentation (Mermaid syntax, internal links, code-path drift) — see [`../README.md`](../README.md).

## Coverage and known limitations

- Backend coverage is **published to Codecov** but **no blocking threshold** is enforced to date.
- The **web tests (Vitest) do not run in CI yet** — they run locally. `npm run test:coverage` requires installing a coverage provider (`@vitest/coverage-v8`); no threshold is configured.
- The Go version declared in `ArboreBackend/go.mod` (`go 1.24.1`) and the CI's `GO_VERSION` variable must be kept aligned.
- The iOS integration tests depend on the test backend (`arbore_test` DB, routed by `ARBORE_API_KEY_TEST`); they are **skipped** automatically if `/health` does not respond.

These points are improvement areas tracked on the CI side, listed here for transparency.
