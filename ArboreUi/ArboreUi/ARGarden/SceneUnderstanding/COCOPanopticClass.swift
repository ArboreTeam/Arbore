import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Coarse semantic category Arbore cares about, mapped from any COCO
/// panoptic label string returned by DETR (cf #187 / #186 Phase 3).
///
/// COCO panoptic has 133 raw labels (80 things + 53 stuff). Most of them
/// are irrelevant for an indoor plant-placement app — we collapse them
/// into a handful of business categories that drive :
///   - the **viz colour** (so two "wall" sublabels share the same hue)
///   - the **SurfaceType** mapping (so a `floor-wood` mask augments the
///     `SurfaceType.floor` evidence side-by-side with ARPlaneAnchor's
///     geometric heuristic)
///   - placement compatibility rules in Phase 4 of #186
///
/// Labels are matched by string (case-insensitive, dashes/spaces
/// equivalent). Lookup against the runtime dict comes from
/// `DETRPostProcessor.ids2Labels` (Apple-provided in
/// huggingface/coreml-examples) so we never hardcode ID-to-name pairs —
/// those depend on Apple's model packaging.
enum COCOPanopticCategory: String, CaseIterable {
    // Structural surfaces
    case floor
    case wall
    case ceiling
    case window
    case door
    case mirror
    case stairs
    case curtain
    case shelf

    // Sittable / placeable furniture
    case couch
    case chair
    case bed
    case diningTable
    case bench
    case counter
    case cabinet
    case tableOther       // table-merged stuff

    // Existing plants / vegetation
    case pottedPlant
    case vase
    case flower
    case tree

    // Appliances + tech (unplaceable, mostly avoid)
    case tv
    case laptop
    case appliance        // microwave, oven, refrigerator, dishwasher…
    case sink
    case toilet
    case light

    // Living things — ignore for placement (but visible in viz)
    case person
    case animal

    /// Catch-all for any label we haven't categorised.
    case other

    /// Display name, in French where it makes sense for the debug UI.
    var label: String {
        switch self {
        case .floor:        return "Sol"
        case .wall:         return "Mur"
        case .ceiling:      return "Plafond"
        case .window:       return "Fenêtre"
        case .door:         return "Porte"
        case .mirror:       return "Miroir"
        case .stairs:       return "Escalier"
        case .curtain:      return "Rideau"
        case .shelf:        return "Étagère"
        case .couch:        return "Canapé"
        case .chair:        return "Chaise"
        case .bed:          return "Lit"
        case .diningTable:  return "Table"
        case .bench:        return "Banc"
        case .counter:      return "Comptoir"
        case .cabinet:      return "Armoire"
        case .tableOther:   return "Table"
        case .pottedPlant:  return "Plante"
        case .vase:         return "Vase"
        case .flower:       return "Fleur"
        case .tree:         return "Arbre"
        case .tv:           return "TV"
        case .laptop:       return "Laptop"
        case .appliance:    return "Appareil"
        case .sink:         return "Évier"
        case .toilet:       return "Toilettes"
        case .light:        return "Lampe"
        case .person:       return "Personne"
        case .animal:       return "Animal"
        case .other:        return "?"
        }
    }

    /// Hex colour used by the SemSeg overlay. Aligned with `SurfaceType`
    /// palette where the categories overlap (floor blue, wall orange, …)
    /// so the eye links DETR's mask with Phase 1's gizmo.
    var debugHex: String {
        switch self {
        case .floor:        return "#1E40FF"
        case .wall:         return "#FF8B00"
        case .ceiling:      return "#9C27FF"
        case .window:       return "#00B8E6"
        case .door:         return "#7A5230"
        case .mirror:       return "#C0C0FF"
        case .stairs:       return "#6E4F2A"
        case .curtain:      return "#D9A6FF"
        case .shelf:        return "#86E300"
        case .couch:        return "#E94560"
        case .chair:        return "#FFD22E"
        case .bed:          return "#9B59B6"
        case .diningTable:  return "#1FA84A"
        case .bench:        return "#A2855F"
        case .counter:      return "#39C6FF"
        case .cabinet:      return "#754F44"
        case .tableOther:   return "#1FA84A"
        case .pottedPlant:  return "#3DDC97"
        case .vase:         return "#FFB200"
        case .flower:       return "#FF77AA"
        case .tree:         return "#2D8A4B"
        case .tv:           return "#202028"
        case .laptop:       return "#404048"
        case .appliance:    return "#9AA0A6"
        case .sink:         return "#7BC2F9"
        case .toilet:       return "#E6E6E6"
        case .light:        return "#FFF59D"
        case .person:       return "#FF4D6D"
        case .animal:       return "#FF8C42"
        case .other:        return "#808080"
        }
    }

    #if canImport(UIKit)
    var debugColor: UIColor { UIColor(hex: debugHex) }
    #endif

    // MARK: - Mapping from COCO label strings

    /// Convert a raw COCO panoptic label (as exposed by DETR's runtime
    /// metadata) into one of our coarse categories. Match is
    /// case-insensitive, with `-` and `_` both treated as a space.
    static func category(for cocoLabel: String) -> COCOPanopticCategory {
        let key = normalise(cocoLabel)
        return labelToCategory[key] ?? .other
    }

    private static func normalise(_ label: String) -> String {
        var s = label.lowercased()
        s = s.replacingOccurrences(of: "_", with: " ")
        s = s.replacingOccurrences(of: "-", with: " ")
        // Strip "-merged" / "-stuff" / "-other" suffixes which COCO uses
        // to disambiguate panoptic sub-classes but which are noise for us.
        for suffix in [" merged", " stuff", " other"] {
            if s.hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count))
            }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Static lookup table — covers every COCO panoptic label that maps
    /// to an Arbore-relevant category. Anything not listed here lands on
    /// `.other` via `category(for:)` fallback.
    private static let labelToCategory: [String: COCOPanopticCategory] = {
        var t: [String: COCOPanopticCategory] = [:]

        // Floors : COCO has 3 floor sub-labels in panoptic.
        for k in ["floor wood", "floor", "rug"] { t[k] = .floor }

        // Walls : 5 variants.
        for k in ["wall brick", "wall stone", "wall tile", "wall wood", "wall"] { t[k] = .wall }

        // Ceiling / window / door / mirror / stairs / curtain / shelf.
        t["ceiling"] = .ceiling
        for k in ["window blind", "window"] { t[k] = .window }
        t["door"] = .door
        t["mirror"] = .mirror
        t["stairs"] = .stairs
        t["curtain"] = .curtain
        t["shelf"] = .shelf

        // Furniture.
        t["couch"] = .couch
        t["chair"] = .chair
        t["bed"] = .bed
        t["dining table"] = .diningTable
        t["bench"] = .bench
        t["counter"] = .counter
        t["cabinet"] = .cabinet
        t["table"] = .tableOther

        // Plants / vegetation.
        t["potted plant"] = .pottedPlant
        t["vase"] = .vase
        t["flower"] = .flower
        t["tree"] = .tree

        // Appliances.
        for k in ["microwave", "oven", "refrigerator", "dishwasher", "toaster"] { t[k] = .appliance }
        t["sink"] = .sink
        t["toilet"] = .toilet
        t["tv"] = .tv
        t["laptop"] = .laptop
        t["light"] = .light

        // Living things.
        t["person"] = .person
        for k in ["cat", "dog", "bird", "horse"] { t[k] = .animal }

        return t
    }()
}
