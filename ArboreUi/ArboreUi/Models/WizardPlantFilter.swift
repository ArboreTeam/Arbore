import Foundation

// MARK: - WizardPlantFilter
/// Converts GardenWizardDTO selections into plant filtering logic.
/// Uses flexible keyword matching since plant data is AI-generated free text.

struct WizardPlantFilter {
    let wizard: GardenWizardDTO

    /// Returns true if this plant matches the wizard's criteria.
    /// If a filter criterion is nil/empty, it is treated as "no preference" → always matches.
    func matches(plant: Plant, locale: String = "fr") -> Bool {
        guard let translation = plant.translations[locale] else {
            // No translation data → can't filter, include the plant
            return true
        }

        // 1. Style → keywords in name, type, description
        if !matchesStyle(plant: plant, translation: translation) { return false }

        // 2. Exposure → sun.lightType
        if !matchesExposure(translation: translation) { return false }

        // 3. Maintenance → care.difficulty + water.frequency
        if !matchesMaintenance(translation: translation) { return false }

        // 4. Safety → exclude toxic plants
        if !matchesSafety(translation: translation) { return false }

        // 5. Soil → soilAndPot.substrate
        if !matchesSoil(translation: translation) { return false }

        return true
    }

    /// True if wizard has any non-nil filter criteria
    var hasActiveFilters: Bool {
        !wizard.style.isEmpty ||
        (wizard.exposure != nil && !wizard.exposure!.isEmpty) ||
        (wizard.maintenance != nil && !wizard.maintenance!.isEmpty) ||
        (wizard.safety != nil && !wizard.safety!.isEmpty) ||
        (wizard.soil != nil && !wizard.soil!.isEmpty)
    }

    // MARK: - Style Matching

    /// Maps garden styles to keywords that describe matching plants.
    /// A plant matches if its name, type, or description contains any of the keywords.
    private static let styleKeywords: [String: [String]] = [
        // Moderne & minimaliste → plantes graphiques, feuillage structuré
        "moderne": [
            "monstera", "ficus", "sansevieria", "dracaena", "zamioculcas", "zz",
            "agave", "yucca", "palmier", "palm", "pilea", "caoutchouc", "rubber",
            "graphique", "architectural", "structur", "épuré", "moderne",
            "minimaliste", "géométrique", "design"
        ],
        // Fleuri & coloré → plantes à fleurs, couleurs vives
        "fleuri": [
            "orchidée", "orchid", "rose", "hibiscus", "jasmin", "gardénia",
            "bougainvillier", "géranium", "azalée", "camélia", "lavande",
            "hortensia", "tulipe", "dahlia", "chrysanthème", "anthurium",
            "fleur", "flower", "coloré", "floraison", "pétale", "bouton"
        ],
        // Champêtre & sauvage → plantes rustiques, naturelles
        "champêtre": [
            "sauvage", "wild", "fougère", "fern", "lierre", "ivy",
            "mousse", "moss", "graminée", "herbe", "grass",
            "champêtre", "rustique", "naturel", "vivace",
            "pothos", "chlorophytum", "tradescantia", "asparagus"
        ],
        // Zen & japonais → plantes apaisantes, feuillage zen
        "zen": [
            "bambou", "bamboo", "bonsaï", "bonsai", "érable", "maple",
            "azalée", "mousse", "fougère", "nénuphar", "lotus",
            "zen", "japonais", "japan", "apaisant", "méditat",
            "palmier", "palm", "chamaedorea", "livistona", "areca",
            "pilea", "dracaena", "ficus"
        ],
        // Méditerranéen → plantes résistantes, aromatiques
        "méditerranéen": [
            "olivier", "olive", "lavande", "romarin", "rosemary", "thym", "thyme",
            "citronnier", "lemon", "oranger", "orange", "figuier", "fig",
            "bougainvillier", "agave", "aloès", "aloe", "cactus", "succulente",
            "méditerranéen", "résistant", "soleil", "sécheresse", "aride",
            "aromatique", "yucca"
        ]
    ]

    private func matchesStyle(plant: Plant, translation: PlantTranslation) -> Bool {
        let style = wizard.style.lowercased()

        // "Sans préférence" or empty → no filter
        if style.isEmpty || style.contains("sans préférence") || style.contains("nopref") {
            return true
        }

        // Find matching keyword list
        let keywords: [String]? = Self.styleKeywords.first { key, _ in
            style.contains(key)
        }?.value

        guard let kws = keywords else {
            // Unknown style → no filter
            return true
        }

        // Build a combined text to search in
        let searchText = [
            plant.name,
            plant.type,
            translation.description,
            translation.plantType
        ].joined(separator: " ").lowercased()

        // Plant matches if ANY keyword is found
        return kws.contains { searchText.contains($0) }
    }

    // MARK: - Exposure Matching

    private func matchesExposure(translation: PlantTranslation) -> Bool {
        guard let exposure = wizard.exposure, !exposure.isEmpty else { return true }

        let plantLight = (translation.sun?.lightType ?? "").lowercased()
        let plantDuration = (translation.sun?.durationPerDay ?? "").lowercased()
        let combined = plantLight + " " + plantDuration

        let exp = exposure.lowercased()

        // "Soleil direct (6h+)" → fullSun
        if exp.contains("soleil direct") || exp.contains("6h") || exp == "fullsun" {
            // Accept plants that like direct sun / full light
            // Reject plants that specifically need shade only
            let shadeOnly = combined.contains("ombre") && !combined.contains("mi-ombre")
                && !combined.contains("indirect") && !combined.contains("direct")
            return !shadeOnly
        }

        // "Mi-ombre" → partialShade
        if exp.contains("mi-ombre") || exp == "partialshade" {
            // Accept plants that tolerate indirect light or partial shade
            // Reject plants that strictly need full direct sun for 6h+
            let needsFullSun = combined.contains("direct") && combined.contains("6h")
            return !needsFullSun
        }

        // "Ombragé" → shade
        if exp.contains("ombrag") || exp == "shade" {
            // Only accept plants that can live in low light / shade
            let likesShade = combined.contains("ombre") || combined.contains("faible")
                || combined.contains("indirect") || combined.contains("basse")
                || combined.contains("tamisé") || combined.contains("shade")
                || combined.contains("low") || combined.contains("mi-ombre")
            return likesShade
        }

        // "Je ne sais pas" → no filter
        return true
    }

