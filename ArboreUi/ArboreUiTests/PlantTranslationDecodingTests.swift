import XCTest
@testable import ArboreUi

// PlantTranslationDecodingTests.swift — issue #489.
//
// Ces tests couvrent un défaut qui n'a jamais été observé en production, et
// c'est précisément la raison de les écrire : il ne se serait pas manifesté par
// un affichage dégradé, mais par la disparition pure et simple d'une plante du
// catalogue. Un symptôme qu'on attribue à un problème de réseau, pas à une
// donnée.
//
// Le mécanisme. `PlantTranslation` déclare `description` et `plantType` NON
// optionnels. Tant que `translations` était décodé d'un bloc, une seule langue
// partielle faisait échouer le dictionnaire entier, l'erreur remontait
// l'`init(from:)`, et la fiche devenait indécodable. Écrire `translations.de`
// sans `plantType` sur une fiche revenait donc à l'effacer de l'app — dans
// TOUTES les langues, y compris celles qui allaient bien.
//
// Les trois scripts d'écriture du catalogue vérifient la complétude avant
// d'écrire. Mais cette discipline vit dans les scripts, pas dans le modèle : un
// `$set` tapé à la main dans `mongosh` ne la connaît pas. Ces tests déplacent la
// garantie là où elle tient toute seule.

final class PlantTranslationDecodingTests: XCTestCase {

    // MARK: - Fabrique

    /// Décode une plante à partir du seul bloc `translations`, le reste étant
    /// le minimum viable. Le chemin testé est le chemin réel : celui du JSON.
    private func plante(traductions: String) throws -> Plant {
        let json = """
        {
            "id": "test-plant",
            "name": "Plante de test",
            "type": "interieur",
            "imageURLs": [],
            "description": "Description racine",
            "translations": \(traductions)
        }
        """
        return try JSONDecoder().decode(Plant.self, from: Data(json.utf8))
    }

    private let complete = #"{"description": "Une description complète.", "plantType": "Plante d'intérieur"}"#

    // MARK: - L'invariant principal

