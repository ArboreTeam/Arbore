import XCTest
@testable import ArboreUi

// GardenSuggestionCategoryTests — issue #792.
//
// Chaque test affirme la plante attendue ET son score. Un moteur qui suggère
// la bonne plante pour la mauvaise raison est un moteur qu'on ne peut pas
// corriger : si seul l'identifiant était vérifié, un changement de barème
// passerait inaperçu jusqu'au jour où il inverse un classement.
//
// `classifyPlant` concaténait le nom, le type et la description TRADUITE, puis
// y cherchait des mots-clés. Conséquence mesurée sur le catalogue : `mousse`
// appariait « tuteur mousse », donc le Monstera sur tuteur était classé
// couvre-sol. Elle lit désormais `kinds`, `goals` et `size`.

final class GardenSuggestionCategoryTests: XCTestCase {

    /// Le barème, calculé à la main depuis le code, pour qu'un changement se
    /// voie ici et pas en production.
    ///
    /// Avec le questionnaire de ces tests, une fiche complète valide deux
    /// critères à 1,0 (milieu et exposition) et laisse un seul trou
    /// (`AR_CATALOG_MISSING_AVAILABLE_WIDTH`, aucune zone de plantation
    /// déclarée). Donc `score = 1,0`, `level = .needsReview`, puis dans le
    /// moteur : `1,0 × 0,78 − 1 × 0,025`.
    private let scoreFicheComplete = 0.755

    /// Une fiche sans `environments` perd le critère de milieu et gagne un
    /// second trou : `1,0 × 0,78 − 2 × 0,025`.
    private let scoreFicheSansMilieu = 0.73

    // MARK: - Le cas réel : « tuteur mousse »

    /// Le Monstera sur tuteur mousse n'est plus classé COUVRE-SOL.
    ///
    /// Son nom contient « mousse », et c'est tout ce qu'il fallait à l'ancienne
    /// classification. Ses valeurs closes disent « plante verte, gabarit
    /// moyen » : son rôle de composition est donc `.medium`.
    func testLeMonsteraSurTuteurMousseNEstPlusClasseCouvreSol() throws {
        let monstera = try plante(
            id: "monstera-tuteur",
            nom: "Monstera Deliciosa Pot Tuteur Mousse",
            type: "Plante verte d'interieur",
            kinds: ["greenPlant"],
            size: "medium"
        )

        let suggestion = moteur().suggest(from: questionnaire(), plants: [monstera])

        XCTAssertEqual(suggestion.plants.count, 1)
        XCTAssertEqual(suggestion.plants.first?.id, "monstera-tuteur")
        XCTAssertEqual(suggestion.plants.first?.category, .medium,
                       "« mousse » dans le nom ne doit plus produire un couvre-sol")
        XCTAssertEqual(suggestion.plants.first?.score ?? 0, scoreFicheComplete, accuracy: 0.0005)
    }

    /// Et le couvre-sol véritable, lui, l'est — sinon le test ci-dessus
    /// passerait aussi avec une fonction qui ne saurait rien classer.
    func testUnVraiCouvreSolEstClasseCouvreSol() throws {
        let couvreSol = try plante(
            id: "vrai-couvre-sol",
            nom: "Fiche sans aucun mot-cle dans son nom",
            type: "Vivace tapissante",
            kinds: ["groundcover"],
            size: "small"
        )

        let suggestion = moteur().suggest(from: questionnaire(), plants: [couvreSol])

        XCTAssertEqual(suggestion.plants.first?.category, .groundCover)
        XCTAssertEqual(suggestion.plants.first?.score ?? 0, scoreFicheComplete, accuracy: 0.0005)
    }

    // MARK: - Les cinq rôles, avec leur score

    /// Cinq plantes, cinq rôles, et le score exact de chacune.
    ///
    /// Les types sont distincts à dessein : la règle de diversité du moteur
    /// n'accepte que deux fiches du même `type`, et les confondre masquerait
    /// trois des cinq rôles.
    func testLesCinqRolesEtLeursScores() throws {
        let catalogue = [
            try plante(id: "arbre", type: "Arbre", kinds: ["tree"], size: "large"),
            try plante(id: "grimpante", type: "Grimpante", kinds: ["climbing"], size: "medium"),
            try plante(id: "tapissante", type: "Tapissante", kinds: ["groundcover"], size: "small"),
            try plante(id: "succulente", type: "Succulente", kinds: ["cactusSucculent"], size: "small"),
            try plante(id: "verte", type: "Plante verte", kinds: ["greenPlant"], size: "medium")
        ]

        let suggestion = moteur().suggest(from: questionnaire(), plants: catalogue)

        let roles: [String: SuggestedPlant.PlantCategory] = Dictionary(
            uniqueKeysWithValues: suggestion.plants.map { ($0.id, $0.category) }
        )
        XCTAssertEqual(roles, [
            "arbre": .tall,
            "grimpante": .climbing,
            "tapissante": .groundCover,
            "succulente": .low,
            "verte": .medium
        ])

        for proposee in suggestion.plants {
            XCTAssertEqual(proposee.score, scoreFicheComplete, accuracy: 0.0005,
                           "\(proposee.id) doit porter le score d'une fiche complète")
        }
    }

