import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Coarse semantic label of a real-world surface detected by ARKit.
///
/// Used to drive both placement rules (which plants are compatible with this
/// kind of surface) and the debug visualization. Persisted as a String into
/// `PersistedPlant.surfaceType` (cf issue #186).
///
/// On non-LiDAR devices the label is derived heuristically from
/// `ARPlaneAnchor.alignment` + Y + extent (see `SurfaceClassifier`). On
/// LiDAR devices we replace the heuristic with `ARMeshAnchor.classification`
/// when available (Phase 2 of #186).
enum SurfaceType: String, Codable, CaseIterable {
    case floor
    case wall
    case ceiling
    case shelf
    case table
    case windowsill
    case furniture
    case unknown

    /// Display name in the AR HUD chip.
    var label: String {
        switch self {
        case .floor:      return L10n.t("SURFACE_FLOOR")
        case .wall:       return L10n.t("SURFACE_WALL")
        case .ceiling:    return L10n.t("SURFACE_CEILING")
        case .shelf:      return L10n.t("SURFACE_SHELF")
        case .table:      return L10n.t("SURFACE_TABLE")
        case .windowsill: return L10n.t("SURFACE_WINDOWSILL")
        case .furniture:  return L10n.t("SURFACE_FURNITURE")
        case .unknown:    return L10n.t("SURFACE_UNKNOWN")
        }
    }

    /// Hex color used by the debug viz overlay. Picked to maximise contrast
    /// in a typical indoor scene and to map roughly to "geographic" cues
    /// (blue = floor like water, orange = wall like sunset light).
    var debugHex: String {
        switch self {
        case .floor:      return "#1E40FF"
        case .wall:       return "#FF8B00"
        case .ceiling:    return "#9C27FF"
        case .shelf:      return "#86E300"
        case .table:      return "#1FA84A"
        case .windowsill: return "#00E0FF"
        case .furniture:  return "#FF4B9D"
        case .unknown:    return "#808080"
        }
    }

    #if canImport(UIKit)
    /// `UIColor` derived from `debugHex`. Uses the project-wide
    /// `UIColor(hex:)` extension declared in LoginAuth/Extensions.swift.
    var debugColor: UIColor { UIColor(hex: debugHex) }
    #endif
}
