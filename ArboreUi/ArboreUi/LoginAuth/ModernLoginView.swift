import SwiftUI
import Firebase
import GoogleSignIn
import GoogleSignInSwift

struct ModernLoginView: View {
    @StateObject private var authViewModel = AuthenticationView()
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var showSignUp = false
    @State private var showReset = false
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @FocusState private var focusedField: Field?

    enum Field {
        case email, password
    }

    var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // Dynamic colors based on theme
    var backgroundColor: Color {
        themeManager.colorScheme == .dark ? Color.black : Color.white
    }
    
    var primaryColor: Color {
        Color(hex: "#4A7C59")
    }
    
    var textColor: Color {
        themeManager.colorScheme == .dark ? Color.white : Color(hex: "#1C1C1E")
    }
    
    var secondaryTextColor: Color {
        themeManager.colorScheme == .dark ? Color(hex: "#EBEBF5").opacity(0.6) : Color(hex: "#8E8E93")
    }
    
    var fieldBackgroundColor: Color {
        themeManager.colorScheme == .dark ? Color(hex: "#1C1C1E") : Color.white
    }
    
    var placeholderColor: Color {
        themeManager.colorScheme == .dark ? Color(hex: "#EBEBF5").opacity(0.4) : Color(hex: "#C7C7CC")
    }

    var body: some View {
        if isLoggedIn {
            MainView()
        } else {
            GeometryReader { geometry in
                ZStack {
                    // Modern gradient background adapted for dark theme
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: themeManager.colorScheme == .dark ? 
                                  Color(hex: "#000000") : Color(hex: "#E8F5E8"), location: 0.0),
                            .init(color: themeManager.colorScheme == .dark ? 
                                  Color(hex: "#1C1C1E") : Color(hex: "#F0F9F0"), location: 0.3),
                            .init(color: backgroundColor, location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    .onTapGesture {
                        hideKeyboard()
                    }
                    
                    // Subtle background pattern
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    primaryColor.opacity(themeManager.colorScheme == .dark ? 0.1 : 0.05),
                                    Color.clear
                                ]),
                                center: .topTrailing,
                                startRadius: 50,
                                endRadius: 400
                            )
                        )
                        .frame(width: 600, height: 600)
                        .position(x: geometry.size.width + 100, y: -100)
                    
                    ScrollView {
                        VStack(spacing: 0) {
                            // Header Section
                            VStack(spacing: 12) {
                                // App Icon/Logo
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [primaryColor, Color(hex: "#2D5016")],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 80, height: 80)
                                        .shadow(color: primaryColor.opacity(0.3), radius: 10, x: 0, y: 5)
                                    
                                    Image(systemName: "leaf.fill")
                                        .font(.system(size: 35, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                .scaleEffect(focusedField != nil ? 0.8 : 1.0)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: focusedField)
                                
                                VStack(spacing: 8) {
                                    Text("Bienvenue sur Arbore")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundColor(textColor)
                                        .multilineTextAlignment(.center)
                                    
                                    Text("Connectez-vous pour gérer votre jardin")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(secondaryTextColor)
                                        .multilineTextAlignment(.center)
                                }
                                .opacity(focusedField != nil ? 0.7 : 1.0)
                                .animation(.easeInOut(duration: 0.3), value: focusedField)
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 60)
                            .padding(.bottom, 40)
                            
                            // Form Section
                            VStack(spacing: 20) {
                                // Email Field
                                ModernTextField(
                                    text: $email,
                                    placeholder: "Adresse email",
                                    systemImage: "envelope.fill",
                                    keyboardType: .emailAddress,
                                    isSecure: false,
                                    focusedField: $focusedField,
                                    fieldType: .email,
                                    themeManager: themeManager
                                )
                                
                                // Password Field
                                ModernTextField(
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
                                
                                // Forgot Password
                                HStack {
                                    Spacer()
                                    Button("Mot de passe oublié ?") {
                                        showReset = true
                                    }
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(primaryColor)
                                }
                                .padding(.horizontal, 24)
                                .padding(.top, -8)
                            }
                            .padding(.bottom, 32)
                            
                            // Sign In Button
                            VStack(spacing: 16) {
                                Button(action: loginUser) {
                                    HStack {
                                        if isLoading {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(0.8)
                                        } else {
                                            Text("Se connecter")
                                                .font(.system(size: 16, weight: .semibold))
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(
                                                LinearGradient(
                                                    colors: isFormValid ? 
                                                        [primaryColor, Color(hex: "#2D5016")] :
                                                        [Color(hex: "#8E8E93"), Color(hex: "#636366")],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .shadow(
                                                color: isFormValid ? primaryColor.opacity(0.3) : Color.clear,
                                                radius: isFormValid ? 10 : 0,
                                                x: 0,
                                                y: isFormValid ? 5 : 0
                                            )
                                    )
                                }
                                .disabled(!isFormValid || isLoading)
                                .scaleEffect(isFormValid ? 1.0 : 0.98)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isFormValid)
                                .padding(.horizontal, 24)
                                
                                // Error Message
                                if !errorMessage.isEmpty {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red)
                                            .font(.system(size: 14))
                                        
                                        Text(errorMessage)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.red)
                                            .multilineTextAlignment(.leading)
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.red.opacity(0.1))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                                    .padding(.horizontal, 24)
                                    .transition(.opacity.combined(with: .scale))
                                }
                            }
                            
                            // Divider
                            HStack {
                                Rectangle()
                                    .fill(secondaryTextColor.opacity(0.3))
                                    .frame(height: 1)
                                Text("ou")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(secondaryTextColor)
                                    .padding(.horizontal, 16)
                                Rectangle()
                                    .fill(secondaryTextColor.opacity(0.3))
                                    .frame(height: 1)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 32)
                            
                            // Social Login Buttons
                            VStack(spacing: 12) {
                                SocialLoginButton(
                                    title: "Continuer avec Apple",
                                    icon: "apple.logo",
                                    backgroundColor: themeManager.colorScheme == .dark ? .white : .black,
                                    foregroundColor: themeManager.colorScheme == .dark ? .black : .white,
                                    action: {}
                                )
                                
                                SocialLoginButton(
                                    title: "Continuer avec Google",
                                    icon: "google",
                                    backgroundColor: fieldBackgroundColor,
                                    foregroundColor: textColor,
                                    hasBorder: true,
                                    borderColor: secondaryTextColor.opacity(0.3),
                                    action: {
                                        authViewModel.signInWithGoogle()
                                    }
                                )
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 32)
                            
                            // Sign Up Link
                            HStack(spacing: 4) {
                                Text("Pas de compte ?")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(secondaryTextColor)
                                
                                Button("Créer un compte") {
                                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                        showSignUp = true
                                    }
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(primaryColor)
                            }
                            .padding(.bottom, 40)
                        }
                    }
                }
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

