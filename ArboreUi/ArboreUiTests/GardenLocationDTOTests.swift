import XCTest
import simd
@testable import ArboreUi

final class GardenLocationDTOTests: XCTestCase {
    func testDeviceLocationIsRoundedBeforeEncoding() throws {
        let location = GardenLocationDTO.deviceApproximate(
            latitude: 48.8566,
            longitude: 2.3522,
            city: " Paris "
        )

        XCTAssertEqual(location.latitude, 48.86)
        XCTAssertEqual(location.longitude, 2.35)
        XCTAssertEqual(location.city, "Paris")
        XCTAssertEqual(location.source, .deviceApproximate)

        let json = String(decoding: try JSONEncoder().encode(location), as: UTF8.self)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("address"))
    }

    func testManualCityContainsNoCoordinates() {
        let location = GardenLocationDTO.manualCity("  Lyon  ")

        XCTAssertEqual(location.city, "Lyon")
        XCTAssertNil(location.latitude)
        XCTAssertNil(location.longitude)
        XCTAssertEqual(location.source, .manualCity)
    }

    func testLightExposureNormalizesHorizontalDirection() {
        let exposure = GardenLightExposureDTO.capture(
            direction: SIMD3<Float>(3, 4, -4),
            magneticYawRadians: 0.75,
            ambientIntensity: 820
        )

        XCTAssertEqual(exposure.directionY, 0)
        XCTAssertEqual(exposure.directionX, 0.6, accuracy: 0.0001)
        XCTAssertEqual(exposure.directionZ, -0.8, accuracy: 0.0001)
        XCTAssertEqual(exposure.magneticYawRadians, 0.75)
        XCTAssertEqual(exposure.ambientIntensity, 820)
    }

    func testSiteProfileRoundTripPreservesMetadataAndZones() throws {
        let metadata = GardenValueMetadataDTO(source: .declared, confidence: .high)
        let profile = GardenSiteProfileDTO(
            orientation: GardenOrientationDTO(degrees: 135, metadata: metadata),
            sunlight: GardenSunlightDTO(minimumHours: 3, maximumHours: 6, metadata: metadata),
            wind: GardenWindDTO(level: .moderate, metadata: metadata),
            availableHeight: GardenAvailableHeightDTO(meters: 2.4, metadata: metadata),
            plantingZones: [
                GardenPlantingZoneDTO(
                    id: "zone-1",
                    name: "Zone 1",
                    points: [[0, 0, 0], [1, 0, 0], [1, 0, 1]],
                    isExcluded: false,
                    metadata: metadata
                )
            ]
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(GardenSiteProfileDTO.self, from: data)

        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.orientation?.metadata.source, .declared)
        XCTAssertEqual(decoded.plantingZones.first?.points.count, 3)
    }

    func testConditionalAnswersRoundTripPreservesKnownValues() throws {
        let answers = GardenConditionalAnswersDTO(
            plantingMode: .containers,
            drainage: .slow,
            windExposure: nil,
            containerProject: nil,
            indoorHumidity: nil,
            nearbyHeat: nil
        )
        let wizard = GardenWizardDTO(
            style: "",
            spaceType: GardenSpaceType.garden.rawValue,
            exposure: nil,
            maintenance: nil,
            safety: [SafetyOption.pets.rawValue],
            soil: nil,
            scanMethod: ScanMethod.gardenPerimeter.rawValue,
            conditionalAnswers: answers
        )

        let data = try JSONEncoder().encode(wizard)
        let decoded = try JSONDecoder().decode(GardenWizardDTO.self, from: data)

        XCTAssertEqual(decoded.conditionalAnswers, answers)
        XCTAssertEqual(decoded.conditionalAnswers?.plantingMode, .containers)
        XCTAssertEqual(decoded.conditionalAnswers?.drainage, .slow)
        XCTAssertNil(decoded.conditionalAnswers?.windExposure)
    }

    func testEmptyConditionalAnswersAreRecognizedAsUnknown() {
        XCTAssertTrue(GardenConditionalAnswersDTO().isEmpty)
        XCTAssertFalse(GardenConditionalAnswersDTO(indoorHumidity: .humid).isEmpty)
    }
}
