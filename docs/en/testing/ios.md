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
| `ArboreUi/ArboreUiTests/PerimeterTracingTests.swift` | Garden perimeter tracing: four points placed in diagonal order still become a valid boundary (automatic reordering), a point too close to an existing one is rejected, `undo` removes the most recently **placed** point rather than the last one in the computed order. |
| `ArboreUi/ArboreUiTests/PlacementReliabilityTests.swift` | Placement reliability: existing geometry is placeable with no stability delay, an estimated plane needs a short stabilisation before commit, limited tracking or an incompatible surface blocks placement. |
| `ArboreUi/ArboreUiTests/PlantPlacementCompatibilityTests.swift` | A plant's placement modes: only floor/wall/ceiling exist, trailing plants named in the catalogue allow ceiling, climbing and trailing plants allow wall, an ordinary floor plant allows neither — and structured flags alone are enough to unlock the special modes. |

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
| `ArboreUi/ArboreUiTests/AIProcessingPreferenceTests.swift` | The “AI processing” setting (#549): with no stored value the project default applies, an explicit value is honoured, the key is the one used by the Privacy screen, and — the central point — **the setting is not recorded in the consent registry** (it is a feature preference, not GDPR consent) whereas real consents still are. |
| `ArboreUi/ArboreUiTests/PlantHealthScannerTests.swift` | Pure health-scan logic: non-empty error descriptions and distinct icons per case, `llmError` carrying its message, the brightness validator (dark image rejected / bright image accepted), colorimetry (green = healthy, brown ≠ green), and `/diagnose` contract decoding (normalised shape, optional fields tolerated, **a disease with no name fails decoding**). |
| `ArboreUi/ArboreUiTests/LocalDataOwnershipTests.swift` | Local data ownership: an unknown identifier has no owner, `forget` is idempotent, nothing is visible without a session, a claim without a session writes nothing, logout clears consent state **and nothing else** — scene files stay on disk. |
| `ArboreUi/ArboreUiTests/SentryAnonymisationTests.swift` | Sentry anonymisation: without consent no identifier survives, the IP address is **replaced rather than erased** (constant across two events), the install identifier is stripped, the binary UUID is kept; even with consent neither email nor name leaves; network breadcrumbs only pass with consent; the SDK stays off during tests. |
| `ArboreUi/ArboreUiTests/GuestAccessTests.swift` | Guest flow: `accountRequired` / `emailNotVerified` recognised, a banned account is not mistaken for a guest, malformed bodies fall back cleanly **without leaking internals**, wire codes match the backend contract, and guest strings are translated. |
| `ArboreUi/ArboreUiTests/PlantThumbnailDecodingTests.swift` | Thumbnail cache (`PlantThumbnailCache`): a prepared image exposes its pixels without waiting for rendering, downscaling to the card's needs without upscaling a small thumbnail, invalid bytes return `nil` rather than crashing, a second read returns the same instance, and a rewrite replaces the in-memory image. |
| `ArboreUi/ArboreUiTests/PlantCatalogTraitsCacheTests.swift` | Catalogue trait memoisation: re-reading the same plants is an order of magnitude faster, the memoised result is identical to the computed one, and two plants with the same `id` but different flags do not share traits. |
| `ArboreUi/ArboreUiTests/GardenMapPerformanceTests.swift` | Garden map rendering: a symbol is rasterised only once, the two sizes are distinct entries, the variant is stable for a given plant, the name takes precedence over the index for cacti, recognition ignores accents, and the cache is bounded. |

## Catalogue, botanical data & localisation tests

These files protect the catalogue's **data contract**: what is displayed, what is
filtered, and what is translated. Their common rule is that **missing** data must
never be guessed — neither turned into a default value, nor allowed to make a
plant disappear.

| File | Covers |
|---|---|
| `ArboreUi/ArboreUiTests/PlantCatalogContextTests.swift` | Plant recommendation from garden context: a shaded garden recommends a shade-tolerant plant, **a toxic plant is never recommended** when pet safety was requested, unknown data stays flagged for review, preferences are OR within a group and AND between groups, a temperature conflict is a hard exclusion before ranking, a coastal garden rewards salt tolerance, a pot requirement can exclude a balcony plant. |
| `ArboreUi/ArboreUiTests/PlantCareDifficultyTests.swift` | Care difficulty and toxicity: missing data yields **“unknown”** rather than a default level, an explicit difficulty takes precedence over flags, the three levels are recognised in all four languages, “demanding” is tested before “easy”, the fallback never produces “intermediate”, unknown toxicity is excluded from a safety filter, and the botanical profile takes precedence over flags. |
| `ArboreUi/ArboreUiTests/PlantTranslationDecodingTests.swift` | Translation decoding: an incomplete language **does not make the plant disappear**, the English fallback stays available after a rejection, a translation with empty text is kept for its structured data, rich sections survive per-language decoding, a malformed block does not take the entry down with it. |
| `ArboreUi/ArboreUiTests/LocalizationCoverageTests.swift` | Localisation guardrail (#578): every critical key — including `AI_DISCLAIMER` and `AI_DISCLAIMER_SCAN` — is defined in all **four** languages (fr/en/es/de), and translations are not plain copies of the French. |
| `ArboreUi/ArboreUiTests/PlantThumbnailRenderingTests.swift` | Thumbnail rendering: the remote URL carries the design version to bypass the CDN cache, framing moves the camera back for a wide plant and accounts for depth when pitched, and the legacy detector rejects a thumbnail without the current design marker. |
| `ArboreUi/ArboreUiTests/GardenLocationDTOTests.swift` | Garden location DTO: the device position is **rounded before encoding**, a manually entered city carries no coordinates, site-profile round-trip (metadata and zones), an instant light reading is never turned into a daily sunlight estimate, and a remote manual profile stays authoritative during repair. |
| `ArboreUi/ArboreUiTests/ArboreNotificationPlannerTests.swift` | Reminder planning: identifier formats, the date is not shifted without a signal, hot + dry pulls it two days earlier, outdoor rain pushes it one day later, and the reminders (watering, care, project completion) carry the right identifier, category and fallback body. |

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
