import Foundation
import simd

struct MorphedPlant {
    let plantId: String
    let plantName: String
    let originalPlant: PersistedPlant
    let newTransform: simd_float4x4
    let warning: DistortionWarning?  // nil if severity is .ok
}

struct MorphResult {
    let morphedPlants: [MorphedPlant]
    /// Convenient access list for the UI: only entries with .moderate or .severe.
    var warnings: [DistortionWarning] {
        morphedPlants.compactMap { $0.warning }
    }
}

/// Morphs a set of saved plants from an old boundary onto a new one using
/// Mean Value Coordinates and reports per-plant distortion.
enum GardenMorpher {

    /// - Parameters:
    ///   - oldPlants: plants captured at save-time (positions in old AR coordinates).
    ///   - oldBoundary: boundary at save-time (3D points on the floor; we project to XZ).
    ///   - newBoundary: new boundary traced by the user (3D points; we project to XZ).
    ///   - floorY: optional Y to snap plants to the new detected floor. If nil, we
    ///     preserve the old plant's relative Y delta to the old floor centroid.
    static func morph(
        oldPlants: [PersistedPlant],
        oldBoundary: [SIMD3<Float>],
        newBoundary: [SIMD3<Float>],
        floorY: Float? = nil
    ) -> MorphResult {
        // Defensive: empty / mismatched boundaries.
        guard !oldPlants.isEmpty else { return MorphResult(morphedPlants: []) }

        let oldPolygon2D = oldBoundary.map { SIMD2<Float>($0.x, $0.z) }
        var newPolygon2D = newBoundary.map { SIMD2<Float>($0.x, $0.z) }
        var newBoundary3D = newBoundary

        // Sanity check: same vertex count required for MVC re-application.
        guard oldPolygon2D.count == newPolygon2D.count, oldPolygon2D.count >= 3 else {
            return fallbackToCenter(plants: oldPlants, newBoundary: newBoundary, floorY: floorY)
        }

        // Winding normalization (cf audit AR F-4) : si l'utilisateur a tracé
        // la nouvelle boundary en sens opposé de l'ancienne (CW vs CCW), les
        // index polygon[i] ne correspondent plus aux mêmes coins logiques, et
        // MVC.apply produit une position miroir. On retourne la nouvelle
        // boundary pour rétablir la correspondance index-à-index.
        let oldSignedArea = MeanValueCoordinates.signedArea(oldPolygon2D)
        let newSignedArea = MeanValueCoordinates.signedArea(newPolygon2D)
        if oldSignedArea * newSignedArea < 0 {
            newPolygon2D.reverse()
            newBoundary3D.reverse()
        }

        let oldCentroid2D = centroid(of: oldPolygon2D)
        let newCentroid2D = centroid(of: newPolygon2D)

        // Floor Y is approximated by the average Y of each boundary's tap
        // points (the user taps the floor, so the average is a good proxy).
        // We use this to PRESERVE THE ELEVATION DELTA of each plant: a plant
        // saved at oldFloorY + 0.6 ends up at newFloorY + 0.6, regardless of
        // session-Y origin differences.
        let oldFloorY = oldBoundary.reduce(Float(0)) { $0 + $1.y } / Float(oldBoundary.count)
        let newFloorY = floorY ?? (newBoundary3D.reduce(Float(0)) { $0 + $1.y } / Float(newBoundary3D.count))
        let floorDelta = newFloorY - oldFloorY

        let morphed: [MorphedPlant] = oldPlants.map { plant in
            let plantPos2D = SIMD2<Float>(plant.position[0], plant.position[2])

            // 1. MVC weights against the old polygon.
            let weights = MeanValueCoordinates.weights(point: plantPos2D, polygon: oldPolygon2D)

            // 2. Apply weights to the new polygon to get the morphed 2D position.
            var newPos2D = MeanValueCoordinates.apply(weights: weights, to: newPolygon2D)

            // 3. If the morphed point fell outside the new polygon (degenerate cases),
            //    snap it onto the boundary at the closest edge point.
            if !pointInPolygon(newPos2D, polygon: newPolygon2D) {
                newPos2D = closestPointOnPolygonEdge(point: newPos2D, polygon: newPolygon2D)
            }

            // 4. Build the new 4x4 transform. We preserve the plant's elevation
            //    above the original floor by shifting Y by `floorDelta` (the
            //    difference between new and old floor Y). Floor plants stay on
            //    the floor; elevated plants keep their height.
            let oldY = plant.position[1]
            let newY = oldY + floorDelta
            let newTransform = buildTransform(
                originalTransform: plant.transform,
                newX: newPos2D.x,
                newY: newY,
                newZ: newPos2D.y,
                snapY: newY
            )

            // 5. Distortion analysis.
            let score = DistortionAnalyzer.score(
                oldPosition: plantPos2D,
                newPosition: newPos2D,
                oldBoundary: oldPolygon2D,
                newBoundary: newPolygon2D
            )
            let severity = DistortionAnalyzer.severity(for: score)

            let warning: DistortionWarning?
            switch severity {
            case .ok:
                warning = nil
            case .moderate, .severe:
                let zone = DistortionAnalyzer.cardinalZone(of: plantPos2D, centroid: oldCentroid2D)
                warning = DistortionWarning(
                    plantId: plant.plantID,
                    plantName: plant.plantName,
                    zone: zone,
                    score: score,
                    severity: severity
                )
            }

            return MorphedPlant(
                plantId: plant.plantID,
                plantName: plant.plantName,
                originalPlant: plant,
                newTransform: newTransform,
                warning: warning
            )
        }

        // Suppress unused warning while keeping centroid available for future use.
        _ = newCentroid2D

        return MorphResult(morphedPlants: morphed)
    }

