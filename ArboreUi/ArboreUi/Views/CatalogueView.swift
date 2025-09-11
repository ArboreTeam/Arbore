import SwiftUI

struct CatalogueView: View {
    @State private var showArticleDetail = false
    @State private var selectedPlant: Plant?
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var plants: [Plant] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var animatedSelection: Plant?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ✅ Barre de recherche avec fond vert foncé
                ZStack(alignment: .bottom) {
                    Color(hex: "#263826")
                        .ignoresSafeArea(edges: .top)

                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)

                            TextField("Search", text: $searchText)
                                .font(.system(size: 16))
                                .foregroundColor(.black)
                                .animation(.easeInOut(duration: 0.25), value: searchText)

                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }

                            NavigationLink(destination: FilterView()) {
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundColor(Color(hex: "#263826"))
                                    .padding(.leading, 4)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(hex: "#263826"), lineWidth: 1)
                        )
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
                        .padding(.horizontal, 20)

                        // ✅ Compteur de résultats
                        HStack {
                            Text("\(filteredPlants.count) résultat\(filteredPlants.count > 1 ? "s" : "")")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.leading, 4)
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 10)
                    }
                }
                .frame(height: 95)

                // ✅ Liste des plantes
                if isLoading {
                    ProgressView("Chargement des plantes...")
                        .padding()
                } else if let errorMessage = errorMessage {
                    Text("❌ \(errorMessage)")
                        .foregroundColor(.red)
                        .padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 15),
                            GridItem(.flexible(), spacing: 15)
                        ], spacing: 20) {
                            ForEach(filteredPlants) { plant in
                                NavigationLink(destination: PlantDetailView(plantID: plant.id)) {
                                    PlantCard(plant: plant)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .background(Color(hex: "#F1F5ED").ignoresSafeArea())
            .navigationBarBackButtonHidden(true)
            .onAppear(perform: fetchPlants)
        }
    }

    var filteredPlants: [Plant] {
        if searchText.isEmpty {
            return plants
        } else {
            return plants.filter { $0.name.lowercased().contains(searchText.lowercased()) }
        }
    }

    func fetchPlants() {
        guard let url = URL(string: "http://79.137.92.154:8080/plants") else {
            self.errorMessage = "URL invalide"
            self.isLoading = false
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error {
                    self.errorMessage = "Erreur de connexion : \(error.localizedDescription)"
                    return
                }

                guard let data = data else {
                    self.errorMessage = "Données non valides"
                    return
                }

                do {
                    self.plants = try JSONDecoder().decode([Plant].self, from: data)
                } catch {
                    self.errorMessage = "Erreur lors du décodage des données"
                }
            }
        }.resume()
    }
}
