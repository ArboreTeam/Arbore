import Foundation
import simd

/// Extract a triangulated iso-surface from a `TSDFGrid` snapshot using
/// the classic Lorensen-Cline marching cubes algorithm (#189 final stage).
///
/// Each "cube cell" is the unit-voxel cell whose 8 corners are the
/// voxels at `(x, y, z) ... (x+1, y+1, z+1)`. We iterate over the
/// snapshot keys and treat each as the v0 of a cube. If all 8 corners
/// are present with `weight ≥ minWeight`, we classify the cube by the
/// sign of `tsdf - isoValue` at each corner, look the triangle list up
/// in `triTable`, and emit triangles whose vertices lie on the edges
/// where the iso-surface crosses (linear-interpolation between the two
/// corner TSDFs).
///
/// Output is a triangle soup (no shared vertices across cubes) so it
/// plugs into SceneKit as a simple `.triangles` element. Vertex colour
/// is the cube's v0 winning SemSeg category.
enum MarchingCubes {

    struct Mesh {
        let vertices: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let colors: [SIMD3<Float>]
        /// One index per vertex (we emit a triangle soup, no sharing).
        let indices: [UInt32]
    }

    /// Run marching cubes on the given TSDF cell snapshot.
    /// - Parameter cells: snapshot from `TSDFGrid.snapshot()`.
    /// - Parameter voxelSize: same as the grid's `voxelSize`.
    /// - Parameter isoValue: SDF level to extract (defaults to 0).
    /// - Parameter minWeight: only consider corners with at least this
    ///   accumulated weight — rejects single-observation noise.
    static func extractMesh(
        cells: [TSDFGrid.Key: TSDFGrid.Cell],
        voxelSize: Float,
        isoValue: Float = 0,
        minWeight: Float = 3
    ) -> Mesh {
        guard !cells.isEmpty else {
            return Mesh(vertices: [], normals: [], colors: [], indices: [])
        }

        let allCats = COCOPanopticCategory.allCases

        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var colors: [SIMD3<Float>] = []
        vertices.reserveCapacity(cells.count * 6)

        // Pre-resolve color from a category index. ".other" / out-of-range
        // → mid-grey fallback (same convention as TSDFOverlay's point path).
        func color(for category: Int8?) -> SIMD3<Float> {
            guard let idx = category, Int(idx) >= 0, Int(idx) < allCats.count else {
                return SIMD3<Float>(0.6, 0.6, 0.6)
            }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            allCats[Int(idx)].debugColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            return SIMD3<Float>(
                Float(max(0, min(1, r))),
                Float(max(0, min(1, g))),
                Float(max(0, min(1, b)))
            )
        }

        for (baseKey, baseCell) in cells {
            _ = baseCell   // base referenced via cornerCells[0] below
            // Gather the 8 corner cells. Bail out if ANY corner is
            // missing or below weight — marching cubes needs all 8.
            var cornerCells: [TSDFGrid.Cell] = []
            cornerCells.reserveCapacity(8)
            var ok = true
            for offset in MarchingCubesLUT.cornerOffsets {
                let key = TSDFGrid.Key(
                    x: baseKey.x + offset.0,
                    y: baseKey.y + offset.1,
                    z: baseKey.z + offset.2
                )
                guard let c = cells[key], c.weight >= minWeight else {
                    ok = false; break
                }
                cornerCells.append(c)
            }
            guard ok else { continue }

            // Build case index. Bit i = 1 if corner i is "inside"
            // (tsdf below the iso-value).
            var caseIndex: Int = 0
            for i in 0..<8 where cornerCells[i].tsdf < isoValue {
                caseIndex |= (1 << i)
            }
            let edgeMask = MarchingCubesLUT.edgeTable[caseIndex]
            if edgeMask == 0 { continue }

            // Compute world position of each crossed edge's vertex.
            // We only fill the 12-slot array for the edges actually
            // present in `edgeMask` ; others stay unused.
            var edgeVerts = [SIMD3<Float>](repeating: .zero, count: 12)
            for e in 0..<12 where (edgeMask & (1 << e)) != 0 {
                let (cA, cB) = MarchingCubesLUT.edgeCornerPairs[e]
                let aOff = MarchingCubesLUT.cornerOffsets[cA]
                let bOff = MarchingCubesLUT.cornerOffsets[cB]
                let posA = SIMD3<Float>(
                    Float(baseKey.x + aOff.0) * voxelSize + voxelSize * 0.5,
                    Float(baseKey.y + aOff.1) * voxelSize + voxelSize * 0.5,
                    Float(baseKey.z + aOff.2) * voxelSize + voxelSize * 0.5
                )
                let posB = SIMD3<Float>(
                    Float(baseKey.x + bOff.0) * voxelSize + voxelSize * 0.5,
                    Float(baseKey.y + bOff.1) * voxelSize + voxelSize * 0.5,
                    Float(baseKey.z + bOff.2) * voxelSize + voxelSize * 0.5
                )
                let vA = cornerCells[cA].tsdf
                let vB = cornerCells[cB].tsdf
                let denom = vB - vA
                // Linear interpolation along the edge. Guard against the
                // degenerate case where both corners have the exact same
                // TSDF (rare, but tank-divides if not handled).
                let t: Float = abs(denom) > 1e-6 ? (isoValue - vA) / denom : 0.5
                edgeVerts[e] = posA + (posB - posA) * max(0, min(1, t))
            }

            let cubeColor = color(for: cornerCells[0].winningCategory)

            // Emit the triangles for this case.
            let row = MarchingCubesLUT.triTable[caseIndex]
            var i = 0
            while i + 2 < row.count, row[i] >= 0 {
                let e1 = Int(row[i])
                let e2 = Int(row[i + 1])
                let e3 = Int(row[i + 2])
                let v1 = edgeVerts[e1]
                let v2 = edgeVerts[e2]
                let v3 = edgeVerts[e3]
                // Per-triangle flat normal — fine for the kind of mesh
                // we produce (smoothed normals would require a second
                // pass to accumulate per-vertex contributions across
                // neighbouring triangles, more complex than warranted
                // for a debug viz).
                let n = simd_normalize(simd_cross(v2 - v1, v3 - v1))
                let baseIdx = UInt32(vertices.count)
                vertices.append(v1)
                vertices.append(v2)
                vertices.append(v3)
                normals.append(n)
                normals.append(n)
                normals.append(n)
                colors.append(cubeColor)
                colors.append(cubeColor)
                colors.append(cubeColor)
                _ = baseIdx
                i += 3
            }
        }

        let indices: [UInt32] = (0..<UInt32(vertices.count)).map { $0 }
        return Mesh(vertices: vertices, normals: normals, colors: colors, indices: indices)
    }
}
