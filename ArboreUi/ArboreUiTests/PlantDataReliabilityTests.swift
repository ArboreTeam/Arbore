import XCTest
@testable import ArboreUi

/// La fiabilité est un vocabulaire fermé et ORDONNÉ, et le seuil exigé dépend
/// de l'axe (#647 §1, #780 §1).
///
/// Avant : `markEvidence` exigeait l'égalité exacte avec `high`, pendant que la
/// base portait `authoritative`, `authoritative-genus` et `derived`. Aucune des
/// trois ne correspondait — les 373 valeurs échouaient donc toutes au contrôle
/// de provenance, et **aucune plante ne pouvait atteindre `.suitable`**.
///
/// Le seuil est désormais fonction de l'axe : un arrosage déduit qui se trompe
/// coûte une plante maussade, une toxicité qui se trompe coûte un animal.
final class PlantDataReliabilityTests: XCTestCase {

    // MARK: - Le vocabulaire, et son ordre

    func testLOrdreEstLowModerateHigh() {
        XCTAssertLessThan(PlantDataReliability.low, .moderate)
        XCTAssertLessThan(PlantDataReliability.moderate, .high)
        XCTAssertGreaterThan(PlantDataReliability.high, .low)
    }

    func testDecodageInsensibleALaCasseEtAuxEspaces() throws {
        XCTAssertEqual(try decode("\"HIGH\""), .high)
        XCTAssertEqual(try decode("\" moderate \""), .moderate)
        XCTAssertEqual(try decode("\"Low\""), .low)
    }

    /// Une valeur non reconnue vaut le PLANCHER, jamais le plafond. C'est ce
    /// qui rend la migration sûre : l'ancien vocabulaire de provenance ne peut
    /// pas se faire passer pour une confiance élevée.
    func testUneValeurNonReconnueVautLePlancher() throws {
        for ancienne in ["authoritative", "authoritative-genus", "derived", "unresolved", "medium"] {
            XCTAssertEqual(
                try decode("\"\(ancienne)\""), .low,
                "« \(ancienne) » ne doit jamais surclasser le plancher"
            )
        }
    }

    /// Ne rien consigner et consigner un mot qu'on ne sait pas lire sont deux
    /// situations différentes : l'absence reste `nil` et fait échouer tout seuil.
    func testLAbsenceDeProvenanceResteNil() throws {
        let json = #"{"sourceName": "ASPCA", "reviewedAt": "2026-11-06"}"#
        let ev = try JSONDecoder().decode(PlantDataEvidence.self, from: Data(json.utf8))
        XCTAssertNil(ev.reliability)
    }

    // MARK: - Le seuil dépend de l'axe

    /// Les axes horticoles se contentent du plancher. C'est le cas de tout le
    /// catalogue réel : `directSunHours`, `drainage` et `wateringIntervalDays`
    /// étaient `derived` sur 335 valeurs, donc `low` après migration.
    func testUnAxeHorticoleSeContenteDuPlancher() throws {
        let plante = try plant(profil: [
            "schemaVersion": 1,
            "environments": fait(["outdoor"], fiabilite: "low"),
            "minimumTemperatureC": fait(-12.0, fiabilite: "low"),
            "directSunHours": intervalle(5, 10, fiabilite: "low"),
        ])
        let resultat = PlantSuitabilityEvaluator(wizard: jardinEnsoleille()).evaluate(plante)
        XCTAssertFalse(
            resultat.missingDataKeys.contains("AR_CATALOG_MISSING_VERIFIED_SOURCE"),
            "une donnée horticole déduite ne doit pas être traitée comme non sourcée"
        )
    }

    /// La toxicité, elle, exige une source nommée — au moins au niveau du genre.
    func testLaToxiciteRefuseLePlancher() throws {
        let resultat = evalueAvecToxicite(fiabilite: "low")
        XCTAssertTrue(
            resultat.missingDataKeys.contains("AR_CATALOG_MISSING_VERIFIED_SOURCE"),
            "une toxicité seulement déduite ne doit pas valoir certification"
        )
    }

    /// Décidé le 2026-11-06 : l'autorité au niveau du GENRE est acceptée.
    /// Avec `high` strict, 13 plantes du catalogue seraient certifiables ;
    /// avec le genre, 38.
    func testLaToxiciteAccepteLAutoriteAuNiveauDuGenre() throws {
        let resultat = evalueAvecToxicite(fiabilite: "moderate")
        XCTAssertFalse(
            resultat.missingDataKeys.contains("AR_CATALOG_MISSING_VERIFIED_SOURCE"),
            "l'ASPCA fiche elle-même certaines espèces au genre : « Mentha sp. »"
        )
        XCTAssertTrue(resultat.positiveReasonKeys.contains("AR_CATALOG_REASON_PET_SAFE"))
    }

