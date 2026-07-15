import Foundation

enum ARPlacementMode: String, Codable, CaseIterable, Identifiable {
    case floor
    case wall
    case ceiling

    var id: String { rawValue }

    static func fromPersisted(_ rawValue: String?) -> ARPlacementMode? {
        guard let rawValue else { return nil }
        switch rawValue {
        case "hanging":
            return .ceiling
        case "shelf":
            return .floor
        default:
            return ARPlacementMode(rawValue: rawValue)
        }
    }

    var label: String {
        switch self {
        case .floor: return L10n.t("AR_PLACEMENT_MODE_FLOOR")
        case .wall: return L10n.t("AR_PLACEMENT_MODE_WALL")
        case .ceiling: return L10n.t("AR_PLACEMENT_MODE_CEILING")
        }
    }

    var icon: String {
        switch self {
        case .floor: return "square"
        case .wall: return "rectangle.portrait"
        case .ceiling: return "arrow.down"
        }
    }

    var acceptedSurfaceTypes: Set<SurfaceType> {
        switch self {
        case .floor:
            return [.floor, .shelf, .table, .windowsill, .furniture]
        case .wall:
            return [.wall]
        case .ceiling:
            return [.ceiling]
        }
    }

    var needsPlantCompatibility: Bool {
        switch self {
        case .wall, .ceiling: return true
        case .floor: return false
        }
    }
}

enum PlantPlacementCompatibility {
    static func supports(_ plant: Plant, mode: ARPlacementMode) -> Bool {
        switch mode {
        case .floor:
            return true
        case .wall:
            return isWallCapable(plant)
        case .ceiling:
            return isHangingCapable(plant)
        }
    }

    static func supportedModes(for plant: Plant) -> Set<ARPlacementMode> {
        Set(ARPlacementMode.allCases.filter { supports(plant, mode: $0) })
    }

    static func isWallCapable(_ plant: Plant) -> Bool {
        if plant.flags?.climbing == true || plant.flags?.trailing == true {
            return true
        }

        let text = searchableText(for: plant)
        let wallKeywords = [
            "climbing", "climber", "vine", "vining", "ivy",
            "grimpant", "grimpante", "grimpe", "liane", "lierre",
            "pothos", "epipremnum", "scindapsus", "pictus", "pictum",
            "philodendron scandens", "philodendron hederaceum", "heartleaf",
            "ceropegia", "woodii", "hoya", "tradescantia", "monstera adansonii"
        ]
        return wallKeywords.contains { text.contains($0) }
    }

    static func isHangingCapable(_ plant: Plant) -> Bool {
        if plant.flags?.trailing == true {
            return true
        }

        let text = searchableText(for: plant)
        let hangingKeywords = [
            "hanging", "trailing", "cascade", "cascading", "string of",
            "suspendu", "suspendue", "suspension", "retombant", "retombante",
            "ceropegia", "woodii", "chaine des coeurs", "string of hearts",
            "hoya bella", "hoya linearis", "hoya",
            "philodendron scandens", "philodendron hederaceum", "heartleaf",
            "pothos", "scindapsus", "pictus", "pictum",
            "dischidia", "rhipsalis", "senecio", "rowleyanus",
            "tradescantia", "chlorophytum", "spider plant"
        ]
        return hangingKeywords.contains { text.contains($0) }
    }

    private static func searchableText(for plant: Plant) -> String {
        var parts = [
            plant.name,
            plant.type,
            plant.description
        ]

        for translation in plant.translations.values {
            parts.append(translation.description)
            parts.append(translation.plantType)
            if let growth = translation.lifeCycle?.growth { parts.append(growth) }
            if let tips = translation.care?.extraTips { parts.append(contentsOf: tips) }
        }

        return parts
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
