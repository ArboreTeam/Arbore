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
                // Top bar with close button - Uniforme
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text("Notification Settings") // Nom plus complet
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor)

                ScrollView {
                    VStack(spacing: 20) { // Augmentation de l'espacement
                        // Header (Aligné à gauche pour un look plus moderne)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Stay Updated")
                                .font(.system(size: 28, weight: .bold)) // Plus grand
                                .foregroundColor(themeManager.textColor)
                            Text("Get timely reminders for plant care and important alerts")
                                .font(.system(size: 15)) // Plus grand
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        
                        // Main notifications toggle (Uniformisé avec le style de carte en verre-morphisme)
                        notificationToggleCard(
                            icon: "bell.badge.fill",
                            iconColor: .green,
                            title: "Enable Notifications",
                            subtitle: "Receive all notifications and reminders",
                            isOn: $notificationsEnabled
                        )
                        .cornerRadius(18) // Coins uniformes
                        .padding(.horizontal, 16)

                        if notificationsEnabled {
                            VStack(spacing: 16) {
                                
                                // Watering reminders section
                                wateringRemindersCard()
                                    .padding(.horizontal, 16)

                                // Disease & pest alerts
                                notificationToggleCard(
                                    icon: "ant.fill", // Icône plus spécifique aux maladies/nuisibles
                                    iconColor: .orange,
                                    title: "Disease & Pest Alerts",
                                    subtitle: "Alert me about potential plant diseases",
                                    isOn: $diseaseAlerts
                                )
                                .padding(.horizontal, 16)
                                
                                // Weather alerts
                                notificationToggleCard(
                                    icon: "cloud.drizzle.fill", // Icône plus adaptée à la météo
                                    iconColor: .blue,
                                    title: "Weather Alerts",
                                    subtitle: "Get notified about weather changes",
                                    isOn: $weatherAlerts
                                )
                                .padding(.horizontal, 16)

                                // Seasonal tips
                                notificationToggleCard(
                                    icon: "sun.max.fill", // Icône plus adaptée aux saisons
                                    iconColor: .yellow,
                                    title: "Seasonal Tips",
                                    subtitle: "Receive seasonal gardening advice",
                                    isOn: $seasonalTips
                                )
                                .padding(.horizontal, 16)
                            }
                            
                            // Info card (Utiliser un style de carte plus grand)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 18))
                                    Text("Manage in Device Settings")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(themeManager.textColor)
                                    Spacer()
                                }
                                Text("For full control, you can also manage notification permissions directly in your device's Settings app.")
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
                            // Notifications disabled message (Uniformisé avec le style de carte)
                            VStack(alignment: .center, spacing: 10) {
                                Image(systemName: "bell.slash.fill")
                                    .font(.system(size: 36)) // Plus grand
                                    .foregroundColor(themeManager.secondaryTextColor.opacity(0.7))
                                Text("Notifications Disabled")
                                    .font(.system(size: 18, weight: .bold)) // Plus audacieux
                                    .foregroundColor(themeManager.textColor)
                                Text("Enable notifications above to stay updated on your plant care and alerts.")
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
    
    // MARK: - Toggle Card Component (Style uniformisé)
    private func notificationToggleCard(icon: String, iconColor: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
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
            RoundedRectangle(cornerRadius: 18) // Uniformisation des coins
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
                    Text("Watering Reminders")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Text("Get reminded when your plants need water")
                        .font(.system(size: 13))
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                Spacer()
                Toggle("", isOn: $wateringReminders)
                    .labelsHidden()
            }

            if wateringReminders {
                VStack(alignment: .leading, spacing: 10) {
                    Divider().background(Color.white.opacity(0.1)).padding(.horizontal, -16) // Séparateur de contenu
                    
                    HStack {
                        Text("Frequency")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                        Spacer()
                        Text("Every \(Int(wateringFrequency)) day\(Int(wateringFrequency) > 1 ? "s" : "")")
                            .font(.system(size: 14, weight: .bold)) // Plus audacieux
                            .foregroundColor(.cyan)
                    }
                    
                    HStack(spacing: 8) {
                        Text("1d")
                            .font(.caption2)
                            .foregroundColor(themeManager.secondaryTextColor)
                        Slider(value: $wateringFrequency, in: 1...14, step: 1)
                            .tint(.cyan) // Couleur d'accentuation
                        Text("14d")
                            .font(.caption2)
                            .foregroundColor(themeManager.secondaryTextColor)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18) // Uniformisation des coins
                .fill(Color.gray.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
    }
}

#Preview {
    NotificationsView()
        .environmentObject(ThemeManager())
}
