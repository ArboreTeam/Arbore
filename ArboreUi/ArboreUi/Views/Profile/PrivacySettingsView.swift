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
                // Top bar with close button
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
                    VStack(spacing: 16) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Privacy Settings")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(themeManager.textColor)
                            Text("Control who sees your profile, your activity, and how we use your data.")
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.10), lineWidth: 1))

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
                            title: "Activity",
                            icon: "waveform.path.ecg.rectangle.fill",
                            content: {
                                ToggleRow(
                                    icon: "text.badge.star",
                                    title: "Show My Activity",
                                    subtitle: "Allow showing your recent garden updates.",
                                    isOn: $showActivity
                                )
                            },
                            themeManager: themeManager
                        )

                        // Section — Data Sharing
                        PrivacySectionCard(
                            title: "Data Sharing",
                            icon: "lock.shield.fill",
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

                        // Lien vers la politique de confidentialité
                        Button(action: { showPrivacyPolicy = true }) {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.green)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Read our Privacy Policy")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(themeManager.textColor)
                                    Text("Understand how we collect, use and protect your data.")
                                        .font(.system(size: 12))
                                        .foregroundColor(themeManager.secondaryTextColor)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(themeManager.secondaryTextColor)
                            }
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.10), lineWidth: 1))
                        }

                        // Note d'information
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Note")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(themeManager.textColor)
                            Text("You can change these settings at any time. Some changes may take a few minutes to apply across all your devices.")
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.10), lineWidth: 1))

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
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

// MARK: - Section Card
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.green)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.textColor)
                Spacer()
            }
            content
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

// MARK: - Toggle Row
private struct ToggleRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.green)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(themeManager.textColor)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}