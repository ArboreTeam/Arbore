import Foundation
import SceneKit
import UIKit
import simd

/// 3D overlay that draws one wireframe bounding box + a floating text
/// label per `SceneRegion` (cf #187). Sits inside the SceneKit scene so
/// the user sees the labelled regions in correct world space, layered
/// with both the ARKit gizmo (Phase 1) and the 2D mask overlays.
///
/// Each refresh rebuilds the child nodes ; the cost is bounded by the
/// number of regions in the snapshot (typically < 30 indoors). At 0.5 Hz
/// this is negligible.
final class FusedSceneOverlay {
    private weak var scene: SCNScene?
    private var root: SCNNode?

    var isActive: Bool { root != nil }

    /// Attach to a scene. Idempotent.
    func attach(to scene: SCNScene) {
        guard root == nil else { return }
        let parent = SCNNode()
        parent.name = "fusedSceneOverlay"
        scene.rootNode.addChildNode(parent)
        self.root = parent
        self.scene = scene
    }

    /// Remove all child nodes + detach.
    func detach() {
        root?.removeFromParentNode()
        root = nil
        scene = nil
    }

    /// Refresh : remove the previous regions' nodes and emit fresh ones.
    func update(regions: [SceneRegion]) {
        guard let root = root else { return }
        root.childNodes.forEach { $0.removeFromParentNode() }
        for region in regions {
            root.addChildNode(Self.makeNode(for: region))
        }
    }

    // MARK: - Node construction

    private static func makeNode(for region: SceneRegion) -> SCNNode {
        let container = SCNNode()
        container.name = "fusedRegion_\(region.id.uuidString.prefix(8))"
        container.position = SCNVector3(region.centroid.x,
                                         region.centroid.y,
                                         region.centroid.z)
        let color = region.category.debugColor

        // 1. Wireframe bbox — SCNBox with .lines fill mode.
        let size = region.size
        let box = SCNBox(width: CGFloat(max(size.x, 0.01)),
                         height: CGFloat(max(size.y, 0.01)),
                         length: CGFloat(max(size.z, 0.01)),
                         chamferRadius: 0)
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color
        mat.lightingModel = .constant
        mat.fillMode = .lines
        mat.isDoubleSided = true
        box.firstMaterial = mat
        container.addChildNode(SCNNode(geometry: box))

        // 2. Floating text label above the bbox top.
        let labelStr = "\(region.category.label.uppercased()) · \(formatExtent(region.size))"
        let text = makeLabel(text: labelStr, color: color)
        text.position = SCNVector3(0, Float(size.y) * 0.5 + 0.08, 0)
        container.addChildNode(text)

        return container
    }

    private static func makeLabel(text: String, color: UIColor) -> SCNNode {
        let geo = SCNText(string: text, extrusionDepth: 0.2)
        geo.font = UIFont.systemFont(ofSize: 5, weight: .bold)
        geo.firstMaterial?.diffuse.contents = UIColor.white
        geo.firstMaterial?.emission.contents = color
        geo.flatness = 0.4
        let node = SCNNode(geometry: geo)
        node.scale = SCNVector3(0.005, 0.005, 0.005)
        let (mn, mx) = geo.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((mx.x - mn.x) / 2, 0, 0)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = [.Y]
        node.constraints = [billboard]
        return node
    }

    private static func formatExtent(_ size: SIMD3<Float>) -> String {
        String(format: "%.2f×%.2f×%.2fm", size.x, size.y, size.z)
    }
}
