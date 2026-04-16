//
//  GardenDataModel.swift
//  ArboreUi
//
//  Created by hugo rath on 08/02/2026.
//

//
//  GardenDataModels.swift
//  ArboreUi
//
//  Fichier unique pour les modèles partagés entre la Vue AR et la Vue 2D
//

import Foundation
import SwiftUI

// MARK: - 1. Gestion des Fichiers (Local Store)
struct GardenLocalStore {
    static func worldMapURL(for gardenId: String) -> URL {
        documentsURL().appendingPathComponent("worldmap_\(gardenId).arexperience")
    }
    static func sceneURL(for gardenId: String) -> URL {
        documentsURL().appendingPathComponent("scene_\(gardenId).json")
    }
    private static func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

// MARK: - 2. Modèles de Sauvegarde (JSON)
struct PersistedARScene: Codable {
    let savedAt: Date
    let plants: [PersistedPlant]
    let boundaryPoints: [[Float]]?  // Points de bordure du jardin [x, y, z]
    let area: Float?                 // Surface du jardin en m²
    let perimeter: Float?            // Périmètre du jardin en m
    
    // Initializer pour rétro-compatibilité avec les anciens jardins
    init(savedAt: Date, plants: [PersistedPlant], boundaryPoints: [[Float]]? = nil, area: Float? = nil, perimeter: Float? = nil) {
        self.savedAt = savedAt
        self.plants = plants
        self.boundaryPoints = boundaryPoints
        self.area = area
        self.perimeter = perimeter
    }
}

struct PersistedPlant: Codable {
    let plantID: String
    let plantName: String
    let modelURLString: String
    let position: [Float]      // [x, y, z]
    let rotation: [Float]
    let scale: [Float]
    let transform: [Float]
    let upAxis: String?
}

// MARK: - 3. Modèle pour l'affichage liste
struct GardenModel: Identifiable {
    let id: String
    let name: String
    let lastModified: Date
    let thumbnail: String
}
