import ARKit
import CoreVideo
import Foundation
import os
import simd

/// Output of one SemSeg+Depth pass, exposed to the debug overlays so they
/// can render the latest known state.
///
/// `@unchecked Sendable` : the contents (MLShapedArray, CVPixelBuffer)
/// are themselves not Sendable in Swift 6's eyes but we treat the
/// snapshot as fully-formed-and-immutable once constructed, so passing
/// it across the actor boundary to overlays is safe in practice.
struct SceneUnderstandingSnapshot: @unchecked Sendable {
    let timestamp: TimeInterval
    /// Last successful regions (may be empty if the latest pass produced
    /// none above `minClusterPixels`).
    let regions: [SceneRegion]
    /// Optional raw SemanticMap so the 2D overlay can render the mask.
    /// nil when the SemSeg toggle is off (skipped to save inference).
    let semanticMap: SemanticMap?
    /// Optional raw depth buffer for the depth-heatmap overlay.
    let depthMap: CVPixelBuffer?
    /// Last fitted scale (`metric = inverseScale / raw`). nil if no
    /// floor reference was available.
    let inverseScale: Float?
    /// Wall-clock duration of the inference (sum of SemSeg + Depth +
    /// fusion). Surfaced in the debug panel.
    let inferenceMs: Int
}

/// Orchestrates DETR Semantic Segmentation + Depth Anything V2 on each
/// AR frame, throttled to a configurable cadence (cf #187). All inference
/// happens off the main thread inside a `Task.detached`. The orchestrator
/// publishes its latest `SceneUnderstandingSnapshot` for the overlays to
/// consume.
///
/// Lifecycle :
///  1. `init()` — lazy, doesn't load models yet.
///  2. `start()` — loads both predictors. If either model is missing the
///     controller stays disabled (overlays render nothing, classifier
///     fallback in Phase 1 stays in effect).
///  3. `tick(frame:floorY:)` — called from the ARSCNViewDelegate frame
///     callback. Internal throttle ensures we don't run faster than
///     `throttleSeconds`. Safe to call from any thread.
///  4. `stop()` — releases models (~134 MB RAM) and clears the snapshot.
///
/// State mutation is gated by an `NSLock` so the AR session's background
/// callback can safely interact with the controller. The published
/// snapshot fires on the main queue via `onSnapshot`.
final class SceneUnderstandingController {

    /// Inject a custom `PredictorFactory` for tests ; production uses the
    /// default which constructs the real CoreML-backed predictors.
    init(predictorFactory: PredictorFactory = .default) {
        self.predictorFactory = predictorFactory
    }

    /// 1 Hz default — DETR ~40ms, DA V2 ~30ms, fusion ~10ms = ~80ms of
    /// ANE work per inference. At 1 Hz = 8% ANE utilization. Earlier
    /// builds tried 2 Hz (0.5s) but that triggered the iOS "device is
    /// getting hot" warning after a few minutes of continuous use, so
    /// we backed off.
    var throttleSeconds: Double = 1.0

    /// Allow ticking up to `.fair` thermal state. On non-LiDAR devices
    /// the AR session + WorldMap relocalization push the device to
    /// `.fair` within seconds of opening a garden — gating on
    /// `.nominal` (the previous default) means the ML pipeline never
    /// runs in practice. `.serious` would let us keep going under heavy
    /// throttle, but at that point AR itself stutters, so `.fair` is
    /// the right ceiling.
    var maxThermalState: ProcessInfo.ThermalState = .fair

    /// Fired on the main queue every time a new snapshot is ready. Set
    /// from the Coordinator to update the overlays. Cleared on `stop()`.
    var onSnapshot: ((SceneUnderstandingSnapshot) -> Void)?

