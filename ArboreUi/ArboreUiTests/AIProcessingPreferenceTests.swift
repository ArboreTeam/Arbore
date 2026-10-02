import XCTest
@testable import ArboreUi

// AIProcessingPreferenceTests — issues #549, #601.
//
// Le réglage « Diagnostic et assistant par IA » a connu deux défauts successifs,
// et ces tests gardent la correction de chacun.
//
// #549 — l'interrupteur était décoratif : `privacy_ai` n'était lu nulle part
// hors de l'écran Confidentialité, et l'éteindre ne changeait rien. Photos et
// messages partaient quand même.
//
// #601 — il était allumé à l'installation, donc un premier scan envoyait une
// photo à un tiers avant que l'utilisateur n'ait rien lu ni rien accordé. App
// Review a refusé la 1.0.0 (2) pour ce motif (directives 5.1.1(i), 5.1.2(i)).
// La porte est désormais fermée jusqu'à ce que la divulgation reçoive réponse.
//
// Ce que ces tests ne doivent PAS laisser dériver : le réglage reste une
// préférence de fonctionnalité et non un consentement RGPD. La base légale est
// le contrat, et le registre des consentements ne doit contenir que des
// consentements — l'autorisation d'Apple est une exigence de plateforme, qui ne
// déplace pas cette frontière.

final class AIProcessingPreferenceTests: XCTestCase {

    private let cle = AIProcessingPreference.storageKey
    private let cleDivulgation = AIProcessingPreference.divulgationKey

    override func setUp() {
        super.setUp()
        nettoyer()
    }

    override func tearDown() {
        nettoyer()
        super.tearDown()
    }

    private func nettoyer() {
        UserDefaults.standard.removeObject(forKey: cle)
        UserDefaults.standard.removeObject(forKey: cleDivulgation)
    }

    // MARK: - La porte : rien ne part avant la divulgation

    /// Le cas exact du refus d'App Review : app fraîchement installée, personne
    /// n'a rien lu, et l'utilisateur lance un scan.
    func testSansDivulgationRienNestAutorise() {
        XCTAssertFalse(AIProcessingPreference.divulgationFaite,
                       "Une app fraîchement installée n'a rien divulgué")
        XCTAssertFalse(AIProcessingPreference.estAutorise,
                       "Aucune photo ne doit pouvoir partir avant que la "
                       + "divulgation n'ait reçu de réponse (5.1.1(i))")
    }

    /// Le point le plus important du lot. Même un réglage explicitement à `true`
    /// ne suffit pas : c'est la divulgation qui commande, sans quoi il resterait
    /// un chemin par lequel des données partent sans que rien n'ait été dit.
    func testUnReglageActifSansDivulgationNautorisePas() {
        UserDefaults.standard.set(true, forKey: cle)
        XCTAssertFalse(AIProcessingPreference.estAutorise,
                       "La divulgation domine le réglage : un `true` hérité ou "
                       + "écrit par erreur ne doit pas ouvrir la porte")
    }

    /// Et le défaut du projet n'est même pas consulté sans divulgation : un
    /// défaut ne vaut autorisation de rien.
    func testLeDefautDuProjetNeContournePasLaDivulgation() {
        XCTAssertFalse(AIProcessingPreference.estAutorise)
        AIProcessingPreference.marquerDivulgationRepondue()
        XCTAssertEqual(AIProcessingPreference.estAutorise, ConsentDefaults.ai,
                       "La divulgation répondue rend la main au défaut déclaré")
    }

    // MARK: - Enregistrement de la réponse

    func testAccepterOuvreLaPorte() {
        AIProcessingPreference.enregistrerReponse(autorise: true)
        XCTAssertTrue(AIProcessingPreference.divulgationFaite)
        XCTAssertTrue(AIProcessingPreference.estAutorise)
    }

    func testRefuserFermeLaPorteMaisRepondALaDivulgation() {
        AIProcessingPreference.enregistrerReponse(autorise: false)
        XCTAssertTrue(AIProcessingPreference.divulgationFaite,
                      "Un refus est une réponse : la feuille ne doit pas revenir")
        XCTAssertFalse(AIProcessingPreference.estAutorise)
    }

    /// Les deux clés sont écrites ensemble. Une divulgation répondue sans
    /// réglage, ou l'inverse, laisserait un état que `estAutorise` ne saurait
    /// pas lire honnêtement.
    func testLaReponseEcritLesDeuxCles() {
        AIProcessingPreference.enregistrerReponse(autorise: true)
        XCTAssertNotNil(UserDefaults.standard.object(forKey: cle))
        XCTAssertEqual(UserDefaults.standard.integer(forKey: cleDivulgation),
                       AIProcessingPreference.versionDivulgation)
    }

