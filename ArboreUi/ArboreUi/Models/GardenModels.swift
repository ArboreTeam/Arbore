import Foundation

struct GardenWizardDTO: Codable {
    var style: String
    var spaceType: String
    var exposure: String?
    var maintenance: String?
    var safety: [String]?
    var soil: String?
    var scanMethod: String?
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

    var createdAt: Date?
    var updatedAt: Date?
}
