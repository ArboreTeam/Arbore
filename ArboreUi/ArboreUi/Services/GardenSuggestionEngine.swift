//
//  GardenSuggestionEngine.swift
//  ArboreUi
//
//  On-device garden composition engine.
//  It ranks the canonical environmental verdicts produced by
//  PlantSuitabilityEvaluator, then applies diversity rules. No network or ML.
//

import Foundation

// MARK: - Output Models

/// A complete garden suggestion returned by the engine.
struct GardenSuggestion {
    let plants: [SuggestedPlant]
    let styleName: String
    let confidenceScore: Double       // 0.0–1.0, overall match quality
    let summary: String               // Human-readable summary of the suggestion
}

/// A single plant recommendation with score + reasoning.
struct SuggestedPlant: Identifiable {
    let id: String
    let plant: Plant
    let score: Double                 // 0.0–1.0, compatibility with wizard filters
    let reasons: [String]             // "Parfait pour mi-ombre", "Sol riche compatible"
    let category: PlantCategory       // Classification for composition rules

    enum PlantCategory: String {
        case tall = "Haute"
        case medium = "Moyenne"
        case low = "Basse"
        case groundCover = "Couvre-sol"
        case climbing = "Grimpante"

        var displayName: String {
            switch self {
            case .tall: return L10n.t("PLANT_CATEGORY_TALL")
            case .medium: return L10n.t("PLANT_CATEGORY_MEDIUM")
            case .low: return L10n.t("PLANT_CATEGORY_LOW")
            case .groundCover: return L10n.t("PLANT_CATEGORY_GROUND_COVER")
            case .climbing: return L10n.t("PLANT_CATEGORY_CLIMBING")
            }
        }
    }
}

// MARK: - Engine

final class GardenSuggestionEngine {

    // MARK: - Configuration

    /// Target number of plants to suggest (adjusted by composition rules)
    private let targetPlantCount: Int

    init(targetPlantCount: Int = 7) {
        self.targetPlantCount = targetPlantCount
    }

    // MARK: - Public API

    /// Generate a garden suggestion from wizard filters and the full plant catalogue.
    /// This runs 100% on-device and is designed to complete in < 100ms.
    /// **`locale` ne décide plus de rien.** Aucun classement, aucune
    /// catégorie, aucun écart de sûreté n'en dépend : la composition ne lit
    /// que des valeurs closes, identiques pour tous les lecteurs (#792). Les
    /// libellés et les résumés restent localisés, mais par `L10n`. Le
    /// paramètre est conservé pour ne pas casser les appelants ; il est
    /// délibérément inutilisé, et c'est le but.
    func suggest(
        from wizard: GardenWizardDTO,
        plants: [Plant],
        locale: String = "fr"
    ) -> GardenSuggestion {

        // 1. Use the same canonical environmental verdict as the AR catalog.
        // Critical conflicts are removed before composition. Missing data
        // lowers ranking and remains visible instead of receiving a neutral
        // score through the obsolete style/exposure/soil axes.
        let evaluator = PlantSuitabilityEvaluator(wizard: wizard)

        // Barrière de sûreté AVANT le classement, et plus stricte que celle des
        // catalogues : ce moteur PROPOSE, il n'offre pas à parcourir.
        //
        // `isRecommended` ne suffisait pas. Une toxicité non établie n'ajoute
        // qu'une clé `missing` sans critère : le niveau tombe à `.needsReview`,
        // mais `isRecommended` accepte `.needsReview` dès 0,55 de score. Une
        // plante aux autres axes solides et à la toxicité INCONNUE pouvait donc
        // être recommandée à un foyer qui avait demandé l'inverse — la forme
        // exacte de la régression #488, par un autre chemin (#783).
        let contrainteFoyer = Plant.HouseholdSafetyRequirement(wizardSafety: wizard.safety)
        let scored = plants.compactMap { plant -> ScoredPlant? in
            guard plant.isAdmitted(by: .offerable, requirement: contrainteFoyer) else { return nil }
            let suitability = evaluator.evaluate(plant)
            guard suitability.isRecommended else { return nil }

            let confidencePenalty = suitability.level == .suitable ? 1.0 : 0.78
            let missingPenalty = min(Double(suitability.missingDataKeys.count) * 0.025, 0.20)
            let score = max(0, (suitability.score ?? 0) * confidencePenalty - missingPenalty)
            let reasonKeys = suitability.positiveReasonKeys + suitability.warningReasonKeys
            let reasons = reasonKeys.isEmpty
                ? [L10n.t("AR_CATALOG_REASON_NOT_ENOUGH_DATA")]
                : reasonKeys.map { L10n.t($0) }

            return ScoredPlant(plant: plant, score: score, reasons: reasons)
        }
        .sorted { $0.score > $1.score }

        // 2. Apply composition rules (diversity, height mix, style-aware count)
        let composed = applyCompositionRules(scored: scored, wizard: wizard)

        // 3. Build suggestion
        let avgScore = composed.isEmpty ? 0 : composed.map(\.score).reduce(0, +) / Double(composed.count)
        let styleName = wizard.style.isEmpty ? L10n.t("GARDEN_STYLE_CUSTOM") : wizard.style

        return GardenSuggestion(
            plants: composed,
            styleName: styleName,
            confidenceScore: min(avgScore, 1.0),
            summary: generateSummary(plants: composed, wizard: wizard)
        )
    }

