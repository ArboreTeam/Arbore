import SwiftUI
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
                .environment(\.themeManager, themeManager)
                .preferredColorScheme(themeManager.colorScheme)
                .environment(\.dynamicTypeSize, themeManager.mappedDynamicTypeSize)
                .accentColor(themeManager.accentColor)
                .environment(roomCaptureController)
            }
        }
    }
}
