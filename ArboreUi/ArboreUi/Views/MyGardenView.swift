import SwiftUI

struct MyGardenView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var searchText = ""
    
    // Données exemple - à remplacer par vos vraies données
    @State private var myPlants: [Plant] = []
    @State private var wishlistPlants: [Plant] = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header avec statistiques
                headerSection
                
                TabView {
                    myPlantsSection
                        .tabItem {
                            Image(systemName: "leaf.fill")
                            Text("Mes Plantes")
                        }

                    wishlistSection
                        .tabItem {
                            Image(systemName: "heart.fill")
                            Text("Souhaits")
                        }

                    statisticsSection
                        .tabItem {
                            Image(systemName: "chart.bar.fill")
                            Text("Stats")
                        }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            }
            .background(themeManager.backgroundColor)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .searchable(text: $searchText, prompt: "Rechercher dans mon jardin")
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mon Jardin")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(themeManager.textColor)
                    
                    Text("Gérez votre collection de plantes")
                        .font(.subheadline)
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                
                Spacer()
                
                // Bouton d'ajout de plante
                Button(action: {
                    // Action pour ajouter une plante
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal)
            
            // Cards avec statistiques rapides
            HStack(spacing: 12) {
                StatCard(
                    title: "Mes Plantes",
                    value: "\(myPlants.count)",
                    icon: "leaf.fill",
                    color: .green
                )
                
                StatCard(
                    title: "À Arroser",
                    value: "3",
                    icon: "drop.fill",
                    color: .blue
                )
                
                StatCard(
                    title: "En Santé",
                    value: "95%",
                    icon: "heart.fill",
                    color: .red
                )
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(themeManager.backgroundColor)
    }
    
    // MARK: - My Plants Section
    private var myPlantsSection: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if myPlants.isEmpty {
                    emptyStateView(
                        title: "Aucune plante pour le moment",
                        description: "Commencez à construire votre jardin en ajoutant votre première plante !",
                        buttonText: "Ajouter une plante",
                        action: {}
                    )
                } else {
                    ForEach(filteredPlants, id: \.id) { plant in
                        PlantGardenCard(plant: plant)
                            .environmentObject(themeManager)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Wishlist Section
    private var wishlistSection: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if wishlistPlants.isEmpty {
                    emptyStateView(
                        title: "Votre liste de souhaits est vide",
                        description: "Ajoutez des plantes que vous aimeriez avoir dans votre jardin !",
                        buttonText: "Explorer le catalogue",
                        action: {}
                    )
                } else {
                    ForEach(wishlistPlants, id: \.id) { plant in
                        WishlistPlantCard(plant: plant)
                            .environmentObject(themeManager)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Statistics Section
    private var statisticsSection: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Graphique de santé des plantes
                VStack(alignment: .leading, spacing: 12) {
                    Text("Santé de vos plantes")
                        .font(.headline)
                        .foregroundColor(themeManager.textColor)
                    
                    HStack {
                        VStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Text("95%")
                                        .font(.caption)
                                        .bold()
                                        .foregroundColor(.white)
                                )
                            Text("Excellente")
                                .font(.caption2)
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HealthBarItem(label: "Bien hydratées", percentage: 0.9, color: .blue)
                            HealthBarItem(label: "Bien exposées", percentage: 0.85, color: .orange)
                            HealthBarItem(label: "Bien nourries", percentage: 0.95, color: .green)
                        }
                    }
                }
                .padding()
                .background(themeManager.cardBackgroundColor)
                .cornerRadius(16)
                
                // Activité récente
                VStack(alignment: .leading, spacing: 12) {
                    Text("Activité récente")
                        .font(.headline)
                        .foregroundColor(themeManager.textColor)
                    
                    VStack(spacing: 8) {
                        ActivityItem(
                            icon: "drop.fill",
                            text: "Monstera arrosée",
                            time: "Il y a 2h",
                            color: .blue
                        )
                        ActivityItem(
                            icon: "leaf.fill",
                            text: "Nouvelle pousse sur le Ficus",
                            time: "Hier",
                            color: .green
                        )
                        ActivityItem(
                            icon: "plus.circle.fill",
                            text: "Pothos ajouté au jardin",
                            time: "Il y a 3 jours",
                            color: .purple
                        )
                    }
                }
                .padding()
                .background(themeManager.cardBackgroundColor)
                .cornerRadius(16)
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Helper Views
    private func emptyStateView(title: String, description: String, buttonText: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "leaf.circle")
                .font(.system(size: 60))
                .foregroundColor(.green.opacity(0.6))
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(themeManager.secondaryTextColor)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: action) {
                Text(buttonText)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(12)
            }
        }
        .padding(.vertical, 40)
    }
    
    private var filteredPlants: [Plant] {
        if searchText.isEmpty {
            return myPlants
        } else {
            return myPlants.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .bold()
                .foregroundColor(themeManager.textColor)
            
            Text(title)
                .font(.caption)
                .foregroundColor(themeManager.secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(themeManager.cardBackgroundColor)
        .cornerRadius(12)
    }
}

struct PlantGardenCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let plant: Plant
    
    var body: some View {
        HStack(spacing: 12) {
            // Image de la plante (utilise la première image du tableau imageURLs)
            AsyncImage(url: URL(string: plant.imageURLs.first ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "leaf.fill")
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(plant.name)
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                Text("Dernière activité: Arrosage")
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
            }
            
            Spacer()
            
            VStack {
                // Indicateur de santé
                Circle()
                    .fill(Color.green)
                    .frame(width: 12, height: 12)
                
                Text("Bonne")
                    .font(.caption2)
                    .foregroundColor(themeManager.secondaryTextColor)
            }
        }
        .padding()
        .background(themeManager.cardBackgroundColor)
        .cornerRadius(16)
    }
}

struct WishlistPlantCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let plant: Plant
    
    var body: some View {
        HStack(spacing: 12) {
            // Image de la plante (utilise la première image du tableau imageURLs)
            AsyncImage(url: URL(string: plant.imageURLs.first ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                    )
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(plant.name)
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                Text("Ajouté à la liste")
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
            }
            
            Spacer()
            
            Button(action: {
                // Action pour ajouter au jardin
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(themeManager.cardBackgroundColor)
        .cornerRadius(16)
    }
}

struct HealthBarItem: View {
    @EnvironmentObject var themeManager: ThemeManager
    let label: String
    let percentage: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
                Spacer()
                Text("\(Int(percentage * 100))%")
                    .font(.caption)
                    .bold()
                    .foregroundColor(themeManager.textColor)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * percentage, height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
        }
    }
}

struct ActivityItem: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    let text: String
    let time: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.caption)
                    .foregroundColor(themeManager.textColor)
                
                Text(time)
                    .font(.caption2)
                    .foregroundColor(themeManager.secondaryTextColor)
            }
            
            Spacer()
        }
    }
}
