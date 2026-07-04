import SwiftUI
import SwiftData
import FirebaseCore
import GoogleSignIn

@main
struct YourApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @State private var showLaunchScreen = true
    @StateObject private var themeManager = ThemeManager()
    private var roomCaptureController = RoomCaptureController()

    var body: some Scene {
        WindowGroup {
            if showLaunchScreen {
                LaunchScreenView()
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showLaunchScreen = false
                            }
                        }
                    }
            } else {
                NavigationView {
                    LoginView()
                }
                .environment(\.locale, Locale(identifier: selectedLanguage))
                .environmentObject(themeManager)
                .environmentObject(RemoteConfigService.shared)
                .environment(\.themeManager, themeManager)
                .preferredColorScheme(themeManager.colorScheme)
                .environment(\.dynamicTypeSize, themeManager.mappedDynamicTypeSize)
                .accentColor(themeManager.accentColor)
                .environment(roomCaptureController)
                // Charge la config distante (wizard + règles de soin, #236) au
                // lancement. Échec silencieux → repli sur le cache / les défauts.
                .task { await RemoteConfigService.shared.load() }
                .modelContainer(for: [ChatConversation.self, ChatMessage.self])
            }
        }
    }
}
