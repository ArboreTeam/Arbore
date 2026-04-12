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
    @State private var isLoading = false

    var body: some View {
        ZStack {
            themeManager.backgroundColor.ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                Image(systemName: "envelope.badge")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(themeManager.brandPrimary)

                Text("Verify your email")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(themeManager.textColor)

                Text("We've sent a verification link to:\n\(email). Please verify your email to continue.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal)

                if !resendMessage.isEmpty {
                    Text(resendMessage)
                        .font(.footnote)
                        .foregroundColor(.green)
                }

                VStack(spacing: 12) {
                    Button(action: resendVerificationEmail) {
                        Text("Resend Email")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(themeManager.cardBackgroundColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(themeManager.brandPrimary, lineWidth: 1)
                            )
                            .foregroundColor(themeManager.brandPrimary)
                    }

                    Button(action: checkVerificationStatus) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(themeManager.brandPrimary.opacity(0.6))
                                .cornerRadius(10)
                        } else {
                            Text("I've Verified")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(themeManager.brandPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
        }
        .onAppear {
            sendInitialEmail()
        }
    }

    func sendInitialEmail() {
        if let user = Auth.auth().currentUser, !user.isEmailVerified {
            user.sendEmailVerification { error in
                if let error = error {
                    print("❌ Error sending email: \(error.localizedDescription)")
                } else {
                    print("✅ Initial email sent.")
                }
            }
        }
    }

    func resendVerificationEmail() {
        if let user = Auth.auth().currentUser {
            user.sendEmailVerification { error in
                if let error = error {
                    print("❌ Error resending email: \(error.localizedDescription)")
                    resendMessage = "Failed to resend. Try again."
                } else {
                    print("✅ Verification email resent.")
                    resendMessage = "A new link has been sent to your inbox."
                }
            }
        }
    }

    func checkVerificationStatus() {
        isLoading = true
        Auth.auth().currentUser?.reload(completion: { error in
            isLoading = false
            if let error = error {
                print("❌ Error reloading user: \(error.localizedDescription)")
            } else {
                if Auth.auth().currentUser?.isEmailVerified == true {
                    print("✅ Email verified — logging in")
                    isLoggedIn = true
                } else {
                    resendMessage = "Email not verified yet."
                }
            }
        })
    }
}
