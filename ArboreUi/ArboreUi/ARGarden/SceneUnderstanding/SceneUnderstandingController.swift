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
    /// Last fitted depth calibration (affine model — cf #190 Niveau 2).
    /// nil if not enough ARKit anchors are visible to fit.
    let depthFit: DepthCalibration.AffineFit?
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
    /// Most recently fitted depth model. Updated every tick (with a
    /// fresh sample set) instead of cached forever — see #186 Niveau 2.
    /// Cleared on `stop()`.
    private var depthFit: DepthCalibration.AffineFit?

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
            self.depthFit = nil
            self.isAvailable = false
        }
        AppLog.sceneML.notice("SceneUnderstandingController stopped")
    }

    /// Force-refit the depth scale on the next tick (use after the user
    /// changes garden / floor anchor moves significantly).
    func recalibrate() {
        lock.withLock { self.depthFit = nil }
    }

    /// Per-AR-frame entrypoint. The expected call site is the
    /// `ARSCNViewDelegate.session(_:didUpdate:)` of the placement view.
    /// Internally throttles ; safe to call at 60 Hz.
    ///
    /// - Parameter calibrationAnchors: world-space points known to be on
    ///   real surfaces (ARKit plane centroids, raw feature points...).
    ///   We project them into the depth image and fit `1/metric = a·raw + b`
    ///   by least squares — see #190 Niveau 2. Pass as many as you have ;
    ///   ≥5 gives a robust fit, but we also accept 1 (degenerate to old
    ///   single-point behaviour) so the pipeline starts producing
    ///   something quickly while ARKit catches up.
    func tick(frame: ARFrame, calibrationAnchors: [SIMD3<Float>]) {
        // Snapshot the runnable state under the lock — returns nil if
        // the tick should be skipped.
        struct TickGo {
            let semseg: any SemSegPredicting
            let depth: any DepthPredicting
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
                go = TickGo(semseg: self.semseg!, depth: self.depth!)
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

        let task = Task.detached(priority: .utility) { [weak self] in
            await self?.runOnce(
                semseg: go.semseg,
                depth: go.depth,
                pixelBuffer: pixelBuffer,
                intrinsics: intrinsics,
                captureSize: captureSize,
                cameraTransform: cameraTransform,
                calibrationAnchors: calibrationAnchors
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
        calibrationAnchors: [SIMD3<Float>]
    ) async {
        let startMs = CFAbsoluteTimeGetCurrent() * 1000

        // 1. Inference — both models run in parallel, each isolated so a
        //    failure in one doesn't kill the other.
        let (semanticMap, depthMap) = await runInference(semseg: semseg,
                                                         depth: depth,
                                                         pixelBuffer: pixelBuffer)
        recordOutcome(semanticOK: semanticMap != nil, depthOK: depthMap != nil)

        // 2. Calibration — re-fit every tick from the current anchors
        //    instead of caching forever. If the new fit fails (no
        //    anchors in view, all anchors degenerate), we fall back to
        //    the previous one so accumulation can keep running through
        //    transient gaps.
        let previousFit = lock.withLock { self.depthFit }
        let fit = fitDepth(depthMap: depthMap,
                           anchors: calibrationAnchors,
                           cameraTransform: cameraTransform,
                           intrinsics: intrinsics,
                           captureSize: captureSize,
                           previous: previousFit)

        // 3. Fusion + voxel accumulation (only when all inputs are valid).
        let regions = fuseAndAccumulate(semanticMap: semanticMap,
                                        depthMap: depthMap,
                                        fit: fit,
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
            depthFit: fit,
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

    /// Fit the depth model `1/metric = a·raw + b` from the current
    /// ARKit anchor set (#190 Niveau 2). On failure, returns the
    /// previous fit so the pipeline keeps running through transient
    /// gaps (anchor briefly out of FoV, etc.).
    ///
    /// Logs the inlier count + the resulting `equivalentInverseScale`
    /// so device traces remain readable in the old "scale=0.9-ish"
    /// mental model. RANSAC + temporal smoothing is tracked in #190.
    private func fitDepth(
        depthMap: CVPixelBuffer?,
        anchors: [SIMD3<Float>],
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        captureSize: CGSize,
        previous: DepthCalibration.AffineFit?
    ) -> DepthCalibration.AffineFit? {
        guard let depthMap = depthMap else { return previous }
        guard !anchors.isEmpty else {
            // No anchors visible this frame — keep last good fit.
            return previous
        }
        let samples = DepthCalibration.collectSamples(
            depthMap: depthMap,
            worldAnchors: anchors,
            cameraTransform: cameraTransform,
            intrinsics: intrinsics,
            captureSize: captureSize
        )
        guard let fit = DepthCalibration.fitAffine(samples: samples) else {
            AppLog.sceneML.notice("Depth fit skipped : anchors=\(anchors.count, privacy: .public) usable=\(samples.count, privacy: .public)")
            return previous
        }
        // Edge-triggered log so we don't spam at 1Hz with the same numbers.
        let equiv = fit.equivalentInverseScale ?? .nan
        if previous == nil || previous != fit {
            AppLog.sceneML.notice("Depth fit anchors=\(anchors.count, privacy: .public) inliers=\(samples.count, privacy: .public) a=\(fit.a, privacy: .public) b=\(fit.b, privacy: .public) ≈inverseScale=\(equiv, privacy: .public)")
        }
        return fit
    }

    private func fuseAndAccumulate(
        semanticMap: SemanticMap?,
        depthMap: CVPixelBuffer?,
        fit: DepthCalibration.AffineFit?,
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        captureSize: CGSize
    ) -> [SceneRegion] {
        guard let semanticMap = semanticMap,
              let depthMap = depthMap,
              let fit = fit else { return [] }

        let regions = SceneFusion.fuse(
            semanticMap: semanticMap,
            depthMap: depthMap,
            fit: fit,
            intrinsics: intrinsics,
            cameraTransform: cameraTransform,
            captureSize: captureSize
        )
        if let grid = (lock.withLock { self.voxelGrid }) {
            VoxelAccumulator.accumulate(
                into: grid,
                semanticMap: semanticMap,
                depthMap: depthMap,
                fit: fit,
                intrinsics: intrinsics,
                cameraTransform: cameraTransform,
                captureSize: captureSize
            )
        }
        return regions
    }

    /// Fire the onSnapshot callback on main and update the cached fit.
    /// We never store the snapshot itself — see the property comment.
    private func publish(_ snap: SceneUnderstandingSnapshot) {
        let callback: ((SceneUnderstandingSnapshot) -> Void)? = lock.withLock {
            self.depthFit = snap.depthFit
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
