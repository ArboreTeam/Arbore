import XCTest
@testable import ArboreUi

// PlantFilterMatchingTests — issue #792.
//
// Chaque test donne une LISTE de plantes, un filtre, et la liste EXACTE
// attendue en sortie. Pas « la plante passe », mais « voici celles qui passent
// et celles qui ne passent pas » — pour qu'un faux positif se voie autant
// qu'un faux négatif.
//
// C'est la forme que le défaut d'origine exigeait. `matches(plant:locale:)`
// commençait par
//
//     guard let translation = plant.translations[locale] else { return true }
//
// et une plante non traduite dans la langue du lecteur traversait donc TOUS
// les filtres. 877 fiches sur 1021 n'ont que l'anglais : un test qui n'affirme
// que « cette plante passe » n'aurait jamais vu le trou, puisque le trou
// consistait précisément à laisser passer.

final class PlantFilterMatchingTests: XCTestCase {

    // MARK: - Le trou des 877 fiches

    /// Une fiche SANS traduction dans la langue testée ne traverse plus un
    /// filtre qu'elle ne satisfait pas.
    ///
    /// Les deux plantes portent le même profil — 8 à 10 heures de soleil
    /// direct — et diffèrent seulement par leurs traductions : l'une est
    /// traduite en français, l'autre en anglais seulement. Un filtre « faible
    /// luminosité » doit écarter les DEUX.
    func testUneFicheNonTraduiteNeTraversePlusUnFiltreQuElleNeSatisfaitPas() throws {
        let traduite = try plante(id: "traduite", soleil: (8, 10), langues: ["fr", "en"])
        let anglaisSeul = try plante(id: "anglais-seul", soleil: (8, 10), langues: ["en"])
        let ombre = try plante(id: "ombre", soleil: (0, 2), langues: ["en"])

        var filtres = PlantFilters()
        filtres.light = .low

        assertRetient(
            filtres, sur: [traduite, anglaisSeul, ombre],
            attendu: ["ombre"],
            "Une fiche en anglais seul doit être évaluée comme les autres"
        )
    }

    // MARK: - Filtre lumière, liste exacte

    /// Dix plantes, un filtre, trois qui passent et sept qui ne passent pas.
    func testFiltreLumiereFaibleRendLaListeExacte() throws {
        let catalogue = try catalogueLumiere()

        var filtres = PlantFilters()
        filtres.light = .low

        assertRetient(
            filtres, sur: catalogue,
            // `low` = tolère 3 h de soleil direct ou moins : le minimum du
            // besoin de la plante doit être ≤ 3.
            attendu: ["ombre-profonde", "mi-ombre", "souple", "sans-donnee"]
        )
    }

    func testFiltreLumiereForteRendLaListeExacte() throws {
        let catalogue = try catalogueLumiere()

        var filtres = PlantFilters()
        filtres.light = .high

        assertRetient(
            filtres, sur: catalogue,
            // `high` = supporte 6 h ou plus : le maximum doit être ≥ 6.
            attendu: ["plein-soleil", "souple", "sans-donnee"]
        )
    }

    func testFiltreLumiereModereeRendLaListeExacte() throws {
        let catalogue = try catalogueLumiere()

        var filtres = PlantFilters()
        filtres.light = .medium

        assertRetient(
            filtres, sur: catalogue,
            attendu: ["mi-ombre", "souple", "sans-donnee"]
        )
    }

    /// **Un critère sans fait n'exclut pas.**
    ///
    /// `sans-donnee` apparaît dans les trois listes ci-dessus, et c'est voulu :
    /// l'incertitude est la nôtre, pas celle de la plante. Ce test l'affirme
    /// seul pour que la règle ne se perde pas dans les listes.
    func testUnePlanteSansHeuresDeSoleilNEstMasqueeParAucunNiveau() throws {
        let sansDonnee = try plante(id: "sans-donnee", soleil: nil, langues: ["en"])

        for niveau in PlantLightNeed.allCases {
            var filtres = PlantFilters()
            filtres.light = niveau
            XCTAssertTrue(filtres.matches(sansDonnee),
                          "Un filtre \(niveau) ne doit pas masquer ce qu'il ne sait pas juger")
        }
    }

