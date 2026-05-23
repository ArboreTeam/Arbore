import ARKit
import Foundation
import SceneKit
import UIKit
import simd

/// Debug viz that renders one colored overlay per `ARPlaneAnchor` the
/// session has detected, so a developer can see what ARKit currently
/// understands of the room (issue #186).
///
/// Each plane gets :
///  - a filled tinted disc/rectangle aligned with the plane's geometry
///    (alpha ~0.35 so the camera feed still shows through),
///  - a thin outline ring around its boundary,
///  - a thin "normal" arrow at its centre to make orientation obvious,
///  - a SCNText label like "WALL · 2.1×2.6m" floating just above the
///    centroid.
///
/// The controller is fully passive : the AR coordinator calls
/// `upsert(anchor:type:)` whenever a plane is added or updated, and
/// `remove(id:)` when it goes away. Nothing happens per-frame, so the
/// overhead is bounded by the number of distinct plane anchors (typically
/// < 30 in a room).
final class SurfaceVizController {
    /// Parent node for ALL overlays. Sits directly under the scene root.
    /// Detached + nil'd in `stop()`.
    private weak var rootNode: SCNNode?
    private var overlayRoot: SCNNode?

    /// per-anchor overlay node ; keyed by `ARAnchor.identifier`.
    private var overlays: [UUID: SCNNode] = [:]

    private(set) var isActive: Bool = false

    // MARK: - Lifecycle

    /// Attach the overlay root to the scene. Idempotent.
    func start(in scene: SCNScene) {
        guard !isActive else { return }
        let parent = SCNNode()
        parent.name = "surfaceVizRoot"
        scene.rootNode.addChildNode(parent)
        self.overlayRoot = parent
        self.rootNode = scene.rootNode
        self.isActive = true
        AppLog.surfaces.notice("SurfaceVizController started")
    }

    /// Detach the overlay root + drop every cached node. Idempotent.
    func stop() {
        guard isActive else { return }
        overlayRoot?.removeFromParentNode()
        overlayRoot = nil
        overlays.removeAll()
        isActive = false
        AppLog.surfaces.notice("SurfaceVizController stopped")
    }

    /// Insert or refresh the overlay for one anchor. Safe to call
    /// repeatedly with the same id ; the previous node is removed.
    func upsert(anchor: ARPlaneAnchor, type: SurfaceType) {
        guard isActive, let overlayRoot = overlayRoot else { return }
        let id = anchor.identifier

        if let existing = overlays[id] {
            existing.removeFromParentNode()
            overlays.removeValue(forKey: id)
        }

        let node = makeOverlayNode(anchor: anchor, type: type)
        overlays[id] = node
        overlayRoot.addChildNode(node)
    }

    /// Drop the overlay for the given anchor. Idempotent.
    func remove(id: UUID) {
        overlays[id]?.removeFromParentNode()
        overlays.removeValue(forKey: id)
    }

    // MARK: - Overlay construction

    private func makeOverlayNode(anchor: ARPlaneAnchor, type: SurfaceType) -> SCNNode {
        let root = SCNNode()
        root.name = "surfaceViz_\(anchor.identifier.uuidString.prefix(8))"
        root.simdTransform = anchor.transform

        let color = type.debugColor

        // 1. Filled rectangle aligned with the plane's local x/z axes (the
        //    plane lives in the anchor's local xz-plane by ARKit convention).
        let (w, d) = planeExtent(of: anchor)
        let fill = SCNPlane(width: CGFloat(w), height: CGFloat(d))
        fill.firstMaterial?.diffuse.contents = color
        fill.firstMaterial?.transparency = 0.35
        fill.firstMaterial?.isDoubleSided = true
        fill.firstMaterial?.lightingModel = .constant
        let fillNode = SCNNode(geometry: fill)
        // SCNPlane lies in its local XY; rotate so it sits in the anchor's XZ.
        fillNode.eulerAngles.x = -.pi / 2
        let centerOffset = SCNVector3(anchor.center.x, anchor.center.y, anchor.center.z)
        fillNode.position = centerOffset
        root.addChildNode(fillNode)

        // 2. Outline rectangle (thin border so the shape is still visible
        //    even when the filled material is occluded). The outline is
        //    constructed directly in the anchor's local XZ plane (corners
        //    at y=0), so unlike the SCNPlane fill it does NOT need an
        //    extra rotation — it already lies in the right plane.
        let outline = makeOutlineRect(width: w, height: d, color: color)
        outline.position = centerOffset
        root.addChildNode(outline)

        // 3. Normal arrow at the centroid, 25cm long, points along the
        //    plane's local +Y (ARKit's plane normal convention).
        let arrow = makeNormalArrow(length: 0.25, color: color)
        arrow.position = centerOffset
        root.addChildNode(arrow)

        // 4. Text label floating 15cm along the plane's normal (local +Y).
        //    Same offset rule for horizontal and vertical anchors — what
        //    "above the plane" means is encoded in `anchor.transform`.
        let extentString = String(format: "%.1f×%.1fm", w, d)
        let labelStr = "\(type.label.uppercased()) · \(extentString)"
        let label = makeLabel(text: labelStr, color: color)
        label.position = SCNVector3(centerOffset.x, centerOffset.y + 0.15, centerOffset.z)
        root.addChildNode(label)

        return root
    }

