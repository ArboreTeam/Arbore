import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("Settings")
                .font(.largeTitle)
                .bold()
                .padding(.top, 20)
                .padding(.horizontal)
            
            List {
                Section(header: Text("General")) {
                    NavigationLink(destination: LanguageView()) {
                        ProfileRow(icon: "globe", title: "Language")
                    }
                    NavigationLink(destination: AppearanceView()) {
                        ProfileRow(icon: "paintbrush", title: "Appearance")
                    }
                    NavigationLink(destination: NotificationsView()) {
                        ProfileRow(icon: "bell.fill", title: "Notifications")
                    }
                }
                
                Section(header: Text("Security & Privacy")) {
                    NavigationLink(destination: ChangePasswordView()) {
                        ProfileRow(icon: "lock.fill", title: "Change Password")
                    }
                    NavigationLink(destination: CloseAccountView()) {
                        ProfileRow(icon: "exclamationmark.triangle.fill", title: "Close Account")
                    }
                }
            }
        }
    }
}
