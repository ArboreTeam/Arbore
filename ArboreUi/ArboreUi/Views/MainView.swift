import SwiftUI

struct MainView: View {
    @StateObject private var tabRouter = TabRouter()
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject private var notificationRouter: NotificationRouter
    @State private var routedPlant: RoutedPlant?

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

            CommunityView()
                .tabItem {
                    Image(systemName: tabRouter.selectedTab == .community ? "person.2.fill" : "person.2")
                    Text("Communauté")
                }
                .tag(TabSelection.community)

            ProfileView()
                .environmentObject(themeManager)
                .tabItem {
                    Image(systemName: tabRouter.selectedTab == .profile ? "person.crop.circle.fill" : "person.crop.circle")
                    Text(L10n.t("TAB_PROFILE"))
                }
                .tag(TabSelection.profile)
        }
        .tint(themeManager.accentColor)
        .environmentObject(tabRouter)
        .onAppear {
            applyNotificationRoute(notificationRouter.pendingRoute)
        }
        .onChange(of: notificationRouter.pendingRoute) { _, route in
            applyNotificationRoute(route)
        }
        .sheet(item: $routedPlant) { routedPlant in
            PlantDetailView(plantID: routedPlant.id)
                .environmentObject(themeManager)
        }
        .alert(item: $notificationRouter.inAppNotification) { notification in
            Alert(
                title: Text(notification.title),
                message: Text(notification.body),
                primaryButton: .default(Text("Ouvrir")) {
                    notificationRouter.openInAppNotification(notification)
                },
                secondaryButton: .cancel(Text("Plus tard")) {
                    notificationRouter.inAppNotification = nil
                }
            )
        }
    }

    private func applyNotificationRoute(_ route: NotificationRoute?) {
        guard let route else { return }

        tabRouter.selectedTab = route.targetTab

        if case .plantDetail(let plantId) = route {
            routedPlant = RoutedPlant(id: plantId)
        }
    }
}

private struct RoutedPlant: Identifiable {
    let id: String
}
