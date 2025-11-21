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
        let components = Locale.components(fromIdentifier: preferred)
        let langCode = components[NSLocale.Key.languageCode.rawValue] ?? preferred
        let locale = Locale.current
        let name = locale.localizedString(forLanguageCode: langCode) ?? "English"
        return name.capitalized
    }
    
    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    
                    appearanceCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
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
            
            Text("Appearance")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(themeManager.textColor)
        }
        .padding(.top, 4)
    }
    
    // MARK: - Main card
    
    private var appearanceCard: some View {
        VStack(spacing: 0) {
            buttonRow(
                icon: "r.circle.fill",
                iconBackground: .gray.opacity(0.25),
                title: "App icon",
                subtitle: "Standard",
                valueText: nil,
                action: {
                    // TODO: ouvrir un écran / sheet pour choisir l’icône si tu en as plusieurs
                }
            )
            
            divider
            
            buttonRow(
                icon: "lightbulb.fill",
                iconBackground: .yellow.opacity(0.25),
                title: "Theme",
                subtitle: "Dark · Glow", // TODO: rendre dynamique si tu as plusieurs thèmes
                valueText: nil,
                action: {
                    showThemeSheet = true
                }
            )
            
            divider
            
            buttonRow(
                icon: "rectangle.and.hand.point.up.left.fill",
                iconBackground: .blue.opacity(0.25),
                title: "Interface",
                subtitle: "Buttons, animations, etc.",
                valueText: nil,
                action: {
                    showInterfaceSheet = true
                }
            )
            
            divider
            
            buttonRow(
                icon: "globe",
                iconBackground: .green.opacity(0.25),
                title: "Language",
                subtitle: currentLanguageDisplayName,
                valueText: nil,
                action: {
                    showLanguageSheet = true
                }
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
    
    // MARK: - Row
    
    private func buttonRow(
        icon: String,
        iconBackground: Color,
        title: String,
        subtitle: String? = nil,
        valueText: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconBackground)
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(themeManager.secondaryTextColor)
                    }
                }
                
                Spacer()
                
                if let valueText = valueText {
                    Text(valueText)
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(themeManager.secondaryTextColor.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Sheets
    
    private var languageSheet: some View {
        VStack(spacing: 20) {
            Capsule()
                .frame(width: 40, height: 4)
                .foregroundColor(Color.gray.opacity(0.4))
                .padding(.top, 8)
            
            Text("Language")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(themeManager.textColor)
            
            Text("We use the same language set for your device. So, you can change the language simply by going into your device settings.")
                .font(.system(size: 15))
                .foregroundColor(themeManager.secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            Button(action: openSystemSettings) {
                Text("Take me there")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.white.opacity(0.12))
                    )
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            
            Spacer()
        }
        .background(themeManager.backgroundColor.ignoresSafeArea())
    }
    
    private var themeSheet: some View {
        VStack(spacing: 20) {
            Capsule()
                .frame(width: 40, height: 4)
                .foregroundColor(Color.gray.opacity(0.4))
                .padding(.top, 8)
            
            Text("Theme")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(themeManager.textColor)
            
            Text("Choose how your app looks. You can match the system appearance or force light / dark.")
                .font(.system(size: 15))
                .foregroundColor(themeManager.secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            VStack(spacing: 10) {
                themeOptionRow(title: "Match system") {
                    // TODO: themeManager.set(.system) si tu as ça
                }
                themeOptionRow(title: "Light") {
                    // TODO: themeManager.set(.light)
                }
                themeOptionRow(title: "Dark") {
                    // TODO: themeManager.set(.dark)
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .background(themeManager.backgroundColor.ignoresSafeArea())
    }
    
    private func themeOptionRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(themeManager.textColor)
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.12))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private var interfaceSheet: some View {
        VStack(spacing: 20) {
            Capsule()
                .frame(width: 40, height: 4)
                .foregroundColor(Color.gray.opacity(0.4))
                .padding(.top, 8)
            
            Text("Interface")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(themeManager.textColor)
            
            Text("Interface options such as button style and motion effects are based on your system settings. You can customise them from the device settings.")
                .font(.system(size: 15))
                .foregroundColor(themeManager.secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            Button(action: openSystemSettings) {
                Text("Open device settings")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.white.opacity(0.12))
                    )
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .background(themeManager.backgroundColor.ignoresSafeArea())
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
