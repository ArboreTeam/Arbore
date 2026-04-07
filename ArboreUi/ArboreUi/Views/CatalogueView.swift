import SwiftUI

struct CatalogueView: View {
    // MARK: - Propriétés

    @State private var showArticleDetail = false
    @State private var selectedPlant: Plant?
    @EnvironmentObject var themeManager: ThemeManager
    
    // Données et état
    @State private var searchText = ""
    @State private var plants: [Plant] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    // Filtres
    @State private var filters = PlantFilters()
    @State private var showFilters = false
    
    // Focus pour le clavier (optionnel mais recommandé pour l'UX)
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                // 1. Fond général
                themeManager.backgroundColor
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 2. En-tête personnalisé (Titre + Recherche)
                    headerView
                    
                    // 3. Contenu principal (Grille)
                    contentView
                }
            }
            .navigationBarHidden(true) // On cache la nav bar native pour utiliser la nôtre
            .sheet(isPresented: $showFilters) {
                FilterView(filters: $filters)
                    .environmentObject(themeManager)
            }
            .onAppear {
                fetchPlants()
            }
        }
    }
    
    // MARK: - Vue de l'En-tête (Design Épuré)
    var headerView: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // Titre de la page
            Text(NSLocalizedString("CATALOG_TITLE", value: "Catalogue", comment: "Page Title"))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(themeManager.textColor)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            
            // Barre de recherche stylisée
            HStack(spacing: 12) {
                // Loupe
                Image(systemName: "magnifyingglass")
                    .foregroundColor(themeManager.secondaryTextColor)
                    .font(.system(size: 18, weight: .semibold))
                
                // Champ de texte
                TextField(
                    NSLocalizedString("CATALOG_SEARCH_PLACEHOLDER", comment: "Search placeholder"),
                    text: $searchText
                )
                .focused($isSearchFocused)
                .foregroundColor(themeManager.textColor)
                
                // Bouton effacer (X)
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        isSearchFocused = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(themeManager.secondaryTextColor)
                    }
                }
                
                // Séparateur vertical
                Divider()
                    .frame(height: 20)
                
                // Bouton Filtre
                Button(action: { showFilters = true }) {
                    ZStack {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(themeManager.brandPrimary)
                            .font(.system(size: 20))
                        
                        if filters.isActive {
                            Circle()
                                .fill(themeManager.systemRed)
                                .frame(width: 8, height: 8)
                                .offset(x: 10, y: -10)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(themeManager.cardBackgroundColor)
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5) // Ombre très douce
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            
            // Compteur de résultats (discret)
            if !isLoading && errorMessage == nil {
                Text(resultsCountText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .background(themeManager.backgroundColor) // Fond pour cacher le contenu qui scrolle dessous
        .padding(.bottom, 10)
    }
    
    // MARK: - Vue du Contenu
    var contentView: some View {
        ZStack {
            if isLoading {
                ProgressView(NSLocalizedString("CATALOG_LOADING", comment: "Loading plants"))
                    .scaleEffect(1.2)
                    .padding()
            } else if let errorMessage = errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(themeManager.systemRed)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .foregroundColor(themeManager.secondaryTextColor)
                        .padding()
                    Button("Réessayer") {
                        fetchPlants()
                    }
                    .padding(.top)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 20) { // Espace vertical augmenté
                        
                        ForEach(filteredPlants) { plant in
                            NavigationLink(destination: PlantDetailView(plantID: plant.id)) {
                                PlantCard(plant: plant)
                                // Optionnel : petite animation au clic
                                    .scaleEffect(selectedPlant?.id == plant.id ? 0.95 : 1.0)
                            }
                            .buttonStyle(PlainButtonStyle()) // Évite l'effet bleu par défaut
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 40) // Marge pour le bas de l'écran
                }
                .scrollIndicators(.hidden) // Cache la barre de défilement pour un look plus propre
            }
        }
    }

    // MARK: - Logique (Inchangée)
    
    private var resultsCountText: String {
        let count = filteredPlants.count
        if count == 1 {
            return String(format: NSLocalizedString("CATALOG_RESULTS_SINGLE", comment: "One result"), count)
        } else {
            return String(format: NSLocalizedString("CATALOG_RESULTS_PLURAL", comment: "Multiple results"), count)
        }
    }

    var filteredPlants: [Plant] {
        var result = plants
        
        // Filtre par recherche texte
        if !searchText.isEmpty {
            result = result.filter { $0.name.lowercased().contains(searchText.lowercased()) }
        }
        
        // Filtre par critères (lumière, eau, difficulté)
        if filters.isActive {
            let locale = Locale.current.language.languageCode?.identifier ?? "fr"
            result = result.filter { plant in
                filters.matches(plant: plant, locale: locale)
            }
        }
        
        return result
    }

    func fetchPlants() {
        self.isLoading = true

        Task {
            do {
                let plants: [Plant] = try await NetworkManager.shared.request(
                    endpoint: "/plants",
                    method: .GET
                )

                await MainActor.run {
                    self.plants = plants
                    self.errorMessage = nil
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    let format = NSLocalizedString("CATALOG_ERROR_CONNECTION_FORMAT", comment: "Connection error")
                    self.errorMessage = String(format: format, error.localizedDescription)
                    self.isLoading = false
                }
            }
        }
    }
}
