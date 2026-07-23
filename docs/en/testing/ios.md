# iOS Tests (front)

The iOS app's tests live in two targets: `ArboreUi/ArboreUiTests/` (unit + integration, XCTest) and `ArboreUi/ArboreUiUITests/` (XCUITest). They combine **deterministic pure tests** (3D reconstruction / morphing math, with no ARKit or network) and **integration tests** that hit the real backend and Firebase.

## Unit tests — AR pipeline / 3D reconstruction

These files only instantiate simple Swift types (`@testable import ArboreUi`, `XCTest`, `simd`): fast and deterministic.

| File | Covers |
|---|---|
| `ArboreUi/ArboreUiTests/MarchingCubesTests.swift` | `MarchingCubes.extractMesh(...)`: empty grid, all-positive/all-negative corners, one negative corner (3 vertices), SDF plane, `minWeight` filtering. |
| `ArboreUi/ArboreUiTests/TSDFGridTests.swift` | Weighted-average SDF integration, truncation, outlier resistance, `maxWeight` cap, category voting, weighted carving, color, `snapshot()`/`clear()`, and **thread safety** (`test_concurrentIntegrate_isThreadSafe`). |
| `ArboreUi/ArboreUiTests/VoxelGridTests.swift` | Insert/lookup, voxel quantization, `snapshot()` independence, FIFO eviction + tombstones, noise filters (`minObservations`/`minNeighbors`), majority voting, thread safety. |
| `ArboreUi/ArboreUiTests/MeanValueCoordinatesTests.swift` | MVC coordinates for garden morphing: sums to 1, uniform weights at center, one-hot at a vertex, linear blend along an edge, numerical stability near a vertex, `signedArea`. |
| `ArboreUi/ArboreUiTests/DistortionAnalyzerTests.swift` | `DistortionAnalyzer.score(...)` (identity, scale equivariance), `severity` thresholds (.ok/.moderate/.severe), `cardinalZone`. |
| `ArboreUi/ArboreUiTests/GardenMorpherTests.swift` | `GardenMorpher.morph(...)`: identity, scaling, translation, ground delta, inverted winding, out-of-polygon snap, fallback on vertex mismatch, perf (`measure {}`). |
| `ArboreUi/ArboreUiTests/SurfaceClassifierTests.swift` | Non-LiDAR heuristic classifier: wall, floor (±10 cm tolerance), ceiling, shelf vs table, windowsill. |
| `ArboreUi/ArboreUiTests/SceneUnderstandingControllerTests.swift` | `effectiveThrottleSeconds(for:)` (thermal scaling) and `shouldIntegrateForMotion(...)` (motion gating). |
| `ArboreUi/ArboreUiTests/DepthCalibrationTests.swift` | `DepthCalibration.fitAffine(...)` (LS affine recovery, metric round-trip, outlier robustness) and the RANSAC variant `fitAffineRANSAC(...)`. |

## Network, cache & privacy tests (unit + integration)

Live integration classes are disabled by default. They require
`ARBORE_RUN_LIVE_INTEGRATION_TESTS=1`, a signed test host (Keychain access),
Firebase, and the test backend. Without the flag, the tests emit an explicit
`XCTSkip` instead of creating accounts against production during a local run.

| File | Covers |
|---|---|
| `ArboreUi/ArboreUiTests/NetworkManagerTests.swift` | **Unit**: singleton, `AppConfig.baseURL`/`apiKey` validity, `HTTPMethod`, `NetworkError` cases, Codable decoding (`UserResponse`, `BackendConsent`, `User`…). **Integration**: creates a test Firebase user, `POST /users`, then `/health`, `/plants`, `/users/:uid`, `/consents`, self-authz deletion. |
| `ArboreUi/ArboreUiTests/RGPDEndpointsIntegrationTests.swift` | GDPR: `GET /users/export` (200 + structure), export without Authorization → 401, cascading `DELETE /users` (gardens/consents counters), delete without auth → 401. |
| `ArboreUi/ArboreUiTests/ModelCacheManagerTests.swift` | **Unit**: `ModelCacheError`, cache directory, `getCacheSize()`/`clearCache()`, `getModelURL(for:"")` → `.invalidModelURL`. **Integration**: download + cache of a USDZ, 2nd call via cache, non-existent model → 404, unauthenticated download rejected. |
| `ArboreUi/ArboreUiTests/PrivacySettingsViewTests.swift` | Local recording of consent changes (`consent_<type>_lastChanged`, history), `BackendConsent` decoding, presence of `AppConfig.privacyPolicyVersion`. Integration: push/pull consent sync, old insecure routes → 404, `/plants` requires the Firebase token. |
| `ArboreUi/ArboreUiTests/FirebaseConfigDiagnosticTests.swift` | CI diagnostics: `AppConfig` secrets loaded (no placeholder), `FirebaseApp.configure()`, Firebase connectivity (creation/deletion of a diagnostic user), backend `/health` connectivity. |

## UI tests (XCUITest)

| File | Covers |
|---|---|
| `ArboreUi/ArboreUiUITests/ArboreUiUITests.swift` | Startup smoke (#66), **state-agnostic**: the app launches and reaches an interactive state (foreground, at least one tappable control, login screen or Home tab), plus `test_launchPerformance`; screenshot in `tearDown`. |
| `ArboreUi/ArboreUiUITests/ArboreUiUITestsLaunchTests.swift` | Xcode-generated launch test (`testLaunch()` + "Launch Screen" screenshot). |

> `ArboreUi/ArboreUiTests/ArboreUiTests.swift` is a placeholder using the new `Testing` framework; the substantive tests use XCTest. The `ArboreARkit` project also has test targets (placeholders) built in CI with `continue-on-error`.

## Running

```sh
# Whole suite (simulator)
cd ArboreUi && xcodebuild test \
  -workspace ArboreUi.xcworkspace -scheme ArboreUi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2' \
  -resultBundlePath build/TestResults.xcresult

# Firebase/backend integrations (signed host, test environment only)
ARBORE_RUN_LIVE_INTEGRATION_TESTS=1 xcodebuild test \
  -workspace ArboreUi.xcworkspace -scheme ArboreUi \
  -destination 'platform=iOS,id=<DEVICE_UDID>' \
  -only-testing:ArboreUiTests/NetworkManagerIntegrationTests \
  -only-testing:ArboreUiTests/ModelCacheManagerIntegrationTests \
  -only-testing:ArboreUiTests/PrivacySettingsIntegrationTests \
  -only-testing:ArboreUiTests/RGPDEndpointsIntegrationTests

# A targeted suite
cd ArboreUi && xcodebuild test \
  -workspace ArboreUi.xcworkspace -scheme ArboreUi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2' \
  -only-testing:ArboreUiTests/TSDFGridTests

# Local interactive menu
./ci-ui-local.sh
```

In CI (`.github/workflows/ci.yml`, `ios_ui` job), the secrets (`GoogleService-Info.plist`, `Secrets.xcconfig`) are reconstructed from GitHub Actions secrets, and — if `ARBORE_API_KEY_TEST` is provided — writes are routed to the `arbore_test` database (#159). Results are parsed from the `.xcresult` (xcresultparser) into CLI/txt/html/JUnit formats.

## Known limitations

- Integration tests depend on the test backend and Firebase; they are **skipped**
  without explicit opt-in or when `/health` does not respond. Do not enable the
  flag against production in the current CI.
- No deterministic E2E coverage for the login → garden → plant flows (currently out of scope for the UI tests).
- Camera, RoomPlan, real-world location, ARKit, and thermal behaviour must be
  validated on physical devices with the
  [P1 device matrix](p1-physical-devices.md).
