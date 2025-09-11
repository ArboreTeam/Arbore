import SwiftUI

struct MainView: View {
    @State private var selectedTab: TabSelection = .home

    var body: some View {
        VStack(spacing: 0) {
            // Vue selon onglet
            Group {
                switch selectedTab {
                case .home:
                    HomeView()
                case .explore:
                    CatalogueView()
                case .garden:
                    MyGardenView()
                case .profile:
                    ProfileView()
                }
            }

            Divider()

            // Barre fixe façon Revolut
            HStack {
                ForEach(TabSelection.allCases, id: \.self) { tab in
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: selectedTab == tab ? tab.iconFill : tab.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .scaleEffect(selectedTab == tab ? 1.15 : 1.0)
                                .opacity(selectedTab == tab ? 1.0 : 0.6)
                                .foregroundColor(selectedTab == tab ? Color(hex: "#263826") : .gray)

                            Text(tab.label)
                                .font(.footnote)
                                .foregroundColor(selectedTab == tab ? Color(hex: "#263826") : .gray)
                                .opacity(selectedTab == tab ? 1.0 : 0.6)
                        }
                    }
                    Spacer()
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 12)
            .background(Color(hex: "#F1F5ED").ignoresSafeArea(edges: .bottom))
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
