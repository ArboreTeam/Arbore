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

        appendSpaceCriterion(plant: plant, criteria: &criteria, missing: &missing)
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

    /// Milieu de culture, lu sur `environments` — un champ clos (`indoor`,
    /// `outdoor`, `both`) rempli sur 1021 fiches sur 1021.
    ///
    /// Le repli textuel qui vivait ici cherchait « plante d'intérieur »,
    /// « houseplant », « zimmerpflanze » dans la prose traduite. Il ne
    /// s'exécutait déjà plus — le champ est complet — et il est retiré plutôt
    /// que laissé en embuscade pour la prochaine fiche importée sans
    /// `environments` (#792). Sans le fait, le critère est MANQUANT, pas
    /// deviné.
    private func appendSpaceCriterion(
        plant: Plant,
        criteria: inout [Criterion],
        missing: inout [String]
    ) {
        guard let space = GardenSpaceType(rawValue: wizard.spaceType) else {
            missing.append("AR_CATALOG_MISSING_SPACE_CONTEXT")
            return
        }

        let expected = space == .interior ? "indoor" : "outdoor"
        guard let fact = plant.botanicalProfile?.environments else {
            missing.append("AR_CATALOG_MISSING_ENVIRONMENT")
            return
        }

        markEvidence(fact.evidence, missing: &missing)
        let values = Set(fact.value.map(normalized))
        if values.contains(expected) || values.contains("both") {
            criteria.append(.positive("AR_CATALOG_REASON_SPACE_MATCH"))
        } else {
            criteria.append(.critical("AR_CATALOG_REASON_SPACE_CONFLICT"))
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
        // Une seule lecture des libellés du questionnaire, partagée avec la
        // politique du catalogue (#783). Il y en avait trois, avec trois
        // tolérances différentes.
        let requirement = Plant.HouseholdSafetyRequirement(wizardSafety: wizard.safety)

        if requirement.pets {
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

        if requirement.children {
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
        fact: PlantToxicityFact?,
        legacyToxic: Bool?,
        safeReason: String,
        conflictReason: String,
        missingKey: String,
        criteria: inout [Criterion],
        missing: inout [String]
    ) {
        if let fact {
            // Seul axe à exiger plus que le plancher : une source nommée, au
            // moins au niveau du genre.
            markEvidence(fact.evidence, minimum: .moderate, missing: &missing)
            // Le verdict est lu, pas deviné. Cette branche refaisait ici le
            // même test de sous-chaîne que `Plant`, avec les mêmes listes dans
            // le même ordre — donc le même piège, « unsafe » contenant
            // « safe » (#778). Deux copies d'une décision de sécurité, c'était
            // une copie de trop (#780).
            switch fact.verdict {
            case .safe:
                criteria.append(.positive(safeReason))
            case .toxic:
                criteria.append(.critical(conflictReason))
            case nil:
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

    /// Exige une provenance, et une confiance AU MOINS égale à `minimum`.
    ///
    /// Le seuil dépend de l'axe, et cette asymétrie est le cœur du réglage :
    /// un arrosage déduit qui se trompe coûte une plante maussade, une
    /// toxicité qui se trompe coûte un animal. Le dépôt écrivait déjà ce
    /// raisonnement ailleurs — `matchesSafety`, la doc de `petToxicity()` —
    /// mais le contrôle de provenance, lui, exigeait `high` de TOUS les axes.
    ///
    /// Comme les trois axes horticoles sont tous `derived` → `low` et que la
    /// toxicité est `moderate` au mieux sur 25 des 38 fiches, cet unique seuil
    /// échouait partout : aucune plante ne pouvait atteindre `.suitable`.
    ///
    /// - `low` par défaut, donc pour le soleil, l'eau, le drainage, les
    ///   dimensions, le vent, le sel, la température.
    /// - `moderate` pour la toxicité, décidé le 2026-11-06 : l'autorité au
    ///   niveau du GENRE est acceptée. Avec `high` strict, 13 plantes du
    ///   catalogue seraient certifiables ; avec le genre, 38. L'ASPCA fiche
    ///   elle-même certaines espèces au genre — « Mentha sp. » là où le thym
    ///   est « Thymus vulgaris ».
    ///
    /// Un `reliability` absent échoue quel que soit le seuil : ne rien
    /// consigner n'est pas une confiance faible, c'est une absence de source.
    private func markEvidence(
        _ evidence: PlantDataEvidence?,
        minimum: PlantDataReliability = .low,
        missing: inout [String]
    ) {
        guard let evidence,
              !(evidence.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                || !(evidence.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
              !(evidence.reviewedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
              let fiabilite = evidence.reliability,
              fiabilite >= minimum else {
            missing.append("AR_CATALOG_MISSING_VERIFIED_SOURCE")
            return
        }
    }

    private func unique(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    /// Normalisation d'une valeur CLOSE (`indoor`, `fast`, `high`…) avant
    /// comparaison par égalité. Ce n'est pas de l'analyse de prose : il n'y a
    /// plus aucun `contains` sur un texte de fiche dans ce fichier (#792).
    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Gabarit, en vocabulaire fermé. Il portait DÉJÀ `unknown`, ce qui donne le
/// modèle aux autres : l'inconnu est une valeur du vocabulaire, pas une
/// absence qu'on rabat sur un voisin.
enum PlantCatalogSize: String, Codable, CaseIterable, Hashable {
    case small
    case medium
    case large
    case unknown

    /// Décodage indulgent vers le PLANCHER. `unknown` EST le plancher ici : il
    /// n'affirme rien, et c'est ce qui rend la migration sans danger.
    init(from decoder: Decoder) throws {
        let conteneur = try decoder.singleValueContainer()
        guard let brut = try? conteneur.decode(String.self) else {
            self = .unknown
            return
        }
        let cle = brut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = PlantCatalogSize(rawValue: cle) ?? .unknown
    }
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
    /// Ajouté avec #792 : la typologie de #777 porte `conifere` sur 39 fiches
    /// et le vocabulaire n'avait aucune cible. Le rabattre sur `tree` ou
    /// `shrub` perdrait une distinction que l'utilisateur voit.
    case conifer

    var id: String { rawValue }
}

/// Les couleurs filtrables, en valeurs closes.
///
/// `silver` et `brown` ont été ajoutés après le premier remplissage, qui a
/// mesuré leur absence : les bases horticoles traitent `Gray/Silver` et
/// `Brown/Copper` comme des couleurs de feuille de plein droit, et 78 fiches
/// étaient mal décrites sans elles — dont les 14 `Olea europaea`, ramenées à
/// `green`, ce qui perd le gris-argent qui fait l'olivier.
///
/// `dark` reste réservé au presque-noir, conformément à son nuancier. Un
/// feuillage pourpre sombre relève de `purple`, pas de `dark`.
enum PlantCatalogColor: String, CaseIterable, Hashable, Identifiable {
    case white
    case yellow
    case orange
    case red
    case pink
    case purple
    case blue
    case green
    case silver
    case brown
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


/// Projection immuable des traits CLOS d'une plante.
///
/// Elle ne dérive plus rien : chaque champ est soit une valeur stockée sur la
/// fiche, soit un repli explicitement nommé sur un autre fait clos. La version
/// précédente relançait sept familles d'inférence par plante — `kinds` seul
/// balayait 36 motifs dans la prose des quatre langues — ce qui avait coûté un
/// gel de 2 000 ms au questionnaire (#499). Le coût disparaît avec la
/// dérivation : il n'y a plus rien à mémoïser, et plus aucune clé de cache à
/// tenir juste.
///
/// Les champs tri-états sont des `Bool?` : `nil` signifie « non établi » et ne
/// doit jamais se lire comme un `false`.
struct PlantCatalogTraitsSnapshot {
    let sunlightTolerances: PlantCatalogTraits.SunlightTolerances
    let goals: Set<PlantCatalogGoal>
    let kinds: Set<PlantCatalogKind>
    let colors: Set<PlantCatalogColor>
    let appearances: Set<PlantCatalogAppearance>
    let size: PlantCatalogSize
    let habits: Set<PlantCatalogHabit>
    let isEasyCare: Bool?
    let needsLittleWater: Bool?
    let isSlowGrowing: Bool?
    let needsLittlePruning: Bool?
    let hasLongBloom: Bool?
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

        // `== true` et non `!= false` : un trait non établi ne satisfait PAS
        // un critère demandé. Le filtre ne devine pas, il n'affirme que ce
        // qu'il sait (#792).
        if careLevel == .minimal, traits.isEasyCare != true { return false }

        for option in careOptions {
            switch option {
            case .lowWater:
                if traits.needsLittleWater != true { return false }
            case .slowGrowth:
                if traits.isSlowGrowing != true { return false }
            case .littlePruning:
                if traits.needsLittlePruning != true { return false }
            case .longBloom:
                if traits.hasLongBloom != true { return false }
            }
        }

        return true
    }
}

/// Index de RECHERCHE, et rien d'autre.
///
/// Ce texte sert à apparier ce que l'utilisateur TAPE dans la barre de
/// recherche. C'est de l'analyse d'entrée utilisateur — comme le `contientMots`
/// du backend qui retrouve une fiche nommée dans un message de chat — et non de
/// la dérivation sur nos propres données.
///
/// **Aucune décision de trait, de filtre, de sûreté ou de capacité de pose ne
/// doit le lire.** C'est précisément ce que faisaient les sept familles
/// d'inférence que #792 a retirées, et c'est pourquoi l'index porte désormais
/// un nom qui dit son seul usage légitime.
enum PlantSearchIndex {
    static func text(for plant: Plant) -> String {
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

        return parts
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}

/// Lecture des traits de catalogue depuis les valeurs CLOSES de la fiche.
///
/// Sept fonctions y dérivaient autrefois leur résultat de la prose traduite,
/// sur ~146 lignes de listes de mots-clés en quatre langues. Trois défauts s'y
/// cumulaient (#792) :
///
/// 1. **Le booléen ne savait dire qu'une moitié de la vérité.** Un
///    `flowering: false` ne voulait pas dire « ne fleurit pas » : il faisait
///    retomber sur la prose, et une description mentionnant « fleur »
///    suffisait à déclarer la plante fleurie.
/// 2. **Le trait dépendait de la langue affichée.** La même plante pouvait
///    être `large` en français et `unknown` en allemand.
/// 3. **Un mot-clé appariait ce qu'il ne devait pas.** La liste de `size`
///    contenait `"mini "` avec une espace — un garde-fou ajouté après coup,
///    qui disait à lui seul que la méthode était fragile.
///
/// Ce qui reste ici ne fait que LIRE : chaque fonction consulte un champ clos
/// du profil, et à défaut un repli nommé sur un autre fait clos. Le repli suit
/// la règle de la toxicité — seul un `true` informe, un `false` ou une absence
/// ne prouve rien.
enum PlantCatalogTraits {

    struct SunlightTolerances {
        let shade: Bool
        let fullSun: Bool

        var hasKnownValue: Bool { shade || fullSun }
    }

    static func snapshot(for plant: Plant) -> PlantCatalogTraitsSnapshot {
        let kinds = kinds(for: plant)
        let colors = colors(for: plant)
        let size = size(for: plant)

        return PlantCatalogTraitsSnapshot(
            sunlightTolerances: sunlightTolerances(for: plant),
            goals: goals(for: plant, kinds: kinds, colors: colors, size: size),
            kinds: kinds,
            colors: colors,
            appearances: appearances(for: plant),
            size: size,
            habits: habits(for: plant),
            isEasyCare: plant.trait(.easyCare),
            needsLittleWater: needsLittleWater(plant),
            isSlowGrowing: isSlowGrowing(plant),
            needsLittlePruning: needsLittlePruning(plant),
            hasLongBloom: hasLongBloom(plant)
        )
    }

    /// Tolérances d'exposition, lues sur `directSunHours`.
    ///
    /// Les bornes 3 h et 6 h ne sont pas inventées ici : ce sont celles que
    /// `appendSunlightCriterion` applique déjà au jardin de l'utilisateur, et
    /// les appliquer aussi à la plante garde les deux côtés comparables.
    ///
    /// Ce chemin ne sert plus qu'aux fiches SANS `directSunHours` : quand le
    /// fait existe, le critère d'exposition le lit directement. 920 fiches sur
    /// 1021 le portent.
    static func sunlightTolerances(for plant: Plant) -> SunlightTolerances {
        if let heures = plant.botanicalProfile?.directSunHours, heures.hasValue {
            return SunlightTolerances(
                shade: (heures.minimum ?? 0) <= 3,
                fullSun: (heures.maximum ?? 24) >= 6
            )
        }

        // Repli par drapeaux : seul leur `true` informe.
        guard let flags = plant.flags else {
            return SunlightTolerances(shade: false, fullSun: false)
        }
        return SunlightTolerances(shade: flags.shadeTolerant, fullSun: flags.fullSunTolerant)
    }

    /// Gabarit stocké. Le repli ne connaît qu'une affirmation — `compact` dit
    /// `small` — et ne sait rien produire d'autre : à défaut, `unknown`.
    static func size(for plant: Plant) -> PlantCatalogSize {
        if let stocke = plant.botanicalProfile?.size {
            // Le fait présent décide, y compris quand il dit `unknown`.
            return stocke.value
        }
        return plant.trait(.compact) == true ? .small : .unknown
    }

    /// Natures botaniques stockées.
    ///
    /// Il n'y a PLUS de `greenPlant` par défaut. L'ancienne lecture insérait
    /// cette nature dès qu'aucune autre n'avait été trouvée dans la prose :
    /// une plante dont on ignore la nature devenait « plante verte », ce qui
    /// est une affirmation qu'aucune donnée ne portait.
    static func kinds(for plant: Plant) -> Set<PlantCatalogKind> {
        if let stockees = plant.botanicalProfile?.kinds {
            // **Présent décide, même vide.** Une liste présente et vide dit
            // « on a cherché, aucune nature ne s'applique » ; elle n'ouvre
            // donc pas le repli. Seule l'ABSENCE du champ dit « on n'a pas
            // cherché ».
            return stockees.values
        }
        // Repli : la seule nature qu'un fait clos suffise à affirmer.
        return plant.trait(.climbing) == true ? [.climbing] : []
    }

    /// Couleurs stockées. Aucun repli n'existe : aucun autre champ clos ne
    /// porte la couleur d'une plante, et la deviner depuis la prose est
    /// exactement ce que #792 retire.
    static func colors(for plant: Plant) -> Set<PlantCatalogColor> {
        plant.botanicalProfile?.colors?.values ?? []
    }

    /// Usages visés.
    ///
    /// Le champ stocké décide seul quand il existe. À défaut, un repli composé
    /// d'autres faits CLOS — jamais de prose : la capacité de pose, la nature
    /// botanique, le gabarit et la floraison suffisent à affirmer six des neuf
    /// buts. `createPrivacy` et `attractPollinators` n'ont aucune source close
    /// et restent donc absents jusqu'au remplissage du champ.
    static func goals(for plant: Plant) -> Set<PlantCatalogGoal> {
        goals(for: plant, kinds: kinds(for: plant), colors: colors(for: plant), size: size(for: plant))
    }

    private static func goals(
        for plant: Plant,
        kinds: Set<PlantCatalogKind>,
        colors: Set<PlantCatalogColor>,
        size: PlantCatalogSize
    ) -> Set<PlantCatalogGoal> {
        if let stockes = plant.botanicalProfile?.goals {
            // Présent décide, même vide : « on a cherché, aucun but ne
            // s'applique » n'est pas « on n'a pas cherché ».
            return stockes.values
        }

        var valeurs = Set<PlantCatalogGoal>()

        if plant.trait(.flowering) == true || !colors.isEmpty { valeurs.insert(.addColor) }

        let poses = PlantPlacementCompatibility.supportedModes(for: plant)
        if poses.contains(.wall) { valeurs.insert(.coverWall) }
        if poses.contains(.ceiling) { valeurs.insert(.createCascade) }

        if kinds.contains(.groundcover) { valeurs.insert(.coverGround) }
        if kinds.contains(.aromaticEdible) { valeurs.insert(.edibleAromatic) }

        let volumineuses: Set<PlantCatalogKind> = [.tree, .shrub, .palm, .conifer]
        if size == .large || !kinds.isDisjoint(with: volumineuses) { valeurs.insert(.addVolume) }

        let remarquables: Set<PlantCatalogKind> = [.tree, .palm, .orchid]
        if size == .large || !kinds.isDisjoint(with: remarquables) { valeurs.insert(.focalPoint) }

        return valeurs
    }

    /// Apparences.
    ///
    /// `flowering` se lit sur le trait clos. `decorativeFoliage` se lit sur son
    /// `no` explicite : le champ « Période de floraison » des fiches en cache
    /// porte la valeur « Feuillage décoratif », qui est un `flowering: no` et
    /// non un silence — c'est tout l'intérêt du tri-état.
    ///
    /// `variegated`, `evergreen` et `fragrant` n'ont AUCUNE source close
    /// aujourd'hui. Ils ne se devinent pas : ces trois critères restent donc
    /// sans réponse jusqu'à ce qu'un champ les porte.
    static func appearances(for plant: Plant) -> Set<PlantCatalogAppearance> {
        var valeurs = Set<PlantCatalogAppearance>()
        switch plant.trait(.flowering) {
        case .some(true): valeurs.insert(.flowering)
        case .some(false): valeurs.insert(.decorativeFoliage)
        case .none: break
        }
        return valeurs
    }

    /// Ports.
    ///
    /// `climbing` et `trailing` se lisent sur les traits clos. `upright` et
    /// `spreading` n'ont aucune source close, et surtout : il n'y a plus de
    /// `upright` par défaut. L'ancienne lecture l'insérait quand rien d'autre
    /// n'avait été trouvé, ce qui faisait passer toute plante inconnue pour
    /// érigée.
    static func habits(for plant: Plant) -> Set<PlantCatalogHabit> {
        var valeurs = Set<PlantCatalogHabit>()
        if plant.trait(.climbing) == true { valeurs.insert(.climbing) }
        if plant.trait(.trailing) == true { valeurs.insert(.trailing) }
        return valeurs
    }

    /// Besoin en eau faible, lu sur `droughtTolerance` — un champ au
    /// vocabulaire fermé (`low`, `moderate`, `high`).
    ///
    /// `moderate` ne répond ni oui ni non : il rend `nil` plutôt que de
    /// trancher vers l'un des deux bords.
    static func needsLittleWater(_ plant: Plant) -> Bool? {
        if let fait = plant.botanicalProfile?.droughtTolerance {
            switch fait.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "high": return true
            case "low": return false
            default: return nil
            }
        }
        return plant.flags?.droughtTolerant == true ? true : nil
    }

    /// Les trois critères d'entretien SANS source close.
    ///
    /// Ils se dérivaient de la prose — « croissance lente », « peu de taille »,
    /// « floraison longue » — et rien ne les porte aujourd'hui en valeur
    /// fermée. Ils rendent donc `nil` : non établi, et un critère non établi
    /// ne satisfait pas une demande.
    ///
    /// Les laisser visibles et muets est un choix assumé : la correction est
    /// un champ clos côté fiche, pas un retour à la prose. En attendant, ces
    /// trois options du filtre ne renvoient rien — voir la note de #792.
    static func isSlowGrowing(_ plant: Plant) -> Bool? { nil }

    static func needsLittlePruning(_ plant: Plant) -> Bool? { nil }

    static func hasLongBloom(_ plant: Plant) -> Bool? { nil }
}
