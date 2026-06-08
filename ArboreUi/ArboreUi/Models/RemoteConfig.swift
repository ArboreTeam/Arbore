//
//  RemoteConfig.swift
//  ArboreUi
//
//  Modèle de la configuration servie par le backend (GET /config, issue #236).
//  Externalise les options du wizard, les règles de soin et les poids du moteur
//  de suggestion afin qu'ils soient ajustables côté serveur sans mise à jour de
//  l'app. Décodé par RemoteConfigService ; chaque consommateur garde une valeur
//  de repli codée en dur si la config distante est indisponible.
//

import Foundation

/// Réponse de `GET /config`.
struct RemoteConfig: Codable, Equatable {
    let version: Int
    let membership: Membership
    let wizard: Wizard
    let care: Care
    let suggestionEngine: SuggestionEngine

    // MARK: - Membership

    /// Contrôle du gating payant/gratuit. Pendant la bêta `enforced == false`
    /// (tout accessible) ; le `tier` des options reste purement informatif.
    struct Membership: Codable, Equatable {
        let enforced: Bool
        let tiers: [String]
    }

    // MARK: - Wizard

    struct Wizard: Codable, Equatable {
        let gardenStyles: [Option]
        let spaceTypes: [Option]
        let sunExposures: [Option]
        let soilTypes: [Option]
        let maintenanceLevels: [Option]
        let safetyOptions: [Option]
    }

    /// Une option du questionnaire. `value` correspond au nom de cas Swift
    /// (clé stable), `label` au libellé affiché, `tier` à "free" ou "premium".
    struct Option: Codable, Equatable, Identifiable {
        let value: String
        let label: String
        let icon: String?
        let tier: String

        var id: String { value }
        var isPremium: Bool { tier == "premium" }
    }

    // MARK: - Care

    struct Care: Codable, Equatable {
        /// Intervalle par défaut (jours) par type d'action d'entretien,
        /// clé = rawValue de `GardenCareKind` (ex. "pruneLeaves").
        let intervalsDays: [String: Int]
        /// Nombre de jours par fréquence d'arrosage,
        /// clé = rawValue de `WateringFrequency` (ex. "weekly").
        let wateringFrequencyDays: [String: Int]
    }

    // MARK: - Suggestion engine

    struct SuggestionEngine: Codable, Equatable {
        let weights: Weights

        struct Weights: Codable, Equatable {
            let style: Double
            let exposure: Double
            let soil: Double
            let maintenance: Double
            let safety: Double
        }
    }
}
