import SwiftUI
import FirebaseAuth

struct VerifyEmailView: View {
    var email: String
    var onResend: () -> Void
    var onBackToLogin: () -> Void

    @AppStorage("isLoggedIn") var isLoggedIn = false
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @State private var resendMessage = ""
    @State private var isResendError = false
    @State private var resendCooldown = 0
    @State private var isLoading = false
    private let resendCooldownSeconds = 60

    var body: some View {
        ZStack {
            ArboreDesign.Colors.background.ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                Image(systemName: "envelope.badge")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(ArboreDesign.Colors.primaryGreen)

                Text("Verify your email")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)

                Text("We've sent a verification link to:\n\(email). Please verify your email to continue.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .padding(.horizontal)

                if !resendMessage.isEmpty {
                    Text(resendMessage)
                        .font(.footnote)
                        .foregroundColor(isResendError ? ArboreDesign.Colors.danger : ArboreDesign.Colors.success)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    Button(action: resendVerificationEmail) {
                        Text(resendCooldown > 0 ? "Resend in \(resendCooldown)s" : "Resend Email")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(ArboreDesign.Colors.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: ArboreDesign.Radius.button)
                                    .stroke(resendCooldown > 0 ? ArboreDesign.Colors.border : ArboreDesign.Colors.primaryGreen, lineWidth: 1)
                            )
                            .foregroundColor(resendCooldown > 0 ? ArboreDesign.Colors.textSecondary : ArboreDesign.Colors.primaryGreen)
                    }
                    .disabled(resendCooldown > 0)

                    Button(action: checkVerificationStatus) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(ArboreDesign.Colors.primaryButton.opacity(0.6))
                                .cornerRadius(ArboreDesign.Radius.button)
                        } else {
                            Text("I've Verified")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(ArboreDesign.Colors.primaryButton)
                                .foregroundColor(.white)
                                .cornerRadius(ArboreDesign.Radius.button)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
        }
    }

    func resendVerificationEmail() {
        guard let user = Auth.auth().currentUser else {
            isResendError = true
            resendMessage = "Please sign in again to resend the verification email."
            return
        }

        startResendCooldown()
        user.sendEmailVerification { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error resending email: \(error.localizedDescription)")
                    isResendError = true
                    resendMessage = resendErrorMessage(for: error)
                } else {
                    print("✅ Verification email resent.")
                    isResendError = false
                    resendMessage = "A new link has been sent to your inbox."
                }
            }
        }
    }

    func checkVerificationStatus() {
        guard let user = Auth.auth().currentUser else {
            isResendError = true
            resendMessage = "Your session expired. Please log in again."
            onBackToLogin()
            return
        }

        isLoading = true
        user.reload(completion: { error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    print("❌ Error reloading user: \(error.localizedDescription)")
                    isResendError = true
                    resendMessage = "Unable to check verification. Try again."
                } else if Auth.auth().currentUser?.isEmailVerified == true {
                    print("✅ Email verified — logging in")
                    isLoggedIn = true
                    onBackToLogin()
                } else {
                    isResendError = false
                    resendMessage = "Email not verified yet."
                }
            }
        })
    }

    private func startResendCooldown() {
        resendCooldown = resendCooldownSeconds
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            DispatchQueue.main.async {
                if resendCooldown > 0 {
                    resendCooldown -= 1
                }

                if resendCooldown == 0 {
                    timer.invalidate()
                }
            }
        }
    }

    private func resendErrorMessage(for error: Error) -> String {
        if AuthErrorCode(rawValue: (error as NSError).code) == .tooManyRequests {
            return "Too many requests from this device. Please wait before trying again."
        }

        return "Failed to resend. Try again."
    }
}
