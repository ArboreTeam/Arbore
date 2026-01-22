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

        #if DEBUG
        // Fallback en développement
        return "http://79.137.92.154:8080"
        #else
        // Fallback en production
        return "http://79.137.92.154:8080"
        #endif
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

    /// Version actuelle de la politique de confidentialité
    static let privacyPolicyVersion = "1.0"

    /// Date de dernière mise à jour de la politique
    static let privacyPolicyLastUpdate = "20 Jan 2026"

    // MARK: - App Information

    /// Version de l'application
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    /// Numéro de build
    static let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
}
