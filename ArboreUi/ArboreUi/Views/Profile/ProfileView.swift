import FirebaseAuth
import SwiftUI
import Firebase

struct ProfileView: View {
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showUpgradeSheet = false

    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - En-tête Profil
                    profileHeaderSection()
                    
                    // MARK: - Section Plan/Upgrade
                    currentPlanSection()
                    
                    // MARK: - Sections Paramètres groupées
                    settingsSectionsGroup()
                    
                    // MARK: - Footer
                    footerSection()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
    }
    
    // MARK: - En-tête Profil
    private func profileHeaderSection() -> some View {
        VStack(spacing: 12) {
            // Avatar avec initiales
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.4, green: 0.6, blue: 1),
                                Color(red: 0.2, green: 0.8, blue: 0.9)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Text("HM")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Text("Hugo Michel")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(themeManager.textColor)
            
            Text("@hugomichel")
                .font(.system(size: 14))
                .foregroundColor(themeManager.secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }
    
    // MARK: - Section Plan Actuel
    private func currentPlanSection() -> some View {
        VStack(spacing: 12) {
            // Affichage du plan actuel
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Standard")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Text("Votre plan actuel")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                Spacer()
                Image(systemName: "crown.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 16))
            }
            .padding(16)
            .background(themeManager.cardBackgroundColor)
            .cornerRadius(12)
            
            // CTA Upgrade
            Button(action: { showUpgradeSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Passer à Premium")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.5, green: 0.3, blue: 1),
                            Color(red: 0.3, green: 0.5, blue: 1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(12)
            }
            .sheet(isPresented: $showUpgradeSheet) {
                UpgradePlanView()
                    .environmentObject(themeManager)
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Groupes de paramètres
    private func settingsSectionsGroup() -> some View {
        VStack(spacing: 16) {
            // Section 1: Account
            settingsSection(items: [
                // wrap destination views with environmentObject inline (generic init will accept)
                SettingRowItem(icon: "person.fill", label: "Informations personnelles", destination: PersonalInformationView().environmentObject(themeManager)),
                SettingRowItem(icon: "creditcard.fill", label: "Informations de paiement", destination: nil as EmptyView?),
                SettingRowItem(icon: "house.fill", label: "Adresse de livraison", destination: nil as EmptyView?)
            ])
            
            // Section 2: Paramètres & Notifications
            settingsSection(items: [
                SettingRowItem(icon: "gearshape.fill", label: "Paramètres", destination: SettingsView().environmentObject(themeManager)),
                SettingRowItem(icon: "bell.fill", label: "Notifications", badge: nil, destination: NotificationsView().environmentObject(themeManager)),
                SettingRowItem(icon: "paintbrush.fill", label: "Apparence", destination: AppearanceView().environmentObject(themeManager))
            ])
            
            // Section 3: Abonnement & Support
            settingsSection(items: [
                SettingRowItem(icon: "star.fill", label: "Abonnement", destination: SubscriptionView().environmentObject(themeManager)),
                SettingRowItem(icon: "questionmark.circle.fill", label: "Aide & Support", destination: nil as EmptyView?)
            ])
        }
    }
    
    // MARK: - Composant Section
    private func settingsSection(items: [SettingRowItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if let destination = item.destination {
                    NavigationLink(destination: destination) {
                        settingRowContent(item: item)
                    }
                } else {
                    settingRowContent(item: item)
                }
                
                if index < items.count - 1 {
                    Divider()
                        .background(Color.gray.opacity(0.2))
                        .padding(.horizontal, 12)
                }
            }
        }
        .background(themeManager.cardBackgroundColor)
        .cornerRadius(12)
    }
    
    // MARK: - Contenu d'une ligne de paramètre
    private func settingRowContent(item: SettingRowItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 16))
                .foregroundColor(.blue)
                .frame(width: 24)
            
            Text(item.label)
                .font(.system(size: 16))
                .foregroundColor(themeManager.textColor)
            
            Spacer()
            
            if let badge = item.badge {
                Text(badge)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .cornerRadius(4)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(themeManager.secondaryTextColor)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
    }
    
    // MARK: - Footer
    private func footerSection() -> some View {
        VStack(spacing: 12) {
            Text("Version 1.0.0")
                .font(.system(size: 12))
                .foregroundColor(themeManager.secondaryTextColor)
            
            Button(action: logout) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Déconnexion")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 40)
    }
    
    // MARK: - Logout
    func logout() {
        do {
            try Auth.auth().signOut()
            isLoggedIn = false
        } catch {
            print("Erreur de déconnexion Firebase :", error.localizedDescription)
        }
    }
}

// MARK: - Modèle
struct SettingRowItem {
    let icon: String
    let label: String
    let badge: String?
    let destination: AnyView?
    
    // generic initializer that accepts any View or nil
    init<V: View>(icon: String, label: String, badge: String? = nil, destination: V? = nil) {
        self.icon = icon
        self.label = label
        self.badge = badge
        self.destination = destination.map { AnyView($0) }
    }
}

#Preview {
    ProfileView()
        .environmentObject(ThemeManager())
}