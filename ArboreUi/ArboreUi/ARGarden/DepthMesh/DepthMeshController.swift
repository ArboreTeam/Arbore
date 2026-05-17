import ARKit
import Foundation
import SceneKit
import simd

/// Orchestrates the depth-prediction → mesh → viz pipeline.
///
/// Lifecycle :
///   1. `init()` lazy-loads the CoreML model. If the model is missing the
///      controller stays in a disabled state (graceful) — `isAvailable`
///      reports false and `tick(...)` is a no-op.
///   2. `start(in: arView)` attaches a viz node to the scene root.
///   3. `tick(frame:)` is called from `ARSCNViewDelegate.session(_:didUpdate:)`
///      and runs at most once every `throttleSeconds` ; predicting + meshing
///      take ~45ms total on iPhone 15 Pro so 0.5s gives plenty of headroom.
///   4. `stop()` removes the viz node.
final class DepthMeshController {

    /// How often we re-run inference. Keep ≥ 0.3 s to avoid choking the
    /// AR session — both the depth predictor and the SceneKit rebuild
    /// allocate on the main thread bridges.
    var throttleSeconds: Double = 0.5

    private(set) var isAvailable: Bool = false
    private var predictor: DepthPredictor?
    private weak var sceneRoot: SCNNode?
    private var meshNode: SCNNode?
    private var lastTickAt: TimeInterval = 0
    private var inflightTask: Task<Void, Never>?

    /// Inverse-depth scale `s` such that `metric = s / raw`. Fitted once
    /// at start, refit on demand via `recalibrate`.
    private var inverseScale: Float?

    init() {
        do {
            self.predictor = try DepthPredictor()
            self.isAvailable = true
            AppLog.depthMesh.notice("DepthMeshController online.")
        } catch {
            self.predictor = nil
            self.isAvailable = false
            AppLog.depthMesh.error("DepthMeshController unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    /// Attach the viz node holder to the scene. Idempotent.
    func start(in scene: SCNScene) {
        guard isAvailable else { return }
        if meshNode == nil {
            let node = SCNNode()
            node.name = "depthMeshOverlay"
            scene.rootNode.addChildNode(node)
            self.meshNode = node
        }
        self.sceneRoot = scene.rootNode
        AppLog.depthMesh.notice("DepthMesh viz started.")
    }

    /// Remove the viz node. Idempotent.
    func stop() {
        inflightTask?.cancel()
        inflightTask = nil
        meshNode?.removeFromParentNode()
        meshNode = nil
        AppLog.depthMesh.notice("DepthMesh viz stopped.")
    }

    /// Force-refit the inverse scale on the next tick. Useful after the
    /// user re-detects the floor (or hops to a new garden).
    func recalibrate() {
        inverseScale = nil
    }

    /// Called every AR frame. Throttles internally and dispatches the
    /// heavy work off-main.
    func tick(frame: ARFrame) {
        guard isAvailable, let predictor = predictor, meshNode != nil else { return }
        let now = frame.timestamp
        if now - lastTickAt < throttleSeconds { return }
        if inflightTask != nil { return }
        lastTickAt = now

        // Snapshot the values the predictor + mesher need ; ARFrame is
        // not safe to hold across async boundaries.
        let pixelBuffer = frame.capturedImage
        let intrinsics = frame.camera.intrinsics
        let captureSize = frame.camera.imageResolution
        let cameraTransform = frame.camera.transform
        let cameraHeight = estimateCameraHeight(frame: frame)

        inflightTask = Task.detached(priority: .utility) { [weak self] in
            await self?.runOnce(
                predictor: predictor,
                pixelBuffer: pixelBuffer,
                intrinsics: intrinsics,
                captureSize: captureSize,
                cameraTransform: cameraTransform,
                cameraHeight: cameraHeight
            )
            await MainActor.run { self?.inflightTask = nil }
        }
    }

    private func runOnce(
        predictor: DepthPredictor,
        pixelBuffer: CVPixelBuffer,
        intrinsics: simd_float3x3,
        captureSize: CGSize,
        cameraTransform: simd_float4x4,
        cameraHeight: Float?
    ) async {
        do {
            let depth = try await predictor.predict(pixelBuffer)

            // First tick (or after recalibrate): fit the inverse-depth scale.
            if inverseScale == nil, let h = cameraHeight, h > 0.3 {
                if let centreRaw = sampleCentreDepth(depth) {
                    if let s = DepthCalibration.fitInverseScale(
                        rawDepthAtFloorSamplePoint: centreRaw,
                        cameraHeightMeters: h
                    ) {
                        self.inverseScale = s
                        AppLog.depthMesh.notice("Calibrated inverseScale=\(s, privacy: .public) from h=\(h, privacy: .public)m centreRaw=\(centreRaw, privacy: .public)")
                    }
                }
            }
            guard let scale = inverseScale else {
                AppLog.depthMesh.debug("Skipping mesh — no calibration yet (no floor / no centre depth).")
                return
            }

            guard let mesh = DepthMesher.build(
                depth: depth,
                intrinsics: intrinsics,
                captureSize: captureSize,
                cameraTransform: cameraTransform,
                inverseScale: scale
            ) else { return }

            guard let geo = DepthMeshVizRenderer.makeGeometry(from: mesh) else { return }

            await MainActor.run { [weak self] in
                guard let self = self, let parent = self.meshNode else { return }
                // Replace the previous mesh atomically. We keep the parent
                // node so anything referencing it (highlights, …) keeps
                // working, but we swap its single child.
                parent.childNodes.forEach { $0.removeFromParentNode() }
                let node = SCNNode(geometry: geo)
                node.name = "depthMeshFrame"
                parent.addChildNode(node)
            }
        } catch {
            AppLog.depthMesh.error("Tick failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Best-effort estimate of camera height above the detected floor.
    /// Returns nil when no horizontal plane is detected yet.
    private func estimateCameraHeight(frame: ARFrame) -> Float? {
        let camY = frame.camera.transform.columns.3.y
        var floorY: Float? = nil
        for anchor in frame.anchors {
            guard let plane = anchor as? ARPlaneAnchor, plane.alignment == .horizontal else { continue }
            let y = anchor.transform.columns.3.y
            // Take the lowest detected horizontal plane — that's the floor
            // in the vast majority of indoor scenes.
            if floorY == nil || y < floorY! { floorY = y }
        }
        guard let f = floorY else { return nil }
        let h = camY - f
        return h > 0.3 ? h : nil  // reject implausible heights
    }

    /// Read the centre pixel of the depth buffer (raw inverse-depth value).
    private func sampleCentreDepth(_ depth: CVPixelBuffer) -> Float? {
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depth) else { return nil }
        let w = CVPixelBufferGetWidth(depth)
        let h = CVPixelBufferGetHeight(depth)
        let bpr = CVPixelBufferGetBytesPerRow(depth)
        let fmt = CVPixelBufferGetPixelFormatType(depth)
        let row = base.advanced(by: (h / 2) * bpr)
        let x = w / 2
        switch fmt {
        case kCVPixelFormatType_OneComponent32Float, kCVPixelFormatType_DepthFloat32:
            return row.assumingMemoryBound(to: Float.self)[x]
        case kCVPixelFormatType_OneComponent16Half, kCVPixelFormatType_DepthFloat16:
            return Float(row.assumingMemoryBound(to: Float16.self)[x])
        default:
            return Float(row.assumingMemoryBound(to: UInt8.self)[x]) / 255.0
        }
    }
}
