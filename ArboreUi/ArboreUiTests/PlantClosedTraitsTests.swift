import XCTest
@testable import ArboreUi

// PlantClosedTraitsTests — issue #792.
//
// Les sept traits de catalogue se dérivaient de la prose traduite, sur ~146
// lignes de listes de mots-clés en quatre langues. Ils se LISENT désormais sur
// des valeurs closes de la fiche.
//
// Le test qui décide de tout est `testUneFicheDontLaProseEtLeNomContredisent…` :
// une fiche dont la prose et le nom contredisent les valeurs stockées ne doit
// rien changer au résultat. Tant qu'il passe, on ne parse plus.

final class PlantClosedTraitsTests: XCTestCase {

    // MARK: - LE test anti-régression

    /// Une prose et un nom qui MENTENT ne changent rien.
    ///
    /// La fiche est construite deux fois avec exactement les mêmes valeurs
    /// closes : une fois nue, une fois avec un nom et une prose bourrés des
    /// mots-clés que les sept anciennes fonctions cherchaient — « arbuste »,
    /// « palmier », « fleur », « grimpante », « cactus », « couvre-sol »,
    /// « mousse », « lierre », « rouge », « facile d'entretien », dans les
    /// quatre langues servies.
    ///
    /// Les deux instantanés doivent être IDENTIQUES. S'ils diffèrent un jour,
    /// un chemin de dérivation est revenu.
    func testUneFicheDontLaProseEtLeNomContredisentLesValeursStockeesDonneLeMemeResultat() throws {
        let valeurs: [String: Any] = [
            "size": gabarit("small"),
            "kinds": liste(["fern"]),
            "goals": liste(["coverGround"]),
            "colors": liste(["white"]),
            "placement": liste(["floor"]),
            "flowering": trait("no"),
            "easyCare": trait("no"),
            "compact": trait("yes"),
            "climbing": trait("no"),
            "trailing": trait("no")
        ]

        let nue = try plante(id: "nue", profil: valeurs)
        let menteuse = try plante(
            id: "menteuse",
            nom: "Grand Arbuste Palmier Cactus Tuteur Mousse Lierre Rouge",
            type: "Plante grimpante retombante couvre-sol",
            profil: valeurs,
            prose: proseMenteuse()
        )

        let traitsNus = PlantCatalogTraits.snapshot(for: nue)
        let traitsMenteurs = PlantCatalogTraits.snapshot(for: menteuse)

        XCTAssertEqual(traitsMenteurs.size, traitsNus.size,
                       "Le gabarit ne doit pas bouger parce que le nom dit « Grand Arbuste »")
        XCTAssertEqual(traitsMenteurs.kinds, traitsNus.kinds,
                       "La nature ne doit pas bouger parce que la prose dit « cactus » et « palmier »")
        XCTAssertEqual(traitsMenteurs.goals, traitsNus.goals)
        XCTAssertEqual(traitsMenteurs.colors, traitsNus.colors,
                       "La couleur ne doit pas bouger parce que le nom dit « Rouge »")
        XCTAssertEqual(traitsMenteurs.appearances, traitsNus.appearances,
                       "L'apparence ne doit pas bouger parce que la prose dit « fleur »")
        XCTAssertEqual(traitsMenteurs.habits, traitsNus.habits,
                       "Le port ne doit pas bouger parce que le type dit « grimpante retombante »")
        XCTAssertEqual(traitsMenteurs.isEasyCare, traitsNus.isEasyCare,
                       "L'entretien ne doit pas bouger parce que la prose dit « facile d'entretien »")
        XCTAssertEqual(
            PlantPlacementCompatibility.supportedModes(for: menteuse),
            PlantPlacementCompatibility.supportedModes(for: nue),
            "La capacité de pose ne doit pas bouger parce que le nom contient « lierre »"
        )

        // Et le contenu lui-même, pour qu'un « identiques mais tous les deux
        // faux » ne passe pas.
        XCTAssertEqual(traitsMenteurs.size, .small)
        XCTAssertEqual(traitsMenteurs.kinds, [.fern])
        XCTAssertEqual(traitsMenteurs.colors, [.white])
        XCTAssertEqual(traitsMenteurs.habits, [])
        XCTAssertEqual(traitsMenteurs.isEasyCare, false)
        XCTAssertEqual(traitsMenteurs.appearances, [.decorativeFoliage])
    }

