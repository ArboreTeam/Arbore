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
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text(NSLocalizedString("NOTIF_TITLE", comment: "Notification settings title"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor)

                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("NOTIF_HEADER_TITLE", comment: ""))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(themeManager.textColor)
                            
                            Text(NSLocalizedString("NOTIF_HEADER_SUBTITLE", comment: ""))
                                .font(.system(size: 15))
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        
                        // Main notifications toggle
                        notificationToggleCard(
                            icon: "bell.badge.fill",
                            iconColor: .green,
                            title: NSLocalizedString("NOTIF_MAIN_TOGGLE_TITLE", comment: ""),
                            subtitle: NSLocalizedString("NOTIF_MAIN_TOGGLE_SUBTITLE", comment: ""),
                            isOn: $notificationsEnabled
                        )
                        .cornerRadius(18)
                        .padding(.horizontal, 16)

                        if notificationsEnabled {
                            VStack(spacing: 16) {
                                // Watering reminders
                                wateringRemindersCard()
                                    .padding(.horizontal, 16)

                                // Disease & pest alerts
                                notificationToggleCard(
                                    icon: "ant.fill",
                                    iconColor: .orange,
                                    title: NSLocalizedString("NOTIF_DISEASE_TITLE", comment: ""),
                                    subtitle: NSLocalizedString("NOTIF_DISEASE_SUBTITLE", comment: ""),
                                    isOn: $diseaseAlerts
                                )
                                .padding(.horizontal, 16)
                                
                                // Weather alerts
                                notificationToggleCard(
                                    icon: "cloud.drizzle.fill",
                                    iconColor: .blue,
                                    title: NSLocalizedString("NOTIF_WEATHER_TITLE", comment: ""),
                                    subtitle: NSLocalizedString("NOTIF_WEATHER_SUBTITLE", comment: ""),
                                    isOn: $weatherAlerts
                                )
                                .padding(.horizontal, 16)

                                // Seasonal tips
                                notificationToggleCard(
                                    icon: "sun.max.fill",
                                    iconColor: .yellow,
                                    title: NSLocalizedString("NOTIF_SEASONAL_TITLE", comment: ""),
                                    subtitle: NSLocalizedString("NOTIF_SEASONAL_SUBTITLE", comment: ""),
                                    isOn: $seasonalTips
                                )
                                .padding(.horizontal, 16)
                            }
                            
                            // Info card
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 18))
                                    
                                    Text(NSLocalizedString("NOTIF_INFO_TITLE", comment: ""))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(themeManager.textColor)
                                    
                                    Spacer()
                                }
                                
                                Text(NSLocalizedString("NOTIF_INFO_SUBTITLE", comment: ""))
                                    .font(.system(size: 13))
                                    .foregroundColor(themeManager.secondaryTextColor)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.gray.opacity(0.12))
                                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
                            )
                            .padding(.horizontal, 16)
                        } else {
                            // Notifications disabled card
                            VStack(alignment: .center, spacing: 10) {
                                Image(systemName: "bell.slash.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(themeManager.secondaryTextColor.opacity(0.7))
                                
                                Text(NSLocalizedString("NOTIF_DISABLED_TITLE", comment: ""))
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(themeManager.textColor)
                                
                                Text(NSLocalizedString("NOTIF_DISABLED_SUBTITLE", comment: ""))
                                    .font(.system(size: 14))
                                    .foregroundColor(themeManager.secondaryTextColor)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(24)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.gray.opacity(0.12))
                                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
                            )
                            .padding(.horizontal, 16)
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.bottom, 30)
                }
            }
        }
        .interactiveDismissDisabled()
    }
    
    // MARK: - Toggle Card Component
    
    private func notificationToggleCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.system(size: 20))
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.textColor)
                
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(themeManager.secondaryTextColor)
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.gray.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
    }
    
    // MARK: - Watering Reminders Card
    
    private func wateringRemindersCard() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "drop.fill")
                    .foregroundColor(.cyan)
                    .font(.system(size: 20))
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("NOTIF_WATERING_TITLE", comment: ""))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    
                    Text(NSLocalizedString("NOTIF_WATERING_SUBTITLE", comment: ""))
                        .font(.system(size: 13))
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                
                Spacer()
                
                Toggle("", isOn: $wateringReminders)
                    .labelsHidden()
            }

            if wateringReminders {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, -16)
                    
                    HStack {
                        Text(NSLocalizedString("NOTIF_WATERING_FREQUENCY_TITLE", comment: ""))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                        
                        Spacer()
                        
                        let days = Int(wateringFrequency)
                        let key = days > 1
                            ? "NOTIF_WATERING_FREQUENCY_FORMAT_PLURAL"
                            : "NOTIF_WATERING_FREQUENCY_FORMAT_SINGULAR"
                        
                        Text(String(format: NSLocalizedString(key, comment: ""), days))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.cyan)
                    }
                    
                    HStack(spacing: 8) {
                        Text(NSLocalizedString("NOTIF_WATERING_MIN_LABEL", comment: ""))
                            .font(.caption2)
                            .foregroundColor(themeManager.secondaryTextColor)
                        
                        Slider(value: $wateringFrequency, in: 1...14, step: 1)
                            .tint(.cyan)
                        
                        Text(NSLocalizedString("NOTIF_WATERING_MAX_LABEL", comment: ""))
                            .font(.caption2)
                            .foregroundColor(themeManager.secondaryTextColor)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.gray.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
    }
}

#Preview {
    NotificationsView()
        .environmentObject(ThemeManager())
}
