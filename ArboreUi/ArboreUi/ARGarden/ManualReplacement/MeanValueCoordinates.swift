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
    /// Special cases (all return early with stable values) :
    ///   - point ≈ vertex          → that vertex gets weight 1 (canonical basis)
    ///   - point on edge interior  → linear blend between the two endpoints
    ///   - degenerate polygon      → uniform weights (apply() returns the centroid)
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

        // Half-angle tangent of each angle (vertex_i, p, vertex_{i+1}) computed
        // via atan2(sin, cos) → tan(theta/2). atan2 is numerically stable across
        // all four quadrants, including near 0 and near ±π, which avoids the
        // (1 - cos)/sin divergence when |sin| is small (cf audit AR F-3).
        var halfTan = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let next = (i + 1) % n
            let cos = simd_clamp(simd_dot(unit[i], unit[next]), -1.0, 1.0)
            // 2D cross product (signed magnitude in the implicit Z axis).
            let sin = unit[i].x * unit[next].y - unit[i].y * unit[next].x
            // Edge case: point on edge between i and next (theta ≈ ±π) →
            // return a linear blend along the edge. Done explicitly because
            // atan2 + tan(π/2) is undefined (infinity).
            if abs(sin) < 1e-6 && cos < 0 {
                let t = dists[next] / (dists[i] + dists[next])
                weights[i] = t
                weights[next] = 1 - t
                return weights
            }
            let theta = atan2(sin, cos)
            halfTan[i] = tan(theta / 2)
        }

        var totalWeight: Float = 0
        for i in 0..<n {
            let prev = (i - 1 + n) % n
            let w = (halfTan[prev] + halfTan[i]) / dists[i]
            weights[i] = w
            totalWeight += w
        }

        // Degenerate fallback (cf audit AR F-5) : if the total weight is zero
        // or non-finite (collinear polygon, NaN propagation from a corner
        // case), return uniform weights so that `apply()` produces the new
        // polygon's centroid instead of (0, 0). Avoids silently teleporting
        // every plant to the session origin.
        guard totalWeight.isFinite, abs(totalWeight) > 1e-6 else {
            return Array(repeating: 1.0 / Float(n), count: n)
        }

        // Normalize.
        for i in 0..<n {
            weights[i] /= totalWeight
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

    /// Signed Shoelace area. Positive = counter-clockwise winding,
    /// negative = clockwise. Used by callers to normalize old/new polygon
    /// winding before computing weights (cf audit AR F-4).
    static func signedArea(_ polygon: [SIMD2<Float>]) -> Float {
        guard polygon.count >= 3 else { return 0 }
        var sum: Float = 0
        for i in 0..<polygon.count {
            let j = (i + 1) % polygon.count
            sum += polygon[i].x * polygon[j].y - polygon[j].x * polygon[i].y
        }
        return sum / 2
    }
}
