import Foundation

enum DistortionSeverity: String {
    case ok        // score < 1.2
    case moderate  // 1.2 ≤ score < 1.8 — orange visual hint
    case severe    // score ≥ 1.8 — alert user
}

struct DistortionWarning: Identifiable {
    let id: String
    let plantId: String
    let plantName: String
    let zone: String         // cardinal direction (e.g. "NORD-EST")
    let score: Float
    let severity: DistortionSeverity

    init(plantId: String, plantName: String, zone: String, score: Float, severity: DistortionSeverity) {
        self.id = plantId
        self.plantId = plantId
        self.plantName = plantName
        self.zone = zone
        self.score = score
        self.severity = severity
    }
}
