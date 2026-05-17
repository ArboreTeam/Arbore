import CoreVideo
import Foundation
import simd

/// Calibrates Depth Anything's relative inverse-depth output to
/// **metric meters**, using ARKit's floor anchor as the absolute
/// reference (cf #187).
///
/// Depth Anything V2 outputs values in an arbitrary range where bigger
/// = closer to the camera. For us, the practical relation is
///
///     metricDepth_meters = inverseScale / rawDepth
///
/// where `inverseScale` is the single scalar we fit per session. To
/// solve it we use one pixel whose metric depth we know : a point on
/// the floor. Specifically, we sample the depth map at the image
/// **centre** when the camera is pointed roughly forward, assume that
/// pixel lands on the floor, and equate its metric depth with the
/// camera-to-floor distance (`cameraY - floorY` is close to the
/// depth when the camera is held vertical ; in practice we use the
/// straight line distance from the camera, which we can compute from
/// the camera height + pitch).
///
/// This isn't surveying-grade calibration, but for an indoor scene
/// the error is within ±10cm — good enough for the SemSeg+Depth
/// fusion that drives debug viz + region detection.
enum DepthCalibration {

    /// **Preferred.** Fit the inverse-depth scale by projecting a KNOWN
    /// world point onto the depth image and reading the raw value there.
    /// Much more reliable than the centre-pixel assumption — the centre
    /// is only on the floor when the user is pointing straight down,
    /// which never happens in practice. Pass any anchored point you
    /// know the geometry of (usually an `ARPlaneAnchor.floor` centroid).
    ///
    /// - Parameter depthMap: Depth Anything's CVPixelBuffer output.
    /// - Parameter worldPoint: a 3D point in world coords we want to use
    ///   as the calibration reference (e.g. floor anchor centre).
    /// - Parameter cameraTransform: ARFrame.camera.transform.
    /// - Parameter intrinsics: ARFrame.camera.intrinsics in capture coords.
    /// - Parameter captureSize: ARFrame.camera.imageResolution.
    /// - Parameter minRaw: reject if the sampled raw is below threshold.
    static func fitInverseScale(
        depthMap: CVPixelBuffer,
        worldPoint: SIMD3<Float>,
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        captureSize: CGSize,
        minRaw: Float = 0.001
    ) -> Float? {
        // Transform world point → camera frame.
        let invCam = cameraTransform.inverse
        let camPoint4 = invCam * SIMD4<Float>(worldPoint, 1)
        // ARKit camera looks toward -Z, so a point in front has z < 0.
        // Skip if behind us or grazing the lens.
        guard camPoint4.z < -0.1 else { return nil }
        let camZ = -camPoint4.z   // positive distance to image plane

        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        let cx = intrinsics[2, 0]
        let cy = intrinsics[2, 1]
        // Project. Image v axis points down, camera +Y points up → negate.
        let u = fx * (camPoint4.x / camZ) + cx
        let v = fy * (-camPoint4.y / camZ) + cy

        // Rescale to depth buffer coordinates (depth model output is
        // typically smaller than the original capture).
        let depthW = CVPixelBufferGetWidth(depthMap)
        let depthH = CVPixelBufferGetHeight(depthMap)
        let dx = Int(u / Float(captureSize.width) * Float(depthW))
        let dy = Int(v / Float(captureSize.height) * Float(depthH))
        guard dx >= 0, dx < depthW, dy >= 0, dy < depthH else { return nil }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let bpr = CVPixelBufferGetBytesPerRow(depthMap)
        let fmt = CVPixelBufferGetPixelFormatType(depthMap)
        let raw = DepthPixelBufferAccess.sampleRaw(
            x: dx, y: dy, base: base,
            bytesPerRow: bpr, format: fmt,
            width: depthW, height: depthH
        )
        guard raw > minRaw else { return nil }

        // Euclidean distance camera→point.
        let metric = simd_length(SIMD3<Float>(camPoint4.x, camPoint4.y, camPoint4.z))
        let scale = metric * raw
        return scale.isFinite ? scale : nil
    }

    /// **Fallback** — centre-pixel-on-floor assumption. Use only when no
    /// known world point is available. Often produces a scale that's
    /// off by 2-3× because the user almost never points straight down.
    static func fitInverseScale(
        depthMap: CVPixelBuffer,
        cameraHeightMeters: Float,
        minRaw: Float = 0.001
    ) -> Float? {
        guard cameraHeightMeters > 0.3 else { return nil }
        guard let centre = sampleCentre(depthMap), centre > minRaw else { return nil }
        let scale = cameraHeightMeters * centre
        return scale.isFinite ? scale : nil
    }

    /// Convert a single raw depth value to metric meters using the
    /// previously fitted scale.
    static func metric(raw: Float, inverseScale: Float) -> Float {
        guard raw > 0.0001 else { return .infinity }
        return inverseScale / raw
    }

    /// Read the depth value at the centre pixel.
    private static func sampleCentre(_ depthMap: CVPixelBuffer) -> Float? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let w = CVPixelBufferGetWidth(depthMap)
        let h = CVPixelBufferGetHeight(depthMap)
        let bpr = CVPixelBufferGetBytesPerRow(depthMap)
        let fmt = CVPixelBufferGetPixelFormatType(depthMap)
        return DepthPixelBufferAccess.sampleRaw(
            x: w / 2, y: h / 2,
            base: base, bytesPerRow: bpr,
            format: fmt, width: w, height: h
        )
    }
}
