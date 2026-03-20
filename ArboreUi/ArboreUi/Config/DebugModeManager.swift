import SwiftUI

#if DEBUG

@MainActor
final class DebugModeManager: ObservableObject {
    @Published var isDebugModeActive = false

    static let shared = DebugModeManager()

    func toggleDebugMode() {
        isDebugModeActive.toggle()
        print("🔧 Debug mode: \(isDebugModeActive)")
    }

    func activate() {
        isDebugModeActive = true
        print("🔧 Debug mode activated")
    }
}

#endif
