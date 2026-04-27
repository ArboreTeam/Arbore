import Foundation
import SwiftUI
import SceneKit
import simd

/// SceneKit helpers used during the manual replacement flow:
/// - Drawing dotted boundary outlines on the floor
/// - Applying / removing a translucent "ghost" appearance to plant nodes
enum GhostRenderer {

    static let ghostNodeName = "ghost_overlay_material"
    static let boundaryNodeName = "manual_replacement_boundary"
    static let boundarySphereName = "manual_replacement_boundary_sphere"

    // MARK: - Boundary visualization

    /// Returns a parent node that draws the polygon as floor lines + small spheres
    /// at each vertex. Caller is responsible for adding it to the scene and
    /// removing it via `removeBoundary`.
    @discardableResult
    static func drawBoundary(
        points: [SIMD3<Float>],
        color: UIColor,
        opacity: Float = 0.6,
        in scene: SCNScene,
        name: String = boundaryNodeName
    ) -> SCNNode {
        // Remove a previous instance with the same name to keep things clean.
        scene.rootNode.childNodes
            .filter { $0.name == name }
            .forEach { $0.removeFromParentNode() }

        let parent = SCNNode()
        parent.name = name

        guard !points.isEmpty else {
            scene.rootNode.addChildNode(parent)
            return parent
        }

        // Vertex spheres
        for p in points {
            let sphere = SCNSphere(radius: 0.025)
            sphere.firstMaterial?.diffuse.contents = color
            sphere.firstMaterial?.lightingModel = .constant
            let node = SCNNode(geometry: sphere)
            node.opacity = CGFloat(opacity)
            node.simdPosition = p
            node.name = boundarySphereName
            parent.addChildNode(node)
        }

        // Edges: only if 2+ points; close polygon if 3+.
        if points.count >= 2 {
            let count = points.count
            let lastIndex = count >= 3 ? count : count - 1
            for i in 0..<lastIndex {
                let a = points[i]
                let b = points[(i + 1) % count]
                if let edge = makeEdgeNode(from: a, to: b, color: color) {
                    edge.opacity = CGFloat(opacity)
                    parent.addChildNode(edge)
                }
            }
        }

        scene.rootNode.addChildNode(parent)
        return parent
    }

    /// Removes any previously-drawn boundary node by name.
    static func removeBoundary(named name: String = boundaryNodeName, from scene: SCNScene) {
        scene.rootNode.childNodes
            .filter { $0.name == name }
            .forEach { $0.removeFromParentNode() }
    }

    // MARK: - Ghost plant materials

    /// Turns a plant node translucent + tinted to indicate preview state.
    /// We do NOT replace the geometry's materials in-place (that would be
    /// destructive). Instead we set the node's `opacity` and apply a tint by
    /// adding a colored emission material override via a flag.
    static func applyGhost(to node: SCNNode, tint: UIColor, opacity: Float = 0.55) {
        node.opacity = CGFloat(opacity)
        node.setValue(true, forKey: ghostNodeName)
        node.enumerateChildNodes { child, _ in
            child.enumerateHierarchy { sub, _ in
                if let materials = sub.geometry?.materials {
                    for m in materials {
                        // Save the original emission contents the first time so we can restore it.
                        if m.value(forKey: "originalEmission") == nil {
                            m.setValue(m.emission.contents ?? NSNull(), forKey: "originalEmission")
                        }
                        m.emission.contents = tint
                    }
                }
            }
        }
    }

    /// Restores a node that was previously made ghost.
    static func removeGhost(from node: SCNNode) {
        node.opacity = 1.0
        node.setValue(false, forKey: ghostNodeName)
        node.enumerateChildNodes { child, _ in
            child.enumerateHierarchy { sub, _ in
                if let materials = sub.geometry?.materials {
                    for m in materials {
                        if let original = m.value(forKey: "originalEmission") {
                            if original is NSNull {
                                m.emission.contents = nil
                            } else {
                                m.emission.contents = original
                            }
                            m.setValue(nil, forKey: "originalEmission")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Private

    private static func makeEdgeNode(from a: SIMD3<Float>, to b: SIMD3<Float>, color: UIColor) -> SCNNode? {
        let v = b - a
        let len = simd_length(v)
        guard len > 1e-4 else { return nil }

        let cylinder = SCNCylinder(radius: 0.008, height: CGFloat(len))
        cylinder.firstMaterial?.diffuse.contents = color
        cylinder.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: cylinder)

        // SCNCylinder is aligned along Y. Rotate so that its main axis matches v.
        let mid = (a + b) * 0.5
        node.simdPosition = mid

        let yAxis = SIMD3<Float>(0, 1, 0)
        let dir = v / len
        let dot = simd_dot(yAxis, dir)
        if abs(dot - 1) < 1e-5 {
            // Already aligned.
        } else if abs(dot + 1) < 1e-5 {
            // Opposite — rotate 180° around X.
            node.simdOrientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        } else {
            let axis = simd_normalize(simd_cross(yAxis, dir))
            let angle = acos(simd_clamp(dot, -1, 1))
            node.simdOrientation = simd_quatf(angle: angle, axis: axis)
        }

        return node
    }
}
