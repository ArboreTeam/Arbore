import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Settings")
                .font(.largeTitle)
                .bold()
                .padding(.top, 20)
                .padding(.horizontal)
                .foregroundColor(themeManager.textColor)
            
            List {
                Section(header: Text("General")) {
                    NavigationLink(destination: LanguageView().environmentObject(themeManager)) {
                        ProfileRow(icon: "globe", title: "Language")
                    }
                    NavigationLink(destination: AppearanceView().environmentObject(themeManager)) {
                        ProfileRow(icon: "paintbrush", title: "Appearance")
                    }
                    NavigationLink(destination: NotificationsView().environmentObject(themeManager)) {
                        ProfileRow(icon: "bell.fill", title: "Notifications")
                    }
                }
                
                Section(header: Text("Security & Privacy")) {
                    NavigationLink(destination: ChangePasswordView().environmentObject(themeManager)) {
                        ProfileRow(icon: "lock.fill", title: "Change Password")
                    }
                    NavigationLink(destination: CloseAccountView().environmentObject(themeManager)) {
                        ProfileRow(icon: "exclamationmark.triangle.fill", title: "Close Account")
                    }
                }
            }
            .background(themeManager.backgroundColor)
        }
        .background(themeManager.backgroundColor)
    }
}
