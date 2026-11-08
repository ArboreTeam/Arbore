import XCTest
@testable import ArboreUi

/// Les cas de référence partagés avec le backend (#792).
///
/// `fixtures/plant-traits.json` est lu ici ET par `plant_traits_fixture_test.go`.
/// Swift et Go ne peuvent pas partager une implémentation ; ils peuvent partager
/// une VÉRITÉ. Si les deux côtés affirment les mêmes verdicts sur les mêmes
/// fiches, ils ne peuvent pas diverger sans qu'un test le dise.
///
/// Deux cas de ce fichier sont les gardes anti-régression de l'issue :
/// `prose_qui_ment`, dont le texte affirme une innocuité que son verdict
/// contredit, et `nom_qui_ment`, dont le nom contient un mot-clé qui la
/// classait autrefois par appariement. Tant qu'ils passent, aucune décision de
/// sûreté ne vient du texte.
final class PlantTraitsFixtureTests: XCTestCase {

    // MARK: - Lecture du fichier partagé

    /// Le chemin vient de `#filePath` et non du bundle : la fixture est une
    /// source partagée avec Go, pas une ressource de l'app. L'embarquer dans le
    /// bundle en ferait une copie, et une copie diverge.
    private static func cheminFixture() throws -> URL {
        let test = URL(fileURLWithPath: #filePath)        // …/ArboreUi/ArboreUiTests/<ce fichier>
        let racine = test
            .deletingLastPathComponent()                   // ArboreUiTests
            .deletingLastPathComponent()                   // ArboreUi
            .deletingLastPathComponent()                   // racine du dépôt
        let fixture = racine.appendingPathComponent("fixtures/plant-traits.json")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("fixtures/plant-traits.json introuvable à \(fixture.path)")
        }
        return fixture
    }

    private struct Cas: Decodable {
        let id: String
        let nom: String
        let pourquoi: String
        let profil: [String: JSONValeur]?
        let flags: [String: Bool]?
        let prose: [String: String]?
        let attendu: Attendu

        struct Attendu: Decodable {
            let verdictPet: String?
            let verdictChild: String?
            let issue: [String: String]
            let admis: [String: Bool]
        }
    }

