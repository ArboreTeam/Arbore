//
//  GardenProject.swift
//  ArboreUi
//
//  Created on November 25, 2025.
//

import Foundation
import CoreLocation
import SwiftUI

// MARK: - Garden Project Model

struct GardenProject: Identifiable, Codable {
    let id: String
    var name: String
    var createdAt: Date
    var updatedAt: Date
    
    // Étape 1: Scan du jardin
    var scanData: ScanData?
    
    // Étape 2: Photos et vidéos
    var mediaFiles: [MediaFile]
    
    // Étape 3: Informations du jardin
    var gardenInfo: GardenInfo?
    
    // Étape 4: Localisation et climat
    var location: LocationData?
    
    // Étape 5: Préférences utilisateur
    var preferences: GardenPreferences?
    
    // Étape 6: Zones de plantation
    var plantingZones: [PlantingZone]
    
    // État du projet
    var status: ProjectStatus
    var completionPercentage: Double {
        var completed: Double = 0
        let total: Double = 6
        
        if scanData != nil { completed += 1 }
        if !mediaFiles.isEmpty { completed += 1 }
        if gardenInfo != nil { completed += 1 }
        if location != nil { completed += 1 }
        if preferences != nil { completed += 1 }
        if !plantingZones.isEmpty { completed += 1 }
        
        return (completed / total) * 100
    }
    
    init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.mediaFiles = []
        self.plantingZones = []
        self.status = .inProgress
    }
}

// MARK: - Project Status

enum ProjectStatus: String, Codable {
    case inProgress = "En cours"
    case completed = "Terminé"
    case analyzing = "Analyse IA"
    case ready = "Prêt à planter"
}

// MARK: - Scan Data

struct ScanData: Codable {
    let scanURL: String // URL du fichier .usdz ou .reality
    let scanDate: Date
    let area: Double // en m²
    let scanType: ScanType
    
    enum ScanType: String, Codable {
        case room = "Pièce"
        case outdoor = "Extérieur"
        case both = "Intérieur/Extérieur"
    }
}

// MARK: - Media File

struct MediaFile: Identifiable, Codable {
    let id: String
    let url: String
    let type: MediaType
    let uploadDate: Date
    var caption: String?
    
    enum MediaType: String, Codable {
        case photo = "Photo"
        case video = "Vidéo"
    }
    
    init(id: String = UUID().uuidString, url: String, type: MediaType, caption: String? = nil) {
        self.id = id
        self.url = url
        self.type = type
        self.uploadDate = Date()
        self.caption = caption
    }
}

// MARK: - Garden Info

struct GardenInfo: Codable {
    var isIndoor: Bool
    var isOutdoor: Bool
    var sunExposure: SunExposure
    var soilType: SoilType?
    var hasWaterAccess: Bool
    var hasAutomaticIrrigation: Bool
    
    enum SunExposure: String, Codable, CaseIterable {
        case fullSun = "Plein soleil (6h+)"
        case partialSun = "Mi-ombre (3-6h)"
        case shade = "Ombre (moins de 3h)"
        case mixed = "Mixte"
    }
    
    enum SoilType: String, Codable, CaseIterable {
        case clay = "Argileux"
        case sandy = "Sableux"
        case loamy = "Limoneux"
        case chalky = "Calcaire"
        case peaty = "Tourbeux"
        case unknown = "Je ne sais pas"
    }
}

// MARK: - Location Data

struct LocationData: Codable {
    let latitude: Double
    let longitude: Double
    let city: String?
    let country: String?
    let climateZone: String?
    let averageTemperature: Double?
    let hardinessZone: String? // Zone de rusticité
    
    init(coordinate: CLLocationCoordinate2D, city: String? = nil, country: String? = nil) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.city = city
        self.country = country
        self.climateZone = nil
        self.averageTemperature = nil
        self.hardinessZone = nil
    }
}

// MARK: - Garden Preferences

struct GardenPreferences: Codable {
    var plantTypes: [PlantType]
    var gardenStyle: GardenStyle
    var densityLevel: DensityLevel
    var maintenanceLevel: MaintenanceLevel
    var plantComplexity: ComplexityLevel
    var budget: BudgetRange?
    var colorPreferences: [String]
    var hasChildren: Bool
    var hasPets: Bool
    var wantsEdiblePlants: Bool
    var wantsFlowers: Bool
    var wantsEvergreen: Bool
    
    enum PlantType: String, Codable, CaseIterable {
        case flowers = "Fleurs"
        case shrubs = "Arbustes"
        case trees = "Arbres"
        case vegetables = "Légumes"
        case herbs = "Herbes aromatiques"
        case succulents = "Succulentes"
        case grasses = "Graminées"
        case climbers = "Plantes grimpantes"
    }
    
    enum GardenStyle: String, Codable, CaseIterable {
        case modern = "Moderne"
        case traditional = "Traditionnel"
        case japanese = "Japonais"
        case mediterranean = "Méditerranéen"
        case cottage = "Cottage"
        case tropical = "Tropical"
        case minimalist = "Minimaliste"
        case wild = "Sauvage/Naturel"
    }
    
    enum DensityLevel: String, Codable, CaseIterable {
        case sparse = "Épuré (peu de plantes)"
        case moderate = "Modéré"
        case dense = "Dense (beaucoup de plantes)"
    }
    
    enum MaintenanceLevel: String, Codable, CaseIterable {
        case veryLow = "Très facile (arrosage rare)"
        case low = "Facile (1x/semaine)"
        case moderate = "Modéré (2-3x/semaine)"
        case high = "Intensif (quotidien)"
    }
    
    enum ComplexityLevel: String, Codable, CaseIterable {
        case beginner = "Débutant (plantes résistantes)"
        case intermediate = "Intermédiaire"
        case advanced = "Expert (plantes exigeantes)"
        case mixed = "Mixte"
    }
    
    enum BudgetRange: String, Codable, CaseIterable {
        case low = "Petit budget (< 100€)"
        case medium = "Moyen (100-500€)"
        case high = "Élevé (500-1000€)"
        case unlimited = "Illimité"
    }
}

// MARK: - Planting Zone

struct PlantingZone: Identifiable, Codable {
    let id: String
    var name: String
    var drawnPath: [CGPoint] // Points dessinés par l'utilisateur sur le scan
    var area: Double // en m²
    var plantType: GardenPreferences.PlantType?
    var notes: String?
    var suggestedPlants: [String] // IDs des plantes suggérées par l'IA
    
    init(id: String = UUID().uuidString, name: String, drawnPath: [CGPoint]) {
        self.id = id
        self.name = name
        self.drawnPath = drawnPath
        self.area = 0
        self.suggestedPlants = []
    }
}
