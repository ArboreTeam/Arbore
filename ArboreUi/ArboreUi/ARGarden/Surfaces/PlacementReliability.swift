import Foundation

enum SurfaceHitSource: String, Codable {
    case existingPlaneGeometry
    case existingPlaneInfinite
    case estimatedPlane
    case syntheticFallback

    var baseScore: Float {
        switch self {
        case .existingPlaneGeometry:
            return 0.36
        case .existingPlaneInfinite:
            return 0.25
        case .estimatedPlane:
            return 0.14
        case .syntheticFallback:
            return 0.08
        }
    }

    var needsStabilityBeforeCommit: Bool {
        switch self {
        case .existingPlaneGeometry:
            return false
        case .existingPlaneInfinite, .estimatedPlane, .syntheticFallback:
            return true
        }
    }

    var isEstimatedLike: Bool {
        switch self {
        case .existingPlaneGeometry:
            return false
        case .existingPlaneInfinite, .estimatedPlane, .syntheticFallback:
            return true
        }
    }
}

enum PlacementReliabilityReason: String {
    case ready
    case trackingLimited
    case incompatibleSurface
    case unstableSurface
    case lowConfidence
}

struct PlacementReliability: Equatable {
    enum Level: String {
        case unavailable
        case weak
        case usable
        case strong
    }

    let score: Float
    let level: Level
    let reason: PlacementReliabilityReason
    let stableDuration: TimeInterval

    var isPlaceable: Bool {
        reason == .ready && (level == .usable || level == .strong)
    }

    static let unavailable = PlacementReliability(
        score: 0,
        level: .unavailable,
        reason: .lowConfidence,
        stableDuration: 0
    )
}

enum PlacementReliabilityScorer {
    static let minimumCommitScore: Float = 0.58
    static let minimumEstimatedStableDuration: TimeInterval = 0.35
    static let fullStabilityDuration: TimeInterval = 0.55

    static func evaluate(
        source: SurfaceHitSource,
        trackingNormal: Bool,
        surfaceAccepted: Bool,
        planeArea: Float?,
        cameraDistance: Float?,
        stableDuration: TimeInterval
    ) -> PlacementReliability {
        guard surfaceAccepted else {
            return PlacementReliability(
                score: 0.12,
                level: .weak,
                reason: .incompatibleSurface,
                stableDuration: stableDuration
            )
        }

        guard trackingNormal else {
            return PlacementReliability(
                score: min(0.35, source.baseScore),
                level: .weak,
                reason: .trackingLimited,
                stableDuration: stableDuration
            )
        }

        var score: Float = 0.22 + source.baseScore

        if let planeArea {
            let normalized = min(max(planeArea / 1.2, 0), 1)
            score += normalized * 0.16
        }

        if let cameraDistance {
            switch cameraDistance {
            case 0.25...3.5:
                score += 0.10
            case 3.5...5.0:
                score += 0.04
            default:
                score += 0
            }
        }

        let stabilityRatio = min(max(Float(stableDuration / fullStabilityDuration), 0), 1)
        score += stabilityRatio * 0.20
        score = min(max(score, 0), 1)

        if source.needsStabilityBeforeCommit,
           stableDuration < minimumEstimatedStableDuration {
            return PlacementReliability(
                score: score,
                level: level(for: score),
                reason: .unstableSurface,
                stableDuration: stableDuration
            )
        }

        guard score >= minimumCommitScore else {
            return PlacementReliability(
                score: score,
                level: level(for: score),
                reason: .lowConfidence,
                stableDuration: stableDuration
            )
        }

        return PlacementReliability(
            score: score,
            level: level(for: score),
            reason: .ready,
            stableDuration: stableDuration
        )
    }

    private static func level(for score: Float) -> PlacementReliability.Level {
        switch score {
        case 0.78...:
            return .strong
        case minimumCommitScore..<0.78:
            return .usable
        case 0.01..<minimumCommitScore:
            return .weak
        default:
            return .unavailable
        }
    }
}
