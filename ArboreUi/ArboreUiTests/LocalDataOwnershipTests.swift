import XCTest
@testable import ArboreUi

// LocalDataOwnershipTests.swift — issue #394.
//
// Le risque couvert n'est pas seulement « un invité voit un jardin ». C'est
// surtout la tentation inverse : régler le problème en supprimant les fichiers
// à la déconnexion. Les scènes AR n'existent QUE sur l'appareil — le serveur ne
// stocke que les métadonnées — donc une purge détruirait le seul exemplaire.
//
// Ces tests portent donc autant sur ce qui doit être masqué que sur ce qui doit
// survivre.

final class LocalDataOwnershipTests: XCTestCase {

    private let identifier = "garden-under-test"

    override func setUp() {
        super.setUp()
        LocalDataOwnership.forget(identifier)
    }

    override func tearDown() {
        LocalDataOwnership.forget(identifier)
        super.tearDown()
    }

    // MARK: - Table de propriété

    func testUnknownIdentifierHasNoOwner() {
        XCTAssertNil(LocalDataOwnership.owner(of: identifier))
    }

    /// `forget` doit être idempotent : il est appelé à chaque suppression de
    /// jardin, y compris pour des jardins jamais attribués.
    func testForgetIsIdempotent() {
        LocalDataOwnership.forget(identifier)
        LocalDataOwnership.forget(identifier)
        XCTAssertNil(LocalDataOwnership.owner(of: identifier))
    }

    /// Sans session, rien n'est visible. Un écran affiché avant la fin de
    /// l'initialisation Firebase ne doit pas exposer le contenu du compte
    /// précédent.
    func testNothingIsVisibleWithoutASession() {
        XCTAssertNil(LocalDataOwnership.currentUID,
                     "test à exécuter hors session authentifiée")
        XCTAssertFalse(LocalDataOwnership.isVisibleInCurrentSession(identifier))
    }

    /// Sans session, `claim` ne doit rien écrire — sinon un identifiant serait
    /// attribué à personne et deviendrait définitivement invisible.
    func testClaimWithoutSessionWritesNothing() {
        LocalDataOwnership.claim(identifier)
        XCTAssertNil(LocalDataOwnership.owner(of: identifier))
    }

    // MARK: - Consentements

    /// Les bascules `privacy_*` gouvernent notamment l'activation de Sentry.
    /// Les laisser en place ferait hériter au compte suivant un consentement
    /// qu'il n'a jamais donné.
    func testLogoutClearsConsentState() {
        let defaults = UserDefaults.standard
        let consentKeys = [
            "privacy_shareData", "privacy_marketing", "privacy_ai",
            "privacy_camera", "consent_terms", "consent_history",
        ]
        for key in consentKeys {
            defaults.set(true, forKey: key)
        }

        LocalDataOwnership.clearConsentStateOnLogout()

        for key in consentKeys {
            XCTAssertNil(defaults.object(forKey: key),
                         "« \(key) » doit être effacé à la déconnexion")
        }
    }

    /// Le point le plus important du lot : la déconnexion ne doit toucher à
    /// RIEN d'autre. Les préférences d'appareil sont légitimement globales, et
    /// surtout les scènes AR, le chat et les routines n'existent nulle part
    /// ailleurs — les effacer serait une perte définitive.
    func testLogoutTouchesNothingButConsents() {
        let defaults = UserDefaults.standard
        let preserved = [
            "selectedLanguage",       // préférence d'appareil
            "dynamicTypeSize",
            "manualDarkMode",
            "wateringRoutines",       // local uniquement, jamais synchronisé
            "plantCareRoutines",
            "gardenCareActions",
        ]
        for key in preserved {
            defaults.set("valeur-témoin", forKey: key)
        }
        defer { preserved.forEach { defaults.removeObject(forKey: $0) } }

        LocalDataOwnership.clearConsentStateOnLogout()

        for key in preserved {
            XCTAssertEqual(
                defaults.string(forKey: key), "valeur-témoin",
                "« \(key) » ne doit PAS être effacé : irrécupérable ou hors périmètre du compte"
            )
        }
    }

    /// Garde-fou explicite contre la correction naïve : les fichiers de scène
    /// doivent survivre à la déconnexion. C'est le seul exemplaire des données
    /// AR d'un jardin.
    func testLogoutLeavesSceneFilesOnDisk() throws {
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sceneURL = documents.appendingPathComponent("scene_\(identifier).json")

        try Data("{}".utf8).write(to: sceneURL)
        defer { try? FileManager.default.removeItem(at: sceneURL) }

        LocalDataOwnership.clearConsentStateOnLogout()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sceneURL.path),
            "la déconnexion ne doit jamais supprimer une scène AR : le serveur n'en a aucune copie"
        )
    }
}