    // MARK: - Filtre arrosage, liste exacte

    func testFiltreArrosageRendLesListesExactes() throws {
        let catalogue = [
            try plante(id: "quotidienne", arrosage: (1, 2), langues: ["en"]),
            try plante(id: "hebdomadaire", arrosage: (6, 8), langues: ["en"]),
            try plante(id: "mensuelle", arrosage: (21, 30), langues: ["en"]),
            try plante(id: "souple", arrosage: (2, 14), langues: ["en"]),
            try plante(id: "sans-donnee", langues: ["en"])
        ]

        var peu = PlantFilters()
        peu.water = .low
        assertRetient(peu, sur: catalogue, attendu: ["mensuelle", "souple", "sans-donnee"])

        var moyen = PlantFilters()
        moyen.water = .medium
        assertRetient(moyen, sur: catalogue, attendu: ["hebdomadaire", "souple", "sans-donnee"])

        var souvent = PlantFilters()
        souvent.water = .high
        assertRetient(souvent, sur: catalogue, attendu: ["quotidienne", "souple", "sans-donnee"])
    }

    // MARK: - Les critères se cumulent

    func testDeuxCriteresSeCumulentEnEt() throws {
        let catalogue = [
            try plante(id: "les-deux", soleil: (7, 10), arrosage: (20, 30), langues: ["en"]),
            try plante(id: "soleil-seul", soleil: (7, 10), arrosage: (1, 2), langues: ["en"]),
            try plante(id: "eau-seule", soleil: (0, 1), arrosage: (20, 30), langues: ["en"]),
            try plante(id: "aucun", soleil: (0, 1), arrosage: (1, 2), langues: ["en"])
        ]

        var filtres = PlantFilters()
        filtres.light = .high
        filtres.water = .low

        assertRetient(filtres, sur: catalogue, attendu: ["les-deux"])
    }

    func testSansCritereRienNEstEcarte() throws {
        let catalogue = try catalogueLumiere()
        let filtres = PlantFilters()

        XCTAssertFalse(filtres.isActive)
        assertRetient(filtres, sur: catalogue, attendu: catalogue.map(\.id))
    }

    // MARK: - Filtre de difficulté : le trait clos décide

    /// Le FAIT stocké prime sur `care.difficulty` et sur le drapeau.
    func testLeTraitCloseDEntretienDecideAvantLaProseEtAvantLeDrapeau() throws {
        let facileStockee = try plante(
            id: "facile-stockee",
            profilSupplementaire: ["easyCare": ["value": "yes", "evidence": preuve()]],
            difficulteProse: "Exigeant",
            langues: ["fr"]
        )
        let exigeanteStockee = try plante(
            id: "exigeante-stockee",
            profilSupplementaire: ["easyCare": ["value": "no", "evidence": preuve()]],
            difficulteProse: "Facile",
            langues: ["fr"]
        )

        XCTAssertEqual(facileStockee.careDifficulty(), .easy)
        XCTAssertEqual(exigeanteStockee.careDifficulty(), .demanding)

        var filtres = PlantFilters()
        filtres.difficulty = .easy
        assertRetient(
            filtres, sur: [facileStockee, exigeanteStockee],
            attendu: ["facile-stockee"]
        )
    }

    /// Un `unknown` stocké ne tranche pas : la lecture continue, et à défaut
    /// de tout, la plante n'est pas masquée (#485).
    func testUnEntretienNonEtabliNeMasquePas() throws {
        let inconnue = try plante(
            id: "inconnue",
            profilSupplementaire: ["easyCare": ["value": "unknown", "evidence": preuve()]],
            langues: ["en"],
            avecDrapeaux: false
        )

        XCTAssertNil(inconnue.careDifficulty())

        var filtres = PlantFilters()
        filtres.difficulty = .easy
        assertRetient(filtres, sur: [inconnue], attendu: ["inconnue"])
    }

