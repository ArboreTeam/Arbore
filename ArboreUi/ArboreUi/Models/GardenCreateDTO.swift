import Foundation

/// Payload envoyé au backend quand tu crées un jardin (POST /gardens)
/// (sans id/uid/createdAt/updatedAt qui sont gérés côté serveur — uid est lu depuis le JWT)
struct GardenCreateDTO: Codable {
    var name: String
    var wizard: GardenWizardDTO
    var plants: [PlacedPlantDTO]
    var thumbnailKey: String?
}
