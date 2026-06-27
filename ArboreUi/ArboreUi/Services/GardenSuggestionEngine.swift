//
//  GardenSuggestionEngine.swift
//  ArboreUi
//
//  On-device AI garden suggestion engine.
//  Uses weighted multi-axis scoring + composition rules to propose
//  a coherent garden based on wizard filters — no network, no ML model,
//  no device heat. Pure algorithmic intelligence.
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
    }
}

// MARK: - Engine

final class GardenSuggestionEngine {

    // MARK: - Configuration

    /// Target number of plants to suggest (adjusted by composition rules)
    private let targetPlantCount: Int

    /// Weight for each scoring axis (must sum to ~1.0).
    /// Valeurs de repli codées en dur ; surchargées par la config distante
    /// (`suggestionEngine.weights`, issue #236) quand elle est disponible.
    private struct Weights {
        let style: Double
        let exposure: Double
        let soil: Double
        let maintenance: Double
        let safety: Double

        static let fallback = Weights(
            style: 0.30, exposure: 0.25, soil: 0.20, maintenance: 0.15, safety: 0.10
        )

        /// Poids effectifs : config distante si présente, sinon repli.
        static var resolved: Weights {
            guard let w = RemoteConfigService.shared.suggestionWeights else { return fallback }
            return Weights(
                style: w.style, exposure: w.exposure, soil: w.soil,
                maintenance: w.maintenance, safety: w.safety
            )
        }
    }

    init(targetPlantCount: Int = 7) {
        self.targetPlantCount = targetPlantCount
    }

    // MARK: - Public API

    /// Generate a garden suggestion from wizard filters and the full plant catalogue.
    /// This runs 100% on-device and is designed to complete in < 100ms.
    func suggest(
        from wizard: GardenWizardDTO,
        plants: [Plant],
        locale: String = "fr"
    ) -> GardenSuggestion {

        // 1. Score every plant
        let scored = plants.compactMap { plant -> ScoredPlant? in
            guard let translation = plant.translations[locale] else { return nil }
            let result = computeScore(plant: plant, translation: translation, wizard: wizard)
            return ScoredPlant(plant: plant, score: result.score, reasons: result.reasons)
        }
        .sorted { $0.score > $1.score }

        // 2. Apply composition rules (diversity, height mix, style-aware count)
        let composed = applyCompositionRules(
            scored: scored,
            wizard: wizard,
            locale: locale
        )

        // 3. Build suggestion
        let avgScore = composed.isEmpty ? 0 : composed.map(\.score).reduce(0, +) / Double(composed.count)
        let styleName = wizard.style.isEmpty ? "Personnalisé" : wizard.style

        return GardenSuggestion(
            plants: composed,
            styleName: styleName,
            confidenceScore: min(avgScore, 1.0),
            summary: generateSummary(plants: composed, wizard: wizard)
        )
    }

    // MARK: - Multi-Axis Scoring

    private struct ScoreResult {
        let score: Double
        let reasons: [String]
    }

    private struct ScoredPlant {
        let plant: Plant
        let score: Double
        let reasons: [String]
    }

    private func computeScore(
        plant: Plant,
        translation: PlantTranslation,
        wizard: GardenWizardDTO
    ) -> ScoreResult {

        var reasons: [String] = []

        // --- Style axis ---
        let styleScore = scoreStyle(plant: plant, translation: translation, style: wizard.style)
        if styleScore > 0.7 {
            reasons.append("Correspond au style \(wizard.style)")
        }

        // --- Exposure axis ---
        let exposureScore = scoreExposure(plant: plant, translation: translation, exposure: wizard.exposure)
        if exposureScore > 0.7 {
            reasons.append("Luminosité adaptée")
        } else if exposureScore < 0.3 {
            reasons.append("⚠️ Lumière peu compatible")
        }

        // --- Soil axis ---
        let soilScore = scoreSoil(plant: plant, translation: translation, soil: wizard.soil)
        if soilScore > 0.7 {
            reasons.append("Sol compatible")
        }

        // --- Maintenance axis ---
        let maintenanceScore = scoreMaintenance(plant: plant, translation: translation, maintenance: wizard.maintenance)
        if maintenanceScore > 0.7 {
            reasons.append("Entretien adapté")
        }

        // --- Safety axis ---
        let safetyScore = scoreSafety(plant: plant, translation: translation, safety: wizard.safety)
        if safetyScore < 0.5 {
            reasons.append("⚠️ Plante potentiellement toxique")
        }

        // Weighted average (poids distants si disponibles, sinon repli)
        let weights = Weights.resolved
        let total = styleScore * weights.style
            + exposureScore * weights.exposure
            + soilScore * weights.soil
            + maintenanceScore * weights.maintenance
            + safetyScore * weights.safety

        if reasons.isEmpty {
            reasons.append("Compatible avec vos critères")
        }

        return ScoreResult(score: total, reasons: reasons)
    }