    // MARK: - Les filtres du catalogue AR, liste exacte

    /// Les préférences du catalogue AR lisent les mêmes valeurs closes, et un
    /// critère non établi ne satisfait PAS une demande : c'est l'inverse du
    /// filtre d'exposition, et l'asymétrie est volontaire. Ici l'utilisateur
    /// demande une caractéristique précise ; là il déclare une contrainte de
    /// son lieu.
    func testPreferencesDuCatalogueARRendentLaListeExacte() throws {
        let catalogue = [
            try plante(id: "fougere-compacte", profilSupplementaire: [
                "kinds": liste(["fern"]), "size": gabarit("small")
            ], langues: ["en"]),
            try plante(id: "arbre-statement", profilSupplementaire: [
                "kinds": liste(["tree"]), "size": gabarit("large")
            ], langues: ["en"]),
            try plante(id: "fougere-grande", profilSupplementaire: [
                "kinds": liste(["fern"]), "size": gabarit("large")
            ], langues: ["en"]),
            try plante(id: "sans-nature", profilSupplementaire: ["size": gabarit("small")], langues: ["en"])
        ]

        var parNature = PlantCatalogFilters()
        parNature.kinds = [.fern]
        assertRetient(parNature, sur: catalogue, attendu: ["fougere-compacte", "fougere-grande"])

        var parGabarit = PlantCatalogFilters()
        parGabarit.scale = .compact
        assertRetient(parGabarit, sur: catalogue, attendu: ["fougere-compacte", "sans-nature"])

        var lesDeux = PlantCatalogFilters()
        lesDeux.kinds = [.fern]
        lesDeux.scale = .compact
        assertRetient(lesDeux, sur: catalogue, attendu: ["fougere-compacte"])
    }

    /// Un critère d'entretien non établi ne satisfait pas la demande.
    func testUnCritereDEntretienNonEtabliNeSatisfaitPasLaDemande() throws {
        let facile = try plante(id: "facile", profilSupplementaire: [
            "easyCare": ["value": "yes", "evidence": preuve()]
        ], langues: ["en"])
        let pasFacile = try plante(id: "pas-facile", profilSupplementaire: [
            "easyCare": ["value": "no", "evidence": preuve()]
        ], langues: ["en"])
        let inconnue = try plante(id: "inconnue", langues: ["en"], avecDrapeaux: false)

        var filtres = PlantCatalogFilters()
        filtres.careLevel = .minimal
        assertRetient(filtres, sur: [facile, pasFacile, inconnue], attendu: ["facile"])
    }

    /// Un filtre vide laisse tout passer, quel que soit l'état des données.
    func testUnFiltreDeCatalogueVideLaisseToutPasser() throws {
        let catalogue = [
            try plante(id: "a", langues: ["en"], avecDrapeaux: false),
            try plante(id: "b", profilSupplementaire: ["kinds": liste(["tree"])], langues: ["en"])
        ]
        assertRetient(PlantCatalogFilters(), sur: catalogue, attendu: ["a", "b"])
    }

    // MARK: - Affirmations

    private func assertRetient(
        _ filtres: PlantFilters,
        sur catalogue: [Plant],
        attendu: [String],
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let obtenu = catalogue.filter { filtres.matches($0) }.map(\.id).sorted()
        affirme(obtenu, attendu, catalogue, message, file: file, line: line)
    }

    private func assertRetient(
        _ filtres: PlantCatalogFilters,
        sur catalogue: [Plant],
        attendu: [String],
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let obtenu = catalogue.filter { filtres.matches($0) }.map(\.id).sorted()
        affirme(obtenu, attendu, catalogue, message, file: file, line: line)
    }

