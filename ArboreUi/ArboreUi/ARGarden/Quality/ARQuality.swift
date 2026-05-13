//
//  ARQuality.swift
//  ArboreUi
//
//  Niveau de qualité retenu pour une session ARKit. Décide notamment
//  de `environmentTexturing` (cube map HDR pour réflexions) qui peut
//  coûter 50-100 MB de RAM en continu.
//
//  La recommandation au démarrage d'une session combine deux signaux :
//
//  - Tier du device (cf. DeviceCapabilities) : un device legacy reçoit
//    une config plus pauvre dès le départ pour éviter de saturer la RAM.
//
//  - Thermal state du système au démarrage : si le téléphone est déjà
//    chaud, on n'aggrave pas la situation en empilant des textures.
//
//  Note d'architecture : `ARQuality` n'observe pas le thermal state en
//  continu — c'est le rôle de `ARQualityObserver`. Changer
//  `environmentTexturing` au cours d'une session demanderait un
//  `session.run(config, options: [.resetTracking])` qui invaliderait
//  la `ARWorldMap` relocalisée, ce qui dégraderait l'UX bien plus que
//  le bénéfice thermique attendu.
//

import ARKit
import Foundation

enum ARQuality {
    /// Toutes les options graphiques activées. Réservé aux devices
    /// modernes en condition thermique nominale.
    case full
    /// Mode intermédiaire — `environmentTexturing` reste actif mais
    /// d'autres dégradations soft sont possibles (frame rate cap, etc.).
    case standard
    /// Mode allégé — `environmentTexturing` désactivé. Réservé aux
    /// devices legacy et aux situations thermiques tendues.
    case lite

    /// Niveau de qualité recommandé au démarrage d'une nouvelle session AR.
    /// La décision est figée pour toute la durée de la session ; les
    /// dégradations dynamiques liées au thermal state sont portées par
    /// `ARQualityObserver` via la notification `.arboreThermalCritical`.
    static var recommended: ARQuality {
        if DeviceCapabilities.tier == .legacy {
            return .lite
        }
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            return .lite
        case .fair:
            return .standard
        case .nominal:
            return .full
        @unknown default:
            return .standard
        }
    }

    /// Valeur à poser sur `ARWorldTrackingConfiguration.environmentTexturing`
    /// pour ce niveau de qualité.
    var environmentTexturing: ARWorldTrackingConfiguration.EnvironmentTexturing {
        switch self {
        case .full, .standard:
            return .automatic
        case .lite:
            return .none
        }
    }
}
