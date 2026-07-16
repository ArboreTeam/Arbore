import Foundation
import simd

enum GardenLocationSource: String, Codable {
    case deviceApproximate
    case manualCity
}

/// Localisation volontairement grossière utilisée pour le climat local.
/// Le modèle ne contient aucun champ d'adresse et les coordonnées provenant
/// de l'appareil sont arrondies avant toute persistance ou transmission.
struct GardenLocationDTO: Codable, Equatable {
    var city: String?
    var latitude: Double?
    var longitude: Double?
    var source: GardenLocationSource

    static func deviceApproximate(
        latitude: Double,
        longitude: Double,
        city: String? = nil
    ) -> GardenLocationDTO {
        GardenLocationDTO(
            city: normalizedCity(city),
            latitude: roundedCoordinate(latitude),
            longitude: roundedCoordinate(longitude),
            source: .deviceApproximate
        )
    }

    static func manualCity(_ city: String) -> GardenLocationDTO {
        GardenLocationDTO(
            city: normalizedCity(city),
            latitude: nil,
            longitude: nil,
            source: .manualCity
        )
    }

    private static func roundedCoordinate(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private static func normalizedCity(_ city: String?) -> String? {
        let trimmed = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Direction de la principale source de lumière, capturée dans le même
/// repère AR que la géométrie du jardin. L'orientation magnétique permettra
/// de relier ensuite ce repère à la localisation fraîche du jardin.
struct GardenLightExposureDTO: Codable, Equatable {
    var directionX: Float
    var directionY: Float
    var directionZ: Float
    var magneticYawRadians: Double?
    var ambientIntensity: Double?

    static func capture(
        direction: SIMD3<Float>,
        magneticYawRadians: Double?,
        ambientIntensity: Double?
    ) -> GardenLightExposureDTO {
        let horizontal = SIMD3<Float>(direction.x, 0, direction.z)
        let normalized = simd_length(horizontal) > 0.0001
            ? simd_normalize(horizontal)
            : SIMD3<Float>(0, 0, -1)

        return GardenLightExposureDTO(
            directionX: normalized.x,
            directionY: normalized.y,
            directionZ: normalized.z,
            magneticYawRadians: magneticYawRadians,
            ambientIntensity: ambientIntensity
        )
    }
}

enum GardenDataSourceDTO: String, Codable {
    case measured
    case inferred
    case declared
    case regionalEstimate
}

enum GardenDataConfidenceDTO: String, Codable {
    case high
    case medium
    case low
}

struct GardenValueMetadataDTO: Codable, Equatable {
    var source: GardenDataSourceDTO
    var confidence: GardenDataConfidenceDTO
}

struct GardenOrientationDTO: Codable, Equatable {
    /// Direction en degrés, avec 0° = nord et une rotation dans le sens horaire.
    var degrees: Double
    var metadata: GardenValueMetadataDTO
}

struct GardenSunlightDTO: Codable, Equatable {
    var minimumHours: Double
    var maximumHours: Double
    var metadata: GardenValueMetadataDTO
}

enum GardenWindLevelDTO: String, Codable, CaseIterable {
    case sheltered
    case light
    case moderate
    case strong
}

struct GardenWindDTO: Codable, Equatable {
    var level: GardenWindLevelDTO
    var metadata: GardenValueMetadataDTO
}

struct GardenAvailableHeightDTO: Codable, Equatable {
    var meters: Double
    var metadata: GardenValueMetadataDTO
}

struct GardenPlantingZoneDTO: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    /// Polygone exprimé dans le même repère X/Y/Z que le contour mesuré.
    var points: [[Float]]
    var isExcluded: Bool
    var metadata: GardenValueMetadataDTO
}

/// Informations durables de la fiche 2D. Les champs restent optionnels tant
/// qu'ils n'ont pas été réellement mesurés, déduits ou déclarés.
struct GardenSiteProfileDTO: Codable, Equatable {
    var orientation: GardenOrientationDTO?
    var sunlight: GardenSunlightDTO?
    var wind: GardenWindDTO?
    var availableHeight: GardenAvailableHeightDTO?
    var plantingZones: [GardenPlantingZoneDTO]

    init(
        orientation: GardenOrientationDTO? = nil,
        sunlight: GardenSunlightDTO? = nil,
        wind: GardenWindDTO? = nil,
        availableHeight: GardenAvailableHeightDTO? = nil,
        plantingZones: [GardenPlantingZoneDTO] = []
    ) {
        self.orientation = orientation
        self.sunlight = sunlight
        self.wind = wind
        self.availableHeight = availableHeight
        self.plantingZones = plantingZones
    }
}

/// Réponses déclaratives que le scan et la localisation ne peuvent pas
/// déterminer de façon fiable. Tous les champs sont optionnels : ignorer une
/// question ou choisir « Je ne sais pas » ne crée aucune fausse donnée.
struct GardenConditionalAnswersDTO: Codable, Equatable {
    var plantingMode: GardenPlantingModeDTO?
    var drainage: GardenDrainageDTO?
    var windExposure: GardenWindExposureDTO?
    var containerProject: GardenContainerProjectDTO?
    var indoorHumidity: GardenIndoorHumidityDTO?
    var nearbyHeat: GardenNearbyHeatDTO?

    init(
        plantingMode: GardenPlantingModeDTO? = nil,
        drainage: GardenDrainageDTO? = nil,
        windExposure: GardenWindExposureDTO? = nil,
        containerProject: GardenContainerProjectDTO? = nil,
        indoorHumidity: GardenIndoorHumidityDTO? = nil,
        nearbyHeat: GardenNearbyHeatDTO? = nil
    ) {
        self.plantingMode = plantingMode
        self.drainage = drainage
        self.windExposure = windExposure
        self.containerProject = containerProject
        self.indoorHumidity = indoorHumidity
        self.nearbyHeat = nearbyHeat
    }

    var isEmpty: Bool {
        plantingMode == nil
            && drainage == nil
            && windExposure == nil
            && containerProject == nil
            && indoorHumidity == nil
            && nearbyHeat == nil
    }
}

enum GardenPlantingModeDTO: String, Codable {
    case inGround
    case containers
    case both
}

enum GardenDrainageDTO: String, Codable {
    case fast
    case normal
    case slow
}

enum GardenWindExposureDTO: String, Codable {
    case sheltered
    case sometimesWindy
    case veryExposed
}

enum GardenContainerProjectDTO: String, Codable {
    case existingPots
    case newComposition
    case both
}

enum GardenIndoorHumidityDTO: String, Codable {
    case dry
    case normal
    case humid
}

enum GardenNearbyHeatDTO: String, Codable {
    case none
    case radiator
    case underfloorHeating
}

struct GardenWizardDTO: Codable {
    var style: String
    var spaceType: String
    var exposure: String?
    var maintenance: String?
    var safety: [String]?
    var soil: String?
    var scanMethod: String?
    var location: GardenLocationDTO? = nil
    var lightExposure: GardenLightExposureDTO? = nil
    var siteProfile: GardenSiteProfileDTO? = nil
    var conditionalAnswers: GardenConditionalAnswersDTO? = nil
}

struct GardenMeasurementsDTO: Codable {
    var boundaryPoints: [[Float]]?
    var area: Float?
    var perimeter: Float?
}

struct PlacedPlantDTO: Codable, Identifiable {
    // Identifiable pour SwiftUI si besoin
    var id: String { plantId }

    var plantId: String

    // Optionnel (tu peux laisser nil tant que tu ne veux pas stocker une position)
    var x: Double?
    var y: Double?
    var z: Double?

    var note: String?
}

struct GardenDTO: Codable, Identifiable {
    var id: String?           // Mongo ObjectID (hex)
    var uid: String
    var name: String
    var wizard: GardenWizardDTO
    var plants: [PlacedPlantDTO]
    var thumbnailKey: String?
    var measurements: GardenMeasurementsDTO?

    var createdAt: Date?
    var updatedAt: Date?
}
