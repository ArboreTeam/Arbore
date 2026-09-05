import XCTest
@testable import ArboreUi

final class PlantCatalogContextTests: XCTestCase {
    func testShadeGardenRecommendsShadeTolerantPlant() throws {
        let wizard = makeWizard(
            sunlight: GardenSunlightDTO(
                minimumHours: 1,
                maximumHours: 3,
                metadata: GardenValueMetadataDTO(source: .inferred, confidence: .medium)
            )
        )
        let shadePlant = try makePlant(shadeTolerant: true)
        let fullSunPlant = try makePlant(id: "sun", fullSunTolerant: true)
        let evaluator = PlantSuitabilityEvaluator(wizard: wizard)

        XCTAssertTrue(evaluator.evaluate(shadePlant).isRecommended)
        XCTAssertEqual(evaluator.evaluate(fullSunPlant).level, .unsuitable)
    }

    func testToxicPlantIsNeverRecommendedWhenPetSafetyWasRequested() throws {
        var wizard = makeWizard(
            sunlight: GardenSunlightDTO(
                minimumHours: 6,
                maximumHours: 10,
                metadata: GardenValueMetadataDTO(source: .inferred, confidence: .medium)
            )
        )
        wizard.safety = [SafetyOption.pets.rawValue]
        let plant = try makePlant(
            toxicToPets: true,
            fullSunTolerant: true
        )

        let result = PlantSuitabilityEvaluator(wizard: wizard).evaluate(plant)

        XCTAssertEqual(result.level, .unsuitable)
        XCTAssertTrue(result.warningReasonKeys.contains("AR_CATALOG_REASON_PET_CONFLICT"))
    }

    func testUnknownGardenAndPlantDataRemainMarkedForReview() throws {
        let wizard = GardenWizardDTO(
            style: "",
            spaceType: "",
            exposure: nil,
            maintenance: nil,
            safety: nil,
            soil: nil,
            scanMethod: nil
        )
        let plant = try makePlant(includeFlags: false)

        let result = PlantSuitabilityEvaluator(wizard: wizard).evaluate(plant)

        XCTAssertEqual(result.level, .needsReview)
        XCTAssertNil(result.score)
        XCTAssertFalse(result.isRecommended)
    }

    func testManualFiltersUseStructuredPlantTraits() throws {
        let plant = try makePlant(
            easyCare: true,
            flowering: true,
            compact: true
        )
        var filters = PlantCatalogFilters()
        filters.appearances = [.flowering]
        filters.scale = .compact
        filters.careLevel = .minimal

        XCTAssertTrue(filters.matches(plant))

        filters.scale = .statement
        XCTAssertFalse(filters.matches(plant))
    }

    func testPreferencesAreOrWithinAGroupAndAndBetweenGroups() throws {
        let plant = try makePlant(flowering: true)
        var filters = PlantCatalogFilters()
        filters.goals = [.addColor, .createPrivacy]

        XCTAssertTrue(filters.matches(plant))

        filters.kinds = [.tree]
        XCTAssertFalse(filters.matches(plant))
    }

    func testLowWaterPreferenceUsesStructuredDroughtFlag() throws {
        let plant = try makePlant(droughtTolerant: true)
        var filters = PlantCatalogFilters()
        filters.careOptions = [.lowWater]

        XCTAssertTrue(filters.matches(plant))
    }

    func testIndexedTraitsProduceTheSameSuitabilityAndFilterResult() throws {
        let wizard = makeWizard(
            sunlight: GardenSunlightDTO(
                minimumHours: 1,
                maximumHours: 3,
                metadata: GardenValueMetadataDTO(source: .inferred, confidence: .medium)
            )
        )
        let plant = try makePlant(
            easyCare: true,
            shadeTolerant: true,
            flowering: true,
            compact: true
        )
        let traits = PlantCatalogTraits.snapshot(for: plant)
        let evaluator = PlantSuitabilityEvaluator(wizard: wizard)
        var filters = PlantCatalogFilters()
        filters.appearances = [.flowering]
        filters.scale = .compact
        filters.careLevel = .minimal

        XCTAssertEqual(
            evaluator.evaluate(plant),
            evaluator.evaluate(plant, traits: traits)
        )
        XCTAssertEqual(filters.matches(plant), filters.matches(traits))
    }

    func testEmptyFiltersAcceptPlantWithoutBuildingRequirements() throws {
        let plant = try makePlant(includeFlags: false)

        XCTAssertTrue(PlantCatalogFilters().matches(plant))
    }

