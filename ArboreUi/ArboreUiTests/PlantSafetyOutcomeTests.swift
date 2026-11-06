import XCTest
@testable import ArboreUi

/// Un prédicat unique, et une politique nommée par surface (#783).
///
/// Ce qui précédait : `WizardPlantFilter` mêlait les deux et ne tournait
/// nulle part, `LegacyPlantSuitabilityEvaluator` n'était jamais instancié, et
/// les deux surfaces réellement actives n'appliquaient aucune contrainte de
/// sûreté. Trois lectures des libellés du questionnaire, trois tolérances.
///
/// Un contrôle de sécurité mort est pire qu'un contrôle absent : sa présence se
/// lit comme une couverture. C'est arrivé deux fois — une qualification erronée
/// de « chemin vivant », et une consigne de remplissage qui demandait d'écrire
/// la toxicité dans la prose pour nourrir un filtre qui ne tourne pas.
final class PlantSafetyOutcomeTests: XCTestCase {

    // MARK: - Une seule lecture des libellés du questionnaire

    func testLesLibellesDuQuestionnaireSontReconnus() {
        let animaux = Plant.HouseholdSafetyRequirement(wizardSafety: [SafetyOption.pets.rawValue])
        XCTAssertTrue(animaux.pets)
        XCTAssertFalse(animaux.children)

        let enfants = Plant.HouseholdSafetyRequirement(wizardSafety: [SafetyOption.children.rawValue])
        XCTAssertTrue(enfants.children)
        XCTAssertFalse(enfants.pets)

        let deux = Plant.HouseholdSafetyRequirement(
            wizardSafety: [SafetyOption.pets.rawValue, SafetyOption.children.rawValue]
        )
        XCTAssertTrue(deux.pets)
        XCTAssertTrue(deux.children)
    }

    /// « Aucune contrainte » est une RÉPONSE, pas une absence de réponse.
    func testAucuneContrainteEstUneReponse() {
        let r = Plant.HouseholdSafetyRequirement(wizardSafety: [SafetyOption.none.rawValue])
        XCTAssertTrue(r.isEmpty)
    }

    func testAbsenceDeReponseNExigeRien() {
        XCTAssertTrue(Plant.HouseholdSafetyRequirement(wizardSafety: nil).isEmpty)
        XCTAssertTrue(Plant.HouseholdSafetyRequirement(wizardSafety: []).isEmpty)
    }

    /// Les libellés stockés sont français, mais la lecture ne doit pas en
    /// dépendre : les jardins créés avant un changement de libellé, ou importés,
    /// doivent continuer d'être compris.
    func testLesJetonsAnglaisEtLesAccentsSontTolerees() {
        XCTAssertTrue(Plant.HouseholdSafetyRequirement(wizardSafety: ["pets"]).pets)
        XCTAssertTrue(Plant.HouseholdSafetyRequirement(wizardSafety: ["CHILDREN"]).children)
        XCTAssertTrue(Plant.HouseholdSafetyRequirement(wizardSafety: ["none"]).isEmpty)
        XCTAssertTrue(
            Plant.HouseholdSafetyRequirement(wizardSafety: ["eviter les plantes toxiques pour les ANIMAUX"]).pets,
            "sans accents et en capitales, c'est le même libellé"
        )
    }

    // MARK: - Le prédicat : trois branches, et le pire l'emporte

    func testLeConflitEstConnuEtIncompatible() throws {
        let p = try plant(pet: "toxic")
        XCTAssertEqual(p.safetyOutcome(for: animaux()), .conflict)
    }

    func testLIndetermineNEstNiUnConflitNiUneSatisfaction() throws {
        let p = try plant(pet: "unknown", flags: false)
        XCTAssertEqual(p.safetyOutcome(for: animaux()), .undetermined)
    }

    func testLaSatisfactionDemandeUnFaitConnu() throws {
        let p = try plant(pet: "safe")
        XCTAssertEqual(p.safetyOutcome(for: animaux()), .satisfied)
    }

    /// Deux publics demandés : un conflit sur un seul suffit.
    func testUnConflitSurUnSeulPublicLEmporte() throws {
        let p = try plant(pet: "safe", child: "toxic")
        XCTAssertEqual(p.safetyOutcome(for: animauxEtEnfants()), .conflict)
    }

    /// À défaut de conflit, un seul indéterminé suffit.
    func testUnIndetermineSurUnSeulPublicLEmporteSurLaSatisfaction() throws {
        let p = try plant(pet: "safe", child: "unknown", flags: false)
        XCTAssertEqual(p.safetyOutcome(for: animauxEtEnfants()), .undetermined)
    }

    func testSansContrainteToutEstSatisfait() throws {
        let p = try plant(pet: "toxic")
        let aucune = Plant.HouseholdSafetyRequirement(wizardSafety: nil)
        XCTAssertEqual(
            p.safetyOutcome(for: aucune), .satisfied,
            "rien n'a été demandé, il n'y a rien à honorer"
        )
    }

    // MARK: - Les deux politiques, table de vérité

    func testParcourirMasqueLeConflitEtLaisseVoirLIndetermine() {
        XCTAssertTrue(Plant.HouseholdSafetyPolicy.browsable.admits(.satisfied))
        XCTAssertFalse(Plant.HouseholdSafetyPolicy.browsable.admits(.conflict))
        XCTAssertTrue(
            Plant.HouseholdSafetyPolicy.browsable.admits(.undetermined),
            "l'incertitude est la nôtre : la taire priverait d'un choix sans rien protéger"
        )
    }

