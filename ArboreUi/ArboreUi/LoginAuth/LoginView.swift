import FirebaseAuth
import SwiftUI
import Firebase
import GoogleSignIn
import GoogleSignInSwift

struct LoginView: View {
    @StateObject private var authViewModel = AuthenticationView()
    @StateObject private var appleAuth = AppleAuthService()

    @State private var showSignUp = false
    @State private var showReset = false
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var errorMessage = ""
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @FocusState private var focusedField: Field?

    enum Field {
        case email, password
    }

    var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        if isLoggedIn {
            MainView()
        } else {
            ZStack(alignment: .top) {
                LinearGradient(
                    gradient: Gradient(colors: [ArboreDesign.Colors.background, ArboreDesign.Colors.background]),
                    startPoint: .top,
                    endPoint: .bottom
                ).ignoresSafeArea()
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }

                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 25) {
                            VStack(spacing: 8) {
                                Text("Arbore")
                                    .font(.system(size: 42, weight: .bold, design: .rounded))
                                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                                    .transition(.opacity.combined(with: .move(edge: .top)))

                                Text(L10n.t("AUTH_TAGLINE"))
                                    .font(.system(size: 18, weight: .medium, design: .rounded))
                                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                                    .transition(.opacity)
                            }
                            .animation(.easeOut(duration: 0.5), value: email)

                            VStack(spacing: 14) {
                                TextField("", text: $email)
                                    .placeholder(when: email.isEmpty) {
                                        Text(L10n.t("AUTH_EMAIL")).foregroundColor(ArboreDesign.Colors.placeholder)
                                    }
                                    .focused($focusedField, equals: .email)
                                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                                    .padding()
                                    .background(ArboreDesign.Colors.card)
                                    .cornerRadius(ArboreDesign.Radius.medium)
                                    .tint(ArboreDesign.Colors.primaryGreen)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium)
                                            .stroke(focusedField == .email ? ArboreDesign.Colors.primaryGreen : ArboreDesign.Colors.border, lineWidth: 1)
                                            .animation(.easeInOut(duration: 0.2), value: focusedField == .email)
                                    )
                                    .submitLabel(.next)
                                    .onSubmit {
                                        focusedField = .password
                                    }

                                ZStack(alignment: .trailing) {
                                    Group {
                                        if isPasswordVisible {
                                            TextField("", text: $password)
                                                .focused($focusedField, equals: .password)
                                                .placeholder(when: password.isEmpty) {
                                                    Text(L10n.t("AUTH_PASSWORD")).foregroundColor(ArboreDesign.Colors.placeholder)
                                                }
                                                .submitLabel(.go)
                                                .onSubmit { loginUser() }
                                        } else {
                                            SecureField("", text: $password)
                                                .focused($focusedField, equals: .password)
                                                .placeholder(when: password.isEmpty) {
                                                    Text(L10n.t("AUTH_PASSWORD")).foregroundColor(ArboreDesign.Colors.placeholder)
                                                }
                                                .submitLabel(.go)
                                                .onSubmit { loginUser() }
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
                                            .animation(.easeInOut(duration: 0.2), value: focusedField == .password)
                                    )

                                    Button(action: {
                                        withAnimation { isPasswordVisible.toggle() }
                                    }) {
                                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                            .resizable()
                                            .frame(width: 18, height: 18)
                                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                                            .padding(.trailing, 12)
                                    }
                                }

                                HStack {
                                    Spacer()
                                    Button(L10n.t("AUTH_FORGOT_PASSWORD")) {
                                        showReset = true
                                    }
                                    .padding(.trailing, 4)
                                    .font(.footnote)
                                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
                                    .padding(.top, 4)
                                }
                            }
                            .padding(.horizontal, 30)
                            .transition(.move(edge: .bottom))

