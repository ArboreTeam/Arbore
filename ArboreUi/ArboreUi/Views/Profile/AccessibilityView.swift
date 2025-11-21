import SwiftUI
import UIKit

struct AccessibilityView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    descriptionText
                    systemSettingsCard
                    featuresCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                        .padding(.trailing, 4)
                }
                Spacer()
            }
            
            Text("Accessibility")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(themeManager.textColor)
        }
        .padding(.top, 4)
    }
    
    private var descriptionText: some View {
        Text("Features controlled by the system")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(themeManager.secondaryTextColor)
    }
    
    // MARK: - System settings card
    
    private var systemSettingsCard: some View {
        Button(action: openSystemAccessibilitySettings) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("System settings")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    
                    Text("We apply system accessibility features. You can configure them in device settings.")
                        .font(.system(size: 13))
                        .foregroundColor(themeManager.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(themeManager.secondaryTextColor.opacity(0.7))
            }
            .padding(16)
            .background(
                ZStack {
                    Color.gray.opacity(0.08)
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.06)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Features card
    
    private var featuresCard: some View {
        VStack(spacing: 0) {
            featureRow(
                icon: "speaker.wave.2.fill",
                title: "Screen reader - VoiceOver",
                subtitle: "Audio descriptions of text and visual elements"
            )
            
            divider
            
            featureRow(
                icon: "u.square.fill",
                title: "Action visibility",
                subtitle: "Use Button Shapes setting to increase visibility of links and buttons"
            )
            
            divider
            
            featureRow(
                icon: "circle.lefthalf.filled",
                title: "Colour contrast",
                subtitle: "Increase contrast between colours"
            )
            
            divider
            
            featureRow(
                icon: "textformat.size",
                title: "Adjust text size",
                subtitle: "Make text bold or change its size for better readability"
            )
            
            divider
            
            featureRow(
                icon: "sparkles",
                title: "Reduce motion",
                subtitle: "Reduce amount of various motion effects"
            )
        }
        .background(
            ZStack {
                Color.gray.opacity(0.08)
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .cornerRadius(16)
    }
    
    private var divider: some View {
        Divider()
            .background(Color.gray.opacity(0.3))
            .padding(.leading, 64)
    }
    
    /// Lignes descriptives (non cliquables, sans flèche)
    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.textColor)
                
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    // MARK: - Helpers
    
    private func openSystemAccessibilitySettings() {
        // API publique : ouvre la page Réglages de l’app.
        // Depuis là, l’utilisateur peut remonter à la page principale des Réglages.
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    AccessibilityView()
        .environmentObject(ThemeManager())
}
