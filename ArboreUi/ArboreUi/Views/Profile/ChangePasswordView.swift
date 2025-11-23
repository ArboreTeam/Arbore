import SwiftUI

struct ChangePasswordView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""

    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text(NSLocalizedString("CHANGE_PASSWORD_TITLE", comment: "Change password title"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor)

                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // Current Password
                        secureInputField(
                            title: NSLocalizedString("CHANGE_PASSWORD_CURRENT_TITLE", comment: ""),
                            placeholder: NSLocalizedString("CHANGE_PASSWORD_CURRENT_PLACEHOLDER", comment: ""),
                            text: $currentPassword
                        )

                        // New Passwords
                        VStack(alignment: .leading, spacing: 16) {
                            Text(NSLocalizedString("CHANGE_PASSWORD_NEW_SECTION_TITLE", comment: ""))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .padding(.horizontal, 4)
                            
                            secureInputFieldContent(
                                placeholder: NSLocalizedString("CHANGE_PASSWORD_NEW_PLACEHOLDER", comment: ""),
                                text: $newPassword
                            )
                            secureInputFieldContent(
                                placeholder: NSLocalizedString("CHANGE_PASSWORD_CONFIRM_PLACEHOLDER", comment: ""),
                                text: $confirmPassword
                            )
                        }
                        .padding(.horizontal, 16)

                        Spacer(minLength: 8)

                        // Update Button
                        Button(action: {
                            // TODO: logique de changement de mot de passe
                            dismiss()
                        }) {
                            Text(NSLocalizedString("CHANGE_PASSWORD_UPDATE_BUTTON", comment: ""))
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
                        .padding(.bottom, 24)
                    }
                    .padding(.top, 20)
                }
            }
        }
        .interactiveDismissDisabled()
    }
    
    // MARK: - Secure Input Field
    
    private func secureInputField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(themeManager.secondaryTextColor)
                .padding(.horizontal, 4)
            
            secureInputFieldContent(placeholder: placeholder, text: text)
        }
        .padding(.horizontal, 16)
    }
    
    private func secureInputFieldContent(placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
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
}

#Preview {
    ChangePasswordView()
        .environmentObject(ThemeManager())
}
