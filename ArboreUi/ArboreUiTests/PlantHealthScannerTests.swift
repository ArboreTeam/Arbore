//
//  PlantHealthScannerTests.swift
//  ArboreUiTests
//
//  Couvre la logique pure du scan de santé (chantier juillet) : erreurs,
//  validateur de qualité d'image, analyse colorimétrique (images synthétiques),
//  et décodage de la réponse de diagnostic (contrat backend #312).
//

import XCTest
import CoreImage
@testable import ArboreUi

final class PlantHealthScannerTests: XCTestCase {

    private func solidImage(
        red: CGFloat, green: CGFloat, blue: CGFloat, side: CGFloat = 240
    ) -> CIImage {
        CIImage(color: CIColor(red: red, green: green, blue: blue))
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
    }

    // MARK: - PlantScanError

    func testScanError_descriptionsAreNonEmpty() {
        let errors: [PlantScanError] = [
            .lowBrightness(luminance: 0.05),
            .blurryImage(variance: 12),
            .noPlantDetected(bestLabel: "wall", bestConfidence: 0.2),
            .cameraUnavailable,
            .analysisTimeout,
            .geminiError("boom")
        ]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error) sans description")
            XCTAssertFalse(error.systemImage.isEmpty, "\(error) sans icône")
        }
    }

    func testScanError_geminiErrorEmbedsMessage() {
        let error = PlantScanError.geminiError("quota dépassé")
        XCTAssertTrue(error.errorDescription?.contains("quota dépassé") ?? false)
    }

    func testScanError_iconsAreDistinctPerCase() {
        XCTAssertEqual(PlantScanError.cameraUnavailable.systemImage, "camera.fill")
        XCTAssertEqual(PlantScanError.analysisTimeout.systemImage, "clock.fill")
        XCTAssertEqual(PlantScanError.lowBrightness(luminance: 0).systemImage, "sun.min.fill")
    }

    // MARK: - ImageQualityValidator

    func testValidator_rejectsDarkImageAsLowBrightness() {
        let dark = solidImage(red: 0, green: 0, blue: 0)
        switch ImageQualityValidator.validate(dark) {
        case .failure(.lowBrightness):
            break // attendu
        default:
            XCTFail("une image noire devrait échouer en lowBrightness")
        }
    }

    func testValidator_brightImagePassesBrightnessCheck() {
        // Une image lumineuse ne doit jamais être rejetée pour manque de luminosité.
        // (Le seuil de netteté dépend du contenu de l'image — artefacts de bord
        // CoreImage inclus — et n'est donc pas assertable de façon déterministe ici.)
        let bright = solidImage(red: 0.6, green: 0.6, blue: 0.6)
        if case .failure(.lowBrightness) = ImageQualityValidator.validate(bright) {
            XCTFail("une image lumineuse ne devrait pas échouer en lowBrightness")
        }
    }

    // MARK: - ColorimetricAnalyzer

    func testColorimetry_greenImageIsHealthy() {
        let green = solidImage(red: 0.1, green: 0.7, blue: 0.1)
        let result = ColorimetricAnalyzer.analyze(green)
        XCTAssertGreaterThan(result.greenRatio, 0.85, "un feuillage vert plein → ratio vert élevé")
        XCTAssertGreaterThan(result.healthScore, 0.85)
        XCTAssertLessThan(result.brownRatio, 0.1)
    }

    func testColorimetry_brownImageIsNotGreen() {
        let brown = solidImage(red: 0.45, green: 0.28, blue: 0.12)
        let result = ColorimetricAnalyzer.analyze(brown)
        XCTAssertGreaterThan(result.brownRatio, 0.5, "une image brune → ratio brun dominant")
        XCTAssertLessThan(result.greenRatio, 0.2)
    }

    // MARK: - Décodage du contrat de diagnostic (backend #312)

    func testDiagnoseResponse_decodesNormalizedShape() throws {
        let json = """
        {
          "species": "Rosa",
          "overallHealth": 0.9,
          "diseases": [{ "name": "Oïdium", "severity": 0.3, "confidence": 0.8 }],
          "recommendations": ["Arroser le matin"],
          "isUncertain": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(
            GeminiDiagnosticService.GeminiDiagnosticResponse.self,
            from: json
        )
        XCTAssertEqual(decoded.species, "Rosa")
        XCTAssertEqual(decoded.overallHealth, 0.9)
        XCTAssertEqual(decoded.diseases?.count, 1)
        XCTAssertEqual(decoded.diseases?.first?.name, "Oïdium")
        XCTAssertEqual(decoded.isUncertain, false)
        XCTAssertEqual(decoded.recommendations, ["Arroser le matin"])
    }

    func testDiagnoseResponse_toleratesMissingOptionalFields() throws {
        // Le backend garantit des tableaux non-null, mais le client doit tolérer
        // l'absence des champs optionnels (species/overallHealth/etc.).
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(
            GeminiDiagnosticService.GeminiDiagnosticResponse.self,
            from: json
        )
        XCTAssertNil(decoded.species)
        XCTAssertNil(decoded.overallHealth)
        XCTAssertNil(decoded.diseases)
    }

    func testDiagnoseResponse_diseaseWithoutNameFailsDecoding() {
        // `name` est non-optionnel côté client → le backend ne doit jamais émettre
        // une maladie sans nom (garanti par la normalisation #312).
        let json = """
        { "diseases": [{ "severity": 0.5 }] }
        """.data(using: .utf8)!
        XCTAssertThrowsError(
            try JSONDecoder().decode(GeminiDiagnosticService.GeminiDiagnosticResponse.self, from: json)
        )
    }
}
