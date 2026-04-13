import FirebaseAuth
import SwiftUI
import Firebase
import GoogleSignIn
import GoogleSignInSwift

// MARK: - Modern Login View
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

    enum Field { case email, password }

    var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Fond beige signature identique à la HomeView
    private var pageBackground: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
            : UIColor(red: 0.956, green: 0.953, blue: 0.937, alpha: 1.0)
        })
    }

    var body: some View {
        if isLoggedIn {
            MainView()
        } else {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    pageBackground.ignoresSafeArea()
                        .onTapGesture { hideKeyboard() }

                    // Halo vert décoratif derrière la hero card
                    Ellipse()
                        .fill(themeManager.brandPrimaryHero.opacity(0.15))
                        .frame(width: geo.size.width * 1.6, height: 320)
                        .offset(y: -60)
                        .blur(radius: 70)
                        .ignoresSafeArea()

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            heroSection
                                .padding(.horizontal, 20)
                                .padding(.top, geo.safeAreaInsets.top + 20)

                            formSection
                                .padding(.horizontal, 20)
                                .padding(.top, -24)

                            footerSection
                                .padding(.top, 28)
                                .padding(.bottom, 48)
                        }
                    }
                    .ignoresSafeArea(edges: .top)
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

    // MARK: - Hero
    private var heroSection: some View {
        VStack(spacing: 16) {
            // Icône feuille dans cercle
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    .frame(width: 68, height: 68)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
            }
            .scaleEffect(focusedField != nil ? 0.82 : 1.0)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: focusedField)

            VStack(spacing: 6) {
                Text("Bienvenue sur Arbore")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Connectez-vous pour gérer votre jardin")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
            }
            .opacity(focusedField != nil ? 0.65 : 1.0)
            .animation(.easeInOut(duration: 0.22), value: focusedField)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: CGFloat(themeManager.heroCornerRadius), style: .continuous)
                .fill(themeManager.brandPrimaryHero)
                .shadow(color: themeManager.brandPrimaryHero.opacity(0.28), radius: 24, x: 0, y: 12)
        )
    }

    // MARK: - Form Card
    private var formSection: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                // Email
                ArboreLoginField(
                    text: $email,
                    placeholder: "Adresse email",
                    icon: "envelope.fill",
                    keyboardType: .emailAddress,
                    isSecure: false,
                    focus: $focusedField,
                    fieldType: .email,
                    theme: themeManager
                )

                // Mot de passe
                ArboreLoginField(
                    text: $password,
                    placeholder: "Mot de passe",
                    icon: "lock.fill",
                    keyboardType: .default,
                    isSecure: !isPasswordVisible,
                    focus: $focusedField,
                    fieldType: .password,
                    showToggle: true,
                    isVisible: $isPasswordVisible,
                    theme: themeManager
                )

                // Mot de passe oublié
                HStack {
                    Spacer()
                    Button("Mot de passe oublié ?") { showReset = true }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(themeManager.brandPrimary)
                }

                // Bouton connexion
                Button(action: loginUser) {
                    ZStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            HStack(spacing: 8) {
                                Text("Se connecter")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Capsule()
                            .fill(isFormValid
                                  ? themeManager.brandPrimaryHero
                                  : themeManager.secondaryTextColor.opacity(0.3))
                            .shadow(
                                color: isFormValid ? themeManager.brandPrimaryHero.opacity(0.4) : .clear,
                                radius: 10, x: 0, y: 5
                            )
                    )
                }
                .disabled(!isFormValid || isLoading)
                .scaleEffect(isFormValid ? 1.0 : 0.97)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isFormValid)

                // Erreur
                if !errorMessage.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.red.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.red.opacity(0.22), lineWidth: 1)
                            )
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(22)

            // Séparateur
            HStack {
                Rectangle().fill(themeManager.separatorColor.opacity(0.5)).frame(height: 1)
                Text("ou")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 12)
                Rectangle().fill(themeManager.separatorColor.opacity(0.5)).frame(height: 1)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            // Boutons sociaux
            VStack(spacing: 10) {
                ArboreSocialButton(
                    title: "Continuer avec Apple",
                    icon: "apple.logo",
                    bg: themeManager.textColor,
                    fg: themeManager.backgroundColor,
                    action: {}
                )
                ArboreSocialButton(
                    title: "Continuer avec Google",
                    icon: "google",
                    bg: themeManager.cardBackgroundColor,
                    fg: themeManager.textColor,
                    border: themeManager.separatorColor,
                    action: { authViewModel.signInWithGoogle() }
                )
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .background(
            RoundedRectangle(cornerRadius: CGFloat(themeManager.heroCornerRadius), style: .continuous)
                .fill(themeManager.cardBackgroundColor)
                .shadow(color: .black.opacity(0.07), radius: 20, x: 0, y: 8)
        )
    }

    // MARK: - Footer
    private var footerSection: some View {
        HStack(spacing: 4) {
            Text("Pas de compte ?")
                .font(.system(size: 14))
                .foregroundColor(themeManager.secondaryTextColor)
            Button("Créer un compte") {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showSignUp = true }
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(themeManager.brandPrimary)
        }
    }

    // MARK: - Auth
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
                    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError,
                       let deserialized = underlying.userInfo["FIRAuthErrorUserInfoDeserializedResponseKey"] as? [String: Any],
                       let msg = deserialized["message"] as? String {
                        switch msg {
                        case "INVALID_LOGIN_CREDENTIALS": self.errorMessage = "Email ou mot de passe incorrect."
                        case "TOO_MANY_ATTEMPTS_TRY_LATER": self.errorMessage = "Trop de tentatives. Réessayez plus tard."
                        case "EMAIL_NOT_FOUND": self.errorMessage = "Aucun compte trouvé avec cet email."
                        default: self.errorMessage = "Erreur : \(msg)"
                        }
                    } else if let code = AuthErrorCode(rawValue: error.code) {
                        switch code {
                        case .wrongPassword: self.errorMessage = "Email ou mot de passe incorrect."
                        case .tooManyRequests: self.errorMessage = "Trop de tentatives. Réessayez plus tard."
                        case .userNotFound: self.errorMessage = "Aucun compte trouvé avec cet email."
                        default: self.errorMessage = error.localizedDescription
                        }
                    } else {
                        self.errorMessage = "Erreur inconnue. Veuillez réessayer."
                    }
                    return
                }
                Task { if let token = try? await Auth.auth().currentUser?.getIDToken() { print("🔑 Token:", token) } }
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