    private(set) var isAvailable: Bool = false
    private(set) var lastErrorDescription: String?
    // Note : we deliberately do NOT store the last snapshot here. Holding
    // a snapshot pins its `CVPixelBuffer` (depth map) and `MLShapedArray`
    // (semantic map) alive ; with ARKit's image-buffer pool capped, this
    // ties up frames that ARKit then can't recycle — exactly the
    // "ARSession is retaining N ARFrames" warning. Snapshot lifetime is
    // now bounded by the main-queue closure that fans out to overlays.

    /// Optional voxel accumulator — when non-nil, every successful tick
    /// also back-projects the depth+semseg into 3D voxels for the "scan
    /// mode" overlay (cf #187 / VoxelOverlay). The Coordinator sets this
    /// when the user toggles voxel scan on.
    var voxelGrid: VoxelGrid?

    /// `OSAllocatedUnfairLock` (iOS 16+) is async-safe — Swift 6 won't
    /// flag `.lock()` / `.unlock()` calls inside `runOnce`'s async body
    /// the way it would for NSLock.
    private let lock = OSAllocatedUnfairLock()
    private let predictorFactory: PredictorFactory
    private var semseg: (any SemSegPredicting)?
    private var depth: (any DepthPredicting)?
    private var lastTickAt: TimeInterval = 0
    private var inflightTask: Task<Void, Never>?
    /// Fitted once when the first valid floor anchor is reachable —
    /// reused across subsequent ticks. Cleared on `stop()`.
    private var inverseScale: Float?

    /// Tracks the last reason tick() exited early so we can log only on
    /// transitions (avoids 60Hz spam).
    private enum TickGate: String { case ok, unavailable, inflight, throttled, thermal }
    private var lastTickGate: TickGate = .ok

    /// Set to true while the async loader is in flight, so re-entrant
    /// calls to `start()` don't kick off duplicate loaders. Reset in
    /// the loader's completion (success or failure).
    private var isLoading = false

    /// Kicks off model loading on a background task and returns
    /// immediately. `isAvailable` flips to true when both predictors
    /// have initialised. Callers should not wait synchronously — the
    /// `tick()` gate already handles the "not yet available" state by
    /// skipping with reason=.unavailable.
    ///
    /// Loading both predictors involves `MLModel(contentsOf:)` which is
    /// synchronous I/O (~200-500ms on a non-LiDAR phone). Doing it under
    /// our state lock froze the UI and starved subsequent `tick()` calls.
    /// Idempotent ; safe to call from main repeatedly.
    func start() {
        let shouldLoad: Bool = lock.withLock {
            guard !self.isAvailable, !self.isLoading else { return false }
            self.isLoading = true
            return true
        }
        guard shouldLoad else { return }

        let factory = self.predictorFactory
        Task.detached(priority: .userInitiated) { [weak self] in
            // Heavy I/O happens OUTSIDE the lock — Apple's CoreML init
            // compiles the model and mmaps weights, totally fine to do
            // in parallel with anything else.
            let result: (semseg: (any SemSegPredicting)?, depth: (any DepthPredicting)?, error: String?) = {
                do {
                    let semseg = try factory.makeSemSeg()
                    let depth = try factory.makeDepth()
                    return (semseg, depth, nil)
                } catch {
                    return (nil, nil, String(describing: error))
                }
            }()
            guard let strong = self else { return }
            strong.lock.withLock {
                strong.isLoading = false
                strong.semseg = result.semseg
                strong.depth = result.depth
                strong.lastErrorDescription = result.error
                strong.isAvailable = (result.semseg != nil && result.depth != nil)
            }
            if result.error == nil {
                AppLog.sceneML.notice("SceneUnderstandingController online (semseg + depth)")
            } else {
                AppLog.sceneML.error("SceneUnderstandingController init failed: \(result.error ?? "", privacy: .public)")
            }
        }
    }

    /// Releases models + clears the snapshot. ~134 MB of RAM is freed.
    func stop() {
        lock.withLock {
            self.inflightTask?.cancel()
            self.inflightTask = nil
            self.semseg = nil
            self.depth = nil
            self.inverseScale = nil
            self.isAvailable = false
        }
        AppLog.sceneML.notice("SceneUnderstandingController stopped")
    }

