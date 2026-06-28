//
//  PlantLODPolicy.swift
//  ArboreUi
//
//  Politique LOD adaptative des modèles 3D de plantes en AR. Décide light vs
//  heavy par une chaîne de précédence (les gates globaux ne peuvent que RÉDUIRE
//  le détail) :
//    1. Gate thermique (global)  — ProcessInfo.thermalState + Low Power Mode.
//    2. Budget K de heavy (global) — selon DeviceCapabilities.tier.
//    3. Distance / taille à l'écran (par plante) — avec hystérésis.
//
//  Valeurs par défaut issues de recherche (sources iOS thermal + LOD mobile AR ;
//  cf docs/3d-lod-architecture.md). Constantes nommées, ajustables ici.
//

import Foundation

enum PlantLODPolicy {

    /// Niveau de détail courant d'un modèle (stocké sur le SCNNode en KVC).
    enum LOD: String { case light, heavy }

    // MARK: - Distance (on raisonne en taille à l'écran, pas en mètres absolus)

    /// heavy tant que `distance < mult × hauteur` (≈ la plante couvre >30% de la
    /// hauteur d'écran à ~60° de FOV vertical). Un seuil absolu en mètres serait
    /// faux : un succulent de 30 cm et un ficus de 1,5 m n'ont pas le même seuil.
    static let heavyDistanceHeightMultiplier: Float = 2.9
    /// Hystérésis : le seuil de DOWNGRADE est 20% plus loin que celui d'UPGRADE,
    /// pour éviter le yoyo quand on se tient juste à la frontière.
    static let hysteresis: Float = 0.20
    /// Clamp bas : à bras tendu une plante reste toujours heavy.
    static let minSwapDistance: Float = 0.6
    /// Clamp haut : au-delà, inutile de charger du heavy même pour une grande plante.
    static let maxSwapDistance: Float = 4.5
    /// Hauteur de repli si la bbox n'est pas exploitable.
    static let fallbackPlantHeight: Float = 0.6

    // MARK: - Budget (nombre max de modèles heavy simultanés)

    /// K = nombre de heavy autorisés en même temps, selon le tier device.
    /// Budget visible ~50k triangles ; un heavy ~20–40k tri → K≈1 sur legacy,
    /// 2 sur modern (les flagships pourraient monter à 3, non distingués ici).
    static func heavyBudget(tier: DeviceCapabilities.Tier) -> Int {
        switch tier {
        case .legacy: return 1
        case .modern: return 2
        }
    }

    // MARK: - Anti-yoyo (downgrade immédiat, upgrade lent — reco Apple)

    /// Durée de thermique ≤ .fair SOUTENUE avant de ré-autoriser les upgrades
    /// après une période de chauffe (pas d'hystérésis native côté API).
    static let coolStableBeforeUpgrade: TimeInterval = 8.0
    /// Délai minimum entre deux swaps d'une même plante.
    static let swapDebounce: TimeInterval = 0.8
    /// Cadence d'évaluation (≈ 4 Hz ; surtout pas 60).
    static let evalInterval: TimeInterval = 0.25
    /// Stickiness du budget : une plante déjà heavy ne se fait déloger par une
    /// candidate plus proche que si celle-ci est >10% plus proche (anti ping-pong
    /// entre plantes quasi-équidistantes).
    static let budgetStickiness: Float = 0.10

    // MARK: - Décision distance

    /// Distance de bascule pour une plante de hauteur donnée (clampée).
    static func swapDistance(forHeight height: Float) -> Float {
        let h = height > 0 ? height : fallbackPlantHeight
        return min(max(heavyDistanceHeightMultiplier * h, minSwapDistance), maxSwapDistance)
    }

    /// Éligible heavy par la distance, avec hystérésis selon le LOD courant :
    /// - en light  : upgrade si `distance < seuil × (1 − hystérésis)`
    /// - en heavy  : on garde heavy tant que `distance < seuil × (1 + hystérésis)`
    static func isWithinHeavy(distance: Float, height: Float, currentlyHeavy: Bool) -> Bool {
        let base = swapDistance(forHeight: height)
        let threshold = currentlyHeavy ? base * (1 + hysteresis) : base * (1 - hysteresis)
        return distance < threshold
    }
}
