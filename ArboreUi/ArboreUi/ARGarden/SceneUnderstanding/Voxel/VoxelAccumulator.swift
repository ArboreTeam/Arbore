import CoreVideo
import Foundation
import UIKit
import simd

/// Per-pixel back-projection that drops each labelled point into a 3D
/// `VoxelGrid` keyed by quantised world position. Runs as a side-pass
/// alongside `SceneFusion.fuse` at the controller's tick cadence.
///
/// Extracted from `SceneUnderstandingController` (cf #188 P2.2) so that
/// the controller stays an orchestrator and the back-projection logic
/// lives next to the rest of the fusion math.
enum VoxelAccumulator {

    /// Stride between sampled pixels. 8 = ~3000 voxels per frame on a
    /// 448×448 input — gentle enough not to tank framerate building 200k
    /// cells in a single tick, dense enough to fill a room in seconds.
    static let pixelStride = 8

    /// Accumulate one frame's worth of voxels into `grid`. The grid's
    /// internal lock makes this safe to call from a worker thread.
    static func accumulate(
        into grid: VoxelGrid,
        semanticMap: SemanticMap,
        depthMap: CVPixelBuffer,
        fit: DepthCalibration.AffineFit,
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

        for r in Swift.stride(from: 0, to: segH, by: pixelStride) {
            let dRow = min(Int(Float(r) / Float(segH) * Float(depthH)), depthH - 1)
            for c in Swift.stride(from: 0, to: segW, by: pixelStride) {
                let dCol = min(Int(Float(c) / Float(segW) * Float(depthW)), depthW - 1)
                let raw = DepthPixelBufferAccess.sampleRaw(
                    x: dCol, y: dRow,
                    base: depthBase, bytesPerRow: depthBpr,
                    format: depthFmt, width: depthW, height: depthH
                )
                let metric = DepthCalibration.metric(raw: raw, fit: fit)
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
                // We pass the category index (1 byte) instead of the
                // resolved colour : the grid keeps a per-cell vote
                // histogram and the overlay resolves the winning
                // category to colour at render time (cf #189 #3).
                let idx = cat.indexInAllCases
                guard idx >= 0, idx < Int(Int8.max) else { continue }
                grid.insert(point: world,
                            categoryIndex: Int8(idx),
                            now: now)
            }
        }
    }
}
