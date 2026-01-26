import Foundation

class PlantService: ObservableObject {
    @Published var plants: [Plant] = []

    func fetchPlants() {
        Task {
            do {
                let plants: [Plant] = try await NetworkManager.shared.request(
                    endpoint: "/plants",
                    method: .GET
                )

                await MainActor.run {
                    self.plants = plants
                }
            } catch {
                print("❌ Erreur lors de la récupération des plantes : \(error)")
            }
        }
    }
}
