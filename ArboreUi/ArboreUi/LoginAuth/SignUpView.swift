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
    @StateObject private var appleAuth = AppleAuthService()
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
                gradient: Gradient(colors: [ArboreDesign.Colors.background, ArboreDesign.Colors.background]),
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
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(ArboreDesign.Colors.textPrimary)

                        Text(L10n.t("AUTH_TAGLINE"))
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                    }

                    VStack(spacing: 14) {
                        TextField("", text: $firstName)
                            .focused($focusedField, equals: .name)
                            .placeholder(when: firstName.isEmpty) {
                                Text(L10n.t("AUTH_FIRST_NAME")).foregroundColor(ArboreDesign.Colors.placeholder)
                            }
                            .foregroundColor(ArboreDesign.Colors.textPrimary)
                            .padding()
                            .background(ArboreDesign.Colors.card)
                            .cornerRadius(ArboreDesign.Radius.medium)
                            .tint(ArboreDesign.Colors.primaryGreen)
                            .overlay(
                                RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium)
                                    .stroke(focusedField == .name ? ArboreDesign.Colors.primaryGreen : ArboreDesign.Colors.border, lineWidth: 1)
                            )
                            .submitLabel(.next)
                            .onSubmit { focusedField = .email }

                        TextField("", text: $lastName)
                            .focused($focusedField, equals: .name)
                            .placeholder(when: lastName.isEmpty) {
                                Text(L10n.t("AUTH_LAST_NAME")).foregroundColor(ArboreDesign.Colors.placeholder)
                            }
                            .foregroundColor(ArboreDesign.Colors.textPrimary)
                            .padding()
                            .background(ArboreDesign.Colors.card)
                            .cornerRadius(ArboreDesign.Radius.medium)
                            .tint(ArboreDesign.Colors.primaryGreen)
                            .overlay(
                                RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium)
                                    .stroke(focusedField == .name ? ArboreDesign.Colors.primaryGreen : ArboreDesign.Colors.border, lineWidth: 1)
                            )
                            .submitLabel(.next)
                            .onSubmit { focusedField = .email }

                        TextField("", text: $email)
                            .focused($focusedField, equals: .email)
                            .placeholder(when: email.isEmpty) {
                                Text(L10n.t("AUTH_EMAIL")).foregroundColor(ArboreDesign.Colors.placeholder)
                            }
                            .foregroundColor(ArboreDesign.Colors.textPrimary)
                            .padding()
                            .background(ArboreDesign.Colors.card)
                            .cornerRadius(ArboreDesign.Radius.medium)
                            .tint(ArboreDesign.Colors.primaryGreen)
                            .overlay(
                                RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium)
                                    .stroke(focusedField == .email ? ArboreDesign.Colors.primaryGreen : ArboreDesign.Colors.border, lineWidth: 1)
                            )
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }

                        ZStack(alignment: .trailing) {
                            Group {
                                if isPasswordVisible {
                                    TextField("", text: $password)
                                        .focused($focusedField, equals: .password)
                                        .placeholder(when: password.isEmpty) {
                                            Text(L10n.t("AUTH_PASSWORD")).foregroundColor(ArboreDesign.Colors.placeholder)
                                        }
                                        .submitLabel(.go)
                                } else {
                                    SecureField("", text: $password)
                                        .focused($focusedField, equals: .password)
                                        .placeholder(when: password.isEmpty) {
                                            Text(L10n.t("AUTH_PASSWORD")).foregroundColor(ArboreDesign.Colors.placeholder)
                                        }
                                        .submitLabel(.go)
                                }
                            }
                            .foregroundColor(ArboreDesign.Colors.textPrimary)
                            .padding()
                            .background(ArboreDesign.Colors.card)
                            .cornerRadius(ArboreDesign.Radius.medium)
                            .tint(ArboreDesign.Colors.primaryGreen)
                            .overlay(
                                RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium)
                                    .stroke(focusedField == .password ? ArboreDesign.Colors.primaryGreen : ArboreDesign.Colors.border, lineWidth: 1)
                            )

                            Button(action: {
                                isPasswordVisible.toggle()
                            }) {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                                    .padding(.trailing, 12)
                            }
                        }
                    }
                    .padding(.horizontal, 30)

                    Button(action: registerUser) {
                        Text(L10n.t("AUTH_SIGN_UP"))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isFormValid ? ArboreDesign.Colors.primaryButton : ArboreDesign.Colors.primaryButton.opacity(0.4))
                            .cornerRadius(ArboreDesign.Radius.button)
                    }
                    .disabled(!isFormValid)
                    .padding(.horizontal, 30)
                    .scaleEffect(isFormValid ? 1.0 : 0.98)
                    .animation(.easeInOut(duration: 0.2), value: isFormValid)
                    
                    if !verificationMessage.isEmpty {
                        Text(verificationMessage)
                            .foregroundColor(ArboreDesign.Colors.success)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    
                    if let errorMessage = signUpError {
                        Text(errorMessage)
                            .foregroundColor(ArboreDesign.Colors.danger)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                            .transition(.opacity)
                    }

                    VStack(spacing: 4) {
                        Text(NSLocalizedString("AUTH_AGREE_SIGNUP", comment: ""))
                            .foregroundColor(ArboreDesign.Colors.textSecondary)

                        HStack(spacing: 4) {
                            NavigationLink(destination: TermsConditionsView()) {
                                Text(NSLocalizedString("AUTH_AGREE_TERMS", comment: ""))
                                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
                                    .underline()
                            }

                            Text(NSLocalizedString("AUTH_AGREE_AND", comment: ""))
                                .foregroundColor(ArboreDesign.Colors.textSecondary)

                            NavigationLink(destination: PrivacyPolicyView()) {
                                Text(NSLocalizedString("AUTH_AGREE_PRIVACY", comment: ""))
                                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
                                    .underline()
                            }
                        }
                    }
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 30)

                    HStack {
                        Rectangle().fill(ArboreDesign.Colors.border).frame(height: 1)
                        Text(L10n.t("AUTH_OR"))
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                            .padding(.horizontal)
                        Rectangle().fill(ArboreDesign.Colors.border).frame(height: 1)
                    }
                    .padding(.horizontal, 30)

                    VStack(spacing: 12) {
                        // Bouton SIWA natif (conforme HIG) — cf. AppleSignInButton.
                        AppleSignInButton(appleAuth: appleAuth)
                            .padding(.horizontal, 30)

                        Button(action: {
                            authViewModel.signInWithGoogle()
                        }) {
                            HStack {
                                Image("google")
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                Text(L10n.t("AUTH_CONTINUE_GOOGLE"))
                                    .fontWeight(.medium)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .foregroundColor(ArboreDesign.Colors.textPrimary)
                            .background(ArboreDesign.Colors.card)
                            .overlay(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button).stroke(ArboreDesign.Colors.border))
                            .cornerRadius(ArboreDesign.Radius.button)
                        }
                        .padding(.horizontal, 30)
                    }

                    HStack {
                        Text(L10n.t("AUTH_HAVE_ACCOUNT"))
                            .foregroundColor(ArboreDesign.Colors.textSecondary)

                        Button(action: {
                            dismiss()
                        }) {
                            Text(L10n.t("AUTH_LOGIN"))
                                .fontWeight(.semibold)
                                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                        }
                    }
                    .font(.footnote)
                    .padding(.top, 8)

                    // Accès invité (#391), en bas de l'inscription comme sur
                    // l'écran de connexion.
                    ContinueAsGuestButton {
                        isLoggedIn = true
                        dismiss()
                    }
                    .padding(.top, 4)

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
                if AuthErrorCode(rawValue: (error as NSError).code) == .emailAlreadyInUse {
                    self.resendVerificationForExistingAccount(email: trimmedEmail, password: trimmedPassword)
                } else {
                    DispatchQueue.main.async {
                        self.signUpError = error.localizedDescription
                    }
                }
                return
            }

            guard let user = result?.user else {
                DispatchQueue.main.async {
                    self.signUpError = L10n.t("AUTH_UNEXPECTED_ERROR")
                }
                return
            }

            // 1) POST /users (Mongo) AVANT l'email de vérif — si ça échoue on
            // supprime le compte Firebase pour que l'utilisateur puisse
            // recommencer proprement (sinon: orphan Firebase user, cf #137).
            Task {
                do {
                    try await saveUserToBackendThrowing(
                        uid: user.uid,
                        email: user.email ?? "",
                        name: fullName,
                        createdAt: Date()
                    )

                    // 2) Consentements RGPD (best-effort, on n'annule pas si ça loupe)
                    recordInitialConsents(uid: user.uid)

                    // 3) Envoyer l'email de vérification (best-effort aussi —
                    // l'utilisateur peut le renvoyer depuis l'écran de vérif)
                    user.sendEmailVerification { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                self.signUpError = self.verificationEmailErrorMessage(for: error)
                            } else {
                                self.emailVerificationSent = true
                            }
                            self.showVerificationScreen = true
                            self.isLoggedIn = false
                        }
                    }
                } catch {
                    print("❌ POST /users a échoué après createUser — rollback Firebase user (uid=\(user.uid)):", error.localizedDescription)
                    // Rollback : on supprime le user Firebase pour qu'il puisse
                    // retenter sans tomber dans "email already in use".
                    do {
                        try await user.delete()
                        print("🧹 Firebase user supprimé (rollback)")
                    } catch {
                        print("⚠️ Rollback Firebase échoué (l'utilisateur devra réessayer plus tard):", error.localizedDescription)
                    }
                    await MainActor.run {
                        self.signUpError = self.signupBackendErrorMessage(for: error)
                        self.isLoggedIn = false
                    }
                }
            }
        }
    }

    private func signupBackendErrorMessage(for error: Error) -> String {
        if let networkError = error as? NetworkError {
            switch networkError {
            case .unauthorized:
                return NSLocalizedString("SIGNUP_BACKEND_UNAUTHORIZED", comment: "")
            case .noUser, .noToken:
                return NSLocalizedString("SIGNUP_BACKEND_AUTH_ISSUE", comment: "")
            default:
                return NSLocalizedString("SIGNUP_BACKEND_UNAVAILABLE", comment: "")
            }
        }
        return NSLocalizedString("SIGNUP_BACKEND_UNAVAILABLE", comment: "")
    }

    private func resendVerificationForExistingAccount(email: String, password: String) {
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            if error != nil {
                DispatchQueue.main.async {
                    self.signUpError = L10n.t("AUTH_EMAIL_ALREADY_ACCOUNT")
                }
                return
            }

            guard let user = result?.user else {
                DispatchQueue.main.async {
                    self.signUpError = L10n.t("AUTH_UNABLE_ACCESS_ACCOUNT")
                }
                return
            }

            if user.isEmailVerified {
                try? Auth.auth().signOut()
                DispatchQueue.main.async {
                    self.signUpError = L10n.t("AUTH_EMAIL_ALREADY_VERIFIED")
                }
                return
            }

            user.sendEmailVerification { error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.signUpError = self.verificationEmailErrorMessage(for: error)
                    } else {
                        self.registeredEmail = email
                        self.emailVerificationSent = true
                        self.signUpError = nil
                        self.showVerificationScreen = true
                    }
                }
            }
        }
    }

    private func verificationEmailErrorMessage(for error: Error) -> String {
        if AuthErrorCode(rawValue: (error as NSError).code) == .tooManyRequests {
            return L10n.t("AUTH_VERIFY_TOO_MANY")
        }

        return L10n.f("AUTH_VERIFY_SEND_FAILED_FORMAT", error.localizedDescription)
    }
}
