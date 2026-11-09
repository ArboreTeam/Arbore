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

/// Capacité PHYSIQUE de pose, lue sur la fiche (#792).
///
/// Ce qui vivait ici était le plus conséquent des six chemins de dérivation,
/// et pas parce qu'il était le plus long : la conséquence d'une erreur n'est
/// pas un badge inexact mais **un geste impossible** — une plante déclarée
/// posable au mur alors qu'elle ne l'est pas.
///
/// Les deux listes retirées comptaient 23 et 25 mots-clés, et chacun des trois
/// défauts suivants suffisait à les disqualifier :
///
/// - **C'était une taxonomie botanique dans du code d'interface.** `pothos`,
///   `hoya`, `rhipsalis`, `senecio`, `rowleyanus`, `dischidia` étaient écrits
///   en dur : chaque nouvelle plante grimpante exigeait une modification du
///   binaire, alors que la donnée vit dans la fiche.
/// - **L'appariement n'avait aucune frontière de mot.** `text.contains("hoya")`
///   appariait n'importe quelle chaîne contenant ces quatre lettres, dans la
///   prose des quatre langues. Le backend a son `contientMots` pour exactement
///   cette raison ; iOS ne l'avait pas.
/// - **Le booléen était à moitié vrai.** `flags.climbing == false` ne disait
///   pas « ne grimpe pas », il faisait retomber sur les mots-clés.
///
/// Le vocabulaire existait déjà : `ARPlacementMode` est une énumération
/// fermée. La fiche porte désormais ses modes dans `botanicalProfile.placement`.
enum PlantPlacementCompatibility {
    static func supports(_ plant: Plant, mode: ARPlacementMode) -> Bool {
        supportedModes(for: plant).contains(mode)
    }

    /// Les modes de pose admis pour cette plante.
    ///
    /// `.floor` est toujours admis : poser une plante au sol ne demande aucune
    /// capacité particulière, et c'est le seul mode dont l'absence de donnée
    /// ne peut pas produire un geste impossible.
    ///
    /// `.wall` et `.ceiling` suivent l'ordre de lecture de la toxicité :
    ///
    /// 1. le champ clos `placement` décide quand il existe — y compris pour
    ///    REFUSER, puisqu'une liste qui ne contient pas `.wall` est une
    ///    affirmation et non un silence ;
    /// 2. à défaut, les drapeaux servent de repli, et seul leur `true`
    ///    informe. Un `climbing: false` ne vaut pas « ne grimpe pas ».
    static func supportedModes(for plant: Plant) -> Set<ARPlacementMode> {
        if let declares = plant.botanicalProfile?.placement {
            // Présent décide, même vide : une liste présente qui ne contient
            // pas `.wall` est une affirmation — « on a cherché, elle ne tient
            // pas au mur » — et non un silence. Seule l'ABSENCE du champ
            // ouvre le repli par drapeaux.
            return declares.values.union([.floor])
        }

        var modes: Set<ARPlacementMode> = [.floor]
        // Grimper ou retomber suffit à tenir au mur ; seule la retombée tient
        // au plafond. C'est le repli exact de l'ancienne branche par drapeaux,
        // conservé tel quel pour ne pas perdre de capacité en attendant le
        // remplissage de `placement`.
        if plant.trait(.climbing) == true || plant.trait(.trailing) == true {
            modes.insert(.wall)
        }
        if plant.trait(.trailing) == true {
            modes.insert(.ceiling)
        }
        return modes
    }

    static func isWallCapable(_ plant: Plant) -> Bool {
        supports(plant, mode: .wall)
    }

    static func isHangingCapable(_ plant: Plant) -> Bool {
        supports(plant, mode: .ceiling)
    }
}