    // MARK: - Helpers

    private static func centroid(of polygon: [SIMD2<Float>]) -> SIMD2<Float> {
        guard !polygon.isEmpty else { return .zero }
        return polygon.reduce(SIMD2<Float>.zero, +) / Float(polygon.count)
    }

    /// Even-odd ray casting test.
    private static func pointInPolygon(_ p: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            let intersect = ((pi.y > p.y) != (pj.y > p.y)) &&
                (p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y + 1e-9) + pi.x)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }

    private static func closestPointOnPolygonEdge(
        point p: SIMD2<Float>,
        polygon: [SIMD2<Float>]
    ) -> SIMD2<Float> {
        var best = polygon[0]
        var bestDist = Float.infinity
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            let candidate = closestPointOnSegment(p: p, a: a, b: b)
            let d = simd_length(candidate - p)
            if d < bestDist {
                bestDist = d
                best = candidate
            }
        }
        return best
    }

    private static func closestPointOnSegment(p: SIMD2<Float>, a: SIMD2<Float>, b: SIMD2<Float>) -> SIMD2<Float> {
        let ab = b - a
        let lenSq = simd_dot(ab, ab)
        guard lenSq > 1e-9 else { return a }
        let t = simd_clamp(simd_dot(p - a, ab) / lenSq, 0, 1)
        return a + ab * t
    }

    /// Build a 4x4 transform that keeps the original rotation/scale (encoded in the
    /// stored 16-float matrix) but updates the translation column.
    private static func buildTransform(
        originalTransform: [Float],
        newX: Float,
        newY: Float,
        newZ: Float,
        snapY: Float
    ) -> simd_float4x4 {
        var matrix = matrixFromFloatArray(originalTransform) ?? matrix_identity_float4x4
        // Column 3 = translation column in column-major SIMD float4x4.
        matrix.columns.3 = SIMD4<Float>(newX, snapY, newZ, 1)
        return matrix
    }

    private static func matrixFromFloatArray(_ a: [Float]) -> simd_float4x4? {
        guard a.count == 16 else { return nil }
        return simd_float4x4(
            SIMD4<Float>(a[0], a[1], a[2], a[3]),
            SIMD4<Float>(a[4], a[5], a[6], a[7]),
            SIMD4<Float>(a[8], a[9], a[10], a[11]),
            SIMD4<Float>(a[12], a[13], a[14], a[15])
        )
    }

    /// Fallback when boundaries don't match: place all plants at the new centroid
    /// (preserving relative offsets to old centroid scaled by an arbitrary factor).
    private static func fallbackToCenter(
        plants: [PersistedPlant],
        newBoundary: [SIMD3<Float>],
        floorY: Float?
    ) -> MorphResult {
        guard !newBoundary.isEmpty else { return MorphResult(morphedPlants: []) }

        let centroid3D = newBoundary.reduce(SIMD3<Float>.zero, +) / Float(newBoundary.count)
        let avgFloorY = floorY ?? centroid3D.y

        let morphed = plants.map { plant -> MorphedPlant in
            let oldX = plant.position[0]
            let oldZ = plant.position[2]
            let oldY = plant.position[1]

            let newTransform = buildTransform(
                originalTransform: plant.transform,
                newX: centroid3D.x + oldX * 0.5,  // soft shrink around new center
                newY: oldY,
                newZ: centroid3D.z + oldZ * 0.5,
                snapY: avgFloorY
            )

            let warning = DistortionWarning(
                plantId: plant.plantID,
                plantName: plant.plantName,
                zone: "CENTRE",
                score: 999,
                severity: .severe
            )

            return MorphedPlant(
                plantId: plant.plantID,
                plantName: plant.plantName,
                originalPlant: plant,
                newTransform: newTransform,
                warning: warning
            )
        }
        return MorphResult(morphedPlants: morphed)
    }
}
