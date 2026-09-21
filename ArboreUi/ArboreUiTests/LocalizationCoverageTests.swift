import XCTest
@testable import ArboreUi

// LocalizationCoverageTests — issue #578.
//
// Le chatbot et le scan santé sont restés entièrement en français pendant des
// mois. Personne ne l'a vu parce que l'app est développée et testée en
// français : un écran monolingue y est indiscernable d'un écran traduit.
//
// Le défaut a été signalé par un testeur dont l'app était en anglais, et il
// prenait deux formes. Des littéraux posés directement dans `Text(…)`, et —
// plus insidieux — des `NSLocalizedString(clé, value: "texte français")` dont
// la clé n'était définie dans AUCUN fichier de langue : la forme était
// correcte, le repli français s'affichait partout.
//
// Ces tests attrapent la seconde forme, qui ne se voit pas à la relecture.

final class LocalizationCoverageTests: XCTestCase {

    /// Les langues que l'app prétend servir.
    private let langues = ["fr", "en", "es", "de"]

    /// Clés des deux écrans concernés, reprises à la main : un test qui
    /// dériverait la liste du code ne prouverait rien, il constaterait.
    private let clesCritiques = [
        // Assistant
        "CHATBOT_HEADER_SUBTITLE", "CHATBOT_EMPTY_TITLE", "CHATBOT_EMPTY_SUBTITLE",
        "CHATBOT_ASK_TITLE", "CHATBOT_ASK_SUBTITLE", "CHATBOT_PHOTO_SELECTED",
        "CHATBOT_ERROR_AI_DISABLED", "CHATBOT_ERROR_UNAVAILABLE",
        // Scan santé — parcours
        "SCAN_CAPTURE_HINT", "SCAN_GUIDE_TEXT", "SCAN_GUIDE_LIGHT",
        "SCAN_CAMERA_REQUIRED", "SCAN_ANALYSING", "SCAN_STEP_QUALITY",
        // Scan santé — résultat, ce que l'utilisateur vient chercher
        "SCAN_VERDICT_EXCELLENT", "SCAN_VERDICT_GOOD", "SCAN_VERDICT_WEAK",
        "SCAN_VERDICT_STRESSED", "SCAN_VERDICT_POOR",
        "SCAN_SPECIES_LABEL", "SCAN_ISSUES_TITLE", "SCAN_RECOMMENDATIONS_TITLE",
        "SCAN_METRIC_NECROSIS", "SCAN_METRIC_UNIFORMITY",
        // Scan santé — erreurs et avertissements
        "SCAN_ERROR_LOW_BRIGHTNESS", "SCAN_ERROR_NO_PLANT", "SCAN_ERROR_TIMEOUT",
        "SCAN_WARNING_AI_DISABLED", "SCAN_WARNING_AI_UNAVAILABLE",
        "SCAN_ADVICE_HEALTHY", "SCAN_ADVICE_CHLOROSIS",
        // Avertissements IA (#585) : ils doivent atteindre l'utilisateur dans
        // SA langue, sans quoi l'avertissement n'en est pas un.
        "AI_DISCLAIMER", "AI_DISCLAIMER_SCAN",
        "CHATBOT_INPUT_PLACEHOLDER", "CHATBOT_RENAME_PLACEHOLDER"
    ]

    private func bundle(_ langue: String) -> Bundle? {
        guard let chemin = Bundle(for: Self.self).path(forResource: langue, ofType: "lproj")
                ?? Bundle.main.path(forResource: langue, ofType: "lproj") else { return nil }
        return Bundle(path: chemin)
    }

    /// Chaque clé doit être DÉFINIE dans les quatre langues.
    ///
    /// Une clé absente ne casse rien de visible : `NSLocalizedString` rend son
    /// `value:` s'il y en a un, la clé brute sinon. C'est exactement ainsi que
    /// vingt chaînes du scan santé sont restées françaises dans les quatre
    /// langues sans qu'aucune relecture ne le remarque.
    func testChaqueCleCritiqueEstDefinieDansLesQuatreLangues() {
        for langue in langues {
            guard let b = bundle(langue) else {
                XCTFail("Le bundle \(langue).lproj est introuvable")
                continue
            }
            for cle in clesCritiques {
                let valeur = b.localizedString(forKey: cle, value: "__ABSENTE__", table: nil)
                XCTAssertNotEqual(valeur, "__ABSENTE__",
                                  "\(cle) n'est pas définie en \(langue) — elle s'affichera "
                                  + "dans la langue de son repli, pas dans celle de l'utilisateur")
                XCTAssertFalse(valeur.isEmpty, "\(cle) est vide en \(langue)")
            }
        }
    }

    /// Une traduction identique au français dans les trois autres langues
    /// signale une clé recopiée sans être traduite.
    ///
    /// Tolère les termes qui ne se traduisent pas — noms propres, termes
    /// botaniques latins, unités.
    func testLesTraductionsNeSontPasDeSimplesCopiesDuFrancais() {
        let identiquesAdmis: Set<String> = [
            "SCAN_METRIC_CHLOROSIS",   // « Chlorose » en FR et DE
            "CHATBOT_TITLE"            // « Chat » dans les quatre langues
        ]
        guard let fr = bundle("fr") else { return XCTFail("fr.lproj introuvable") }

        for langue in ["en", "es", "de"] {
            guard let b = bundle(langue) else { continue }
            for cle in clesCritiques where !identiquesAdmis.contains(cle) {
                let vfr = fr.localizedString(forKey: cle, value: "", table: nil)
                let v = b.localizedString(forKey: cle, value: "", table: nil)
                guard !vfr.isEmpty, !v.isEmpty else { continue }
                XCTAssertNotEqual(v, vfr,
                                  "\(cle) est identique au français en \(langue) : "
                                  + "probablement recopiée sans être traduite")
            }
        }
    }
}
