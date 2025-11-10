import SwiftUI
import FirebaseAuth

struct HomeView: View {
    @ObservedObject var plantService = PlantService()
    @StateObject var userService = UserService()
    @State private var showARScan = false
    @State private var userName: String = ""
    @State private var userError: String? = nil
    @State private var currentUID: String = ""
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // ✨ HEADER SECTION - Accueil personnalisé
                    VStack(spacing: 16) {
                        // Salutation et avatar
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Bonjour 👋")
                                    .font(.subheadline)
                                    .foregroundColor(themeManager.secondaryTextColor)
                                
                                if let error = userError {
                                    Text("Erreur de connexion")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(themeManager.systemRed)
                                } else {
                                    Text(userName.isEmpty ? "Ami des plantes" : userName)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(themeManager.textColor)
                                }
                            }
                            
                            Spacer()
                            
                            // Avatar circulaire
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [themeManager.adjust(Color(hex: "#2E7D32")), themeManager.adjust(Color(hex: "#4CAF50"))],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 45, height: 45)
                                .overlay(
                                    Text(userName.first?.uppercased() ?? "U")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        
                        // Action principale - Scanner
                        VStack(spacing: 12) {
                            Button(action: {
                                showARScan.toggle()
                            }) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(themeManager.adjust(Color.white).opacity(0.2))
                                            .frame(width: 40, height: 40)
                                        
                                        Image(systemName: "camera.viewfinder")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundColor(themeManager.adjust(Color.white))
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Scanner une plante")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(themeManager.adjust(Color.white))
                                        
                                        Text("Découvre instantanément")
                                            .font(.subheadline)
                                            .foregroundColor(themeManager.adjust(Color.white).opacity(0.8))
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(themeManager.adjust(Color.white).opacity(0.8))
                                }
                                .padding(20)
                                .background(
                                    LinearGradient(
                                        colors: [themeManager.adjust(Color(hex: "#2E7D32")), themeManager.adjust(Color(hex: "#4CAF50"))],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(16)
                                .shadow(color: themeManager.adjust(Color(hex: "#2E7D32")).opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 32)
                    
                    // ✨ REMINDER CARD - Notification importante
                    if !plantService.plants.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(themeManager.systemOrange.opacity(0.1))
                                        .frame(width: 36, height: 36)
                                    
                                    Image(systemName: "drop.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(themeManager.systemOrange)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Rappel d'arrosage")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(themeManager.textColor)
                                    
                                    Text("N'oublie pas d'arroser ton Monstera aujourd'hui !")
                                        .font(.footnote)
                                        .foregroundColor(themeManager.secondaryTextColor)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(themeManager.secondaryTextColor)
                            }
                            .padding(16)
                            .background(themeManager.cardBackgroundColor)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(themeManager.systemOrange.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                    
                    // ✨ QUICK ACTIONS - Actions rapides
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Actions rapides")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(themeManager.textColor)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                QuickActionCard(
                                    icon: "leaf.fill",
                                    title: "Mon Jardin",
                                    subtitle: "Gérer mes plantes",
                                    color: Color(hex: "#4CAF50")
                                )
                                
                                QuickActionCard(
                                    icon: "magnifyingglass",
                                    title: "Explorer",
                                    subtitle: "Découvrir nouvelles plantes",
                                    color: Color.blue
                                )
                                
                                QuickActionCard(
                                    icon: "calendar",
                                    title: "Planning",
                                    subtitle: "Calendrier d'entretien",
                                    color: Color.purple
                                )
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 32)
                    
                    // ✨ SECTIONS DE CONTENU
                    VStack(spacing: 32) {
                        // Plantes populaires
                        PlantSection(
                            title: "🌱 Plantes populaires",
                            subtitle: "Les plus appréciées",
                            plants: Array(plantService.plants.prefix(5))
                        )
                        
                        // Plantes à arroser
                        WateringSection(plants: Array(plantService.plants.prefix(3)))
                        
                        // Dernières visitées
                        PlantSection(
                            title: "🔍 Récemment consultées",
                            subtitle: "Tes dernières découvertes",
                            plants: Array(plantService.plants.prefix(4))
                        )
                    }
                    .padding(.bottom, 120) // Espace pour la tab bar
                }
            }
            .background(themeManager.backgroundColor)
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showARScan) {
                ScanAR()
            }
            .onAppear {
                loadUserData()
                plantService.fetchPlants()
            }
        }
    }
    
    private func loadUserData() {
        if let uid = Auth.auth().currentUser?.uid {
            self.currentUID = uid
            userService.fetchUser(by: uid) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let user):
                        self.userName = user.name.components(separatedBy: " ").first ?? ""
                    case .failure(let error):
                        self.userError = "Impossible de récupérer l'utilisateur : \(error.localizedDescription)"
                    }
                }
            }
        } else {
            self.userError = "Utilisateur non connecté."
        }
    }
}

struct QuickActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 8) {
            // Icône
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(themeManager.adjust(color))
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(themeManager.adjust(color).opacity(0.2))
                        .frame(width: 56, height: 56)
                )
            
            // Titres
            VStack(alignment: .center, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.textColor)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
            }
        }
        .padding(16)
        .background(themeManager.cardBackgroundColor)
        .cornerRadius(12)
        .shadow(color: themeManager.adjust(Color.black).opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct PlantSection: View {
    let title: String
    let subtitle: String
    let plants: [Plant]
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Titres
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.textColor)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            HStack {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(themeManager.secondaryTextColor)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            
            // Cartes de plantes
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(plants) { plant in
                        PlantCard(plant: plant)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

struct WateringSection: View {
    let plants: [Plant]
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Titres
            HStack {
                Text("💧 Plantes à arroser bientôt")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.textColor)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            // Liste des plantes à arroser
            VStack(spacing: 8) {
                ForEach(plants) { plant in
                    WaterReminderRow(plantName: plant.name, daysLeft: Int.random(in: 1...5))
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
