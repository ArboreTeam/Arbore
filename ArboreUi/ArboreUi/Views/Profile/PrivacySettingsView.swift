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
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text(NSLocalizedString("PRIVACYSETTINGS_TITLE", comment: ""))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("PRIVACYSETTINGS_HEADER_TITLE", comment: ""))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(themeManager.textColor)

                            Text(NSLocalizedString("PRIVACYSETTINGS_HEADER_SUBTITLE", comment: ""))
                                .font(.system(size: 15))
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        .padding(.top, 18)

                        // Profile Visibility
                        PrivacySectionCard(
                            title: NSLocalizedString("PRIVACYSETTINGS_SECTION_PROFILE", comment: ""),
                            icon: "person.crop.circle.fill",
                            content: {
                                ToggleRow(
                                    icon: "globe.europe.africa.fill",
                                    title: NSLocalizedString("PRIVACYSETTINGS_PUBLICPROFILE_TITLE", comment: ""),
                                    subtitle: NSLocalizedString("PRIVACYSETTINGS_PUBLICPROFILE_SUB", comment: ""),
                                    isOn: $profilePublic
                                )
                            },
                            themeManager: themeManager
                        )

                        // Activity Sharing
                        PrivacySectionCard(
                            title: NSLocalizedString("PRIVACYSETTINGS_SECTION_ACTIVITY", comment: ""),
                            icon: "waveform.path.ecg.rectangle.fill",
                            content: {
                                ToggleRow(
                                    icon: "list.bullet.rectangle.portrait",
                                    title: NSLocalizedString("PRIVACYSETTINGS_ACTIVITY_TITLE", comment: ""),
                                    subtitle: NSLocalizedString("PRIVACYSETTINGS_ACTIVITY_SUB", comment: ""),
                                    isOn: $showActivity
                                )
                            },
                            themeManager: themeManager
                        )

                        // Data Sharing
                        PrivacySectionCard(
                            title: NSLocalizedString("PRIVACYSETTINGS_SECTION_DATASHARING", comment: ""),
                            icon: "chart.bar.doc.horizontal.fill",
                            content: {
                                ToggleRow(
                                    icon: "chart.bar.doc.horizontal.fill",
                                    title: NSLocalizedString("PRIVACYSETTINGS_DATASHARING_TITLE", comment: ""),
                                    subtitle: NSLocalizedString("PRIVACYSETTINGS_DATASHARING_SUB", comment: ""),
                                    isOn: $shareData
                                )
                            },
                            themeManager: themeManager
                        )

                        // Link to Privacy Policy
                        Button(action: { showPrivacyPolicy = true }) {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.green)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(NSLocalizedString("PRIVACYSETTINGS_READ_POLICY", comment: ""))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(themeManager.textColor)

                                    Text(NSLocalizedString("PRIVACYSETTINGS_READ_POLICY_SUB", comment: ""))
                                        .font(.system(size: 13))
                                        .foregroundColor(themeManager.secondaryTextColor)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(themeManager.secondaryTextColor.opacity(0.7))
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.gray.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        )
                        .cornerRadius(18)
                        .buttonStyle(.plain)

                        // Info note
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("PRIVACYSETTINGS_NOTE_TITLE", comment: ""))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(themeManager.textColor)

                            Text(NSLocalizedString("PRIVACYSETTINGS_NOTE_TEXT", comment: ""))
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.green)

                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(themeManager.textColor)

                Spacer()
            }

            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.gray.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
        .cornerRadius(18)
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
                .font(.system(size: 20))
                .foregroundColor(.green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
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
                .tint(.green)
        }
    }
}
