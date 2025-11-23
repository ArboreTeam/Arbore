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
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text(NSLocalizedString("ACCESSIBILITY_TITLE", comment: "Accessibility screen title"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        
                        // Header text
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("ACCESSIBILITY_HEADER_TITLE", comment: "Accessibility header title"))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(themeManager.textColor)
                            
                            Text(NSLocalizedString("ACCESSIBILITY_HEADER_SUBTITLE", comment: "Accessibility header subtitle"))
                                .font(.system(size: 15))
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        .padding(.top, 18)
                        
                        // System settings card
                        systemSettingsCard
                        
                        // Features list
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("ACCESSIBILITY_FEATURES_SECTION_TITLE", comment: "Supported system features title"))
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
    
    // MARK: - System settings card
    
    private var systemSettingsCard: some View {
        Button(action: openSystemAccessibilitySettings) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("ACCESSIBILITY_OPEN_SETTINGS_TITLE", comment: "Open device settings button title"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    
                    Text(NSLocalizedString("ACCESSIBILITY_OPEN_SETTINGS_SUBTITLE", comment: "Open device settings subtitle"))
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
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.gray.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
        .cornerRadius(18)
        .buttonStyle(.plain)
    }
    
    // MARK: - Features card
    
    private var featuresCard: some View {
        VStack(spacing: 0) {
            featureRow(
                icon: "waveform.circle.fill",
                iconColor: .orange,
                titleKey: "ACCESSIBILITY_FEATURE_VOICEOVER_TITLE",
                subtitleKey: "ACCESSIBILITY_FEATURE_VOICEOVER_SUBTITLE"
            )
            
            divider
            
            featureRow(
                icon: "rectangle.and.text.magnifyingglass",
                iconColor: .purple,
                titleKey: "ACCESSIBILITY_FEATURE_DYNAMICTYPE_TITLE",
                subtitleKey: "ACCESSIBILITY_FEATURE_DYNAMICTYPE_SUBTITLE"
            )
            
            divider
            
            featureRow(
                icon: "circle.lefthalf.filled",
                iconColor: .yellow,
                titleKey: "ACCESSIBILITY_FEATURE_CONTRAST_TITLE",
                subtitleKey: "ACCESSIBILITY_FEATURE_CONTRAST_SUBTITLE"
            )
            
            divider
            
            featureRow(
                icon: "hand.tap.fill",
                iconColor: .teal,
                titleKey: "ACCESSIBILITY_FEATURE_REDUCEDMOTION_TITLE",
                subtitleKey: "ACCESSIBILITY_FEATURE_REDUCEDMOTION_SUBTITLE"
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
    private func featureRow(icon: String, iconColor: Color, titleKey: String, subtitleKey: String) -> some View {
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
                Text(NSLocalizedString(titleKey, comment: "Accessibility feature title"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.textColor)
                
                Text(NSLocalizedString(subtitleKey, comment: "Accessibility feature subtitle"))
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
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    AccessibilityView()
        .environmentObject(ThemeManager())
}
