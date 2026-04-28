import SwiftUI
import Foundation
import UIKit

class ThemeManager: ObservableObject {
    @Published var useSystemTheme: Bool {
        didSet { UserDefaults.standard.set(useSystemTheme, forKey: "useSystemTheme") }
    }
    @Published var manualDarkMode: Bool {
        didSet { UserDefaults.standard.set(manualDarkMode, forKey: "manualDarkMode") }
    }
    @Published var selectedColorScheme: String {
        didSet {
            UserDefaults.standard.set(selectedColorScheme, forKey: "selectedColorScheme")
        }
    }
    @Published var dynamicTypeSize: Double {
        didSet { UserDefaults.standard.set(dynamicTypeSize, forKey: "dynamicTypeSize") }
    }
    
    init() {
        self.useSystemTheme = UserDefaults.standard.object(forKey: "useSystemTheme") as? Bool ?? true
        self.manualDarkMode = UserDefaults.standard.bool(forKey: "manualDarkMode")
        self.selectedColorScheme = UserDefaults.standard.string(forKey: "selectedColorScheme") ?? "Default"
        self.dynamicTypeSize = UserDefaults.standard.double(forKey: "dynamicTypeSize") != 0.0 ? UserDefaults.standard.double(forKey: "dynamicTypeSize") : 1.0
    }
    
    var colorScheme: ColorScheme? { useSystemTheme ? nil : (manualDarkMode ? .dark : .light) }
    
    // Mapping du slider (0.8...1.5) vers DynamicTypeSize pour affecter toute l'app
    var mappedDynamicTypeSize: DynamicTypeSize {
        let v = dynamicTypeSize
        switch v {
        case ..<0.85: return .xSmall
        case ..<0.95: return .small
        case ..<1.05: return .medium
        case ..<1.15: return .large
        case ..<1.25: return .xLarge
        case ..<1.35: return .xxLarge
        case ..<1.45: return .xxxLarge
        case ..<1.55: return .accessibility1
        default: return .accessibility2
        }
    }
    
    // MARK: - Daltonisme: ajustement des couleurs via matrices simples
    private func adjustForColorBlindness(r: CGFloat, g: CGFloat, b: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        switch selectedColorScheme {
        case "Protanopia":
            // Perte de sensibilité au rouge
            let r2 = 0.567*r + 0.433*g
            let g2 = 0.558*r + 0.442*g
            let b2 = b
            return (r2, g2, b2)
        case "Deuteranopia":
            // Perte de sensibilité au vert
            let r2 = 0.625*r + 0.375*g
            let g2 = 0.7*r + 0.3*g
            let b2 = b
            return (r2, g2, b2)
        case "Tritanopia":
            // Perte de sensibilité au bleu
            let r2 = r
            let g2 = 0.95*g + 0.05*b
            let b2 = 0.43*g + 0.57*b
            return (r2, g2, b2)
        default:
            return (r, g, b)
        }
    }
    
    private func adjustedUIColor(_ uiColor: UIColor) -> UIColor {
        guard selectedColorScheme != "Default" else { return uiColor }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let (nr, ng, nb) = adjustForColorBlindness(r: r, g: g, b: b)
        return UIColor(red: min(max(nr,0),1), green: min(max(ng,0),1), blue: min(max(nb,0),1), alpha: a)
    }
    
    func adjust(_ color: Color) -> Color { Color(adjustedUIColor(UIColor(color))) }
    
    // MARK: - Arbore Organic Premium Color System
    var backgroundColor: Color { adjust(ArboreDesign.Colors.background) }
    var cardBackgroundColor: Color { adjust(ArboreDesign.Colors.card) }
    var tertiaryBackgroundColor: Color { adjust(ArboreDesign.Colors.softSurface) }
    var textColor: Color { adjust(ArboreDesign.Colors.textPrimary) }
    var secondaryTextColor: Color { adjust(ArboreDesign.Colors.textSecondary) }
    var tertiaryTextColor: Color { adjust(ArboreDesign.Colors.textSecondary.opacity(0.78)) }
    var placeholderTextColor: Color { adjust(ArboreDesign.Colors.placeholder) }
    var accentColor: Color { brandPrimary }

    // MARK: - Brand Design Tokens
    var brandPrimary: Color {
        adjust(ArboreDesign.Colors.primaryGreen)
    }

    var brandPrimaryLight: Color {
        adjust(ArboreDesign.Colors.softSurface)
    }

    var brandPrimaryHero: Color {
        adjust(ArboreDesign.Colors.primaryGreen)
    }

    // MARK: - Design Tokens — Spacing & Shape
    var cardCornerRadius: CGFloat { ArboreDesign.Radius.large }
    var heroCornerRadius: CGFloat { ArboreDesign.Radius.image }

    func pageTitle(size: CGFloat = 34) -> Font {
        .system(size: size, weight: .bold)
    }

    func sectionTitle(size: CGFloat = 22) -> Font {
        .system(size: size, weight: .semibold)
    }

    func cardTitle(size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold)
    }

    func bodyText(size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular)
    }
    // System colors adjusted for color blindness
    var systemBlue: Color { adjust(.blue) }
    var systemGreen: Color { adjust(ArboreDesign.Colors.success) }
    var systemRed: Color { adjust(ArboreDesign.Colors.danger) }
    var systemOrange: Color { adjust(.orange) }
    var systemYellow: Color { adjust(.yellow) }
    var systemPurple: Color { adjust(.purple) }
    var systemPink: Color { adjust(.pink) }
    var systemIndigo: Color { adjust(.indigo) }
    var systemTeal: Color { adjust(.teal) }
    var systemMint: Color { adjust(.mint) }
    var systemCyan: Color { adjust(.cyan) }
    
    // UI Element colors
    var separatorColor: Color { adjust(ArboreDesign.Colors.border) }
    var linkColor: Color { adjust(Color(.link)) }
    var fillColor: Color { adjust(ArboreDesign.Colors.softSurface) }
    var secondaryFillColor: Color { adjust(ArboreDesign.Colors.softSurface.opacity(0.75)) }
    var tertiaryFillColor: Color { adjust(ArboreDesign.Colors.softSurface.opacity(0.55)) }
    var quaternaryFillColor: Color { adjust(ArboreDesign.Colors.softSurface.opacity(0.35)) }
    
    // Navigation and Tab Bar colors
    var navigationBackgroundColor: Color { adjust(ArboreDesign.Colors.background) }
    var tabBarBackgroundColor: Color { adjust(ArboreDesign.Colors.card) }
}