                            Button(action: loginUser) {
                                Text(L10n.t("AUTH_SIGN_IN"))
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

                            if !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .foregroundColor(ArboreDesign.Colors.danger)
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 30)
                                    .transition(.opacity)
                            }

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

                            // Sign-in wrap : couvre l'email ET les SSO Apple/Google
                            // (où le « sign in » crée le compte). Pas de checkbox —
                            // l'action affirmative est le tap sur un bouton d'auth
                            // (issue #227). Le consentement analytics/marketing est
                            // géré à part, en opt-in (cf. PrivacySettings / #226).
                            VStack(spacing: 4) {
                                Text(NSLocalizedString("AUTH_AGREE_CONTINUE", comment: ""))
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
                            .padding(.top, 12)

                            HStack {
                                Text(L10n.t("AUTH_NO_ACCOUNT"))
                                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                                Button(action: {
                                    withAnimation { showSignUp = true }
                                }) {
                                    Text(L10n.t("AUTH_SIGN_UP"))
                                        .fontWeight(.semibold)
                                        .foregroundColor(ArboreDesign.Colors.primaryGreen)
                                }
                            }
                            .font(.footnote)
                            .padding(.top, 8)

                            // Accès invité (#391). En dernière position et en
                            // traitement fantôme : c'est une action tertiaire,
                            // sous les trois fournisseurs de connexion.
                            ContinueAsGuestButton { isLoggedIn = true }
                                .padding(.top, 4)

                            Spacer(minLength: 30)
                        }
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .fullScreenCover(isPresented: $showSignUp) {
                NavigationStack {
                    SignUpView()
                }
            }
            .sheet(isPresented: $showReset) {
                ResetPasswordView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    func loginUser() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty && !trimmedPassword.isEmpty else {
            errorMessage = L10n.t("AUTH_ERROR_EMPTY_CREDENTIALS")
            return
        }

        Auth.auth().signIn(withEmail: trimmedEmail, password: trimmedPassword) { result, error in
            if let error = error as NSError? {
                print("❌ Firebase Auth error:")
                print("Full error: \(error)")
                print("UserInfo: \(error.userInfo)")

                if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError,
                   let deserialized = underlyingError.userInfo["FIRAuthErrorUserInfoDeserializedResponseKey"] as? [String: Any],
                   let firebaseMessage = deserialized["message"] as? String {
                    
                    switch firebaseMessage {
                    case "INVALID_LOGIN_CREDENTIALS":
                        self.errorMessage = L10n.t("AUTH_ERROR_INVALID_CREDENTIALS")
                    case "TOO_MANY_ATTEMPTS_TRY_LATER":
                        self.errorMessage = L10n.t("AUTH_ERROR_TOO_MANY")
                    case "EMAIL_NOT_FOUND":
                        self.errorMessage = L10n.t("AUTH_ERROR_NO_ACCOUNT")
                    default:
                        self.errorMessage = L10n.f("AUTH_ERROR_GENERIC_FORMAT", firebaseMessage)
                    }
                } else if let authError = AuthErrorCode(rawValue: error.code) {
                    // Cas où Firebase mappe bien l'erreur
                    switch authError {
                    case .wrongPassword:
                        self.errorMessage = L10n.t("AUTH_ERROR_INVALID_CREDENTIALS")
                    case .tooManyRequests:
                        self.errorMessage = L10n.t("AUTH_ERROR_TOO_MANY")
                    case .userNotFound:
                        self.errorMessage = L10n.t("AUTH_ERROR_NO_ACCOUNT")
                    default:
                        self.errorMessage = L10n.f("AUTH_ERROR_GENERIC_FORMAT", error.localizedDescription)
                    }
                } else {
                    self.errorMessage = L10n.t("AUTH_ERROR_UNKNOWN")
                }
                return
            }

            guard let user = result?.user else { return }

            if !user.isEmailVerified {
                checkAndDeleteIfExpired(uid: user.uid)
                self.errorMessage = L10n.t("AUTH_VERIFY_BEFORE_LOGIN")
                try? Auth.auth().signOut()
                return
            }

            self.isLoggedIn = true
        }
    }
}

func checkAndDeleteIfExpired(uid: String) {
    Task {
        do {
            let response: UserResponse = try await NetworkManager.shared.requestWithoutAuth(
                endpoint: "/users/\(uid)",
                method: .GET
            )

            guard let user = response.user else {
                print("⚠️ User not found in MongoDB")
                return
            }

            let now = Date()
            let hoursSinceCreation = now.timeIntervalSince(user.createdAt) / 3600

            if hoursSinceCreation > 48 {
                print("🧹 Deleting expired, unverified user...")
                deleteAccount()
            } else {
                print("⏱ Account still within time window")
            }
        } catch {
            print("❌ Error checking user expiration: \(error)")
        }
    }
}

func deleteAccount() {
    guard let user = Auth.auth().currentUser else { return }
    let uid = user.uid

    // Supprime de Firebase
    user.delete { error in
        if let error = error {
            print("❌ Error deleting Firebase account: \(error.localizedDescription)")
            return
        }

        // Supprime de MongoDB avec API Key
        Task {
            do {
                try await NetworkManager.shared.requestWithoutAuthNoResponse(
                    endpoint: "/users/\(uid)",
                    method: .DELETE
                )
                print("✅ Account deleted from MongoDB and Firebase")
            } catch {
                print("❌ Error deleting from MongoDB: \(error)")
            }
        }
    }
}