    /// Le message nomme les faux positifs ET les faux négatifs séparément :
    /// « montré à tort » et « masqué à tort » ne se corrigent pas pareil.
    private func affirme(
        _ obtenu: [String],
        _ attendu: [String],
        _ catalogue: [Plant],
        _ message: String,
        file: StaticString,
        line: UInt
    ) {
        let attenduTrie = attendu.sorted()
        guard obtenu != attenduTrie else { return }

        let aTort = Set(obtenu).subtracting(attenduTrie).sorted()
        let manquantes = Set(attenduTrie).subtracting(obtenu).sorted()
        var rapport = "Liste attendue \(attenduTrie), obtenue \(obtenu)"
        if !aTort.isEmpty { rapport += " — montrées à tort : \(aTort)" }
        if !manquantes.isEmpty { rapport += " — masquées à tort : \(manquantes)" }
        if !message.isEmpty { rapport += " — \(message)" }
        rapport += " (catalogue de \(catalogue.count) fiches)"

        XCTFail(rapport, file: file, line: line)
    }

    // MARK: - Fabrique

    private func catalogueLumiere() throws -> [Plant] {
        [
            try plante(id: "ombre-profonde", soleil: (0, 1), langues: ["en"]),
            try plante(id: "mi-ombre", soleil: (2, 4), langues: ["en"]),
            try plante(id: "plein-soleil", soleil: (7, 12), langues: ["en"]),
            try plante(id: "souple", soleil: (1, 10), langues: ["en"]),
            try plante(id: "sans-donnee", soleil: nil, langues: ["en"])
        ]
    }

    private func plante(
        id: String,
        soleil: (Double, Double)? = nil,
        arrosage: (Double, Double)? = nil,
        profilSupplementaire: [String: Any] = [:],
        difficulteProse: String? = nil,
        langues: [String] = ["en"],
        avecDrapeaux: Bool = true
    ) throws -> Plant {
        var profil: [String: Any] = ["schemaVersion": 1]
        if let soleil {
            profil["directSunHours"] = plage(soleil.0, soleil.1, "hours/day")
        }
        if let arrosage {
            profil["wateringIntervalDays"] = plage(arrosage.0, arrosage.1, "days")
        }
        for (cle, valeur) in profilSupplementaire { profil[cle] = valeur }

        var traductions: [String: Any] = [:]
        for langue in langues {
            var traduction: [String: Any] = [
                "description": "Prose de test en \(langue).",
                "plantType": "Plante",
                // Volontairement contradictoires avec le profil : plus aucun
                // filtre ne les lit.
                "sun": ["lightType": "Plein soleil, ombre, faible luminosité"],
                "water": ["frequency": "Peu, moyen, souvent"]
            ]
            if let difficulteProse {
                traduction["care"] = ["difficulty": difficulteProse]
            }
            traductions[langue] = traduction
        }

        var json: [String: Any] = [
            "id": id,
            "name": "Plante \(id)",
            "type": "Plant",
            "imageURLs": [],
            "description": "",
            "translations": traductions,
            "botanicalProfile": profil
        ]

        if avecDrapeaux {
            json["flags"] = [
                "toxicToPets": false, "toxicToChildren": false, "easyCare": false,
                "shadeTolerant": false, "fullSunTolerant": false, "droughtTolerant": false,
                "humidityLoving": false, "flowering": false, "climbing": false,
                "trailing": false, "compact": false, "airPurifying": false
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(Plant.self, from: data)
    }

    /// Les faits de traits sont SOURCÉS, comme tous les autres champs du
    /// profil : une valeur sans provenance n'est pas une donnée vérifiable.
    private func gabarit(_ value: String) -> [String: Any] {
        ["value": value, "evidence": preuve()]
    }

    private func liste(_ values: [String]) -> [String: Any] {
        ["value": values, "evidence": preuve()]
    }

    private func plage(_ minimum: Double, _ maximum: Double, _ unit: String) -> [String: Any] {
        ["minimum": minimum, "maximum": maximum, "unit": unit, "evidence": preuve()]
    }

    private func preuve() -> [String: Any] {
        [
            "sourceName": "Source de test",
            "sourceURL": "https://example.test/plant",
            "reviewedAt": "2026-11-08",
            "reliability": "high"
        ]
    }
}
