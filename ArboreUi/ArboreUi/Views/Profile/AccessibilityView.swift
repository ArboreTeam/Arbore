import SwiftUI
import UIKit

struct AccessibilityView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top bar - Uniforme
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text("Accessibility")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor) // Assurer un fond uni pour la barre

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) { // Augmentation de l'espacement
                        
                        // Header text
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Adapt Your Experience")
                                .font(.system(size: 28, weight: .bold)) // Plus grand
                                .foregroundColor(themeManager.textColor)
                            
                            Text("We follow your device's accessibility settings to ensure the best experience.")
                                .font(.system(size: 15))
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        .padding(.top, 18)
                        
                        // System settings card (Bouton d'action)
                        systemSettingsCard
                        
                        // Features list (Glassmorphism card)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Supported System Features")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .padding(.leading, 8)
                            
                            featuresCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                    .padding(.top, 8)
                }
            }
        }
    }
    
    // MARK: - System settings card (Refonte en bouton de style uniforme)
    private var systemSettingsCard: some View {
        Button(action: openSystemAccessibilitySettings) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14) // Carré arrondi
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: 48, height: 48) // Plus grand
                    
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 22, weight: .bold)) // Plus grand
                        .foregroundColor(.blue) // Couleur d'accentuation
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Device Settings")
                        .font(.system(size: 17, weight: .semibold)) // Plus grand
                        .foregroundColor(themeManager.textColor)
                    
                    Text("We apply system accessibility features. Configure them in device settings.")
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.secondaryTextColor.opacity(0.7))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18) // Coins uniformes
                .fill(Color.gray.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
        .cornerRadius(18) // Coins uniformes
        .buttonStyle(.plain)
    }
    
    // MARK: - Features card (Liste plus propre)
    private var featuresCard: some View {
        VStack(spacing: 0) {
            featureRow(
                icon: "waveform.circle.fill", // Nouvelle icône plus moderne
                iconColor: .orange,
                title: "VoiceOver (Screen Reader)",
                subtitle: "Audio descriptions of text and visual elements"
            )
            
            divider
            
            featureRow(
                icon: "rectangle.and.text.magnifyingglass", // Nouvelle icône
                iconColor: .purple,
                title: "Dynamic Type (Text Size)",
                subtitle: "The app adapts to your preferred text size for readability"
            )
            
            divider
            
            featureRow(
                icon: "circle.lefthalf.filled",
                iconColor: .yellow,
                title: "Increased Contrast",
                subtitle: "Adjusts colour contrast for better visibility"
            )
            
            divider
            
            featureRow(
                icon: "hand.tap.fill", // Nouvelle icône
                iconColor: .teal,
                title: "Reduced Motion",
                subtitle: "Reduces motion and visual effects for comfort"
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.gray.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
        .cornerRadius(18)
    }
    
    private var divider: some View {
        Divider()
            .background(Color.white.opacity(0.1))
            .padding(.leading, 64)
    }
    
    /// Lignes descriptives (non cliquables, pas de flèche)
    private func featureRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.18))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
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
        // Envoie l'utilisateur aux paramètres de l'application (le plus que l'on puisse faire en général)
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    AccessibilityView()
        .environmentObject(ThemeManager())
}