    func testSourcedOutdoorProfileCanBeCertifiedSuitable() throws {
        var wizard = makeWizard(
            sunlight: GardenSunlightDTO(
                minimumHours: 6,
                maximumHours: 8,
                metadata: GardenValueMetadataDTO(source: .declared, confidence: .high)
            )
        )
        wizard.spaceType = GardenSpaceType.garden.rawValue
        wizard.siteProfile?.climate = GardenClimateDTO(
            historicalMinimumTemperature: GardenTemperatureDTO(
                celsius: -5,
                metadata: GardenValueMetadataDTO(
                    source: .regionalEstimate,
                    confidence: .high,
                    sourceReference: "Climate normals",
                    observedAt: "2026-07-23"
                )
            )
        )
        let plant = try makePlant(
            includeFlags: false,
            botanicalProfile: botanicalProfile(
                environments: ["outdoor"],
                minimumTemperatureC: -12,
                directSunMinimum: 5,
                directSunMaximum: 10
            )
        )

        let result = PlantSuitabilityEvaluator(wizard: wizard).evaluate(plant)

        XCTAssertEqual(result.level, .suitable)
        XCTAssertTrue(result.missingDataKeys.isEmpty)
    }

    func testTemperatureConflictIsHardExclusionBeforeRanking() throws {
        var wizard = makeWizard(
            sunlight: GardenSunlightDTO(
                minimumHours: 4,
                maximumHours: 7,
                metadata: GardenValueMetadataDTO(source: .declared, confidence: .high)
            )
        )
        wizard.spaceType = GardenSpaceType.garden.rawValue
        wizard.siteProfile?.climate = GardenClimateDTO(
            historicalMinimumTemperature: GardenTemperatureDTO(
                celsius: -8,
                metadata: GardenValueMetadataDTO(source: .regionalEstimate, confidence: .high)
            )
        )
        let plant = try makePlant(
            includeFlags: false,
            botanicalProfile: botanicalProfile(
                environments: ["outdoor"],
                minimumTemperatureC: 5,
                directSunMinimum: 3,
                directSunMaximum: 8
            )
        )

        let result = PlantSuitabilityEvaluator(wizard: wizard).evaluate(plant)

        XCTAssertEqual(result.level, .unsuitable)
        XCTAssertTrue(result.warningReasonKeys.contains("AR_CATALOG_REASON_TEMPERATURE_CONFLICT"))
    }

    func testCoastalGardenRewardsSaltTolerantPlant() throws {
        var wizard = makeWizard(
            sunlight: GardenSunlightDTO(
                minimumHours: 6,
                maximumHours: 8,
                metadata: GardenValueMetadataDTO(source: .declared, confidence: .high)
            )
        )
        wizard.spaceType = GardenSpaceType.garden.rawValue
        wizard.siteProfile?.climate = coastalClimate()

        var profile = botanicalProfile(
            environments: ["outdoor"],
            minimumTemperatureC: -8,
            directSunMinimum: 4,
            directSunMaximum: 10
        )
        profile["saltTolerance"] = sourcedFact("high")
        let plant = try makePlant(includeFlags: false, botanicalProfile: profile)

        let result = PlantSuitabilityEvaluator(wizard: wizard).evaluate(plant)

        XCTAssertEqual(result.level, .suitable)
        XCTAssertTrue(result.positiveReasonKeys.contains("AR_CATALOG_REASON_COASTAL_MATCH"))
    }

    func testCoastalGardenWarnsWhenSaltToleranceIsLow() throws {
        var wizard = makeWizard(
            sunlight: GardenSunlightDTO(
                minimumHours: 6,
                maximumHours: 8,
                metadata: GardenValueMetadataDTO(source: .declared, confidence: .high)
            )
        )
        wizard.spaceType = GardenSpaceType.garden.rawValue
        wizard.siteProfile?.climate = coastalClimate()

        var profile = botanicalProfile(
            environments: ["outdoor"],
            minimumTemperatureC: -8,
            directSunMinimum: 4,
            directSunMaximum: 10
        )
        profile["saltTolerance"] = sourcedFact("low")
        let plant = try makePlant(includeFlags: false, botanicalProfile: profile)

        let result = PlantSuitabilityEvaluator(wizard: wizard).evaluate(plant)

        XCTAssertEqual(result.level, .needsReview)
        XCTAssertTrue(result.warningReasonKeys.contains("AR_CATALOG_REASON_COASTAL_CONFLICT"))
    }

