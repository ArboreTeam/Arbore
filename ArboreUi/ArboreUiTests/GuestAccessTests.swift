import XCTest
@testable import ArboreUi

// GuestAccessTests.swift — issue #391.
//
// Couvre la classification d'un 403 et ce qui en découle côté UI. Le point
// sensible n'est pas qu'un invité soit refusé — le backend s'en charge — mais
// que ce refus soit **distingué** d'un compte banni : les deux arrivent en 403,
// et les confondre ferait afficher « accès interdit » à un invité au lieu de
// l'inviter à créer un compte.

final class ForbiddenReasonTests: XCTestCase {

    private func body(_ json: String) -> Data { Data(json.utf8) }

    // MARK: - Classification

    func testAccountRequiredIsRecognised() {
        let reason = ForbiddenReason(
            responseBody: body(#"{"code":"ACCOUNT_REQUIRED","error":"This action requires a registered account"}"#)
        )
        XCTAssertEqual(reason, .accountRequired)
    }

    func testEmailNotVerifiedIsRecognised() {
        let reason = ForbiddenReason(
            responseBody: body(#"{"code":"EMAIL_NOT_VERIFIED","error":"Email not verified"}"#)
        )
        XCTAssertEqual(reason, .emailNotVerified)
    }

    /// Un compte banni arrive lui aussi en 403. Il ne doit jamais être classé
    /// `.accountRequired` : proposer à un banni de « créer un compte » serait
    /// absurde, et masquerait la vraie raison du refus.
    func testBannedAccountIsNotMistakenForAGuest() {
        let reason = ForbiddenReason(
            responseBody: body(#"{"code":"ACCOUNT_BANNED","error":"Account banned"}"#)
        )
        XCTAssertEqual(reason, .other)
    }

    /// Le repli doit être `.other`, jamais `.accountRequired` : un corps
    /// illisible ne doit pas déclencher une invitation à créer un compte.
    func testMalformedBodiesFallBackToOther() {
        let malformed = [
            "",
            "pas du json",
            "[]",
            #"{"error":"sans code"}"#,
            #"{"code":123}"#,
            #"{"code":null}"#,
        ]
        for json in malformed {
            XCTAssertEqual(
                ForbiddenReason(responseBody: body(json)), .other,
                "corps « \(json) » : le repli doit être .other"
            )
        }
    }

    /// Les codes sont un contrat avec le backend Go. Ce test échoue si
    /// quelqu'un les modifie côté Swift sans toucher au serveur — ou l'inverse,
    /// puisque le test jumeau existe côté Go (`TestRequireAccountRejectsGuests`).
    func testWireCodesMatchTheBackendContract() {
        XCTAssertEqual(ForbiddenReason.accountRequiredCode, "ACCOUNT_REQUIRED")
        XCTAssertEqual(ForbiddenReason.emailNotVerifiedCode, "EMAIL_NOT_VERIFIED")
    }
}

final class AccountRequiredErrorTests: XCTestCase {

    func testIsAccountRequiredRecognisesTheDedicatedCase() {
        XCTAssertTrue(NetworkError.accountRequired.isAccountRequired)
    }

    /// Le prédicat sert dans des `catch` génériques : il doit être faux pour
    /// toutes les autres erreurs, sans quoi une panne réseau afficherait une
    /// invitation à créer un compte.
    func testIsAccountRequiredIsFalseForEverythingElse() {
        let others: [Error] = [
            NetworkError.forbidden,
            NetworkError.emailNotVerified,
            NetworkError.unauthorized,
            NetworkError.notFound,
            NetworkError.noUser,
            NetworkError.serverError("boom"),
            URLError(.notConnectedToInternet),
        ]
        for error in others {
            XCTAssertFalse(
                error.isAccountRequired,
                "\(error) ne doit pas être confondu avec un refus faute de compte"
            )
        }
    }

    /// Le message présenté doit être la chaîne localisée, pas un libellé Swift
    /// codé en dur : il s'affiche tel quel dans l'alerte et dans deux écrans du
    /// profil.
    func testAccountRequiredMessageIsLocalized() {
        let message = NetworkError.accountRequired.errorDescription
        XCTAssertEqual(message, L10n.t("GUEST_ACCOUNT_REQUIRED_MESSAGE"))
        XCTAssertNotEqual(message, "GUEST_ACCOUNT_REQUIRED_MESSAGE",
                          "clé non traduite : la chaîne manque dans Localizable.strings")
        XCTAssertFalse(message?.isEmpty ?? true)
    }
}

final class BackendErrorMessageTests: XCTestCase {

    private func body(_ json: String) -> Data { Data(json.utf8) }

    /// L'export RGPD et la suppression de compte affichaient le corps brut de
    /// la réponse. Un invité y aurait lu du JSON.
    func testAccountRequiredBodyBecomesAReadableMessage() {
        let message = BackendErrorMessage.humanReadable(
            from: body(#"{"code":"ACCOUNT_REQUIRED","error":"This action requires a registered account"}"#),
            fallback: "générique"
        )
        XCTAssertEqual(message, L10n.t("GUEST_ACCOUNT_REQUIRED_MESSAGE"))
        XCTAssertFalse(message.contains("{"), "aucun JSON ne doit atteindre l'utilisateur")
        XCTAssertFalse(message.contains("ACCOUNT_REQUIRED"))
    }

    /// Tout le reste retombe sur le message générique : les détails internes du
    /// backend n'apprennent rien à l'utilisateur et peuvent renseigner un
    /// attaquant.
    func testOtherBodiesFallBackWithoutLeakingInternals() {
        let leaky = #"{"error":"mongo: connection to arbore-cluster-0 refused"}"#
        let message = BackendErrorMessage.humanReadable(from: body(leaky), fallback: "générique")

        XCTAssertEqual(message, "générique")
        XCTAssertFalse(message.contains("mongo"))
        XCTAssertFalse(message.contains("arbore-cluster-0"))
    }

    func testEmptyBodyFallsBack() {
        XCTAssertEqual(
            BackendErrorMessage.humanReadable(from: Data(), fallback: "générique"),
            "générique"
        )
    }
}

final class GuestLocalizationTests: XCTestCase {

    /// Les libellés de l'accès invité s'affichent sur l'écran de connexion,
    /// première impression de l'app. Une clé non traduite y serait très visible.
    func testGuestStringsAreTranslated() {
        let keys = [
            "AUTH_CONTINUE_AS_GUEST",
            "AUTH_CONTINUE_AS_GUEST_SUBTITLE",
            "GUEST_ACCOUNT_REQUIRED_TITLE",
            "GUEST_ACCOUNT_REQUIRED_MESSAGE",
            "GUEST_ACCOUNT_REQUIRED_CTA",
            "DATA_EXPORT_ERROR_GENERIC",
            "CLOSE_ACCOUNT_ERROR_GENERIC",
        ]
        for key in keys {
            let value = L10n.t(key)
            XCTAssertNotEqual(value, key, "clé « \(key) » absente de Localizable.strings")
            XCTAssertFalse(value.isEmpty, "clé « \(key) » vide")
        }
    }

    /// Le sous-titre doit annoncer ce que l'invité PERD. Sans cela, la
    /// déception arrive au premier jardin non sauvegardé, après plusieurs
    /// minutes de travail.
    func testGuestSubtitleWarnsAboutTheLimitation() {
        let subtitle = L10n.t("AUTH_CONTINUE_AS_GUEST_SUBTITLE").lowercased()
        let warnsInSomeLanguage = ["sauvegard", "saved", "guardar", "gespeichert"]
            .contains { subtitle.contains($0) }

        XCTAssertTrue(
            warnsInSomeLanguage,
            "le sous-titre doit prévenir que les jardins ne seront pas sauvegardés — reçu : « \(subtitle) »"
        )
    }
}
