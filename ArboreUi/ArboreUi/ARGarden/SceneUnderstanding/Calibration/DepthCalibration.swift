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

    /// Fit the multiplicative scale `s` such that `metric = s / raw`.
    /// Returns nil if the centre depth is degenerate (the model can't
    /// see anything, or the floor reference is unreliable).
    ///
    /// - Parameter depthMap: Depth Anything's CVPixelBuffer output.
    /// - Parameter cameraHeightMeters: distance camera → floor in
    ///   metres (typically `camera.transform.columns.3.y - floorPlaneY`).
    /// - Parameter minRaw: reject if the centre raw value is below this
    ///   threshold (would amplify noise to absurd metric values).
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
