# Arbore agent guide

This repository is a multi-part Arbore product. The user's main focus is the
mobile application in `ArboreUi/`, so start there unless the request clearly
targets backend, web, AI generation, docs, or deployment.

## Product shape

- `ArboreUi/`: native iOS app using SwiftUI, ARKit, RoomPlan, SceneKit,
  RealityKit, Firebase Auth, Google Sign-In, Sentry, and XCTest/XCUITest.
- `ArboreBackend/`: Go 1.24 API using Gin, MongoDB Atlas, Firebase Admin, and
  API-key protected REST endpoints.
- `AiGenerator/`: Python FastAPI service for AI-generated plant sheets.
- `web/`: Next.js 13 companion web app with TypeScript, Tailwind, shadcn/Radix,
  Firebase, Sentry, and Vitest.
- `docs/`: bilingual FR/EN technical docs. Any PR touching a documented domain
  should update both languages.

## Mobile architecture reminders

- App entry point: `ArboreUi/ArboreUi/ArboreUiApp.swift`.
- Runtime config: `ArboreUi/ArboreUi/Config/AppConfig.swift`.
- Backend calls should go through `ArboreUi/ArboreUi/Services/NetworkManager.swift`
  so `X-API-Key`, Firebase bearer tokens, token refresh, and retry behavior stay
  consistent.
- USDZ model downloads and caching go through
  `ArboreUi/ArboreUi/Services/ModelCacheManager.swift`.
- `DatabaseFireBaseStore/` is legacy/deprecated for business data. Prefer the Go
  backend via `NetworkManager` for new flows outside authentication.
- `GardenARPlacementView` and extensions are the main AR placement surface and
  remain a large, sensitive area. Keep changes narrow and prefer extending nearby
  tested helpers over adding more state to the view.
- Manual replacement and relocalization logic lives in
  `ArboreUi/ArboreUi/ARGarden/ManualReplacement/`.
- Scene understanding, voxels, TSDF, Marching Cubes, calibration, predictors, and
  fusion live in `ArboreUi/ArboreUi/ARGarden/SceneUnderstanding/`.
- Adaptive AR quality and thermal behavior live in
  `ArboreUi/ArboreUi/ARGarden/Quality/`.
- Local AR persistence is in `ArboreUi/ArboreUi/Views/GardenLocalStore.swift`
  using `worldmap_{id}.arworldmap` and `scene_{id}.json`.

## Docs to read before larger mobile changes

- iOS components: `docs/fr/architecture/03-components-ios.md`
- AR placement flow: `docs/fr/flows/ar-placement.md`
- Garden creation flow: `docs/fr/flows/garden-creation.md`
- Relocation state machine: `docs/fr/state-machines/relocation-phase.md`
- iOS testing strategy: `docs/fr/testing/ios.md`
- 3D LOD/thermal behavior: `docs/fr/3d-lod-architecture.md`
- Observability: `docs/fr/operations/observability.md`
- TestFlight/deploy: `docs/fr/operations/testflight-deploy.md`

Use the matching `docs/en/...` file when updating documentation.

## Secrets and local config

- Do not commit secrets. iOS expects `ArboreUi/Secrets.xcconfig` from
  `ArboreUi/Secrets.xcconfig.example`.
- iOS Firebase config expects `GoogleService-Info.plist`.
- `AppConfig.apiKey` intentionally crashes if `ARBORE_API_KEY` is missing or still
  a placeholder.
- Sentry DSN is split across xcconfig fields because `.xcconfig` treats `//` as a
  comment.

## Common commands

Install iOS dependencies:

```sh
cd ArboreUi && pod install
```

Open iOS workspace:

```sh
open ArboreUi/ArboreUi.xcworkspace
```

Build iOS for simulator without signing:

```sh
cd ArboreUi && xcodebuild clean build \
  -workspace ArboreUi.xcworkspace \
  -scheme ArboreUi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY=""
```

Run all iOS tests:

```sh
cd ArboreUi && xcodebuild test \
  -workspace ArboreUi.xcworkspace \
  -scheme ArboreUi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2' \
  -resultBundlePath build/TestResults.xcresult
```

Run one iOS test suite:

```sh
cd ArboreUi && xcodebuild test \
  -workspace ArboreUi.xcworkspace \
  -scheme ArboreUi \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2' \
  -only-testing:ArboreUiTests/TSDFGridTests
```

List available simulators before relying on hardcoded destinations:

```sh
xcrun simctl list devices available
```

Backend checks:

```sh
make test-backend
```

AI checks:

```sh
make test-ai
```

Web checks:

```sh
cd web && npm test
cd web && npm run typecheck
```

Local service startup:

```sh
./dev.sh dev
```

## Testing guidance

- Prefer targeted XCTest suites first for mobile changes, then broaden if the
  touched area affects shared app behavior.
- Pure AR math/reconstruction tests are deterministic and fast:
  `MarchingCubesTests`, `TSDFGridTests`, `VoxelGridTests`,
  `MeanValueCoordinatesTests`, `DistortionAnalyzerTests`, `GardenMorpherTests`,
  `SurfaceClassifierTests`, `SceneUnderstandingControllerTests`, and
  `DepthCalibrationTests`.
- Network, cache, Firebase, RGPD, and privacy tests may hit real services or skip
  when `/health` is unavailable.
- XCUITests are smoke/performance oriented and depend on simulator state.
- ARKit and RoomPlan behavior should be validated on a physical iOS device when
  camera, LiDAR, tracking, relocalization, or thermal behavior is central to the
  change.

## Coding preferences

- Follow existing SwiftUI and folder conventions. Avoid introducing a new
  architecture style unless the touched code already points that way.
- Keep AR changes small and test math/helpers independently where possible.
- Use `ArboreLog` or existing observability patterns for runtime diagnostics
  instead of scattered prints, except for established DEBUG-only diagnostics.
- Preserve localization. User-facing iOS strings should be checked against
  `fr.lproj`, `en.lproj`, `es.lproj`, and `de.lproj` when applicable.
- Keep `PrivacyInfo.xcprivacy`, consent behavior, and App Store privacy docs in
  mind when adding SDKs, tracking, analytics, permissions, or network collection.
- Before editing, check `git status --short --branch` and protect user changes.
- After editing, report what was verified and what could not be verified locally.

