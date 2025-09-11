import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct YourApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("selectedLanguage") private var selectedLanguage = "en"
    @State private var showLaunchScreen = true

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
            }
        }
    }
}
