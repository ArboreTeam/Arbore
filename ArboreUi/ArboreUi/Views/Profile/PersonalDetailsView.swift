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
                
                // MARK: - Top Bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text(NSLocalizedString("PERSONAL_DETAILS_TITLE", comment: ""))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor)

                ScrollView {
                    VStack(spacing: 24) {

                        // Full Name
                        inputField(
                            title: NSLocalizedString("PERSONAL_DETAILS_FULLNAME_LABEL", comment: ""),
                            placeholder: NSLocalizedString("PERSONAL_DETAILS_FULLNAME_PLACEHOLDER", comment: ""),
                            text: $fullName
                        )
                        
                        // Phone Number
                        inputField(
                            title: NSLocalizedString("PERSONAL_DETAILS_PHONE_LABEL", comment: ""),
                            placeholder: NSLocalizedString("PERSONAL_DETAILS_PHONE_PLACEHOLDER", comment: ""),
                            text: $phoneNumber,
                            keyboardType: .phonePad
                        )
                        
                        // Email
                        inputField(
                            title: NSLocalizedString("PERSONAL_DETAILS_EMAIL_LABEL", comment: ""),
                            placeholder: NSLocalizedString("PERSONAL_DETAILS_EMAIL_PLACEHOLDER", comment: ""),
                            text: $email,
                            keyboardType: .emailAddress
                        )
                        
                        // Address
                        inputField(
                            title: NSLocalizedString("PERSONAL_DETAILS_ADDRESS_LABEL", comment: ""),
                            placeholder: NSLocalizedString("PERSONAL_DETAILS_ADDRESS_PLACEHOLDER", comment: ""),
                            text: $address
                        )
                        
                        Spacer()
                        
                        // Save Button
                        Button(action: { dismiss() }) {
                            Text(NSLocalizedString("PERSONAL_DETAILS_SAVE_BUTTON", comment: ""))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.green)
                                )
                                .shadow(color: Color.green.opacity(0.4), radius: 8, x: 0, y: 4)
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
    
    // MARK: - Input Field
    private func inputField(title: String, placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(themeManager.secondaryTextColor)
                .padding(.horizontal, 4)
            
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.gray.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .foregroundColor(themeManager.textColor)
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    PersonalDetailsView()
        .environmentObject(ThemeManager())
}
