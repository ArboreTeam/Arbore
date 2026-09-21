//
//  ConsentDefaults.swift
//  ArboreUi
//
//  Source unique des valeurs par défaut des consentements RGPD (issue #218).
//  Référencée à la fois par `PrivacySettingsView` (defaults @AppStorage) et par
//  la capture initiale au signup (`recordInitialConsents`) pour éviter toute
//  divergence entre l'état réel des toggles et la preuve enregistrée.
//

import Foundation

/// Valeurs par défaut des consentements, alignées sur le principe de
/// **privacy by default** (RGPD Art. 25 / CJEU Planet49) : tout ce qui relève
/// d'un consentement libre est `false` par défaut. Restent `true` uniquement :
/// les traitements en base légale « contrat » (fonctionnalité cœur) et les
/// toggles purement informatifs dont le vrai gate est une permission iOS.
enum ConsentDefaults {
    /// Profil privé par défaut — aucune exposition publique tant que l'utilisateur ne l'active pas.
    static let profilePublic = false
    /// Activité masquée par défaut.
    static let showActivity = false
    /// Diagnostics (Sentry) — opt-in (issue #226), dont la portée a changé
    /// avec #469 : il ne conditionne plus la COLLECTE mais l'IDENTIFICATION.
    ///
    /// Sans consentement, les plantages remontent en régime anonyme : aucun
    /// identifiant, pas de hiérarchie de vues, pas de fil d'Ariane réseau. Avec,
    /// l'UID Firebase est joint et permet de corréler plusieurs plantages.
    ///
    /// Reste `false` par défaut : le régime enrichi, lui, demande bien un
    /// consentement explicite.
    static let analytics = false
    /// Marketing — opt-in strict.
    static let marketing = false
    /// Caméra — informatif : le vrai consentement est la permission iOS (NSCameraUsageDescription).
    static let camera = true
    /// Diagnostic santé et assistant — **préférence de fonctionnalité**, pas un
    /// consentement. La base légale est le contrat (Art. 6(1)(b)) : l'utilisateur
    /// déclenche chaque envoi en prenant une photo ou en écrivant un message. Le
    /// moteur de *suggestion de plantes*, lui, est entièrement local et n'est pas
    /// concerné. Les contenus partent vers Mistral AI, hébergé dans l'UE (#555).
    ///
    /// Lu par `AIProcessingPreference`, que consultent les deux points d'envoi
    /// (#549). Éteint : le scan se rabat sur la colorimétrie locale et la photo
    /// ne quitte pas l'appareil, l'assistant devient indisponible.
    ///
    /// N'apparaît PAS dans `initialSnapshot` : le registre des consentements ne
    /// doit contenir que des consentements.
    static let ai = true
    /// Notifications — informatif : le vrai consentement est la permission iOS.
    static let notifications = true

    /// Snapshot ordonné (type backend ↔ valeur par défaut) capturé au premier
    /// lancement / signup, pour disposer d'une preuve datée dès l'inscription
    /// (accountability, RGPD Art. 5(2)) même si l'utilisateur n'ouvre jamais
    /// l'écran Confidentialité. Les clés correspondent à `consent.consentType`
    /// côté backend (`/consents`).
    static let initialSnapshot: [(type: String, granted: Bool)] = [
        ("analytics", analytics),
        ("marketing", marketing),
        ("camera", camera),
        ("notifications", notifications),
    ]
}
