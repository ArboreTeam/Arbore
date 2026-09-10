import XCTest
import Sentry
@testable import ArboreUi

// SentryAnonymisationTests — issues #496 et #498.
//
// Ces tests existent à cause d'un échec précis. Le 9 septembre, #495 a instauré
// un régime anonyme et j'ai affirmé, après relecture, qu'aucun identifiant ne
// quittait l'appareil. La politique de confidentialité publique l'a affirmé le
// lendemain.
//
// Le PREMIER événement réel a démenti les deux : `device_app_hash`, un
// identifiant d'installation stable, passait toujours. Il ne vit pas dans
// `user` mais dans le contexte `app` — un angle mort que la relecture ne
// pouvait pas voir, et qu'aucun test ne pouvait attraper puisque la logique
// vivait dans une closure imbriquée.
//
// D'où l'extraction de `scrub` et `filtrer`, et d'où ces tests. Ils gardent une
// promesse écrite sur arbore.app/privacy — pas une préférence d'implémentation.

final class SentryAnonymisationTests: XCTestCase {

    private func evenement(avecUtilisateur uid: String? = nil,
                           deviceAppHash: String? = "abc123",
                           appId: String? = "BCA5EA99-112D-3DF0-BDB4-0D6553E5B2FE") -> Event {
        let e = Event()
        if let uid {
            let u = Sentry.User()
            u.userId = uid
            u.email = "quelquun@exemple.fr"
            u.ipAddress = "92.184.105.12"
            e.user = u
        }
        var app: [String: Any] = [:]
        if let deviceAppHash { app["device_app_hash"] = deviceAppHash }
        if let appId { app["app_id"] = appId }
        e.context = ["app": app]
        return e
    }

    private func app(_ e: Event) -> [String: Any] { (e.context?["app"]) ?? [:] }

    // MARK: - Sans consentement : l'anonymat

    /// L'invariant que la politique publique promet.
    ///
    /// Le bloc `user` n'est plus supprimé mais vidé : il ne porte qu'une adresse
    /// factice. Un `nil` pur rendrait la main à Sentry, qui regarderait alors
    /// l'adresse de la connexion et en dériverait une ville (#498). Ce qui
    /// compte n'est pas que `user` soit absent — c'est qu'il ne désigne
    /// personne.
    func testSansConsentementAucunIdentifiantNeSubsiste() {
        let e = SentryManager.scrub(evenement(avecUtilisateur: "firebase-uid-123"), consenti: false)

        XCTAssertNil(e.user?.userId, "Aucun identifiant de compte ne doit subsister")
        XCTAssertNil(e.user?.email)
        XCTAssertNil(e.user?.username)
        XCTAssertNil(e.user?.name)
        XCTAssertNil(e.user?.data)
    }

    // MARK: - L'adresse IP (#498)

    /// Effacer l'IP ne suffisait pas : sans adresse dans la charge, Sentry
    /// prenait celle de la connexion et en dérivait `user.geo` — pays ET ville,
    /// y compris sur les rapports anonymes. Aucune règle de scrubbing ne peut
    /// l'atteindre, la géolocalisation étant calculée après le nettoyage.
    ///
    /// Poser une adresse explicite coupe la déduction. Remettre `nil` ici fait
    /// échouer le test, et rouvre la fuite.
    func testSansConsentementLAdresseEstRemplaceeEtNonEffacee() {
        let e = SentryManager.scrub(evenement(avecUtilisateur: "uid"), consenti: false)

        XCTAssertEqual(e.user?.ipAddress, "0.0.0.0",
                       "Une adresse absente laisse Sentry lire celle de la connexion "
                       + "et en déduire une ville")
    }

    /// Le consentement porte sur le rattachement au compte, jamais sur la
    /// localisation : l'adresse est remplacée dans les deux régimes.
    func testAvecConsentementLAdresseEstAussiRemplacee() {
        let e = SentryManager.scrub(evenement(avecUtilisateur: "uid"), consenti: true)

        XCTAssertEqual(e.user?.ipAddress, "0.0.0.0")
        XCTAssertEqual(e.user?.userId, "uid", "Le compte, lui, reste rattaché")
    }

