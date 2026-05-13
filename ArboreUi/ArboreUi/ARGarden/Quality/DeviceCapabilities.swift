//
//  DeviceCapabilities.swift
//  ArboreUi
//
//  Détection du tier d'un device iOS basée sur ProcessInfo.physicalMemory.
//  Pas de hardcoded model strings (qui exigeraient une table à maintenir
//  à chaque nouvelle génération d'iPhone) : la quantité de RAM est un
//  proxy stable, future-proof, et corrélé à la capacité graphique réelle.
//
//  Seuil retenu : 4 GB.
//  - iPhone XR (A12, 3 GB) → legacy
//  - iPhone XS / 11 (A12-A13, 4 GB) → modern (minimal)
//  - iPhone 12+ (A14+, 4-8 GB) → modern (comfortable)
//
//  Le seuil 4 GB est aligné avec la limite pratique pour un usage AR
//  multi-objets avec textures PBR sans warnings "resource constraints".
//

import Foundation

enum DeviceCapabilities {

    enum Tier: Equatable {
        /// Device avec moins de 4 GB de RAM physique. ARKit fonctionne mais
        /// les options gourmandes (environmentTexturing, scene reconstruction)
        /// doivent être désactivées pour éviter le thermal throttling et
        /// les warnings de ressources.
        case legacy
        /// Device avec 4 GB ou plus. Toutes les features AR par défaut sont
        /// utilisables.
        case modern
    }

    /// Tier estimé du device courant. Évalué une seule fois au premier accès.
    static let tier: Tier = {
        let gigabytes = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        return gigabytes < 4.0 ? .legacy : .modern
    }()
}