    private func planeExtent(of anchor: ARPlaneAnchor) -> (Float, Float) {
        if #available(iOS 16.0, *) {
            return (anchor.planeExtent.width, anchor.planeExtent.height)
        } else {
            return (anchor.extent.x, anchor.extent.z)
        }
    }

    private func makeOutlineRect(width w: Float, height h: Float, color: UIColor) -> SCNNode {
        let half = SCNNode()
        let radius: CGFloat = 0.005
        let halfW = w / 2
        let halfH = h / 2

        func segment(from a: SCNVector3, to b: SCNVector3) -> SCNNode {
            let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
            let length = sqrtf(dx*dx + dy*dy + dz*dz)
            let cyl = SCNCylinder(radius: radius, height: CGFloat(length))
            cyl.firstMaterial?.diffuse.contents = color
            cyl.firstMaterial?.lightingModel = .constant
            let node = SCNNode(geometry: cyl)
            node.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
            // Cylinder default axis is Y. Rotate to align with segment direction.
            let up = SIMD3<Float>(0, 1, 0)
            let dir = simd_normalize(SIMD3<Float>(dx, dy, dz))
            let axis = simd_cross(up, dir)
            let dot = simd_dot(up, dir)
            if simd_length(axis) > 1e-4 {
                let angle = acosf(simd_clamp(dot, -1, 1))
                node.simdRotation = SIMD4<Float>(simd_normalize(axis), angle)
            } else if dot < 0 {
                node.simdRotation = SIMD4<Float>(1, 0, 0, .pi)
            }
            return node
        }

        let corners = [
            SCNVector3(-halfW, 0, -halfH),
            SCNVector3( halfW, 0, -halfH),
            SCNVector3( halfW, 0,  halfH),
            SCNVector3(-halfW, 0,  halfH),
        ]
        for i in 0..<corners.count {
            half.addChildNode(segment(from: corners[i], to: corners[(i + 1) % corners.count]))
        }
        return half
    }

    private func makeNormalArrow(length: Float, color: UIColor) -> SCNNode {
        let cyl = SCNCylinder(radius: 0.006, height: CGFloat(length))
        cyl.firstMaterial?.diffuse.contents = color
        cyl.firstMaterial?.lightingModel = .constant
        let stem = SCNNode(geometry: cyl)
        stem.position = SCNVector3(0, length / 2, 0)

        let cone = SCNCone(topRadius: 0, bottomRadius: 0.018, height: 0.04)
        cone.firstMaterial?.diffuse.contents = color
        cone.firstMaterial?.lightingModel = .constant
        let tip = SCNNode(geometry: cone)
        tip.position = SCNVector3(0, length + 0.02, 0)

        let group = SCNNode()
        group.addChildNode(stem)
        group.addChildNode(tip)
        return group
    }

    private func makeLabel(text: String, color: UIColor) -> SCNNode {
        let geo = SCNText(string: text, extrusionDepth: 0.2)
        geo.font = UIFont.systemFont(ofSize: 4, weight: .bold)
        geo.firstMaterial?.diffuse.contents = UIColor.white
        geo.firstMaterial?.emission.contents = color
        geo.flatness = 0.4
        let node = SCNNode(geometry: geo)
        // SCNText is sized in points, scale it down to ~3cm height total.
        node.scale = SCNVector3(0.005, 0.005, 0.005)
        // Recenter the text on the X axis (otherwise the left edge sits
        // on the anchor centroid).
        let (min, max) = geo.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((max.x - min.x) / 2, 0, 0)
        // Always face the user — billboard constraint.
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = [.Y]
        node.constraints = [billboard]
        return node
    }
}
