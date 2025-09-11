import SwiftUI
import FirebaseAuth

struct VerifyEmailView: View {
    var email: String
    var onResend: () -> Void
    var onBackToLogin: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var isVerified = false
    @State private var resendMessage = ""
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Color(hex: "#F1F5ED").ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                Image(systemName: "envelope.badge")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(Color(hex: "#263826"))

                Text("Verify your email")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(Color(hex: "#263826"))

                Text("We've sent a verification link to:\n\(email). Please verify your email to continue.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
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
                            .background(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(hex: "#263826"), lineWidth: 1)
                            )
                            .foregroundColor(Color(hex: "#263826"))
                    }

                    Button(action: checkVerificationStatus) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: "#263826").opacity(0.6))
                                .cornerRadius(10)
                        } else {
                            Text("I've Verified")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: "#263826"))
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
        .fullScreenCover(isPresented: $isVerified) {
            LoginView() // Ou ta vue principale
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
                    print("✅ Email verified")
                    isVerified = true
                } else {
                    resendMessage = "Email not verified yet."
                }
            }
        })
    }
}
