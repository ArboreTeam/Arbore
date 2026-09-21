import XCTest
@testable import ArboreUi

// AIProcessingPreferenceTests — issue #549.
//
// Le réglage « Diagnostic et assistant par IA » a longtemps été un interrupteur
// décoratif : `privacy_ai` n'était lu nulle part hors de l'écran
// Confidentialité, et l'éteindre ne changeait rien. Photos et messages
// partaient quand même.
//
// Ces tests gardent les deux propriétés qui rendent le réglage honnête : il est
// bien lu, et il n'est pas consigné comme un consentement — la base légale de
// ces traitements étant le contrat, pas le consentement.

final class AIProcessingPreferenceTests: XCTestCase {

    private let cle = AIProcessingPreference.storageKey

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: cle)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: cle)
        super.tearDown()
    }

    // MARK: - Lecture du réglage

    /// Clé absente : la fonctionnalité est proposée d'emblée. Qui la coupe le
    /// fait sciemment.
    func testSansValeurEnregistreeOnSuitLeDefautDuProjet() {
        XCTAssertEqual(AIProcessingPreference.estAutorise, ConsentDefaults.ai,
                       "Sans valeur enregistrée, le réglage doit valoir le défaut déclaré")
    }

    func testUneValeurExpliciteEstRespectee() {
        UserDefaults.standard.set(false, forKey: cle)
        XCTAssertFalse(AIProcessingPreference.estAutorise,
                       "Éteindre le réglage doit se voir — c'était tout le défaut de #549")

        UserDefaults.standard.set(true, forKey: cle)
        XCTAssertTrue(AIProcessingPreference.estAutorise)
    }

    /// La clé doit rester celle qu'écrit `PrivacySettingsView` via @AppStorage.
    /// Deux clés divergentes rendraient le réglage silencieusement inopérant,
    /// exactement comme avant — sans que rien ne le signale.
    func testLaCleEstCelleDeLEcranConfidentialite() {
        XCTAssertEqual(AIProcessingPreference.storageKey, "privacy_ai",
                       "Changer cette clé sans changer l'@AppStorage de "
                       + "PrivacySettingsView redonnerait un interrupteur décoratif")
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

    /// Le défaut reste `true` : la fonctionnalité est proposée à l'installation.
    /// Ce n'est pas un consentement, donc le principe d'opt-in strict ne
    /// s'applique pas — contrairement à `analytics` et `marketing`.
    func testLeDefautResteActifContrairementAuxConsentements() {
        XCTAssertTrue(ConsentDefaults.ai,
                      "Une préférence de fonctionnalité contractuelle est active par défaut")
        XCTAssertFalse(ConsentDefaults.analytics,
                       "Un vrai consentement reste opt-in strict")
        XCTAssertFalse(ConsentDefaults.marketing)
    }
}