    func testPotRequirementCanHardExcludeBalconyPlant() throws {
        var wizard = makeWizard(
            sunlight: GardenSunlightDTO(
                minimumHours: 4,
                maximumHours: 6,
                metadata: GardenValueMetadataDTO(source: .declared, confidence: .high)
            )
        )
        wizard.conditionalAnswers = GardenConditionalAnswersDTO(maximumContainerSize: .small)
        var profile = botanicalProfile(
            environments: ["outdoor"],
            minimumTemperatureC: -10,
            directSunMinimum: 3,
            directSunMaximum: 8
        )
        profile["minimumPotVolumeLiters"] = sourcedFact(25)
        let plant = try makePlant(includeFlags: false, botanicalProfile: profile)

        let result = PlantSuitabilityEvaluator(wizard: wizard).evaluate(plant)

        XCTAssertEqual(result.level, .unsuitable)
        XCTAssertTrue(result.warningReasonKeys.contains("AR_CATALOG_REASON_POT_SIZE_CONFLICT"))
    }

    private func makeWizard(sunlight: GardenSunlightDTO) -> GardenWizardDTO {
        GardenWizardDTO(
            style: "",
            spaceType: GardenSpaceType.balcony.rawValue,
            exposure: nil,
            maintenance: nil,
            safety: nil,
            soil: nil,
            scanMethod: nil,
            siteProfile: GardenSiteProfileDTO(sunlight: sunlight)
        )
    }

    private func makePlant(
        id: String = "plant",
        includeFlags: Bool = true,
        toxicToPets: Bool = false,
        toxicToChildren: Bool = false,
        easyCare: Bool = false,
        shadeTolerant: Bool = false,
        fullSunTolerant: Bool = false,
        droughtTolerant: Bool = false,
        humidityLoving: Bool = false,
        flowering: Bool = false,
        climbing: Bool = false,
        trailing: Bool = false,
        compact: Bool = false,
        airPurifying: Bool = false,
        botanicalProfile: [String: Any]? = nil
    ) throws -> Plant {
        var json: [String: Any] = [
            "id": id,
            "name": "Test plant",
            "type": "Plant",
            "imageURLs": [],
            "description": "",
            "translations": [:]
        ]

        if includeFlags {
            json["flags"] = [
                "toxicToPets": toxicToPets,
                "toxicToChildren": toxicToChildren,
                "easyCare": easyCare,
                "shadeTolerant": shadeTolerant,
                "fullSunTolerant": fullSunTolerant,
                "droughtTolerant": droughtTolerant,
                "humidityLoving": humidityLoving,
                "flowering": flowering,
                "climbing": climbing,
                "trailing": trailing,
                "compact": compact,
                "airPurifying": airPurifying
            ]
        }
        if let botanicalProfile {
            json["botanicalProfile"] = botanicalProfile
        }

        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(Plant.self, from: data)
    }

    private func botanicalProfile(
        environments: [String],
        minimumTemperatureC: Double,
        directSunMinimum: Double,
        directSunMaximum: Double
    ) -> [String: Any] {
        [
            "schemaVersion": 1,
            "environments": sourcedFact(environments),
            "minimumTemperatureC": sourcedFact(minimumTemperatureC),
            "directSunHours": sourcedRange(minimum: directSunMinimum, maximum: directSunMaximum, unit: "hours/day")
        ]
    }

    private func sourcedFact(_ value: Any) -> [String: Any] {
        [
            "value": value,
            "evidence": evidence()
        ]
    }

    private func sourcedRange(minimum: Double, maximum: Double, unit: String) -> [String: Any] {
        [
            "minimum": minimum,
            "maximum": maximum,
            "unit": unit,
            "evidence": evidence()
        ]
    }

    private func evidence() -> [String: Any] {
        [
            "sourceName": "Test horticultural source",
            "sourceURL": "https://example.test/plant",
            "reviewedAt": "2026-07-23",
            "reliability": "high"
        ]
    }

    private func coastalClimate() -> GardenClimateDTO {
        let metadata = GardenValueMetadataDTO(
            source: .regionalEstimate,
            confidence: .high,
            sourceReference: "Météo-France Données Publiques",
            observedAt: "2026-07-23"
        )
        return GardenClimateDTO(
            historicalMinimumTemperature: GardenTemperatureDTO(celsius: -5, metadata: metadata),
            coastalExposure: GardenCoastalExposureDTO(isCoastal: true, metadata: metadata)
        )
    }
}
