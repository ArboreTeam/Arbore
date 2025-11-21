import SwiftUI

struct AboutUsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

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
                    Text("About Us")
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
                        // Header card with app info
                        VStack(spacing: 16) {
                            Image(systemName: "leaf.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.green)

                            VStack(spacing: 6) {
                                Text("Arbore")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(themeManager.textColor)

                                Text("Version 1.0.0")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.green)
                            }

                            Text("Your intelligent gardening companion")
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .multilineTextAlignment(.center)
                        }
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.10), lineWidth: 1))
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

                        // About section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 18))
                                Text("About Arbore")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(themeManager.textColor)
                                Spacer()
                            }

                            Text("Arbore is an intelligent gardening companion designed to help you grow, manage, and maintain your plants with ease. Whether you're a seasoned gardener or just starting out, Arbore provides personalized recommendations, real-time monitoring, and expert guidance.")
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.textColor)
                                .lineSpacing(4)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
                        .padding(.horizontal, 16)

                        // Features section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.green)
                                    .font(.system(size: 18))
                                Text("Key Features")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(themeManager.textColor)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                FeatureRow(icon: "camera.viewfinder", title: "Plant Identification", description: "Instantly identify plants with AI-powered scanning")
                                FeatureRow(icon: "cube.fill", title: "3D Garden Design", description: "Plan and visualize your garden in 3D")
                                FeatureRow(icon: "bell.badge.fill", title: "Smart Notifications", description: "Get reminders based on weather and seasons")
                                FeatureRow(icon: "leaf.fill", title: "Care Guidance", description: "Receive personalized plant care tips")
                            }
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
                        .padding(.horizontal, 16)

                        // Contact & Support
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 18))
                                Text("Get in Touch")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(themeManager.textColor)
                                Spacer()
                            }

                            Text("Have questions or feedback? We'd love to hear from you.")
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.secondaryTextColor)

                            Link(destination: URL(string: "mailto:support@arbore.app") ?? URL(fileURLWithPath: "")) {
                                HStack(spacing: 8) {
                                    Image(systemName: "paperplane.fill")
                                    Text("Contact Support")
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white)
                                .cornerRadius(10)
                            }
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
                        .padding(.horizontal, 16)

                        // Footer
                        VStack(alignment: .center, spacing: 6) {
                            Text("Made with 🌿 for plant lovers")
                                .font(.system(size: 13))
                                .foregroundColor(themeManager.secondaryTextColor)
                            Text("© 2025 Arbore. All rights reserved.")
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.secondaryTextColor.opacity(0.7))
                        }
                        .padding(.vertical, 20)
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - Feature Row Component
struct FeatureRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.textColor)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .lineLimit(2)
            }

            Spacer()
        }
    }
}

#Preview {
    AboutUsView()
        .environmentObject(ThemeManager())
}