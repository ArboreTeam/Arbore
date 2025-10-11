import SwiftUI
import Foundation

class ThemeManager: ObservableObject {
    @Published var useSystemTheme: Bool {
        didSet {
            UserDefaults.standard.set(useSystemTheme, forKey: "useSystemTheme")
        }
    }
    
    @Published var manualDarkMode: Bool {
        didSet {
            UserDefaults.standard.set(manualDarkMode, forKey: "manualDarkMode")
        }
    }
    
    @Published var selectedColorScheme: String {
        didSet {
            UserDefaults.standard.set(selectedColorScheme, forKey: "selectedColorScheme")
        }
    }
    
    @Published var dynamicTypeSize: Double {
        didSet {
            UserDefaults.standard.set(dynamicTypeSize, forKey: "dynamicTypeSize")
        }
    }
    
    init() {
        self.useSystemTheme = UserDefaults.standard.object(forKey: "useSystemTheme") as? Bool ?? true
        self.manualDarkMode = UserDefaults.standard.bool(forKey: "manualDarkMode")
        self.selectedColorScheme = UserDefaults.standard.string(forKey: "selectedColorScheme") ?? "Default"
        self.dynamicTypeSize = UserDefaults.standard.double(forKey: "dynamicTypeSize") != 0.0 ? 
            UserDefaults.standard.double(forKey: "dynamicTypeSize") : 1.0
    }
    
    var colorScheme: ColorScheme? {
        if useSystemTheme {
            return nil // Utilise le thème système automatiquement
        } else {
            return manualDarkMode ? .dark : .light
        }
    }
    
    // Colors qui s'adaptent automatiquement au thème système
    var backgroundColor: Color {
        return Color(.systemBackground)
    }
    
    var cardBackgroundColor: Color {
        return Color(.secondarySystemBackground)
    }
    
    var textColor: Color {
        return Color(.label)
    }
    
    var secondaryTextColor: Color {
        return Color(.secondaryLabel)
    }
}
