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

    #if DEBUG
    @State private var showDebugThumbnailGenerator = false
    #endif

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
        AppBackground {
            ScrollView {
                VStack(spacing: ArboreDesign.Spacing.xl) {
                    header()
                    currentPlanSection()
                    settingsSectionsGroup()
                    footerSection()
                }
                .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
                .padding(.vertical, ArboreDesign.Spacing.lg)
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

        #if DEBUG
        .sheet(isPresented: $showDebugThumbnailGenerator) {
            DebugThumbnailGeneratorView()
        }
        #endif
    }

    // MARK: - Header (single line name + editable photo)
    private func header() -> some View {
        AppCard {
            VStack(alignment: .center, spacing: ArboreDesign.Spacing.md) {
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
                                            ArboreDesign.Colors.secondaryGreen,
                                            ArboreDesign.Colors.primaryGreen
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
                    .overlay(
                        Circle()
                            .stroke(ArboreDesign.Colors.card, lineWidth: 3)
                    )
                    .shadow(color: ArboreDesign.Colors.primaryGreen.opacity(0.18), radius: 12, x: 0, y: 6)

                    Button(action: { showImagePicker = true }) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(ArboreDesign.Colors.primaryGreen)
                            .frame(width: 36, height: 36)
                            .background(ArboreDesign.Colors.softSurface)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(ArboreDesign.Colors.card, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: 6)
                }

                VStack(alignment: .center, spacing: 4) {
                    HStack(spacing: 6) {
                        Spacer()
                        Text(firstName.isEmpty ? NSLocalizedString("PROFILE_USER_DEFAULT", comment: "") : firstName)
                            .font(ArboreDesign.Typography.pageTitle)
                            .foregroundColor(ArboreDesign.Colors.textPrimary)
                        if !lastName.isEmpty {
                            Text(lastName)
                                .font(ArboreDesign.Typography.pageTitle)
                                .foregroundColor(ArboreDesign.Colors.textPrimary)
                        }
                        Spacer()
                    }

                    if isUploading {
                        Text(L10n.t("PROFILE_UPLOADING"))
                            .font(ArboreDesign.Typography.caption)
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                    } else if let err = uploadError {
                        Text(err)
                            .font(ArboreDesign.Typography.caption)
                            .foregroundColor(ArboreDesign.Colors.danger)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Current Plan Section
    private func currentPlanSection() -> some View {
        SubscriptionPlanCard()
    }

    // MARK: - Settings groups
    private func settingsSectionsGroup() -> some View {
        VStack(spacing: ArboreDesign.Spacing.xl) {
            settingsSection(
                title: NSLocalizedString("PROFILE_ACCOUNT_TITLE", comment: ""),
                items: [
                    SettingRowItem(icon: "person.crop.circle", label: NSLocalizedString("PROFILE_PERSONAL_DETAILS", comment: ""), destination: PersonalDetailsView().environmentObject(themeManager), iconColor: ArboreDesign.Colors.primaryGreen),
                    SettingRowItem(icon: "key", label: NSLocalizedString("PROFILE_CHANGE_PASSWORD", comment: ""), destination: ChangePasswordView().environmentObject(themeManager), iconColor: ArboreDesign.Colors.accentGold),
                    SettingRowItem(icon: "lock.shield", label: NSLocalizedString("PROFILE_PRIVACY_POLICY", comment: ""), destination: PrivacyPolicyView().environmentObject(themeManager), iconColor: ArboreDesign.Colors.secondaryGreen),
                    SettingRowItem(icon: "doc.text", label: NSLocalizedString("PROFILE_TERMS", comment: ""), destination: TermsConditionsView().environmentObject(themeManager), iconColor: ArboreDesign.Colors.primaryGreen),
                    SettingRowItem(icon: "square.and.arrow.down", label: NSLocalizedString("PROFILE_DOWNLOAD_DATA", comment: "Download My Data"), destination: DataExportView().environmentObject(themeManager), iconColor: ArboreDesign.Colors.success),
                    SettingRowItem(icon: "trash", label: NSLocalizedString("PROFILE_CLOSE_ACCOUNT", comment: ""), destination: CloseAccountView().environmentObject(themeManager), iconColor: ArboreDesign.Colors.danger)
                ]
            )

            settingsSection(
                title: NSLocalizedString("PROFILE_PRIVACY_SECTION", comment: ""),
                items: [
                    SettingRowItem(icon: "eye.slash", label: NSLocalizedString("PROFILE_PRIVACY_SETTINGS", comment: ""), destination: PrivacySettingsView().environmentObject(themeManager), iconColor: ArboreDesign.Colors.primaryGreen)
                ]
            )

            settingsSection(
                title: NSLocalizedString("PROFILE_SETTINGS_SECTION", comment: ""),
                items: [
                    SettingRowItem(icon: "bell.badge", label: NSLocalizedString("PROFILE_NOTIFICATIONS", comment: ""), destination: NotificationsView().environmentObject(themeManager), iconColor: ArboreDesign.Colors.accentGold),
                    SettingRowItem(icon: "paintbrush", label: NSLocalizedString("PROFILE_APPEARANCE", comment: ""), destination: AppearanceView().environmentObject(themeManager), iconColor: ArboreDesign.Colors.secondaryGreen)
                ]
            )

            settingsSection(
                title: NSLocalizedString("PROFILE_APP_INFO", comment: ""),
                items: [
                    SettingRowItem(icon: "figure.walk", label: NSLocalizedString("PROFILE_ACCESSIBILITY", comment: ""), destination: AccessibilityView().environmentObject(themeManager), iconColor: ArboreDesign.Colors.success),
                    SettingRowItem(icon: "info.circle", label: NSLocalizedString("PROFILE_ABOUT", comment: ""), destination: AboutUsView().environmentObject(themeManager), iconColor: ArboreDesign.Colors.textSecondary)
                ]
            )

            #if DEBUG
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
                SectionTitle(title: "Debug Tools")

                Button(action: { showDebugThumbnailGenerator = true }) {
                    SettingsRow(
                        systemImage: "hammer",
                        title: "Thumbnail Generator",
                        tint: ArboreDesign.Colors.danger
                    )
                }
                .buttonStyle(.plain)

                // Sentry (#205) : envoie un event de test pour vérifier le DSN.
                // No-op si Sentry n'est pas configuré dans Secrets.xcconfig.
                Button(action: { SentryManager.sendTestEvent() }) {
                    SettingsRow(
                        systemImage: "ladybug",
                        title: "Send Sentry test event",
                        tint: ArboreDesign.Colors.accentGold
                    )
                }
                .buttonStyle(.plain)
            }
            #endif
        }
    }

    private func settingsSection(title: String, items: [SettingRowItem]) -> some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
            SectionTitle(title: title)

            VStack(spacing: ArboreDesign.Spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button(action: { selectedDestination = DestinationItem(view: item.destination) }) {
                        SettingsRow(
                            systemImage: item.icon,
                            title: item.label,
                            tint: item.iconColor
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Footer
    private func footerSection() -> some View {
        VStack(spacing: ArboreDesign.Spacing.md) {
            Text(String(format: NSLocalizedString("PROFILE_VERSION", comment: ""), appVersion))
                .font(ArboreDesign.Typography.caption)
                .foregroundColor(ArboreDesign.Colors.textSecondary)

            Button(action: logout) {
                HStack(spacing: ArboreDesign.Spacing.xs) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text(NSLocalizedString("PROFILE_LOGOUT", comment: ""))
                }
            }
            .buttonStyle(.arboreDanger)
        }
        .padding(.top, ArboreDesign.Spacing.sm)
        .padding(.bottom, ArboreDesign.Spacing.xxl)
    }

    // MARK: - Networking / helpers
    private func uploadProfileImage(_ image: UIImage) async {
        await MainActor.run {
            isUploading = true
            uploadError = nil
        }

        do {
            try saveProfileImageLocally(image)
            await MainActor.run {
                self.profileImage = image
                self.isUploading = false
            }
        } catch {
            await MainActor.run {
                self.uploadError = "Impossible de sauvegarder la photo."
                self.isUploading = false
            }
        }
    }

    private func fetchProfileImage() {
        guard let image = loadLocalProfileImage() else { return }
        profileImage = image
    }

    private var profileImageURL: URL? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProfileImages", isDirectory: true)
        return directory.appendingPathComponent("\(uid).jpg")
    }

    private func saveProfileImageLocally(_ image: UIImage) throws {
        guard let url = profileImageURL else { return }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let data = image.normalizedProfileImage().jpegData(compressionQuality: 0.86) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try data.write(to: url, options: [.atomic])
    }

    private func loadLocalProfileImage() -> UIImage? {
        guard let url = profileImageURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return UIImage(data: data)
    }

    private func loadUserData() {
        if let user = Auth.auth().currentUser {
            let nameComponents = user.displayName?
                .split(separator: " ")
                .map(String.init) ?? []
            self.firstName = nameComponents.first
                ?? NSLocalizedString("PROFILE_USER_DEFAULT", comment: "")
            self.lastName = nameComponents.count > 1 ? nameComponents.dropFirst().joined(separator: " ") : ""
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

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

private extension UIImage {
    func normalizedProfileImage(maxDimension: CGFloat = 600) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return self }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

// Preview
#Preview {
    ProfileView()
        .environmentObject(ThemeManager())
}
