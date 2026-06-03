//
//  SentryManager.swift
//  ArboreUi
//
//  Thin wrapper around the Sentry SDK (issue #205).
//
//  Tout est gardé derrière `isEnabled` : si aucun DSN n'est configuré dans
//  Secrets.xcconfig (cf. AppConfig.sentryDSN), Sentry ne démarre pas et toutes
//  les méthodes sont des no-op. L'app se comporte donc à l'identique sans
//  secrets — pratique pour les contributeurs et la CI.
//

import Foundation
import Sentry

enum SentryManager {

    /// Clé `AppStorage` du consentement diagnostic/analytics (toggle « Partage
    /// de données » dans PrivacySettingsView). Absente = `false` : opt-out par
    /// défaut, Sentry ne démarre pas tant que l'utilisateur n'a pas accepté.
    private static let consentKey = "privacy_shareData"

    /// Vrai si un DSN est configuré dans Secrets.xcconfig.
    static var isConfigured: Bool { !AppConfig.sentryDSN.isEmpty }

    /// Vrai si l'utilisateur a consenti au partage des données de diagnostic.
    static var hasConsent: Bool { UserDefaults.standard.bool(forKey: consentKey) }

    /// Vrai si le crash reporting doit être actif : DSN présent ET consentement donné.
    static var isEnabled: Bool { isConfigured && hasConsent }

    /// Démarre Sentry si (et seulement si) un DSN est configuré ET que
    /// l'utilisateur a donné son consentement diagnostic. Appelée au tout début
    /// de `AppDelegate.didFinishLaunchingWithOptions`, AVANT
    /// `FirebaseApp.configure()`, pour capturer un éventuel crash d'init — mais
    /// sans consentement c'est un no-op (RGPD : aucune collecte avant opt-in).
    /// Re-déclenchée par `updateConsent(...)` quand l'utilisateur accepte.
    static func start() {
        guard isConfigured else {
            #if DEBUG
            print("ℹ️ Sentry désactivé (aucun DSN dans Secrets.xcconfig).")
            #endif
            return
        }
        guard hasConsent else {
            #if DEBUG
            print("ℹ️ Sentry en attente du consentement diagnostic (opt-in RGPD).")
            #endif
            return
        }

        SentrySDK.start { options in
            options.dsn = AppConfig.sentryDSN
            options.environment = AppConfig.environment
            options.releaseName = AppConfig.sentryReleaseName
            options.dist = AppConfig.buildNumber

            // 10% de transactions de performance : marge confortable sous le
            // free tier (5k events/mois) pour la beta.
            options.tracesSampleRate = 0.1

            // Vie privée : pas de capture d'écran (peut contenir des données
            // personnelles). La hiérarchie de vues (structure, sans pixels)
            // reste utile pour diagnostiquer les crashs d'UI.
            options.attachScreenshot = false
            options.attachViewHierarchy = true

            // Minimisation RGPD : ne jamais joindre les PII collectées « par
            // défaut » par le SDK (adresse IP, etc.).
            options.sendDefaultPii = false

            // Défense en profondeur : on retire explicitement de chaque event
            // l'IP, l'identité (e-mail/nom) et le payload de requête avant
            // envoi. On conserve volontairement `user.userId` = UID Firebase,
            // pseudonyme nécessaire pour corréler les crashs d'un même compte.
            options.beforeSend = { event in
                event.user?.ipAddress = nil
                event.user?.email = nil
                event.user?.username = nil
                event.user?.name = nil
                event.user?.data = nil
                event.serverName = nil
                event.request = nil
                return event
            }

            #if DEBUG
            options.debug = true
            #endif
        }
    }

    /// Réagit à un changement du consentement diagnostic depuis
    /// PrivacySettingsView : démarre Sentry à l'acceptation (et réattache le
    /// contexte user si l'utilisateur était déjà connecté), le coupe au retrait.
    static func updateConsent(granted: Bool, uid: String?) {
        guard isConfigured else { return }
        if granted {
            if !SentrySDK.isEnabled { start() }
            if let uid { setUser(uid: uid) }
        } else {
            SentrySDK.close()
        }
    }

    /// Rattache les events au user via son UID Firebase (pseudonyme).
    /// On n'envoie ni e-mail ni nom à Sentry : minimisation des données (RGPD).
    static func setUser(uid: String) {
        guard isEnabled else { return }
        let user = Sentry.User()        // Sentry.User, à ne pas confondre avec le modèle `User` de l'app
        user.userId = uid
        SentrySDK.setUser(user)
    }

    /// Efface le contexte user (au logout).
    static func clearUser() {
        guard isEnabled else { return }
        SentrySDK.setUser(nil)
    }

    #if DEBUG
    /// Envoie un event de test non-crashant pour vérifier que le DSN
    /// fonctionne (visible sur sentry.io en quelques secondes).
    static func sendTestEvent() {
        guard isEnabled else {
            print("⚠️ Sentry désactivé : renseigne le DSN dans Secrets.xcconfig.")
            return
        }
        SentrySDK.capture(message: "Arbore test event — \(AppConfig.sentryReleaseName)")
    }
    #endif
}
