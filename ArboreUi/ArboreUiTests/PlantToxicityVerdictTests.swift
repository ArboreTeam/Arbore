import XCTest
@testable import ArboreUi

/// Le verdict de toxicité est une donnée stockée, en valeurs closes (#778).
///
/// Ce qu'il remplace : un analyseur de sous-chaînes qui testait la liste sûre
/// avant la liste toxique. Comme `safe` est une sous-chaîne de `unsafe`, toute
/// phrase niant l'innocuité était rendue `.safe` — l'inverse exact de ce
/// qu'elle disait, et avec provenance et date de revue à l'appui, donc plus
/// crédible qu'une absence de donnée.
///
/// Ces tests tiennent les deux propriétés qui comptent :
///   1. le verdict vient du champ, jamais d'une lecture de prose ;
///   2. tout ce qui n'est pas reconnu vaut « inconnu », jamais « sûr ».
final class PlantToxicityVerdictTests: XCTestCase {

    // MARK: - Les quatre valeurs du vocabulaire

    func testVerdictStockeEstLuTelQuel() throws {
        XCTAssertEqual(try plant(petToxicity: "toxic").petToxicity(), .toxic)
        XCTAssertEqual(try plant(petToxicity: "safe").petToxicity(), .safe)
        XCTAssertEqual(try plant(childToxicity: "toxic").childToxicity(), .toxic)
        XCTAssertEqual(try plant(childToxicity: "safe").childToxicity(), .safe)
    }

    func testIrritantCompteCommeToxique() throws {
        // Les sources distinguent l'irritation de l'empoisonnement ; l'app non.
        // Une atteinte reste une atteinte.
        XCTAssertEqual(try plant(petToxicity: "irritant").petToxicity(), .toxic)
    }

    func testVerdictInsensibleALaCasseEtAuxEspaces() throws {
        XCTAssertEqual(try plant(petToxicity: "  TOXIC ").petToxicity(), .toxic)
        XCTAssertEqual(try plant(petToxicity: "Safe").petToxicity(), .safe)
    }

    // MARK: - « unknown » retombe sur les drapeaux, et n'affirme rien

    func testUnknownRetombeSurLesDrapeaux() throws {
        XCTAssertEqual(
            try plant(petToxicity: "unknown", toxicToPets: true).petToxicity(),
            .toxic,
            "un verdict non établi doit laisser le repli décider"
        )
        XCTAssertNil(
            try plant(petToxicity: "unknown", includeFlags: false).petToxicity(),
            "sans verdict ni drapeau, la toxicité n'est pas établie — et nil n'est pas « sûre »"
        )
    }

    func testLaToxiciteEnfantSuitLeMemeContrat() throws {
        // Le repli par drapeau existe pour les deux publics. Les fiches
        // d'avant 2026-11 ne portaient aucun `childToxicity` — l'ASPCA ne
        // couvre que chiens, chats et chevaux — et retombaient donc toujours
        // sur le drapeau.
        XCTAssertEqual(
            try plant(childToxicity: "unknown", toxicToChildren: true).childToxicity(),
            .toxic
        )
        XCTAssertEqual(
            try plant(childToxicity: "unknown", toxicToChildren: false).childToxicity(),
            .safe
        )
        XCTAssertNil(
            try plant(childToxicity: "unknown", includeFlags: false).childToxicity()
        )
        XCTAssertNil(try plant(includeFlags: false).childToxicity())
    }

