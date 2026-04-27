import Foundation
import simd

/// Mean Value Coordinates — Floater 2003.
/// Generalized barycentric coordinates that work on arbitrary (including non-convex) polygons.
/// Used to morph plant positions from an old garden boundary onto a new boundary.
enum MeanValueCoordinates {

    /// Computes MVC weights of a 2D point relative to the vertices of a polygon.
    /// The returned weights sum to 1 and can be used to express the point as a
    /// weighted combination of polygon vertices.
    ///
    /// Special case: if the point lies exactly on a vertex, that vertex gets weight 1.
    /// If it lies on an edge, the two endpoints share the weight linearly.
    static func weights(point p: SIMD2<Float>, polygon: [SIMD2<Float>]) -> [Float] {
        let n = polygon.count
        guard n >= 3 else { return Array(repeating: 1.0 / Float(max(n, 1)), count: n) }

        var weights = [Float](repeating: 0, count: n)

        // Distances and unit vectors from p to each vertex.
        var dists = [Float](repeating: 0, count: n)
        var unit = [SIMD2<Float>](repeating: .zero, count: n)

        for i in 0..<n {
            let d = polygon[i] - p
            let len = simd_length(d)
            dists[i] = len
            // Vertex coincidence — return canonical basis.
            if len < 1e-6 {
                weights[i] = 1
                return weights
            }
            unit[i] = d / len
        }

        // tan(theta_i / 2) = (1 - cos(theta_i)) / sin(theta_i)
        // where theta_i is the angle between (vertex_i, vertex_{i+1}) seen from p.
        var halfTan = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let next = (i + 1) % n
            let dot = simd_clamp(simd_dot(unit[i], unit[next]), -1.0, 1.0)
            // Cross product (2D) for sign of sin.
            let cross = unit[i].x * unit[next].y - unit[i].y * unit[next].x
            let sin = cross
            let cos = dot
            // Edge case: point on edge between i and next (theta ~ pi).
            if abs(sin) < 1e-6 && cos < 0 {
                // Linear blend along the edge — assign and return.
                let t = dists[next] / (dists[i] + dists[next])
                weights[i] = t
                weights[next] = 1 - t
                return weights
            }
            // tan(half-angle) via stable formula.
            halfTan[i] = (1 - cos) / sin
        }

        var totalWeight: Float = 0
        for i in 0..<n {
            let prev = (i - 1 + n) % n
            let w = (halfTan[prev] + halfTan[i]) / dists[i]
            weights[i] = w
            totalWeight += w
        }

        // Normalize.
        if totalWeight != 0 {
            for i in 0..<n {
                weights[i] /= totalWeight
            }
        }

        return weights
    }

    /// Applies a set of MVC weights to a polygon's vertices to recover a position.
    /// When called with the same polygon used to compute the weights, returns the
    /// original point. When called with a deformed polygon, returns the morphed
    /// position that preserves relative placement.
    static func apply(weights: [Float], to polygon: [SIMD2<Float>]) -> SIMD2<Float> {
        precondition(weights.count == polygon.count, "weights and polygon must have same length")
        var result = SIMD2<Float>(0, 0)
        for i in 0..<polygon.count {
            result += weights[i] * polygon[i]
        }
        return result
    }
}
