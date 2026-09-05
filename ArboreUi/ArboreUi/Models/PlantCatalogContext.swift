import Foundation

enum PlantSuitabilityLevel: Int, Comparable {
    case unsuitable = 0
    case needsReview = 1
    case suitable = 2

    static func < (lhs: PlantSuitabilityLevel, rhs: PlantSuitabilityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct PlantSuitability: Equatable {
    let level: PlantSuitabilityLevel
    let score: Double?
    let positiveReasonKeys: [String]
    let warningReasonKeys: [String]
    let evaluatedCriteriaCount: Int
    var missingDataKeys: [String] = []

    var isRecommended: Bool {
        level == .suitable
            || (level == .needsReview && evaluatedCriteriaCount > 0 && (score ?? 0) >= 0.55)
    }
}

/// Évalue une plante uniquement à partir des informations effectivement
/// disponibles dans le jardin. Un axe inconnu est ignoré au lieu d'être
/// transformé en compatibilité supposée.
private struct LegacyPlantSuitabilityEvaluator {
    let wizard: GardenWizardDTO

    private struct Criterion {
        let score: Double
        let positiveReasonKey: String?
        let warningReasonKey: String?
        let isCriticalConflict: Bool

        static func positive(_ score: Double, _ reasonKey: String) -> Self {
            Criterion(
                score: score,
                positiveReasonKey: reasonKey,
                warningReasonKey: nil,
                isCriticalConflict: false
            )
        }

        static func warning(_ score: Double, _ reasonKey: String) -> Self {
            Criterion(
                score: score,
                positiveReasonKey: nil,
                warningReasonKey: reasonKey,
                isCriticalConflict: false
            )
        }

        static func critical(_ reasonKey: String) -> Self {
            Criterion(
                score: 0,
                positiveReasonKey: nil,
                warningReasonKey: reasonKey,
                isCriticalConflict: true
            )
        }
    }

    func evaluate(_ plant: Plant) -> PlantSuitability {
        evaluate(plant, traits: PlantCatalogTraits.snapshot(for: plant))
    }

    /// Variant used by the AR catalog after plant traits have been indexed.
    /// Keeping the snapshot out of SwiftUI's render path avoids rescanning all
    /// localized descriptions every time the view invalidates.
    func evaluate(_ plant: Plant, traits: PlantCatalogTraitsSnapshot) -> PlantSuitability {
        var criteria: [Criterion] = []

        appendSpaceCriterion(searchableText: traits.searchableText, to: &criteria)
        appendSunlightCriterion(tolerances: traits.sunlightTolerances, to: &criteria)
        appendSafetyCriteria(for: plant, to: &criteria)
        appendPlantingCriterion(for: plant, size: traits.size, to: &criteria)
        appendDrainageCriterion(for: plant, to: &criteria)
        appendWindCriterion(for: plant, to: &criteria)
        appendHumidityCriterion(for: plant, to: &criteria)
        appendHeatCriterion(for: plant, to: &criteria)
        appendHeightCriterion(size: traits.size, to: &criteria)

        guard !criteria.isEmpty else {
            return PlantSuitability(
                level: .needsReview,
                score: nil,
                positiveReasonKeys: [],
                warningReasonKeys: ["AR_CATALOG_REASON_NOT_ENOUGH_DATA"],
                evaluatedCriteriaCount: 0
            )
        }

        let average = criteria.map(\.score).reduce(0, +) / Double(criteria.count)
        let hasCriticalConflict = criteria.contains(where: \.isCriticalConflict)
        let level: PlantSuitabilityLevel

        if hasCriticalConflict || average < 0.40 {
            level = .unsuitable
        } else if average >= 0.64 {
            level = .suitable
        } else {
            level = .needsReview
        }

        return PlantSuitability(
            level: level,
            score: average,
            positiveReasonKeys: unique(criteria.compactMap(\.positiveReasonKey)),
            warningReasonKeys: unique(criteria.compactMap(\.warningReasonKey)),
            evaluatedCriteriaCount: criteria.count
        )
    }

    private func appendSpaceCriterion(
        searchableText text: String,
        to criteria: inout [Criterion]
    ) {
        let indoorSignals = [
            "plante d'interieur", "plante interieur", "indoor plant", "houseplant",
            "zimmerpflanze", "planta de interior"
        ]
        let outdoorSignals = [
            "plante d'exterieur", "outdoor plant", "garden plant", "jardin exterieur",
            "gartenpflanze", "planta de exterior"
        ]
        let isExplicitlyIndoor = containsAny(text, indoorSignals)
        let isExplicitlyOutdoor = containsAny(text, outdoorSignals)

        switch GardenSpaceType(rawValue: wizard.spaceType) {
        case .interior:
            if isExplicitlyIndoor {
                criteria.append(.positive(1, "AR_CATALOG_REASON_SPACE_MATCH"))
            } else if isExplicitlyOutdoor {
                criteria.append(.warning(0.25, "AR_CATALOG_REASON_SPACE_CONFLICT"))
            }
        case .balcony, .terrace, .garden:
            if isExplicitlyOutdoor {
                criteria.append(.positive(1, "AR_CATALOG_REASON_SPACE_MATCH"))
            } else if isExplicitlyIndoor {
                criteria.append(.warning(0.35, "AR_CATALOG_REASON_SPACE_CONFLICT"))
            }
        case .none:
            break
        }
    }

    private func appendSunlightCriterion(
        tolerances: PlantCatalogTraits.SunlightTolerances,
        to criteria: inout [Criterion]
    ) {
        guard let sunlight = wizard.siteProfile?.sunlight else { return }

        let need: SunlightNeed
        if sunlight.maximumHours <= 3 {
            need = .shade
        } else if sunlight.minimumHours >= 6 {
            need = .fullSun
        } else {
            need = .partial
        }

        guard tolerances.hasKnownValue else { return }

        switch need {
        case .shade:
            if tolerances.shade {
                criteria.append(.positive(tolerances.fullSun ? 0.88 : 1, "AR_CATALOG_REASON_LIGHT_MATCH"))
            } else if tolerances.fullSun {
                criteria.append(.warning(0.15, "AR_CATALOG_REASON_SHADE_CONFLICT"))
            }
        case .partial:
            if tolerances.shade || tolerances.fullSun {
                criteria.append(.positive(0.86, "AR_CATALOG_REASON_LIGHT_MATCH"))
            }
        case .fullSun:
            if tolerances.fullSun {
                criteria.append(.positive(tolerances.shade ? 0.88 : 1, "AR_CATALOG_REASON_LIGHT_MATCH"))
            } else if tolerances.shade {
                criteria.append(.warning(0.15, "AR_CATALOG_REASON_SUN_CONFLICT"))
            }
        }
    }

    private func appendSafetyCriteria(for plant: Plant, to criteria: inout [Criterion]) {
        guard let safety = wizard.safety, !safety.isEmpty else { return }
        let values = safety.map(normalized)
        let wantsPetSafe = values.contains { $0.contains("animaux") || $0.contains("pets") }
        let wantsChildSafe = values.contains { $0.contains("enfants") || $0.contains("children") }

        guard let flags = plant.flags else { return }

        if wantsPetSafe {
            criteria.append(
                flags.toxicToPets
                    ? .critical("AR_CATALOG_REASON_PET_CONFLICT")
                    : .positive(1, "AR_CATALOG_REASON_PET_SAFE")
            )
        }

        if wantsChildSafe {
            criteria.append(
                flags.toxicToChildren
                    ? .critical("AR_CATALOG_REASON_CHILD_CONFLICT")
                    : .positive(1, "AR_CATALOG_REASON_CHILD_SAFE")
            )
        }
    }

    private func appendPlantingCriterion(
        for plant: Plant,
        size: PlantCatalogSize,
        to criteria: inout [Criterion]
    ) {
        guard wizard.conditionalAnswers?.plantingMode == .containers else { return }

        if plant.flags?.compact == true || size == .small {
            criteria.append(.positive(1, "AR_CATALOG_REASON_CONTAINER_MATCH"))
        } else if size == .large {
            criteria.append(.warning(0.45, "AR_CATALOG_REASON_CONTAINER_CONFLICT"))
        }
    }

    private func appendDrainageCriterion(for plant: Plant, to criteria: inout [Criterion]) {
        guard let drainage = wizard.conditionalAnswers?.drainage, let flags = plant.flags else { return }

        switch drainage {
        case .fast:
            if flags.droughtTolerant {
                criteria.append(.positive(1, "AR_CATALOG_REASON_DRY_MATCH"))
            } else if flags.humidityLoving {
                criteria.append(.warning(0.35, "AR_CATALOG_REASON_DRAINAGE_CONFLICT"))
            }
        case .slow:
            if flags.humidityLoving {
                criteria.append(.positive(1, "AR_CATALOG_REASON_HUMIDITY_MATCH"))
            } else if flags.droughtTolerant {
                criteria.append(.warning(0.35, "AR_CATALOG_REASON_DRAINAGE_CONFLICT"))
            }
        case .normal:
            break
        }
    }

    private func appendWindCriterion(for plant: Plant, to criteria: inout [Criterion]) {
        let windLevel: GardenWindExposureDTO?
        if let declared = wizard.conditionalAnswers?.windExposure {
            windLevel = declared
        } else {
            switch wizard.siteProfile?.wind?.level {
            case .strong: windLevel = .veryExposed
            case .moderate, .light: windLevel = .sometimesWindy
            case .sheltered: windLevel = .sheltered
            case .none: windLevel = nil
            }
        }

        guard let windLevel else { return }
        let flags = plant.flags

        switch windLevel {
        case .veryExposed:
            if flags?.compact == true {
                criteria.append(.positive(0.95, "AR_CATALOG_REASON_WIND_MATCH"))
            } else if flags?.climbing == true || flags?.trailing == true {
                criteria.append(.warning(0.30, "AR_CATALOG_REASON_WIND_CONFLICT"))
            }
        case .sometimesWindy:
            if flags?.climbing == true || flags?.trailing == true {
                criteria.append(.warning(0.55, "AR_CATALOG_REASON_WIND_CONFLICT"))
            } else if flags?.compact == true {
                criteria.append(.positive(0.90, "AR_CATALOG_REASON_WIND_MATCH"))
            }
        case .sheltered:
            break
        }
    }

    private func appendHumidityCriterion(for plant: Plant, to criteria: inout [Criterion]) {
        guard let humidity = wizard.conditionalAnswers?.indoorHumidity, let flags = plant.flags else { return }

        switch humidity {
        case .dry:
            if flags.droughtTolerant {
                criteria.append(.positive(1, "AR_CATALOG_REASON_DRY_MATCH"))
            } else if flags.humidityLoving {
                criteria.append(.warning(0.30, "AR_CATALOG_REASON_HUMIDITY_CONFLICT"))
            }
        case .humid:
            if flags.humidityLoving {
                criteria.append(.positive(1, "AR_CATALOG_REASON_HUMIDITY_MATCH"))
            } else if flags.droughtTolerant {
                criteria.append(.warning(0.45, "AR_CATALOG_REASON_HUMIDITY_CONFLICT"))
            }
        case .normal:
            break
        }
    }

    private func appendHeatCriterion(for plant: Plant, to criteria: inout [Criterion]) {
        guard let heat = wizard.conditionalAnswers?.nearbyHeat, heat != .none, let flags = plant.flags else { return }

        if flags.droughtTolerant {
            criteria.append(.positive(0.90, "AR_CATALOG_REASON_HEAT_MATCH"))
        } else if flags.humidityLoving {
            criteria.append(.warning(0.30, "AR_CATALOG_REASON_HEAT_CONFLICT"))
        }
    }

    private func appendHeightCriterion(
        size: PlantCatalogSize,
        to criteria: inout [Criterion]
    ) {
        guard let height = wizard.siteProfile?.availableHeight?.meters, height <= 1.6 else { return }

        switch size {
        case .small:
            criteria.append(.positive(1, "AR_CATALOG_REASON_HEIGHT_MATCH"))
        case .large:
            criteria.append(.warning(0.20, "AR_CATALOG_REASON_HEIGHT_CONFLICT"))
        case .medium, .unknown:
            break
        }
    }

    private func unique(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    private func containsAny(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains { text.contains($0) }
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private enum SunlightNeed {
        case shade
        case partial
        case fullSun
    }
}

/// Canonical compatibility evaluator. Critical constraints are checked before
/// ranking, sourced botanical facts take precedence, and every missing fact is
/// surfaced instead of receiving a neutral score.
struct PlantSuitabilityEvaluator {
    let wizard: GardenWizardDTO

    private struct Criterion {
        let score: Double
        let positiveReasonKey: String?
        let warningReasonKey: String?
        let isCriticalConflict: Bool

        static func positive(_ score: Double, _ key: String) -> Self {
            Criterion(score: score, positiveReasonKey: key, warningReasonKey: nil, isCriticalConflict: false)
        }

        static func positive(_ key: String) -> Self {
            positive(1, key)
        }

        static func warning(_ score: Double, _ key: String) -> Self {
            Criterion(score: score, positiveReasonKey: nil, warningReasonKey: key, isCriticalConflict: false)
        }

        static func critical(_ key: String) -> Self {
            Criterion(score: 0, positiveReasonKey: nil, warningReasonKey: key, isCriticalConflict: true)
        }
    }

    func evaluate(_ plant: Plant) -> PlantSuitability {
        evaluate(plant, traits: PlantCatalogTraits.snapshot(for: plant))
    }

    func evaluate(_ plant: Plant, traits: PlantCatalogTraitsSnapshot) -> PlantSuitability {
        var criteria: [Criterion] = []
        var missing: [String] = []

        if plant.botanicalProfile == nil {
            missing.append("AR_CATALOG_MISSING_BOTANICAL_PROFILE")
        }

        appendSpaceCriterion(plant: plant, traits: traits, criteria: &criteria, missing: &missing)
        appendSunlightCriterion(plant: plant, traits: traits, criteria: &criteria, missing: &missing)
        appendTemperatureCriterion(plant: plant, criteria: &criteria, missing: &missing)
        appendSafetyCriteria(plant: plant, criteria: &criteria, missing: &missing)
        appendContainerCriterion(plant: plant, criteria: &criteria, missing: &missing)
        appendDrainageCriterion(plant: plant, criteria: &criteria, missing: &missing)
        appendWateringCriterion(plant: plant, criteria: &criteria, missing: &missing)
        appendWindCriterion(plant: plant, criteria: &criteria, missing: &missing)
        appendCoastalCriterion(plant: plant, criteria: &criteria, missing: &missing)
        appendHumidityCriterion(plant: plant, criteria: &criteria, missing: &missing)
        appendHeatCriterion(plant: plant, criteria: &criteria, missing: &missing)
        appendDimensionsCriteria(plant: plant, criteria: &criteria, missing: &missing)

        let uniqueMissing = unique(missing)
        guard !criteria.isEmpty else {
            return PlantSuitability(
                level: .needsReview,
                score: nil,
                positiveReasonKeys: [],
                warningReasonKeys: ["AR_CATALOG_REASON_NOT_ENOUGH_DATA"],
                evaluatedCriteriaCount: 0,
                missingDataKeys: uniqueMissing
            )
        }

        let average = criteria.map(\.score).reduce(0, +) / Double(criteria.count)
        let criticalConflict = criteria.contains(where: \.isCriticalConflict)
        let hasWarnings = criteria.contains { $0.warningReasonKey != nil }

        let level: PlantSuitabilityLevel
        if criticalConflict || average < 0.35 {
            level = .unsuitable
        } else if !uniqueMissing.isEmpty || hasWarnings || average < 0.75 {
            level = .needsReview
        } else {
            level = .suitable
        }

        return PlantSuitability(
            level: level,
            score: average,
            positiveReasonKeys: unique(criteria.compactMap(\.positiveReasonKey)),
            warningReasonKeys: unique(criteria.compactMap(\.warningReasonKey)),
            evaluatedCriteriaCount: criteria.count,
            missingDataKeys: uniqueMissing
        )
    }

    private func appendSpaceCriterion(
        plant: Plant,
        traits: PlantCatalogTraitsSnapshot,
        criteria: inout [Criterion],
        missing: inout [String]
    ) {
        guard let space = GardenSpaceType(rawValue: wizard.spaceType) else {
            missing.append("AR_CATALOG_MISSING_SPACE_CONTEXT")
            return
        }

        let expected = space == .interior ? "indoor" : "outdoor"
        if let fact = plant.botanicalProfile?.environments {
            markEvidence(fact.evidence, missing: &missing)
            let values = Set(fact.value.map(normalized))
            if values.contains(expected) || values.contains("both") {
                criteria.append(.positive("AR_CATALOG_REASON_SPACE_MATCH"))
            } else {
                criteria.append(.critical("AR_CATALOG_REASON_SPACE_CONFLICT"))
            }
            return
        }

        let text = traits.searchableText
        let indoor = containsAny(text, ["plante d'interieur", "indoor plant", "houseplant", "zimmerpflanze", "planta de interior"])
        let outdoor = containsAny(text, ["plante d'exterieur", "outdoor plant", "garden plant", "gartenpflanze", "planta de exterior"])
        missing.append("AR_CATALOG_MISSING_ENVIRONMENT")

        if (expected == "indoor" && indoor) || (expected == "outdoor" && outdoor) {
            criteria.append(.positive(0.72, "AR_CATALOG_REASON_SPACE_MATCH"))
        } else if (expected == "indoor" && outdoor) || (expected == "outdoor" && indoor) {
            criteria.append(.warning(0.20, "AR_CATALOG_REASON_SPACE_CONFLICT"))
        }
    }

    private func appendSunlightCriterion(
        plant: Plant,
        traits: PlantCatalogTraitsSnapshot,
        criteria: inout [Criterion],
        missing: inout [String]
    ) {
        let gardenRange: ClosedRange<Double>?
        if let declared = wizard.conditionalAnswers?.directSunDuration {
            gardenRange = declared.estimatedRange
        } else if let sunlight = wizard.siteProfile?.sunlight {
            gardenRange = sunlight.minimumHours...sunlight.maximumHours
            if sunlight.metadata.confidence == .low {
                missing.append("AR_CATALOG_MISSING_RELIABLE_SUNLIGHT")
            }
        } else {
            gardenRange = nil
        }

        guard let gardenRange else {
            missing.append("AR_CATALOG_MISSING_SUNLIGHT_CONTEXT")
            return
        }

        if let fact = plant.botanicalProfile?.directSunHours, fact.hasValue {
            markEvidence(fact.evidence, missing: &missing)
            let plantMinimum = fact.minimum ?? 0
            let plantMaximum = fact.maximum ?? 24
            let overlaps = plantMaximum >= gardenRange.lowerBound && plantMinimum <= gardenRange.upperBound
            if overlaps {
                criteria.append(.positive("AR_CATALOG_REASON_LIGHT_MATCH"))
            } else if gardenRange.upperBound < plantMinimum {
                criteria.append(.critical("AR_CATALOG_REASON_SHADE_CONFLICT"))
            } else {
                criteria.append(.critical("AR_CATALOG_REASON_SUN_CONFLICT"))
            }
            return
        }

        missing.append("AR_CATALOG_MISSING_LIGHT_REQUIREMENT")
        let tolerances = traits.sunlightTolerances
        guard tolerances.hasKnownValue else { return }

        if gardenRange.upperBound <= 3 {
            criteria.append(
                tolerances.shade
                    ? .positive(0.70, "AR_CATALOG_REASON_LIGHT_MATCH")
                    : .warning(0.20, "AR_CATALOG_REASON_SHADE_CONFLICT")
            )
        } else if gardenRange.lowerBound >= 6 {
            criteria.append(
                tolerances.fullSun
                    ? .positive(0.70, "AR_CATALOG_REASON_LIGHT_MATCH")
                    : .warning(0.20, "AR_CATALOG_REASON_SUN_CONFLICT")
            )
        } else if tolerances.shade || tolerances.fullSun {
            criteria.append(.positive(0.65, "AR_CATALOG_REASON_LIGHT_MATCH"))
        }
    }

    private func appendTemperatureCriterion(
        plant: Plant,
        criteria: inout [Criterion],
        missing: inout [String]
    ) {
        guard let space = GardenSpaceType(rawValue: wizard.spaceType), space != .interior else { return }

        guard let gardenMinimum = wizard.siteProfile?.climate?.historicalMinimumTemperature else {
            missing.append("AR_CATALOG_MISSING_MINIMUM_TEMPERATURE_CONTEXT")
            return
        }
        if gardenMinimum.metadata.confidence == .low {
            missing.append("AR_CATALOG_MISSING_CLIMATE_CONFIDENCE")
        }

        guard let fact = plant.botanicalProfile?.minimumTemperatureC else {
            missing.append("AR_CATALOG_MISSING_MINIMUM_TEMPERATURE")
            return
        }
        markEvidence(fact.evidence, missing: &missing)

        if gardenMinimum.celsius + 0.5 < fact.value {
            criteria.append(.critical("AR_CATALOG_REASON_TEMPERATURE_CONFLICT"))
        } else {
            criteria.append(.positive("AR_CATALOG_REASON_TEMPERATURE_MATCH"))
        }
    }

    private func appendSafetyCriteria(
        plant: Plant,
        criteria: inout [Criterion],
        missing: inout [String]
    ) {
        let safety = wizard.safety?.map(normalized) ?? []
        let requiresPetSafety = safety.contains { $0.contains("animaux") || $0.contains("pets") }
        let requiresChildSafety = safety.contains { $0.contains("enfants") || $0.contains("children") }

        if requiresPetSafety {
            appendToxicityCriterion(
                fact: plant.botanicalProfile?.petToxicity,
                legacyToxic: plant.flags?.toxicToPets,
                safeReason: "AR_CATALOG_REASON_PET_SAFE",
                conflictReason: "AR_CATALOG_REASON_PET_CONFLICT",
                missingKey: "AR_CATALOG_MISSING_PET_TOXICITY",
                criteria: &criteria,
                missing: &missing
            )
        }

        if requiresChildSafety {
            appendToxicityCriterion(
                fact: plant.botanicalProfile?.childToxicity,
                legacyToxic: plant.flags?.toxicToChildren,
                safeReason: "AR_CATALOG_REASON_CHILD_SAFE",
                conflictReason: "AR_CATALOG_REASON_CHILD_CONFLICT",
                missingKey: "AR_CATALOG_MISSING_CHILD_TOXICITY",
                criteria: &criteria,
                missing: &missing
            )
        }
    }

    private func appendToxicityCriterion(
        fact: PlantFact<String>?,
        legacyToxic: Bool?,
        safeReason: String,
        conflictReason: String,
        missingKey: String,
        criteria: inout [Criterion],
        missing: inout [String]
    ) {
        if let fact {
            markEvidence(fact.evidence, missing: &missing)
            let value = normalized(fact.value)
            if containsAny(value, ["safe", "non toxic", "non-toxic", "not toxic"]) {
                criteria.append(.positive(safeReason))
            } else if containsAny(value, ["toxic", "irritant", "danger", "poison"]) {
                criteria.append(.critical(conflictReason))
            } else {
                missing.append(missingKey)
            }
        } else if legacyToxic == true {
            criteria.append(.critical(conflictReason))
            missing.append(missingKey)
        } else {
            // `false` in legacy flags meant both “safe” and “not researched”.
            missing.append(missingKey)
        }
    }

    private func appendContainerCriterion(
        plant: Plant,
        criteria: inout [Criterion],
        missing: inout [String]
    ) {
        let space = GardenSpaceType(rawValue: wizard.spaceType)
        let requiresContainer = space == .balcony
            || space == .terrace
            || wizard.conditionalAnswers?.plantingMode == .containers

        guard requiresContainer else { return }
        guard let acceptedSize = wizard.conditionalAnswers?.maximumContainerSize else {
            missing.append("AR_CATALOG_MISSING_CONTAINER_CONTEXT")
            return
        }
        guard let fact = plant.botanicalProfile?.minimumPotVolumeLiters else {
            missing.append("AR_CATALOG_MISSING_POT_REQUIREMENT")
            return
        }
        markEvidence(fact.evidence, missing: &missing)

        guard let maximumVolume = acceptedSize.maximumVolumeLiters else {
            criteria.append(.positive(0.90, "AR_CATALOG_REASON_CONTAINER_MATCH"))
            return
        }
        if fact.value > maximumVolume {
            criteria.append(.critical("AR_CATALOG_REASON_POT_SIZE_CONFLICT"))
        } else {
            criteria.append(.positive("AR_CATALOG_REASON_CONTAINER_MATCH"))
        }
    }

    private func appendDrainageCriterion(
        plant: Plant,
        criteria: inout [Criterion],
        missing: inout [String]
    ) {
        guard let gardenDrainage = wizard.conditionalAnswers?.drainage else { return }
        guard let fact = plant.botanicalProfile?.drainage else {
            missing.append("AR_CATALOG_MISSING_DRAINAGE_REQUIREMENT")
            return
        }
        markEvidence(fact.evidence, missing: &missing)

        let plantDrainage = normalized(fact.value)
        if plantDrainage == "any" || plantDrainage == gardenDrainage.rawValue {
            criteria.append(.positive("AR_CATALOG_REASON_DRAINAGE_MATCH"))
        } else if (gardenDrainage == .fast && plantDrainage == "slow")
                    || (gardenDrainage == .slow && plantDrainage == "fast") {
            criteria.append(.warning(0.25, "AR_CATALOG_REASON_DRAINAGE_CONFLICT"))
        } else {
            criteria.append(.warning(0.60, "AR_CATALOG_REASON_DRAINAGE_CONFLICT"))
        }
    }

    private func appendWateringCriterion(
        plant: Plant,
        criteria: inout [Criterion],
        missing: inout [String]
    ) {
        guard let capacity = wizard.conditionalAnswers?.wateringCapacity else { return }
        guard let fact = plant.botanicalProfile?.wateringIntervalDays, fact.hasValue else {
            missing.append("AR_CATALOG_MISSING_WATERING_REQUIREMENT")
            return
        }
        markEvidence(fact.evidence, missing: &missing)

        let longestInterval = fact.maximum ?? fact.minimum ?? 0
        switch capacity {
        case .low:
            if longestInterval >= 7 {
                criteria.append(.positive("AR_CATALOG_REASON_WATERING_MATCH"))
            } else {
                criteria.append(.warning(0.25, "AR_CATALOG_REASON_WATERING_CONFLICT"))
            }
        case .regular:
            if longestInterval >= 3 {
                criteria.append(.positive("AR_CATALOG_REASON_WATERING_MATCH"))
            } else {
                criteria.append(.warning(0.50, "AR_CATALOG_REASON_WATERING_CONFLICT"))
            }
        case .frequent:
            criteria.append(.positive(0.90, "AR_CATALOG_REASON_WATERING_MATCH"))
        }
    }

    private func appendWindCriterion(
        plant: Plant,
        criteria: inout [Criterion],
        missing: inout [String]
    ) {
        let exposure: GardenWindExposureDTO?
        if let declared = wizard.conditionalAnswers?.windExposure {
            exposure = declared
        } else {
            switch wizard.siteProfile?.wind?.level {
            case .strong: exposure = .veryExposed
            case .moderate, .light: exposure = .sometimesWindy
            case .sheltered: exposure = .sheltered
            case .none: exposure = nil
            }
        }
        guard let exposure, exposure != .sheltered else { return }
        guard let fact = plant.botanicalProfile?.windTolerance else {
            missing.append("AR_CATALOG_MISSING_WIND_TOLERANCE")
            return
        }
        markEvidence(fact.evidence, missing: &missing)

        let tolerance = normalized(fact.value)
        if exposure == .veryExposed {
            if tolerance == "high" {
                criteria.append(.positive("AR_CATALOG_REASON_WIND_MATCH"))
            } else if tolerance == "low" {
                criteria.append(.warning(0.15, "AR_CATALOG_REASON_WIND_CONFLICT"))
            } else {
                criteria.append(.warning(0.60, "AR_CATALOG_REASON_WIND_CONFLICT"))
            }
        } else if tolerance == "low" {
            criteria.append(.warning(0.55, "AR_CATALOG_REASON_WIND_CONFLICT"))
        } else {
            criteria.append(.positive(0.90, "AR_CATALOG_REASON_WIND_MATCH"))
        }
    }

    private func appendCoastalCriterion(
        plant: Plant,
        criteria: inout [Criterion],
        missing: inout [String]
    ) {
        guard let space = GardenSpaceType(rawValue: wizard.spaceType), space != .interior else { return }
        guard wizard.siteProfile?.climate?.coastalExposure?.isCoastal == true else { return }

        guard let fact = plant.botanicalProfile?.saltTolerance else {
            missing.append("AR_CATALOG_MISSING_SALT_TOLERANCE")
            return
        }
        markEvidence(fact.evidence, missing: &missing)

        switch normalized(fact.value) {
        case "high":
            criteria.append(.positive("AR_CATALOG_REASON_COASTAL_MATCH"))
        case "moderate", "medium":
            criteria.append(.positive(0.85, "AR_CATALOG_REASON_COASTAL_MATCH"))
        case "low":
            criteria.append(.warning(0.45, "AR_CATALOG_REASON_COASTAL_CONFLICT"))
        default:
            missing.append("AR_CATALOG_MISSING_SALT_TOLERANCE")
        }
    }

    private func appendHumidityCriterion(
        plant: Plant,
        criteria: inout [Criterion],
        missing: inout [String]
    ) {
        guard let humidity = wizard.conditionalAnswers?.indoorHumidity else { return }
        guard let fact = plant.botanicalProfile?.indoorHumidityPercent, fact.hasValue else {
            missing.append("AR_CATALOG_MISSING_HUMIDITY_REQUIREMENT")
            return
        }
        markEvidence(fact.evidence, missing: &missing)

        let target: ClosedRange<Double>
        switch humidity {
        case .dry: target = 20...40
        case .normal: target = 35...60
        case .humid: target = 55...80
        }
        let plantMinimum = fact.minimum ?? 0
        let plantMaximum = fact.maximum ?? 100
        if plantMaximum >= target.lowerBound && plantMinimum <= target.upperBound {
            criteria.append(.positive("AR_CATALOG_REASON_HUMIDITY_MATCH"))
        } else {
            criteria.append(.warning(0.25, "AR_CATALOG_REASON_HUMIDITY_CONFLICT"))
        }
    }

    private func appendHeatCriterion(
        plant: Plant,
        criteria: inout [Criterion],
        missing: inout [String]
    ) {
        guard let heat = wizard.conditionalAnswers?.nearbyHeat, heat != .none else { return }
        guard let fact = plant.botanicalProfile?.droughtTolerance else {
            missing.append("AR_CATALOG_MISSING_DROUGHT_TOLERANCE")
            return
        }
        markEvidence(fact.evidence, missing: &missing)
        let tolerance = normalized(fact.value)
        if tolerance == "high" {
            criteria.append(.positive(0.85, "AR_CATALOG_REASON_HEAT_MATCH"))
        } else if tolerance == "low" {
            criteria.append(.warning(0.30, "AR_CATALOG_REASON_HEAT_CONFLICT"))
        } else {
            criteria.append(.warning(0.60, "AR_CATALOG_REASON_HEAT_CONFLICT"))
        }
    }

    private func appendDimensionsCriteria(
        plant: Plant,
        criteria: inout [Criterion],
        missing: inout [String]
    ) {
        if let availableHeight = wizard.siteProfile?.availableHeight?.meters {
            if let fact = plant.botanicalProfile?.matureHeightCm, fact.hasValue {
                markEvidence(fact.evidence, missing: &missing)
                let minimumHeight = fact.minimum ?? fact.maximum ?? 0
                let maximumHeight = fact.maximum ?? minimumHeight
                if minimumHeight > availableHeight * 100 {
                    criteria.append(.critical("AR_CATALOG_REASON_HEIGHT_CONFLICT"))
                } else if maximumHeight > availableHeight * 100 {
                    criteria.append(.warning(0.55, "AR_CATALOG_REASON_HEIGHT_CONFLICT"))
                } else {
                    criteria.append(.positive("AR_CATALOG_REASON_HEIGHT_MATCH"))
                }
            } else {
                missing.append("AR_CATALOG_MISSING_MATURE_HEIGHT")
            }
        }

        guard let availableWidth = maximumPlantingZoneWidthMeters() else {
            if GardenSpaceType(rawValue: wizard.spaceType) != .garden {
                missing.append("AR_CATALOG_MISSING_AVAILABLE_WIDTH")
            }
            return
        }
        guard let fact = plant.botanicalProfile?.matureWidthCm, fact.hasValue else {
            missing.append("AR_CATALOG_MISSING_MATURE_WIDTH")
            return
        }
        markEvidence(fact.evidence, missing: &missing)
        let minimumWidth = fact.minimum ?? fact.maximum ?? 0
        if minimumWidth > availableWidth * 100 {
            criteria.append(.critical("AR_CATALOG_REASON_WIDTH_CONFLICT"))
        } else {
            criteria.append(.positive("AR_CATALOG_REASON_WIDTH_MATCH"))
        }
    }

    private func maximumPlantingZoneWidthMeters() -> Double? {
        wizard.siteProfile?.plantingZones
            .filter { !$0.isExcluded }
            .compactMap { zone -> Double? in
                let points = zone.points.filter { $0.count >= 3 }
                guard let first = points.first else { return nil }
                let xs = points.map { Double($0[0]) }
                let zs = points.map { Double($0[2]) }
                let width = (xs.max() ?? Double(first[0])) - (xs.min() ?? Double(first[0]))
                let depth = (zs.max() ?? Double(first[2])) - (zs.min() ?? Double(first[2]))
                return max(width, depth)
            }
            .max()
    }

    private func markEvidence(_ evidence: PlantDataEvidence?, missing: inout [String]) {
        guard let evidence,
              !(evidence.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                || !(evidence.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
              !(evidence.reviewedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
              normalized(evidence.reliability ?? "") == "high" else {
            missing.append("AR_CATALOG_MISSING_VERIFIED_SOURCE")
            return
        }
    }

    private func unique(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    private func containsAny(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains { text.contains($0) }
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum PlantCatalogSize: String {
    case small
    case medium
    case large
    case unknown
}

enum PlantCatalogGoal: String, CaseIterable, Hashable, Identifiable {
    case addColor
    case createPrivacy
    case addVolume
    case coverWall
    case createCascade
    case coverGround
    case attractPollinators
    case edibleAromatic
    case focalPoint

    var id: String { rawValue }
}

enum PlantCatalogKind: String, CaseIterable, Hashable, Identifiable {
    case greenPlant
    case floweringPlant
    case cactusSucculent
    case palm
    case fern
    case orchid
    case tree
    case shrub
    case perennial
    case annual
    case grass
    case groundcover
    case climbing
    case aromaticEdible

    var id: String { rawValue }
}

enum PlantCatalogColor: String, CaseIterable, Hashable, Identifiable {
    case white
    case yellow
    case orange
    case red
    case pink
    case purple
    case blue
    case green
    case dark

    var id: String { rawValue }
}

enum PlantCatalogAppearance: String, CaseIterable, Hashable, Identifiable {
    case flowering
    case variegated
    case evergreen
    case fragrant
    case decorativeFoliage

    var id: String { rawValue }
}

enum PlantCatalogScale: String, CaseIterable, Hashable, Identifiable {
    case compact
    case balanced
    case statement

    var id: String { rawValue }
}

enum PlantCatalogHabit: String, CaseIterable, Hashable, Identifiable {
    case upright
    case spreading
    case climbing
    case trailing

    var id: String { rawValue }
}

enum PlantCatalogCareLevel: String, CaseIterable, Hashable, Identifiable {
    case minimal
    case regular

    var id: String { rawValue }
}

enum PlantCatalogCareOption: String, CaseIterable, Hashable, Identifiable {
    case lowWater
    case slowGrowth
    case littlePruning
    case longBloom

    var id: String { rawValue }
}

/// Immutable index of all catalog signals inferred from a plant. Building it
/// once is more expensive than a direct flag lookup, but all subsequent
/// searches, filters and suitability evaluations become simple set/string
/// operations.
struct PlantCatalogTraitsSnapshot {
    let searchableText: String
    let sunlightTolerances: PlantCatalogTraits.SunlightTolerances
    let goals: Set<PlantCatalogGoal>
    let kinds: Set<PlantCatalogKind>
    let colors: Set<PlantCatalogColor>
    let appearances: Set<PlantCatalogAppearance>
    let size: PlantCatalogSize
    let habits: Set<PlantCatalogHabit>
    let isEasyCare: Bool
    let needsLittleWater: Bool
    let isSlowGrowing: Bool
    let needsLittlePruning: Bool
    let hasLongBloom: Bool
}

struct PlantCatalogFilters: Equatable {
    var goals: Set<PlantCatalogGoal> = []
    var kinds: Set<PlantCatalogKind> = []
    var colors: Set<PlantCatalogColor> = []
    var appearances: Set<PlantCatalogAppearance> = []
    var scale: PlantCatalogScale?
    var habits: Set<PlantCatalogHabit> = []
    var careLevel: PlantCatalogCareLevel?
    var careOptions: Set<PlantCatalogCareOption> = []

    var isEmpty: Bool {
        goals.isEmpty
            && kinds.isEmpty
            && colors.isEmpty
            && appearances.isEmpty
            && scale == nil
            && habits.isEmpty
            && careLevel == nil
            && careOptions.isEmpty
    }

    var count: Int {
        goals.count
            + kinds.count
            + colors.count
            + appearances.count
            + (scale == nil ? 0 : 1)
            + habits.count
            + (careLevel == nil ? 0 : 1)
            + careOptions.count
    }

    func matches(_ plant: Plant) -> Bool {
        guard !isEmpty else { return true }
        return matches(PlantCatalogTraits.snapshot(for: plant))
    }

    func matches(_ traits: PlantCatalogTraitsSnapshot) -> Bool {
        guard !isEmpty else { return true }

        if !goals.isEmpty, goals.isDisjoint(with: traits.goals) { return false }

        if !kinds.isEmpty, kinds.isDisjoint(with: traits.kinds) { return false }

        if !colors.isEmpty, colors.isDisjoint(with: traits.colors) { return false }

        if !appearances.isSubset(of: traits.appearances) { return false }

        if let scale {
            let requiredSize: PlantCatalogSize
            switch scale {
            case .compact: requiredSize = .small
            case .balanced: requiredSize = .medium
            case .statement: requiredSize = .large
            }
            if traits.size != requiredSize { return false }
        }

        if !habits.isEmpty, habits.isDisjoint(with: traits.habits) { return false }

        if careLevel == .minimal, !traits.isEasyCare { return false }

        for option in careOptions {
            switch option {
            case .lowWater:
                if !traits.needsLittleWater { return false }
            case .slowGrowth:
                if !traits.isSlowGrowing { return false }
            case .littlePruning:
                if !traits.needsLittlePruning { return false }
            case .longBloom:
                if !traits.hasLongBloom { return false }
            }
        }

        return true
    }
}

enum PlantCatalogTraits {
    /// Text normalization is the most expensive part of trait inference. An
    /// `NSCache` is thread-safe and lets the one-time index reuse the exact same
    /// normalized text across all inference families.
    private static let searchableTextCache = NSCache<NSString, NSString>()

    struct SunlightTolerances {
        let shade: Bool
        let fullSun: Bool

        var hasKnownValue: Bool { shade || fullSun }
    }

    static func clearSearchableTextCache() {
        searchableTextCache.removeAllObjects()
    }

    static func snapshot(for plant: Plant) -> PlantCatalogTraitsSnapshot {
        PlantCatalogTraitsSnapshot(
            searchableText: searchableText(for: plant),
            sunlightTolerances: sunlightTolerances(for: plant),
            goals: goals(for: plant),
            kinds: kinds(for: plant),
            colors: colors(for: plant),
            appearances: appearances(for: plant),
            size: size(for: plant),
            habits: habits(for: plant),
            isEasyCare: isEasyCare(plant),
            needsLittleWater: needsLittleWater(plant),
            isSlowGrowing: isSlowGrowing(plant),
            needsLittlePruning: needsLittlePruning(plant),
            hasLongBloom: hasLongBloom(plant)
        )
    }

    static func searchableText(for plant: Plant) -> String {
        let cacheKey = plant.id as NSString
        if let cached = searchableTextCache.object(forKey: cacheKey) {
            return cached as String
        }

        var parts = [plant.name, plant.type, plant.description]

        for translation in plant.translations.values {
            parts.append(translation.description)
            parts.append(translation.plantType)
            if let sun = translation.sun {
                parts.append(sun.lightType ?? "")
                parts.append(sun.durationPerDay ?? "")
            }
            if let growth = translation.lifeCycle?.growth { parts.append(growth) }
            if let flowering = translation.lifeCycle?.flowering { parts.append(flowering) }
            if let difficulty = translation.care?.difficulty { parts.append(difficulty) }
        }

        let value = normalized(parts.joined(separator: " "))
        searchableTextCache.setObject(value as NSString, forKey: cacheKey)
        return value
    }

    static func sunlightTolerances(for plant: Plant) -> SunlightTolerances {
        if let flags = plant.flags, flags.shadeTolerant || flags.fullSunTolerant {
            return SunlightTolerances(shade: flags.shadeTolerant, fullSun: flags.fullSunTolerant)
        }

        let text = searchableText(for: plant)
        let shade = containsAny(text, [
            "ombre", "mi-ombre", "lumiere indirecte", "faible luminosite",
            "shade", "partial shade", "indirect light", "low light",
            "schatten", "indirektes licht", "sombra", "luz indirecta"
        ])
        let fullSun = containsAny(text, [
            "plein soleil", "soleil direct", "full sun", "direct sunlight",
            "volle sonne", "sonne direkt", "pleno sol", "sol directo"
        ])
        return SunlightTolerances(shade: shade, fullSun: fullSun)
    }

    static func size(for plant: Plant) -> PlantCatalogSize {
        if plant.flags?.compact == true { return .small }

        let text = searchableText(for: plant)
        if containsAny(text, [
            "compact", "miniature", "mini ", "nain", "naine", "bonsai",
            "small plant", "dwarf", "kleinwuchsig", "pequena"
        ]) {
            return .small
        }
        if containsAny(text, [
            "grand arbre", "petit arbre", "arbre d'ornement", "arbuste", "palmier",
            "large tree", "small tree", "ornamental tree", "shrub", "palm tree",
            "hoher baum", "strauch", "palme", "arbol", "arbusto", "palmera"
        ]) {
            return .large
        }
        if containsAny(text, [
            "taille moyenne", "medium-sized", "medium size", "mittelgross", "tamano medio"
        ]) {
            return .medium
        }

        let inferredKinds = kinds(for: plant)
        if !inferredKinds.isDisjoint(with: [.tree, .shrub, .palm]) { return .large }
        if !inferredKinds.isEmpty { return .medium }
        return .unknown
    }

    static func isFlowering(_ plant: Plant) -> Bool {
        if plant.flags?.flowering == true { return true }
        let text = searchableText(for: plant)
        return containsAny(text, [
            "floraison", "fleuri", "fleur", "colore", "flowering", "flower",
            "colorful", "blute", "bluhend", "floracion", "flor"
        ])
    }

    static func isEasyCare(_ plant: Plant) -> Bool {
        if plant.flags?.easyCare == true { return true }
        let text = searchableText(for: plant)
        return containsAny(text, [
            "facile d'entretien", "entretien facile", "debutant", "peu exigeant",
            "easy care", "easy-care", "beginner", "low maintenance",
            "pflegeleicht", "anfanger", "facil de cuidar", "principiante"
        ])
    }

    static func goals(for plant: Plant) -> Set<PlantCatalogGoal> {
        let text = searchableText(for: plant)
        let inferredKinds = kinds(for: plant)
        var values = Set<PlantCatalogGoal>()

        if isFlowering(plant) || !colors(for: plant).isEmpty { values.insert(.addColor) }
        if size(for: plant) == .large
            || plant.flags?.climbing == true
            || containsAny(text, ["brise-vue", "brise vue", "haie", "privacy", "screening", "sichtschutz", "privacidad"]) {
            values.insert(.createPrivacy)
        }
        if size(for: plant) == .large || !inferredKinds.isDisjoint(with: [.tree, .shrub, .palm]) {
            values.insert(.addVolume)
        }
        if plant.flags?.climbing == true || PlantPlacementCompatibility.isWallCapable(plant) {
            values.insert(.coverWall)
        }
        if plant.flags?.trailing == true || PlantPlacementCompatibility.isHangingCapable(plant) {
            values.insert(.createCascade)
        }
        if inferredKinds.contains(.groundcover) { values.insert(.coverGround) }
        if containsAny(text, [
            "pollinisateur", "abeille", "papillon", "pollinator", "bee friendly", "butterfly",
            "bienenfreundlich", "mariposa", "polinizador"
        ]) {
            values.insert(.attractPollinators)
        }
        if inferredKinds.contains(.aromaticEdible) { values.insert(.edibleAromatic) }
        if size(for: plant) == .large
            || !inferredKinds.isDisjoint(with: [.palm, .orchid, .tree])
            || containsAny(text, ["point focal", "architectural", "sculptural", "statement plant"]) {
            values.insert(.focalPoint)
        }

        return values
    }

    static func kinds(for plant: Plant) -> Set<PlantCatalogKind> {
        let text = searchableText(for: plant)
        var values = Set<PlantCatalogKind>()

        if isFlowering(plant) { values.insert(.floweringPlant) }
        if containsAny(text, ["cactus", "succulente", "succulent", "agave", "aloe", "sukkulente", "suculenta"]) {
            values.insert(.cactusSucculent)
        }
        if containsAny(text, ["palmier", "palm tree", "palm plant", "palme", "palmera"]) { values.insert(.palm) }
        if containsAny(text, ["fougere", "fern", "farn", "helecho"]) { values.insert(.fern) }
        if containsAny(text, ["orchidee", "orchid", "orchidee", "orquidea"]) { values.insert(.orchid) }
        if containsAny(text, ["arbre", " tree", "baum", "arbol"]) { values.insert(.tree) }
        if containsAny(text, ["arbuste", "shrub", "bush", "strauch", "arbusto"]) { values.insert(.shrub) }
        if containsAny(text, ["vivace", "perennial", "mehrjahrig", "perenne"]) { values.insert(.perennial) }
        if containsAny(text, ["annuelle", "annual plant", "einjahrig", "anual"]) { values.insert(.annual) }
        if containsAny(text, ["graminee", "ornamental grass", "ziergras", "graminea"]) { values.insert(.grass) }
        if containsAny(text, ["couvre-sol", "couvre sol", "groundcover", "ground cover", "bodendecker", "cubresuelo"]) {
            values.insert(.groundcover)
        }
        if plant.flags?.climbing == true || containsAny(text, ["grimpante", "climbing", "climber", "kletterpflanze", "trepadora"]) {
            values.insert(.climbing)
        }
        if containsAny(text, [
            "aromatique", "comestible", "potager", "herbe culinaire", "edible", "culinary herb",
            "aromatic herb", "essbar", "krauter", "comestible", "aromatica"
        ]) {
            values.insert(.aromaticEdible)
        }

        let specialKinds: Set<PlantCatalogKind> = [
            .cactusSucculent, .palm, .fern, .orchid, .tree, .shrub, .perennial,
            .annual, .grass, .groundcover, .climbing, .aromaticEdible
        ]
        if values.isDisjoint(with: specialKinds) { values.insert(.greenPlant) }
        return values
    }

    static func colors(for plant: Plant) -> Set<PlantCatalogColor> {
        let text = searchableText(for: plant)
        var values = Set<PlantCatalogColor>()
        let keywords: [(PlantCatalogColor, [String])] = [
            (.white, ["blanc", "blanche", "white", "weiss", "blanco", "blanca"]),
            (.yellow, ["jaune", "yellow", "gelb", "amarillo", "amarilla"]),
            (.orange, ["orange", "orangefarben", "naranja"]),
            (.red, ["rouge", " red ", "rot", "rojo", "roja"]),
            (.pink, ["rose", " pink", "rosa"]),
            (.purple, ["violet", "pourpre", "purple", "violett", "morado", "morada"]),
            (.blue, ["bleu", " blue", "blau", "azul"]),
            (.green, ["vert", " green", "grun", "verde"]),
            (.dark, ["noir", "sombre", "black", "dark foliage", "schwarz", "dunkel", "negro", "oscuro"])
        ]
        for (color, words) in keywords where containsAny(text, words) {
            values.insert(color)
        }
        return values
    }

    static func appearances(for plant: Plant) -> Set<PlantCatalogAppearance> {
        let text = searchableText(for: plant)
        var values = Set<PlantCatalogAppearance>()
        if isFlowering(plant) { values.insert(.flowering) }
        if containsAny(text, ["panache", "variegated", "panaschiert", "variegado"]) { values.insert(.variegated) }
        if containsAny(text, ["persistant", "evergreen", "immergrun", "perenne de hoja"]) { values.insert(.evergreen) }
        if containsAny(text, ["parfume", "odorant", "fragrant", "scented", "duftend", "perfumado", "fragante"]) {
            values.insert(.fragrant)
        }
        if containsAny(text, [
            "feuillage decoratif", "feuillage graphique", "decorative foliage", "ornamental foliage",
            "dekoratives blatt", "follaje decorativo"
        ]) || plant.flags?.airPurifying == true {
            values.insert(.decorativeFoliage)
        }
        return values
    }

    static func habits(for plant: Plant) -> Set<PlantCatalogHabit> {
        let text = searchableText(for: plant)
        var values = Set<PlantCatalogHabit>()
        if plant.flags?.climbing == true || containsAny(text, ["grimpant", "climbing", "kletternd", "trepador"]) {
            values.insert(.climbing)
        }
        if plant.flags?.trailing == true || containsAny(text, ["retombant", "trailing", "hanging", "hangend", "colgante"]) {
            values.insert(.trailing)
        }
        if containsAny(text, ["erige", "vertical", "upright", "columnar", "aufrecht", "erguido"]) {
            values.insert(.upright)
        }
        if containsAny(text, ["etale", "buissonnant", "spreading", "bushy", "ausladend", "extendido"]) {
            values.insert(.spreading)
        }
        if values.isEmpty { values.insert(.upright) }
        return values
    }

    static func needsLittleWater(_ plant: Plant) -> Bool {
        if plant.flags?.droughtTolerant == true { return true }
        let text = searchableText(for: plant)
        return containsAny(text, [
            "peu d'arrosage", "arrosage espace", "resiste a la secheresse", "low water", "drought tolerant",
            "wenig wasser", "trockenheitsvertraglich", "poco riego", "resistente a la sequia"
        ])
    }

    static func isSlowGrowing(_ plant: Plant) -> Bool {
        containsAny(searchableText(for: plant), [
            "croissance lente", "slow growing", "slow growth", "langsam wachsend", "crecimiento lento"
        ])
    }

    static func needsLittlePruning(_ plant: Plant) -> Bool {
        containsAny(searchableText(for: plant), [
            "peu de taille", "taille inutile", "sans taille", "little pruning", "no pruning",
            "wenig schnitt", "kein schnitt", "poca poda", "sin poda"
        ])
    }

    static func hasLongBloom(_ plant: Plant) -> Bool {
        containsAny(searchableText(for: plant), [
            "floraison longue", "floraison prolongee", "long blooming", "long flowering",
            "lange blute", "floracion larga", "floracion prolongada"
        ])
    }

    private static func containsAny(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains { text.contains($0) }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
