import Foundation
import SceneKit
import simd

#if canImport(UIKit)
import UIKit
#endif

/// Turns a `DepthMesh` into a colored `SCNGeometry`.
///
/// Two colour signals are combined into per-vertex RGB :
///
///  1. **Height (Y world)** → hue gradient. Floor (Y ≈ 0) is blue, ceiling
///     (Y ≈ 2.5m) is red — same metaphor as a topographic map. This is
///     the dominant signal the user reads.
///  2. **Connected component id** → hue **offset** (±0.12). Two desks at
///     75cm height sit next to each other in hue but separated by a small
///     wedge so the eye can tell "this is desk A, that is desk B".
///
/// The CC pass labels the triangles by BFS over `mesh.triangleAdjacency`.
/// A "component" is a maximal set of triangles all connected through
/// shared edges (the mesher already rejected edges crossing big depth
/// jumps, so each component should roughly equal one physical surface).
enum DepthMeshVizRenderer {

    /// Lowest world Y (in meters) mapped to hue 0.66 (blue).
    static let minHeight: Float = 0.0
    /// Highest world Y mapped to hue 0.00 (red).
    static let maxHeight: Float = 2.5
    /// Max hue offset applied based on component id (kept small so the
    /// height signal stays readable).
    static let componentHueJitter: Float = 0.12
    /// Transparency of the overlay mesh — we want to see the camera
    /// feed underneath.
    static let alpha: CGFloat = 0.55

    /// Build a `SCNGeometry` ready to be set on a new `SCNNode`.
    static func makeGeometry(from mesh: DepthMesh) -> SCNGeometry? {
        guard !mesh.vertices.isEmpty, mesh.triangleCount > 0 else { return nil }

        let labels = labelConnectedComponents(mesh: mesh)
        let colors = perVertexColors(mesh: mesh, triangleComponent: labels)

        let vertexSource = SCNGeometrySource(vertices: mesh.vertices.map {
            SCNVector3($0.x, $0.y, $0.z)
        })

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

        let indexData = mesh.triangleIndices.withUnsafeBufferPointer {
            Data(buffer: $0)
        }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: mesh.triangleCount,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geo = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        // diffuse defaults to white — per-vertex color comes from the
        // .color geometry source above and multiplies the diffuse.
        mat.isDoubleSided = true
        mat.transparency = alpha
        // Render mesh as filled triangles (default). Wireframe is available
        // via `geo.firstMaterial?.fillMode = .lines` if we want a Quest-y
        // wireframe overlay instead — exposed as a toggle below.
        geo.materials = [mat]
        return geo
    }

    /// BFS-based connected-component labelling. Returns an array where
    /// `result[t]` = component id of triangle `t` (0-indexed).
    static func labelConnectedComponents(mesh: DepthMesh) -> [Int32] {
        var labels = [Int32](repeating: -1, count: mesh.triangleCount)
        var queue: [Int] = []
        queue.reserveCapacity(mesh.triangleCount)
        var nextId: Int32 = 0

        for seed in 0..<mesh.triangleCount {
            if labels[seed] != -1 { continue }
            labels[seed] = nextId
            queue.removeAll(keepingCapacity: true)
            queue.append(seed)

            while let t = queue.popLast() {
                let neighbours = mesh.triangleAdjacency[t]
                for k in 0..<3 {
                    let n = Int(neighbours[k])
                    if n < 0 { continue }
                    if labels[n] != -1 { continue }
                    labels[n] = nextId
                    queue.append(n)
                }
            }
            nextId += 1
        }
        return labels
    }

    /// Per-vertex colors. For each vertex we average the component id of
    /// the triangles that own it (a vertex on the boundary between two CC
    /// gets an intermediate hue, which avoids hard seams).
    private static func perVertexColors(
        mesh: DepthMesh,
        triangleComponent: [Int32]
    ) -> [SIMD3<Float>] {
        // Hash component id → hue offset in [-jitter, +jitter] deterministically.
        func componentHueOffset(_ id: Int32) -> Float {
            // Bit-mixed pseudo-random in [0, 1).
            var x = UInt32(bitPattern: id) &* 0x9E3779B1
            x ^= (x >> 16); x &*= 0x85EBCA6B
            x ^= (x >> 13); x &*= 0xC2B2AE35
            x ^= (x >> 16)
            let unit = Float(x) / Float(UInt32.max)  // 0…1
            return (unit * 2 - 1) * componentHueJitter
        }

        let n = mesh.vertices.count
        var hueSum = [Float](repeating: 0, count: n)
        var hueCount = [Int](repeating: 0, count: n)

        for t in 0..<mesh.triangleCount {
            let offset = componentHueOffset(triangleComponent[t])
            for k in 0..<3 {
                let v = Int(mesh.triangleIndices[t * 3 + k])
                hueSum[v] += offset
                hueCount[v] += 1
            }
        }

        var colors = [SIMD3<Float>](repeating: SIMD3<Float>(1, 1, 1), count: n)
        let span = max(maxHeight - minHeight, 0.001)
        for v in 0..<n {
            let y = mesh.vertices[v].y
            let t = simd_clamp((y - minHeight) / span, 0, 1)
            // Hue ramp : blue (0.66) at low, red (0.0) at high.
            var hue = 0.66 - 0.66 * t
            if hueCount[v] > 0 {
                hue += hueSum[v] / Float(hueCount[v])
            }
            hue = (hue + 1).truncatingRemainder(dividingBy: 1)  // wrap to [0, 1]
            colors[v] = hsvToRgb(h: hue, s: 0.85, v: 1.0)
        }
        return colors
    }

    /// Standard HSV→RGB in [0,1].
    private static func hsvToRgb(h: Float, s: Float, v: Float) -> SIMD3<Float> {
        let i = floor(h * 6)
        let f = h * 6 - i
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        switch Int(i) % 6 {
        case 0: return SIMD3<Float>(v, t, p)
        case 1: return SIMD3<Float>(q, v, p)
        case 2: return SIMD3<Float>(p, v, t)
        case 3: return SIMD3<Float>(p, q, v)
        case 4: return SIMD3<Float>(t, p, v)
        default: return SIMD3<Float>(v, p, q)
        }
    }
}
