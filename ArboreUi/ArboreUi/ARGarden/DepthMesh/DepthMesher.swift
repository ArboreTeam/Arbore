import ARKit
import CoreVideo
import Foundation
import simd

/// Triangle mesh produced by back-projecting a depth map into world space.
///
/// Vertex/index buffers are laid out so the result can be fed directly into
/// an `SCNGeometry` (positions + per-vertex SCNGeometryElement of triangles).
/// The `triangleAdjacency` precomputes, for each triangle, the index of its
/// up-to-3 neighbours sharing an edge — used by the connected-component
/// labelling step in `DepthMeshVizRenderer`.
struct DepthMesh {
    /// World-space positions, one per grid cell on the downsampled depth map.
    let vertices: [SIMD3<Float>]
    /// Triangle indices into `vertices`, 3 per triangle.
    let triangleIndices: [UInt32]
    /// triangleAdjacency[t] = up to 3 neighbour-triangle indices (or -1 if none).
    let triangleAdjacency: [SIMD3<Int32>]

    var triangleCount: Int { triangleIndices.count / 3 }
}

/// Builds a `DepthMesh` from a depth pixel buffer + camera pose/intrinsics.
///
/// The depth buffer is **assumed inverse-depth** (Depth Anything V2 convention)
/// and is converted to metric using `inverseScale` (`metric = inverseScale / raw`).
/// Pixels with `raw < epsilon` (sky / far) are dropped.
///
/// Downsampling : we sample the depth map every `stride` pixels in both axes
/// (default 8 → ~85×64 vertex grid for a 686×518 input). That keeps the
/// triangle count below ~10k, low enough that SceneKit renders smoothly and
/// connected-components runs in <10ms.
enum DepthMesher {
    /// Triangle stride 1 (8px ≈ 1cm at 50cm range with 1080p cam, plenty).
    static let defaultStride = 8
    /// Reject depth pixels closer than this — almost certainly noise / lens.
    static let minMetricDepth: Float = 0.15
    /// Reject anything beyond — likely the sky / a window into the void.
    static let maxMetricDepth: Float = 8.0
    /// Reject triangles whose vertices span more than this metric distance
    /// in depth — usually a silhouette edge where the model interpolates
    /// across a "cliff", giving a fake skirt-like triangle.
    static let maxEdgeDepthJump: Float = 0.4

    /// Build the mesh.
    ///
    /// - Parameters:
    ///   - depth: output of `DepthPredictor.predict` (kCVPixelFormatType_OneComponent16Half
    ///     or Float32 depending on the .mlpackage). Both handled.
    ///   - intrinsics: `ARFrame.camera.intrinsics` — focal/principal point
    ///     in the *original capture* coordinate space. We rescale to depth
    ///     buffer pixel space internally.
    ///   - captureSize: `ARFrame.camera.imageResolution` — width/height
    ///     of the camera image the intrinsics were measured against.
    ///   - cameraTransform: `ARFrame.camera.transform` — camera-to-world.
    ///   - inverseScale: `s` such that `metric = s / raw`. See
    ///     `DepthCalibration.fitInverseScale` for how this is obtained.
    ///   - stride: pixel stride between sampled vertices (>= 1).
    static func build(
        depth: CVPixelBuffer,
        intrinsics: simd_float3x3,
        captureSize: CGSize,
        cameraTransform: simd_float4x4,
        inverseScale: Float,
        stride: Int = defaultStride
    ) -> DepthMesh? {
        let width = CVPixelBufferGetWidth(depth)
        let height = CVPixelBufferGetHeight(depth)
        guard width > 0, height > 0, stride > 0 else { return nil }

        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }

