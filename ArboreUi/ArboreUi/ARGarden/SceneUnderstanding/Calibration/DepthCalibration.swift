import CoreVideo
import Foundation
import simd

/// Calibrates Depth Anything V2's relative inverse-depth output to
/// **metric meters** using a 2-parameter affine model fitted against
/// world-space anchor points known via ARKit (cf #187, #190).
///
/// The model is :
///
///     1 / metric = a · raw + b
///
/// equivalently `metric = 1 / (a · raw + b)`. The two parameters `(a, b)`
/// are fitted by least squares on a set of `(raw, knownMetric)` pairs
/// where `knownMetric` comes from projecting an ARKit anchor (plane
/// centroid, raw feature point, etc.) into the depth image.
///
/// Compared to the old single-scalar fit (`metric = scale / raw`), this :
///  - uses many anchors per frame instead of one (robust to a single bad
///    floor anchor centroid that happens to project on a wall mask)
///  - models the depth network's potential offset bias correctly
///  - allows continuous re-fitting per tick without locking onto an
///    early bad calibration (which was the source of `inverseScale=0.32`
///    on device when the floor centroid projection failed)
///
/// RANSAC + temporal median smoothing on top of this is tracked in #190.
enum DepthCalibration {

    // MARK: - Affine fit

    /// Two-parameter affine model. `metric(raw:)` is the only call site
    /// the rest of the pipeline needs.
    struct AffineFit: Equatable {
        /// `metric = 1 / (a · raw + b)`. `a` is the slope of inverse
        /// depth against raw model output.
        let a: Float
        let b: Float

        /// Convenience for callers that still think in terms of the old
        /// single-scale API : when `b == 0` we have `metric = (1/a) / raw`,
        /// so `inverseScale = 1/a`. Used for the device-side log and
        /// the DepthOverlay's metric range mapping.
        var equivalentInverseScale: Float? {
            guard a != 0, abs(a) > 1e-6 else { return nil }
            return 1 / a
        }

        func metric(raw: Float) -> Float {
            let den = a * raw + b
            guard abs(den) > 1e-6 else { return .infinity }
            return 1 / den
        }
    }

    /// One observation : raw value sampled from the depth model + the
    /// metric distance we know from ARKit.
    struct Sample {
        let raw: Float
        let metric: Float
    }

    /// Convert a single raw depth value to metric meters using the
    /// previously fitted affine model. Pipe-friendly with `SceneFusion`
    /// + `VoxelAccumulator` which already pass a `fit` through.
    static func metric(raw: Float, fit: AffineFit) -> Float {
        fit.metric(raw: raw)
    }

    /// Solves `1/metric = a·raw + b` by ordinary least squares on `samples`.
    ///
    /// - Returns `nil` if `samples.count < 2` (under-determined) or the
    ///   normal equations are singular (e.g. all samples have the same
    ///   raw value — no variance, can't fit a slope).
    /// - With exactly 2 samples we still solve, but the fit is brittle ;
    ///   the caller typically wants at least 5 to absorb noise.
    static func fitAffine(samples: [Sample]) -> AffineFit? {
        guard samples.count >= 2 else { return nil }
        // Solve A·[a;b] = y where each row of A is [raw_i, 1] and
        // y_i = 1/metric_i. Normal equations : (A^T A)·x = A^T y.
        var sumRR: Float = 0, sumR: Float = 0
        var sumI: Float = 0, sumRI: Float = 0
        let n = Float(samples.count)
        for s in samples {
            guard s.metric > 0.01 else { continue }
            let invM = 1 / s.metric
            sumRR += s.raw * s.raw
            sumR += s.raw
            sumI += invM
            sumRI += s.raw * invM
        }
        // det = n·ΣR² − (ΣR)². Zero means all raws are identical.
        let det = n * sumRR - sumR * sumR
        guard abs(det) > 1e-6 else { return nil }
        let a = (n * sumRI - sumR * sumI) / det
        let b = (sumRR * sumI - sumR * sumRI) / det
        guard a.isFinite, b.isFinite else { return nil }
        return AffineFit(a: a, b: b)
    }

