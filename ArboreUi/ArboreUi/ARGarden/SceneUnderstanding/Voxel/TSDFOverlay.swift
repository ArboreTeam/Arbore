import Foundation
import SceneKit
import UIKit
import simd

/// Renders the iso-surface of a `TSDFGrid` as a point cloud — same
/// `.point` primitive as `VoxelOverlay`, but the cell filtering is
/// driven by the SDF instead of raw observation counts.
///
/// Compared to `VoxelOverlay` (every back-projected pixel becomes a
/// point), TSDFOverlay only renders voxels that are :
///   - well-observed (weight ≥ `minWeight`)
///   - close to the surface (|tsdf| ≤ `isoSurfaceTolerance`)
///
/// The visual effect is a cleaner, surface-aligned cloud — multi-view
/// fusion via TSDF integration cancels out the per-frame depth noise
/// before rendering, so isolated outliers naturally vanish from the
/// iso-surface set.
///
/// Marching-cubes mesh extraction for a smooth iso-surface is a
/// follow-up (cf #189 final state) ; this is the minimum-viable
/// rendering on top of the working TSDF math.
final class TSDFOverlay {
    private weak var scene: SCNScene?
    private var meshRoot: SCNNode?

    var pointSize: CGFloat = 14
    var minWeight: Float = 3
    /// Cells with |tsdf| under this distance from the iso-surface are
    /// rendered. Defaulted to half a voxel — anything smaller misses
    /// cells whose centre sits slightly above/below the surface.
    var isoSurfaceTolerance: Float = 0.02

    var isAttached: Bool { meshRoot?.parent != nil }

    /// Attach a root node to the scene. Idempotent.
    func attach(to scene: SCNScene) {
        if meshRoot?.parent === scene.rootNode { return }
        let parent = SCNNode()
        parent.name = "tsdfRoot"
        scene.rootNode.addChildNode(parent)
        self.meshRoot = parent
        self.scene = scene
        AppLog.sceneML.notice("TSDFOverlay attached")
    }

    func detach() {
        meshRoot?.removeFromParentNode()
        meshRoot = nil
    }

    // MARK: - Mesh rebuild

    private static var refreshCount = 0

    /// Rebuild the iso-surface from the current TSDF grid. Same O(n)
    /// snapshot-then-emit pattern as `VoxelOverlay.refresh`.
    func refresh(grid: TSDFGrid) {
        guard let root = meshRoot else { return }
        root.childNodes.forEach { $0.removeFromParentNode() }
        Self.refreshCount += 1

        let cells = grid.snapshot()
        // Filter to iso-surface cells.
        let isoCells: [(TSDFGrid.Key, TSDFGrid.Cell)] = cells.compactMap { (k, c) in
            guard c.weight >= minWeight else { return nil }
            guard abs(c.tsdf) <= isoSurfaceTolerance else { return nil }
            return (k, c)
        }

        if Self.refreshCount % 5 == 0 {
            AppLog.sceneML.notice("TSDFOverlay refresh raw=\(cells.count, privacy: .public) iso=\(isoCells.count, privacy: .public)")
        }

        guard !isoCells.isEmpty,
              let geometry = Self.makeGeometry(cells: isoCells, grid: grid, pointSize: pointSize) else {
            return
        }
        let node = SCNNode(geometry: geometry)
        node.name = "tsdfMesh"
        root.addChildNode(node)
    }

    private static func makeGeometry(
        cells: [(TSDFGrid.Key, TSDFGrid.Cell)],
        grid: TSDFGrid,
        pointSize: CGFloat
    ) -> SCNGeometry? {
        let n = cells.count
        guard n > 0 else { return nil }

        let allCats = COCOPanopticCategory.allCases

        var positions = [SCNVector3]()
        positions.reserveCapacity(n)
        var colors = [SIMD3<Float>]()
        colors.reserveCapacity(n)

        for (key, cell) in cells {
            // Position the point at the world centre of the voxel,
            // offset along the zero-isosurface normal so it sits closer
            // to the actual surface — `tsdf` is the signed distance,
            // so subtracting `tsdf · grad` shifts toward the iso-surface.
            // We approximate the gradient as +Z (we don't have neighbour
            // queries here cheap enough to compute true gradient) and
            // just use the centre for now.
            let world = grid.worldCenter(of: key)
            positions.append(SCNVector3(world.x, world.y, world.z))

            // Resolve colour from winning SemSeg category. Fallback to
            // mid-grey if no category vote was cast on this voxel.
            var r: CGFloat = 0.6, g: CGFloat = 0.6, b: CGFloat = 0.6, a: CGFloat = 0
            if let idx = cell.winningCategory, Int(idx) >= 0, Int(idx) < allCats.count {
                allCats[Int(idx)].debugColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            }
            colors.append(SIMD3<Float>(
                Float(max(0, min(1, r))),
                Float(max(0, min(1, g))),
                Float(max(0, min(1, b)))
            ))
        }

        let vertexSource = SCNGeometrySource(vertices: positions)
        let colorData = Data(bytes: colors, count: colors.count * MemoryLayout<SIMD3<Float>>.stride)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        var indices = [UInt32](0..<UInt32(n))
        let indexData = Data(bytes: &indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: n,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        element.pointSize = pointSize
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = CGFloat(pointSize)

        let geo = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        geo.materials = [mat]
        return geo
    }
}
