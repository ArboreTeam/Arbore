import SwiftUI

final class TabRouter: ObservableObject {
    @Published var selectedTab: TabSelection = .home
}