    /// Force-refit the depth scale on the next tick (use after the user
    /// changes garden / floor anchor moves significantly).
    func recalibrate() {
        lock.withLock { self.inverseScale = nil }
    }

    /// Per-AR-frame entrypoint. The expected call site is the
    /// `ARSCNViewDelegate.session(_:didUpdate:)` of the placement view.
    /// Internally throttles ; safe to call at 60 Hz.
    ///
    /// - Parameter floorWorldPoint: optional centroid of a known floor
    ///   plane anchor in world coordinates. Preferred over `floorY` for
    ///   calibration — single-point fit assuming the centre pixel sits
    ///   on the floor (the old API) is wrong 90% of the time because
    ///   users don't point straight down.
    func tick(frame: ARFrame, floorY: Float?, floorWorldPoint: SIMD3<Float>? = nil) {
        // Snapshot the runnable state under the lock — returns nil if
        // the tick should be skipped.
        struct TickGo {
            let semseg: any SemSegPredicting
            let depth: any DepthPredicting
            let cachedScale: Float?
        }
        struct TickGateResult {
            let go: TickGo?
            let reason: TickGate
            let transitioned: Bool
            let thermalRaw: Int
        }
        let result: TickGateResult = lock.withLock {
            let thermal = ProcessInfo.processInfo.thermalState
            let now = frame.timestamp
            let reason: TickGate
            var go: TickGo? = nil
            if !self.isAvailable || self.semseg == nil || self.depth == nil {
                reason = .unavailable
            } else if self.inflightTask != nil {
                reason = .inflight
            } else if now - self.lastTickAt < self.throttleSeconds {
                reason = .throttled
            } else if thermal.rawValue > self.maxThermalState.rawValue {
                reason = .thermal
            } else {
                reason = .ok
                self.lastTickAt = now
                go = TickGo(semseg: self.semseg!, depth: self.depth!, cachedScale: self.inverseScale)
            }
            let transitioned = reason != self.lastTickGate
            self.lastTickGate = reason
            return TickGateResult(go: go, reason: reason, transitioned: transitioned, thermalRaw: thermal.rawValue)
        }
        if result.transitioned && result.reason != .throttled {
            // .throttled is the expected 59 out of 60 frames — don't log it.
            // Log every other transition, INCLUDING the resume to .ok so we
            // can see when inference recovers from thermal / unavailable.
            AppLog.sceneML.notice("tick gate=\(result.reason.rawValue, privacy: .public) thermal=\(result.thermalRaw, privacy: .public)")
        }
        guard let go = result.go else { return }

        // Snapshot the frame data — ARFrame isn't safe across async boundaries.
        let pixelBuffer = frame.capturedImage
        let intrinsics = frame.camera.intrinsics
        let captureSize = frame.camera.imageResolution
        let cameraTransform = frame.camera.transform
        let cameraY = cameraTransform.columns.3.y

        let task = Task.detached(priority: .utility) { [weak self] in
            await self?.runOnce(
                semseg: go.semseg,
                depth: go.depth,
                pixelBuffer: pixelBuffer,
                intrinsics: intrinsics,
                captureSize: captureSize,
                cameraTransform: cameraTransform,
                cameraY: cameraY,
                floorY: floorY,
                floorWorldPoint: floorWorldPoint,
                cachedScale: go.cachedScale
            )
            // Strong-capture self inside the lock body — the outer weak
            // closure already gates the call ; we only want to silence
            // Swift 6's warning about capturing `self` mutably.
            if let strong = self {
                strong.lock.withLock { strong.inflightTask = nil }
            }
        }
        lock.withLock { self.inflightTask = task }
    }

