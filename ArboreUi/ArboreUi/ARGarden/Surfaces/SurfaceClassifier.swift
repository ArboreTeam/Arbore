import Foundation
import simd

#if canImport(ARKit)
import ARKit
#endif

/// Geometric description of a plane, extracted from `ARPlaneAnchor` and
/// reduced to pure values so the classifier logic stays testable without
/// having to fake ARKit types.
struct PlaneFeatures: Equatable {
    enum Alignment { case horizontal, vertical }

    let alignment: Alignment
    /// World-space center of the plane (anchor.transform · anchor.center, in y-up world).
    let center: SIMD3<Float>
    /// Width / depth of the plane in meters along the plane's local axes.
    let extentWidth: Float
    let extentDepth: Float
    /// Outward normal in world space.
    let normal: SIMD3<Float>
}

/// Heuristic classifier turning `PlaneFeatures` + world context into a
/// `SurfaceType`. Pure function ; no ARKit dependency so it can be unit-
/// tested with fabricated inputs.
///
/// The heuristic uses:
/// - **alignment** to separate walls from horizontal surfaces immediately
/// - **Y** to distinguish floor / shelf / table / ceiling
/// - **extent** to differentiate small (shelf) vs large (table) horizontal
/// - **nearby verticals** for windowsill detection (horizontal plane whose
///   extent visibly touches a vertical plane's extent)
///
/// Tweakable thresholds are exposed as static lets so the unit tests can
/// document the chosen values.
enum SurfaceClassifier {
    /// Anything within this distance of the lowest horizontal plane is
    /// considered to BE the floor (vs a low table).
    static let floorYTolerance: Float = 0.10
    /// Horizontal planes above (cameraY + this) are classified as ceiling.
    /// The user's eyes are typically ~10cm below the camera so this kicks
    /// in once the surface is clearly overhead.
    static let ceilingHeightAboveCamera: Float = 0.50
    /// Shelf vs table cutoff. Area-based; below = shelf, above = table.
    static let shelfTableAreaCutoff: Float = 1.0 // m²
    /// A horizontal plane within this radius of a vertical plane's extent
    /// is considered a windowsill (the rim adjacent to a wall).
    static let windowsillAdjacencyRadius: Float = 0.15

    /// Classify a single plane given the world context.
    ///
    /// - Parameters:
    ///   - plane: the plane to classify
    ///   - floorY: y-coord of the surface we believe is the floor, in world
    ///     coords. Typically the minimum Y among all horizontal planes seen
    ///     so far. `nil` if no floor candidate yet — in that case the
    ///     lowest horizontal plane is best-effort labelled `.floor`.
    ///   - cameraY: y-coord of the camera in world space.
    ///   - nearbyVerticals: vertical planes whose extent is within
    ///     `windowsillAdjacencyRadius` of `plane.center` — used for the
    ///     windowsill rule. Callers can pass all verticals; the classifier
    ///     will filter by distance internally.
    static func classify(
        plane: PlaneFeatures,
        floorY: Float?,
        cameraY: Float,
        nearbyVerticals: [PlaneFeatures] = []
    ) -> SurfaceType {
        switch plane.alignment {
        case .vertical:
            return .wall

        case .horizontal:
            let y = plane.center.y

            // 1. Ceiling: comfortably above the camera.
            if y > cameraY + ceilingHeightAboveCamera {
                return .ceiling
            }

            // 2. Floor: at the known floor Y, OR the only horizontal we've
            //    seen yet (best-effort).
            if let floor = floorY {
                if abs(y - floor) <= floorYTolerance {
                    return .floor
                }
            } else {
                return .floor
            }

            // 3. Windowsill: horizontal plane adjacent to a wall.
            if isAdjacentToVertical(plane: plane, verticals: nearbyVerticals) {
                return .windowsill
            }

            // 4. Shelf vs table by area.
            let area = plane.extentWidth * plane.extentDepth
            return area < shelfTableAreaCutoff ? .shelf : .table
        }
    }

    /// True when at least one of the candidate vertical planes touches the
    /// horizontal plane's footprint within `windowsillAdjacencyRadius`.
    private static func isAdjacentToVertical(
        plane: PlaneFeatures,
        verticals: [PlaneFeatures]
    ) -> Bool {
        for vert in verticals where vert.alignment == .vertical {
            let dx = plane.center.x - vert.center.x
            let dz = plane.center.z - vert.center.z
            let horizontalDistance = sqrt(dx * dx + dz * dz)
            // The wall has a wide extent — we shrink the horizontal plane's
            // candidate radius by half its width so a small windowsill
            // touching the wall counts as adjacent. For a wider table that
            // ends 50cm from a wall, this still correctly says NOT adjacent.
            let shrink = max(plane.extentWidth, plane.extentDepth) * 0.5
            if horizontalDistance - shrink <= windowsillAdjacencyRadius {
                // Plus, the Y of the horizontal must fall within the wall's
                // vertical extent — a 1m-high windowsill on a 2.5m wall ✓,
                // but a horizontal plane far above the wall's top ✗.
                let verticalHalf = max(vert.extentWidth, vert.extentDepth) * 0.5
                if abs(plane.center.y - vert.center.y) <= verticalHalf {
                    return true
                }
            }
        }
        return false
    }
}

#if canImport(ARKit)
extension PlaneFeatures {
    /// Construct from an `ARPlaneAnchor`. Reads `planeExtent` (iOS 16+) to
    /// get accurate width/height ; falls back to the deprecated `extent`
    /// on earlier OSes.
    init(_ anchor: ARPlaneAnchor) {
        let center4 = anchor.transform * SIMD4<Float>(anchor.center, 1)
        let center = SIMD3<Float>(center4.x, center4.y, center4.z)

        let width: Float
        let depth: Float
        if #available(iOS 16.0, *) {
            width = anchor.planeExtent.width
            depth = anchor.planeExtent.height
        } else {
            width = anchor.extent.x
            depth = anchor.extent.z
        }

        // The plane normal lives in the local +Y axis of the anchor's frame
        // (ARKit convention for plane anchors).
        let normal4 = anchor.transform * SIMD4<Float>(0, 1, 0, 0)
        let normal = simd_normalize(SIMD3<Float>(normal4.x, normal4.y, normal4.z))

        self.alignment = (anchor.alignment == .vertical) ? .vertical : .horizontal
        self.center = center
        self.extentWidth = width
        self.extentDepth = depth
        self.normal = normal
    }
}
#endif