    func testProposerMasqueAussiLIndetermine() {
        XCTAssertTrue(Plant.HouseholdSafetyPolicy.offerable.admits(.satisfied))
        XCTAssertFalse(Plant.HouseholdSafetyPolicy.offerable.admits(.conflict))
        XCTAssertFalse(
            Plant.HouseholdSafetyPolicy.offerable.admits(.undetermined),
            "quand on recommande, on engage sa parole"
        )
    }

    /// L'asymétrie entre les deux politiques est le cœur du réglage : elle doit
    /// porter sur l'indéterminé, et sur lui seul.
    func testLesDeuxPolitiquesNeDifferentQueSurLIndetermine() {
        for cas in [Plant.SafetyOutcome.satisfied, .conflict] {
            XCTAssertEqual(
                Plant.HouseholdSafetyPolicy.browsable.admits(cas),
                Plant.HouseholdSafetyPolicy.offerable.admits(cas),
                "les politiques ne doivent differer que sur .undetermined"
            )
        }
        XCTAssertNotEqual(
            Plant.HouseholdSafetyPolicy.browsable.admits(.undetermined),
            Plant.HouseholdSafetyPolicy.offerable.admits(.undetermined)
        )
    }

    // MARK: - La régression trouvée en appliquant le principe

    /// `isRecommended` ne suffisait pas comme barriere.
    ///
    /// Une toxicite non etablie n'ajoute qu'une cle `missing` sans critere : le
    /// niveau tombe a `.needsReview`, mais `isRecommended` accepte
    /// `.needsReview` des 0,55 de score. Une plante aux autres axes solides et
    /// a la toxicite INCONNUE pouvait donc etre recommandee a un foyer qui
    /// avait demande l'inverse.
    func testLeMoteurNeProposeJamaisUneToxiciteNonEtablie() throws {
        var wizard = jardinEnsoleille()
        wizard.safety = [SafetyOption.pets.rawValue]
        let inconnue = try plant(pet: "unknown", flags: false, id: "inconnue")

        let suggestion = GardenSuggestionEngine().suggest(from: wizard, plants: [inconnue])

        XCTAssertFalse(
            suggestion.plants.contains { $0.plant.id == "inconnue" },
            "une toxicité non établie ne doit jamais être proposée quand la sûreté a été demandée"
        )
    }

    func testLeMoteurNeProposeJamaisUnConflit() throws {
        var wizard = jardinEnsoleille()
        wizard.safety = [SafetyOption.pets.rawValue]
        let toxique = try plant(pet: "toxic", id: "toxique")

        let suggestion = GardenSuggestionEngine().suggest(from: wizard, plants: [toxique])

        XCTAssertFalse(suggestion.plants.contains { $0.plant.id == "toxique" })
    }

    /// Sans contrainte declaree, la barriere ne doit rien retirer : le moteur
    /// retrouve son comportement d'avant.
    func testSansContrainteLaBarriereNeRetireRien() throws {
        let inconnue = try plant(pet: "unknown", flags: false, id: "inconnue")
        let contrainte = Plant.HouseholdSafetyRequirement(wizardSafety: nil)
        XCTAssertTrue(inconnue.isAdmitted(by: .offerable, requirement: contrainte))
    }

    // MARK: - Fixtures

    private func animaux() -> Plant.HouseholdSafetyRequirement {
        Plant.HouseholdSafetyRequirement(wizardSafety: [SafetyOption.pets.rawValue])
    }

    private func animauxEtEnfants() -> Plant.HouseholdSafetyRequirement {
        Plant.HouseholdSafetyRequirement(
            wizardSafety: [SafetyOption.pets.rawValue, SafetyOption.children.rawValue]
        )
    }

    private func jardinEnsoleille() -> GardenWizardDTO {
        GardenWizardDTO(
            style: "",
            spaceType: GardenSpaceType.garden.rawValue,
            exposure: nil,
            maintenance: nil,
            safety: nil,
            soil: nil,
            scanMethod: nil,
            siteProfile: GardenSiteProfileDTO(
                sunlight: GardenSunlightDTO(
                    minimumHours: 6,
                    maximumHours: 8,
                    metadata: GardenValueMetadataDTO(source: .declared, confidence: .high)
                )
            )
        )
    }

    private func plant(
        pet: String? = nil,
        child: String? = nil,
        flags: Bool = true,
        id: String = "plant"
    ) throws -> Plant {
        var json: [String: Any] = [
            "id": id,
            "name": "Test plant",
            "type": "Plant",
            "imageURLs": [],
            "description": "",
            "translations": [:],
        ]
        if flags {
            json["flags"] = [
                "toxicToPets": pet == "toxic",
                "toxicToChildren": child == "toxic",
                "easyCare": true,
                "shadeTolerant": false,
                "fullSunTolerant": true,
                "droughtTolerant": false,
                "humidityLoving": false,
                "flowering": false,
                "climbing": false,
                "trailing": false,
                "compact": false,
                "airPurifying": false,
            ]
        }
        let provenance: [String: Any] = [
            "sourceName": "ASPCA Toxic and Non-Toxic Plants",
            "sourceURL": "https://example.test/plant",
            "reviewedAt": "2026-11-06",
            "reliability": "high",
        ]
        var profil: [String: Any] = ["schemaVersion": 1]
        if let pet { profil["petToxicity"] = ["value": pet, "evidence": provenance] }
        if let child { profil["childToxicity"] = ["value": child, "evidence": provenance] }
        if profil.count > 1 { json["botanicalProfile"] = profil }

        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(Plant.self, from: data)
    }
}