    /// Le cas réel du catalogue : « tuteur mousse ».
    ///
    /// `Monstera_Deliciosa_Pot_Tuteur_Mousse` et
    /// `Pothos_Dore_Vert_Sur_Tuteur_Mousse` étaient classés COUVRE-SOL parce
    /// que leur nom contient « mousse ».
    func testLeNomTuteurMousseNeClassePlusEnCouvreSol() throws {
        let monstera = try plante(
            id: "monstera",
            nom: "Monstera Deliciosa Pot Tuteur Mousse",
            profil: ["kinds": liste(["greenPlant"]), "size": gabarit("large")]
        )

        XCTAssertEqual(PlantCatalogTraits.kinds(for: monstera), [.greenPlant])
        XCTAssertFalse(PlantCatalogTraits.kinds(for: monstera).contains(.groundcover))
    }

    // MARK: - Les sept traits, lus depuis la structure

    func testLeGabaritSeLitSurLeChampStocke() throws {
        XCTAssertEqual(PlantCatalogTraits.size(for: try plante(profil: ["size": gabarit("large")])), .large)
        XCTAssertEqual(PlantCatalogTraits.size(for: try plante(profil: ["size": gabarit("medium")])), .medium)
        XCTAssertEqual(PlantCatalogTraits.size(for: try plante(profil: ["size": gabarit("unknown")])), .unknown)
    }

    func testLesNaturesSeLisentSurLeChampStocke() throws {
        let p = try plante(profil: ["kinds": liste(["shrub", "conifer", "perennial"])])
        XCTAssertEqual(PlantCatalogTraits.kinds(for: p), [.shrub, .conifer, .perennial])
    }

    /// `conifer` est entré au vocabulaire avec #792 : la typologie de #777 le
    /// porte sur 39 fiches et aucune cible n'existait.
    func testConiferEstUneValeurDuVocabulaire() throws {
        XCTAssertTrue(PlantCatalogKind.allCases.contains(.conifer))
        let p = try plante(profil: ["kinds": liste(["conifer"])])
        XCTAssertEqual(PlantCatalogTraits.kinds(for: p), [.conifer])
    }

    func testLesButsEtLesCouleursSeLisentSurLesChampsStockes() throws {
        let p = try plante(profil: [
            "goals": liste(["createPrivacy", "attractPollinators"]),
            "colors": liste(["purple", "blue"])
        ])
        XCTAssertEqual(PlantCatalogTraits.goals(for: p), [.createPrivacy, .attractPollinators])
        XCTAssertEqual(PlantCatalogTraits.colors(for: p), [.purple, .blue])
    }

    func testLesSeptTraitsTriEtatsSeLisentSurLeurFait() throws {
        let oui = try plante(profil: [
            "flowering": trait("yes"), "easyCare": trait("yes"), "compact": trait("yes"),
            "climbing": trait("yes"), "trailing": trait("yes"),
            "humidityLoving": trait("yes"), "airPurifying": trait("yes")
        ])
        for trait in Plant.DescriptiveTrait.allCases {
            XCTAssertEqual(oui.trait(trait), true, "\(trait) devrait valoir oui")
        }

        let non = try plante(profil: [
            "flowering": trait("no"), "easyCare": trait("no"), "compact": trait("no"),
            "climbing": trait("no"), "trailing": trait("no"),
            "humidityLoving": trait("no"), "airPurifying": trait("no")
        ])
        for trait in Plant.DescriptiveTrait.allCases {
            XCTAssertEqual(non.trait(trait), false, "\(trait) devrait valoir non")
        }
    }

    // MARK: - Le plancher, et le silence