    func testLaToxiciteAccepteEvidemmentLEspece() throws {
        let resultat = evalueAvecToxicite(fiabilite: "high")
        XCTAssertFalse(resultat.missingDataKeys.contains("AR_CATALOG_MISSING_VERIFIED_SOURCE"))
    }

    // MARK: - Ce que ça débloque

    /// Une plante à la forme du catalogue RÉEL après migration — `low` sur les
    /// axes horticoles, `moderate` sur la toxicité — doit pouvoir être
    /// certifiée. C'était impossible avant : le seuil unique `high` échouait
    /// sur les 373 valeurs de la base.
    func testUnePlanteDuCatalogueReelPeutEtreCertifiee() throws {
        var wizard = jardinEnsoleille()
        wizard.safety = [SafetyOption.pets.rawValue]
        let plante = try plant(profil: [
            "schemaVersion": 1,
            "environments": fait(["outdoor"], fiabilite: "low"),
            "minimumTemperatureC": fait(-12.0, fiabilite: "low"),
            "directSunHours": intervalle(5, 10, fiabilite: "low"),
            "petToxicity": [
                "value": "safe",
                "evidence": provenance("moderate"),
            ],
        ])

        let resultat = PlantSuitabilityEvaluator(wizard: wizard).evaluate(plante)

        XCTAssertEqual(resultat.level, .suitable)
        XCTAssertTrue(
            resultat.missingDataKeys.isEmpty,
            "restait : \(resultat.missingDataKeys)"
        )
        XCTAssertTrue(resultat.isRecommended)
    }

    // MARK: - Fixtures

    private func decode(_ json: String) throws -> PlantDataReliability {
        try JSONDecoder().decode(PlantDataReliability.self, from: Data(json.utf8))
    }

    private func evalueAvecToxicite(fiabilite: String) -> PlantSuitability {
        var wizard = jardinEnsoleille()
        wizard.safety = [SafetyOption.pets.rawValue]
        let plante = try! plant(profil: [
            "schemaVersion": 1,
            "petToxicity": ["value": "safe", "evidence": provenance(fiabilite)],
        ])
        return PlantSuitabilityEvaluator(wizard: wizard).evaluate(plante)
    }

    private func provenance(_ fiabilite: String) -> [String: Any] {
        [
            "sourceName": "ASPCA Toxic and Non-Toxic Plants",
            "sourceURL": "https://example.test/plant",
            "reviewedAt": "2026-11-06",
            "reliability": fiabilite,
        ]
    }

    private func fait(_ valeur: Any, fiabilite: String) -> [String: Any] {
        ["value": valeur, "evidence": provenance(fiabilite)]
    }

    private func intervalle(_ minimum: Double, _ maximum: Double, fiabilite: String) -> [String: Any] {
        [
            "minimum": minimum,
            "maximum": maximum,
            "unit": "hours/day",
            "evidence": provenance(fiabilite),
        ]
    }

    private func jardinEnsoleille() -> GardenWizardDTO {
        var wizard = GardenWizardDTO(
            style: "",
            spaceType: GardenSpaceType.garden.rawValue,
            exposure: nil,
            maintenance: nil,
            safety: nil,
            soil: nil,
            scanMethod: nil,
            siteProfile: GardenSiteProfileDTO(
                sunlight: GardenSunlightDTO(
                    minimumHours: 6,
                    maximumHours: 8,
                    metadata: GardenValueMetadataDTO(source: .declared, confidence: .high)
                )
            )
        )
        wizard.siteProfile?.climate = GardenClimateDTO(
            historicalMinimumTemperature: GardenTemperatureDTO(
                celsius: -5,
                metadata: GardenValueMetadataDTO(
                    source: .regionalEstimate,
                    confidence: .high,
                    sourceReference: "Climate normals",
                    observedAt: "2026-11-06"
                )
            )
        )
        return wizard
    }

    private func plant(profil: [String: Any]) throws -> Plant {
        let json: [String: Any] = [
            "id": "plant",
            "name": "Test plant",
            "type": "Plant",
            "imageURLs": [],
            "description": "",
            "translations": [:],
            "botanicalProfile": profil,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(Plant.self, from: data)
    }
}
