import Foundation

class PlantService: ObservableObject {
    @Published var plants: [Plant] = []
    
    func fetchPlants() {
        guard let url = URL(string: AppConfig.plantsEndpoint) else {
            print("❌ URL invalide")
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ Erreur lors de la récupération des plantes : \(error)")
                return
            }
            
            guard let data = data else {
                print("❌ Pas de données reçues")
                return
            }
            
            do {
                let decodedPlants = try JSONDecoder().decode([Plant].self, from: data)
                DispatchQueue.main.async {
                    self.plants = decodedPlants
                }
            } catch {
                print("❌ Erreur lors du décodage JSON : \(error)")
            }
        }.resume()
    }
}
