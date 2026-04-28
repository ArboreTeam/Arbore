import SwiftUI
import UIKit

struct AccessibilityView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        SettingsPage(title: NSLocalizedString("ACCESSIBILITY_TITLE", comment: "Accessibility screen title")) {
            SettingsIntroCard(
                systemImage: "accessibility",
                title: NSLocalizedString("ACCESSIBILITY_HEADER_TITLE", comment: "Accessibility header title"),
                message: NSLocalizedString("ACCESSIBILITY_HEADER_SUBTITLE", comment: "Accessibility header subtitle")
            )

            systemSettingsCard

            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
                SectionTitle(title: NSLocalizedString("ACCESSIBILITY_FEATURES_SECTION_TITLE", comment: "Supported system features title"))
                featuresCard
            }
        }
    }
    
    // MARK: - System settings card
    
    private var systemSettingsCard: some View {
        Button(action: openSystemAccessibilitySettings) {
            SettingsRow(
                systemImage: "gearshape",
                title: NSLocalizedString("ACCESSIBILITY_OPEN_SETTINGS_TITLE", comment: "Open device settings button title"),
                subtitle: NSLocalizedString("ACCESSIBILITY_OPEN_SETTINGS_SUBTITLE", comment: "Open device settings subtitle")
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Features card
    
    private var featuresCard: some View {
        SettingsSectionCard(
            title: NSLocalizedString("ACCESSIBILITY_FEATURES_SECTION_TITLE", comment: "Supported system features title"),
            systemImage: "checkmark.seal"
        ) {
            VStack(spacing: ArboreDesign.Spacing.md) {
            featureRow(
                icon: "waveform.circle",
                titleKey: "ACCESSIBILITY_FEATURE_VOICEOVER_TITLE",
                subtitleKey: "ACCESSIBILITY_FEATURE_VOICEOVER_SUBTITLE"
            )

            SettingsDivider()

            featureRow(
                icon: "rectangle.and.text.magnifyingglass",
                titleKey: "ACCESSIBILITY_FEATURE_DYNAMICTYPE_TITLE",
                subtitleKey: "ACCESSIBILITY_FEATURE_DYNAMICTYPE_SUBTITLE"
            )

            SettingsDivider()

            featureRow(
                icon: "circle.lefthalf.filled",
                titleKey: "ACCESSIBILITY_FEATURE_CONTRAST_TITLE",
                subtitleKey: "ACCESSIBILITY_FEATURE_CONTRAST_SUBTITLE"
            )

            SettingsDivider()

            featureRow(
                icon: "hand.tap",
                titleKey: "ACCESSIBILITY_FEATURE_REDUCEDMOTION_TITLE",
                subtitleKey: "ACCESSIBILITY_FEATURE_REDUCEDMOTION_SUBTITLE"
            )
            }
        }
    }
    
    /// Lignes descriptives (non cliquables, pas de flèche)
    private func featureRow(icon: String, titleKey: String, subtitleKey: String) -> some View {
        SettingsInfoRow(
            systemImage: icon,
            title: NSLocalizedString(titleKey, comment: "Accessibility feature title"),
            subtitle: NSLocalizedString(subtitleKey, comment: "Accessibility feature subtitle")
        )
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