        guard let raw = CVPixelBufferGetBaseAddress(depth) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depth)
        let format = CVPixelBufferGetPixelFormatType(depth)

        // Rescale ARKit intrinsics (in original captureSize coord) into the
        // depth buffer's coord — they have the same FoV, only resolution differs.
        let sx = Float(width) / Float(captureSize.width)
        let sy = Float(height) / Float(captureSize.height)
        let fx = intrinsics[0, 0] * sx
        let fy = intrinsics[1, 1] * sy
        let cx = intrinsics[2, 0] * sx
        let cy = intrinsics[2, 1] * sy

        // Build the vertex grid. `vertexIndex[r][c]` is the index in `vertices`
        // for the sample at (row r, col c), or -1 if the depth was rejected.
        let gridCols = (width  + stride - 1) / stride
        let gridRows = (height + stride - 1) / stride
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(gridCols * gridRows)
        var vertexIndex = [[Int32]](repeating: [Int32](repeating: -1, count: gridCols),
                                     count: gridRows)
        var metricDepthAt: [[Float]] = [[Float]](repeating: [Float](repeating: 0, count: gridCols),
                                                  count: gridRows)

        for r in 0..<gridRows {
            let y = min(r * stride, height - 1)
            for c in 0..<gridCols {
                let x = min(c * stride, width - 1)
                let rawValue = sampleDepth(at: x, y: y, base: raw,
                                            bytesPerRow: bytesPerRow,
                                            format: format)
                guard rawValue > 0.0001 else { continue }
                let metric = inverseScale / rawValue
                guard metric >= minMetricDepth, metric <= maxMetricDepth else { continue }

                // Back-project pixel (x, y, metric) into camera space, then world.
                let camX = (Float(x) - cx) * metric / fx
                let camY = (Float(y) - cy) * metric / fy
                // ARKit camera convention: +X right, +Y up, -Z forward.
                // The image's +Y axis points down ⇒ camY is negated.
                let camSpace = SIMD4<Float>(camX, -camY, -metric, 1)
                let worldSpace = cameraTransform * camSpace
                vertices.append(SIMD3<Float>(worldSpace.x, worldSpace.y, worldSpace.z))
                vertexIndex[r][c] = Int32(vertices.count - 1)
                metricDepthAt[r][c] = metric
            }
        }

        // Emit triangles. For each 2×2 cell we emit up to 2 triangles
        // (top-left + bottom-right diagonal). A triangle is rejected if any
        // of its vertices is missing OR if the edge depth jump is too big.
        var triangleIndices: [UInt32] = []
        triangleIndices.reserveCapacity(gridRows * gridCols * 6)

        // We also build a (row, col, diag) → triangleIndex lookup so we can
        // compute triangleAdjacency in a second pass. Diag 0 = upper-left,
        // 1 = lower-right. Negative = no triangle emitted at that cell.
        var triKey = [Int: Int32]()
        triKey.reserveCapacity(gridRows * gridCols * 2)

        func cellKey(_ r: Int, _ c: Int, _ diag: Int) -> Int {
            (r * gridCols + c) * 2 + diag
        }
        func depthJumpOK(_ d0: Float, _ d1: Float, _ d2: Float) -> Bool {
            let m = max(abs(d0 - d1), max(abs(d1 - d2), abs(d0 - d2)))
            return m < maxEdgeDepthJump
        }

        for r in 0..<(gridRows - 1) {
            for c in 0..<(gridCols - 1) {
                let tl = vertexIndex[r][c]
                let tr = vertexIndex[r][c + 1]
                let bl = vertexIndex[r + 1][c]
                let br = vertexIndex[r + 1][c + 1]
                let dtl = metricDepthAt[r][c]
                let dtr = metricDepthAt[r][c + 1]
                let dbl = metricDepthAt[r + 1][c]
                let dbr = metricDepthAt[r + 1][c + 1]

                // Upper-left triangle (tl, bl, tr)
                if tl >= 0, bl >= 0, tr >= 0, depthJumpOK(dtl, dbl, dtr) {
                    triKey[cellKey(r, c, 0)] = Int32(triangleIndices.count / 3)
                    triangleIndices.append(UInt32(tl))
                    triangleIndices.append(UInt32(bl))
                    triangleIndices.append(UInt32(tr))
                }
                // Lower-right triangle (tr, bl, br)
                if tr >= 0, bl >= 0, br >= 0, depthJumpOK(dtr, dbl, dbr) {
                    triKey[cellKey(r, c, 1)] = Int32(triangleIndices.count / 3)
                    triangleIndices.append(UInt32(tr))
                    triangleIndices.append(UInt32(bl))
                    triangleIndices.append(UInt32(br))
                }
            }
        }

        // Triangle adjacency : two triangles share an edge iff they share
        // 2 of their 3 vertices. For our grid layout the share pattern is
        // deterministic — encode it directly.
        let triCount = triangleIndices.count / 3
        var adjacency = [SIMD3<Int32>](repeating: SIMD3<Int32>(-1, -1, -1), count: triCount)

        for r in 0..<(gridRows - 1) {
            for c in 0..<(gridCols - 1) {
                if let tUL = triKey[cellKey(r, c, 0)] {
                    var neighbours = SIMD3<Int32>(-1, -1, -1)
                    var slot = 0
                    // Shared edge with the other diagonal of this same cell.
                    if let other = triKey[cellKey(r, c, 1)] {
                        neighbours[slot] = other; slot += 1
                    }
                    // Shared with cell above (its lower-right diagonal).
                    if r > 0, let other = triKey[cellKey(r - 1, c, 1)], slot < 3 {
                        neighbours[slot] = other; slot += 1
                    }
                    // Shared with cell to the left (its lower-right diagonal).
                    if c > 0, let other = triKey[cellKey(r, c - 1, 1)], slot < 3 {
                        neighbours[slot] = other; slot += 1
                    }
                    adjacency[Int(tUL)] = neighbours
                }
                if let tLR = triKey[cellKey(r, c, 1)] {
                    var neighbours = SIMD3<Int32>(-1, -1, -1)
                    var slot = 0
                    if let other = triKey[cellKey(r, c, 0)] {
                        neighbours[slot] = other; slot += 1
                    }
                    if r + 2 < gridRows, let other = triKey[cellKey(r + 1, c, 0)], slot < 3 {
                        neighbours[slot] = other; slot += 1
                    }
                    if c + 2 < gridCols, let other = triKey[cellKey(r, c + 1, 0)], slot < 3 {
                        neighbours[slot] = other; slot += 1
                    }
                    adjacency[Int(tLR)] = neighbours
                }
            }
        }

        return DepthMesh(
            vertices: vertices,
            triangleIndices: triangleIndices,
            triangleAdjacency: adjacency
        )
    }

    /// Read one depth value out of a CVPixelBuffer at (x, y).
    /// Supports the two common Apple CoreML output formats : 16-bit half
    /// float (`kCVPixelFormatType_OneComponent16Half`) and 32-bit float.
    private static func sampleDepth(
        at x: Int, y: Int,
        base: UnsafeMutableRawPointer,
        bytesPerRow: Int,
        format: OSType
    ) -> Float {
        let row = base.advanced(by: y * bytesPerRow)
        switch format {
        case kCVPixelFormatType_OneComponent32Float:
            return row.assumingMemoryBound(to: Float.self)[x]
        case kCVPixelFormatType_OneComponent16Half:
            // Float16 ↔ Float32 via the stdlib helper (iOS 14+).
            let half = row.assumingMemoryBound(to: Float16.self)[x]
            return Float(half)
        case kCVPixelFormatType_DepthFloat32:
            return row.assumingMemoryBound(to: Float.self)[x]
        case kCVPixelFormatType_DepthFloat16:
            let half = row.assumingMemoryBound(to: Float16.self)[x]
            return Float(half)
        default:
            // Unknown format — treat the first byte as a normalized 0..1
            // value. Should never hit this in practice with Apple's model.
            return Float(row.assumingMemoryBound(to: UInt8.self)[x]) / 255.0
        }
    }
}
