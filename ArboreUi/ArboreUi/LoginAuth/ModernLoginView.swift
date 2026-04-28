import FirebaseAuth
import SwiftUI
import Firebase
import GoogleSignIn
import GoogleSignInSwift

struct ModernLoginView: View {
    @StateObject internal var authViewModel = AuthenticationView()
    @EnvironmentObject var themeManager: ThemeManager

    @State internal var showSignUp = false
    @State internal var showReset = false
    @State internal var email = ""
    @State internal var password = ""
    @State internal var isPasswordVisible = false
    @State internal var errorMessage = ""
    @State internal var isLoading = false
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @FocusState internal var focusedField: Field?

    enum Field {
        case email, password
    }

    var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Fond beige signature identique à la HomeView
    private var loginBackground: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
            : UIColor(red: 0.956, green: 0.953, blue: 0.937, alpha: 1.0) // #F4F3EF
        })
    }

    var body: some View {
        if isLoggedIn {
            MainView()
        } else {
            GeometryReader { geometry in
                ZStack {
                    // Fond beige signature Arbore
                    loginBackground
                        .ignoresSafeArea()
                        .onTapGesture { hideKeyboard() }

                    // Halo décoratif en haut
                    Ellipse()
                        .fill(themeManager.brandPrimaryHero.opacity(0.12))
                        .frame(width: geometry.size.width * 1.4, height: 340)
                        .offset(y: -geometry.size.height * 0.35)
                        .blur(radius: 60)
                        .ignoresSafeArea()

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {

                            // ── HERO ─────────────────────────────────────────
                            heroHeader(geometry: geometry)

                            // ── FORMULAIRE ───────────────────────────────────
                            formCard
                                .padding(.top, -20)

                            // ── SIGN UP LINK ──────────────────────────────────
                            signUpFooter
                                .padding(.top, 28)
                                .padding(.bottom, 48)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showSignUp) {
                NavigationStack { SignUpView() }
            }
            .sheet(isPresented: $showReset) {
                ResetPasswordView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Hero Header
    private func heroHeader(geometry: GeometryProxy) -> some View {
        ZStack(alignment: .bottom) {
            // Carte hero verte identique à la HomeView
            RoundedRectangle(cornerRadius: CGFloat(themeManager.heroCornerRadius), style: .continuous)
                .fill(themeManager.brandPrimaryHero)
                .shadow(color: themeManager.brandPrimaryHero.opacity(0.22), radius: 20, x: 0, y: 12)
                .frame(height: 240)
                .padding(.horizontal, 16)

            VStack(spacing: 14) {
                // Logo feuille
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
                        .frame(width: 64, height: 64)

                    Image(systemName: "leaf.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                }
                .scaleEffect(focusedField != nil ? 0.85 : 1.0)
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: focusedField)

                VStack(spacing: 6) {
                    Text("Bienvenue sur Arbore")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("Connectez-vous pour gérer votre jardin")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.80))
                        .multilineTextAlignment(.center)
                }
                .opacity(focusedField != nil ? 0.7 : 1.0)
                .animation(.easeInOut(duration: 0.25), value: focusedField)
            }
            .padding(.bottom, 40)
        }
        .padding(.top, 56)
        .padding(.horizontal, 0)
    }

    // MARK: - Form Card
    private var formCard: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {

                // Email
                ArborTextField(
                    text: $email,
                    placeholder: "Adresse email",
                    systemImage: "envelope.fill",
                    keyboardType: .emailAddress,
                    isSecure: false,
                    focusedField: $focusedField,
                    fieldType: .email,
                    themeManager: themeManager
                )

                // Mot de passe
                ArborTextField(
                    text: $password,
                    placeholder: "Mot de passe",
                    systemImage: "lock.fill",
                    keyboardType: .default,
                    isSecure: !isPasswordVisible,
                    focusedField: $focusedField,
                    fieldType: .password,
                    showPasswordToggle: true,
                    isPasswordVisible: $isPasswordVisible,
                    themeManager: themeManager
                )

                // Mot de passe oublié
                HStack {
                    Spacer()
                    Button("Mot de passe oublié ?") { showReset = true }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(themeManager.brandPrimary)
                }
                .padding(.top, -4)

                // Bouton connexion
                Button(action: loginUser) {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.85)
                        } else {
                            Text("Se connecter")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        Capsule()
                            .fill(isFormValid
                                  ? themeManager.brandPrimaryHero
                                  : Color(.systemGray4))
                            .shadow(
                                color: isFormValid ? themeManager.brandPrimaryHero.opacity(0.35) : .clear,
                                radius: isFormValid ? 12 : 0,
                                x: 0, y: isFormValid ? 6 : 0
                            )
                    )
                }
                .disabled(!isFormValid || isLoading)
                .scaleEffect(isFormValid ? 1.0 : 0.97)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isFormValid)

                // Message d'erreur
                if !errorMessage.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 14))
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.red.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.red.opacity(0.25), lineWidth: 1)
                            )
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(24)

            // ── Séparateur ────────────────────────────────────────────
            HStack {
                Rectangle()
                    .fill(themeManager.secondaryTextColor.opacity(0.2))
                    .frame(height: 1)
                Text("ou")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 14)
                Rectangle()
                    .fill(themeManager.secondaryTextColor.opacity(0.2))
                    .frame(height: 1)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            // ── Boutons sociaux ───────────────────────────────────────
            VStack(spacing: 12) {
                ArborSocialButton(
                    title: "Continuer avec Apple",
                    icon: "apple.logo",
                    backgroundColor: themeManager.textColor,
                    foregroundColor: themeManager.backgroundColor,
                    action: {}
                )

                ArborSocialButton(
                    title: "Continuer avec Google",
                    icon: "google",
                    backgroundColor: themeManager.cardBackgroundColor,
                    foregroundColor: themeManager.textColor,
                    hasBorder: true,
                    borderColor: themeManager.secondaryTextColor.opacity(0.25),
                    action: { authViewModel.signInWithGoogle() }
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(
            RoundedRectangle(cornerRadius: CGFloat(themeManager.heroCornerRadius), style: .continuous)
                .fill(themeManager.cardBackgroundColor)
                .shadow(color: .black.opacity(0.07), radius: 18, x: 0, y: 6)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Sign Up Footer
    private var signUpFooter: some View {
        HStack(spacing: 4) {
            Text("Pas de compte ?")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(themeManager.secondaryTextColor)

            Button("Créer un compte") {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showSignUp = true }
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(themeManager.brandPrimary)
        }
    }

    // MARK: - Login Logic
    func loginUser() {
        isLoading = true
        errorMessage = ""

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty && !trimmedPassword.isEmpty else {
            errorMessage = "Veuillez saisir votre email et mot de passe."
            isLoading = false
            return
        }

        Auth.auth().signIn(withEmail: trimmedEmail, password: trimmedPassword) { result, error in
            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error as NSError? {
                    print("❌ Firebase Auth error:")
                    print("Full error: \(error)")
                    print("UserInfo: \(error.userInfo)")

                    if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError,
                       let deserialized = underlyingError.userInfo["FIRAuthErrorUserInfoDeserializedResponseKey"] as? [String: Any],
                       let firebaseMessage = deserialized["message"] as? String {

                        switch firebaseMessage {
                        case "INVALID_LOGIN_CREDENTIALS":
                            self.errorMessage = "Email ou mot de passe incorrect."
                        case "TOO_MANY_ATTEMPTS_TRY_LATER":
                            self.errorMessage = "Trop de tentatives. Veuillez réessayer plus tard."
                        case "EMAIL_NOT_FOUND":
                            self.errorMessage = "Aucun compte trouvé avec cet email."
                        default:
                            self.errorMessage = "Erreur d'authentification: \(firebaseMessage)"
                        }
                    } else if let authError = AuthErrorCode(rawValue: error.code) {
                        switch authError {
                        case .wrongPassword:
                            self.errorMessage = "Email ou mot de passe incorrect."
                        case .tooManyRequests:
                            self.errorMessage = "Trop de tentatives. Veuillez réessayer plus tard."
                        case .userNotFound:
                            self.errorMessage = "Aucun compte trouvé avec cet email."
                        default:
                            self.errorMessage = "Erreur d'authentification: \(error.localizedDescription)"
                        }
                    } else {
                        self.errorMessage = "Erreur d'authentification inconnue. Veuillez réessayer."
                    }
                    return
                }

                Task {
                    if let token = try? await Auth.auth().currentUser?.getIDToken() {
                        print("🔑 Firebase Token:", token)
                    }
                }

                guard let user = result?.user else { return }

                if !user.isEmailVerified {
                    checkAndDeleteIfExpired(uid: user.uid)
                    self.errorMessage = "Veuillez vérifier votre email avant de vous connecter."
                    try? Auth.auth().signOut()
                    return
                }

                self.isLoggedIn = true
            }
        }
    }
}

// MARK: - Arbore Text Field
struct ArborTextField: View {
    @Binding var text: String
    let placeholder: String
    let systemImage: String
    let keyboardType: UIKeyboardType
    let isSecure: Bool
    @FocusState.Binding var focusedField: ModernLoginView.Field?
    let fieldType: ModernLoginView.Field
    var showPasswordToggle: Bool = false
    @Binding var isPasswordVisible: Bool
    let themeManager: ThemeManager

    init(text: Binding<String>, placeholder: String, systemImage: String, keyboardType: UIKeyboardType, isSecure: Bool, focusedField: FocusState<ModernLoginView.Field?>.Binding, fieldType: ModernLoginView.Field, showPasswordToggle: Bool = false, isPasswordVisible: Binding<Bool> = .constant(false), themeManager: ThemeManager) {
        self._text = text
        self.placeholder = placeholder
        self.systemImage = systemImage
        self.keyboardType = keyboardType
        self.isSecure = isSecure
        self._focusedField = focusedField
        self.fieldType = fieldType
        self.showPasswordToggle = showPasswordToggle
        self._isPasswordVisible = isPasswordVisible
        self.themeManager = themeManager
    }

    private var isFocused: Bool { focusedField == fieldType }

    private var iconColor: Color {
        isFocused ? themeManager.brandPrimaryHero : themeManager.secondaryTextColor
    }
    private var borderColor: Color {
        isFocused ? themeManager.brandPrimaryHero : themeManager.secondaryTextColor.opacity(0.25)
    }
    private var shadowColor: Color {
        isFocused ? themeManager.brandPrimaryHero.opacity(0.12) : .clear
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 20)
                .animation(.easeInOut(duration: 0.2), value: isFocused)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 16))
                        .foregroundColor(themeManager.placeholderTextColor)
                }

                if isSecure {
                    SecureField("", text: $text)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(themeManager.textColor)
                        .keyboardType(keyboardType)
                        .focused($focusedField, equals: fieldType)
                        .submitLabel(fieldType == .email ? .next : .go)
                        .onSubmit { if fieldType == .email { focusedField = .password } }
                        .tint(themeManager.brandPrimaryHero)
                } else {
                    TextField("", text: $text)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(themeManager.textColor)
                        .keyboardType(keyboardType)
                        .focused($focusedField, equals: fieldType)
                        .submitLabel(fieldType == .email ? .next : .go)
                        .onSubmit { if fieldType == .email { focusedField = .password } }
                        .tint(themeManager.brandPrimaryHero)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }

            if showPasswordToggle {
                Button(action: { isPasswordVisible.toggle() }) {
                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(themeManager.secondaryTextColor)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: CGFloat(themeManager.cardCornerRadius), style: .continuous)
                .fill(themeManager.backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: CGFloat(themeManager.cardCornerRadius), style: .continuous)
                        .stroke(borderColor, lineWidth: isFocused ? 1.5 : 1)
                )
                .shadow(color: shadowColor, radius: 8, x: 0, y: 3)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
    }
}

// MARK: - Social Login Button
struct ArborSocialButton: View {
    let title: String
    let icon: String
    let backgroundColor: Color
    let foregroundColor: Color
    var hasBorder: Bool = false
    var borderColor: Color = .clear
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if icon == "google" {
                    Image("google")
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        hasBorder
                        ? RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                        : nil
                    )
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helper
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