    /// Décodage lâche : la fixture porte des structures hétérogènes qu'on
    /// réinjecte telles quelles dans le JSON de la plante.
    private enum JSONValeur: Decodable {
        case chaine(String), nombre(Double), booleen(Bool)
        case objet([String: JSONValeur]), tableau([JSONValeur]), nul

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .nul }
            else if let v = try? c.decode(Bool.self) { self = .booleen(v) }
            else if let v = try? c.decode(Double.self) { self = .nombre(v) }
            else if let v = try? c.decode(String.self) { self = .chaine(v) }
            else if let v = try? c.decode([JSONValeur].self) { self = .tableau(v) }
            else { self = .objet(try c.decode([String: JSONValeur].self)) }
        }

        var brut: Any {
            switch self {
            case .chaine(let v): return v
            case .nombre(let v): return v == v.rounded() ? Int(v) : v
            case .booleen(let v): return v
            case .nul: return NSNull()
            case .tableau(let v): return v.map(\.brut)
            case .objet(let v): return v.mapValues(\.brut)
            }
        }
    }

    private struct Fixture: Decodable {
        let contraintes: [String]
        let plantes: [Cas]
    }

    private static func charger() throws -> Fixture {
        let data = try Data(contentsOf: try cheminFixture())
        return try JSONDecoder().decode(Fixture.self, from: data)
    }

    // MARK: - Construction d'une plante depuis un cas

    private func plante(_ cas: Cas) throws -> Plant {
        var json: [String: Any] = [
            "id": cas.id,
            "name": cas.nom,
            "type": "Plant",
            "imageURLs": [],
            "description": cas.prose?["en"] ?? "",
            "translations": traductions(cas),
        ]
        if let flags = cas.flags {
            // Les douze champs sont requis par le décodeur ; la fixture n'en
            // nomme que ceux qui comptent pour le cas.
            var complets: [String: Bool] = [
                "toxicToPets": false, "toxicToChildren": false, "easyCare": false,
                "shadeTolerant": false, "fullSunTolerant": false, "droughtTolerant": false,
                "humidityLoving": false, "flowering": false, "climbing": false,
                "trailing": false, "compact": false, "airPurifying": false,
            ]
            for (k, v) in flags { complets[k] = v }
            json["flags"] = complets
        }
        if let profil = cas.profil {
            json["botanicalProfile"] = profil.mapValues(\.brut)
        }
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(Plant.self, from: data)
    }

    /// La prose du cas est injectée dans TOUTES les langues servies : si une
    /// décision dépendait du texte, elle se verrait ici quelle que soit la
    /// locale de lecture.
    private func traductions(_ cas: Cas) -> [String: Any] {
        guard let prose = cas.prose else { return [:] }
        var out: [String: Any] = [:]
        for langue in ["fr", "en", "es", "de"] {
            out[langue] = [
                "description": prose[langue] ?? prose["en"] ?? "",
                "plantType": prose[langue] ?? prose["en"] ?? "",
            ]
        }
        return out
    }

    private func exigence(_ nom: String) -> Plant.HouseholdSafetyRequirement {
        switch nom {
        case "animaux": return .init(pets: true, children: false)
        case "enfants": return .init(pets: false, children: true)
        case "les_deux": return .init(pets: true, children: true)
        default: return .init(pets: false, children: false)
        }
    }

    /// `ToxicityVerdict` n'est pas adossé à `String` : il n'a que deux cas, et
    /// `irritant` y est volontairement confondu avec `toxic` — les sources les
    /// distinguent, le foyer non. La fixture écrit la valeur STOCKÉE ; on la
    /// ramène ici au verdict rendu au lecteur.
    private func verdictAttendu(_ stocke: String?) -> Plant.ToxicityVerdict? {
        switch stocke {
        case "safe": return .safe
        case "toxic", "irritant": return .toxic
        default: return nil
        }
    }

    private func nom(_ v: Plant.ToxicityVerdict?) -> String {
        switch v {
        case .safe: return "safe"
        case .toxic: return "toxic"
        case nil: return "<non établi>"
        }
    }

    private func issue(_ nom: String) -> Plant.SafetyOutcome {
        switch nom {
        case "conflict": return .conflict
        case "undetermined": return .undetermined
        default: return .satisfied
        }
    }

    // MARK: - Le fichier lui-même

    func testChaqueCasDitCeQuIlProuve() throws {
        for cas in try Self.charger().plantes {
            XCTAssertFalse(
                cas.pourquoi.trimmingCharacters(in: .whitespaces).isEmpty,
                "le cas « \(cas.id) » ne dit pas ce qu'il protège"
            )
        }
    }

    func testLesDeuxGardesAntiRegressionSontPresentes() throws {
        let ids = Set(try Self.charger().plantes.map(\.id))
        XCTAssertTrue(ids.contains("prose_qui_ment"),
                      "sans ce cas, rien ne prouve qu'on ne lit plus la prose")
        XCTAssertTrue(ids.contains("nom_qui_ment"),
                      "sans ce cas, rien ne prouve qu'on ne lit plus le nom")
    }

    // MARK: - Les verdicts stockés

    func testLesVerdictsSontCeuxQueLaFixtureAffirme() throws {
        for cas in try Self.charger().plantes {
            let p = try plante(cas)
            XCTAssertEqual(
                p.petToxicity(), verdictAttendu(cas.attendu.verdictPet),
                "axe animal de « \(cas.id) » : \(nom(p.petToxicity())), "
                + "attendu \(nom(verdictAttendu(cas.attendu.verdictPet))) — \(cas.pourquoi)"
            )
            XCTAssertEqual(
                p.childToxicity(), verdictAttendu(cas.attendu.verdictChild),
                "axe enfant de « \(cas.id) » : \(nom(p.childToxicity())), "
                + "attendu \(nom(verdictAttendu(cas.attendu.verdictChild))) — \(cas.pourquoi)"
            )
        }
    }

    // MARK: - Le prédicat, sur les quatre contraintes

    func testLePredicatRendCeQueLaFixtureAffirme() throws {
        let f = try Self.charger()
        for cas in f.plantes {
            let p = try plante(cas)
            for contrainte in f.contraintes {
                guard let attendu = cas.attendu.issue[contrainte] else {
                    XCTFail("le cas « \(cas.id) » ne couvre pas la contrainte « \(contrainte) »")
                    continue
                }
                XCTAssertEqual(
                    p.safetyOutcome(for: exigence(contrainte)), issue(attendu),
                    "« \(cas.id) » sous contrainte « \(contrainte) » — \(cas.pourquoi)"
                )
            }
        }
    }

    // MARK: - Les deux politiques

    func testLesPolitiquesAdmettentCeQueLaFixtureAffirme() throws {
        for cas in try Self.charger().plantes {
            let p = try plante(cas)
            for (cle, attendu) in cas.attendu.admis {
                let morceaux = cle.split(separator: "_", maxSplits: 1).map(String.init)
                guard morceaux.count == 2 else { continue }
                let politique: Plant.HouseholdSafetyPolicy =
                    morceaux[0] == "offerable" ? .offerable : .browsable
                XCTAssertEqual(
                    p.isAdmitted(by: politique, requirement: exigence(morceaux[1])),
                    attendu,
                    "« \(cas.id) » · \(cle) — \(cas.pourquoi)"
                )
            }
        }
    }

    // MARK: - Ce qui ne doit JAMAIS arriver

    /// La propriété de sûreté, affirmée directement et non déduite de la
    /// fixture : aucune plante dont un axe exigé est toxique ou non établi ne
    /// doit être PROPOSÉE. Ce test tomberait même si la fixture se trompait.
    func testAucunePlanteNonSureNEstJamaisProposee() throws {
        for cas in try Self.charger().plantes {
            let p = try plante(cas)
            for contrainte in ["animaux", "enfants", "les_deux"] {
                let e = exigence(contrainte)
                let verdicts = [
                    e.pets ? p.petToxicity() : .safe,
                    e.children ? p.childToxicity() : .safe,
                ]
                let sûre = verdicts.allSatisfy { $0 == .safe }
                if !sûre {
                    XCTAssertFalse(
                        p.isAdmitted(by: .offerable, requirement: e),
                        "« \(cas.id) » est PROPOSÉE sous « \(contrainte) » alors que son verdict ne le permet pas"
                    )
                }
            }
        }
    }

    /// L'asymétrie entre les deux politiques est un CHOIX, et il doit se
    /// vérifier : tout ce que `offerable` admet, `browsable` l'admet aussi.
    /// L'inverse est faux, et c'est voulu.
    func testToutCeQuiEstProposableEstParcourable() throws {
        for cas in try Self.charger().plantes {
            let p = try plante(cas)
            for contrainte in ["aucune", "animaux", "enfants", "les_deux"] {
                let e = exigence(contrainte)
                if p.isAdmitted(by: .offerable, requirement: e) {
                    XCTAssertTrue(
                        p.isAdmitted(by: .browsable, requirement: e),
                        "« \(cas.id) » est proposable mais pas parcourable sous « \(contrainte) »"
                    )
                }
            }
        }
    }

    /// Sans contrainte déclarée, aucune plante n'est jamais écartée pour
    /// raison de sûreté — y compris les toxiques. L'utilisateur n'a rien demandé.
    func testSansContrainteAucunePlanteNEstEcartee() throws {
        let aucune = Plant.HouseholdSafetyRequirement(pets: false, children: false)
        for cas in try Self.charger().plantes {
            let p = try plante(cas)
            XCTAssertTrue(p.isAdmitted(by: .browsable, requirement: aucune), cas.id)
            XCTAssertTrue(p.isAdmitted(by: .offerable, requirement: aucune), cas.id)
        }
    }

    // MARK: - La prose et le nom ne décident de rien

    /// Le garde anti-régression de l'issue, affirmé explicitement.
    func testUneProseRassuranteNeRendPasUnePlanteProposable() throws {
        guard let cas = try Self.charger().plantes.first(where: { $0.id == "prose_qui_ment" }) else {
            return XCTFail("cas « prose_qui_ment » absent de la fixture")
        }
        let p = try plante(cas)

        // La prose est bien là, dans les quatre langues, et elle affirme l'inverse.
        for langue in ["fr", "en", "es", "de"] {
            let texte = (p.translations[langue]?.description ?? "").lowercased()
            XCTAssertFalse(texte.isEmpty, "la prose doit être présente en \(langue) pour que le test ait un sens")
        }
        XCTAssertTrue(
            (p.translations["en"]?.description ?? "").lowercased().contains("non-toxic"),
            "la prose anglaise doit affirmer l'innocuité, sinon ce test ne prouve rien"
        )

        // Et elle ne change rien.
        XCTAssertNil(p.petToxicity())
        XCTAssertNil(p.childToxicity())
        for contrainte in ["animaux", "enfants", "les_deux"] {
            XCTAssertFalse(
                p.isAdmitted(by: .offerable, requirement: exigence(contrainte)),
                "la prose a rendu « prose_qui_ment » proposable sous « \(contrainte) »"
            )
        }
    }
}
