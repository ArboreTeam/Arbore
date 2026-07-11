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
                            Text(L10n.t("MY_GARDEN_MY_PLANTS"))
                        }

                    wishlistSection
                        .tabItem {
                            Image(systemName: "heart.fill")
                            Text(L10n.t("MY_GARDEN_WISHLIST"))
                        }

                    statisticsSection
                        .tabItem {
                            Image(systemName: "chart.bar.fill")
                            Text(L10n.t("MY_GARDEN_STATS"))
                        }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            }
            .background(themeManager.backgroundColor)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .searchable(text: $searchText, prompt: L10n.t("MY_GARDEN_SEARCH_PROMPT"))
        }
        .preferredColorScheme(themeManager.colorScheme)
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("MY_GARDEN_TITLE"))
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(themeManager.textColor)
                    
                    Text(L10n.t("MY_GARDEN_SUBTITLE"))
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
                        .foregroundColor(themeManager.accentColor)
                }
            }
            .padding(.horizontal)
            
            // Cards avec statistiques rapides
            HStack(spacing: 12) {
                StatCard(
                    title: L10n.t("MY_GARDEN_STAT_PLANTS"),
                    value: "\(myPlants.count)",
                    icon: "leaf.fill",
                    color: themeManager.systemGreen
                )
                
                StatCard(
                    title: L10n.t("MY_GARDEN_STAT_TO_WATER"),
                    value: "3",
                    icon: "drop.fill",
                    color: themeManager.systemBlue
                )
                
                StatCard(
                    title: L10n.t("MY_GARDEN_STAT_HEALTHY"),
                    value: "95%",
                    icon: "heart.fill",
                    color: themeManager.systemRed
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
                        title: L10n.t("MY_GARDEN_EMPTY_PLANTS_TITLE"),
                        description: L10n.t("MY_GARDEN_EMPTY_PLANTS_DESCRIPTION"),
                        buttonText: L10n.t("MY_GARDEN_ADD_PLANT"),
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
                        title: L10n.t("MY_GARDEN_EMPTY_WISHLIST_TITLE"),
                        description: L10n.t("MY_GARDEN_EMPTY_WISHLIST_DESCRIPTION"),
                        buttonText: L10n.t("MY_GARDEN_EXPLORE_CATALOG"),
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
                    Text(L10n.t("MY_GARDEN_HEALTH_TITLE"))
                        .font(.headline)
                        .foregroundColor(themeManager.textColor)
                    
                    HStack {
                        VStack {
                            Circle()
                                .fill(themeManager.systemGreen)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Text("95%")
                                        .font(.caption)
                                        .bold()
                                        .foregroundColor(.white)
                                )
                            Text(L10n.t("MY_GARDEN_HEALTH_EXCELLENT"))
                                .font(.caption2)
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HealthBarItem(label: L10n.t("MY_GARDEN_HEALTH_HYDRATED"), percentage: 0.9, color: themeManager.systemBlue)
                            HealthBarItem(label: L10n.t("MY_GARDEN_HEALTH_EXPOSED"), percentage: 0.85, color: themeManager.adjust(.orange))
                            HealthBarItem(label: L10n.t("MY_GARDEN_HEALTH_FED"), percentage: 0.95, color: themeManager.systemGreen)
                        }
                    }
                }
                .padding()
                .background(themeManager.cardBackgroundColor)
                .cornerRadius(16)
                
                // Activité récente
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.t("MY_GARDEN_RECENT_ACTIVITY"))
                        .font(.headline)
                        .foregroundColor(themeManager.textColor)
                    
                    VStack(spacing: 8) {
                        ActivityItem(
                            icon: "drop.fill",
                            text: L10n.t("MY_GARDEN_ACTIVITY_WATERED"),
                            time: L10n.t("MY_GARDEN_TIME_2H_AGO"),
                            color: themeManager.systemBlue
                        )
                        ActivityItem(
                            icon: "leaf.fill",
                            text: L10n.t("MY_GARDEN_ACTIVITY_NEW_GROWTH"),
                            time: L10n.t("MY_GARDEN_TIME_YESTERDAY"),
                            color: themeManager.systemGreen
                        )
                        ActivityItem(
                            icon: "plus.circle.fill",
                            text: L10n.t("MY_GARDEN_ACTIVITY_ADDED"),
                            time: L10n.t("MY_GARDEN_TIME_3_DAYS_AGO"),
                            color: themeManager.adjust(.purple)
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
                .foregroundColor(themeManager.accentColor.opacity(0.6))
            
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
                    .background(themeManager.accentColor)
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
                    .fill(themeManager.cardBackgroundColor)
                    .overlay(
                        Image(systemName: "leaf.fill")
                            .foregroundColor(themeManager.secondaryTextColor)
                    )
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(plant.name)
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                Text(L10n.t("MY_GARDEN_LAST_ACTIVITY_WATERING"))
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
            }
            
            Spacer()
            
            VStack {
                // Indicateur de santé
                Circle()
                    .fill(themeManager.systemGreen)
                    .frame(width: 12, height: 12)
                
                Text(L10n.t("MY_GARDEN_HEALTH_GOOD"))
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
                    .fill(themeManager.cardBackgroundColor)
                    .overlay(
                        Image(systemName: "heart.fill")
                            .foregroundColor(themeManager.systemRed)
                    )
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(plant.name)
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                Text(L10n.t("MY_GARDEN_ADDED_TO_LIST"))
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
            }
            
            Spacer()
            
            Button(action: {
                // Action pour ajouter au jardin
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(themeManager.accentColor)
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