    private func runOnce(
        semseg: any SemSegPredicting,
        depth: any DepthPredicting,
        pixelBuffer: CVPixelBuffer,
        intrinsics: simd_float3x3,
        captureSize: CGSize,
        cameraTransform: simd_float4x4,
        cameraY: Float,
        floorY: Float?,
        floorWorldPoint: SIMD3<Float>?,
        cachedScale: Float?
    ) async {
        let startMs = CFAbsoluteTimeGetCurrent() * 1000

        // 1. Inference — both models run in parallel, each isolated so a
        //    failure in one doesn't kill the other.
        let (semanticMap, depthMap) = await runInference(semseg: semseg,
                                                         depth: depth,
                                                         pixelBuffer: pixelBuffer)
        recordOutcome(semanticOK: semanticMap != nil, depthOK: depthMap != nil)

        // 2. Calibration — fit metric depth scale (preferred from a known
        //    floor world point ; fallback to camera-height/centre-pixel).
        let scale = cachedScale ?? fitInverseScale(depthMap: depthMap,
                                                   floorWorldPoint: floorWorldPoint,
                                                   floorY: floorY,
                                                   cameraY: cameraY,
                                                   cameraTransform: cameraTransform,
                                                   intrinsics: intrinsics,
                                                   captureSize: captureSize)

        // 3. Fusion + voxel accumulation (only when all inputs are valid).
        let regions = fuseAndAccumulate(semanticMap: semanticMap,
                                        depthMap: depthMap,
                                        inverseScale: scale,
                                        intrinsics: intrinsics,
                                        cameraTransform: cameraTransform,
                                        captureSize: captureSize)

        // 4. Publish — only when at least one predictor produced output.
        guard semanticMap != nil || depthMap != nil else {
            lock.withLock { self.lastErrorDescription = "both models failed" }
            return
        }
        let elapsed = Int(CFAbsoluteTimeGetCurrent() * 1000 - startMs)
        publish(SceneUnderstandingSnapshot(
            timestamp: CFAbsoluteTimeGetCurrent(),
            regions: regions,
            semanticMap: semanticMap,
            depthMap: depthMap,
            inverseScale: scale,
            inferenceMs: elapsed
        ))
    }

    // MARK: - runOnce helpers

    private func runInference(
        semseg: any SemSegPredicting,
        depth: any DepthPredicting,
        pixelBuffer: CVPixelBuffer
    ) async -> (SemanticMap?, CVPixelBuffer?) {
        async let semOptional: SemanticMap? = {
            do { return try await semseg.predict(pixelBuffer) }
            catch {
                AppLog.sceneML.error("semseg failed: \(String(describing: error), privacy: .public)")
                return nil
            }
        }()
        async let depthOptional: CVPixelBuffer? = {
            do { return try await depth.predict(pixelBuffer) }
            catch {
                AppLog.sceneML.error("depth failed: \(String(describing: error), privacy: .public)")
                return nil
            }
        }()
        return (await semOptional, await depthOptional)
    }

