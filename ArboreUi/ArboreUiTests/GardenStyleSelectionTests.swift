import XCTest
@testable import ArboreUi

// GardenStyleSelectionTests — sélection multiple des styles du wizard.
//
// L'étape style acceptait un seul choix, qu'on ne pouvait pas retirer. Elle
// accepte maintenant plusieurs styles et une carte choisie se désélectionne.
// Le backend ne stocke toujours qu'une chaîne `style` : ces tests vérifient
// la forme jointe envoyée et que le filtre la lit comme une union.

final class GardenStyleSelectionTests: XCTestCase {

    // MARK: - Sélection

    func testUneCarteChoisieSeDeselectionne() {
        let state = GardenWizardState()
        state.toggleStyle(.zen)
        state.toggleStyle(.zen)
        XCTAssertTrue(state.styles.isEmpty)
    }

    func testPlusieursStylesSeCumulent() {
        let state = GardenWizardState()
        state.toggleStyle(.zen)
        state.toggleStyle(.modern)
        XCTAssertEqual(state.styles, [.zen, .modern])
    }

    /// « Sans préférence » ne peut pas cohabiter avec un style précis.
    func testSansPreferenceEstExclusif() {
        let state = GardenWizardState()
        state.toggleStyle(.zen)
        state.toggleStyle(.modern)
        state.toggleStyle(.noPreference)
        XCTAssertEqual(state.styles, [.noPreference])

        state.toggleStyle(.floral)
        XCTAssertEqual(state.styles, [.floral])
    }

    // MARK: - Valeur envoyée

    /// L'ordre suit les cartes, pas l'ordre des taps : la valeur stockée
    /// reste stable pour une même sélection.
    func testLaValeurJointSuitLOrdreDesCartes() {
        let state = GardenWizardState()
        state.toggleStyle(.mediterranean)
        state.toggleStyle(.modern)
        XCTAssertEqual(state.styleValue, "Moderne & minimaliste, Méditerranéen")
    }

    func testAucunStyleDonneUneValeurVide() {
        XCTAssertEqual(GardenWizardState().styleValue, "")
    }

    // MARK: - Filtre

    /// Avec deux styles, une plante qui n'en sert qu'un seul passe le filtre.
    func testLeFiltreRetientUnePlanteDeNImporteQuelStyleChoisi() throws {
        let wizard = GardenWizardDTO(style: "Moderne & minimaliste, Zen & japonais", spaceType: "")
        let filter = WizardPlantFilter(wizard: wizard)

        XCTAssertTrue(filter.matches(plant: try makePlant(name: "Bambou"), locale: "fr"))
        XCTAssertTrue(filter.matches(plant: try makePlant(name: "Sansevieria"), locale: "fr"))
        XCTAssertFalse(filter.matches(plant: try makePlant(name: "Tulipe"), locale: "fr"))
    }

    // MARK: - Fabrique

    private func makePlant(name: String) throws -> Plant {
        let json = #"""
        {
            "id": "test-plant",
            "name": "\#(name)",
            "type": "exterieur",
            "imageURLs": [],
            "description": "",
            "modelURL": null,
            "translations": {
                "fr": {
                    "description": "",
                    "plantType": "",
                    "care": {"weekly": [], "monthly": [], "yearly": [], "extraTips": []}
                }
            }
        }
        """#
        return try JSONDecoder().decode(Plant.self, from: Data(json.utf8))
    }
}