    /// La régression de #489, dans sa forme la plus directe.
    ///
    /// `de` n'a pas de `plantType`. Avant le garde-fou, ce seul manque faisait
    /// disparaître la plante. Désormais il ne coûte que l'allemand.
    func testUneLangueIncompleteNeFaitPasDisparaitreLaPlante() throws {
        let p = try plante(traductions: #"""
        {
            "fr": \#(complete),
            "en": \#(complete),
            "de": {"description": "Eine Beschreibung ohne Typ."}
        }
        """#)

        XCTAssertEqual(p.name, "Plante de test", "La fiche doit survivre à une traduction fautive")
        XCTAssertNotNil(p.translations["fr"], "Les langues saines ne doivent pas être emportées")
        XCTAssertNotNil(p.translations["en"])
        XCTAssertNil(p.translations["de"], "La langue incomplète est la seule perte")
    }

    /// Le repli est ce qui rend la perte acceptable : sans `de`, l'appelant
    /// trouve `en`. Si ce test échoue, écarter la langue ne suffit plus.
    func testLeRepliSurAnglaisResteDisponibleApresRejet() throws {
        let p = try plante(traductions: #"""
        {
            "en": \#(complete),
            "de": {"plantType": "Zimmerpflanze"}
        }
        """#)

        let vue = p.translations["de"] ?? p.translations["en"]
        XCTAssertEqual(vue?.description, "Une description complète.",
                       "Le lecteur germanophone doit voir une fiche anglaise complète, pas rien")
        XCTAssertEqual(vue?.plantType, "Plante d'intérieur")
    }

    /// Une traduction au texte vide est CONSERVÉE, et ce choix mérite d'être
    /// défendu : l'écarter au profit du repli sur `en` paraissait plus utile au
    /// lecteur, et c'est un piège.
    ///
    /// Un bloc de langue ne porte pas que de la prose. Il porte aussi
    /// `care.difficulty`, dont dépend le filtrage du catalogue. Jeter la langue
    /// parce que sa description est blanche jetterait sa difficulté avec, et
    /// ferait disparaître la plante des filtres pour régler un problème
    /// d'affichage — le bug de #485, réintroduit par le correctif de #489.
    ///
    /// Un décodeur ne détruit pas de la donnée valide pour arranger une vue.
    func testUneTraductionAuTexteVideEstConserveePourSesDonneesStructurees() throws {
        let p = try plante(traductions: #"""
        {
            "en": \#(complete),
            "es": {
                "description": "   ",
                "plantType": "",
                "care": {"difficulty": "Fácil", "weekly": [], "monthly": [], "yearly": [], "extraTips": []}
            }
        }
        """#)

        let es = try XCTUnwrap(p.translations["es"],
                               "La langue doit survivre : sa difficulté est exploitable même sans texte")
        XCTAssertEqual(es.care?.difficulty, "Fácil")
    }

    /// La conséquence directe sur le catalogue : la difficulté reste lisible.
    /// C'est ce test qui relie le garde-fou de #489 au filtre de #485.
    func testUneDifficulteResteLisibleMalgreUnTexteVide() throws {
        let p = try plante(traductions: #"""
        {"fr": {"description": "", "plantType": "", "care": {"difficulty": "Exigeant"}}}
        """#)

        XCTAssertEqual(p.careDifficulty(locale: "fr"), .demanding,
                       "Le filtre du catalogue ne doit rien perdre au passage du décodage par langue")
    }

    // MARK: - Ce qui doit continuer de passer

    /// Le garde-fou ne doit rien coûter au cas nominal : les 124 fiches du
    /// catalogue portent quatre langues complètes.
    func testLesQuatreLanguesCompletesSontToutesRetenues() throws {
        let p = try plante(traductions: #"""
        {
            "fr": \#(complete),
            "en": \#(complete),
            "es": \#(complete),
            "de": \#(complete)
        }
        """#)

        XCTAssertEqual(Set(p.translations.keys), ["fr", "en", "es", "de"])
    }

    /// Les sections optionnelles vides ne sont pas un défaut : une fiche
    /// succincte reste une fiche. Le garde-fou ne juge que `description` et
    /// `plantType`.
    func testUneTraductionSansSectionsFacultativesEstRetenue() throws {
        let p = try plante(traductions: #"""
        {"fr": \#(complete)}
        """#)

        let t = try XCTUnwrap(p.translations["fr"])
        XCTAssertEqual(t.description, "Une description complète.")
        XCTAssertNil(t.sun, "Les sections facultatives absentes restent absentes, sans rejet")
        XCTAssertNil(t.care)
    }

    /// Les sections riches doivent continuer de se décoder normalement — le
    /// passage par un conteneur dynamique ne doit rien perdre en chemin.
    func testLesSectionsRichesSurviventAuDecodageParLangue() throws {
        let p = try plante(traductions: #"""
        {
            "fr": {
                "description": "Une description complète.",
                "plantType": "Plante d'intérieur",
                "care": {"difficulty": "Facile", "weekly": ["Arroser"], "monthly": [], "yearly": [], "extraTips": []},
                "sun": {"lightType": "Lumière vive indirecte", "tips": ["Tourner le pot"]}
            }
        }
        """#)

        let t = try XCTUnwrap(p.translations["fr"])
        XCTAssertEqual(t.care?.difficulty, "Facile")
        XCTAssertEqual(t.care?.weekly, ["Arroser"])
        XCTAssertEqual(t.sun?.lightType, "Lumière vive indirecte")
        XCTAssertEqual(t.sun?.tips, ["Tourner le pot"])
    }

    // MARK: - Formes dégénérées du bloc lui-même

    /// `translations` absent : cas des fiches legacy.
    func testUnBlocAbsentDonneUnDictionnaireVide() throws {
        let json = """
        {"id": "x", "name": "Sans traduction", "type": "interieur", "imageURLs": [], "description": "d"}
        """
        let p = try JSONDecoder().decode(Plant.self, from: Data(json.utf8))
        XCTAssertTrue(p.translations.isEmpty)
    }

    /// `translations` du mauvais type ne doit pas non plus emporter la fiche.
    func testUnBlocMalFormeNEmportePasLaFiche() throws {
        let p = try plante(traductions: #""une chaîne au lieu d'un objet""#)
        XCTAssertEqual(p.name, "Plante de test")
        XCTAssertTrue(p.translations.isEmpty)
    }

    /// Toutes les langues fautives : la plante reste au catalogue, sans
    /// traduction. C'est le pire cas, et il reste préférable à sa disparition.
    func testToutesLesLanguesFautivesLaissentLaPlanteAuCatalogue() throws {
        let p = try plante(traductions: #"""
        {
            "fr": {"description": "Sans type."},
            "en": {"plantType": "Sans description."}
        }
        """#)

        XCTAssertEqual(p.name, "Plante de test")
        XCTAssertTrue(p.translations.isEmpty)
    }
}
