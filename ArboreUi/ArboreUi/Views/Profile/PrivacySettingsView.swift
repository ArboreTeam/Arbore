import SwiftUI

struct PrivacySettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var profilePublic: Bool = true
    @State private var showActivity: Bool = true
    @State private var shareData: Bool = false
    
    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            VStack {
                List {
                    Section(header: Text("Profile Visibility")) {
                        Toggle("Public Profile", isOn: $profilePublic)
                    }
                    .listRowBackground(themeManager.cardBackgroundColor)
                    
                    Section(header: Text("Activity")) {
                        Toggle("Show My Activity", isOn: $showActivity)
                    }
                    .listRowBackground(themeManager.cardBackgroundColor)
                    
                    Section(header: Text("Data Sharing")) {
                        Toggle("Share Data for Analytics", isOn: $shareData)
                    }
                    .listRowBackground(themeManager.cardBackgroundColor)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Privacy Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}