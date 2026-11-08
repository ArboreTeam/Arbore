//
//  PlantPlacementCompatibilityTests.swift
//  ArboreUiTests
//

import XCTest
@testable import ArboreUi

// Réécrite avec #792.
//
// Les quatre tests précédents affirmaient le défaut comme exigence. L'un
// s'appelait `test_namedTrailingCatalogPlants_supportCeilingMode` et vérifiait
// que « Ceropegia Woodii », « Hoya Bella », « Hoya Linearis »,
// « Philodendron scandens » et « Pothos pictum » supportaient le plafond — par
// leur NOM. Un autre affirmait qu'un « Ficus lyrata » ne le supportait pas, et
// qu'un « Lierre » tenait au mur. La suite de tests inscrivait donc comme
// contrat une taxonomie botanique écrite en dur dans du code d'interface, et un
// appariement sans frontière de mot.
//
// Ce qui est vérifié désormais : la capacité de pose vient du champ clos
// `botanicalProfile.placement`, et à défaut du repli par drapeaux dont seul le
// `true` informe.

final class PlantPlacementCompatibilityTests: XCTestCase {

    func test_availablePlacementModes_areFloorWallCeilingOnly() {
        XCTAssertEqual(ARPlacementMode.allCases, [.floor, .wall, .ceiling])
        XCTAssertTrue(ARPlacementMode.floor.acceptedSurfaceTypes.contains(.shelf))
        XCTAssertTrue(ARPlacementMode.floor.acceptedSurfaceTypes.contains(.table))
        XCTAssertTrue(ARPlacementMode.floor.acceptedSurfaceTypes.contains(.windowsill))
    }

    // MARK: - Le champ clos décide

    func testLeChampPlacementDecideDesModesAdmis() throws {
        let suspendue = try plante(placement: ["floor", "ceiling"])
        let murale = try plante(placement: ["wall"])
        let auSol = try plante(placement: ["floor"])

        XCTAssertEqual(PlantPlacementCompatibility.supportedModes(for: suspendue), [.floor, .ceiling])
        XCTAssertEqual(PlantPlacementCompatibility.supportedModes(for: murale), [.floor, .wall])
        XCTAssertEqual(PlantPlacementCompatibility.supportedModes(for: auSol), [.floor])
    }

    /// Le sol est toujours admis : poser une plante au sol ne demande aucune
    /// capacité particulière, et c'est le seul mode dont l'absence de donnée
    /// ne peut pas produire un geste impossible.
    func testLeSolEstToujoursAdmisMemeQuandLaListeNeLeNommePas() throws {
        let murale = try plante(placement: ["wall"])
        XCTAssertTrue(PlantPlacementCompatibility.supports(murale, mode: .floor))
    }

    /// **Une liste présente qui ne nomme pas un mode est une affirmation**, pas
    /// un silence : elle refuse, et aucun drapeau ne vient la contredire.
    func testUneListePresenteRefuseCeQuElleNeNommePasMemeContreLesDrapeaux() throws {
        let auSol = try plante(placement: ["floor"], drapeaux: ["climbing": true, "trailing": true])

        XCTAssertEqual(PlantPlacementCompatibility.supportedModes(for: auSol), [.floor])
        XCTAssertFalse(PlantPlacementCompatibility.isWallCapable(auSol),
                       "le champ stocké prime sur le drapeau, toujours")
        XCTAssertFalse(PlantPlacementCompatibility.isHangingCapable(auSol))
    }

    /// Une liste présente et VIDE affirme qu'aucun mode spécial ne s'applique.
    func testUneListePresenteEtVideNOuvreAucunMode() throws {
        let aucun = try plante(placement: [], drapeaux: ["trailing": true])
        XCTAssertEqual(PlantPlacementCompatibility.supportedModes(for: aucun), [.floor])
    }

    /// Une valeur hors vocabulaire est écartée et ne devient pas une capacité.
    func testUneValeurDePlacementHorsVocabulaireNOuvreAucunMode() throws {
        let futur = try plante(placement: ["balcony", "ceiling"])

        XCTAssertEqual(PlantPlacementCompatibility.supportedModes(for: futur), [.floor, .ceiling],
                       "« balcony » est écarté, « ceiling » est retenu")
        XCTAssertEqual(futur.botanicalProfile?.placement?.rejected, ["balcony"])
    }

    // MARK: - Le repli par drapeaux, sans le champ

    func testSansChampLesDrapeauxServentDeRepliEtSeulLeurTrueInforme() throws {
        let retombante = try plante(drapeaux: ["trailing": true])
        let grimpante = try plante(drapeaux: ["climbing": true])

        XCTAssertEqual(PlantPlacementCompatibility.supportedModes(for: retombante),
                       [.floor, .wall, .ceiling])
        XCTAssertEqual(PlantPlacementCompatibility.supportedModes(for: grimpante),
                       [.floor, .wall],
                       "grimper tient au mur, pas au plafond")
    }

    /// Sans champ et sans drapeau levé, seul le sol est admis — et c'est le
    /// bon défaut : il ne propose jamais un geste impossible.
    func testSansChampNiDrapeauSeulLeSolEstAdmis() throws {
        let nue = try plante()
        XCTAssertEqual(PlantPlacementCompatibility.supportedModes(for: nue), [.floor])
    }

    /// Un drapeau BAISSÉ ne prouve rien, et surtout ne fait plus retomber sur
    /// des mots-clés.
    func testUnDrapeauBaisseNeFaitPlusRetomberSurLeNom() throws {
        let pothos = try plante(
            nom: "Pothos pictus Hoya Ceropegia woodii lierre",
            type: "Liane retombante grimpante suspendue",
            drapeaux: ["climbing": false, "trailing": false]
        )

        XCTAssertEqual(PlantPlacementCompatibility.supportedModes(for: pothos), [.floor],
                       "cinq mots-clés de l'ancienne liste dans le nom, et plus aucun effet")
    }

    // MARK: - Fabrique

    private func plante(
        nom: String = "Plante de test",
        type: String = "Plant",
        placement: [String]? = nil,
        drapeaux: [String: Bool] = [:]
    ) throws -> Plant {
        var json: [String: Any] = [
            "id": UUID().uuidString,
            "name": nom,
            "type": type,
            "imageURLs": [],
            "description": "",
            "modelURL": "test.usdz",
            "translations": [:]
        ]

        if let placement {
            json["botanicalProfile"] = [
                "schemaVersion": 1,
                "placement": [
                    "value": placement,
                    "evidence": [
                        "sourceName": "mesure d'atelier",
                        "sourceURL": "https://example.test/plant",
                        "reviewedAt": "2026-11-08",
                        "reliability": "high"
                    ]
                ]
            ]
        }

        if !drapeaux.isEmpty {
            var complets: [String: Bool] = [
                "toxicToPets": false, "toxicToChildren": false, "easyCare": false,
                "shadeTolerant": false, "fullSunTolerant": false, "droughtTolerant": false,
                "humidityLoving": false, "flowering": false, "climbing": false,
                "trailing": false, "compact": false, "airPurifying": false
            ]
            for (cle, valeur) in drapeaux { complets[cle] = valeur }
            json["flags"] = complets
        }

        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        return try JSONDecoder().decode(Plant.self, from: data)
    }
}
