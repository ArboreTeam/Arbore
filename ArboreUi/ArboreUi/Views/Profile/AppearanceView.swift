import SwiftUI
import UIKit

struct AppearanceView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showLanguageSheet = false
    @State private var showThemeSheet = false
    @State private var showInterfaceSheet = false
    
    // Langue actuelle affichée dans la cellule
    private var currentLanguageDisplayName: String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let components = Locale.Components(identifier: preferred)
        let langCode = components.languageComponents.languageCode?.identifier ?? preferred
        let locale = Locale.current
        let name = locale.localizedString(forLanguageCode: langCode) ?? "English"
        return name.capitalized
    }
    
    var body: some View {
        SettingsPage(title: NSLocalizedString("APPEARANCE_TITLE", comment: "Appearance Title")) {
            appearanceCard
        }
        .sheet(isPresented: $showLanguageSheet) {
            languageSheet
                .presentationDetents([.height(260), .medium])
        }
        .sheet(isPresented: $showThemeSheet) {
            themeSheet
                .presentationDetents([.height(280), .medium])
        }
        .sheet(isPresented: $showInterfaceSheet) {
            interfaceSheet
                .presentationDetents([.height(260), .medium])
        }
    }

    // MARK: - Main card
    
    private var appearanceCard: some View {
        VStack(spacing: ArboreDesign.Spacing.xs) {
            buttonRow(
                icon: "app.dashed",
                title: NSLocalizedString("APPEARANCE_APP_ICON", comment: ""),
                subtitle: NSLocalizedString("APPEARANCE_APP_ICON_STANDARD", comment: ""),
                valueText: nil,
                action: {}
            )

            buttonRow(
                icon: "circle.lefthalf.filled",
                title: NSLocalizedString("APPEARANCE_THEME", comment: ""),
                subtitle: NSLocalizedString("APPEARANCE_THEME_CURRENT", comment: ""),  
                valueText: nil,
                action: { showThemeSheet = true },
                tint: ArboreDesign.Colors.accentGold
            )

            buttonRow(
                icon: "rectangle.and.hand.point.up.left",
                title: NSLocalizedString("APPEARANCE_INTERFACE", comment: ""),
                subtitle: NSLocalizedString("APPEARANCE_INTERFACE_SUBTITLE", comment: ""),
                valueText: nil,
                action: { showInterfaceSheet = true }
            )

            buttonRow(
                icon: "globe",
                title: NSLocalizedString("APPEARANCE_LANGUAGE", comment: ""),
                subtitle: currentLanguageDisplayName,
                valueText: nil,
                action: { showLanguageSheet = true }
            )
        }
    }
    
    // MARK: - Row
    
    private func buttonRow(
        icon: String,
        title: String,
        subtitle: String? = nil,
        valueText: String? = nil,
        action: @escaping () -> Void,
        tint: Color = ArboreDesign.Colors.primaryGreen
    ) -> some View {
        Button(action: action) {
            SettingsRow(
                systemImage: icon,
                title: title,
                subtitle: valueText.map { subtitle == nil ? $0 : "\(subtitle ?? "") · \($0)" } ?? subtitle,
                tint: tint
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Sheets
    
    private var languageSheet: some View {
        AppBackground {
            sheetStack {
                Text(NSLocalizedString("APPEARANCE_LANGUAGE", comment: ""))
                    .font(ArboreDesign.Typography.sectionTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)

                Text(NSLocalizedString("APPEARANCE_LANGUAGE_DESCRIPTION", comment: ""))
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)

                Button(action: openSystemSettings) {
                    Text(NSLocalizedString("APPEARANCE_LANGUAGE_BUTTON", comment: ""))
                }
                .buttonStyle(.arborePrimary)
                .padding(.top, ArboreDesign.Spacing.xs)
            }
        }
    }
    
    private var themeSheet: some View {
        AppBackground {
            sheetStack {
                Text(NSLocalizedString("APPEARANCE_THEME", comment: ""))
                    .font(ArboreDesign.Typography.sectionTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)

                Text(NSLocalizedString("APPEARANCE_THEME_DESCRIPTION", comment: ""))
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: ArboreDesign.Spacing.xs) {
                    themeOptionRow(title: NSLocalizedString("APPEARANCE_THEME_SYSTEM", comment: "")) {}
                    themeOptionRow(title: NSLocalizedString("APPEARANCE_THEME_LIGHT", comment: "")) {}
                    themeOptionRow(title: NSLocalizedString("APPEARANCE_THEME_DARK", comment: "")) {}
                }
            }
        }
    }
    
    private func themeOptionRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(ArboreDesign.Typography.body)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                Spacer()
            }
            .padding(ArboreDesign.Spacing.md)
            .background(ArboreDesign.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                    .stroke(ArboreDesign.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var interfaceSheet: some View {
        AppBackground {
            sheetStack {
                Text(NSLocalizedString("APPEARANCE_INTERFACE", comment: ""))
                    .font(ArboreDesign.Typography.sectionTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)

                Text(NSLocalizedString("APPEARANCE_INTERFACE_DESCRIPTION", comment: ""))
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)

                Button(action: openSystemSettings) {
                    Text(NSLocalizedString("APPEARANCE_OPEN_DEVICE_SETTINGS", comment: ""))
                }
                .buttonStyle(.arborePrimary)
                .padding(.top, ArboreDesign.Spacing.xs)
            }
        }
    }

    private func sheetStack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: ArboreDesign.Spacing.lg) {
            Capsule()
                .frame(width: 40, height: 4)
                .foregroundColor(ArboreDesign.Colors.border)
                .padding(.top, ArboreDesign.Spacing.sm)

            content()

            Spacer()
        }
        .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
    }
    
    // MARK: - Helpers
    
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    AppearanceView()
        .environmentObject(ThemeManager())
}
