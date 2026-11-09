import Foundation
import simd

/// La décision de pose automatique selon la lumière, extraite pour être
/// vérifiable (#795).
///
/// Elle vivait dans une fonction imbriquée au milieu de
/// `GardenARPlacementView`, et on la croyait donc invérifiable sans appareil.
/// C'était une confusion entre deux choses : **le rendu** dans une vraie pièce
/// demande effectivement un iPhone, mais **la décision** est du calcul pur.
///
/// Trois couches, toutes déterministes :
///
/// 1. le besoin en lumière d'une plante, lu sur `directSunHours` ;
/// 2. l'ordre dans lequel les plantes sont posées, selon la luminosité ;
/// 3. la tranche de profondeur où chacune est tirée.
///
/// Seul le tirage lui-même est aléatoire, et il reste dans la vue. Ce qui est
/// ici se teste avec des valeurs, sans caméra ni LiDAR.
enum GardenLightNeed: Int, CaseIterable, Equatable {
    case shade = 0
    case partial = 1
    case fullSun = 2
}

/// Les repères de profondeur d'une zone de pose, en mètres dans le repère du
/// monde. `centroid` n'est pas forcément au milieu de `min` et `max` : une
/// zone en L a son barycentre décalé.
struct GardenPlacementDepth: Equatable {
    let min: Float
    let mid: Float
    let max: Float
    let centroid: Float
}

enum GardenLightPlacement {

    /// Le besoin en lumière d'une plante.
    ///
    /// Les seuils viennent de `PlantThresholds.Light`, partagés avec le filtre
    /// du catalogue et l'évaluateur de compatibilité : les trois doivent dire
    /// la même chose d'une même plante.
    ///
    /// Ce qui précédait appariait **29 noms de genres botaniques en dur** sur
    /// `plant.name` — « cactus », « monstera », « zamioculcas » — avec un
    /// commentaire qui avouait le manque (« pas de modèle Plant dédié »). Le
    /// modèle existe, renseigné sur 920 fiches.
    static func need(for plant: Plant) -> GardenLightNeed {
        if let sun = plant.botanicalProfile?.directSunHours, sun.hasValue {
            // Une borne absente ne borne rien : minimum nil vaut 0,
            // maximum nil vaut 24.
            if (sun.minimum ?? 0) >= PlantThresholds.Light.fullSunMinHours {
                return .fullSun
            }
            if (sun.maximum ?? 24) <= PlantThresholds.Light.shadeMaxHours {
                return .shade
            }
            return .partial
        }
        // Sans fait, seul le `true` d'un drapeau informe — son `false` a voulu
        // dire à la fois « non » et « pas recherché ». Même règle que
        // `verdict(_:repli:)`.
        if plant.flags?.fullSunTolerant == true { return .fullSun }
        if plant.flags?.shadeTolerant == true { return .shade }
        // Rien de connu : rang neutre. La plante est posée sans préférence
        // plutôt que selon une devinette.
        return .partial
    }

    /// L'ordre de pose.
    ///
    /// Dans une pièce lumineuse, les plantes de plein soleil passent d'abord
    /// et prennent les emplacements exposés ; dans une pièce sombre, l'ordre
    /// s'inverse pour que les plantes d'ombre prennent les meilleures places.
    ///
    /// Le tri est **stable** : deux plantes de même besoin gardent leur ordre
    /// d'entrée. Sans ça, deux poses successives du même jardin donneraient
    /// des dispositions différentes sans raison.
    static func ordered(_ plants: [Plant], lux: Int) -> [Plant] {
        let lumineux = lux > PlantThresholds.Light.brightRoomLux
        return plants.enumerated().sorted { a, b in
            let na = need(for: a.element).rawValue
            let nb = need(for: b.element).rawValue
            if na != nb { return lumineux ? na > nb : na < nb }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// La tranche de profondeur où tirer la position d'une plante.
    ///
    /// Dans une pièce lumineuse, la profondeur maximale est la zone exposée :
    /// le plein soleil y va, l'ombre reste vers l'intérieur. Dans une pièce
    /// sombre il n'y a pas de zone exposée à distribuer, donc une plante de
    /// plein soleil est resserrée autour du barycentre, au plus près de ce que
    /// la pièce peut offrir.
    static func depthRange(
        for need: GardenLightNeed,
        lux: Int,
        depth: GardenPlacementDepth
    ) -> ClosedRange<Float> {
        if lux > PlantThresholds.Light.brightRoomLux {
            switch need {
            case .fullSun: return borne(depth.mid, depth.max, depth)
            case .shade: return borne(depth.min, depth.mid, depth)
            case .partial: return borne(depth.min, depth.max, depth)
            }
        }
        switch need {
        case .fullSun:
            let r = PlantThresholds.Light.dimRoomCentreRadiusMeters
            return borne(depth.centroid - r, depth.centroid + r, depth)
        case .shade, .partial:
            return borne(depth.min, depth.max, depth)
        }
    }

    /// Ramène une tranche dans les bornes de la zone, et garantit qu'elle
    /// n'est jamais vide.
    ///
    /// `ClosedRange` lève une exception fatale si sa borne basse dépasse la
    /// haute. Le code qui précédait bornait par
    /// `max(minZ, zLo)...min(maxZ, zHi)`, ce qui **suffisait** : `midZ` est la
    /// moyenne de `minZ` et `maxZ`, le barycentre vient du polygone, donc les
    /// quatre comparaisons nécessaires tenaient dans tous les cas.
    ///
    /// Cette fonction ne corrige donc pas un plantage : elle rend l'invariant
    /// EXPLICITE au lieu de le faire reposer sur quatre propriétés implicites.
    /// Si la façon de calculer le barycentre change un jour, le bornage tient
    /// toujours, et `testUneZonePlusEtroiteQueLeResserrementNeProduitPasDeTrancheVide`
    /// le dit.
    private static func borne(
        _ bas: Float,
        _ haut: Float,
        _ depth: GardenPlacementDepth
    ) -> ClosedRange<Float> {
        let b = Swift.max(depth.min, Swift.min(bas, depth.max))
        let h = Swift.max(depth.min, Swift.min(haut, depth.max))
        return b <= h ? b...h : h...b
    }
}