    // MARK: - Style Scoring

    /// Keyword-based style matching with graded scoring.
    /// Returns 0.0–1.0.
    private func scoreStyle(plant: Plant, translation: PlantTranslation, style: String) -> Double {
        let s = style.lowercased()
        if s.isEmpty || s.contains("sans préférence") || s.contains("nopref") {
            return 0.8 // Neutral — slight positive bias
        }

        let searchText = [
            plant.name,
            plant.type,
            translation.description,
            translation.plantType
        ].joined(separator: " ").lowercased()

        // Primary keywords (strong match → 1.0)
        let primary: [String: [String]] = [
            "moderne": ["monstera", "ficus", "sansevieria", "dracaena", "zamioculcas", "zz",
                         "agave", "yucca", "palmier", "palm", "pilea", "caoutchouc"],
            "fleuri": ["orchidée", "orchid", "rose", "hibiscus", "jasmin", "anthurium",
                       "hortensia", "lavande", "bougainvillier", "géranium", "tulipe"],
            "champêtre": ["fougère", "fern", "lierre", "ivy", "pothos", "chlorophytum",
                          "tradescantia", "asparagus", "graminée"],
            "zen": ["bambou", "bamboo", "bonsaï", "bonsai", "érable", "maple",
                    "azalée", "lotus", "mousse", "fougère"],
            "méditerranéen": ["olivier", "olive", "lavande", "romarin", "thym", "citronnier",
                              "figuier", "bougainvillier", "agave", "aloès", "aloe", "cactus"]
        ]

        // Secondary keywords (weaker match → 0.6)
        let secondary: [String: [String]] = [
            "moderne": ["graphique", "architectural", "structur", "épuré", "minimaliste", "géométrique"],
            "fleuri": ["fleur", "flower", "coloré", "floraison", "pétale", "bouton"],
            "champêtre": ["sauvage", "wild", "rustique", "naturel", "vivace", "mousse"],
            "zen": ["zen", "japonais", "japan", "apaisant", "méditat", "calme"],
            "méditerranéen": ["méditerranéen", "résistant", "sécheresse", "aride", "aromatique", "soleil"]
        ]

        // Find matching style key
        guard let styleKey = primary.keys.first(where: { s.contains($0) }) else {
            return 0.5 // Unknown style → neutral
        }

        // Check primary keywords
        if let kws = primary[styleKey], kws.contains(where: { searchText.contains($0) }) {
            return 1.0
        }

        // Check secondary keywords
        if let kws = secondary[styleKey], kws.contains(where: { searchText.contains($0) }) {
            return 0.6
        }

        return 0.2 // No match at all
    }

    // MARK: - Exposure Scoring

    private func scoreExposure(plant: Plant, translation: PlantTranslation, exposure: String?) -> Double {
        guard let exposure = exposure, !exposure.isEmpty else { return 0.8 }

        if let flags = plant.flags {
            let exp = exposure.lowercased()
            if exp.contains("soleil direct") || exp.contains("6h") || exp == "fullsun" {
                return flags.fullSunTolerant ? 1.0 : (flags.shadeTolerant ? 0.2 : 0.6)
            }
            if exp.contains("mi-ombre") || exp == "partialshade" {
                if flags.shadeTolerant && !flags.fullSunTolerant { return 1.0 }
                return (flags.fullSunTolerant && !flags.shadeTolerant) ? 0.5 : 0.9
            }
            if exp.contains("ombrag") || exp == "shade" {
                return flags.shadeTolerant ? 1.0 : 0.1
            }
            return 0.7
        }

        let plantLight = (translation.sun?.lightType ?? "").lowercased()
        let plantDuration = (translation.sun?.durationPerDay ?? "").lowercased()
        let combined = plantLight + " " + plantDuration
        let exp = exposure.lowercased()

        // Full sun (6h+)
        if exp.contains("soleil direct") || exp.contains("6h") || exp == "fullsun" {
            if combined.contains("direct") || combined.contains("soleil") || combined.contains("sun") {
                return 1.0
            }
            if combined.contains("indirect") || combined.contains("mi-ombre") {
                return 0.5 // Tolerable
            }
            if combined.contains("ombre") || combined.contains("shade") {
                return 0.1 // Bad match
            }
        }

        // Partial shade
        if exp.contains("mi-ombre") || exp == "partialshade" {
            if combined.contains("indirect") || combined.contains("mi-ombre") || combined.contains("modér") {
                return 1.0
            }
            if combined.contains("direct") || combined.contains("ombre") {
                return 0.5
            }
        }

        // Full shade
        if exp.contains("ombrag") || exp == "shade" {
            if combined.contains("ombre") || combined.contains("faible") || combined.contains("shade")
                || combined.contains("low") || combined.contains("tamisé") {
                return 1.0
            }
            if combined.contains("indirect") || combined.contains("mi-ombre") {
                return 0.6
            }
            if combined.contains("direct") || combined.contains("soleil") {
                return 0.1
            }
        }

        // "Je ne sais pas"
        return 0.7
    }

