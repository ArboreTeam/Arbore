import SwiftUI

final class TabRouter: ObservableObject {
    @Published var selectedTab: TabSelection = .home
    /// Jardin à ouvrir lors du prochain affichage de l'onglet Jardin.
    @Published var targetGardenId: String?
}
