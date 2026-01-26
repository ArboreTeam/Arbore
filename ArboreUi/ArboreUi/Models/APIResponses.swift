//
//  APIResponses.swift
//  ArboreUi
//
//  Created by Matribuk on 25/01/2026.
//

import Foundation

// MARK: - User API Responses

struct UserResponse: Codable {
    let user: User?
    let message: String?
}

// MARK: - Consent API Responses

struct BackendConsent: Codable {
    let consentType: String
    let granted: Bool
    let timestamp: String
    let version: String
}

struct BackendConsentsResponse: Codable {
    let uid: String
    let consents: [BackendConsent]?  // Optionnel car peut être null si aucun consent
}
