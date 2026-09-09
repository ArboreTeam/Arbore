import XCTest
@testable import ArboreUi

// PlantCareDifficultyTests.swift — issue #485.
//
// Le bug couvert ici était invisible et total : le filtre par difficulté du
// catalogue lisait `care.difficulty`, un champ que le backend ne sérialisait
// pas. La valeur étant toujours vide, aucun mot-clé ne correspondait jamais, et
// CHAQUE plante tombait dans un `return false`. Sélectionner une difficulté
// vidait la liste — mesuré sur les 124 fiches de production, dont 0 possédait
// ce champ.
//
// La leçon qui structure ces tests : un filtre doit distinguer « je ne sais
// pas » de « ne correspond pas ». Confondre les deux ne masque pas quelques
// résultats, ça masque tout. C'est cet invariant qui est vérifié en premier.
//
// Les plantes sont construites par décodage JSON plutôt que par init direct :
// c'est le chemin réel, et il couvre au passage la tolérance du modèle aux
// champs absents.

final class PlantCareDifficultyTests: XCTestCase {

    // MARK: - Fabrique

    /// Construit une plante depuis un fragment JSON, en complétant le minimum requis.
    private func makePlant(careDifficulty: String? = nil,
                           easyCare: Bool? = nil) throws -> Plant {
        let care: String
        if let d = careDifficulty {
            care = #"{"difficulty": "\#(d)", "weekly": [], "monthly": [], "yearly": [], "extraTips": []}"#
        } else {
            care = #"{"weekly": [], "monthly": [], "yearly": [], "extraTips": []}"#
        }

        var flags = ""
        if let easy = easyCare {
            flags = #""flags": {"toxicToPets": false, "toxicToChildren": false, "easyCare": \#(easy), "shadeTolerant": false, "fullSunTolerant": false, "droughtTolerant": false, "humidityLoving": false, "flowering": false, "climbing": false, "trailing": false, "compact": false, "airPurifying": false},"#
        }

        let json = #"""
        {
            "id": "test-plant",
            "name": "Plante de test",
            "type": "interieur",
            "imageURLs": [],
            "description": "",
            "modelURL": null,
            \#(flags)
            "translations": {
                "fr": {
                    "description": "",
                    "plantType": "",
                    "care": \#(care)
                }
            }
        }
        """#

        return try JSONDecoder().decode(Plant.self, from: Data(json.utf8))
    }

    // MARK: - L'invariant central

    /// Sans difficulté ni flags, le niveau est INCONNU — et surtout pas « exigeant ».
    ///
    /// C'est la régression de #485. 26 des 124 fiches sont dans ce cas ; les
    /// traiter comme non conformes revenait à les faire disparaître.
    func testDonneeAbsenteDonneInconnuEtNonUnNiveauParDefaut() throws {
        let plant = try makePlant()
        XCTAssertNil(plant.careDifficulty(),
                     "Une plante sans donnée d'entretien doit rester inconnue, jamais classée par défaut")
    }

    /// Le filtre du catalogue ne masque pas ce qu'il ne sait pas juger.
    func testFiltreNExclutPasUnePlanteDeDifficulteInconnue() throws {
        let plant = try makePlant()
        let filters = PlantFilters(lightType: nil, waterFrequency: nil, difficulty: "Facile")

        XCTAssertTrue(filters.matches(plant: plant, locale: "fr"),
                      "Une difficulté inconnue ne doit pas exclure la plante — c'est le bug de #485")
    }

    // MARK: - Résolution depuis care.difficulty

    func testDifficulteExpliciteEstPrioritaireSurLesFlags() throws {
        // `easyCare: true` dit « facile », le texte dit « exigeant ».
        // Le texte, plus précis, doit l'emporter.
        let plant = try makePlant(careDifficulty: "Exigeant", easyCare: true)
        XCTAssertEqual(plant.careDifficulty(), .demanding)
    }

    func testTroisNiveauxReconnusEnFrancais() throws {
        XCTAssertEqual(try makePlant(careDifficulty: "Facile").careDifficulty(), .easy)
        XCTAssertEqual(try makePlant(careDifficulty: "Intermédiaire").careDifficulty(), .moderate)
        XCTAssertEqual(try makePlant(careDifficulty: "Exigeant").careDifficulty(), .demanding)
    }

    func testNiveauxReconnusDansLesQuatreLangues() throws {
        XCTAssertEqual(try makePlant(careDifficulty: "Easy").careDifficulty(), .easy)
        XCTAssertEqual(try makePlant(careDifficulty: "Einfach").careDifficulty(), .easy)
        XCTAssertEqual(try makePlant(careDifficulty: "Fácil").careDifficulty(), .easy)
        XCTAssertEqual(try makePlant(careDifficulty: "Anspruchsvoll").careDifficulty(), .demanding)
    }

    /// « Pas facile » contient « facile » : l'ordre d'évaluation doit protéger
    /// contre cette lecture naïve.
    func testExigeantEstTesteAvantFacile() throws {
        XCTAssertEqual(try makePlant(careDifficulty: "Plutôt difficile").careDifficulty(), .demanding)
    }

    // MARK: - Repli sur les flags

    func testReplieSurEasyCareQuandLaDifficulteManque() throws {
        XCTAssertEqual(try makePlant(easyCare: true).careDifficulty(), .easy)
        XCTAssertEqual(try makePlant(easyCare: false).careDifficulty(), .demanding)
    }

    /// Le repli est binaire : il ne peut pas produire « intermédiaire ».
    /// Ce test documente la limite plutôt que de la laisser surprendre.
    func testLeRepliNeProduitJamaisIntermediaire() throws {
        XCTAssertNotEqual(try makePlant(easyCare: true).careDifficulty(), .moderate)
        XCTAssertNotEqual(try makePlant(easyCare: false).careDifficulty(), .moderate)
    }

    // MARK: - Le filtre discrimine bien quand la donnée existe

    func testFiltreExclutUnNiveauQuiNeCorrespondPas() throws {
        let exigeante = try makePlant(careDifficulty: "Exigeant")
        let filters = PlantFilters(lightType: nil, waterFrequency: nil, difficulty: "Facile")

        XCTAssertFalse(filters.matches(plant: exigeante, locale: "fr"),
                       "Une plante exigeante doit être exclue d'un filtre « Facile »")
    }

    func testFiltreConserveUnNiveauQuiCorrespond() throws {
        let facile = try makePlant(careDifficulty: "Facile")
        let filters = PlantFilters(lightType: nil, waterFrequency: nil, difficulty: "Facile")

        XCTAssertTrue(filters.matches(plant: facile, locale: "fr"))
    }

    // MARK: - Les options proposées suivent les données

    /// Avec les seules données d'aujourd'hui — `flags.easyCare`, binaire —
    /// « Intermédiaire » ne doit pas être proposé.
    ///
    /// Ce n'est pas cosmétique : ce choix ne renverrait ni les faciles ni les
    /// exigeantes, mais exactement les fiches SANS donnée. Un sous-ensemble
    /// arbitraire présenté comme une réponse.
    func testIntermediaireNEstPasProposeSansDonneeDeDifficulte() throws {
        let catalogue = [
            try makePlant(easyCare: true),
            try makePlant(easyCare: false),
            try makePlant()                     // inconnue
        ]
        let vue = FilterView(filters: .constant(PlantFilters()), plants: catalogue)

        XCTAssertEqual(vue.difficultyOptions.count, 2,
                       "Sans care.difficulty, seuls deux niveaux sont proposables")
    }

    /// Dès qu'une fiche porte un niveau intermédiaire, l'option réapparaît —
    /// sans changement de code.
    func testIntermediaireReapparaitQuandLaDonneeExiste() throws {
        let catalogue = [
            try makePlant(easyCare: true),
            try makePlant(careDifficulty: "Intermédiaire")
        ]
        let vue = FilterView(filters: .constant(PlantFilters()), plants: catalogue)

        XCTAssertEqual(vue.difficultyOptions.count, 3)
    }

    /// Un catalogue vide ne doit pas faire disparaître le filtre entier.
    func testCatalogueVideProposeQuandMemeLesNiveauxDeBase() {
        let vue = FilterView(filters: .constant(PlantFilters()), plants: [])
        XCTAssertEqual(vue.difficultyOptions.count, 2)
    }

    /// Sans critère sélectionné, le filtre laisse tout passer.
    func testAucunCritereNExcluRien() throws {
        let plant = try makePlant(careDifficulty: "Exigeant")
        let filters = PlantFilters(lightType: nil, waterFrequency: nil, difficulty: nil)

        XCTAssertTrue(filters.matches(plant: plant, locale: "fr"))
    }
}

// PlantToxicityTests — issue #488.
//
// Le filtre de sécurité laissait passer 25 des 26 fiches sans `flags` : il
// cherchait le mot « toxique » dans une prose écrite pour décrire l'apparence
// et l'entretien. Rien n'oblige la description d'un rhododendron à mentionner
// ses grayanotoxines — et de fait, elle ne les mentionne pas.
//
// L'invariant central, et il est l'INVERSE de celui du filtre de difficulté :
// ici, une toxicité non établie doit EXCLURE. Le coût des deux erreurs n'est
// pas le même.

final class PlantToxicityTests: XCTestCase {

    private func makePlant(petToxicity: String? = nil,
                           toxicToPetsFlag: Bool? = nil) throws -> Plant {
        var profile = ""
        if let t = petToxicity {
            profile = #""botanicalProfile": {"petToxicity": {"value": "\#(t)"}},"#
        }
        var flags = ""
        if let f = toxicToPetsFlag {
            flags = #""flags": {"toxicToPets": \#(f), "toxicToChildren": \#(f), "easyCare": true, "shadeTolerant": false, "fullSunTolerant": false, "droughtTolerant": false, "humidityLoving": false, "flowering": false, "climbing": false, "trailing": false, "compact": false, "airPurifying": false},"#
        }
        let json = #"""
        {
            "id": "t", "name": "Test", "type": "x", "imageURLs": [],
            "description": "", "modelURL": null,
            \#(profile)\#(flags)
            "translations": { "fr": { "description": "", "plantType": "" } }
        }
        """#
        return try JSONDecoder().decode(Plant.self, from: Data(json.utf8))
    }

    // MARK: - L'invariant central

    /// Sans donnée, la toxicité n'est pas établie — et surtout pas « sûre ».
    func testToxiciteNonEtablieQuandRienNEstRenseigne() throws {
        XCTAssertNil(try makePlant().petToxicity())
    }

    /// C'est la régression de #488 : 25 fiches passaient le filtre faute de
    /// donnée, pas parce qu'elles étaient inoffensives.
    func testUneToxiciteInconnueEstExclueDUnFiltreSurete() throws {
        let plant = try makePlant()
        let wizard = GardenWizardDTO(style: "", spaceType: "", safety: ["Éviter les plantes toxiques pour les animaux"])
        XCTAssertFalse(WizardPlantFilter(wizard: wizard).matches(plant: plant, locale: "fr"),
                       "Une toxicité non établie doit exclure quand l'utilisateur demande des plantes sûres")
    }

    // MARK: - Résolution

    func testLeProfilBotaniquePrimeSurLesFlags() throws {
        // Le flag dit « sûre », l'ASPCA dit « toxique ». L'autorité l'emporte.
        let p = try makePlant(petToxicity: "toxic to dogs, cats, horses", toxicToPetsFlag: false)
        XCTAssertEqual(p.petToxicity(), .toxic)
    }

    /// « non-toxic » contient « toxic » : l'ordre d'évaluation doit protéger
    /// contre cette lecture naïve.
    func testNonToxiqueNEstPasLuCommeToxique() throws {
        XCTAssertEqual(try makePlant(petToxicity: "non-toxic").petToxicity(), .safe)
    }

    func testReplieSurLesFlagsQuandLeProfilManque() throws {
        XCTAssertEqual(try makePlant(toxicToPetsFlag: true).petToxicity(), .toxic)
        XCTAssertEqual(try makePlant(toxicToPetsFlag: false).petToxicity(), .safe)
    }

    // MARK: - Le filtre

    func testUnePlanteToxiqueEstExclue() throws {
        let p = try makePlant(petToxicity: "toxic to dogs, cats, horses")
        let wizard = GardenWizardDTO(style: "", spaceType: "", safety: ["Éviter les plantes toxiques pour les animaux"])
        XCTAssertFalse(WizardPlantFilter(wizard: wizard).matches(plant: p, locale: "fr"))
    }

    func testUnePlanteSureEstConservee() throws {
        let p = try makePlant(petToxicity: "non-toxic")
        let wizard = GardenWizardDTO(style: "", spaceType: "", safety: ["Éviter les plantes toxiques pour les animaux"])
        XCTAssertTrue(WizardPlantFilter(wizard: wizard).matches(plant: p, locale: "fr"))
    }

    /// Sans contrainte de sécurité demandée, rien n'est exclu — même inconnu.
    func testSansDemandeDeSureteRienNEstExclu() throws {
        let p = try makePlant()
        XCTAssertTrue(WizardPlantFilter(wizard: GardenWizardDTO(style: "", spaceType: "")).matches(plant: p, locale: "fr"))
    }
}