    /// Un `unknown` stocké rend `nil`, PAS `false`.
    ///
    /// La distinction est tout l'objet du tri-état : « on a cherché sans
    /// trouver » n'est pas « non ».
    func testUnTraitInconnuRendNilEtPasFaux() throws {
        let p = try plante(profil: ["flowering": trait("unknown")])
        XCTAssertNil(p.trait(.flowering))
    }

    /// Une valeur hors vocabulaire tombe vers le PLANCHER.
    ///
    /// C'est la règle qui rend la migration sans danger : les fiches
    /// historiques portent de la prose dans ces champs, elle se décode en
    /// « inconnu » et n'affirme rien.
    func testUneValeurHorsVocabulaireTombeVersInconnuEtJamaisVersOui() throws {
        let p = try plante(profil: ["flowering": trait("probablement-fleurie")])
        XCTAssertNil(p.trait(.flowering), "Hors vocabulaire doit valoir inconnu, jamais oui")
    }

    /// Un élément hors vocabulaire dans une liste est ÉCARTÉ, et les autres
    /// restent — sans que la fiche entière échoue au décodage.
    func testUnElementHorsVocabulaireEstEcarteSansEmporterLaFiche() throws {
        let p = try plante(profil: ["kinds": liste(["shrub", "mega-arbuste-du-futur", "fern"])])

        XCTAssertEqual(PlantCatalogTraits.kinds(for: p), [.shrub, .fern])
        XCTAssertEqual(p.botanicalProfile?.kinds?.rejected, ["mega-arbuste-du-futur"],
                       "L'élément écarté doit rester consignable, pour que la divergence se voie")
    }

    /// Un `value` absent vaut `unknown` et ne fait pas échouer le profil.
    func testUnFaitSansValeurVautInconnuEtLaFicheSeDecodeQuandMeme() throws {
        let p = try plante(profil: [
            "flowering": ["detail": "le champ value manque"],
            "size": gabarit("large")
        ])
        XCTAssertNil(p.trait(.flowering))
        XCTAssertEqual(PlantCatalogTraits.size(for: p), .large,
                       "Une clé manquante ne doit pas emporter le reste du profil")
    }

    /// Un champ absent vaut `unknown`, et sans drapeau rien ne l'affirme.
    func testUnChampAbsentVautInconnu() throws {
        let p = try plante(profil: ["size": gabarit("medium")], avecDrapeaux: false)
        for trait in Plant.DescriptiveTrait.allCases {
            XCTAssertNil(p.trait(trait), "\(trait) sans champ ni drapeau doit rester inconnu")
        }
        XCTAssertEqual(PlantCatalogTraits.kinds(for: p), [],
                       "Il n'y a plus de « plante verte » par défaut")
        XCTAssertEqual(PlantCatalogTraits.habits(for: p), [],
                       "Il n'y a plus de port « érigé » par défaut")
    }

    // MARK: - Le repli par drapeau, et ses deux règles

    /// Le fait STOCKÉ prime sur le drapeau, toujours — y compris pour dire
    /// qu'il ne sait pas.
    func testLeFaitStockePrimeSurLeDrapeauYComprisQuandIlDitInconnu() throws {
        let contredit = try plante(
            profil: ["flowering": trait("no")],
            drapeaux: ["flowering": true]
        )
        XCTAssertEqual(contredit.trait(.flowering), false,
                       "Le verdict stocké prime sur le drapeau")

        let indetermine = try plante(
            profil: ["flowering": trait("unknown")],
            drapeaux: ["flowering": true]
        )
        XCTAssertNil(indetermine.trait(.flowering),
                     "Un fait présent décide, même pour dire qu'il ne sait pas : "
                     + "consulter le drapeau par-dessus transformerait une absence mesurée "
                     + "en affirmation")
    }

    /// Sans fait, seul le `true` du drapeau informe.
    func testSansFaitSeulLeTrueDuDrapeauInforme() throws {
        XCTAssertEqual(try plante(drapeaux: ["flowering": true]).trait(.flowering), true)
    }

