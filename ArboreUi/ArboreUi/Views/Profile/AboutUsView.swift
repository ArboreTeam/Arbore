import SwiftUI

struct AboutUsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    
    // Version de l'application
    private let appVersion = "1.0.0"
    private let supportEmail = "support@arbore.app"

    var body: some View {
        SettingsPage(title: NSLocalizedString("PROFILE_ABOUT", comment: "About Arbore title")) {
            AppCard {
                VStack(spacing: ArboreDesign.Spacing.md) {
                    SettingsIconBadge(
                        systemImage: "leaf",
                        tint: ArboreDesign.Colors.primaryGreen,
                        size: 64
                    )

                    VStack(spacing: ArboreDesign.Spacing.xs) {
                        Text("Arbore")
                            .font(ArboreDesign.Typography.largeTitle)
                            .foregroundColor(ArboreDesign.Colors.textPrimary)

                        Text(String(format: NSLocalizedString("PROFILE_VERSION", comment: ""), appVersion))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(ArboreDesign.Colors.primaryGreen)
                    }

                    Text(NSLocalizedString("ABOUT_APP_SLOGAN", comment: "App slogan"))
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }

            SettingsSectionCard(
                title: NSLocalizedString("ABOUT_SECTION_TITLE", comment: "About section title"),
                systemImage: "info.circle"
            ) {
                Text(NSLocalizedString("ABOUT_SECTION_DESCRIPTION", comment: "About section description"))
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsSectionCard(
                title: NSLocalizedString("FEATURES_SECTION_TITLE", comment: "Features section title"),
                systemImage: "sparkles",
                tint: ArboreDesign.Colors.accentGold
            ) {
                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                    FeatureRow(icon: "camera.viewfinder",
                               titleKey: "FEATURE_ID_TITLE",
                               descriptionKey: "FEATURE_ID_DESC")
                    SettingsDivider()
                    FeatureRow(icon: "cube",
                               titleKey: "FEATURE_3D_TITLE",
                               descriptionKey: "FEATURE_3D_DESC")
                    SettingsDivider()
                    FeatureRow(icon: "bell.badge",
                               titleKey: "FEATURE_NOTIF_TITLE",
                               descriptionKey: "FEATURE_NOTIF_DESC")
                    SettingsDivider()
                    FeatureRow(icon: "leaf",
                               titleKey: "FEATURE_CARE_TITLE",
                               descriptionKey: "FEATURE_CARE_DESC")
                }
            }

            SettingsSectionCard(
                title: NSLocalizedString("CONTACT_SECTION_TITLE", comment: "Contact section title"),
                systemImage: "envelope"
            ) {
                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                    Text(NSLocalizedString("CONTACT_SECTION_SUBTITLE", comment: "Contact section subtitle"))
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: URL(string: "mailto:\(supportEmail)") ?? URL(fileURLWithPath: "")) {
                        HStack(spacing: ArboreDesign.Spacing.xs) {
                            Image(systemName: "paperplane")
                            Text(NSLocalizedString("CONTACT_BUTTON", comment: "Contact button"))
                        }
                    }
                    .buttonStyle(.arboreSecondary)
                }
            }

            VStack(alignment: .center, spacing: ArboreDesign.Spacing.xs) {
                Text(NSLocalizedString("FOOTER_MADEMOTTO", comment: "Footer motto"))
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)

                Text(NSLocalizedString("FOOTER_COPYRIGHT", comment: "Footer copyright"))
                    .font(ArboreDesign.Typography.caption)
                    .foregroundColor(ArboreDesign.Colors.textMuted)
            }
            .frame(maxWidth: .infinity)
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - Feature Row (Composant Localisé)
struct FeatureRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    let titleKey: String
    let descriptionKey: String

    var body: some View {
        SettingsInfoRow(
            systemImage: icon,
            title: NSLocalizedString(titleKey, comment: "Feature title"),
            subtitle: NSLocalizedString(descriptionKey, comment: "Feature description")
        )
    }
}

#Preview {
    AboutUsView()
        .environmentObject(ThemeManager())
}
