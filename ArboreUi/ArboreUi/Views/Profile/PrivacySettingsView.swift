import SwiftUI

struct PrivacySettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    @State private var profilePublic: Bool = true
    @State private var showActivity: Bool = true
    @State private var shareData: Bool = false
    @State private var showPrivacyPolicy: Bool = false

    var body: some View {
        ZStack {
            themeManager.backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with close button - Uniforme
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text("Privacy Settings")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) { // Augmentation de l'espacement
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your Privacy, Your Control") // Nouveau titre plus audacieux
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(themeManager.textColor)
                            Text("Control who sees your profile, your activity, and how we use your data.")
                                .font(.system(size: 15))
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        .padding(.top, 18)
                        
                        // Section — Profile Visibility
                        PrivacySectionCard(
                            title: "Profile Visibility",
                            icon: "person.crop.circle.fill",
                            content: {
                                ToggleRow(
                                    icon: "globe.europe.africa.fill",
                                    title: "Public Profile",
                                    subtitle: "Your name and avatar are visible to others.",
                                    isOn: $profilePublic
                                )
                            },
                            themeManager: themeManager
                        )

                        // Section — Activity
                        PrivacySectionCard(
                            title: "Activity Sharing",
                            icon: "waveform.path.ecg.rectangle.fill",
                            content: {
                                ToggleRow(
                                    icon: "list.bullet.rectangle.portrait",
                                    title: "Show My Activity", // Nouvelle icône
                                    subtitle: "Allow showing your recent garden updates.",
                                    isOn: $showActivity
                                )
                            },
                            themeManager: themeManager
                        )

                        // Section — Data Sharing
                        PrivacySectionCard(
                            title: "Data Sharing",
                            icon: "chart.bar.doc.horizontal.fill", // Icône mise à jour
                            content: {
                                ToggleRow(
                                    icon: "chart.bar.doc.horizontal.fill",
                                    title: "Share Data for Analytics",
                                    subtitle: "Help us improve features and reliability. No personal content is sold.",
                                    isOn: $shareData
                                )
                            },
                            themeManager: themeManager
                        )

                        // Lien vers la politique de confidentialité (Style de carte unifié)
                        Button(action: { showPrivacyPolicy = true }) {
                            HStack(spacing: 12) { // Augmentation de l'espacement
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 20)) // Icône plus grande
                                    .foregroundColor(.green)
                                    .frame(width: 24) // Espace d'icône plus large
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Read our Privacy Policy")
                                        .font(.system(size: 16, weight: .semibold)) // Plus grand
                                        .foregroundColor(themeManager.textColor)
                                    Text("Understand how we collect, use and protect your data.")
                                        .font(.system(size: 13))
                                        .foregroundColor(themeManager.secondaryTextColor)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(themeManager.secondaryTextColor.opacity(0.7))
                            }
                        }
                        .padding(16) // Rembourrage uniforme
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.gray.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        )
                        .cornerRadius(18)
                        .buttonStyle(.plain)


                        // Note d'information (Style de carte unifié)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Note")
                                .font(.system(size: 15, weight: .semibold)) // Plus grand
                                .foregroundColor(themeManager.textColor)
                            Text("You can change these settings at any time. Some changes may take a few minutes to apply across all your devices.")
                                .font(.system(size: 13))
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.gray.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        )
                        .cornerRadius(18)

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .fullScreenCover(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
                .environmentObject(themeManager)
                .interactiveDismissDisabled()
        }
    }
}

// MARK: - Section Card (Mise à jour pour coins uniformes)
private struct PrivacySectionCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    let themeManager: ThemeManager

    init(title: String, icon: String, @ViewBuilder content: () -> Content, themeManager: ThemeManager) {
        self.title = title
        self.icon = icon
        self.content = content()
        self.themeManager = themeManager
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { // Augmentation de l'espacement
            HStack(spacing: 12) { // Augmentation de l'espacement
                Image(systemName: icon)
                    .font(.system(size: 20)) // Icône plus grande
                    .foregroundColor(.green)
                Text(title)
                    .font(.system(size: 17, weight: .bold)) // Plus audacieux
                    .foregroundColor(themeManager.textColor)
                Spacer()
            }
            content
        }
        .padding(18) // Rembourrage uniforme
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.gray.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
        .cornerRadius(18)
    }
}

// MARK: - Toggle Row (Mise à jour pour coins uniformes et icônes plus grandes)
private struct ToggleRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20)) // Icône plus grande
                .foregroundColor(.green)
                .frame(width: 24) // Espace d'icône plus large

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold)) // Plus grand
                    .foregroundColor(themeManager.textColor)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(themeManager.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.green) // Couleur d'accentuation verte
        }
    }
}
