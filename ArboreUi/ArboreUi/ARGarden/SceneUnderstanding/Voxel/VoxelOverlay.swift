import Foundation
import SceneKit
import UIKit
import simd

/// Renders a `VoxelGrid` as a colored point cloud in SceneKit. Each voxel
/// becomes one vertex in a `SCNGeometry` with primitive type `.point`,
/// drawn at a large point size so the visual effect resembles a
/// Minecraft-style voxelization of the room.
///
/// One geometry node is rebuilt from scratch on each refresh — cheap
/// enough for ~50k voxels at 1 Hz. For larger clouds we could move to
/// incremental updates, but at 4cm voxels in an indoor scene we stay
/// well below that.
///
/// **Scan mode** : a separate `cameraOcclusion` SCNNode parented to the
/// AR camera renders a flat black plane in front of the lens — this
/// hides the live camera feed without disrupting ARKit tracking. When
/// the user moves the device, the voxels stay anchored in world space
/// (because they ARE in world space), so the scene perspective shifts
/// correctly as if walking through a 3D model.
final class VoxelOverlay {
    private weak var scene: SCNScene?
    private weak var cameraNode: SCNNode?
    private var voxelRoot: SCNNode?
    private var cameraOcclusion: SCNNode?

    var pointSize: CGFloat = 12

    var isVoxelRootAttached: Bool { voxelRoot?.parent != nil }
    var isCameraHidden: Bool { cameraOcclusion?.parent != nil }

    /// Attach the voxel point cloud to the scene. Idempotent.
    func attachVoxels(to scene: SCNScene) {
        if voxelRoot?.parent === scene.rootNode { return }
        let parent = SCNNode()
        parent.name = "voxelRoot"
        scene.rootNode.addChildNode(parent)
        self.voxelRoot = parent
        self.scene = scene
        AppLog.sceneML.notice("VoxelOverlay attached")
    }

    func detachVoxels() {
        voxelRoot?.removeFromParentNode()
        voxelRoot = nil
    }

    /// Hide the AR camera feed by parking an opaque black quad in front
    /// of the camera. ARKit tracking keeps running — only the visual
    /// background is replaced. Idempotent.
    ///
    /// `cameraNode` is `arView.pointOfView`.
    func hideCamera(cameraNode: SCNNode) {
        if cameraOcclusion?.parent === cameraNode { return }
        let plane = SCNPlane(width: 100, height: 100)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.black
        mat.isDoubleSided = false
        // Don't interfere with depth — voxels render through.
        mat.writesToDepthBuffer = false
        mat.readsFromDepthBuffer = false
        plane.firstMaterial = mat
        let node = SCNNode(geometry: plane)
        // 30cm in front of camera ; large enough to cover the whole FoV.
        node.position = SCNVector3(0, 0, -0.3)
        // Draw before everything else so voxels overlap it cleanly.
        node.renderingOrder = -100
        cameraNode.addChildNode(node)
        self.cameraOcclusion = node
        self.cameraNode = cameraNode
    }

    func showCamera() {
        cameraOcclusion?.removeFromParentNode()
        cameraOcclusion = nil
    }

    // MARK: - Voxel mesh rebuild

    private static var refreshCount = 0

    /// Rebuilds the SCNGeometry from the current grid. O(n) over the
    /// grid count. Call after a tick of inserts.
    func refresh(grid: VoxelGrid) {
        guard let root = voxelRoot else { return }
        root.childNodes.forEach { $0.removeFromParentNode() }
        Self.refreshCount += 1
        // Log every 5 refreshes (every ~5s at 1Hz) to avoid spamming.
        if Self.refreshCount % 5 == 0 {
            AppLog.sceneML.notice("VoxelOverlay refresh count=\(grid.count, privacy: .public)")
        }
        guard let geometry = Self.makeGeometry(from: grid, pointSize: pointSize) else { return }
        let node = SCNNode(geometry: geometry)
        node.name = "voxelCloud"
        root.addChildNode(node)
    }

    private static func makeGeometry(from grid: VoxelGrid, pointSize: CGFloat) -> SCNGeometry? {
        let n = grid.count
        guard n > 0 else { return nil }

        var positions = [SCNVector3]()
        positions.reserveCapacity(n)
        var colors = [SIMD3<Float>]()
        colors.reserveCapacity(n)

        for (key, cell) in grid.cells {
            let world = grid.worldCenter(of: key)
            positions.append(SCNVector3(world.x, world.y, world.z))
            colors.append(cell.color)
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

        // Index buffer is 0..n-1 since we want every vertex as its own point.
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
