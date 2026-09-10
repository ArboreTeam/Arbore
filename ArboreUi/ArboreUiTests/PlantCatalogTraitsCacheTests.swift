import XCTest
@testable import ArboreUi

// PlantCatalogTraitsCacheTests — issue #499.
//
// Le premier événement Sentry réel a mesuré un gel de 2 000 ms à la validation
// du questionnaire, sur un iPhone 17 Pro. Coupable : `PlantCatalogTraits.snapshot`,
// qui relançait chaque famille d'inférence à chaque appel — `kinds` seul balaie
// 36 motifs dans la prose des quatre langues — pour les 124 plantes du catalogue,
// sur le fil principal.
//
// Le texte normalisé était déjà mis en cache ; le snapshot qui en dérive ne
// l'était pas. Ces tests gardent la mémoïsation qui corrige ça, et la clé qui
// la rend sûre.

final class PlantCatalogTraitsCacheTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PlantCatalogTraits.clearCaches()
    }

    override func tearDown() {
        // Les caches sont globaux au processus : ne pas les rendre ne
        // laisserait aux tests suivants que des traits fabriqués ici.
        PlantCatalogTraits.clearCaches()
        super.tearDown()
    }

    // MARK: - La mémoïsation existe

    /// Le garde-fou de #499. Il ne mesure pas une durée absolue — elle dépend
    /// de la machine — mais le rapport entre deux passes sur le même matériel :
    /// retirer la mémoïsation les ramène au même ordre de grandeur et fait
    /// échouer le test.
    func testRelireLesMemesPlantesEstUnOrdreDeGrandeurPlusRapide() throws {
        // Charge volontairement petite : une inférence complète coûte ~15 ms
        // par plante, ce qui suffit à creuser un écart net sans facturer des
        // secondes à la CI. C'est le même ordre de grandeur que l'événement
        // réel — 124 plantes, 2 000 ms.
        let plantes = try (0..<6).map { try plante(id: "cache-\($0)") }
        let passes = 2

        let calcule = duree {
            for _ in 0..<passes {
                PlantCatalogTraits.clearCaches()
                for p in plantes { _ = PlantCatalogTraits.snapshot(for: p) }
            }
        }

        for p in plantes { _ = PlantCatalogTraits.snapshot(for: p) }   // préchauffage
        let memoise = duree {
            for _ in 0..<passes {
                for p in plantes { _ = PlantCatalogTraits.snapshot(for: p) }
            }
        }

        print("[#499] \(plantes.count) plantes × \(passes) passes — "
              + "calculées \(Int(calcule * 1000)) ms, mémoïsées \(Int(memoise * 1000)) ms")

        XCTAssertLessThan(
            memoise * 5, calcule,
            "Les traits doivent être servis depuis le cache, pas recalculés : "
            + "\(Int(calcule * 1000)) ms recalculés contre \(Int(memoise * 1000)) ms mémoïsés"
        )
    }

    /// Ce que la mémoïsation ne doit surtout pas changer : le résultat.
    func testLeResultatMemoiseEstIdentiqueAuResultatCalcule() throws {
        let p = try plante(id: "identique", type: "Arbre d'ornement")

        let calcule = PlantCatalogTraits.snapshot(for: p)
        let relu = PlantCatalogTraits.snapshot(for: p)

        XCTAssertEqual(relu.searchableText, calcule.searchableText)
        XCTAssertEqual(relu.kinds, calcule.kinds)
        XCTAssertEqual(relu.size, calcule.size)
        XCTAssertEqual(relu.goals, calcule.goals)
        XCTAssertEqual(relu.habits, calcule.habits)
    }

    // MARK: - La clé observe ce dont le résultat dépend

    /// L'identifiant seul serait une clé fausse : le snapshot dépend aussi des
    /// drapeaux, et deux charges différentes peuvent porter le même id — une
    /// actualisation du catalogue après édition côté serveur, ou deux fixtures
    /// de test. Sans ce garde-fou, la seconde plante hériterait des traits de
    /// la première, silencieusement.
    func testDeuxPlantesDeMemeIdMaisDeDrapeauxDifferentsNePartagentPasLeursTraits() throws {
        let ombre = try plante(id: "meme-id", shadeTolerant: true)
        let soleil = try plante(id: "meme-id", fullSunTolerant: true)

        let traitsOmbre = PlantCatalogTraits.snapshot(for: ombre)
        let traitsSoleil = PlantCatalogTraits.snapshot(for: soleil)

        XCTAssertTrue(traitsOmbre.sunlightTolerances.shade)
        XCTAssertFalse(traitsOmbre.sunlightTolerances.fullSun)
        XCTAssertFalse(traitsSoleil.sunlightTolerances.shade)
        XCTAssertTrue(traitsSoleil.sunlightTolerances.fullSun)
    }

    /// Une plante sans drapeaux ne doit pas hériter de ceux d'une homonyme.
    func testUnePlanteSansDrapeauxADroitASaPropreEntree() throws {
        let avec = try plante(id: "legacy", easyCare: true)
        let sans = try plante(id: "legacy", includeFlags: false)

        XCTAssertTrue(PlantCatalogTraits.snapshot(for: avec).isEasyCare)
        XCTAssertNotEqual(
            PlantCatalogTraits.snapshot(for: sans).isEasyCare,
            true,
            "Sans drapeau, la facilité d'entretien se déduit de la prose, pas de l'homonyme"
        )
    }

    // MARK: - Outils

    private func duree(_ bloc: () -> Void) -> TimeInterval {
        let debut = Date()
        bloc()
        return Date().timeIntervalSince(debut)
    }

    /// Une fiche réaliste : c'est la prose des quatre langues qui coûte cher,
    /// une fixture vide ne mesurerait rien.
    private func plante(
        id: String,
        type: String = "Plante d'intérieur",
        includeFlags: Bool = true,
        easyCare: Bool = false,
        shadeTolerant: Bool = false,
        fullSunTolerant: Bool = false
    ) throws -> Plant {
        var json: [String: Any] = [
            "id": id,
            "name": "Plante \(id)",
            "type": type,
            "imageURLs": [],
            "description": "Un feuillage persistant, port buissonnant, "
                + "appréciant une lumière indirecte et un sol drainant.",
            "translations": [
                "fr": traduction(
                    "Feuillage persistant au port buissonnant, à installer en lumière indirecte.",
                    type: type, lumiere: "Lumière indirecte vive", duree: "4 à 6 heures par jour"),
                "en": traduction(
                    "Evergreen foliage with a bushy habit, best grown in bright indirect light.",
                    type: "Houseplant", lumiere: "Bright indirect light", duree: "4 to 6 hours a day"),
                "es": traduction(
                    "Follaje perenne de porte arbustivo, se cultiva con luz indirecta.",
                    type: "Planta de interior", lumiere: "Luz indirecta", duree: "4 a 6 horas al día"),
                "de": traduction(
                    "Immergrünes Laub mit buschigem Wuchs, für indirektes Licht.",
                    type: "Zimmerpflanze", lumiere: "Indirektes Licht", duree: "4 bis 6 Stunden täglich")
            ]
        ]

        if includeFlags {
            json["flags"] = [
                "toxicToPets": false, "toxicToChildren": false,
                "easyCare": easyCare,
                "shadeTolerant": shadeTolerant, "fullSunTolerant": fullSunTolerant,
                "droughtTolerant": false, "humidityLoving": false,
                "flowering": false, "climbing": false, "trailing": false,
                "compact": false, "airPurifying": false
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(Plant.self, from: data)
    }

    private func traduction(
        _ description: String,
        type: String,
        lumiere: String,
        duree: String
    ) -> [String: Any] {
        [
            "description": description,
            "plantType": type,
            "sun": ["lightType": lumiere, "durationPerDay": duree],
            "lifeCycle": ["growth": "Croissance modérée au printemps et en été",
                          "flowering": "Floraison discrète, estivale"],
            "care": ["difficulty": "Facile"]
        ]
    }
}
