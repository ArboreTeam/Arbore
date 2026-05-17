import Foundation
import OSLog
import simd
import ARKit
import SceneKit

/// Centralised loggers for AR/Garden/Plants flows.
///
/// One subsystem per app; categories are split by feature. Filter in
/// Console.app or via `log stream --predicate 'subsystem == "com.arboreteam.arbore"'`.
///
/// Default level is `notice` — only state transitions and outcomes. `debug`
/// is reserved for per-frame or verbose tracing and is not persisted unless
/// the developer is actively streaming.
enum AppLog {
    private static let subsystem = "com.arboreteam.arbore"

    /// AR session lifecycle: makeUIView, session.run, world map load, relocalization status.
    static let arSession = Logger(subsystem: subsystem, category: "AR.Session")

    /// ARAnchor lifecycle: add, didAdd, didUpdate, didRemove.
    static let arAnchor = Logger(subsystem: subsystem, category: "AR.Anchor")

    /// Garden save flow: validate, capture, normalize, persist (scene JSON + worldmap).
    static let gardenSave = Logger(subsystem: subsystem, category: "Garden.Save")

    /// Garden load flow: scene JSON read, restoreScene orchestration.
    static let gardenLoad = Logger(subsystem: subsystem, category: "Garden.Load")

    /// Per-plant placement: model load, bounding box, scale + pivot, final world transform.
    static let plants = Logger(subsystem: subsystem, category: "Plants")

    /// Manual replacement (Issue #111): boundary tracing, morphing, ghost preview.
    static let manualReplace = Logger(subsystem: subsystem, category: "AR.ManualReplace")

    /// Depth-anything mesh viz pipeline (non-LiDAR scene reconstruction).
    static let depthMesh = Logger(subsystem: subsystem, category: "AR.DepthMesh")
}

// MARK: - Compact descriptions for SIMD / matrix types
//
// Apple's OSLogMessage doesn't know about SIMD types, so falling through
// to String(describing:) dumps verbose multi-line output. These helpers
// produce one-line, fixed-precision strings safe to mark `.public`.

extension SIMD3 where Scalar == Float {
    var logDescription: String {
        String(format: "(%.3f, %.3f, %.3f)", x, y, z)
    }
}

extension SIMD2 where Scalar == Float {
    var logDescription: String {
        String(format: "(%.3f, %.3f)", x, y)
    }
}

extension simd_float4x4 {
    /// Compact translation + a quick rotation summary. Use this instead of
    /// dumping all 16 floats — translation is by far the most useful field
    /// for diagnosing AR placement bugs.
    var logDescription: String {
        let t = columns.3
        // Magnitude of basis columns gives the (uniform-or-not) scale baked in.
        let s0 = simd_length(SIMD3<Float>(columns.0.x, columns.0.y, columns.0.z))
        let s1 = simd_length(SIMD3<Float>(columns.1.x, columns.1.y, columns.1.z))
        let s2 = simd_length(SIMD3<Float>(columns.2.x, columns.2.y, columns.2.z))
        return String(format: "t=(%.3f,%.3f,%.3f) s=(%.3f,%.3f,%.3f)",
                      t.x, t.y, t.z, s0, s1, s2)
    }
}

extension SCNVector3 {
    var logDescription: String {
        String(format: "(%.3f, %.3f, %.3f)", x, y, z)
    }
}

// MARK: - ARKit enum descriptions

extension ARFrame.WorldMappingStatus {
    var logDescription: String {
        switch self {
        case .notAvailable: return "notAvailable"
        case .limited:      return "limited"
        case .extending:    return "extending"
        case .mapped:       return "mapped"
        @unknown default:   return "unknown(\(self.rawValue))"
        }
    }
}

extension ARCamera.TrackingState {
    var logDescription: String {
        switch self {
        case .notAvailable:
            return "notAvailable"
        case .normal:
            return "normal"
        case .limited(let reason):
            switch reason {
            case .initializing:        return "limited.initializing"
            case .relocalizing:        return "limited.relocalizing"
            case .excessiveMotion:     return "limited.excessiveMotion"
            case .insufficientFeatures: return "limited.insufficientFeatures"
            @unknown default:           return "limited.unknown"
            }
        }
    }
}
