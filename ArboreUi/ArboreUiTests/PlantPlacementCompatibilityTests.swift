//
//  PlantPlacementCompatibilityTests.swift
//  ArboreUiTests
//

import XCTest
@testable import ArboreUi

final class PlantPlacementCompatibilityTests: XCTestCase {

    func test_availablePlacementModes_areFloorWallCeilingOnly() {
        XCTAssertEqual(ARPlacementMode.allCases, [.floor, .wall, .ceiling])
        XCTAssertTrue(ARPlacementMode.floor.acceptedSurfaceTypes.contains(.shelf))
        XCTAssertTrue(ARPlacementMode.floor.acceptedSurfaceTypes.contains(.table))
        XCTAssertTrue(ARPlacementMode.floor.acceptedSurfaceTypes.contains(.windowsill))
    }

    func test_namedTrailingCatalogPlants_supportCeilingMode() throws {
        let names = [
            "Ceropegia Woodii",
            "Hoya Bella",
            "Hoya Linearis",
            "Philodendron scandens",
            "Pothos pictum"
        ]

        for name in names {
            let plant = try makePlant(name: name, type: "Plante d'interieur")
            XCTAssertTrue(
                PlantPlacementCompatibility.supports(plant, mode: .ceiling),
                "\(name) should be available for ceiling placement"
            )
        }
    }

    func test_climbingAndTrailingPlants_supportWallMode() throws {
        let pothos = try makePlant(name: "Pothos pictum", type: "Liane retombante")
        let ivy = try makePlant(name: "Lierre", type: "Plante grimpante")

        XCTAssertTrue(PlantPlacementCompatibility.supports(pothos, mode: .wall))
        XCTAssertTrue(PlantPlacementCompatibility.supports(ivy, mode: .wall))
    }

    func test_regularFloorPlant_doesNotSupportWallOrCeiling() throws {
        let ficus = try makePlant(name: "Ficus lyrata", type: "Arbuste d'interieur")

        XCTAssertTrue(PlantPlacementCompatibility.supports(ficus, mode: .floor))
        XCTAssertFalse(PlantPlacementCompatibility.supports(ficus, mode: .wall))
        XCTAssertFalse(PlantPlacementCompatibility.supports(ficus, mode: .ceiling))
    }

    func test_structuredFlags_enableSpecialModes() throws {
        let trailing = try makePlant(
            name: "Curated trailing plant",
            type: "Indoor",
            flags: ["trailing": true]
        )
        let climbing = try makePlant(
            name: "Curated climbing plant",
            type: "Indoor",
            flags: ["climbing": true]
        )

        XCTAssertTrue(PlantPlacementCompatibility.supports(trailing, mode: .ceiling))
        XCTAssertTrue(PlantPlacementCompatibility.supports(trailing, mode: .wall))
        XCTAssertTrue(PlantPlacementCompatibility.supports(climbing, mode: .wall))
    }

    private func makePlant(
        name: String,
        type: String,
        description: String = "",
        flags: [String: Bool] = [:]
    ) throws -> Plant {
        var json: [String: Any] = [
            "id": UUID().uuidString,
            "name": name,
            "type": type,
            "imageURLs": [],
            "description": description,
            "modelURL": "\(name).usdz",
            "translations": [:]
        ]

        if !flags.isEmpty {
            json["flags"] = flags
        }

        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        return try JSONDecoder().decode(Plant.self, from: data)
    }
}
