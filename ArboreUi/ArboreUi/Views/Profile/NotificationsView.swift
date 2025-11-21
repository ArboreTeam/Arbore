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
                // Top bar with close button
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text("Notifications")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor)

                ScrollView {
                    VStack(spacing: 18) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Stay Updated")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(themeManager.textColor)
                            Text("Get timely reminders for plant care and important alerts")
                                .font(.system(size: 13))
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)

                        // Main notifications toggle
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "bell.badge.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 18))
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Enable Notifications")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(themeManager.textColor)
                                    Text("Receive all notifications and reminders")
                                        .font(.system(size: 12))
                                        .foregroundColor(themeManager.secondaryTextColor)
                                }
                                Spacer()
                                Toggle("", isOn: $notificationsEnabled)
                                    .labelsHidden()
                            }
                        }
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
                        .padding(.horizontal, 16)

                        if notificationsEnabled {
                            // Watering reminders section
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "drop.fill")
                                        .foregroundColor(.cyan)
                                        .font(.system(size: 18))
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Watering Reminders")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(themeManager.textColor)
                                        Text("Get reminded when your plants need water")
                                            .font(.system(size: 12))
                                            .foregroundColor(themeManager.secondaryTextColor)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $wateringReminders)
                                        .labelsHidden()
                                }

                                if wateringReminders {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text("Frequency")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(themeManager.textColor)
                                            Spacer()
                                            Text("Every \(Int(wateringFrequency)) day\(Int(wateringFrequency) > 1 ? "s" : "")")
                                                .font(.system(size: 13))
                                                .foregroundColor(.cyan)
                                        }
                                        .padding(.top, 6)

                                        HStack(spacing: 8) {
                                            Text("1d")
                                                .font(.caption2)
                                                .foregroundColor(themeManager.secondaryTextColor)
                                            Slider(value: $wateringFrequency, in: 1...14, step: 1)
                                            Text("14d")
                                                .font(.caption2)
                                                .foregroundColor(themeManager.secondaryTextColor)
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                            }
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
                            .padding(.horizontal, 16)

                            // Disease & pest alerts
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 18))
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Disease & Pest Alerts")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(themeManager.textColor)
                                        Text("Alert me about potential plant diseases")
                                            .font(.system(size: 12))
                                            .foregroundColor(themeManager.secondaryTextColor)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $diseaseAlerts)
                                        .labelsHidden()
                                }
                            }
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
                            .padding(.horizontal, 16)

                            // Weather alerts
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "cloud.rain.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 18))
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Weather Alerts")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(themeManager.textColor)
                                        Text("Get notified about weather changes")
                                            .font(.system(size: 12))
                                            .foregroundColor(themeManager.secondaryTextColor)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $weatherAlerts)
                                        .labelsHidden()
                                }
                            }
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
                            .padding(.horizontal, 16)

                            // Seasonal tips
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.yellow)
                                        .font(.system(size: 18))
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Seasonal Tips")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(themeManager.textColor)
                                        Text("Receive seasonal gardening advice")
                                            .font(.system(size: 12))
                                            .foregroundColor(themeManager.secondaryTextColor)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $seasonalTips)
                                        .labelsHidden()
                                }
                            }
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
                            .padding(.horizontal, 16)

                            // Info card
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 16))
                                    Text("Manage in Settings")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(themeManager.textColor)
                                    Spacer()
                                }
                                Text("You can also manage notification permissions in your device's Settings app.")
                                    .font(.system(size: 12))
                                    .foregroundColor(themeManager.secondaryTextColor)
                                    .lineLimit(3)
                            }
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
                            .padding(.horizontal, 16)
                        } else {
                            // Notifications disabled message
                            VStack(alignment: .center, spacing: 10) {
                                Image(systemName: "bell.slash.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(themeManager.secondaryTextColor)
                                Text("Notifications Disabled")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(themeManager.textColor)
                                Text("Enable notifications to stay updated on your plant care")
                                    .font(.system(size: 13))
                                    .foregroundColor(themeManager.secondaryTextColor)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
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
}

#Preview {
    NotificationsView()
        .environmentObject(ThemeManager())
}