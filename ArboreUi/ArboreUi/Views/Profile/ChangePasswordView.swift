import SwiftUI

struct ChangePasswordView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""

    var body: some View {
        SettingsPage(title: NSLocalizedString("CHANGE_PASSWORD_TITLE", comment: "Change password title")) {
            SettingsSectionCard(
                title: NSLocalizedString("CHANGE_PASSWORD_CURRENT_TITLE", comment: ""),
                systemImage: "lock"
            ) {
                secureInputFieldContent(
                    placeholder: NSLocalizedString("CHANGE_PASSWORD_CURRENT_PLACEHOLDER", comment: ""),
                    text: $currentPassword
                )
            }

            SettingsSectionCard(
                title: NSLocalizedString("CHANGE_PASSWORD_NEW_SECTION_TITLE", comment: ""),
                systemImage: "key"
            ) {
                VStack(spacing: ArboreDesign.Spacing.md) {
                    secureInputFieldContent(
                        placeholder: NSLocalizedString("CHANGE_PASSWORD_NEW_PLACEHOLDER", comment: ""),
                        text: $newPassword
                    )

                    secureInputFieldContent(
                        placeholder: NSLocalizedString("CHANGE_PASSWORD_CONFIRM_PLACEHOLDER", comment: ""),
                        text: $confirmPassword
                    )
                }
            }

            Button(action: {
                // TODO: logique de changement de mot de passe
                dismiss()
            }) {
                Text(NSLocalizedString("CHANGE_PASSWORD_UPDATE_BUTTON", comment: ""))
            }
            .buttonStyle(.arborePrimary)
        }
        .interactiveDismissDisabled()
    }
    
    // MARK: - Secure Input Field

    private func secureInputFieldContent(placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .font(ArboreDesign.Typography.body)
            .foregroundColor(ArboreDesign.Colors.textPrimary)
            .tint(ArboreDesign.Colors.primaryGreen)
            .frame(height: 50)
            .padding(.horizontal, ArboreDesign.Spacing.md)
            .background(ArboreDesign.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                    .stroke(ArboreDesign.Colors.border, lineWidth: 1)
            )
    }
}

#Preview {
    ChangePasswordView()
        .environmentObject(ThemeManager())
}
