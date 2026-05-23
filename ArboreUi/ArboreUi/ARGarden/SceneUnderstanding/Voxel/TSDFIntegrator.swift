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

    /// Outer reach of the photometric-gated carve, in units of
    /// `truncationDistance`. The "near carve" covers
    /// `[metric - nearCarveMultiplier · truncation, metric - truncation]`
    /// — voxels close enough to the measured surface that they could
    /// plausibly be a real surface the depth model just missed by a
    /// few cm of noise. Photometric gating (below) preserves them
    /// when their accumulated colour matches the live camera RGB.
    private static let nearCarveMultiplier: Float = 3.0

    /// Photometric carve gate (#189 follow-up C). When a near-carve
    /// observation hits an existing cell, compare the camera RGB at
    /// this ray's pixel to the cell's accumulated colour. If they
    /// agree within `photometricThreshold` (Euclidean distance in
    /// linear RGB ∈ [0, 1]), the voxel is plausibly a real surface
    /// that current-frame depth missed (or it's the same material
    /// occluding itself across viewpoints) — skip the carve to
    /// preserve real surfaces. Only applies once the cell has at
    /// least `photometricMinWeight` accumulated observations, so a
    /// freshly seeded ghost cell doesn't shield itself from carving
    /// using its own first noisy colour sample.
    ///
    /// The gate is INTENTIONALLY restricted to the near-carve band.
    /// Voxels much farther in front of the measured surface (i.e. in
    /// the far-carve band, see below) cannot reasonably be a missed
    /// surface — they are free space, and the gate would only let
    /// ghost-walls of the same material as the real wall behind them
    /// persist indefinitely (cf user device test 2026-05-17).
    private static let photometricThreshold: Float = 0.25
    private static let photometricMinWeight: Float = 2.0

    static func integrate(
        into grid: TSDFGrid,
        semanticMap: SemanticMap,
        depthMap: CVPixelBuffer,
        capturedImage: CVPixelBuffer?,
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

        // Optional captured image (YCbCr biplanar) for photometric
        // colour sampling. Locked once per tick — sampling per pixel
        // is just a pointer offset. If absent (or lock fails) we run
        // the integrator without colour, falling back to the pre-C
        // behaviour : surface obs without colour, carve obs without
        // photometric gating. The pipeline still works.
        var captureCtx: CaptureSamplerContext? = nil
        if let capturedImage = capturedImage {
            captureCtx = CaptureSamplerContext.lock(capturedImage)
        }
        defer { captureCtx?.unlock() }

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
                let metricZ = fit.metric(raw: raw)
                guard SceneFusion.validMetricRange.contains(metricZ) else { continue }

                // Build world-space ray direction for this pixel
                // (camera-frame ray, then rotate to world).
                let u = Float(c)
                let v = Float(r)
                let xCam = (u - cx) / fx
                let yCam = -(v - cy) / fy
                let dirCam = SIMD4<Float>(xCam, yCam, -1, 0)
                let dirWorld4 = cameraTransform * dirCam
                let dirWorld = simd_normalize(SIMD3<Float>(dirWorld4.x, dirWorld4.y, dirWorld4.z))
                // Convert Z-depth (perpendicular distance to image
                // plane, what `fit.metric` actually returns) to
                // Euclidean ray length along this pixel's direction.
                // K = |(xCam, yCam, -1)| = √(1 + xCam² + yCam²) → 1
                // at the principal point, ~1.18 at iPhone wide-FoV
                // corners. Pre-fix we baked an averaged K into the
                // affine fit and used the result as ray length — that
                // placed off-axis surfaces 5-15 % too close
                // (device post-mortem 2026-05-17).
                let kFactor = sqrt(1 + xCam * xCam + yCam * yCam)
                let metric = metricZ * kFactor

                // Resolve category once per ray.
                let rawId = Int(semanticMap.pixels[scalarAt: [r, c]])
                let label = semanticMap.labels[rawId] ?? ""
                let cat = COCOPanopticCategory.category(for: label)
                let catIndex: Int8? = (cat == .other) ? nil : Int8(cat.indexInAllCases)

                // Sample camera RGB once per ray. All voxels touched
                // by this ray share the same pixel and therefore the
                // same camera colour observation. nil when there's no
                // captured image (test path / older callers).
                let rayColor: SIMD3<Float>? = captureCtx?.sampleRGB(
                    segCol: c, segRow: r,
                    segWidth: segW, segHeight: segH
                )

                // March along the ray in three regions :
                //   1. Surface band — weight 1.0, seeds new cells.
                //   2. Near carve   — photometric-gated, weight 0.3.
                //   3. Far carve    — existing cells only, weight 0.3,
                //                     no photometric gate.
                // Step is half a voxel so we don't skip voxels when
                // the ray grazes a cell boundary.

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
                                       color: rayColor,
                                       categoryIndex: catIndex, now: now)
                    }
                    t += halfStep
                }

                // 2. Two-stage carve in front of the surface band :
                //  - Far carve `[nearClip, metric - nearCarveMultiplier · trunc]`
                //    Voxels this far in front of the measured surface
                //    cannot reasonably be a "missed real surface".
                //    They are free space. We carve ONLY existing cells
                //    (don't seed new ones here — that's the surface
                //    band's job), with NO photometric gate. This is
                //    what actually dissolves stale ghost walls that
                //    appeared during early depth-calibration noise,
                //    even when their accumulated colour matches the
                //    live camera RGB (which it usually does, because
                //    a ghost wall and the real wall behind it are the
                //    same physical surface — see device post-mortem
                //    2026-05-17).
                //  - Near carve `[metric - nearCarveMultiplier · trunc,
                //                 metric - trunc]`
                //    Photometric-gated. A voxel here might still be a
                //    real surface the depth model missed by a few cm
                //    of noise. The colour check prevents eroding it.
                let nearCarveOuter = max(nearClip, metric - nearCarveMultiplier * truncation)
                let nearCarveInner = metric - truncation

                // Far carve.
                t = nearClip
                while t < nearCarveOuter {
                    let world = cameraOrigin + dirWorld * t
                    let key = grid.quantize(world)
                    if grid.cell(at: key) != nil {
                        let sdf = metric - t   // large positive, clamped to +trunc in integrate
                        grid.integrate(key: key, sdf: sdf, weight: carveWeight,
                                       color: nil,
                                       categoryIndex: nil, now: now)
                    }
                    t += halfStep
                }

                // Near carve.
                t = nearCarveOuter
                while t < nearCarveInner {
                    let world = cameraOrigin + dirWorld * t
                    let key = grid.quantize(world)
                    var allowCarve = true
                    if let rayColor = rayColor,
                       let existing = grid.cell(at: key),
                       existing.weight >= photometricMinWeight {
                        let colorDist = simd_distance(existing.color, rayColor)
                        if colorDist < photometricThreshold {
                            allowCarve = false
                        }
                    }
                    if allowCarve {
                        let sdf = metric - t
                        grid.integrate(key: key, sdf: sdf, weight: carveWeight,
                                       color: nil,
                                       categoryIndex: nil, now: now)
                    }
                    t += halfStep
                }
            }
        }
    }
}
