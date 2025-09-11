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
                gradient: Gradient(colors: [Color(hex: "#F1F5ED"), Color(hex: "#EAF1E7")]),
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 25) {
                VStack(spacing: 8) {
                    Text("Arbore")
                        .font(.system(size: 42, weight: .bold, design: .serif))
                        .foregroundColor(Color(hex: "#2D3E30"))

                    Text("Forgot password")
                        .font(.system(size: 20, design: .serif))
                        .foregroundColor(Color(hex: "#2D3E30").opacity(0.7))
                }

                Text("Enter the email address associated with your account and we’ll send you a link to reset your password.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                // Email field
                TextField("", text: $email)
                    .focused($focusedField)
                    .placeholder(when: email.isEmpty) {
                        Text("Email").foregroundColor(.gray)
                    }
                    .foregroundColor(.black)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField ? Color(hex: "#263826") : Color.gray.opacity(0.3), lineWidth: 1)
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
                        .background(isEmailValid ? Color(hex: "#263826") : Color(hex: "#263826").opacity(0.4))
                        .cornerRadius(10)
                }
                .disabled(!isEmailValid)
                .padding(.horizontal, 30)
                .scaleEffect(isEmailValid ? 1.0 : 0.98)
                .animation(.easeInOut(duration: 0.2), value: isEmailValid)
                
                if !successMessage.isEmpty {
                    Text(successMessage)
                        .foregroundColor(.green)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
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
