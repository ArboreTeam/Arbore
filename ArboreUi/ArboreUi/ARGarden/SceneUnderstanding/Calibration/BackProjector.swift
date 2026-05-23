import Foundation
import simd

/// Converts (image pixel, metric depth) into a 3D world-space position
/// using ARKit's `ARFrame.camera` intrinsics + transform.
///
/// ARKit cameras follow the convention :
///   - intrinsics is a 3×3 matrix (column-major in Swift) giving `[fx 0 cx; 0 fy cy; 0 0 1]`
///     in the **original capture coordinate** space (pixels of `imageResolution`).
///   - the camera transform places the camera origin in world space ;
///     local axes are +X right, +Y up, **-Z forward**.
///   - image pixel (u, v) origin is top-left, +u right, +v down. We
///     negate the camera-space Y to align with ARKit's convention.
///
/// Use case : after fusing a SemSeg label and a metric depth, project
/// each labelled pixel to a 3D world coordinate so we can build labelled
/// 3D regions (`SceneRegion`).
enum BackProjector {

    /// Project one pixel `(u, v)` with metric depth `dMetric` into world
    /// space. `u, v` are in the same coordinate space as `intrinsics` —
    /// i.e. expressed in the `captureSize` resolution.
    ///
    /// - Parameter intrinsics: `ARFrame.camera.intrinsics`
    /// - Parameter cameraTransform: `ARFrame.camera.transform`
    /// - Parameter u, v: pixel coords in the original capture resolution
    /// - Parameter dMetric: metric depth in meters (positive)
    static func worldPosition(
        u: Float, v: Float, dMetric: Float,
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4
    ) -> SIMD3<Float> {
        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        let cx = intrinsics[2, 0]
        let cy = intrinsics[2, 1]

        let camX = (u - cx) * dMetric / fx
        let camY = (v - cy) * dMetric / fy
        // Image's +v points down ; ARKit camera +Y is up → negate.
        // Camera looks toward -Z, so a pixel at depth `d` sits at z=-d.
        let camSpace = SIMD4<Float>(camX, -camY, -dMetric, 1)
        let worldSpace = cameraTransform * camSpace
        return SIMD3<Float>(worldSpace.x, worldSpace.y, worldSpace.z)
    }

    /// Rescale intrinsics measured against `originalSize` into the
    /// coordinate space of `targetSize`. Useful when sampling a smaller
    /// depth/seg map than the original capture : ARKit gives intrinsics
    /// in capture pixels, but the model output is at a different
    /// resolution. The scale ratios cancel out the FoV mismatch.
    static func scaledIntrinsics(
        _ intrinsics: simd_float3x3,
        from originalSize: CGSize,
        to targetSize: CGSize
    ) -> simd_float3x3 {
        let sx = Float(targetSize.width / originalSize.width)
        let sy = Float(targetSize.height / originalSize.height)
        var k = intrinsics
        k[0, 0] *= sx   // fx
        k[1, 1] *= sy   // fy
        k[2, 0] *= sx   // cx
        k[2, 1] *= sy   // cy
        return k
    }
}
