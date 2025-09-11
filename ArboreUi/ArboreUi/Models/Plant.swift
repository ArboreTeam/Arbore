import Foundation
import SwiftUI

struct Plant: Identifiable, Codable {
    let id: String
    let name: String
    let type: String
    let imageURLs: [String]
    let description: String
    let soilType: String
    let exposure: String
    let wateringNeeds: String
    let temperature: String
    let floraison: String
    let origin: String
    let wateringReminder: String
    let careTips: [String]
    let modelURL: String?
    let translations: [String: [String: String]]

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case name, type, imageURLs, description, soilType, exposure,
             wateringNeeds, temperature, floraison, origin,
             wateringReminder, careTips, modelURL, translations
    }

    // Décode avec fallback
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Plante inconnue"
        self.type = try container.decodeIfPresent(String.self, forKey: .type) ?? "Inconnu"
        self.imageURLs = try container.decodeIfPresent([String].self, forKey: .imageURLs)?.filter { !$0.isEmpty } ?? ["https://via.placeholder.com/300x200?text=Plante"]
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? "Description inconnue"
        self.soilType = try container.decodeIfPresent(String.self, forKey: .soilType) ?? "Inconnu"
        self.exposure = try container.decodeIfPresent(String.self, forKey: .exposure) ?? "Inconnue"
        self.wateringNeeds = try container.decodeIfPresent(String.self, forKey: .wateringNeeds) ?? "Inconnus"
        self.temperature = try container.decodeIfPresent(String.self, forKey: .temperature) ?? "N.C."
        self.floraison = try container.decodeIfPresent(String.self, forKey: .floraison) ?? "N.C."
        self.origin = try container.decodeIfPresent(String.self, forKey: .origin) ?? "N.C."
        self.wateringReminder = try container.decodeIfPresent(String.self, forKey: .wateringReminder) ?? "Non défini"
        self.careTips = try container.decodeIfPresent([String].self, forKey: .careTips) ?? ["Aucun conseil disponible"]
        self.modelURL = try container.decodeIfPresent(String.self, forKey: .modelURL)
        self.translations = try container.decodeIfPresent([String: [String: String]].self, forKey: .translations) ?? [:]
    }

    // 🔁 Traductions dynamiques selon la langue sélectionnée
    @AppStorage("selectedLanguage") static var selectedLanguage = "en"
    var localized: [String: String] {
        translations[Plant.selectedLanguage] ?? [:]
    }
}
