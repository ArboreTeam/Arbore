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
            themeManager.backgroundColor
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
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
        .fullScreenCover(item: $selectedDestination) { dest in
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
                                    Text(initials.isEmpty ? NSLocalizedString("PROFILE_USER_DEFAULT", comment: "Default user display name") : initials)
                                        .font(.system(size: 32, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                    .frame(width: 90, height: 90)
                    .clipShape(Circle())
                    .shadow(color: .green.opacity(0.4), radius: 8)

                    Button(action: { showImagePicker = true }) {
                        ZStack {
                            Circle()
                                .fill(themeManager.backgroundColor.opacity(0.8))
                                .frame(width: 36, height: 36)
                            Image(systemName: "camera.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .offset(x: 6, y: 6)
                }

                VStack(alignment: .center, spacing: 4) {
                    HStack(spacing: 6) {
                        Spacer()
                        Text(firstName.isEmpty ? NSLocalizedString("PROFILE_USER_DEFAULT", comment: "") : firstName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(themeManager.textColor)
                        if !lastName.isEmpty {
                            Text(lastName)
                                .font(.system(size: 22, weight: .bold))
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

    // MARK: - Current Plan Section
    private func currentPlanSection() -> some View {
        let currentPlanLevel = currentSubscriptionPlan
        var ctaText: String
        var ctaIcon: String

        switch currentPlanLevel {
        case "Standard":
            ctaText = NSLocalizedString("PROFILE_CTA_TRY_PREMIUM", comment: "")
            ctaIcon = "sparkles"
        case "Premium":
            ctaText = NSLocalizedString("PROFILE_CTA_UPGRADE_METAL", comment: "")
            ctaIcon = "arrow.up.circle.fill"
        case "Metal":
            ctaText = NSLocalizedString("PROFILE_CTA_UPGRADE_ULTRA", comment: "")
            ctaIcon = "arrow.up.circle.fill"
        case "Ultra":
            ctaText = NSLocalizedString("PROFILE_CTA_MANAGE", comment: "")
            ctaIcon = "gearshape.fill"
        default:
            ctaText = NSLocalizedString("PROFILE_CTA_TRY_PREMIUM", comment: "")
            ctaIcon = "sparkles"
        }

        return VStack(spacing: 16) {
            SubscriptionPlanCard(currentPlanName: currentPlanLevel)
                .environmentObject(themeManager)

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
        }
        .padding(.top, 8)
        .fullScreenCover(isPresented: $showUpgradeSheet) {
            UpgradePlanView().environmentObject(themeManager)
        }
    }

    // MARK: - Settings groups
    private func settingsSectionsGroup() -> some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("PROFILE_ACCOUNT_TITLE", comment: ""))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 4)

                settingsSection(items: [
                    SettingRowItem(icon: "person.circle.fill", label: NSLocalizedString("PROFILE_PERSONAL_DETAILS", comment: ""), destination: PersonalDetailsView().environmentObject(themeManager), iconColor: .green),
                    SettingRowItem(icon: "key.fill", label: NSLocalizedString("PROFILE_CHANGE_PASSWORD", comment: ""), destination: ChangePasswordView().environmentObject(themeManager), iconColor: .orange),
                    SettingRowItem(icon: "lock.shield.fill", label: NSLocalizedString("PROFILE_PRIVACY_POLICY", comment: ""), destination: PrivacyPolicyView().environmentObject(themeManager), iconColor: .blue),
                    SettingRowItem(icon: "scroll.fill", label: NSLocalizedString("PROFILE_TERMS", comment: ""), destination: TermsConditionsView().environmentObject(themeManager), iconColor: .purple),
                    SettingRowItem(icon: "square.and.arrow.down.fill", label: NSLocalizedString("PROFILE_DOWNLOAD_DATA", comment: "Download My Data"), destination: DataExportView().environmentObject(themeManager), iconColor: .blue),
                    SettingRowItem(icon: "trash.fill", label: NSLocalizedString("PROFILE_CLOSE_ACCOUNT", comment: ""), destination: CloseAccountView().environmentObject(themeManager), iconColor: .red)
                ])
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("PROFILE_PRIVACY_SECTION", comment: ""))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 4)

                settingsSection(items: [
                    SettingRowItem(icon: "eye.slash.fill", label: NSLocalizedString("PROFILE_PRIVACY_SETTINGS", comment: ""), destination: PrivacySettingsView().environmentObject(themeManager), iconColor: .teal)
                ])
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("PROFILE_SETTINGS_SECTION", comment: ""))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 4)

                settingsSection(items: [
                    SettingRowItem(icon: "bell.badge.fill", label: NSLocalizedString("PROFILE_NOTIFICATIONS", comment: ""), destination: NotificationsView().environmentObject(themeManager), iconColor: .pink),
                    SettingRowItem(icon: "paintbrush.fill", label: NSLocalizedString("PROFILE_APPEARANCE", comment: ""), destination: AppearanceView().environmentObject(themeManager), iconColor: .yellow)
                ])
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("PROFILE_APP_INFO", comment: ""))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 4)

                settingsSection(items: [
                    SettingRowItem(icon: "figure.walk", label: NSLocalizedString("PROFILE_ACCESSIBILITY", comment: ""), destination: AccessibilityView().environmentObject(themeManager), iconColor: .cyan),
                    SettingRowItem(icon: "info.circle.fill", label: NSLocalizedString("PROFILE_ABOUT", comment: ""), destination: AboutUsView().environmentObject(themeManager), iconColor: .gray)
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
                        .background(Color.white.opacity(0.1))
                        .padding(.leading, 64)
                }
            }
        }
        .background(
            ZStack {
                Color.gray.opacity(0.12)
                RoundedRectangle(cornerRadius: 18)
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
        .cornerRadius(18)
        .buttonStyle(.plain)
    }

    private func settingRowContent(item: SettingRowItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(item.iconColor.opacity(0.18))
                    .frame(width: 40, height: 40)

                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .semibold))
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
        VStack(spacing: 16) {
            Text(String(format: NSLocalizedString("PROFILE_VERSION", comment: ""), "1.0.0"))
                .font(.system(size: 12))
                .foregroundColor(themeManager.secondaryTextColor)

            Button(action: logout) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text(NSLocalizedString("PROFILE_LOGOUT", comment: ""))
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.8))
                .cornerRadius(14)
                .shadow(color: Color.red.opacity(0.4), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 24)
        .padding(.bottom, 40)
    }

    // MARK: - Networking / helpers
    private func uploadProfileImage(_ image: UIImage) async {
        // Placeholder upload logic - replace with your storage/upload code
        isUploading = true
        uploadError = nil
        try? await Task.sleep(nanoseconds: 700_000_000)
        DispatchQueue.main.async {
            self.profileImage = image
            self.isUploading = false
        }
    }

    private func fetchProfileImage() {
        // Implement your fetch logic; kept empty for sample
    }

    private func loadUserData() {
        if let user = Auth.auth().currentUser {
            self.firstName = user.displayName?.components(separatedBy: " ").first ?? "Hugo"
            self.lastName = user.displayName?.components(separatedBy: " ").last ?? ""
        }
    }

    private func loadFallbackFromAuth() {
        if let user = Auth.auth().currentUser {
            self.firstName = user.displayName ?? NSLocalizedString("PROFILE_USER_DEFAULT", comment: "")
        }
    }

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