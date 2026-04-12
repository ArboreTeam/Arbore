import SwiftUI

struct AboutUsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    
    // Version de l'application
    private let appVersion = "1.0.0"
    private let supportEmail = "support@arbore.app"

    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Top Bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    // Titre localisé
                    Text(NSLocalizedString("PROFILE_ABOUT", comment: "About Arbore title"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor)

                ScrollView {
                    VStack(spacing: 24) {
                        
                        // MARK: - Header Card
                        VStack(spacing: 16) {
                            Image(systemName: "leaf.fill")
                                .font(.system(size: 52))
                                .foregroundColor(.green)

                            VStack(spacing: 6) {
                                Text("Arbore") // Nom de l'app
                                    .font(.system(size: 32, weight: .heavy))
                                    .foregroundColor(themeManager.textColor)

                                // Version localisée avec format
                                Text(String(format: NSLocalizedString("PROFILE_VERSION", comment: ""), appVersion))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.green)
                            }

                            // Slogan localisé
                            Text(NSLocalizedString("ABOUT_APP_SLOGAN", comment: "App slogan"))
                                .font(.system(size: 15))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .multilineTextAlignment(.center)
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.gray.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.separatorColor.opacity(0.3), lineWidth: 1))
                        )
                        .cornerRadius(18)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

                        // MARK: - About Section
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 20))
                                Text(NSLocalizedString("ABOUT_SECTION_TITLE", comment: "About section title"))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(themeManager.textColor)
                                Spacer()
                            }

                            Text(NSLocalizedString("ABOUT_SECTION_DESCRIPTION", comment: "About section description"))
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.textColor)
                                .lineSpacing(4)
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.gray.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.separatorColor.opacity(0.3), lineWidth: 1))
                        )
                        .cornerRadius(18)
                        .padding(.horizontal, 16)

                        // MARK: - Features Section
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles.square.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 20))
                                Text(NSLocalizedString("FEATURES_SECTION_TITLE", comment: "Features section title"))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(themeManager.textColor)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                FeatureRow(icon: "camera.viewfinder",
                                           titleKey: "FEATURE_ID_TITLE",
                                           descriptionKey: "FEATURE_ID_DESC")
                                FeatureRow(icon: "cube.fill",
                                           titleKey: "FEATURE_3D_TITLE",
                                           descriptionKey: "FEATURE_3D_DESC")
                                FeatureRow(icon: "bell.badge.fill",
                                           titleKey: "FEATURE_NOTIF_TITLE",
                                           descriptionKey: "FEATURE_NOTIF_DESC")
                                FeatureRow(icon: "leaf.fill",
                                           titleKey: "FEATURE_CARE_TITLE",
                                           descriptionKey: "FEATURE_CARE_DESC")
                            }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.gray.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.separatorColor.opacity(0.3), lineWidth: 1))
                        )
                        .cornerRadius(18)
                        .padding(.horizontal, 16)

                        // MARK: - Contact & Support
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 20))
                                Text(NSLocalizedString("CONTACT_SECTION_TITLE", comment: "Contact section title"))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(themeManager.textColor)
                                Spacer()
                            }

                            Text(NSLocalizedString("CONTACT_SECTION_SUBTITLE", comment: "Contact section subtitle"))
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.secondaryTextColor)

                            Link(destination: URL(string: "mailto:\(supportEmail)") ?? URL(fileURLWithPath: "")) {
                                HStack(spacing: 8) {
                                    Image(systemName: "paperplane.fill")
                                    Text(NSLocalizedString("CONTACT_BUTTON", comment: "Contact button"))
                                }
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(themeManager.textColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(themeManager.cardBackgroundColor))
                            }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.gray.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.separatorColor.opacity(0.3), lineWidth: 1))
                        )
                        .cornerRadius(18)
                        .padding(.horizontal, 16)

                        // MARK: - Footer
                        VStack(alignment: .center, spacing: 6) {
                            Text(NSLocalizedString("FOOTER_MADEMOTTO", comment: "Footer motto"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(themeManager.secondaryTextColor)
                            Text(NSLocalizedString("FOOTER_COPYRIGHT", comment: "Footer copyright"))
                                .font(.system(size: 13))
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

// MARK: - Feature Row (Composant Localisé)
struct FeatureRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    let titleKey: String
    let descriptionKey: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString(titleKey, comment: "Feature title"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(themeManager.textColor)
                
                Text(NSLocalizedString(descriptionKey, comment: "Feature description"))
                    .font(.system(size: 13))
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