    /// Une clé `value` absente ne doit pas emporter le profil botanique entier.
    func testUnFaitSansValeurNeCassePasLeProfil() throws {
        let json: [String: Any] = [
            "id": "plant", "name": "Test plant", "type": "Plant",
            "imageURLs": [], "description": "", "translations": [:],
            "botanicalProfile": [
                "schemaVersion": 1,
                "minimumTemperatureC": ["value": -10.0],
                "petToxicity": ["detail": "source consultee, verdict non consigne"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let p = try JSONDecoder().decode(Plant.self, from: data)
        XCTAssertEqual(p.botanicalProfile?.petToxicity?.value, .unknown)
        XCTAssertEqual(
            p.botanicalProfile?.minimumTemperatureC?.value, -10,
            "le reste du profil doit survivre"
        )
        XCTAssertNil(p.petToxicity(), "sans drapeaux, la toxicite reste non etablie")
    }

    // MARK: - Les inversions que l'analyseur produisait

    /// Chaque chaîne ci-dessous était rendue `.safe` par l'ancien analyseur,
    /// alors qu'elle nie l'innocuité : `safe` y est une sous-chaîne.
    func testLesPhrasesNiantLInnocuiteNeSontJamaisLuesSures() throws {
        let inversions = [
            "unsafe for cats and dogs",
            "not safe around children",
            "never safe to chew",
            "toxicity not established — treat as unknown, not as safe",
            "rather than safe, assume harmful"
        ]
        for phrase in inversions {
            let p = try plant(petToxicity: phrase, toxicToPets: true)
            XCTAssertNotEqual(
                p.petToxicity(), .safe,
                "« \(phrase) » ne doit jamais être lue comme sûre"
            )
            XCTAssertEqual(p.petToxicity(), .toxic, "ici c'est le drapeau qui tranche")
        }
    }

    /// La formulation réellement écrite sur les fiches non tranchées.
    func testLaProseDesFichesNonTrancheesNAffirmeRien() throws {
        let detail = "toxic risk unresolved - no veterinary reference classifies "
            + "Olea europaea either way, so treat it as potentially toxic "
            + "rather than proven harmless"
        let p = try plant(petToxicity: "unknown", detail: detail, toxicToPets: true)
        XCTAssertEqual(p.petToxicity(), .toxic)
    }

    // MARK: - Migration : la prose historique se décode en « inconnu »

    /// Les fiches d'avant #778 portent une phrase dans `value`. Elle doit se
    /// décoder en `unknown` — pas faire échouer tout le profil botanique, et
    /// surtout pas devenir `safe`.
    func testLaProseHistoriqueSeDecodeEnInconnuSansCasserLeProfil() throws {
        let p = try plant(
            petToxicity: "Toxic to dogs, cats and horses: eugenol and other essential oils",
            toxicToPets: true
        )
        XCTAssertNotNil(p.botanicalProfile, "le profil doit survivre au décodage")
        XCTAssertEqual(p.botanicalProfile?.petToxicity?.value, .unknown)
        XCTAssertEqual(p.petToxicity(), .toxic, "le drapeau reprend la main")
    }

    func testLaProseHistoriqueNeRendJamaisSurUneFicheSansDrapeau() throws {
        let p = try plant(petToxicity: "Non-toxic per the ASPCA", includeFlags: false)
        XCTAssertNil(
            p.petToxicity(),
            "même une prose rassurante ne vaut pas verdict : il faut la valeur close"
        )
    }

    // MARK: - L'évaluateur dit la même chose que l'accesseur

    /// La décision existait en deux copies : `Plant` et `appendToxicityCriterion`
    /// refaisaient le même test, et divergeaient sur le repli (#780). Les deux
    /// lisent désormais le même champ.
    func testEvaluateurEtAccesseurSAccordent() throws {
        let toxique = try plant(petToxicity: "toxic", fullSunTolerant: true)
        XCTAssertEqual(toxique.petToxicity(), .toxic)
        let verdict = PlantSuitabilityEvaluator(wizard: wizardExigeantDesAnimaux())
            .evaluate(toxique)
        XCTAssertEqual(verdict.level, .unsuitable)
        XCTAssertFalse(verdict.isRecommended)
        XCTAssertTrue(verdict.warningReasonKeys.contains("AR_CATALOG_REASON_PET_CONFLICT"))
    }

    func testUnVerdictInconnuNEstPasPresenteCommeSansDanger() throws {
        let inconnu = try plant(petToxicity: "unknown", fullSunTolerant: true)
        let verdict = PlantSuitabilityEvaluator(wizard: wizardExigeantDesAnimaux())
            .evaluate(inconnu)
        XCTAssertFalse(
            verdict.positiveReasonKeys.contains("AR_CATALOG_REASON_PET_SAFE"),
            "une toxicité non établie ne doit jamais produire un motif « sans danger »"
        )
    }

    // MARK: - Fixtures

    private func wizardExigeantDesAnimaux() -> GardenWizardDTO {
        var wizard = GardenWizardDTO(
            style: "",
            spaceType: GardenSpaceType.balcony.rawValue,
            exposure: nil,
            maintenance: nil,
            safety: nil,
            soil: nil,
            scanMethod: nil,
            siteProfile: GardenSiteProfileDTO(
                sunlight: GardenSunlightDTO(
                    minimumHours: 6,
                    maximumHours: 10,
                    metadata: GardenValueMetadataDTO(source: .inferred, confidence: .medium)
                )
            )
        )
        wizard.safety = [SafetyOption.pets.rawValue]
        return wizard
    }

    private func plant(
        petToxicity: String? = nil,
        childToxicity: String? = nil,
        detail: String? = nil,
        includeFlags: Bool = true,
        toxicToPets: Bool = false,
        toxicToChildren: Bool = false,
        fullSunTolerant: Bool = false
    ) throws -> Plant {
        var json: [String: Any] = [
            "id": "plant",
            "name": "Test plant",
            "type": "Plant",
            "imageURLs": [],
            "description": "",
            "translations": [:]
        ]
        if includeFlags {
            json["flags"] = [
                "toxicToPets": toxicToPets,
                "toxicToChildren": toxicToChildren,
                "easyCare": false,
                "shadeTolerant": false,
                "fullSunTolerant": fullSunTolerant,
                "droughtTolerant": false,
                "humidityLoving": false,
                "flowering": false,
                "climbing": false,
                "trailing": false,
                "compact": false,
                "airPurifying": false
            ]
        }
        var profile: [String: Any] = ["schemaVersion": 1]
        let evidence: [String: Any] = [
            "sourceName": "ASPCA Toxic and Non-Toxic Plants",
            "sourceURL": "https://example.test/plant",
            "reviewedAt": "2026-11-06",
            "reliability": "high"
        ]
        if let petToxicity {
            var fact: [String: Any] = ["value": petToxicity, "evidence": evidence]
            if let detail { fact["detail"] = detail }
            profile["petToxicity"] = fact
        }
        if let childToxicity {
            profile["childToxicity"] = ["value": childToxicity, "evidence": evidence]
        }
        if profile.count > 1 {
            json["botanicalProfile"] = profile
        }

        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(Plant.self, from: data)
    }
}
