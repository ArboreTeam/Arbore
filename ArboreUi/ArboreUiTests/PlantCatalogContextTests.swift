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
        airPurifying: Bool = false
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

        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(Plant.self, from: data)
    }
}