// MARK: - Modern TextField Component
struct ModernTextField: View {
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
    
    // Dynamic colors based on theme
    var iconColor: Color {
        focusedField == fieldType ? 
            Color(hex: "#4A7C59") : 
            (themeManager.colorScheme == .dark ? Color(hex: "#EBEBF5").opacity(0.6) : Color(hex: "#8E8E93"))
    }
    
    var placeholderColor: Color {
        themeManager.colorScheme == .dark ? Color(hex: "#EBEBF5").opacity(0.4) : Color(hex: "#C7C7CC")
    }
    
    var textColor: Color {
        themeManager.colorScheme == .dark ? Color.white : Color(hex: "#1C1C1E")
    }
    
    var fieldBackgroundColor: Color {
        themeManager.colorScheme == .dark ? Color(hex: "#1C1C1E") : Color.white
    }
    
    var borderColor: Color {
        focusedField == fieldType ? 
            Color(hex: "#4A7C59") : 
            (themeManager.colorScheme == .dark ? Color(hex: "#38383A") : Color(hex: "#E5E5E7"))
    }
    
    var shadowColor: Color {
        focusedField == fieldType ? 
            Color(hex: "#4A7C59").opacity(0.1) : 
            (themeManager.colorScheme == .dark ? Color.clear : Color.black.opacity(0.05))
    }
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 20)
            
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 16))
                        .foregroundColor(placeholderColor)
                }
                
                if isSecure {
                    SecureField("", text: $text)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(textColor)
                        .keyboardType(keyboardType)
                        .focused($focusedField, equals: fieldType)
                        .submitLabel(fieldType == .email ? .next : .go)
                        .onSubmit {
                            if fieldType == .email {
                                focusedField = .password
                            }
                        }
                        .accentColor(Color(hex: "#4A7C59"))
                } else {
                    TextField("", text: $text)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(textColor)
                        .keyboardType(keyboardType)
                        .focused($focusedField, equals: fieldType)
                        .submitLabel(fieldType == .email ? .next : .go)
                        .onSubmit {
                            if fieldType == .email {
                                focusedField = .password
                            }
                        }
                        .accentColor(Color(hex: "#4A7C59"))
                }
            }
            
            if showPasswordToggle {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPasswordVisible.toggle()
                    }
                }) {
                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(iconColor)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(fieldBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(borderColor, lineWidth: focusedField == fieldType ? 2 : 1)
                )
                .shadow(
                    color: shadowColor,
                    radius: focusedField == fieldType ? 8 : 2,
                    x: 0,
                    y: focusedField == fieldType ? 4 : 1
                )
        )
        .padding(.horizontal, 24)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: focusedField == fieldType)
    }
}

// MARK: - Social Login Button Component
struct SocialLoginButton: View {
    let title: String
    let icon: String
    let backgroundColor: Color
    let foregroundColor: Color
    var hasBorder: Bool = false
    var borderColor: Color = Color.clear
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
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(backgroundColor)
                    .overlay(
                        hasBorder ? 
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(borderColor, lineWidth: 1) :
                            nil
                    )
                    .shadow(
                        color: backgroundColor == .black ? Color.black.opacity(0.2) : Color.black.opacity(0.05),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
            )
        }
        .scaleEffect(1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: backgroundColor)
    }
}

// MARK: - Helper Functions
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
