import SwiftUI

struct MainView: View {
    @StateObject private var tabRouter = TabRouter()
    @EnvironmentObject var themeManager: ThemeManager

    #if DEBUG
    @State private var isDebugModeActive = false
    #endif

    var body: some View {
        ZStack {
            TabView(selection: $tabRouter.selectedTab) {
                HomeView()
                    .tabItem {
                        Image(systemName: tabRouter.selectedTab == .home ? "house.fill" : "house")
                        Text("Accueil")
                    }
                    .tag(TabSelection.home)

                CatalogueView()
                    .tabItem {
                        Image(systemName: tabRouter.selectedTab == .explore ? "square.grid.2x2.fill" : "square.grid.2x2")
                        Text("Catalogue")
                    }
                    .tag(TabSelection.explore)

                ManageGardenView()
                    .tabItem {
                        Image(systemName: tabRouter.selectedTab == .garden ? "leaf.fill" : "leaf")
                        Text("Jardin")
                    }
                    .tag(TabSelection.garden)

                ProfileView()
                    .environmentObject(themeManager)
                    .tabItem {
                        Image(systemName: tabRouter.selectedTab == .profile ? "person.crop.circle.fill" : "person.crop.circle")
                        Text("Profil")
                    }
                    .tag(TabSelection.profile)
            }
            .accentColor(themeManager.accentColor)
            .environmentObject(tabRouter) // ✅ injecte le router à toute l'app
            .onAppear {
                let appearance = UITabBarAppearance()
                appearance.configureWithDefaultBackground()
                UITabBar.appearance().standardAppearance = appearance
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }

            #if DEBUG
            // Debug Mode Sheet
            .sheet(isPresented: $isDebugModeActive) {
                DebugThumbnailGeneratorView()
            }

            // Secret triple-tap gesture on app version
            .overlay(
                VStack {
                    HStack {
                        Text("v1.0")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .opacity(0.3)
                            .onTapGesture(count: 3) {
                                isDebugModeActive.toggle()
                            }
                        Spacer()
                    }
                    .padding(8)
                    Spacer()
                },
                alignment: .topLeading
            )
            #endif
        }
    }
}