    /// **Le piège historique.** Un drapeau BAISSÉ ne prouve rien.
    ///
    /// C'est la forme exacte du `toxicToPets: false` que #778 a retirée des
    /// données et que le repli de `petToxicity()` portait encore jusqu'à
    /// #792 : « prouvé non » et « pas recherché » confondus dans un booléen.
    func testUnDrapeauBaisseNeProuveRien() throws {
        let p = try plante(drapeaux: ["flowering": false])
        XCTAssertNil(p.trait(.flowering),
                     "Un drapeau baissé vaut « pas recherché », pas « ne fleurit pas »")
    }

    // MARK: - Les dérivées de traits clos

    /// Le `no` explicite de la floraison porte « Feuillage décoratif ».
    func testLeNonDeLaFloraisonDonneLeFeuillageDecoratif() throws {
        let fleurie = try plante(profil: ["flowering": trait("yes")])
        let feuillage = try plante(profil: ["flowering": trait("no")])
        let inconnue = try plante(profil: ["flowering": trait("unknown")])

        XCTAssertEqual(PlantCatalogTraits.appearances(for: fleurie), [.flowering])
        XCTAssertEqual(PlantCatalogTraits.appearances(for: feuillage), [.decorativeFoliage])
        XCTAssertEqual(PlantCatalogTraits.appearances(for: inconnue), [],
                       "Un silence n'affirme ni la floraison ni le feuillage décoratif")
    }

    /// Les tolérances d'exposition se lisent sur `directSunHours`, pas sur la
    /// prose. Les bornes 3 h et 6 h sont celles du critère d'exposition.
    func testLesTolerancesDExpositionSeLisentSurLesHeuresDeSoleil() throws {
        let ombre = try plante(profil: ["directSunHours": plage(0, 2)], avecDrapeaux: false)
        let soleil = try plante(profil: ["directSunHours": plage(7, 12)], avecDrapeaux: false)

        XCTAssertTrue(PlantCatalogTraits.sunlightTolerances(for: ombre).shade)
        XCTAssertFalse(PlantCatalogTraits.sunlightTolerances(for: ombre).fullSun)
        XCTAssertFalse(PlantCatalogTraits.sunlightTolerances(for: soleil).shade)
        XCTAssertTrue(PlantCatalogTraits.sunlightTolerances(for: soleil).fullSun)
    }

    /// Le besoin en eau faible se lit sur `droughtTolerance`, au vocabulaire
    /// fermé. `moderate` ne tranche pas.
    func testLeBesoinEnEauFaibleSeLitSurLaToleranceALaSecheresse() throws {
        XCTAssertEqual(
            PlantCatalogTraits.needsLittleWater(try plante(profil: ["droughtTolerance": ["value": "high"]])),
            true
        )
        XCTAssertEqual(
            PlantCatalogTraits.needsLittleWater(try plante(profil: ["droughtTolerance": ["value": "low"]])),
            false
        )
        XCTAssertNil(
            PlantCatalogTraits.needsLittleWater(try plante(profil: ["droughtTolerance": ["value": "moderate"]])),
            "« modéré » ne répond ni oui ni non"
        )
    }

    /// Les trois critères d'entretien SANS source close rendent `nil`.
    ///
    /// Ce test documente le trou plutôt que de le laisser surprendre : ces
    /// options du filtre ne renvoient rien tant qu'aucun champ ne les porte.
    func testLesTroisCriteresSansSourceCloseRestentNonEtablis() throws {
        let p = try plante(profil: ["size": gabarit("large")])
        XCTAssertNil(PlantCatalogTraits.isSlowGrowing(p))
        XCTAssertNil(PlantCatalogTraits.needsLittlePruning(p))
        XCTAssertNil(PlantCatalogTraits.hasLongBloom(p))
    }

    // MARK: - Outils