    private struct ScoredPlant {
        let plant: Plant
        let score: Double
        let reasons: [String]
    }

    // MARK: - Composition Rules

    /// Apply diversity & style-aware composition rules to produce a balanced garden.
    private func applyCompositionRules(
        scored: [ScoredPlant],
        wizard: GardenWizardDTO
    ) -> [SuggestedPlant] {

        // Determine target count based on style
        let count = targetCountForStyle(wizard.style)
        var selected: [SuggestedPlant] = []
        var usedTypes: [String: Int] = [:]  // Track type frequency for diversity

        for sp in scored {
            guard selected.count < count else { break }

            // Skip plants with very low scores
            guard sp.score > 0.25 else { continue }

            // Diversity rule: max 2 plants of the same base type
            let baseType = normalizeType(sp.plant.type)
            let currentCount = usedTypes[baseType, default: 0]
            if currentCount >= 2 { continue }

            // Classify by category
            let category = classifyPlant(sp.plant)

            let suggested = SuggestedPlant(
                id: sp.plant.id,
                plant: sp.plant,
                score: sp.score,
                reasons: sp.reasons,
                category: category
            )

            selected.append(suggested)
            usedTypes[baseType, default: 0] += 1
        }

        return selected
    }

    /// Zen/Japanese styles use odd numbers (3, 5, 7). Others use the default target.
    private func targetCountForStyle(_ style: String) -> Int {
        let s = style.lowercased()
        if s.contains("zen") || s.contains("japonais") {
            // Nearest odd number to target
            let n = targetPlantCount
            return n % 2 == 0 ? n - 1 : n
        }
        return targetPlantCount
    }

    /// Normalize plant type for diversity tracking.
    private func normalizeType(_ type: String) -> String {
        type.lowercased()
            .replacingOccurrences(of: "plante d'intérieur", with: "intérieur")
            .replacingOccurrences(of: "plante grimpante", with: "grimpante")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Classe une plante par rôle de composition, depuis ses valeurs CLOSES.
    ///
    /// Cette fonction concaténait le nom, le type et la **description
    /// traduite**, puis y cherchait des mots-clés. La catégorie d'une plante
    /// dépendait donc de la formulation retenue par un traducteur — et d'un
    /// appariement sans frontière de mot, dont la conséquence était mesurable
    /// sur le catalogue : `mousse` appariait « tuteur **mousse** », donc le
    /// `Monstera_Deliciosa_Pot_Tuteur_Mousse` et le
    /// `Pothos_Dore_Vert_Sur_Tuteur_Mousse` étaient classés **couvre-sol**
    /// parce que leur nom contenait le mot (#792).
    ///
    /// L'ordre des branches reste celui d'avant — le rôle le plus spécifique
    /// d'abord — mais chaque test lit `kinds`, `goals` ou `size`.
    private func classifyPlant(_ plant: Plant) -> SuggestedPlant.PlantCategory {
        let traits = PlantCatalogTraits.snapshot(for: plant)

        if traits.kinds.contains(.climbing) || traits.goals.contains(.coverWall) {
            return .climbing
        }
        if traits.kinds.contains(.groundcover) || traits.goals.contains(.coverGround) {
            return .groundCover
        }
        if !traits.kinds.isDisjoint(with: [.tree, .palm, .conifer]) || traits.size == .large {
            return .tall
        }
        if traits.kinds.contains(.cactusSucculent) || traits.size == .small {
            return .low
        }

        // `.medium` reste le défaut, et c'est assumé : une plante dont la
        // nature et le gabarit ne sont pas établis occupe le rôle du milieu
        // plutôt que de disparaître de la composition. C'est un défaut
        // d'AFFICHAGE, pas un trait affirmé sur la fiche.
        return .medium
    }

    // MARK: - Summary Generation

    /// Generate a human-readable summary of the suggestion.
    private func generateSummary(plants: [SuggestedPlant], wizard: GardenWizardDTO) -> String {
        guard !plants.isEmpty else {
            return L10n.t("SUGGESTION_SUMMARY_EMPTY")
        }

        let style = wizard.style
        let count = plants.count
        let avgScore = plants.map(\.score).reduce(0, +) / Double(count)

        // Style-specific intros
        let styleIntros: [String: String] = [
            "moderne": L10n.t("SUGGESTION_SUMMARY_STYLE_MODERN"),
            "fleuri": L10n.t("SUGGESTION_SUMMARY_STYLE_FLORAL"),
            "champêtre": L10n.t("SUGGESTION_SUMMARY_STYLE_WILD"),
            "zen": L10n.t("SUGGESTION_SUMMARY_STYLE_ZEN"),
            "méditerranéen": L10n.t("SUGGESTION_SUMMARY_STYLE_MEDITERRANEAN")
        ]

        let intro = styleIntros.first(where: { style.lowercased().contains($0.key) })?.value
            ?? L10n.t("SUGGESTION_SUMMARY_STYLE_CUSTOM")

        let quality: String
        if avgScore > 0.75 {
            quality = L10n.t("SUGGESTION_SUMMARY_QUALITY_EXCELLENT")
        } else if avgScore > 0.5 {
            quality = L10n.t("SUGGESTION_SUMMARY_QUALITY_GOOD")
        } else {
            quality = L10n.t("SUGGESTION_SUMMARY_QUALITY_MODERATE")
        }

        return "\(intro)\n\(L10n.f("SUGGESTION_SUMMARY_COUNT_FORMAT", count)) \(quality)"
    }
}