    // MARK: - Soil Scoring

    private func scoreSoil(plant: Plant, translation: PlantTranslation, soil: String?) -> Double {
        guard let soil = soil, !soil.isEmpty else { return 0.8 }

        if let flags = plant.flags {
            let s = soil.lowercased()
            if s.contains("je ne sais pas") || s.contains("unknown") { return 0.7 }
            if s.contains("sec") || s == "dry" { return flags.droughtTolerant ? 1.0 : 0.2 }
            if s.contains("rocailleux") || s == "rocky" { return flags.droughtTolerant ? 1.0 : 0.4 }
            if s.contains("retient") || s == "waterretentive" {
                return flags.humidityLoving ? 1.0 : (flags.droughtTolerant ? 0.2 : 0.6)
            }
            if s.contains("riche") || s == "rich" { return flags.droughtTolerant ? 0.3 : 1.0 }
            return 0.6
        }

        let plantSoil = (translation.soilAndPot?.substrate ?? "").lowercased()
        let plantDrainage = (translation.soilAndPot?.drainage ?? "").lowercased()
        let combined = plantSoil + " " + plantDrainage
        let s = soil.lowercased()

        if s.contains("je ne sais pas") || s.contains("unknown") {
            return 0.7
        }

        // Rich soil
        if s.contains("riche") || s == "rich" {
            let richKeywords = ["riche", "rich", "humus", "fertil", "terreau", "nutritif", "compost"]
            if richKeywords.contains(where: { combined.contains($0) }) { return 1.0 }
            let dryKeywords = ["sableux", "caillou", "aride", "sec"]
            if dryKeywords.contains(where: { combined.contains($0) }) { return 0.2 }
            return 0.5
        }

        // Dry soil
        if s.contains("sec") || s == "dry" {
            let dryKeywords = ["sec", "dry", "drain", "sable", "sand", "aride", "cact"]
            if dryKeywords.contains(where: { combined.contains($0) }) { return 1.0 }
            let wetKeywords = ["humide", "tourbe", "retient"]
            if wetKeywords.contains(where: { combined.contains($0) }) { return 0.2 }
            return 0.5
        }

        // Rocky soil
        if s.contains("rocailleux") || s == "rocky" {
            let rockyKeywords = ["rocai", "rocky", "caillou", "minéral", "gravier", "drain", "pierre"]
            if rockyKeywords.contains(where: { combined.contains($0) }) { return 1.0 }
            return 0.4
        }

        // Water-retentive soil
        if s.contains("retient") || s == "waterretentive" {
            let wetKeywords = ["humide", "humid", "tourbe", "peat", "retient", "moist", "argile", "clay"]
            if wetKeywords.contains(where: { combined.contains($0) }) { return 1.0 }
            let dryKeywords = ["sec", "dry", "drain", "sable"]
            if dryKeywords.contains(where: { combined.contains($0) }) { return 0.2 }
            return 0.5
        }

        return 0.6
    }

    // MARK: - Maintenance Scoring

    private func scoreMaintenance(plant: Plant, translation: PlantTranslation, maintenance: String?) -> Double {
        guard let maintenance = maintenance, !maintenance.isEmpty else { return 0.8 }

        if let flags = plant.flags {
            let maint = maintenance.lowercased()
            if maint.contains("très facile") || maint == "veryeasy" { return flags.easyCare ? 1.0 : 0.3 }
            if maint.contains("facile") || maint == "easy" { return flags.easyCare ? 1.0 : 0.5 }
            if maint.contains("exigeant") || maint == "demanding" { return flags.easyCare ? 0.6 : 1.0 }
            return 0.7
        }

        let plantDifficulty = (translation.care?.difficulty ?? "").lowercased()
        let plantWater = (translation.water?.frequency ?? "").lowercased()
        let combined = plantDifficulty + " " + plantWater
        let maint = maintenance.lowercased()

        let easyKeywords = ["facile", "simple", "easy", "débutant", "minimal", "peu", "résistant"]
        let hardKeywords = ["exigeant", "difficile", "expert", "hard", "quotidien", "daily"]

        let isEasy = easyKeywords.contains { combined.contains($0) }
        let isHard = hardKeywords.contains { combined.contains($0) }

        // "Très facile"
        if maint.contains("très facile") || maint == "veryeasy" {
            if isEasy { return 1.0 }
            if isHard { return 0.1 }
            return 0.5
        }

        // "Facile"
        if maint.contains("facile") || maint == "easy" {
            if isEasy { return 1.0 }
            if isHard { return 0.2 }
            return 0.6
        }

        // "Exigeant" — accepts everything, but prefers demanding plants
        if maint.contains("exigeant") || maint == "demanding" {
            if isHard { return 1.0 }
            return 0.7
        }

        return 0.7
    }