    // MARK: - Maintenance Matching

    private func matchesMaintenance(translation: PlantTranslation) -> Bool {
        guard let maintenance = wizard.maintenance, !maintenance.isEmpty else { return true }

        let plantDifficulty = (translation.care?.difficulty ?? "").lowercased()
        let plantWater = (translation.water?.frequency ?? "").lowercased()
        let combined = plantDifficulty + " " + plantWater

        let maint = maintenance.lowercased()

        // "Très facile" → veryEasy
        if maint.contains("très facile") || maint == "veryeasy" {
            // Only accept very easy / easy plants
            let isEasy = combined.contains("facile") || combined.contains("simple")
                || combined.contains("easy") || combined.contains("débutant")
                || combined.contains("minimal") || combined.contains("peu")
                || combined.contains("résistant")
            let isHard = combined.contains("exigeant") || combined.contains("difficile")
                || combined.contains("expert") || combined.contains("hard")
            return isEasy || !isHard
        }

        // "Facile" → easy
        if maint.contains("facile") || maint == "easy" {
            // Accept easy + moderate plants
            let isHard = combined.contains("exigeant") || combined.contains("difficile")
                || combined.contains("expert") || combined.contains("hard")
            return !isHard
        }

        // "Exigeant" → demanding - show ALL plants, including demanding ones
        if maint.contains("exigeant") || maint == "demanding" {
            return true
        }

        return true
    }

    // MARK: - Safety Matching

    private func matchesSafety(translation: PlantTranslation) -> Bool {
        guard let safety = wizard.safety, !safety.isEmpty else { return true }

        // If "Aucune contrainte" is selected, no filtering needed
        if safety.contains("Aucune contrainte") || safety.contains("none") {
            return true
        }

        let problems = (translation.health?.commonProblems ?? []).joined(separator: " ").lowercased()
        let treatments = (translation.health?.treatments ?? []).joined(separator: " ").lowercased()
        let description = translation.description.lowercased()
        let combined = problems + " " + treatments + " " + description

        let toxicKeywords = ["toxique", "toxic", "dangere", "danger", "poison",
                             "irritant", "nocif", "vénéneux", "nocive"]

        let isToxic = toxicKeywords.contains { combined.contains($0) }

        if isToxic {
            // If user wants pet-safe plants, exclude toxic ones
            if safety.contains("Éviter les plantes toxiques pour les animaux")
                || safety.contains("pets") {
                let petToxic = combined.contains("animal") || combined.contains("chat")
                    || combined.contains("chien") || combined.contains("pet")
                    || combined.contains("cat") || combined.contains("dog")
                    || isToxic
                if petToxic { return false }
            }

            // If user wants child-safe plants, exclude dangerous ones
            if safety.contains("Éviter les plantes dangereuses pour les enfants")
                || safety.contains("children") {
                let childDanger = combined.contains("enfant") || combined.contains("child")
                    || combined.contains("ingestion") || combined.contains("ingér")
                    || isToxic
                if childDanger { return false }
            }
        }

        return true
    }

    // MARK: - Soil Matching

    private func matchesSoil(translation: PlantTranslation) -> Bool {
        guard let soil = wizard.soil, !soil.isEmpty else { return true }

        let plantSoil = (translation.soilAndPot?.substrate ?? "").lowercased()
        let plantDrainage = (translation.soilAndPot?.drainage ?? "").lowercased()
        let combined = plantSoil + " " + plantDrainage

        let s = soil.lowercased()

        // "Je ne sais pas" → no filter
        if s.contains("je ne sais pas") || s.contains("unknown") {
            return true
        }

        // "Riche" → rich soil
        if s.contains("riche") || s == "rich" {
            let likesRich = combined.contains("riche") || combined.contains("rich")
                || combined.contains("humus") || combined.contains("fertil")
                || combined.contains("terreau") || combined.contains("nutritif")
            let needsDry = combined.contains("sableux") || combined.contains("caillou")
            // If plant needs dry soil, it doesn't match rich soil
            return likesRich || !needsDry
        }

        // "Sec" → dry soil
        if s.contains("sec") || s == "dry" {
            let likesDry = combined.contains("sec") || combined.contains("dry")
                || combined.contains("drain") || combined.contains("sable")
                || combined.contains("sand") || combined.contains("aride")
                || combined.contains("cact")
            return likesDry
        }

        // "Rocailleux" → rocky
        if s.contains("rocailleux") || s == "rocky" {
            let likesRocky = combined.contains("rocai") || combined.contains("rocky")
                || combined.contains("caillou") || combined.contains("minéral")
                || combined.contains("gravier") || combined.contains("drain")
                || combined.contains("pierre")
            return likesRocky
        }

        // "Retient l'eau" → water retentive
        if s.contains("retient") || s == "waterretentive" {
            let likesWet = combined.contains("humide") || combined.contains("humid")
                || combined.contains("tourbe") || combined.contains("peat")
                || combined.contains("retient") || combined.contains("moist")
                || combined.contains("argile") || combined.contains("clay")
            return likesWet
        }

        return true
    }
}
