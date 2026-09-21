//
//  AIProcessingPreference.swift
//  ArboreUi
//
//  Préférence de traitement IA — issue #549.
//

import Foundation

/// Source unique du réglage « Diagnostic et assistant par IA ».
///
/// ## Ce que ce réglage est, et ce qu'il n'est pas
///
/// Ce n'est **pas un consentement**. La base légale de ces deux traitements est
/// le contrat (RGPD art. 6(1)(b)) : l'utilisateur déclenche chaque envoi en
/// prenant une photo ou en écrivant un message, le traitement *est* le service.
/// Proposer un consentement pour un traitement contractuel suggérerait un droit
/// de retrait qu'on ne pourrait honorer qu'en supprimant la fonctionnalité — ce
/// que l'art. 7(3) n'admet pas.
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
/// ## Ce que « désactivé » produit
///
/// | | activé | désactivé |
/// |---|---|---|
/// | Scan santé | diagnostic complet, photo envoyée | **colorimétrie locale**, la photo ne quitte pas l'appareil |
/// | Assistant | disponible | indisponible, message explicite |
///
/// Le scan se dégrade au lieu de disparaître parce que `PlantHealthScanner`
/// sait déjà produire un résultat sans réseau. L'assistant n'a pas d'équivalent
/// local, donc il s'efface.
enum AIProcessingPreference {

    /// Clé partagée avec l'`@AppStorage` de `PrivacySettingsView`.
    static let storageKey = "privacy_ai"

    /// Vrai si l'utilisateur accepte que photos et messages soient analysés
    /// hors de l'appareil.
    ///
    /// Une clé absente vaut la valeur par défaut : le réglage est activé à
    /// l'installation, la fonctionnalité étant proposée d'emblée. Qui le coupe
    /// le fait sciemment.
    static var estAutorise: Bool {
        guard UserDefaults.standard.object(forKey: storageKey) != nil else {
            return ConsentDefaults.ai
        }
        return UserDefaults.standard.bool(forKey: storageKey)
    }
}
