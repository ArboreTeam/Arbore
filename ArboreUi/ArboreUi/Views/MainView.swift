import SwiftUI

struct MainView: View {
    @State private var selectedTab: TabSelection = .home
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Image(systemName: selectedTab == .home ? "house.fill" : "house")
                    Text("Accueil")
                }
                .tag(TabSelection.home)
            
            CatalogueView()
                .tabItem {
                    Image(systemName: selectedTab == .explore ? "square.grid.2x2.fill" : "square.grid.2x2")
                    Text("Catalogue")
                }
                .tag(TabSelection.explore)
            
            MyGardenView()
                .tabItem {
                    Image(systemName: selectedTab == .garden ? "leaf.fill" : "leaf")
                    Text("Jardin")
                }
                .tag(TabSelection.garden)
            
            ProfileView()
                .environmentObject(themeManager)
                .tabItem {
                    Image(systemName: selectedTab == .profile ? "person.crop.circle.fill" : "person.crop.circle")
                    Text("Profil")
                }
                .tag(TabSelection.profile)
        }
        .accentColor(themeManager.accentColor)
        .onAppear {
            // Configuration de l'apparence de la TabBar pour qu'elle s'adapte au thème système
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            
            // La TabBar s'adaptera automatiquement au thème système (clair/sombre)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

enum TabSelection: CaseIterable {
    case home, explore, garden, profile

    var icon: String {
        switch self {
        case .home: return "house"
        case .explore: return "square.grid.2x2"
        case .garden: return "leaf"
        case .profile: return "person.crop.circle"
        }
    }

    var iconFill: String {
        switch self {
        case .home: return "house.fill"
        case .explore: return "square.grid.2x2.fill"
        case .garden: return "leaf.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .home: return "Accueil"
        case .explore: return "Catalogue"
        case .garden: return "Jardin"
        case .profile: return "Profil"
        }
    }
}
