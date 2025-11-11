import FirebaseAuth
import SwiftUI
import Firebase

struct SignUpView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("isLoggedIn") var isLoggedIn = false

    @State private var name = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var signUpError: String? = nil
    @State private var emailVerificationSent = false
    @State private var verificationMessage = ""
    @State private var showVerificationScreen = false
    @State private var registeredEmail: String = ""
    @StateObject private var authViewModel = AuthenticationView()
    @FocusState private var focusedField: Field?

    enum Field {
        case name, email, password
    }

    var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(hex: "#F1F5ED"), Color(hex: "#EAF1E7")]),
                startPoint: .top,
                endPoint: .bottom
            ).ignoresSafeArea()
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }

            ScrollView {
                VStack(spacing: 25) {
                    VStack(spacing: 8) {
                        Text("Arbore")
                            .font(.system(size: 42, weight: .bold, design: .serif))
                            .foregroundColor(Color(hex: "#2D3E30"))

                        Text("Grow with harmony")
                            .font(.system(size: 20, design: .serif))
                            .foregroundColor(Color(hex: "#2D3E30").opacity(0.7))
                    }

                    VStack(spacing: 14) {
                        TextField("", text: $firstName)
                            .focused($focusedField, equals: .name)
                            .placeholder(when: firstName.isEmpty) {
                                Text("First Name").foregroundColor(.gray)
                            }
                            .foregroundColor(.black)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                            .tint(Color(hex: "#263826"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(focusedField == .name ? Color(hex: "#263826") : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .submitLabel(.next)
                            .onSubmit { focusedField = .email }

                        TextField("", text: $lastName)
                            .focused($focusedField, equals: .name)
                            .placeholder(when: lastName.isEmpty) {
                                Text("Last Name").foregroundColor(.gray)
                            }
                            .foregroundColor(.black)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                            .tint(Color(hex: "#263826"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(focusedField == .name ? Color(hex: "#263826") : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .submitLabel(.next)
                            .onSubmit { focusedField = .email }

                        TextField("", text: $email)
                            .focused($focusedField, equals: .email)
                            .placeholder(when: email.isEmpty) {
                                Text("Email").foregroundColor(.gray)
                            }
                            .foregroundColor(.black)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                            .tint(Color(hex: "#263826"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(focusedField == .email ? Color(hex: "#263826") : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }

                        ZStack(alignment: .trailing) {
                            Group {
                                if isPasswordVisible {
                                    TextField("", text: $password)
                                        .focused($focusedField, equals: .password)
                                        .placeholder(when: password.isEmpty) {
                                            Text("Password").foregroundColor(.gray)
                                        }
                                        .submitLabel(.go)
                                } else {
                                    SecureField("", text: $password)
                                        .focused($focusedField, equals: .password)
                                        .placeholder(when: password.isEmpty) {
                                            Text("Password").foregroundColor(.gray)
                                        }
                                        .submitLabel(.go)
                                }
                            }
                            .foregroundColor(.black)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                            .tint(Color(hex: "#263826"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(focusedField == .password ? Color(hex: "#263826") : Color.gray.opacity(0.3), lineWidth: 1)
                            )

                            Button(action: {
                                isPasswordVisible.toggle()
                            }) {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                    .foregroundColor(.gray)
                                    .padding(.trailing, 12)
                            }
                        }
                    }
                    .padding(.horizontal, 30)

                    Button(action: registerUser) {
                        Text("Sign Up")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isFormValid ? Color(hex: "#263826") : Color(hex: "#263826").opacity(0.4))
                            .cornerRadius(10)
                    }
                    .disabled(!isFormValid)
                    .padding(.horizontal, 30)
                    .scaleEffect(isFormValid ? 1.0 : 0.98)
                    .animation(.easeInOut(duration: 0.2), value: isFormValid)
                    
                    if !verificationMessage.isEmpty {
                        Text(verificationMessage)
                            .foregroundColor(.green)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    
                    if let errorMessage = signUpError {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                            .transition(.opacity)
                    }

                    HStack(spacing: 0) {
                        Text("By signing up, you agree to our ")
                            .foregroundColor(.gray)
                        NavigationLink(destination: TermsOfServiceView()) {
                            Text("Terms of Service.")
                                .foregroundColor(Color(hex: "#263826"))
                                .underline()
                        }
                    }
                    .font(.footnote)

                    HStack {
                        Rectangle().fill(Color.gray.opacity(0.4)).frame(height: 1)
                        Text("or")
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                        Rectangle().fill(Color.gray.opacity(0.4)).frame(height: 1)
                    }
                    .padding(.horizontal, 30)

                    VStack(spacing: 12) {
                        Button(action: {}) {
                            HStack {
                                Image(systemName: "apple.logo")
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                Text("Continue with Apple")
                                    .fontWeight(.medium)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal, 30)

                        Button(action: {
                            authViewModel.signInWithGoogle()
                        }) {
                            HStack {
                                Image("google")
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                Text("Continue with Google")
                                    .fontWeight(.medium)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2)))
                            .cornerRadius(10)
                        }
                        .padding(.horizontal, 30)
                    }

                    HStack {
                        Text("Already have an account?")
                            .foregroundColor(.gray)

                        Button(action: {
                            dismiss()
                        }) {
                            Text("Log in")
                                .fontWeight(.semibold)
                                .foregroundColor(Color(hex: "#263826"))
                        }
                    }
                    .font(.footnote)
                    .padding(.top, 8)

                    Spacer(minLength: 20)
                }
                .padding(.top, 40)
                .navigationDestination(isPresented: $showVerificationScreen) {
                    VerifyEmailView(
                        email: registeredEmail,
                        onResend: {
                            Auth.auth().currentUser?.sendEmailVerification(completion: { error in
                                if let error = error {
                                    self.signUpError = "Resend failed: \(error.localizedDescription)"
                                } else {
                                    self.signUpError = nil
                                }
                            })
                        },
                        onBackToLogin: {
                            dismiss()
                        }
                    )
                }
            }
        }
    }

    func registerUser() {
        signUpError = nil // on reset l’erreur précédente

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.registeredEmail = trimmedEmail
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = "\(trimmedFirst) \(trimmedLast)"


        Auth.auth().createUser(withEmail: trimmedEmail, password: trimmedPassword) { result, error in
            if let error = error {
                self.signUpError = error.localizedDescription
                return
            }

            guard let user = result?.user else {
                self.signUpError = "Unexpected error."
                return
            }

            // Envoyer l'email de vérification
            user.sendEmailVerification { error in
                if let error = error {
                    self.signUpError = "Failed to send verification email: \(error.localizedDescription)"
                } else {
                    self.emailVerificationSent = true
                    self.showVerificationScreen = true
                }
            }

            // Enregistre l'utilisateur dans ta DB uniquement si tu veux malgré tout
            saveUserToBackend(uid: user.uid, email: user.email ?? "", name: fullName, createdAt: Date())

            // Ne connecte pas l'utilisateur tout de suite
            self.isLoggedIn = false
        }
    }
}
