import Foundation
import simd

// MARK: - Root Plant model

struct Plant: Identifiable, Codable {
    let id: String
    let name: String
    let type: String
    let imageURLs: [String]
    let description: String
    let modelURL: String?
    let translations: [String: PlantTranslation]   // fr / en / es / de

    enum CodingKeys: String, CodingKey {
        case id
        case name, type, imageURLs, description, modelURL, translations
    }

    // Décode avec fallback safe
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Plante inconnue"
        self.type = try container.decodeIfPresent(String.self, forKey: .type) ?? "Type inconnu"

        self.imageURLs = try container
            .decodeIfPresent([String].self, forKey: .imageURLs)?
            .filter { !$0.isEmpty }
            ?? ["https://via.placeholder.com/300x200?text=Plante"]

        self.description = try container.decodeIfPresent(String.self, forKey: .description)
            ?? "Description non disponible."

        self.modelURL = try container.decodeIfPresent(String.self, forKey: .modelURL)

        self.translations = try container.decodeIfPresent([String: PlantTranslation].self, forKey: .translations)
            ?? [:]
    }
}

// MARK: - Translations & sub-objects

struct PlantTranslation: Codable {
    let description: String
    let plantType: String
    let sun: SunInfo?
    let water: WaterInfo?
    let soilAndPot: SoilAndPotInfo?
    let health: HealthInfo?
    let lifeCycle: LifeCycleInfo?
    let care: CareInfo?
}

struct SunInfo: Codable {
    let lightType: String?
    let durationPerDay: String?
    let orientation: String?
    let windowDistance: String?
    let recommendedRooms: [String]?
    let tips: [String]?
}

struct WaterInfo: Codable {
    let frequency: String?
    let amount: String?
    let method: String?
    let humidity: String?
    let signsLack: String?
    let signsExcess: String?
    let recommendedWater: String?
}

struct SoilAndPotInfo: Codable {
    let substrate: String?
    let drainage: String?
    let potSize: String?
    let repotFrequency: String?
    let repotSigns: String?
}

struct HealthInfo: Codable {
    let commonProblems: [String]?
    let symptomsAndCauses: [String]?
    let pests: [String]?
    let treatments: [String]?
    let prevention: [String]?
}

struct LifeCycleInfo: Codable {
    let growth: String?
    let flowering: String?
    let dormancy: String?
    let fertilizer: String?
    let pruning: String?
}

struct CareInfo: Codable {
    let weekly: [String]?
    let monthly: [String]?
    let yearly: [String]?
    let extraTips: [String]?
}

// MARK: - PlantModel3D

struct PlantModel3D {
    /// Nom du fichier dans le bundle (sans extension)
    let assetName: String
    
    /// Extension du fichier (usdz ou usdc)
    let fileExtension: String
    
    /// Échelle appliquée au modèle dans AR
    let scale: SIMD3<Float>
    
    /// Décalage vertical (pour que le pot repose bien sur le sol)
    let yOffset: Float
    
    init(
        assetName: String,
        fileExtension: String = "usdz",
        scale: SIMD3<Float> = SIMD3<Float>(repeating: 1.0),
        yOffset: Float = 0.0
    ) {
        self.assetName = assetName
        self.fileExtension = fileExtension
        self.scale = scale
        self.yOffset = yOffset
    }
}

// MARK: - Extension Plant → config 3D + URL locale

extension Plant {
    /// Configuration du modèle 3D local associé à la plante (si dispo côté app)
    var model3D: PlantModel3D? {
        switch name.lowercased() {
        case "guzmania":
            // 🔧 adapte assetName / extension à ton vrai fichier dans Xcode
            return PlantModel3D(
                assetName: "Guzmania",   // ex: fichier "Guzmania.usdz"
                fileExtension: "usdz",
                scale: SIMD3<Float>(repeating: 0.01),
                yOffset: 0.0
            )
            
        case "monstera":
            return PlantModel3D(
                assetName: "Monstera",
                fileExtension: "glb",
                scale: SIMD3<Float>(repeating: 0.01),
                yOffset: 0.0
            )
        
        case "bambou":
            return PlantModel3D(
                assetName: "Bambou",
                fileExtension: "glb",
                scale: SIMD3<Float>(repeating: 0.01),
                yOffset: 0.0
            )

        // ➕ Tu ajoutes simplement un case par plante qui a un modèle
        // case "ficus":
        //     return PlantModel3D(
        //         assetName: "Ficus",
        //         fileExtension: "usdz",
        //         scale: SIMD3<Float>(repeating: 0.01),
        //         yOffset: 0.0
        //     )
            
        default:
            return nil
        }
    }
    
    /// URL du fichier local dans le bundle, dérivée de `model3D`
    var localModelURL: URL? {
        guard let cfg = model3D else { return nil }
        return Bundle.main.url(
            forResource: cfg.assetName,
            withExtension: cfg.fileExtension
        )
    }
}
