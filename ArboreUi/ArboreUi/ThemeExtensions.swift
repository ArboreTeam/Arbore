import SwiftUI

// Extension pour faciliter l'application des couleurs ajustées du thème
extension View {
    func themedForeground(_ themeManager: ThemeManager) -> some View {
        self.foregroundColor(themeManager.textColor)
    }
    
    func themedSecondaryForeground(_ themeManager: ThemeManager) -> some View {
        self.foregroundColor(themeManager.secondaryTextColor)
    }
    
    func themedBackground(_ themeManager: ThemeManager) -> some View {
        self.background(themeManager.backgroundColor)
    }
    
    func themedCardBackground(_ themeManager: ThemeManager) -> some View {
        self.background(themeManager.cardBackgroundColor)
    }
    
    // New helper methods for common colors
    func themedAccent(_ themeManager: ThemeManager) -> some View {
        self.accentColor(themeManager.accentColor)
    }
    
    func themedTint(_ themeManager: ThemeManager, _ color: Color) -> some View {
        self.tint(themeManager.adjust(color))
    }
}

// Environment key for ThemeManager
struct ThemeManagerKey: EnvironmentKey {
    static let defaultValue: ThemeManager = ThemeManager()
}

extension EnvironmentValues {
    var themeManager: ThemeManager {
        get { self[ThemeManagerKey.self] }
        set { self[ThemeManagerKey.self] = newValue }
    }
}

// Extension to make Color adjustments easier
extension Color {
    func adjusted(for themeManager: ThemeManager) -> Color {
        themeManager.adjust(self)
    }
    
    // Common system colors that should be adjusted
    static func systemBlue(for themeManager: ThemeManager) -> Color {
        themeManager.adjust(.blue)
    }
    
    static func systemGreen(for themeManager: ThemeManager) -> Color {
        themeManager.adjust(.green)
    }
    
    static func systemRed(for themeManager: ThemeManager) -> Color {
        themeManager.adjust(.red)
    }
    
    static func systemOrange(for themeManager: ThemeManager) -> Color {
        themeManager.adjust(.orange)
    }
    
    static func systemYellow(for themeManager: ThemeManager) -> Color {
        themeManager.adjust(.yellow)
    }
    
    static func systemPurple(for themeManager: ThemeManager) -> Color {
        themeManager.adjust(.purple)
    }
    
    static func systemPink(for themeManager: ThemeManager) -> Color {
        themeManager.adjust(.pink)
    }
}
