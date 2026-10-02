//
//  AIProcessingPreference.swift
//  ArboreUi
//
//  Préférence de traitement IA — issues #549, #607.
//

import Foundation

/// Source unique du réglage « Diagnostic et assistant par IA », et de la
/// divulgation qui doit précéder le premier envoi.
///
/// ## Ce que ce réglage est, et ce qu'il n'est pas
///
/// Ce n'est **pas un consentement** au sens du RGPD. La base légale de ces deux
/// traitements est le contrat (art. 6(1)(b)) : l'utilisateur déclenche chaque
/// envoi en prenant une photo ou en écrivant un message, le traitement *est* le
/// service. Proposer un consentement pour un traitement contractuel suggérerait
/// un droit de retrait qu'on ne pourrait honorer qu'en supprimant la
/// fonctionnalité — ce que l'art. 7(3) n'admet pas.
///
/// C'est une **préférence de fonctionnalité**, au sens de la minimisation par
/// défaut (art. 25). Elle n'est donc pas consignée dans le registre des
/// consentements : celui-ci ne doit contenir que des consentements.
///
/// Le consentement légitime — celui portant sur l'entraînement, finalité
/// distincte — est réglé en amont chez le fournisseur : l'option d'amélioration
/// y est désactivée pour tout le monde, aucun contenu ne sert à entraîner quoi
/// que ce soit (#555).
///
/// ## La divulgation préalable, et pourquoi elle ne contredit pas ce qui précède
///
/// La version 1.0.0 (2) a été refusée par App Review au titre des directives
/// 5.1.1(i) et 5.1.2(i) : l'app transmettait des photos à un service d'IA tiers
/// sans dire lesquelles, sans nommer le destinataire et **sans demander** —
/// le réglage était allumé à l'installation. Apple exige quatre choses, dont
/// trois tenaient déjà dans la politique de confidentialité ; la quatrième,
/// obtenir l'autorisation avant l'envoi, manquait.
///
/// Cette autorisation n'est pas un consentement RGPD et ne change donc rien au
/// raisonnement ci-dessus : c'est une exigence de la plateforme, doublée d'une
/// exigence d'honnêteté. Afficher un réglage « activé » à quelqu'un à qui on n'a
/// jamais dit que ses photos partiraient chez un tiers serait faux, quelle que
/// soit la base légale invoquée.
///
/// D'où la forme retenue : `estAutorise` reste la seule porte lue par les deux
/// points d'envoi, mais elle est **fermée tant que la divulgation n'a pas reçu
/// de réponse**. Le registre des consentements, lui, n'est pas touché.
///
/// ## Ce que « désactivé » produit
///
/// | | activé | désactivé |
/// |---|---|---|
/// | Scan santé | diagnostic complet, photo envoyée | **colorimétrie locale**, la photo ne quitte pas l'appareil |
/// | Assistant | disponible | indisponible, message explicite |
///
/// Le scan se dégrade au lieu de disparaître parce que `PlantHealthScanner`
/// sait déjà produire un résultat sans réseau. L'assistant n'a pas d'équivalent
/// local, donc il s'efface. C'est ce qui permet à un refus d'être un vrai choix
/// plutôt qu'une impasse.
enum AIProcessingPreference {

    /// Clé partagée avec l'`@AppStorage` de `PrivacySettingsView`.
    static let storageKey = "privacy_ai"

    /// Clé portant la version de divulgation à laquelle l'utilisateur a répondu.
    /// Absente ou inférieure à `versionDivulgation` : personne ne lui a encore
    /// rien dit, donc rien ne doit partir.
    static let divulgationKey = "privacy_ai_divulgation"

    /// Version du texte de divulgation. **À incrémenter dès que la substance
    /// change** — un nouveau fournisseur, une nouvelle catégorie de données, un
    /// nouveau pays d'hébergement. L'incrémenter re-demande l'autorisation à
    /// tout le monde, ce qui est précisément l'effet voulu : l'accord portait sur
    /// l'ancien texte, pas sur le nouveau.
    static let versionDivulgation = 1

    /// Vrai si l'utilisateur a vu la divulgation en vigueur et y a répondu,
    /// quelle que soit sa réponse.
    static var divulgationFaite: Bool {
        UserDefaults.standard.integer(forKey: divulgationKey) >= versionDivulgation
    }

    /// Vrai si photos et messages peuvent être analysés hors de l'appareil.
    ///
    /// Deux conditions, dans cet ordre : la divulgation a reçu une réponse, et
    /// le réglage est actif. La première domine — sans elle, le défaut du projet
    /// n'est même pas consulté, car un défaut ne vaut autorisation de rien.
    static var estAutorise: Bool {
        guard divulgationFaite else { return false }
        guard UserDefaults.standard.object(forKey: storageKey) != nil else {
            return ConsentDefaults.ai
        }
        return UserDefaults.standard.bool(forKey: storageKey)
    }

    /// Enregistre la réponse à la divulgation, et le réglage qui en découle.
    ///
    /// Les deux clés sont écrites ensemble : une divulgation répondue sans
    /// réglage, ou l'inverse, laisserait un état que `estAutorise` ne saurait
    /// pas lire honnêtement.
    static func enregistrerReponse(autorise: Bool) {
        UserDefaults.standard.set(autorise, forKey: storageKey)
        UserDefaults.standard.set(versionDivulgation, forKey: divulgationKey)
    }

    /// Marque la divulgation comme répondue sans toucher au réglage.
    ///
    /// Appelé quand l'utilisateur allume lui-même le réglage depuis l'écran
    /// Confidentialité : la ligne qu'il actionne nomme déjà les données et le
    /// destinataire, donc l'allumer **est** une autorisation informée. Lui
    /// présenter ensuite la feuille de divulgation reviendrait à lui redemander
    /// ce qu'il vient d'accorder.
    static func marquerDivulgationRepondue() {
        UserDefaults.standard.set(versionDivulgation, forKey: divulgationKey)
    }
}
