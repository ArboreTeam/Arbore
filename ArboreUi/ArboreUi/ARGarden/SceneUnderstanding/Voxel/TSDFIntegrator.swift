import CoreVideo
import Foundation
import simd

/// Per-frame ray-cast integration into a `TSDFGrid` (cf #189).
///
/// We sample the depth image at a coarse stride, back-project each
/// pixel into a world-space ray from the camera, then walk the ray
/// over a band of `±truncationDistance` around the observed depth.
/// Every voxel the ray hits gets one TSDF observation = `observed -
/// distanceAlongRay`. Repeated across many frames from different
/// viewpoints, the per-voxel weighted average converges to the true
/// signed distance and the iso-surface `tsdf=0` becomes the
/// reconstructed mesh.
///
/// Why ray-cast (vs voxel-iterate-in-frustum) :
///  - O(pixels × ray_steps) instead of O(voxels in frustum)
///  - typical 64×64 grid × ~10 steps = 40k updates per tick, easy on CPU
///  - automatically handles sparse coverage (we only touch voxels the
///    depth model can see, no wasted work on occluded regions)
enum TSDFIntegrator {

    /// Pixel stride along the SemanticMap when sampling rays. Stride 8
    /// on a 448×448 input = 56×56 = ~3100 rays per tick, comparable to
    /// the voxel-cloud accumulator.
    static let pixelStride = 8

    /// Minimum metric distance for any voxel we update — never march
    /// through the lens. 30 cm matches `validMetricRange.lowerBound`.
    private static let nearClip: Float = 0.30

    /// Half-voxel step relative to a grid's voxelSize is computed at
    /// call time (we need access to `grid.voxelSize`).

    /// Weight assigned to a single carve observation. Lower than the
    /// surface observation weight (1.0) so that one in-band on-surface
    /// observation outweighs ~3 carve observations from neighbouring
    /// rays whose noisy depth wrongly classifies this voxel as empty.
    /// Without this asymmetry, ±20 cm DA V2 noise between adjacent
    /// pixels erodes real surfaces by the time a few ticks have run
    /// (cf #189 follow-up B post-mortem on the device test).
    private static let carveWeight: Float = 0.3

    /// Carve band depth, in units of `truncationDistance`. The carve
    /// march covers `[metric - carveBandMultiplier · truncation,
    ///                 metric - truncation]` — i.e. just in front of
    /// the surface band. 2× keeps the corridor narrow enough that
    /// the depth-noise level (±20 cm) on adjacent rays doesn't tank
    /// real surfaces.
    private static let carveBandMultiplier: Float = 2.0

    static func integrate(
        into grid: TSDFGrid,
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

        // Intrinsics in SemSeg pixel space — both maps align after the
        // model's internal resize.
        let segIntrinsics = BackProjector.scaledIntrinsics(
            intrinsics,
            from: captureSize,
            to: CGSize(width: segW, height: segH)
        )
        let fx = segIntrinsics[0, 0]
        let fy = segIntrinsics[1, 1]
        let cx = segIntrinsics[2, 0]
        let cy = segIntrinsics[2, 1]

        let depthW = CVPixelBufferGetWidth(depthMap)
        let depthH = CVPixelBufferGetHeight(depthMap)
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let depthBpr = CVPixelBufferGetBytesPerRow(depthMap)
        let depthFmt = CVPixelBufferGetPixelFormatType(depthMap)

        let cameraOrigin = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        let halfStep = grid.voxelSize * 0.5
        let truncation = grid.truncationDistance

        for r in Swift.stride(from: 0, to: segH, by: pixelStride) {
            let dRow = min(Int(Float(r) / Float(segH) * Float(depthH)), depthH - 1)
            for c in Swift.stride(from: 0, to: segW, by: pixelStride) {
                let dCol = min(Int(Float(c) / Float(segW) * Float(depthW)), depthW - 1)

                let raw = DepthPixelBufferAccess.sampleRaw(
                    x: dCol, y: dRow,
                    base: depthBase, bytesPerRow: depthBpr,
                    format: depthFmt, width: depthW, height: depthH
                )
                let metric = fit.metric(raw: raw)
                guard SceneFusion.validMetricRange.contains(metric) else { continue }

                // Build world-space ray direction for this pixel
                // (camera-frame ray, then rotate to world).
                let u = Float(c)
                let v = Float(r)
                let xCam = (u - cx) / fx
                let yCam = -(v - cy) / fy
                let dirCam = SIMD4<Float>(xCam, yCam, -1, 0)
                let dirWorld4 = cameraTransform * dirCam
                let dirWorld = simd_normalize(SIMD3<Float>(dirWorld4.x, dirWorld4.y, dirWorld4.z))

                // Resolve category once per ray.
                let rawId = Int(semanticMap.pixels[scalarAt: [r, c]])
                let label = semanticMap.labels[rawId] ?? ""
                let cat = COCOPanopticCategory.category(for: label)
                let catIndex: Int8? = (cat == .other) ? nil : Int8(cat.indexInAllCases)

                // Two-band march along the ray :
                //   1. Surface band [metric - trunc, metric + trunc]
                //      with weight 1.0 + category vote — this is the
                //      classic TSDF integration.
                //   2. Carve band [metric - 2·trunc, metric - trunc]
                //      with weight 0.3 and no category — pulls existing
                //      ghost voxels toward "definitely empty" without
                //      eroding real surfaces (the surface band's full-
                //      weight observations dominate the running
                //      average — see TSDFGrid.integrate doc).
                // The step is half a voxel so we don't skip voxels
                // when the ray grazes a cell boundary.

                // 1. Surface band.
                let surfStart = metric - truncation
                let surfEnd = metric + truncation
                var t = surfStart
                while t <= surfEnd {
                    if t > nearClip {
                        let world = cameraOrigin + dirWorld * t
                        let key = grid.quantize(world)
                        let sdf = metric - t
                        grid.integrate(key: key, sdf: sdf, weight: 1.0,
                                       categoryIndex: catIndex, now: now)
                    }
                    t += halfStep
                }

                // 2. Carve band.
                let carveStart = max(nearClip, metric - carveBandMultiplier * truncation)
                let carveEnd = metric - truncation
                t = carveStart
                while t < carveEnd {
                    let world = cameraOrigin + dirWorld * t
                    let key = grid.quantize(world)
                    let sdf = metric - t   // large positive, clamped to +trunc in integrate
                    grid.integrate(key: key, sdf: sdf, weight: carveWeight,
                                   categoryIndex: nil, now: now)
                    t += halfStep
                }
            }
        }
    }
}