    /// RANSAC variant of `fitAffine` — robust to outliers (cf #190
    /// Niveau 3). For `iterations` rounds, picks 2 random samples,
    /// fits a candidate model, counts the inliers (samples whose
    /// predicted metric is within `inlierMetricRatio` of observed),
    /// keeps the model with the most inliers, then re-fits by LS on
    /// the best inlier set.
    ///
    /// Returns nil if `samples.count < 4` (no outlier rejection
    /// possible) — caller falls back to `fitAffine` in that case.
    /// Also returns nil if no model reaches `minInliers` inliers.
    static func fitAffineRANSAC(
        samples: [Sample],
        iterations: Int = 50,
        inlierMetricRatio: Float = 0.20,
        minInliers: Int = 5
    ) -> (fit: AffineFit, inlierCount: Int)? {
        // Below 4 samples RANSAC isn't useful — fall back to plain LS.
        if samples.count < 4 {
            return fitAffine(samples: samples).map { ($0, samples.count) }
        }

        var bestInliers: [Sample] = []
        for _ in 0..<iterations {
            let i = Int.random(in: 0..<samples.count)
            var j = Int.random(in: 0..<samples.count)
            while j == i { j = Int.random(in: 0..<samples.count) }
            guard let candidate = fitAffine(samples: [samples[i], samples[j]]) else { continue }

            var inliers: [Sample] = []
            for s in samples {
                let predicted = candidate.metric(raw: s.raw)
                guard predicted.isFinite, predicted > 0.05, predicted < 50 else { continue }
                let err = abs(predicted - s.metric) / s.metric
                if err < inlierMetricRatio {
                    inliers.append(s)
                }
            }
            if inliers.count > bestInliers.count {
                bestInliers = inliers
            }
        }

        guard bestInliers.count >= minInliers else { return nil }
        guard let refined = fitAffine(samples: bestInliers) else { return nil }
        return (refined, bestInliers.count)
    }

    // MARK: - Sample collection

    /// Project each world anchor into the depth image and pair it with
    /// the raw depth observed at that pixel. Rejects anchors that fall
    /// outside the FoV, behind the camera, too close, or have a
    /// degenerate raw reading. The return value is what
    /// `fitAffine(samples:)` expects.
    ///
    /// - Parameter maxDistance: ignore anchors farther than this (8m by
    ///   default). DA V2 confidence drops off past ~10m and farther
    ///   anchors dominate the LS fit with large residuals.
    static func collectSamples(
        depthMap: CVPixelBuffer,
        worldAnchors: [SIMD3<Float>],
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        captureSize: CGSize,
        minRaw: Float = 0.001,
        maxDistance: Float = 8.0
    ) -> [Sample] {
        guard !worldAnchors.isEmpty else { return [] }

        let invCam = cameraTransform.inverse
        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        let cx = intrinsics[2, 0]
        let cy = intrinsics[2, 1]
        let depthW = CVPixelBufferGetWidth(depthMap)
        let depthH = CVPixelBufferGetHeight(depthMap)
        let captureW = Float(captureSize.width)
        let captureH = Float(captureSize.height)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return [] }
        let bpr = CVPixelBufferGetBytesPerRow(depthMap)
        let fmt = CVPixelBufferGetPixelFormatType(depthMap)

        var samples: [Sample] = []
        samples.reserveCapacity(worldAnchors.count)
        for world in worldAnchors {
            let cam4 = invCam * SIMD4<Float>(world, 1)
            // ARKit camera looks toward -Z. Skip points behind or
            // grazing the lens.
            guard cam4.z < -0.1 else { continue }
            let dist = simd_length(SIMD3<Float>(cam4.x, cam4.y, cam4.z))
            guard dist > 0.3, dist < maxDistance else { continue }

            let camZ = -cam4.z   // positive depth to image plane
            let u = fx * (cam4.x / camZ) + cx
            let v = fy * (-cam4.y / camZ) + cy   // image v points down
            // Project capture-coord pixel into depth-buffer coords.
            let dx = Int(u / captureW * Float(depthW))
            let dy = Int(v / captureH * Float(depthH))
            guard dx >= 0, dx < depthW, dy >= 0, dy < depthH else { continue }

            let raw = DepthPixelBufferAccess.sampleRaw(
                x: dx, y: dy, base: base,
                bytesPerRow: bpr, format: fmt,
                width: depthW, height: depthH
            )
            guard raw > minRaw, raw.isFinite else { continue }
            samples.append(Sample(raw: raw, metric: dist))
        }
        return samples
    }
}
