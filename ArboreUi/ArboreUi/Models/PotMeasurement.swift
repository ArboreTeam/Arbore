import Foundation
import SwiftUI

// MARK: - Pot Measurement Model

struct PotMeasurement: Identifiable, Codable {
    var id = UUID()
    var plantName: String?
    var diameter: Double // en cm
    var height: Double // en cm
    var volume: Double // en litres
    var shape: PotShape
    var material: PotMaterial?
    var drainageHoles: Bool
    var notes: String
    var createdAt: Date
    var photos: [String] // URLs ou noms de fichiers
    
    init(
        plantName: String? = nil,
        diameter: Double = 0,
        height: Double = 0,
        shape: PotShape = .round,
        material: PotMaterial? = nil,
        drainageHoles: Bool = true,
        notes: String = "",
        createdAt: Date = Date(),
        photos: [String] = []
    ) {
        self.plantName = plantName
        self.diameter = diameter
        self.height = height
        self.shape = shape
        self.material = material
        self.drainageHoles = drainageHoles
        self.notes = notes
        self.createdAt = createdAt
        self.photos = photos
        
        // Calcul automatique du volume selon la forme
        self.volume = shape.calculateVolume(diameter: diameter, height: height)
    }
    
    var volumeInLiters: String {
        return String(format: "%.1f L", volume)
    }
    
    var dimensionsText: String {
        return String(format: "Ø %.1f cm × %.1f cm", diameter, height)
    }
}

// MARK: - Pot Shape

enum PotShape: String, CaseIterable, Codable {
    case round = "round"
    case square = "square"
    case rectangular = "rectangular"
    case conical = "conical"
    
    var displayName: String {
        switch self {
        case .round:
            return NSLocalizedString("POT_SHAPE_ROUND", comment: "")
        case .square:
            return NSLocalizedString("POT_SHAPE_SQUARE", comment: "")
        case .rectangular:
            return NSLocalizedString("POT_SHAPE_RECTANGULAR", comment: "")
        case .conical:
            return NSLocalizedString("POT_SHAPE_CONICAL", comment: "")
        }
    }
    
    var icon: String {
        switch self {
        case .round:
            return "circle"
        case .square:
            return "square"
        case .rectangular:
            return "rectangle"
        case .conical:
            return "triangle"
        }
    }
    
    // Calcul du volume en litres
    func calculateVolume(diameter: Double, height: Double) -> Double {
        let radius = diameter / 2.0
        let volumeCm3: Double
        
        switch self {
        case .round:
            // Volume cylindre: π × r² × h
            volumeCm3 = Double.pi * radius * radius * height
        case .square:
            // Volume cube: côté² × h (on utilise diameter comme côté)
            volumeCm3 = diameter * diameter * height
        case .rectangular:
            // Volume rectangle: largeur × longueur × h (approximation)
            volumeCm3 = diameter * (diameter * 1.5) * height
        case .conical:
            // Volume cône: (π × r² × h) / 3
            volumeCm3 = (Double.pi * radius * radius * height) / 3.0
        }
        
        // Conversion cm³ en litres (1L = 1000cm³)
        return volumeCm3 / 1000.0
    }
}

// MARK: - Pot Material

enum PotMaterial: String, CaseIterable, Codable {
    case terracotta = "terracotta"
    case plastic = "plastic"
    case ceramic = "ceramic"
    case wood = "wood"
    case metal = "metal"
    case concrete = "concrete"
    
    var displayName: String {
        switch self {
        case .terracotta:
            return NSLocalizedString("POT_MATERIAL_TERRACOTTA", comment: "")
        case .plastic:
            return NSLocalizedString("POT_MATERIAL_PLASTIC", comment: "")
        case .ceramic:
            return NSLocalizedString("POT_MATERIAL_CERAMIC", comment: "")
        case .wood:
            return NSLocalizedString("POT_MATERIAL_WOOD", comment: "")
        case .metal:
            return NSLocalizedString("POT_MATERIAL_METAL", comment: "")
        case .concrete:
            return NSLocalizedString("POT_MATERIAL_CONCRETE", comment: "")
        }
    }
    
    var icon: String {
        switch self {
        case .terracotta:
            return "drop.triangle"
        case .plastic:
            return "cube.transparent"
        case .ceramic:
            return "sparkles"
        case .wood:
            return "tree"
        case .metal:
            return "bolt.circle"
        case .concrete:
            return "square.stack.3d.up"
        }
    }
    
    var characteristics: String {
        switch self {
        case .terracotta:
            return NSLocalizedString("POT_MATERIAL_TERRACOTTA_DESC", comment: "")
        case .plastic:
            return NSLocalizedString("POT_MATERIAL_PLASTIC_DESC", comment: "")
        case .ceramic:
            return NSLocalizedString("POT_MATERIAL_CERAMIC_DESC", comment: "")
        case .wood:
            return NSLocalizedString("POT_MATERIAL_WOOD_DESC", comment: "")
        case .metal:
            return NSLocalizedString("POT_MATERIAL_METAL_DESC", comment: "")
        case .concrete:
            return NSLocalizedString("POT_MATERIAL_CONCRETE_DESC", comment: "")
        }
    }
}

// MARK: - Measurement Recommendations

struct PotRecommendation {
    let currentVolume: Double
    let plantType: String?
    
    var needsRepotting: Bool {
        // Logique simple: si le pot fait moins de 2L, recommander rempotage
        return currentVolume < 2.0
    }
    
    var recommendedVolume: Double {
        // Recommandation: 1.5x le volume actuel
        return currentVolume * 1.5
    }
    
    var recommendedDiameter: Double {
        // Calcul du diamètre recommandé basé sur le volume
        // Pour un cylindre: d = 2 × sqrt(V / (π × h))
        // Supposons h ≈ d pour un pot standard
        return pow((recommendedVolume * 1000) / Double.pi, 1.0/3.0) * 2.0
    }
    
    var message: String {
        if needsRepotting {
            return NSLocalizedString("POT_RECOMMENDATION_NEEDS_REPOT", comment: "")
        } else {
            return NSLocalizedString("POT_RECOMMENDATION_SIZE_OK", comment: "")
        }
    }
}
