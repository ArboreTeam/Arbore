import Foundation

/// Payload envoyé au backend quand tu crées un jardin (POST /gardens)
/// (sans id/createdAt/updatedAt qui sont gérés côté serveur)
struct GardenCreateDTO: Codable {
    var uid: String
    var name: String
    var wizard: GardenWizardDTO
    var plants: [PlacedPlantDTO]
    var thumbnailKey: String?
}
