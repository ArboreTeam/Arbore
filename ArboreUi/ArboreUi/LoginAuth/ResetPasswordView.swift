import SwiftUI
import FirebaseAuth

struct ResetPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var successMessage = ""
    @State private var errorMessage = ""
    @FocusState private var focusedField: Bool

    var isEmailValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [ArboreDesign.Colors.background, ArboreDesign.Colors.background]),
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 25) {
                VStack(spacing: 8) {
                    Text("Arbore")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(ArboreDesign.Colors.textPrimary)

                    Text("Forgot password")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                }

                Text("Enter the email address associated with your account and we’ll send you a link to reset your password.")
                    .font(.footnote)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                // Email field
                TextField("", text: $email)
                    .focused($focusedField)
                    .placeholder(when: email.isEmpty) {
                        Text("Email").foregroundColor(ArboreDesign.Colors.placeholder)
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
                Button(action: {
                    Auth.auth().sendPasswordReset(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines)) { error in
                        if let error = error {
                            withAnimation {
                                errorMessage = error.localizedDescription
                                successMessage = ""
                            }
                        } else {
                            withAnimation {
                                successMessage = "✅ A reset link has been sent to your email."
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                errorMessage = ""
                            }

                            // ⏳ Ferme automatiquement après 2 secondes
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                dismiss()
                            }
                        }
                    }
                }) {
                    Text("Send")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isEmailValid ? ArboreDesign.Colors.primaryButton : ArboreDesign.Colors.primaryButton.opacity(0.4))
                        .cornerRadius(ArboreDesign.Radius.button)
                }
                .disabled(!isEmailValid)
                .padding(.horizontal, 30)
                .scaleEffect(isEmailValid ? 1.0 : 0.98)
                .animation(.easeInOut(duration: 0.2), value: isEmailValid)
                
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
}
