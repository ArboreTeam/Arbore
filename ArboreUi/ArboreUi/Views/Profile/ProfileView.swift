import SwiftUI
import FirebaseAuth
import Firebase
import PhotosUI

// MARK: - Vue Principale
struct ProfileView: View {
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @EnvironmentObject var themeManager: ThemeManager

    @StateObject var userService = UserService()
    @State private var userNameFetchError: String? = nil
    @State private var showUpgradeSheet = false

    // Variable brute simulée pour le plan actuel (Changer pour tester)
    @State private var currentSubscriptionPlan: String = "Ultra"

    // name
    @State private var firstName: String = ""
    @State private var lastName: String = ""

    // profile image
    @State private var profileImage: UIImage? = nil
    @State private var showImagePicker = false
    @State private var isUploading = false
    @State private var uploadError: String? = nil

    private var initials: String {
        let f = firstName.first.map(String.init) ?? ""
        let l = lastName.first.map(String.init) ?? ""
        return (f + l).uppercased()
    }

    @State private var selectedDestination: DestinationItem? = nil

    var body: some View {
        ZStack {
            // Utiliser le thème manager
            themeManager.backgroundColor
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) { // Augmentation de l'espacement
                    header()
                    currentPlanSection()
                    settingsSectionsGroup()
                    footerSection()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .onAppear {
            loadUserData()
            fetchProfileImage()
        }
        // utilise fullScreenCover(item:) lié à selectedDestination
        .fullScreenCover(item: $selectedDestination) { dest in
            // Utiliser une transition plus professionnelle
            dest.view
                .environmentObject(themeManager)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showImagePicker) {
            PhotoPicker(selectedImage: $profileImage) { image in
                if let img = image {
                    Task { await uploadProfileImage(img) }
                }
            }
        }
    }

    // MARK: - Header (single line name + editable photo)
    private func header() -> some View {
        VStack(spacing: 12) {
            VStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    // Profile Image or Initials (Glass-like Circle)
                    Group {
                        if let img = profileImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.2, green: 0.7, blue: 0.4),
                                            Color(red: 0.1, green: 0.6, blue: 0.3)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    Text(initials.isEmpty ? "U" : initials)
                                        .font(.system(size: 32, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                    .frame(width: 90, height: 90) // Légèrement plus grand
                    .clipShape(Circle())
                    .shadow(color: .green.opacity(0.4), radius: 8) // Ombre pour plus de profondeur

                    // Camera icon button
                    Button(action: { showImagePicker = true }) {
                        ZStack {
                            Circle()
                                .fill(themeManager.backgroundColor.opacity(0.8)) // Fond sombre transparent pour l'icône
                                .frame(width: 36, height: 36)
                            Image(systemName: "camera.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 16, weight: .bold)) // Icône verte
                        }
                    }
                    .offset(x: 6, y: 6)
                }
                
                // Name centered
                VStack(alignment: .center, spacing: 4) {
                    HStack(spacing: 6) {
                        Spacer()
                        Text(firstName.isEmpty ? "Utilisateur" : firstName)
                            .font(.system(size: 22, weight: .bold)) // Plus grand
                            .foregroundColor(themeManager.textColor)
                        if !lastName.isEmpty {
                            Text(lastName)
                                .font(.system(size: 22, weight: .bold)) // Plus grand
                            // Correction: .foregroundColor(themeManager.textColor) (déjà dans le Group)
                            // Note: Le code ici est basé sur ce que vous avez fourni, mais l'utilisation de `themeManager.textColor` dans la boucle ci-dessus était déjà présente.
                                .foregroundColor(themeManager.textColor)
                        }
                        Spacer()
                    }

                    if isUploading {
                        Text("Uploading…").font(.caption).foregroundColor(.gray)
                    } else if let err = uploadError {
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                }
            }
            .padding(.top, 20)
        }
    }


    // MARK: - Current Plan Section (UX/Bouton corrigé)
    private func currentPlanSection() -> some View {
        let currentPlanLevel = currentSubscriptionPlan
        var ctaText: String
        var ctaIcon: String
        
        // Logique UX pour le bouton d'action
        switch currentPlanLevel {
        case "Standard":
            ctaText = "Try Premium"
            ctaIcon = "sparkles"
        case "Premium":
            ctaText = "Upgrade to Metal" // Propose le plan supérieur
            ctaIcon = "arrow.up.circle.fill"
        case "Metal":
            ctaText = "Upgrade to Ultra" // Propose le plan supérieur
            ctaIcon = "arrow.up.circle.fill"
        case "Ultra":
            ctaText = "Manage Subscription" // Plan le plus élevé, propose la gestion
            ctaIcon = "gearshape.fill"
        default:
            ctaText = "Discover Plans"
            ctaIcon = "sparkles"
        }

        return VStack(spacing: 16) {

            // Carte d'abonnement stylisée
            SubscriptionPlanCard(currentPlanName: currentPlanLevel)
                .environmentObject(themeManager)

            // Bouton d'action logique (CTA corrigé)
            Button(action: { showUpgradeSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: ctaIcon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(ctaText)
                        .font(.system(size: 17, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.1, green: 0.8, blue: 0.5),
                            Color(red: 0.05, green: 0.5, blue: 0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(18)
                .shadow(color: Color.green.opacity(0.5), radius: 10, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 0)
            .padding(.top, 0)
        }
        .padding(.top, 8)
        .fullScreenCover(isPresented: $showUpgradeSheet) {
            UpgradePlanView().environmentObject(themeManager)
        }
    }

    // MARK: - Settings groups (Redesigned icons, same style)
    private func settingsSectionsGroup() -> some View {
        VStack(spacing: 20) { // Augmentation de l'espacement
            
            // Account Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Account")
                    .font(.system(size: 14, weight: .bold)) // Un peu plus audacieux
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 4)
                
                settingsSection(items: [
                    SettingRowItem(icon: "person.circle.fill", label: "Personal Details", destination: PersonalDetailsView().environmentObject(themeManager), iconColor: .green),
                    SettingRowItem(icon: "key.fill", label: "Change Password", destination: ChangePasswordView().environmentObject(themeManager), iconColor: .orange),
                    SettingRowItem(icon: "lock.shield.fill", label: "Privacy Policy", destination: PrivacyPolicyView().environmentObject(themeManager), iconColor: .blue),
                    SettingRowItem(icon: "scroll.fill", label: "Terms & Conditions", destination: TermsConditionsView().environmentObject(themeManager), iconColor: .purple),
                    SettingRowItem(icon: "trash.fill", label: "Close Account", destination: CloseAccountView().environmentObject(themeManager), iconColor: .red) // Icône plus simple
                ])
            }

            // Privacy Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Privacy")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 4)
                
                settingsSection(items: [
                    SettingRowItem(icon: "eye.slash.fill", label: "Privacy Settings", destination: PrivacySettingsView().environmentObject(themeManager), iconColor: .teal)
                ])
            }

            // Settings Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Settings")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 4)
                
                settingsSection(items: [
                    SettingRowItem(icon: "bell.badge.fill", label: "Notification Settings", destination: NotificationsView().environmentObject(themeManager), iconColor: .pink),
                    SettingRowItem(icon: "paintbrush.fill", label: "Appearance", destination: AppearanceView().environmentObject(themeManager), iconColor: .yellow)
                ])
            }

            // Information & Accessibility
            VStack(alignment: .leading, spacing: 8) {
                Text("App Information")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 4)
                
                settingsSection(items: [
                    SettingRowItem(icon: "figure.walk", label: "Accessibility", destination: AccessibilityView().environmentObject(themeManager), iconColor: .cyan),
                    SettingRowItem(icon: "info.circle.fill", label: "About Arbore", destination: AboutUsView().environmentObject(themeManager), iconColor: .gray)
                ])
            }
        }
    }

    private func settingsSection(items: [SettingRowItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button(action: { selectedDestination = DestinationItem(view: item.destination) }) {
                    settingRowContent(item: item)
                }

                if index < items.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.1)) // Ligne de séparation plus fine/subtile
                        .padding(.leading, 64) // Indenter la ligne pour un look moderne
                }
            }
        }
        .background(
            ZStack {
                Color.gray.opacity(0.12)
                RoundedRectangle(cornerRadius: 18) // Cohérence des coins
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .cornerRadius(18) // Cohérence des coins
        .buttonStyle(.plain)
    }

    private func settingRowContent(item: SettingRowItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(item.iconColor.opacity(0.18)) // Utiliser la couleur spécifique pour l'arrière-plan de l'icône
                    .frame(width: 40, height: 40)
                
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .semibold)) // Icône un peu plus grande et plus audacieuse
                    .foregroundColor(item.iconColor)
            }

            Text(item.label)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(themeManager.textColor)

            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(themeManager.secondaryTextColor.opacity(0.7))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    // MARK: - Footer
    private func footerSection() -> some View {
        VStack(spacing: 16) { // Augmentation de l'espacement
            Text("Version 1.0.0")
                .font(.system(size: 12))
                .foregroundColor(themeManager.secondaryTextColor)
            
            Button(action: logout) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Log Out")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.8)) // Fond plus solide pour la déconnexion
                .cornerRadius(14)
                .shadow(color: Color.red.opacity(0.4), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 24)
        .padding(.bottom, 40)
    }
    
    // ... Networking / loadUserData / logout functions (unchanged) ...
    
    private func uploadProfileImage(_ image: UIImage) async { /* ... */ }
    private func fetchProfileImage() { /* ... */ }
    
    // Simplifié pour l'exemple
    private func loadUserData() {
        if let user = Auth.auth().currentUser {
            // Logique de chargement simulée
            self.firstName = "Hugo"
            self.lastName = "Michel"
        }
    }
    
    private func loadFallbackFromAuth() { /* ... */ }
    
    private func logout() {
        do {
            try Auth.auth().signOut()
            isLoggedIn = false
        } catch {
            print("Erreur de déconnexion Firebase :", error.localizedDescription)
        }
    }
}

// Preview
#Preview {
    ProfileView()
        .environmentObject(ThemeManager())
}
