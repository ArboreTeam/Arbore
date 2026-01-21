//
//  AppConfig.swift
//  ArboreUi
//
//  Created by Matribuk on 20/01/2026.
//

import Foundation

struct AppConfig {
    // MARK: - Backend Configuration

    /// URL de base du serveur backend
    static let baseURL: String = {
        #if DEBUG
        // En développement, utiliser l'IP du serveur
        return "http://79.137.92.154:8080"
        #else
        // En production, utiliser l'URL de production
        return "http://79.137.92.154:8080"
        // return "https://api.arbore.app" // À configurer plus tard
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
