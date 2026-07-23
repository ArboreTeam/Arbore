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
    /// Diagnostics (Sentry) — opt-in strict (issue #226). Gate effectif : `SentryManager.hasConsent`.
    static let analytics = false
    /// Marketing — opt-in strict.
    static let marketing = false
    /// Caméra — informatif : le vrai consentement est la permission iOS (NSCameraUsageDescription).
    static let camera = true
    /// Suggestions / traitement IA — fonctionnalité cœur, base légale contrat (Art. 6(1)(b)),
    /// pas un consentement. Le moteur de *suggestion de plantes* est local, mais le
    /// diagnostic santé et l'assistant transmettent photos et messages à Google (Gemini),
    /// y compris hors UE (cf. politique de confidentialité 2.1).
    /// ⚠️ Ce drapeau n'est aujourd'hui lu ni par PlantHealthScanner ni par GeminiService :
    /// conditionner ces envois à ce consentement est suivi dans l'issue de conformité.
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
        ("ai", ai),
        ("notifications", notifications),
    ]
}