    /// Tous les champs de traits sont des faits SOURCÉS. La provenance
    /// n'est pas un ornement : tout ce corpus repose sur le fait qu'une valeur
    /// dise d'où elle vient, quand elle a été revue et à quel degré de
    /// confiance (#782, et c'est ce que la carte de #790 affiche).
    private func trait(_ value: String) -> [String: Any] {
        ["value": value, "evidence": preuve()]
    }

    private func gabarit(_ value: String) -> [String: Any] {
        ["value": value, "evidence": preuve()]
    }

    private func liste(_ values: [String]) -> [String: Any] {
        ["value": values, "evidence": preuve()]
    }

    private func plage(_ minimum: Double, _ maximum: Double) -> [String: Any] {
        ["minimum": minimum, "maximum": maximum, "unit": "hours/day", "evidence": preuve()]
    }

    private func preuve() -> [String: Any] {
        [
            "sourceName": "Source de test",
            "sourceURL": "https://example.test/plant",
            "reviewedAt": "2026-11-08",
            "reliability": "high"
        ]
    }

    private func plante(
        id: String = "plante",
        nom: String = "Plante de test",
        type: String = "Plant",
        profil: [String: Any]? = nil,
        drapeaux: [String: Bool] = [:],
        avecDrapeaux: Bool = true,
        prose: [String: Any]? = nil
    ) throws -> Plant {
        var json: [String: Any] = [
            "id": id,
            "name": nom,
            "type": type,
            "imageURLs": [],
            "description": "",
            "translations": prose ?? [:]
        ]

        if avecDrapeaux || !drapeaux.isEmpty {
            var complets: [String: Bool] = [
                "toxicToPets": false, "toxicToChildren": false, "easyCare": false,
                "shadeTolerant": false, "fullSunTolerant": false, "droughtTolerant": false,
                "humidityLoving": false, "flowering": false, "climbing": false,
                "trailing": false, "compact": false, "airPurifying": false
            ]
            for (k, v) in drapeaux { complets[k] = v }
            json["flags"] = complets
        }

        if var profil {
            profil["schemaVersion"] = 1
            json["botanicalProfile"] = profil
        }

        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(Plant.self, from: data)
    }

    /// Chacun des mots-clés que les sept anciennes fonctions cherchaient, dans
    /// les quatre langues servies. Si une décision dépendait du texte, elle se
    /// verrait quelle que soit la locale de lecture.
    private func proseMenteuse() -> [String: Any] {
        let fr = "Grand arbuste ornemental, palmier et cactus à la fois, plante grimpante "
            + "retombante et couvre-sol. Floraison rouge abondante, feuillage panaché "
            + "persistant et parfumé. Facile d'entretien pour un débutant, peu d'arrosage, "
            + "croissance lente, peu de taille, floraison longue. Attire les abeilles et "
            + "les papillons. Tuteur mousse, lierre, brise-vue."
        let en = "A large ornamental shrub, palm tree and cactus, a climbing trailing "
            + "groundcover with red flowering, variegated evergreen fragrant foliage. "
            + "Easy care for a beginner, low water, slow growing, little pruning, "
            + "long blooming. Bee friendly and butterfly friendly. Moss pole, ivy, privacy."
        let es = "Arbusto grande, palmera y cactus, planta trepadora y cubresuelo, "
            + "floración roja, follaje decorativo, fácil de cuidar, poco riego."
        let de = "Großer Strauch, Palme und Kaktus, Kletterpflanze und Bodendecker, "
            + "blühend rot, panaschiert immergrün, pflegeleicht, wenig Wasser."

        func traduction(_ texte: String) -> [String: Any] {
            [
                "description": texte,
                "plantType": "Arbuste grimpant retombant",
                "sun": ["lightType": "Plein soleil et ombre", "durationPerDay": "6 heures"],
                "lifeCycle": ["growth": "Croissance lente", "flowering": "Floraison longue"],
                "care": ["difficulty": "Facile"]
            ]
        }

        return ["fr": traduction(fr), "en": traduction(en), "es": traduction(es), "de": traduction(de)]
    }
}
