import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct YourApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("selectedLanguage") private var selectedLanguage = "en"
    @State private var showLaunchScreen = true
    @StateObject private var themeManager = ThemeManager()

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
                    ModernLoginView()
                }
                .environment(\.locale, Locale(identifier: selectedLanguage))
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.colorScheme)
            }
        }
    }
}