    /// Un conifère est une plante HAUTE, et `conifer` est entré au vocabulaire
    /// avec #792 : avant, la typologie n'avait aucune cible et 39 fiches
    /// tombaient dans le défaut `.medium`.
    func testUnConifereEstClasseHaut() throws {
        let conifere = try plante(id: "conifere", type: "Conifere", kinds: ["conifer"], size: "large")

        let suggestion = moteur().suggest(from: questionnaire(), plants: [conifere])

        XCTAssertEqual(suggestion.plants.first?.category, .tall)
    }

    // MARK: - Le classement, et sa raison

    /// Deux fiches, deux scores, et l'ordre qui en découle.
    ///
    /// La seconde n'a pas de `environments` : elle perd un critère et gagne un
    /// trou. L'écart — 0,755 contre 0,73 — n'est pas une opinion, c'est le
    /// barème, et il est affirmé chiffre en main.
    func testLeClassementSuitLesScoresEtLesScoresSontAffirmes() throws {
        let complete = try plante(id: "complete", type: "Complete", kinds: ["greenPlant"], size: "medium")
        let sansMilieu = try plante(
            id: "sans-milieu", type: "Partielle",
            kinds: ["greenPlant"], size: "medium",
            avecEnvironments: false
        )

        let suggestion = moteur().suggest(from: questionnaire(), plants: [sansMilieu, complete])

        XCTAssertEqual(suggestion.plants.map(\.id), ["complete", "sans-milieu"],
                       "La fiche la mieux documentée passe devant")
        XCTAssertEqual(suggestion.plants[0].score, scoreFicheComplete, accuracy: 0.0005)
        XCTAssertEqual(suggestion.plants[1].score, scoreFicheSansMilieu, accuracy: 0.0005)
    }

    /// Une prose et un nom MENTEURS ne déplacent ni le rôle ni le score.
    ///
    /// C'est le garde-fou de l'issue appliqué au moteur : les deux fiches
    /// portent les mêmes valeurs closes et des textes opposés.
    func testUneProseMenteuseNeChangeNiLeRoleNiLeScore() throws {
        let nue = try plante(id: "nue", type: "Nue", kinds: ["greenPlant"], size: "medium")
        let menteuse = try plante(
            id: "menteuse",
            nom: "Grand arbre palmier grimpant lierre couvre-sol mousse cactus",
            type: "Nue",
            kinds: ["greenPlant"], size: "medium",
            prose: "A tall climbing tree, a trailing ivy groundcover, moss and cactus."
        )

        let suggestion = moteur().suggest(from: questionnaire(), plants: [nue, menteuse])

        XCTAssertEqual(suggestion.plants.count, 2)
        let categories = Set(suggestion.plants.map(\.category))
        XCTAssertEqual(categories, [.medium],
                       "Les deux fiches doivent occuper le même rôle : leurs valeurs closes sont identiques")
        for proposee in suggestion.plants {
            XCTAssertEqual(proposee.score, scoreFicheComplete, accuracy: 0.0005)
        }
    }

    // MARK: - Ce que le moteur refuse toujours de proposer

    /// Un conflit d'exposition reste une exclusion dure, avant tout classement.
    func testUneFicheEnConflitDExpositionNEstPasProposee() throws {
        let conflit = try plante(
            id: "conflit", type: "Conflit",
            kinds: ["cactusSucculent"], size: "small",
            heuresDeSoleil: (8, 12)
        )

        let suggestion = moteur().suggest(from: questionnaire(), plants: [conflit])

        XCTAssertTrue(suggestion.plants.isEmpty,
                      "Une plante qui exige 8 h de soleil dans un lieu qui en offre 3 "
                      + "n'est pas une suggestion")
    }

    // MARK: - Fabrique

    private func moteur() -> GardenSuggestionEngine {
        GardenSuggestionEngine(targetPlantCount: 7)
    }

    /// Questionnaire volontairement minimal : intérieur, 1 à 3 heures de
    /// soleil, aucune contrainte de sûreté, aucune réponse conditionnelle.
    /// Deux critères s'évaluent, un seul trou subsiste — ce qui rend le score
    /// calculable à la main.
    private func questionnaire() -> GardenWizardDTO {
        GardenWizardDTO(
            style: "",
            spaceType: GardenSpaceType.interior.rawValue,
            exposure: nil,
            maintenance: nil,
            safety: nil,
            soil: nil,
            scanMethod: nil,
            siteProfile: GardenSiteProfileDTO(
                sunlight: GardenSunlightDTO(
                    minimumHours: 1,
                    maximumHours: 3,
                    metadata: GardenValueMetadataDTO(source: .declared, confidence: .high)
                )
            )
        )
    }

    private func plante(
        id: String,
        nom: String? = nil,
        type: String = "Plant",
        kinds: [String],
        size: String,
        heuresDeSoleil: (Double, Double) = (0, 3),
        avecEnvironments: Bool = true,
        prose: String = ""
    ) throws -> Plant {
        var profil: [String: Any] = [
            "schemaVersion": 1,
            "directSunHours": plage(heuresDeSoleil.0, heuresDeSoleil.1, "hours/day"),
            "kinds": ["value": kinds, "evidence": preuve()],
            "size": ["value": size, "evidence": preuve()]
        ]
        if avecEnvironments {
            profil["environments"] = ["value": ["indoor"], "evidence": preuve()]
        }

        let traduction: [String: Any] = [
            "description": prose,
            "plantType": type
        ]

        let json: [String: Any] = [
            "id": id,
            "name": nom ?? "Plante \(id)",
            "type": type,
            "imageURLs": [],
            "description": prose,
            "translations": ["fr": traduction, "en": traduction],
            "botanicalProfile": profil
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(Plant.self, from: data)
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