    /// L'adresse posée doit être la même partout : une valeur qui varierait
    /// redeviendrait un identifiant.
    func testLAdresseAnonymeEstConstanteEntreDeuxEvenements() {
        let a = SentryManager.scrub(evenement(avecUtilisateur: "uid-a"), consenti: false)
        let b = SentryManager.scrub(evenement(avecUtilisateur: "uid-b"), consenti: false)

        XCTAssertEqual(a.user?.ipAddress, b.user?.ipAddress)
    }

    /// La régression de #498 : `user = nil` ne suffisait pas.
    func testSansConsentementLIdentifiantDInstallationEstRetire() {
        let e = SentryManager.scrub(evenement(), consenti: false)
        XCTAssertNil(app(e)["device_app_hash"],
                     "device_app_hash est un identifiant d'installation : il doit partir avec le reste")
    }

    /// L'UUID du binaire reste — il ne désigne pas une personne, et la
    /// symbolication en dépend.
    func testLUUIDDuBinaireEstConserve() {
        let e = SentryManager.scrub(evenement(), consenti: false)
        XCTAssertEqual(app(e)["app_id"] as? String, "BCA5EA99-112D-3DF0-BDB4-0D6553E5B2FE",
                       "app_id est l'UUID du binaire, identique pour tous : le retirer casserait la symbolication")
    }

    /// Un contexte `app` absent ne doit pas faire échouer le nettoyage.
    func testUnContexteAbsentNeCassePas() {
        let e = Event()
        XCTAssertNoThrow(SentryManager.scrub(e, consenti: false))
    }

    // MARK: - Avec consentement : le régime enrichi

    func testAvecConsentementLIdentifiantDeCompteEstConserve() {
        let e = SentryManager.scrub(evenement(avecUtilisateur: "firebase-uid-123"), consenti: true)
        XCTAssertEqual(e.user?.userId, "firebase-uid-123")
    }

    /// Même consenti, l'identité directe ne part jamais — minimisation RGPD.
    /// L'adresse réelle non plus : elle est remplacée, cf. la section suivante.
    func testMemeConsentiNiEmailNiNomNePartent() {
        let e = SentryManager.scrub(evenement(avecUtilisateur: "uid"), consenti: true)
        XCTAssertNotEqual(e.user?.ipAddress, "92.184.105.12", "L'adresse réelle ne doit jamais partir")
        XCTAssertNil(e.user?.email)
        XCTAssertNil(e.user?.name)
        XCTAssertNil(e.user?.username)
    }

    // MARK: - Fils d'Ariane

    /// Les URL portent `/gardens/<id>` : par recoupement, elles désignent
    /// leur propriétaire.
    func testSansConsentementLesTracesReseauSontEcartees() {
        let c = Breadcrumb()
        c.type = "http"
        c.category = "http"
        XCTAssertNil(SentryManager.filtrer(c, consenti: false))
    }

    func testAvecConsentementLesTracesReseauPassent() {
        let c = Breadcrumb()
        c.type = "http"
        c.category = "http"
        XCTAssertNotNil(SentryManager.filtrer(c, consenti: true))
    }

    // MARK: - Muet sous XCTest (#506)

    /// Ce test s'exécute sous XCTest, donc il vérifie la détection dans le seul
    /// contexte où elle compte. Casser le mécanisme le fait échouer.
    func testLaPresenceDuHarnaisDeTestEstDetectee() {
        XCTAssertTrue(SentryManager.isRunningTests,
                      "Le harnais XCTest pose XCTestConfigurationFilePath : ne pas le voir, "
                      + "c'est réémettre de faux plantages depuis la suite de tests")
    }

    /// L'invariant réel : un test ne doit pas pouvoir écrire dans
    /// l'observabilité de production, DSN configuré ou non.
    func testLeSDKResteEteintPendantLesTests() {
        XCTAssertFalse(SentryManager.isEnabled,
                       "Un DSN présent dans Secrets.xcconfig ne doit pas suffire à faire "
                       + "émettre la suite de tests (#506)")
    }

    /// Les autres fils d'Ariane — navigation, cycle de vie — ne portent pas
    /// d'identifiant et restent utiles au diagnostic.
    func testLesAutresFilsDArianePassentDansLesDeuxCas() {
        let c = Breadcrumb()
        c.category = "ui.lifecycle"
        XCTAssertNotNil(SentryManager.filtrer(c, consenti: false))
        XCTAssertNotNil(SentryManager.filtrer(c, consenti: true))
    }
}
