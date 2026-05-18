import Foundation
import SceneKit
import UIKit
import simd

/// Renders the iso-surface of a `TSDFGrid` as a **triangulated mesh**
/// extracted by marching cubes (#189). Real triangles + depth writing
/// = surfaces behind other surfaces are correctly occluded — fixes the
/// "voir les points cachés derrière" issue of the point-cloud rendering.
///
/// Each tick of marching cubes produces a triangle soup (no shared
/// vertices across cubes — flat-shaded look, simpler implementation,
/// indistinguishable from smooth-shading at the 4cm voxel resolution).
/// Per-vertex colour comes from the cube's v0 winning SemSeg category.
final class TSDFOverlay {
    private weak var scene: SCNScene?
    private var meshRoot: SCNNode?

    /// Discard cells with fewer than this accumulated weight before
    /// running marching cubes — kills single-observation noise around
    /// the iso-surface.
    var minWeight: Float = 3

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

    /// Rebuild the iso-surface mesh from the current TSDF grid.
    func refresh(grid: TSDFGrid) {
        guard let root = meshRoot else { return }
        root.childNodes.forEach { $0.removeFromParentNode() }
        Self.refreshCount += 1

        let cells = grid.snapshot()
        let mesh = MarchingCubes.extractMesh(
            cells: cells,
            voxelSize: grid.voxelSize,
            isoValue: 0,
            minWeight: minWeight
        )

        if Self.refreshCount % 5 == 0 {
            AppLog.sceneML.notice("TSDFOverlay refresh cells=\(cells.count, privacy: .public) triangles=\(mesh.indices.count / 3, privacy: .public)")
        }

        guard !mesh.vertices.isEmpty,
              let geometry = Self.makeGeometry(from: mesh) else { return }
        let node = SCNNode(geometry: geometry)
        node.name = "tsdfMesh"
        root.addChildNode(node)
    }

    private static func makeGeometry(from mesh: MarchingCubes.Mesh) -> SCNGeometry? {
        guard !mesh.vertices.isEmpty else { return nil }

        let vertexSource = SCNGeometrySource(vertices: mesh.vertices.map {
            SCNVector3($0.x, $0.y, $0.z)
        })

        let normalSource = SCNGeometrySource(normals: mesh.normals.map {
            SCNVector3($0.x, $0.y, $0.z)
        })

        let colorData = Data(bytes: mesh.colors, count: mesh.colors.count * MemoryLayout<SIMD3<Float>>.stride)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: mesh.colors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        let indexData = mesh.indices.withUnsafeBufferPointer { ptr in
            Data(buffer: ptr)
        }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: mesh.indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geo = SCNGeometry(sources: [vertexSource, normalSource, colorSource], elements: [element])
        let mat = SCNMaterial()
        // Constant lighting + per-vertex colour : we don't carry a
        // dedicated SCNLight in the AR scene, so anything depending on
        // a light source goes black.
        mat.lightingModel = .constant
        // Single-sided so back faces don't ghost through walls when the
        // camera ends up behind a reconstructed plane. Combined with
        // SceneKit's default depth-buffer writing this gives the
        // "real LiDAR-mesh" occlusion the user wanted (#189).
        mat.isDoubleSided = false
        mat.writesToDepthBuffer = true
        mat.readsFromDepthBuffer = true
        geo.materials = [mat]
        return geo
    }
}
