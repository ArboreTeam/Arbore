import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("wateringReminders") private var wateringReminders: Bool = true
    @AppStorage("wateringFrequency") private var wateringFrequency: Double = 2.0
    @AppStorage("diseaseAlerts") private var diseaseAlerts: Bool = true
    @AppStorage("seasonalTips") private var seasonalTips: Bool = true
    @AppStorage("weatherAlerts") private var weatherAlerts: Bool = true

    var body: some View {
        SettingsPage(title: NSLocalizedString("NOTIF_TITLE", comment: "Notification settings title")) {
            SettingsIntroCard(
                systemImage: "bell",
                title: NSLocalizedString("NOTIF_HEADER_TITLE", comment: ""),
                message: NSLocalizedString("NOTIF_HEADER_SUBTITLE", comment: "")
            )

            notificationToggleCard(
                icon: "bell.badge",
                title: NSLocalizedString("NOTIF_MAIN_TOGGLE_TITLE", comment: ""),
                subtitle: NSLocalizedString("NOTIF_MAIN_TOGGLE_SUBTITLE", comment: ""),
                isOn: $notificationsEnabled
            )

            if notificationsEnabled {
                wateringRemindersCard()

                notificationToggleCard(
                    icon: "ladybug",
                    title: NSLocalizedString("NOTIF_DISEASE_TITLE", comment: ""),
                    subtitle: NSLocalizedString("NOTIF_DISEASE_SUBTITLE", comment: ""),
                    isOn: $diseaseAlerts
                )

                notificationToggleCard(
                    icon: "cloud.drizzle",
                    title: NSLocalizedString("NOTIF_WEATHER_TITLE", comment: ""),
                    subtitle: NSLocalizedString("NOTIF_WEATHER_SUBTITLE", comment: ""),
                    isOn: $weatherAlerts
                )

                notificationToggleCard(
                    icon: "sun.max",
                    title: NSLocalizedString("NOTIF_SEASONAL_TITLE", comment: ""),
                    subtitle: NSLocalizedString("NOTIF_SEASONAL_SUBTITLE", comment: ""),
                    isOn: $seasonalTips,
                    tint: ArboreDesign.Colors.accentGold
                )

                SettingsSectionCard(
                    title: NSLocalizedString("NOTIF_INFO_TITLE", comment: ""),
                    systemImage: "info.circle"
                ) {
                    Text(NSLocalizedString("NOTIF_INFO_SUBTITLE", comment: ""))
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                AppCard {
                    VStack(alignment: .center, spacing: ArboreDesign.Spacing.sm) {
                        SettingsIconBadge(
                            systemImage: "bell.slash",
                            tint: ArboreDesign.Colors.textSecondary,
                            size: 58
                        )

                        Text(NSLocalizedString("NOTIF_DISABLED_TITLE", comment: ""))
                            .font(ArboreDesign.Typography.cardTitle)
                            .foregroundColor(ArboreDesign.Colors.textPrimary)

                        Text(NSLocalizedString("NOTIF_DISABLED_SUBTITLE", comment: ""))
                            .font(ArboreDesign.Typography.bodySmall)
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .interactiveDismissDisabled()
    }
    
    // MARK: - Toggle Card Component
    
    private func notificationToggleCard(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        tint: Color = ArboreDesign.Colors.primaryGreen
    ) -> some View {
        AppCard {
            SettingsToggleRow(
                systemImage: icon,
                title: title,
                subtitle: subtitle,
                isOn: isOn,
                tint: tint
            )
        }
    }
    
    // MARK: - Watering Reminders Card
    
    private func wateringRemindersCard() -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                SettingsToggleRow(
                    systemImage: "drop",
                    title: NSLocalizedString("NOTIF_WATERING_TITLE", comment: ""),
                    subtitle: NSLocalizedString("NOTIF_WATERING_SUBTITLE", comment: ""),
                    isOn: $wateringReminders
                )

                if wateringReminders {
                    SettingsDivider()

                    VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
                        HStack {
                            Text(NSLocalizedString("NOTIF_WATERING_FREQUENCY_TITLE", comment: ""))
                                .font(ArboreDesign.Typography.bodySmall.weight(.semibold))
                                .foregroundColor(ArboreDesign.Colors.textPrimary)

                            Spacer()

                            let days = Int(wateringFrequency)
                            let key = days > 1
                                ? "NOTIF_WATERING_FREQUENCY_FORMAT_PLURAL"
                                : "NOTIF_WATERING_FREQUENCY_FORMAT_SINGULAR"

                            Text(String(format: NSLocalizedString(key, comment: ""), days))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                        }

                        HStack(spacing: ArboreDesign.Spacing.xs) {
                            Text(NSLocalizedString("NOTIF_WATERING_MIN_LABEL", comment: ""))
                                .font(ArboreDesign.Typography.caption)
                                .foregroundColor(ArboreDesign.Colors.textSecondary)

                            Slider(value: $wateringFrequency, in: 1...14, step: 1)
                                .tint(ArboreDesign.Colors.primaryGreen)

                            Text(NSLocalizedString("NOTIF_WATERING_MAX_LABEL", comment: ""))
                                .font(ArboreDesign.Typography.caption)
                                .foregroundColor(ArboreDesign.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NotificationsView()
        .environmentObject(ThemeManager())
}
