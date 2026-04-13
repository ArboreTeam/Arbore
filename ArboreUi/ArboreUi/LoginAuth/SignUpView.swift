import FirebaseAuth
import SwiftUI
import Firebase

struct SignUpView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @AppStorage("isLoggedIn") var isLoggedIn = false

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var signUpError: String? = nil
    @State private var showVerificationScreen = false
    @State private var registeredEmail: String = ""
    @State private var acceptedTerms = false
    @State private var acceptedPrivacy = false
    @StateObject private var authViewModel = AuthenticationView()
    @FocusState private var focusedField: Field?

    enum Field { case firstName, lastName, email, password }

    var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        acceptedTerms && acceptedPrivacy
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
        ZStack(alignment: .top) {
            pageBackground.ignoresSafeArea()
                .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }

            // Halo décoratif
            Ellipse()
                .fill(themeManager.brandPrimaryHero.opacity(0.12))
                .frame(width: 500, height: 260)
                .offset(y: -40)
                .blur(radius: 60)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero header
                    heroHeader

                    // Carte formulaire
                    formCard
                        .padding(.horizontal, 20)
                        .padding(.top, -20)
                        .padding(.bottom, 40)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .navigationDestination(isPresented: $showVerificationScreen) {
            VerifyEmailView(
                email: registeredEmail,
                onResend: {
                    Auth.auth().currentUser?.sendEmailVerification { error in
                        if let error = error { signUpError = "Renvoi échoué : \(error.localizedDescription)" }
                    }
                },
                onBackToLogin: { dismiss() }
            )
        }
    }

    // MARK: - Hero
    private var heroHeader: some View {
        VStack(spacing: 14) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(10)
                        .background(Circle().fill(Color.white.opacity(0.18)))
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    .frame(width: 60, height: 60)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 6) {
                Text("Créer un compte")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Rejoignez la communauté Arbore")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.78))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 60)
        .padding(.bottom, 36)
        .background(
            themeManager.brandPrimaryHero
                .shadow(color: themeManager.brandPrimaryHero.opacity(0.25), radius: 24, x: 0, y: 12)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: CGFloat(themeManager.heroCornerRadius), style: .continuous)
        )
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    // MARK: - Form Card
    private var formCard: some View {
        VStack(spacing: 16) {
            // Prénom / Nom côte à côte
            HStack(spacing: 12) {
                SignUpField(text: $firstName, placeholder: "Prénom", icon: "person.fill",
                           focus: $focusedField, fieldType: .firstName, theme: themeManager)
                SignUpField(text: $lastName, placeholder: "Nom", icon: "person.fill",
                           focus: $focusedField, fieldType: .lastName, theme: themeManager)
            }

            // Email
            SignUpField(text: $email, placeholder: "Adresse email", icon: "envelope.fill",
                       keyboardType: .emailAddress, focus: $focusedField, fieldType: .email, theme: themeManager)

            // Mot de passe
            SignUpField(text: $password, placeholder: "Mot de passe", icon: "lock.fill",
                       isSecure: !isPasswordVisible, focus: $focusedField, fieldType: .password,
                       showToggle: true, isVisible: $isPasswordVisible, theme: themeManager)

            // Consentements
            VStack(spacing: 10) {
                consentRow(
                    accepted: $acceptedTerms,
                    text: NSLocalizedString("SIGNUP_ACCEPT", comment: "I accept the"),
                    linkText: NSLocalizedString("SIGNUP_TERMS", comment: "Terms of Service"),
                    destination: AnyView(TermsConditionsView())
                )
                consentRow(
                    accepted: $acceptedPrivacy,
                    text: NSLocalizedString("SIGNUP_ACCEPT", comment: "I accept the"),
                    linkText: NSLocalizedString("SIGNUP_PRIVACY", comment: "Privacy Policy"),
                    destination: AnyView(PrivacyPolicyView())
                )
            }
            .padding(.top, 4)

            // Erreur
            if let error = signUpError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                    Text(error)
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

            // Bouton inscription
            Button(action: registerUser) {
                HStack(spacing: 8) {
                    Text("Créer mon compte")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    Capsule()
                        .fill(isFormValid
                              ? themeManager.brandPrimaryHero
                              : themeManager.secondaryTextColor.opacity(0.3))
                        .shadow(color: isFormValid ? themeManager.brandPrimaryHero.opacity(0.35) : .clear,
                                radius: 10, x: 0, y: 5)
                )
            }
            .disabled(!isFormValid)
            .scaleEffect(isFormValid ? 1.0 : 0.97)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isFormValid)

            // Séparateur
            HStack {
                Rectangle().fill(themeManager.separatorColor.opacity(0.5)).frame(height: 1)
                Text("ou")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 12)
                Rectangle().fill(themeManager.separatorColor.opacity(0.5)).frame(height: 1)
            }
            .padding(.vertical, 4)

            // Bouton Google
            ArboreSocialButton(
                title: "Continuer avec Google",
                icon: "google",
                bg: themeManager.backgroundColor,
                fg: themeManager.textColor,
                border: themeManager.separatorColor,
                action: { authViewModel.signInWithGoogle() }
            )

            // Déjà un compte
            HStack(spacing: 4) {
                Text("Déjà un compte ?")
                    .font(.system(size: 13))
                    .foregroundColor(themeManager.secondaryTextColor)
                Button("Se connecter") { dismiss() }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(themeManager.brandPrimary)
            }
            .padding(.top, 4)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: CGFloat(themeManager.heroCornerRadius), style: .continuous)
                .fill(themeManager.cardBackgroundColor)
                .shadow(color: .black.opacity(0.07), radius: 20, x: 0, y: 8)
        )
    }

    // MARK: - Consent Row
    private func consentRow(accepted: Binding<Bool>, text: String, linkText: String, destination: AnyView) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { accepted.wrappedValue.toggle() } label: {
                Image(systemName: accepted.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundColor(accepted.wrappedValue ? themeManager.brandPrimary : themeManager.secondaryTextColor)
            }
            HStack(spacing: 3) {
                Text(text)
                    .foregroundColor(themeManager.secondaryTextColor)
                NavigationLink(destination: destination) {
                    Text(linkText)
                        .foregroundColor(themeManager.brandPrimary)
                        .underline()
                }
            }
            .font(.system(size: 13))
            Spacer()
        }
    }

    // MARK: - Register Logic
    func registerUser() {
        signUpError = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.registeredEmail = trimmedEmail
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = "\(firstName.trimmingCharacters(in: .whitespacesAndNewlines)) \(lastName.trimmingCharacters(in: .whitespacesAndNewlines))"

        Auth.auth().createUser(withEmail: trimmedEmail, password: trimmedPassword) { result, error in
            if let error = error { self.signUpError = error.localizedDescription; return }
            guard let user = result?.user else { self.signUpError = "Erreur inattendue."; return }

            user.sendEmailVerification { error in
                if let error = error {
                    self.signUpError = "Erreur d'envoi de l'email : \(error.localizedDescription)"
                } else {
                    self.showVerificationScreen = true
                }
            }
            saveUserToBackend(uid: user.uid, email: user.email ?? "", name: fullName, createdAt: Date())
            recordInitialConsents(uid: user.uid, acceptedTerms: self.acceptedTerms, acceptedPrivacy: self.acceptedPrivacy)
            self.isLoggedIn = false
        }
    }
}

