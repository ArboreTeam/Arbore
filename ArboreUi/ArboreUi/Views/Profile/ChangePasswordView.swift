import SwiftUI
import FirebaseAuth

enum PasswordPolicy {
    static let minimumLength = 8

    static func validationError(
        currentPassword: String,
        newPassword: String,
        confirmation: String
    ) -> String? {
        if currentPassword.isEmpty || newPassword.isEmpty || confirmation.isEmpty {
            return "CHANGE_PASSWORD_ERROR_REQUIRED"
        }
        if newPassword.count < minimumLength {
            return "CHANGE_PASSWORD_ERROR_LENGTH"
        }
        if newPassword != confirmation {
            return "CHANGE_PASSWORD_ERROR_MISMATCH"
        }
        if newPassword == currentPassword {
            return "CHANGE_PASSWORD_ERROR_SAME"
        }
        return nil
    }
}

struct ChangePasswordView: View {
    @EnvironmentObject var themeManager: ThemeManager

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isUpdating = false
    @State private var successMessage: String?
    @State private var errorMessage: String?

    private var isPasswordAccount: Bool {
        Auth.auth().currentUser?.providerData.contains(where: { $0.providerID == "password" }) == true
    }

    private var canSubmit: Bool {
        isPasswordAccount
            && !isUpdating
            && PasswordPolicy.validationError(
                currentPassword: currentPassword,
                newPassword: newPassword,
                confirmation: confirmPassword
            ) == nil
    }

    var body: some View {
        SettingsPage(title: L10n.t("CHANGE_PASSWORD_TITLE")) {
            if isPasswordAccount {
                passwordForm
            } else {
                SettingsSectionCard(
                    title: L10n.t("CHANGE_PASSWORD_EXTERNAL_TITLE"),
                    systemImage: "person.badge.key"
                ) {
                    Text(L10n.t("CHANGE_PASSWORD_EXTERNAL_MESSAGE"))
                        .font(ArboreDesign.Typography.body)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var passwordForm: some View {
        Group {
            SettingsSectionCard(
                title: L10n.t("CHANGE_PASSWORD_CURRENT_TITLE"),
                systemImage: "lock"
            ) {
                secureInputFieldContent(
                    placeholder: L10n.t("CHANGE_PASSWORD_CURRENT_PLACEHOLDER"),
                    text: $currentPassword,
                    contentType: .password
                )
            }

            SettingsSectionCard(
                title: L10n.t("CHANGE_PASSWORD_NEW_SECTION_TITLE"),
                systemImage: "key"
            ) {
                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                    secureInputFieldContent(
                        placeholder: L10n.t("CHANGE_PASSWORD_NEW_PLACEHOLDER"),
                        text: $newPassword,
                        contentType: .newPassword
                    )

                    secureInputFieldContent(
                        placeholder: L10n.t("CHANGE_PASSWORD_CONFIRM_PLACEHOLDER"),
                        text: $confirmPassword,
                        contentType: .newPassword
                    )

                    Text(L10n.f("CHANGE_PASSWORD_REQUIREMENT", PasswordPolicy.minimumLength))
                        .font(ArboreDesign.Typography.caption)
                        .foregroundColor(ArboreDesign.Colors.textMuted)
                }
            }

            if let successMessage {
                SettingsInfoRow(
                    systemImage: "checkmark.circle.fill",
                    title: successMessage,
                    tint: ArboreDesign.Colors.success
                )
            }

            if let errorMessage {
                SettingsInfoRow(
                    systemImage: "exclamationmark.triangle.fill",
                    title: errorMessage,
                    tint: ArboreDesign.Colors.danger
                )
            }

            Button(action: updatePassword) {
                HStack(spacing: ArboreDesign.Spacing.xs) {
                    if isUpdating {
                        ProgressView().tint(.white)
                    }
                    Text(L10n.t("CHANGE_PASSWORD_UPDATE_BUTTON"))
                }
            }
            .buttonStyle(.arborePrimary)
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.55)
        }
    }

    private func secureInputFieldContent(
        placeholder: String,
        text: Binding<String>,
        contentType: UITextContentType
    ) -> some View {
        SecureField(placeholder, text: text)
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
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

    private func updatePassword() {
        errorMessage = nil
        successMessage = nil

        if let validationKey = PasswordPolicy.validationError(
            currentPassword: currentPassword,
            newPassword: newPassword,
            confirmation: confirmPassword
        ) {
            errorMessage = L10n.t(validationKey)
            return
        }

        guard let user = Auth.auth().currentUser, let email = user.email else {
            errorMessage = L10n.t("CHANGE_PASSWORD_ERROR_SESSION")
            return
        }

        isUpdating = true
        let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
        user.reauthenticate(with: credential) { _, reauthError in
            if let reauthError {
                finishWithError(reauthError, currentPasswordStep: true)
                return
            }

            user.updatePassword(to: newPassword) { updateError in
                if let updateError {
                    finishWithError(updateError, currentPasswordStep: false)
                    return
                }

                DispatchQueue.main.async {
                    isUpdating = false
                    currentPassword = ""
                    newPassword = ""
                    confirmPassword = ""
                    successMessage = L10n.t("CHANGE_PASSWORD_SUCCESS")
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
    }

    private func finishWithError(_ error: Error, currentPasswordStep: Bool) {
        let nsError = error as NSError
        let key: String
        switch AuthErrorCode(rawValue: nsError.code) {
        case .wrongPassword, .invalidCredential:
            key = "CHANGE_PASSWORD_ERROR_CURRENT"
        case .weakPassword:
            key = "CHANGE_PASSWORD_ERROR_WEAK"
        case .networkError:
            key = "CHANGE_PASSWORD_ERROR_NETWORK"
        case .requiresRecentLogin:
            key = "CHANGE_PASSWORD_ERROR_RECENT_LOGIN"
        default:
            key = currentPasswordStep
                ? "CHANGE_PASSWORD_ERROR_CURRENT"
                : "CHANGE_PASSWORD_ERROR_GENERIC"
        }

        DispatchQueue.main.async {
            isUpdating = false
            errorMessage = L10n.t(key)
        }
    }
}

#Preview {
    ChangePasswordView()
        .environmentObject(ThemeManager())
}