    // MARK: - Safety Scoring

    private func scoreSafety(plant: Plant, translation: PlantTranslation, safety: [String]?) -> Double {
        guard let safety = safety, !safety.isEmpty else { return 1.0 }

        // "Aucune contrainte" → no filtering
        if safety.contains("Aucune contrainte") || safety.contains("none") {
            return 1.0
        }

        let hasPetFilter = safety.contains(where: { $0.contains("animaux") || $0.contains("pets") })
        let hasChildFilter = safety.contains(where: { $0.contains("enfants") || $0.contains("children") })

        // Prefer structured flags — robust (keyword fallback below false-positives
        // on "non toxique" / "non-toxic" descriptions).
        if let flags = plant.flags {
            if hasPetFilter && flags.toxicToPets { return 0.0 }
            if hasChildFilter && flags.toxicToChildren { return 0.0 }
            return 1.0
        }

        let problems = (translation.health?.commonProblems ?? []).joined(separator: " ").lowercased()
        let treatments = (translation.health?.treatments ?? []).joined(separator: " ").lowercased()
        let description = translation.description.lowercased()
        let combined = problems + " " + treatments + " " + description

        let toxicKeywords = ["toxique", "toxic", "dangere", "danger", "poison",
                             "irritant", "nocif", "vénéneux", "nocive"]
        let isToxic = toxicKeywords.contains { combined.contains($0) }

        if isToxic {
            // Heavy penalty for toxic plants when safety is required (legacy fallback)
            if hasPetFilter || hasChildFilter {
                return 0.0 // Hard exclude
            }
        }

        return 1.0
    }

    // MARK: - Composition Rules

    /// Apply diversity & style-aware composition rules to produce a balanced garden.
    private func applyCompositionRules(
        scored: [ScoredPlant],
        wizard: GardenWizardDTO,
        locale: String
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
            let category = classifyPlant(sp.plant, locale: locale)

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

    /// Classify a plant by height/role category based on keywords in its data.
    private func classifyPlant(_ plant: Plant, locale: String) -> SuggestedPlant.PlantCategory {
        let name = plant.name.lowercased()
        let type = plant.type.lowercased()
        let desc = plant.translations[locale]?.description.lowercased() ?? ""
        let combined = name + " " + type + " " + desc

        if combined.contains("grimpant") || combined.contains("climbing") || combined.contains("lierre") || combined.contains("ivy") {
            return .climbing
        }
        if combined.contains("couvre-sol") || combined.contains("ground") || combined.contains("mousse") || combined.contains("moss") {
            return .groundCover
        }
        if combined.contains("arbre") || combined.contains("tree") || combined.contains("palmier")
            || combined.contains("palm") || combined.contains("figuier") || combined.contains("olivier") {
            return .tall
        }
        if combined.contains("succulente") || combined.contains("succulent") || combined.contains("cactus")
            || combined.contains("couvre") || combined.contains("mini") || combined.contains("petit") {
            return .low
        }

        return .medium
    }

    // MARK: - Summary Generation

    /// Generate a human-readable summary of the suggestion.
    private func generateSummary(plants: [SuggestedPlant], wizard: GardenWizardDTO) -> String {
        guard !plants.isEmpty else {
            return "Aucune plante ne correspond parfaitement à vos critères. Essayez d'élargir vos filtres."
        }

        let style = wizard.style
        let count = plants.count
        let avgScore = plants.map(\.score).reduce(0, +) / Double(count)

        // Style-specific intros
        let styleIntros: [String: String] = [
            "moderne": "Un jardin aux lignes épurées avec des plantes graphiques et structurées.",
            "fleuri": "Une explosion de couleurs et de parfums pour un jardin vibrant.",
            "champêtre": "Un jardin naturel et sauvage, facile à entretenir.",
            "zen": "Un espace de calme et de méditation avec des plantes apaisantes.",
            "méditerranéen": "Un jardin résistant au soleil, aux saveurs aromatiques."
        ]

        let intro = styleIntros.first(where: { style.lowercased().contains($0.key) })?.value
            ?? "Une sélection personnalisée adaptée à votre espace."

        let quality: String
        if avgScore > 0.75 {
            quality = "Excellente compatibilité avec vos critères !"
        } else if avgScore > 0.5 {
            quality = "Bonne compatibilité avec vos critères."
        } else {
            quality = "Compatibilité modérée — certaines plantes sont des compromis."
        }

        return "\(intro)\n\(count) plantes sélectionnées. \(quality)"
    }
}
