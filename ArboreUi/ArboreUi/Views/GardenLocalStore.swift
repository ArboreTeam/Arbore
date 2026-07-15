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

// MARK: - Convention de coordonnées
//
// Tout ce qui est persisté dans `scene_<id>.json` est en **frame monde
// ARKit** (mètres, repère défini au démarrage de la session). Cela
// concerne :
//   - `plants[*].position`         : [x, y, z] en world frame
//   - `plants[*].transform[12..14]`: tx, ty, tz en world frame
//   - `plants[*].surfaceHeight`    : Y de la surface en world frame
//   - `plants[*].placementMode`    : intention AR ("floor", "wall", "ceiling")
//   - `boundaryPoints[*]`          : [x, y, z] en world frame
//
// `position[0,2]` et `transform[12,14]` du même plant doivent toujours
// être égaux (sauf 1-2 mm de drift de stripScale). C'est le contrat de
// l'issue #170 / #136 — pré-fix, certains chemins de save soustrayaient
// le centroïde de la boundary à `position` et `boundaryPoints` (mais pas
// à `transform`), produisant un JSON en 2 frames incompatibles.
//
// `PersistedARScene.normalizedToWorldFrame()` détecte les jardins legacy
// (offset constant entre `position` et `transform`) et les migre en
// mémoire au moment de la lecture. Tous les consommateurs (restore,
// morpher, saveMeasurementsOnly, saveToDisk reopen) doivent appeler
// `.normalizedToWorldFrame()` après JSONDecoder.decode().

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

struct PersistedSurfaceAnchor: Codable, Equatable {
    let source: String
    let reliabilityScore: Float
    let normal: [Float]
    let center: [Float]?
    let extent: [Float]?
    let localOffset: [Float]?
    let worldPosition: [Float]

    init(
        source: String,
        reliabilityScore: Float,
        normal: [Float],
        center: [Float]? = nil,
        extent: [Float]? = nil,
        localOffset: [Float]? = nil,
        worldPosition: [Float]
    ) {
        self.source = source
        self.reliabilityScore = reliabilityScore
        self.normal = normal
        self.center = center
        self.extent = extent
        self.localOffset = localOffset
        self.worldPosition = worldPosition
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
    // Issue #113 — surface info for snap-to-plane on elevated plants.
    // Optional for backward compatibility with old saved JSONs.
    let surfaceType: String?     // SurfaceType raw value, legacy "elevated", or nil
    let surfaceHeight: Float?    // Y of the surface at save-time, in world coords
    // AR multi-surface placement intent. Optional for old saved JSONs.
    let placementMode: String?   // "floor" | "wall" | "ceiling" | nil
    // Premium anchoring metadata. Optional for old saved JSONs.
    let surfaceAnchor: PersistedSurfaceAnchor?
    // LOD : indique si une version 3D haute définition existe pour cette plante,
    // pour ré-déclencher le swap heavy à la ré-ouverture du jardin. Optionnel →
    // les anciennes sauvegardes (sans la clé) décodent à nil (= pas d'upgrade).
    let hasHeavy: Bool?

    init(
        plantID: String,
        plantName: String,
        modelURLString: String,
        position: [Float],
        rotation: [Float],
        scale: [Float],
        transform: [Float],
        upAxis: String? = nil,
        surfaceType: String? = nil,
        surfaceHeight: Float? = nil,
        placementMode: String? = nil,
        surfaceAnchor: PersistedSurfaceAnchor? = nil,
        hasHeavy: Bool? = nil
    ) {
        self.plantID = plantID
        self.plantName = plantName
        self.modelURLString = modelURLString
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.transform = transform
        self.upAxis = upAxis
        self.surfaceType = surfaceType
        self.surfaceHeight = surfaceHeight
        self.placementMode = placementMode
        self.surfaceAnchor = surfaceAnchor
        self.hasHeavy = hasHeavy
    }
}

// MARK: - 3. Modèle pour l'affichage liste
struct GardenModel: Identifiable {
    let id: String
    let name: String
    let lastModified: Date
    let thumbnail: String
}

// MARK: - 4. Migration legacy → world frame

extension PersistedARScene {
    /// Renvoie une copie du scène garantie en frame monde ARKit (cf entête
    /// du fichier). Si la scène est déjà en frame monde, renvoie `self`
    /// inchangé. Si elle est en frame legacy (`position` shifté par le
    /// centroïde de la boundary, `transform` non-shifté), migre :
    ///   1. réécrit chaque `plant.position[0,2]` depuis `plant.transform[12,14]`
    ///   2. ajoute le centroïde déduit à chaque `boundaryPoints[i]`
    ///
    /// La détection compare l'écart `transform[12] - position[0]` (et 14/2)
    /// par plante : tous les plants d'un même jardin legacy partagent le
    /// même centroïde, donc le même offset. On utilise la médiane pour
    /// résister à un plant qui aurait été drag-and-saved indépendamment.
    func normalizedToWorldFrame() -> PersistedARScene {
        guard !plants.isEmpty else { return self }

        // Per-plant offset between transform translation and stored position.
        // For a world-frame garden, all offsets ≈ 0. For a legacy garden, all
        // offsets ≈ boundary centroid.
        var offsetsX: [Float] = []
        var offsetsZ: [Float] = []
        for plant in plants {
            guard plant.position.count >= 3, plant.transform.count == 16 else { continue }
            offsetsX.append(plant.transform[12] - plant.position[0])
            offsetsZ.append(plant.transform[14] - plant.position[2])
        }
        guard !offsetsX.isEmpty else { return self }

        let medianX = Self.median(offsetsX)
        let medianZ = Self.median(offsetsZ)

        // Threshold : 1 cm. Below this we consider the scene already in
        // world frame (drift between transform and position is negligible).
        let epsilon: Float = 0.01
        if abs(medianX) < epsilon && abs(medianZ) < epsilon {
            return self
        }

        // Migration : plants take their position from transform (source of
        // truth in world frame). Boundary points get the centroid added back.
        let migratedPlants = plants.map { plant -> PersistedPlant in
            guard plant.position.count >= 3, plant.transform.count == 16 else {
                return plant
            }
            return PersistedPlant(
                plantID: plant.plantID,
                plantName: plant.plantName,
                modelURLString: plant.modelURLString,
                position: [plant.transform[12], plant.position[1], plant.transform[14]],
                rotation: plant.rotation,
                scale: plant.scale,
                transform: plant.transform,
                upAxis: plant.upAxis,
                surfaceType: plant.surfaceType,
                surfaceHeight: plant.surfaceHeight,
                placementMode: plant.placementMode,
                surfaceAnchor: plant.surfaceAnchor,
                hasHeavy: plant.hasHeavy
            )
        }

        let migratedBoundary: [[Float]]? = boundaryPoints.map { points in
            points.map { point in
                guard point.count >= 3 else { return point }
                return [point[0] + medianX, point[1], point[2] + medianZ]
            }
        }

        return PersistedARScene(
            savedAt: savedAt,
            plants: migratedPlants,
            boundaryPoints: migratedBoundary,
            area: area,
            perimeter: perimeter
        )
    }

    private static func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let n = sorted.count
        if n == 0 { return 0 }
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }
}
