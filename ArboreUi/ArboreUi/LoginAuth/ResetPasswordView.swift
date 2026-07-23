import SwiftUI
import FirebaseAuth

struct ResetPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var successMessage = ""
    @State private var errorMessage = ""
    @State private var isSending = false
    @FocusState private var focusedField: Bool

    var isEmailValid: Bool {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && parts[1].contains(".")
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [ArboreDesign.Colors.background, ArboreDesign.Colors.background]),
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 25) {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(ArboreDesign.Colors.textPrimary)
                            .frame(width: 42, height: 42)
                            .background(ArboreDesign.Colors.card)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(L10n.t("AUTH_RESET_CLOSE"))
                }
                .padding(.horizontal, 24)

                VStack(spacing: 8) {
                    Text("Arbore")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(ArboreDesign.Colors.textPrimary)

                    Text(L10n.t("AUTH_RESET_TITLE"))
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                }

                Text(L10n.t("AUTH_RESET_DESCRIPTION"))
                    .font(.footnote)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                // Email field
                TextField("", text: $email)
                    .focused($focusedField)
                    .placeholder(when: email.isEmpty) {
                        Text(L10n.t("AUTH_EMAIL")).foregroundColor(ArboreDesign.Colors.placeholder)
                    }
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                    .padding()
                    .background(ArboreDesign.Colors.card)
                    .cornerRadius(ArboreDesign.Radius.medium)
                    .overlay(
                        RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium)
                            .stroke(focusedField ? ArboreDesign.Colors.primaryGreen : ArboreDesign.Colors.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 30)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .submitLabel(.done)

                // Submit button
                Button(action: sendResetEmail) {
                    HStack(spacing: 8) {
                        if isSending {
                            ProgressView().tint(.white)
                        }
                        Text(L10n.t("AUTH_SEND"))
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isEmailValid && !isSending ? ArboreDesign.Colors.primaryButton : ArboreDesign.Colors.primaryButton.opacity(0.4))
                    .cornerRadius(ArboreDesign.Radius.button)
                }
                .disabled(!isEmailValid || isSending)
                .padding(.horizontal, 30)
                .scaleEffect(isEmailValid && !isSending ? 1.0 : 0.98)
                .animation(.easeInOut(duration: 0.2), value: isEmailValid && !isSending)
                
                if !successMessage.isEmpty {
                    Text(successMessage)
                        .foregroundColor(ArboreDesign.Colors.success)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(ArboreDesign.Colors.danger)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                Spacer()

            }
            .padding(.top, 40)
        }
    }

    private func sendResetEmail() {
        guard isEmailValid else {
            errorMessage = L10n.t("AUTH_RESET_INVALID_EMAIL")
            return
        }

        isSending = true
        errorMessage = ""
        successMessage = ""

        Auth.auth().sendPasswordReset(
            withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines)
        ) { error in
            DispatchQueue.main.async {
                isSending = false
                if let error = error as NSError?,
                   AuthErrorCode(rawValue: error.code) == .networkError {
                    errorMessage = L10n.t("AUTH_RESET_NETWORK_ERROR")
                } else if error != nil {
                    errorMessage = L10n.t("AUTH_RESET_GENERIC_ERROR")
                } else {
                    // Deliberately generic: do not disclose whether an account
                    // exists for this address.
                    successMessage = L10n.t("AUTH_RESET_SUCCESS")
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
    }
}
