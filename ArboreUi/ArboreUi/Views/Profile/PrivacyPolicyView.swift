import SwiftUI

struct PrivacyPolicyView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Privacy Policy")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(themeManager.textColor)
                    
                    Text("Your privacy is important to us. This Privacy Policy explains how we collect, use, disclose, and safeguard your information.")
                        .foregroundColor(themeManager.secondaryTextColor)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Information We Collect")
                            .font(.headline)
                            .foregroundColor(themeManager.textColor)
                        Text("We collect information you provide directly, such as when you create an account.")
                            .foregroundColor(themeManager.secondaryTextColor)
                            .font(.caption)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("2. How We Use Your Information")
                            .font(.headline)
                            .foregroundColor(themeManager.textColor)
                        Text("We use your information to provide, maintain, and improve our services.")
                            .foregroundColor(themeManager.secondaryTextColor)
                            .font(.caption)
                    }
                    
                    Spacer()
                }
                .padding()
            }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}