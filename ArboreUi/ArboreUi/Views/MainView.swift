import SwiftUI

struct MainView: View {
    @StateObject private var tabRouter = TabRouter()
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        TabView(selection: $tabRouter.selectedTab) {
            HomeView()
                .tabItem {
                    Image(systemName: tabRouter.selectedTab == .home ? "house.fill" : "house")
                    Text(L10n.t("TAB_HOME"))
                }
                .tag(TabSelection.home)

            CatalogueView()
                .tabItem {
                    Image(systemName: tabRouter.selectedTab == .explore ? "square.grid.2x2.fill" : "square.grid.2x2")
                    Text(L10n.t("TAB_CATALOG"))
                }
                .tag(TabSelection.explore)

            ManageGardenView()
                .tabItem {
                    Image(systemName: tabRouter.selectedTab == .garden ? "leaf.fill" : "leaf")
                    Text(L10n.t("TAB_GARDEN"))
                }
                .tag(TabSelection.garden)

            ProfileView()
                .environmentObject(themeManager)
                .tabItem {
                    Image(systemName: tabRouter.selectedTab == .profile ? "person.crop.circle.fill" : "person.crop.circle")
                    Text(L10n.t("TAB_PROFILE"))
                }
                .tag(TabSelection.profile)
        }
        .accentColor(themeManager.accentColor)
        .environmentObject(tabRouter) // ✅ injecte le router à toute l'app
        .onAppear {
            ArboreTabBarAppearance.apply()
        }
    }
}