    /// `marquerDivulgationRepondue` sert au cas où l'utilisateur actionne
    /// lui-même le réglage depuis l'écran Confidentialité : la ligne qu'il
    /// manipule nomme déjà données et destinataire, donc on ne lui redemande
    /// rien — mais on ne touche pas pour autant à son choix.
    func testMarquerLaDivulgationNeTouchePasAuReglage() {
        UserDefaults.standard.set(false, forKey: cle)
        AIProcessingPreference.marquerDivulgationRepondue()
        XCTAssertTrue(AIProcessingPreference.divulgationFaite)
        XCTAssertFalse(AIProcessingPreference.estAutorise,
                       "Marquer la divulgation ne doit pas allumer le réglage")
    }

    // MARK: - Versionnement

    /// Une divulgation périmée ne vaut plus accord : l'utilisateur avait dit oui
    /// à un autre texte. C'est le mécanisme qui protège le jour où le
    /// fournisseur, le pays d'hébergement ou les données envoyées changent.
    func testUneVersionAnterieureRefermeLaPorte() {
        UserDefaults.standard.set(true, forKey: cle)
        UserDefaults.standard.set(AIProcessingPreference.versionDivulgation - 1,
                                  forKey: cleDivulgation)
        XCTAssertFalse(AIProcessingPreference.divulgationFaite)
        XCTAssertFalse(AIProcessingPreference.estAutorise,
                       "Changer le texte de divulgation doit re-demander l'accord")
    }

    func testLaVersionCouranteEstAuMoinsUn() {
        XCTAssertGreaterThanOrEqual(AIProcessingPreference.versionDivulgation, 1,
                                    "La version 0 serait indiscernable d'une clé absente")
    }

    // MARK: - Les clés

    /// La clé doit rester celle qu'écrit `PrivacySettingsView` via @AppStorage.
    /// Deux clés divergentes rendraient le réglage silencieusement inopérant,
    /// exactement comme avant — sans que rien ne le signale.
    func testLaCleEstCelleDeLEcranConfidentialite() {
        XCTAssertEqual(AIProcessingPreference.storageKey, "privacy_ai",
                       "Changer cette clé sans changer l'@AppStorage de "
                       + "PrivacySettingsView redonnerait un interrupteur décoratif")
    }

    /// Le préfixe n'est pas cosmétique : `LocalDataOwnership` efface les clés
    /// `privacy_*` à la déconnexion. La divulgation doit en faire partie — une
    /// autorisation est personnelle, et le compte suivant sur le même appareil
    /// n'a jamais rien accordé.
    func testLaCleDeDivulgationEstEffaceeALaDeconnexion() {
        XCTAssertTrue(AIProcessingPreference.divulgationKey.hasPrefix("privacy_"),
                      "Sans ce préfixe, l'autorisation d'un compte vaudrait pour le suivant")

        AIProcessingPreference.enregistrerReponse(autorise: true)
        LocalDataOwnership.clearConsentStateOnLogout()
        XCTAssertFalse(AIProcessingPreference.divulgationFaite,
                       "La déconnexion doit refermer la porte")
        XCTAssertFalse(AIProcessingPreference.estAutorise)
    }

    // MARK: - Ce n'est pas un consentement

    /// Le registre des consentements ne doit contenir que des consentements.
    /// La base légale de ces traitements est le contrat (RGPD art. 6(1)(b)) :
    /// l'utilisateur déclenche chaque envoi. Y consigner « ai » suggérerait un
    /// droit de retrait qu'on ne pourrait honorer qu'en supprimant la
    /// fonctionnalité, ce que l'art. 7(3) n'admet pas.
    func testLeReglageNestPasConsigneDansLeRegistreDesConsentements() {
        let types = ConsentDefaults.initialSnapshot.map(\.type)
        XCTAssertFalse(types.contains("ai"),
                       "« ai » est une préférence de fonctionnalité, pas un consentement : "
                       + "il n'a pas sa place dans initialSnapshot")
    }

    /// Les vrais consentements, eux, doivent y rester.
    func testLesVraisConsentementsRestentConsignes() {
        let types = ConsentDefaults.initialSnapshot.map(\.type)
        for attendu in ["analytics", "marketing", "notifications"] {
            XCTAssertTrue(types.contains(attendu),
                          "\(attendu) doit rester dans le registre")
        }
    }

    /// Le défaut est passé à `false` avec #601, et ce test dit pourquoi — pour
    /// qu'on ne le repasse pas à `true` en croyant corriger une régression.
    ///
    /// Ce n'est pas un revirement sur la base légale : c'est qu'App Review exige
    /// l'autorisation avant l'envoi, et qu'afficher « activé » à qui n'a rien lu
    /// serait faux. Le défaut ne gouverne d'ailleurs plus l'envoi — `estAutorise`
    /// est fermé sans divulgation — mais l'affichage de la ligne, qui doit être
    /// exact.
    func testLeDefautEstInactifDepuisLeRefusDAppReview() {
        XCTAssertFalse(ConsentDefaults.ai,
                       "Le réglage doit s'afficher éteint tant que personne n'a "
                       + "été informé : l'afficher allumé serait un énoncé faux")
        XCTAssertFalse(ConsentDefaults.analytics,
                       "Un vrai consentement reste opt-in strict")
        XCTAssertFalse(ConsentDefaults.marketing)
    }
}
