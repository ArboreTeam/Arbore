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

    /// 1 Hz default — DETR ~40ms, DA V2 ~30ms, fusion ~10ms = ~80ms of
    /// ANE work per inference. At 1 Hz = 8% ANE utilization. Earlier
    /// builds tried 2 Hz (0.5s) but that triggered the iOS "device is
    /// getting hot" warning after a few minutes of continuous use, so
    /// we backed off.
    var throttleSeconds: Double = 1.0

    /// Stop ticking as soon as the device leaves `.nominal` thermal state.
    /// The .fair state already means "elevated, performance may be
    /// throttled" — by then the ARSession is already competing with us
    /// for the GPU/CPU. .nominal = "everything fine" only.
    var maxThermalState: ProcessInfo.ThermalState = .nominal

    /// Fired on the main queue every time a new snapshot is ready. Set
    /// from the Coordinator to update the overlays. Cleared on `stop()`.
    var onSnapshot: ((SceneUnderstandingSnapshot) -> Void)?

    private(set) var isAvailable: Bool = false
    private(set) var lastErrorDescription: String?
    private(set) var snapshot: SceneUnderstandingSnapshot?

    /// Optional voxel accumulator — when non-nil, every successful tick
    /// also back-projects the depth+semseg into 3D voxels for the "scan
    /// mode" overlay (cf #187 / VoxelOverlay). The Coordinator sets this
    /// when the user toggles voxel scan on.
    var voxelGrid: VoxelGrid?

    /// `OSAllocatedUnfairLock` (iOS 16+) is async-safe — Swift 6 won't
    /// flag `.lock()` / `.unlock()` calls inside `runOnce`'s async body
    /// the way it would for NSLock.
    private let lock = OSAllocatedUnfairLock()
    private var semseg: SemSegPredictor?
    private var depth: DepthPredictor?
    private var lastTickAt: TimeInterval = 0
    private var inflightTask: Task<Void, Never>?
    /// Fitted once when the first valid floor anchor is reachable —
    /// reused across subsequent ticks. Cleared on `stop()`.
    private var inverseScale: Float?

    /// Loads the models. Idempotent ; safe to call repeatedly.
    func start() {
        lock.withLock {
            guard !self.isAvailable else { return }
            do {
                self.semseg = try SemSegPredictor()
                self.depth = try DepthPredictor()
                self.isAvailable = true
                self.lastErrorDescription = nil
                AppLog.sceneML.notice("SceneUnderstandingController online (semseg + depth)")
            } catch {
                self.semseg = nil
                self.depth = nil
                self.isAvailable = false
                self.lastErrorDescription = String(describing: error)
                AppLog.sceneML.error("SceneUnderstandingController init failed: \(String(describing: error), privacy: .public)")
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
            self.snapshot = nil
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
            let semseg: SemSegPredictor
            let depth: DepthPredictor
            let cachedScale: Float?
        }
        let go: TickGo? = lock.withLock {
            guard self.isAvailable,
                  let semseg = self.semseg,
                  let depth = self.depth,
                  self.inflightTask == nil else { return nil }
            let now = frame.timestamp
            if now - self.lastTickAt < self.throttleSeconds { return nil }
            let thermal = ProcessInfo.processInfo.thermalState
            if thermal.rawValue > self.maxThermalState.rawValue { return nil }
            self.lastTickAt = now
            return TickGo(semseg: semseg, depth: depth, cachedScale: self.inverseScale)
        }
        guard let go = go else { return }

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
        semseg: SemSegPredictor,
        depth: DepthPredictor,
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

        // Run both predictors in parallel. Each one is wrapped in its own
        // do/catch so a failure in one doesn't bubble up and kill the other
        // — we publish whatever we got. Important on device when one of
        // the two models gets re-released by Apple with a different input
        // size : we still want the working overlay to render.
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
        let semanticMap = await semOptional
        let depthMap = await depthOptional

        // Auto-disable after `maxRepeatedFailures` consecutive failures
        // of one model. Stops burning GPU on inputs the model will never
        // accept — typically a sign Apple updated the .mlpackage and our
        // resize size is now wrong, or the model file is corrupt.
        recordOutcome(semanticOK: semanticMap != nil, depthOK: depthMap != nil)

        // Calibrate (fit once, reuse). Prefer the floor-anchor-point
        // method when we have one — projects a known world point onto
        // the depth image, way more reliable than the centre-pixel
        // assumption. Falls back to camera-height/centre-pixel only
        // when no floor anchor centroid is known.
        var scale = cachedScale
        if scale == nil, let depthMap = depthMap {
            // Diagnostic : log once per attempt so we can see why
            // calibration isn't firing.
            AppLog.sceneML.notice("Calibration attempt floorAnchor=\(floorWorldPoint != nil, privacy: .public) floorY=\(floorY ?? -999, privacy: .public) cameraY=\(cameraY, privacy: .public)")
            if let worldPoint = floorWorldPoint {
                scale = DepthCalibration.fitInverseScale(
                    depthMap: depthMap,
                    worldPoint: worldPoint,
                    cameraTransform: cameraTransform,
                    intrinsics: intrinsics,
                    captureSize: captureSize
                )
                if let scale = scale {
                    AppLog.sceneML.notice("Calibrated via floor anchor inverseScale=\(scale, privacy: .public) worldPoint=(\(worldPoint.x, privacy: .public),\(worldPoint.y, privacy: .public),\(worldPoint.z, privacy: .public))")
                } else {
                    AppLog.sceneML.notice("Calibration via floor anchor returned nil — projection out of bounds or raw depth degenerate")
                }
            }
            if scale == nil, let floorY = floorY {
                let height = cameraY - floorY
                if height > 0.3 {
                    scale = DepthCalibration.fitInverseScale(
                        depthMap: depthMap,
                        cameraHeightMeters: height
                    )
                    if let scale = scale {
                        AppLog.sceneML.notice("Calibrated via centre-pixel inverseScale=\(scale, privacy: .public) h=\(height, privacy: .public)m (less reliable)")
                    } else {
                        AppLog.sceneML.notice("Centre-pixel calibration returned nil (h=\(height, privacy: .public)m)")
                    }
                } else {
                    AppLog.sceneML.notice("Skipping centre-pixel fallback : camera height \(height, privacy: .public)m < 0.3m")
                }
            }
        }

        // Fuse only when ALL inputs are available. Otherwise the snapshot
        // ships with regions = [] but still carries the partial 2D overlays.
        var regions: [SceneRegion] = []
        if let semanticMap = semanticMap, let depthMap = depthMap, let scale = scale {
            regions = SceneFusion.fuse(
                semanticMap: semanticMap,
                depthMap: depthMap,
                inverseScale: scale,
                intrinsics: intrinsics,
                cameraTransform: cameraTransform,
                captureSize: captureSize
            )
            // Voxel accumulation (scan mode). Same backprojection pass
            // as fusion but quantizes onto a 4cm world-space grid and
            // colours each cell by its SemSeg category. Cheap : the
            // grid hashmap insert is O(1) per pixel.
            if let grid = (lock.withLock { self.voxelGrid }) {
                Self.accumulateVoxels(
                    into: grid,
                    semanticMap: semanticMap,
                    depthMap: depthMap,
                    inverseScale: scale,
                    intrinsics: intrinsics,
                    cameraTransform: cameraTransform,
                    captureSize: captureSize
                )
            }
        }

        // No point publishing if BOTH predictors failed and we had no
        // previous data to update — the overlays would just stay empty.
        guard semanticMap != nil || depthMap != nil else {
            lock.withLock { self.lastErrorDescription = "both models failed" }
            return
        }

        let elapsed = Int(CFAbsoluteTimeGetCurrent() * 1000 - startMs)
        let resolvedScale = scale
        let snap = SceneUnderstandingSnapshot(
            timestamp: CFAbsoluteTimeGetCurrent(),
            regions: regions,
            semanticMap: semanticMap,
            depthMap: depthMap,
            inverseScale: resolvedScale,
            inferenceMs: elapsed
        )
        let callback: ((SceneUnderstandingSnapshot) -> Void)? = lock.withLock {
            self.inverseScale = resolvedScale
            self.snapshot = snap
            return self.onSnapshot
        }
        if let callback = callback {
            DispatchQueue.main.async { callback(snap) }
        }
    }

    // MARK: - Voxel accumulator

    /// Per-pixel back-projection identical to `SceneFusion.fuse`, but
    /// instead of building region clusters we drop each labelled point
    /// into the voxel grid keyed by its quantised world position. Runs
    /// at the same 1 Hz cadence as the rest of the tick.
    private static func accumulateVoxels(
        into grid: VoxelGrid,
        semanticMap: SemanticMap,
        depthMap: CVPixelBuffer,
        inverseScale: Float,
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        captureSize: CGSize
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        let segW = semanticMap.width
        let segH = semanticMap.height

        let segIntrinsics = BackProjector.scaledIntrinsics(
            intrinsics,
            from: captureSize,
            to: CGSize(width: segW, height: segH)
        )

        let depthW = CVPixelBufferGetWidth(depthMap)
        let depthH = CVPixelBufferGetHeight(depthMap)
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let depthBpr = CVPixelBufferGetBytesPerRow(depthMap)
        let depthFmt = CVPixelBufferGetPixelFormatType(depthMap)

        // Stride 8 = ~3000 voxels per frame on a 448×448 input — gentle
        // enough that we don't tank framerate building 200k cells in a
        // single tick, dense enough to fill the room in a few seconds.
        let stride = 8

        for r in Swift.stride(from: 0, to: segH, by: stride) {
            let dRow = min(Int(Float(r) / Float(segH) * Float(depthH)), depthH - 1)
            for c in Swift.stride(from: 0, to: segW, by: stride) {
                let dCol = min(Int(Float(c) / Float(segW) * Float(depthW)), depthW - 1)
                let raw = DepthPixelBufferAccess.sampleRaw(
                    x: dCol, y: dRow,
                    base: depthBase, bytesPerRow: depthBpr,
                    format: depthFmt, width: depthW, height: depthH
                )
                let metric = DepthCalibration.metric(raw: raw, inverseScale: inverseScale)
                guard SceneFusion.validMetricRange.contains(metric) else { continue }
                let rawId = Int(semanticMap.pixels[scalarAt: [r, c]])
                let label = semanticMap.labels[rawId] ?? ""
                let cat = COCOPanopticCategory.category(for: label)
                if cat == .other { continue }

                let world = BackProjector.worldPosition(
                    u: Float(c), v: Float(r),
                    dMetric: metric,
                    intrinsics: segIntrinsics,
                    cameraTransform: cameraTransform
                )
                let color = cat.debugColor
                var r4: CGFloat = 0, g4: CGFloat = 0, b4: CGFloat = 0, a: CGFloat = 0
                color.getRed(&r4, green: &g4, blue: &b4, alpha: &a)
                grid.insert(point: world,
                            color: SIMD3<Float>(Float(r4), Float(g4), Float(b4)),
                            now: now)
            }
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