// MARK: - Champ de formulaire SignUp
struct SignUpField: View {
    @Binding var text: String
    let placeholder: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    @FocusState.Binding var focus: SignUpView.Field?
    let fieldType: SignUpView.Field
    var showToggle: Bool = false
    @Binding var isVisible: Bool
    let theme: ThemeManager

    init(text: Binding<String>, placeholder: String, icon: String,
         keyboardType: UIKeyboardType = .default, isSecure: Bool = false,
         focus: FocusState<SignUpView.Field?>.Binding, fieldType: SignUpView.Field,
         showToggle: Bool = false, isVisible: Binding<Bool> = .constant(false),
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
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(active ? theme.brandPrimaryHero : theme.secondaryTextColor)
                .frame(width: 18)
                .animation(.easeInOut(duration: 0.18), value: active)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14))
                        .foregroundColor(theme.placeholderTextColor)
                }
                if isSecure {
                    SecureField("", text: $text)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(theme.textColor)
                        .focused($focus, equals: fieldType)
                        .tint(theme.brandPrimaryHero)
                } else {
                    TextField("", text: $text)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(theme.textColor)
                        .keyboardType(keyboardType)
                        .focused($focus, equals: fieldType)
                        .tint(theme.brandPrimaryHero)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }

            if showToggle {
                Button { isVisible.toggle() } label: {
                    Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 14))
                        .foregroundColor(theme.secondaryTextColor)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: CGFloat(theme.cardCornerRadius), style: .continuous)
                .fill(theme.backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: CGFloat(theme.cardCornerRadius), style: .continuous)
                        .stroke(active ? theme.brandPrimaryHero : theme.separatorColor.opacity(0.6),
                                lineWidth: active ? 1.5 : 1)
                )
                .shadow(color: active ? theme.brandPrimaryHero.opacity(0.1) : .clear, radius: 5, x: 0, y: 2)
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: active)
    }
}
