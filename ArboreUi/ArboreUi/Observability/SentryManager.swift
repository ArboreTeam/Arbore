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

    /// Vrai si un DSN est configuré → crash reporting actif.
    static var isEnabled: Bool { !AppConfig.sentryDSN.isEmpty }

    /// Démarre Sentry. À appeler tout au début de
    /// `AppDelegate.didFinishLaunchingWithOptions`, AVANT
    /// `FirebaseApp.configure()`, afin de capturer aussi un éventuel crash
    /// pendant l'init de Firebase.
    static func start() {
        let dsn = AppConfig.sentryDSN
        guard !dsn.isEmpty else {
            #if DEBUG
            print("ℹ️ Sentry désactivé (aucun DSN dans Secrets.xcconfig).")
            #endif
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
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

            #if DEBUG
            options.debug = true
            #endif
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