// MARK: - Champ de texte Arbore
struct ArboreLoginField: View {
    @Binding var text: String
    let placeholder: String
    let icon: String
    let keyboardType: UIKeyboardType
    let isSecure: Bool
    @FocusState.Binding var focus: ModernLoginView.Field?
    let fieldType: ModernLoginView.Field
    var showToggle: Bool = false
    @Binding var isVisible: Bool
    let theme: ThemeManager

    init(text: Binding<String>, placeholder: String, icon: String,
         keyboardType: UIKeyboardType, isSecure: Bool,
         focus: FocusState<ModernLoginView.Field?>.Binding,
         fieldType: ModernLoginView.Field,
         showToggle: Bool = false,
         isVisible: Binding<Bool> = .constant(false),
         theme: ThemeManager) {
        self._text = text
        self.placeholder = placeholder
        self.icon = icon
        self.keyboardType = keyboardType
        self.isSecure = isSecure
        self._focus = focus
        self.fieldType = fieldType
        self.showToggle = showToggle
        self._isVisible = isVisible
        self.theme = theme
    }

    private var active: Bool { focus == fieldType }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(active ? theme.brandPrimaryHero : theme.secondaryTextColor)
                .frame(width: 20)
                .animation(.easeInOut(duration: 0.18), value: active)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 15))
                        .foregroundColor(theme.placeholderTextColor)
                }
                if isSecure {
                    SecureField("", text: $text)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(theme.textColor)
                        .keyboardType(keyboardType)
                        .focused($focus, equals: fieldType)
                        .submitLabel(fieldType == .email ? .next : .go)
                        .onSubmit { if fieldType == .email { focus = .password } }
                        .tint(theme.brandPrimaryHero)
                } else {
                    TextField("", text: $text)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(theme.textColor)
                        .keyboardType(keyboardType)
                        .focused($focus, equals: fieldType)
                        .submitLabel(fieldType == .email ? .next : .go)
                        .onSubmit { if fieldType == .email { focus = .password } }
                        .tint(theme.brandPrimaryHero)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }

            if showToggle {
                Button { isVisible.toggle() } label: {
                    Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 15))
                        .foregroundColor(theme.secondaryTextColor)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: CGFloat(theme.cardCornerRadius), style: .continuous)
                .fill(theme.backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: CGFloat(theme.cardCornerRadius), style: .continuous)
                        .stroke(
                            active ? theme.brandPrimaryHero : theme.separatorColor.opacity(0.6),
                            lineWidth: active ? 1.5 : 1
                        )
                )
                .shadow(color: active ? theme.brandPrimaryHero.opacity(0.12) : .clear, radius: 6, x: 0, y: 2)
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: active)
    }
}

// MARK: - Bouton social Arbore
struct ArboreSocialButton: View {
    let title: String
    let icon: String
    let bg: Color
    let fg: Color
    var border: Color = .clear
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if icon == "google" {
                    Image("google").resizable().frame(width: 18, height: 18)
                } else {
                    Image(systemName: icon).font(.system(size: 17, weight: .medium))
                }
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                Capsule()
                    .fill(bg)
                    .overlay(
                        border != .clear
                        ? Capsule().stroke(border, lineWidth: 1)
                        : nil
                    )
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Keyboard helper
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
