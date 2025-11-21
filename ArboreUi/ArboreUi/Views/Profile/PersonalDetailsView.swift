import SwiftUI

struct PersonalDetailsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var fullName: String = "Hugo Michel"
    @State private var phoneNumber: String = ""
    @State private var email: String = ""
    @State private var address: String = ""
    
    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top bar - Same as UpgradePlanView
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text("Personal Details")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor)
                
                // ScrollView content
                ScrollView {
                    VStack(spacing: 16) {
                        // Full Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FULL NAME")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .padding(.horizontal, 16)
                            
                            TextField("Full Name", text: $fullName)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                                .padding(.horizontal, 16)
                                .foregroundColor(themeManager.textColor)
                        }
                        
                        // Phone Number
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PHONE NUMBER")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .padding(.horizontal, 16)
                            
                            TextField("Phone Number", text: $phoneNumber)
                                .keyboardType(.phonePad)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                                .padding(.horizontal, 16)
                                .foregroundColor(themeManager.textColor)
                        }
                        
                        // Email
                        VStack(alignment: .leading, spacing: 8) {
                            Text("EMAIL")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .padding(.horizontal, 16)
                            
                            TextField("Email", text: $email)
                                .keyboardType(.emailAddress)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                                .padding(.horizontal, 16)
                                .foregroundColor(themeManager.textColor)
                        }
                        
                        // Address
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ADDRESS")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .padding(.horizontal, 16)
                            
                            TextField("Address", text: $address)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                                .padding(.horizontal, 16)
                                .foregroundColor(themeManager.textColor)
                        }
                        
                        Spacer()
                        
                        // Save Button
                        Button(action: { dismiss() }) {
                            Text("Save Changes")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.green)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .padding(.vertical, 20)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

#Preview {
    PersonalDetailsView()
        .environmentObject(ThemeManager())
}