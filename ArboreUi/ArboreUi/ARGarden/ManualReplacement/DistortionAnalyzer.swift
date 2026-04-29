import Foundation
import simd

/// Computes how much the local neighborhood of a plant got stretched/compressed
/// by the morphing. The score is a ratio between the average distance to the 3
/// closest boundary vertices, before vs after the morph.
///
/// - score ≈ 1.0: neighborhood preserved — placement is reliable
/// - score > 1.0: stretched — plant is in a region that grew
/// - score < 1.0: compressed — plant is in a region that shrunk
///
/// We always report `max(score, 1/score)` so that both expansion and compression
/// flag a warning equally.
enum DistortionAnalyzer {

    /// Returns the symmetric distortion score (≥ 1.0).
    static func score(
        oldPosition: SIMD2<Float>,
        newPosition: SIMD2<Float>,
        oldBoundary: [SIMD2<Float>],
        newBoundary: [SIMD2<Float>]
    ) -> Float {
        guard oldBoundary.count == newBoundary.count, oldBoundary.count >= 3 else { return 1 }

        // Find indices of 3 closest old-boundary vertices to the old position.
        let kClosest = 3
        let indices = closestVertexIndices(to: oldPosition, in: oldBoundary, count: kClosest)

        // Average distance in old vs new boundary using same indices.
        var oldAvg: Float = 0
        var newAvg: Float = 0
        for i in indices {
            oldAvg += simd_length(oldBoundary[i] - oldPosition)
            newAvg += simd_length(newBoundary[i] - newPosition)
        }
        oldAvg /= Float(indices.count)
        newAvg /= Float(indices.count)

        guard oldAvg > 1e-5, newAvg > 1e-5 else { return 1 }

        let ratio = newAvg / oldAvg
        return max(ratio, 1 / ratio)
    }

    /// Maps a numeric score to a severity bucket.
    static func severity(for score: Float) -> DistortionSeverity {
        if score < 1.2 { return .ok }
        if score < 1.8 { return .moderate }
        return .severe
    }

    /// Returns a French cardinal label for the position relative to the centroid.
    /// Example: (0.5, -0.5) with centroid at (0,0) → "NORD-EST" (z negative = north
    /// in our AR convention).
    static func cardinalZone(of position: SIMD2<Float>, centroid: SIMD2<Float>) -> String {
        let dx = position.x - centroid.x
        let dz = position.y - centroid.y  // SIMD2 used as (x, z)

        let nsThreshold: Float = 0.15  // tolerance to call something "centre"
        let ewThreshold: Float = 0.15

        var ns: String? = nil
        var ew: String? = nil

        if dz < -nsThreshold { ns = "NORD" }
        else if dz > nsThreshold { ns = "SUD" }

        if dx > ewThreshold { ew = "EST" }
        else if dx < -ewThreshold { ew = "OUEST" }

        switch (ns, ew) {
        case (let n?, let e?): return "\(n)-\(e)"
        case (let n?, nil):    return n
        case (nil, let e?):    return e
        case (nil, nil):       return "CENTRE"
        }
    }

    // MARK: - Helpers

    private static func closestVertexIndices(
        to point: SIMD2<Float>,
        in polygon: [SIMD2<Float>],
        count: Int
    ) -> [Int] {
        let withDistances = polygon.enumerated().map { idx, v in
            (idx, simd_length(v - point))
        }
        let sorted = withDistances.sorted { $0.1 < $1.1 }
        return sorted.prefix(min(count, polygon.count)).map { $0.0 }
    }
}
