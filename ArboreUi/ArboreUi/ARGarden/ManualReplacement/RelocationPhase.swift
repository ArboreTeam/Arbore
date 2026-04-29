import Foundation

/// Lifecycle of a garden re-open session on a non-LiDAR device.
enum RelocationPhase: Equatable {
    /// ARKit is trying to relocalize the saved WorldMap. Coaching overlay is shown.
    case scanning
    /// User chose to replace manually — they are tapping the floor to define the new boundary.
    case tracingBoundary
    /// New boundary validated, plants are shown as ghost previews at morphed positions.
    case morphingPreview
    /// User confirmed — plants are opaque and can be drag/pinch-adjusted.
    case adjusting
    /// Final state, transient before dismiss.
    case completed

    /// True when the user took manual control (not relying on ARKit relocalization anymore).
    var isManualReplacement: Bool {
        switch self {
        case .tracingBoundary, .morphingPreview, .adjusting, .completed:
            return true
        case .scanning:
            return false
        }
    }
}
