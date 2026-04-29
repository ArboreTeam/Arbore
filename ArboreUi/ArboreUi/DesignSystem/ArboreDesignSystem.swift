import SwiftUI
import UIKit

enum ArboreDesign {
    enum Colors {
        static let backgroundLight = Color(hex: "#F0EEEA")
        static let backgroundDark = Color(hex: "#10100E")
        static let primaryGreen = dynamic(light: UIColor(hex: "#234632"), dark: UIColor(hex: "#2F6B46"))
        static let primaryGreenDark = Color(hex: "#2F6B46")
        static let secondaryGreen = Color(hex: "#8FAF8A")
        static let softGreenBackground = Color(hex: "#E3EBDF")
        static let accentGold = Color(hex: "#D8A85B")
        static let cardLight = Color(hex: "#FFFFFF")
        static let cardDark = Color(hex: "#1B1A17")
        static let elevatedCardDark = Color(hex: "#24231F")
        static let textPrimaryLight = Color(hex: "#1B1F1A")
        static let textSecondaryLight = Color(hex: "#6E746B")
        static let textPrimaryDark = Color(hex: "#F7F4EF")
        static let textSecondaryDark = Color(hex: "#C5CBBF")
        static let textMutedDark = Color(hex: "#9EA79D")
        static let borderLight = Color(hex: "#DDD8CF")
        static let borderDark = Color(hex: "#3B3932")
        static let danger = Color(hex: "#D9534F")
        static let success = Color(hex: "#4F8F5B")
        static let placeholderLight = Color(hex: "#9B9F98")

        static let background = dynamic(light: UIColor(hex: "#F0EEEA"), dark: UIColor(hex: "#10100E"))
        static let card = dynamic(light: UIColor(hex: "#FFFFFF"), dark: UIColor(hex: "#1B1A17"))
        static let elevatedCard = dynamic(light: UIColor(hex: "#FFFFFF"), dark: UIColor(hex: "#24231F"))
        static let textPrimary = dynamic(light: UIColor(hex: "#1B1F1A"), dark: UIColor(hex: "#F7F4EF"))
        static let textSecondary = dynamic(light: UIColor(hex: "#6E746B"), dark: UIColor(hex: "#C5CBBF"))
        static let textMuted = dynamic(light: UIColor(hex: "#8A8F87"), dark: UIColor(hex: "#9EA79D"))
        static let border = dynamic(light: UIColor(hex: "#DDD8CF"), dark: UIColor(hex: "#3B3932"))
        static let softSurface = dynamic(light: UIColor(hex: "#E3EBDF"), dark: UIColor(hex: "#2A2924"))
        static let primaryButton = dynamic(light: UIColor(hex: "#234632"), dark: UIColor(hex: "#2F6B46"))
        static let placeholder = dynamic(light: UIColor(hex: "#9B9F98"), dark: UIColor(hex: "#9EA79D"))
        static let shadow = Color.black.opacity(0.08)

        static func dynamic(light: UIColor, dark: UIColor) -> Color {
            Color(UIColor { trait in
                trait.userInterfaceStyle == .dark ? dark : light
            })
        }
    }

    enum Typography {
        static let largeTitle = Font.system(size: 32, weight: .bold)
        static let pageTitle = Font.system(size: 26, weight: .bold)
        static let sectionTitle = Font.system(size: 20, weight: .semibold)
        static let cardTitle = Font.system(size: 17, weight: .semibold)
        static let body = Font.system(size: 16, weight: .regular)
        static let bodySmall = Font.system(size: 14, weight: .regular)
        static let caption = Font.system(size: 12, weight: .regular)
        static let button = Font.system(size: 16, weight: .semibold)
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let screenHorizontal: CGFloat = 20
        static let cardPadding: CGFloat = 16
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 14
        static let button: CGFloat = 16
        static let large: CGFloat = 20
        static let image: CGFloat = 22
        static let full: CGFloat = 999
    }

    enum Icons {
        static let home = "house"
        static let catalogue = "square.grid.2x2"
        static let garden = "leaf"
        static let ar = "arkit"
        static let profile = "person.crop.circle"
        static let search = "magnifyingglass"
        static let filter = "slider.horizontal.3"
        static let chevron = "chevron.right"
        static let empty = "leaf"
        static let loading = "leaf.circle"
    }
}

enum ArboreTabBarAppearance {
    static func apply() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: "#1B1A17") : UIColor(hex: "#FFFFFF")
        }
        appearance.shadowColor = UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: "#3B3932") : UIColor(hex: "#DDD8CF")
        }

        let selected = UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: "#F7F4EF") : UIColor(hex: "#234632")
        }
        let normal = UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: "#C5CBBF") : UIColor(hex: "#8C928A")
        }

        [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance].forEach { item in
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = [.foregroundColor: selected]
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = [.foregroundColor: normal]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().tintColor = selected
        UITabBar.appearance().unselectedItemTintColor = normal
    }
}
