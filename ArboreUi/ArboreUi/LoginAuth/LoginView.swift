import SwiftUI
import Firebase
import GoogleSignIn
import GoogleSignInSwift

struct LoginView: View {
    @StateObject private var authViewModel = AuthenticationView()

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
                                .transition(.opacity.combined(with: .move(edge: .top)))

                            Text("Grow with harmony")
                                .font(.system(size: 20, design: .serif))
                                .foregroundColor(Color(hex: "#2D3E30").opacity(0.7))
                                .transition(.opacity)
                        }
                        .animation(.easeOut(duration: 0.5), value: email)

                        VStack(spacing: 14) {
                            TextField("", text: $email)
                                .placeholder(when: email.isEmpty) {
                                    Text("Email").foregroundColor(.gray)
                                }
                                .focused($focusedField, equals: .email)
                                .foregroundColor(.black)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(10)
                                .tint(Color(hex: "#263826"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(focusedField == .email ? Color(hex: "#263826") : Color.gray.opacity(0.3), lineWidth: 1)
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
                                                Text("Password").foregroundColor(.gray)
                                            }
                                            .submitLabel(.go)
                                            .onSubmit { loginUser() }
                                    } else {
                                        SecureField("", text: $password)
                                            .focused($focusedField, equals: .password)
                                            .placeholder(when: password.isEmpty) {
                                                Text("Password").foregroundColor(.gray)
                                            }
                                            .submitLabel(.go)
                                            .onSubmit { loginUser() }
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
                                        .animation(.easeInOut(duration: 0.2), value: focusedField == .password)
                                )

                                Button(action: {
                                    withAnimation { isPasswordVisible.toggle() }
                                }) {
                                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                        .foregroundColor(.gray)
                                        .padding(.trailing, 12)
                                }
                            }

                            HStack {
                                Spacer()
                                Button("Forgot password?") {
                                    showReset = true
                                }
                                .padding(.trailing, 4)
                                .font(.footnote)
                                .foregroundColor(Color(hex: "#2D3E30"))
                                .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 30)
                        .transition(.move(edge: .bottom))

                        Button(action: loginUser) {
                            Text("Sign In")
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

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                                .transition(.opacity)
                        }

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
                            Text("Don’t have an account?")
                                .foregroundColor(.gray)
                            Button(action: {
                                withAnimation { showSignUp = true }
                            }) {
                                Text("Sign up")
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color(hex: "#263826"))
                            }
                        }
                        .font(.footnote)
                        .padding(.top, 8)

                        Spacer(minLength: 30)
                    }
                    .padding(.top, 40)
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
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty && !trimmedPassword.isEmpty else {
            errorMessage = "Please enter email and password."
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
                        self.errorMessage = "Incorrect email or password."
                    case "TOO_MANY_ATTEMPTS_TRY_LATER":
                        self.errorMessage = "Too many unsuccessful login attempts. Please try again later."
                    case "EMAIL_NOT_FOUND":
                        self.errorMessage = "No account found with this email."
                    default:
                        self.errorMessage = "Authentication error: \(firebaseMessage)"
                    }
                } else if let authError = AuthErrorCode(rawValue: error.code) {
                    // Cas où Firebase mappe bien l'erreur
                    switch authError {
                    case .wrongPassword:
                        self.errorMessage = "Incorrect email or password."
                    case .tooManyRequests:
                        self.errorMessage = "Too many unsuccessful login attempts. Please try again later."
                    case .userNotFound:
                        self.errorMessage = "No account found with this email."
                    default:
                        self.errorMessage = "Authentication error: \(error.localizedDescription)"
                    }
                } else {
                    self.errorMessage = "Unknown authentication error. Please try again."
                }
                return
            }

            guard let user = result?.user else { return }

            if !user.isEmailVerified {
                checkAndDeleteIfExpired(uid: user.uid)
                self.errorMessage = "Please verify your email before logging in."
                try? Auth.auth().signOut()
                return
            }

            self.isLoggedIn = true
        }
    }
}

func checkAndDeleteIfExpired(uid: String) {
    guard let url = URL(string: "http://79.137.92.154:8080/users/\(uid)") else { return }

    URLSession.shared.dataTask(with: url) { data, response, error in
        guard let data = data, error == nil else { return }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let user = try decoder.decode(User.self, from: data)

            let now = Date()
            let hoursSinceCreation = now.timeIntervalSince(user.createdAt) / 3600

            if hoursSinceCreation > 48 {
                print("🧹 Deleting expired, unverified user...")
                deleteAccount()
            } else {
                print("⏱ Account still within time window")
            }
        } catch {
            print("❌ Error decoding user from MongoDB: \(error)")
        }
    }.resume()
}

func deleteAccount() {
    guard let user = Auth.auth().currentUser else { return }

    // Supprime de Firebase
    user.delete { error in
        if let error = error {
            print("❌ Error deleting Firebase account: \(error.localizedDescription)")
            return
        }

        // Supprime de MongoDB
        if let url = URL(string: "http://79.137.92.154:8080/users/\(user.uid)") {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"

            URLSession.shared.dataTask(with: request) { _, _, _ in
                print("✅ Account deleted from MongoDB and Firebase")
            }.resume()
        }
    }
}
