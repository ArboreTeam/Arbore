import XCTest
@testable import ArboreUi

// ConsentDocumentVersionTests — issue #841, tâche 4.
//
// Le registre des consentements horodatait TOUTES ses entrées avec
// `AppConfig.privacyPolicyVersion`, y compris le consentement `terms`. Une
// acceptation des CGU se retrouvait donc estampillée de la version de la
// politique de confidentialité — « 2.5 » quand les CGU en étaient à la 2.3.
//
// Le défaut ne cassait rien de visible : le backend accepte `version` comme
// chaîne libre et n'exige qu'elle soit non vide (`recordConsent`, main.go).
// Il vidait en revanche la preuve de son sens. Une preuve de consentement qui
// désigne la version d'un autre document ne prouve pas ce qu'elle prétend
// prouver, et c'est l'accountability de l'Art. 5(2) qui tombe avec elle.
//
// Ces tests verrouillent l'appariement document ↔ version. Ils ne vérifient
// pas que l'envoi réseau a lieu : `recordInitialConsents` est un effet de
// bord sans valeur de retour, et le point qui se trompait était le choix de
// la version, pas l'envoi.

final class ConsentDocumentVersionTests: XCTestCase {

    /// Le cas qui était faux.
    func testLeConsentementAuxCGUPorteLaVersionDesCGU() {
        XCTAssertEqual(
            AppConfig.documentVersion(forConsentType: "terms"),
            AppConfig.termsVersion
        )
    }

    /// Et la preuve ne vaut que si les deux versions sont distinguables :
    /// tant qu'elles diffèrent, le test ci-dessus a un contenu. Si un jour
    /// elles coïncident, ce test tombera et dira pourquoi plutôt que de
    /// laisser le précédent devenir une tautologie silencieuse.
    func testLesDeuxDocumentsNePortentPasLaMemeVersion() {
        XCTAssertNotEqual(
            AppConfig.termsVersion,
            AppConfig.privacyPolicyVersion,
            "Si les deux documents portent la même version, "
            + "testLeConsentementAuxCGUPorteLaVersionDesCGU ne prouve plus rien."
        )
    }

    func testLeConsentementALaPolitiquePorteLaVersionDeLaPolitique() {
        XCTAssertEqual(
            AppConfig.documentVersion(forConsentType: "privacy"),
            AppConfig.privacyPolicyVersion
        )
    }

    /// Les consentements granulaires relèvent de la politique : c'est elle qui
    /// décrit ces traitements. Leur rattachement ne doit pas dériver vers les
    /// CGU par inadvertance.
    func testLesConsentementsGranulairesRelevantDeLaPolitique() {
        for entree in ConsentDefaults.initialSnapshot {
            XCTAssertEqual(
                AppConfig.documentVersion(forConsentType: entree.type),
                AppConfig.privacyPolicyVersion,
                "Le consentement '\(entree.type)' doit porter la version de la politique."
            )
        }
    }

    /// Un type inconnu ne doit pas rendre une chaîne vide : le backend
    /// refuserait l'entrée par un 400, et la preuve serait simplement perdue.
    func testUnTypeInconnuRetombeSurLaPolitiqueEtJamaisSurLeVide() {
        let version = AppConfig.documentVersion(forConsentType: "un_type_qui_nexiste_pas")
        XCTAssertEqual(version, AppConfig.privacyPolicyVersion)
        XCTAssertFalse(version.isEmpty)
    }

    /// Les deux versions doivent exister et être non vides, sans quoi tout
    /// `POST /consents` part avec un `version` vide et se fait refuser.
    func testLesDeuxVersionsSontRenseignees() {
        XCTAssertFalse(AppConfig.termsVersion.isEmpty)
        XCTAssertFalse(AppConfig.privacyPolicyVersion.isEmpty)
    }
}