    /// Fit the metric depth scale `s` such that `metric = s / raw`. Tries
    /// the floor-anchor projection first (reliable), falls back to the
    /// camera-height + centre-pixel assumption (less reliable — only
    /// correct when the user happens to be aiming straight down). Logs
    /// the path taken for debugging.
    private func fitInverseScale(
        depthMap: CVPixelBuffer?,
        floorWorldPoint: SIMD3<Float>?,
        floorY: Float?,
        cameraY: Float,
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        captureSize: CGSize
    ) -> Float? {
        guard let depthMap = depthMap else { return nil }
        AppLog.sceneML.notice("Calibration attempt floorAnchor=\(floorWorldPoint != nil, privacy: .public) floorY=\(floorY ?? -999, privacy: .public) cameraY=\(cameraY, privacy: .public)")

        if let worldPoint = floorWorldPoint {
            let scale = DepthCalibration.fitInverseScale(
                depthMap: depthMap,
                worldPoint: worldPoint,
                cameraTransform: cameraTransform,
                intrinsics: intrinsics,
                captureSize: captureSize
            )
            if let scale = scale {
                AppLog.sceneML.notice("Calibrated via floor anchor inverseScale=\(scale, privacy: .public) worldPoint=(\(worldPoint.x, privacy: .public),\(worldPoint.y, privacy: .public),\(worldPoint.z, privacy: .public))")
                return scale
            }
            AppLog.sceneML.notice("Calibration via floor anchor returned nil — projection out of bounds or raw depth degenerate")
        }

        guard let floorY = floorY else { return nil }
        let height = cameraY - floorY
        guard height > 0.3 else {
            AppLog.sceneML.notice("Skipping centre-pixel fallback : camera height \(height, privacy: .public)m < 0.3m")
            return nil
        }
        let scale = DepthCalibration.fitInverseScale(depthMap: depthMap, cameraHeightMeters: height)
        if let scale = scale {
            AppLog.sceneML.notice("Calibrated via centre-pixel inverseScale=\(scale, privacy: .public) h=\(height, privacy: .public)m (less reliable)")
        } else {
            AppLog.sceneML.notice("Centre-pixel calibration returned nil (h=\(height, privacy: .public)m)")
        }
        return scale
    }

    private func fuseAndAccumulate(
        semanticMap: SemanticMap?,
        depthMap: CVPixelBuffer?,
        inverseScale: Float?,
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        captureSize: CGSize
    ) -> [SceneRegion] {
        guard let semanticMap = semanticMap,
              let depthMap = depthMap,
              let scale = inverseScale else { return [] }

        let regions = SceneFusion.fuse(
            semanticMap: semanticMap,
            depthMap: depthMap,
            inverseScale: scale,
            intrinsics: intrinsics,
            cameraTransform: cameraTransform,
            captureSize: captureSize
        )
        if let grid = (lock.withLock { self.voxelGrid }) {
            VoxelAccumulator.accumulate(
                into: grid,
                semanticMap: semanticMap,
                depthMap: depthMap,
                inverseScale: scale,
                intrinsics: intrinsics,
                cameraTransform: cameraTransform,
                captureSize: captureSize
            )
        }
        return regions
    }

    /// Fire the onSnapshot callback on main and update the cached scale.
    /// We never store the snapshot itself — see the property comment.
    private func publish(_ snap: SceneUnderstandingSnapshot) {
        let callback: ((SceneUnderstandingSnapshot) -> Void)? = lock.withLock {
            self.inverseScale = snap.inverseScale
            return self.onSnapshot
        }
        if let callback = callback {
            DispatchQueue.main.async { callback(snap) }
        }
    }

    /// Track per-model consecutive failures and auto-disable models that
    /// keep failing — they're never going to succeed (most likely a Apple
    /// model revision changed the input size). After `maxRepeatedFailures`
    /// we set `semseg` / `depth` to nil and stop ticking that one.
    private static let maxRepeatedFailures = 6
    private var semsegFailureStreak = 0
    private var depthFailureStreak = 0

    private func recordOutcome(semanticOK: Bool, depthOK: Bool) {
        lock.withLock {
            if semanticOK {
                self.semsegFailureStreak = 0
            } else {
                self.semsegFailureStreak += 1
                if self.semsegFailureStreak >= Self.maxRepeatedFailures {
                    AppLog.sceneML.error("SemSeg auto-disabled after \(Self.maxRepeatedFailures, privacy: .public) consecutive failures.")
                    self.semseg = nil
                }
            }
            if depthOK {
                self.depthFailureStreak = 0
            } else {
                self.depthFailureStreak += 1
                if self.depthFailureStreak >= Self.maxRepeatedFailures {
                    AppLog.sceneML.error("Depth auto-disabled after \(Self.maxRepeatedFailures, privacy: .public) consecutive failures.")
                    self.depth = nil
                }
            }
        }
    }
}
