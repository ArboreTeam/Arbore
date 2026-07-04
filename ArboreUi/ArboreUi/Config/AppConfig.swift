//
//  AppConfig.swift
//  ArboreUi
//
//  Created by Matribuk on 20/01/2026.
//

import Foundation

struct AppConfig {
    // MARK: - Security Configuration

    /// Clé API pour authentifier l'application iOS auprès du backend
    /// Chargée depuis Secrets.xcconfig via Info.plist
    static let apiKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "ARBORE_API_KEY") as? String,
              !key.isEmpty,
              key != "$(ARBORE_API_KEY)" else {
            fatalError("❌ ARBORE_API_KEY non configurée dans Secrets.xcconfig")
        }
        return key
    }()

    // MARK: - Backend Configuration

    /// URL de base du serveur backend
    /// Chargée depuis Secrets.xcconfig via Info.plist (ou valeur par défaut)
    static let baseURL: String = {
        // Lire le protocole et le host depuis Info.plist
        let protocolScheme = Bundle.main.object(forInfoDictionaryKey: "ARBORE_BACKEND_PROTOCOL") as? String
        let host = Bundle.main.object(forInfoDictionaryKey: "ARBORE_BACKEND_HOST") as? String

        // Vérifier que les valeurs sont valides (pas vides, pas les placeholders)
        if let protocolScheme = protocolScheme,
           let host = host,
           !protocolScheme.isEmpty,
           !host.isEmpty,
           protocolScheme != "$(ARBORE_BACKEND_PROTOCOL)",
           host != "$(ARBORE_BACKEND_HOST)" {
            return "\(protocolScheme)://\(host)"
        }

        // Fallback HTTPS via Cloudflare (#121), en DEBUG comme en release :
        // l'accès direct à l'origine est fermé par le firewall, on passe donc
        // toujours par api.arbore.app. Le TLD .app impose HSTS preload —
        // URLSession refuserait de toute façon tout HTTP.
        return "https://api.arbore.app"
    }()

    // MARK: - API Endpoints

    /// Endpoint pour les utilisateurs
    static let usersEndpoint = "\(baseURL)/users"

    /// Endpoint pour les plantes
    static let plantsEndpoint = "\(baseURL)/plants"

    /// Endpoint pour les jardins
    static let gardensEndpoint = "\(baseURL)/gardens"

    /// Endpoint pour les consentements RGPD
    static let consentsEndpoint = "\(baseURL)/consents"

    // MARK: - RGPD Configuration

    /// Version actuelle de la politique de confidentialité.
    /// Bumpée à 2.0 (31 mai 2026) : refonte complète, RGPD, FR/EN, alignée sur
    /// https://arbore.app/privacy et https://arbore.app/terms. Les nouveaux
    /// consentements sont horodatés avec cette version.
    static let privacyPolicyVersion = "2.0"

    /// Date de dernière mise à jour de la politique
    static let privacyPolicyLastUpdate = "31 May 2026"

    /// URL publique de la politique de confidentialité (FR/EN).
    /// Champ obligatoire App Store Connect + liens in-app.
    static let privacyPolicyURL = "https://arbore.app/privacy"

    /// URL publique des conditions générales d'utilisation (FR/EN).
    static let termsOfServiceURL = "https://arbore.app/terms"

    // MARK: - App Information

    /// Version de l'application
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    /// Numéro de build
    static let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    // MARK: - AI Chatbot

    /// Clé API Google Gemini (gemini-2.0-flash).
    /// Obtenez une clé gratuite sur https://aistudio.google.com/apikey
    /// Configurez GEMINI_API_KEY dans Secrets.xcconfig, ou définissez-la
    /// directement ici en développement.
    static let geminiAPIKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String,
              !key.isEmpty,
              key != "$(GEMINI_API_KEY)" else {
            return ""
        }
        return key
    }()

    // MARK: - Observability (Sentry — issue #205)

    /// Environnement reporté à Sentry pour filtrer les events.
    /// DEBUG = "debug" (builds Xcode locaux), sinon "beta" (TestFlight / release).
    static var environment: String {
        #if DEBUG
        return "debug"
        #else
        return "beta"
        #endif
    }

    /// Nom de release Sentry, au format `version+build` (ex. "1.0+10").
    /// Doit matcher le release créé à l'upload des dSYM pour la symbolication.
    static var sentryReleaseName: String { "\(appVersion)+\(buildNumber)" }

    /// DSN Sentry reconstruit depuis 3 champs de Secrets.xcconfig.
    ///
    /// Un DSN est une URL `https://<publicKey>@<host>/<projectID>`. Or les
    /// fichiers .xcconfig traitent `//` comme un commentaire : on ne peut pas y
    /// stocker l'URL telle quelle (même raison que le split protocol/host pour
    /// le backend). On stocke donc les 3 composants séparément et on
    /// reconstruit le DSN ici.
    ///
    /// Retourne "" si non configuré → Sentry reste désactivé (cf. SentryManager).
    static var sentryDSN: String {
        func value(_ key: String) -> String? {
            guard let v = Bundle.main.object(forInfoDictionaryKey: key) as? String,
                  !v.isEmpty, !v.hasPrefix("$(") else { return nil }
            return v
        }
        guard let publicKey = value("SENTRY_DSN_PUBLIC_KEY"),
              let host = value("SENTRY_DSN_HOST"),
              let projectID = value("SENTRY_DSN_PROJECT_ID") else {
            return ""
        }
        return "https://\(publicKey)@\(host)/\(projectID)"
    }
}
