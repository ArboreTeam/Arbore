import SwiftUI
import FirebaseAuth
import GoogleSignIn
import GoogleSignInSwift

struct ReAuthView: View {
    var onSuccess: () -> Void

    @Environment(\.dismiss) var dismiss
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @StateObject private var authViewModel = AuthenticationView()

    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var errorMessage = ""
    @State private var isLoading = false

    @FocusState private var focusedField: Field?

    enum Field {
        case email, password
    }

    var isFormValid: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedEmail.isEmpty && !trimmedPassword.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "#F1F5ED"), Color(hex: "#EAF1E7")]),
                    startPoint: .top,
                    endPoint: .bottom
                ).ignoresSafeArea()
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }

                if isLoading {
                    ProgressView("Reauthenticating...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                } else {
                    ScrollView {
                        VStack(spacing: 25) {
                            HStack {
                                Button(action: { dismiss() }) {
                                    Image(systemName: "chevron.left")
                                        .font(.title2)
                                        .foregroundColor(.black)
                                        .padding()
                                }
                                Spacer()
                            }

                            VStack(spacing: 8) {
                                Text("Re-authenticate")
                                    .font(.system(size: 42, weight: .bold, design: .serif))
                                    .foregroundColor(Color(hex: "#2D3E30"))

                                Text("For security reasons, please confirm your identity by entering your login information again. If you registered using Google or Apple, please use the same option below.")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }

                            VStack(spacing: 14) {
                                emailField
                                passwordField
                            }
                            .padding(.horizontal, 30)

                            Button(action: reauthenticate) {
                                Text("Confirm Deletion")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(isFormValid ? Color.red : Color.red.opacity(0.4))
                                    .cornerRadius(10)
                            }
                            .disabled(!isFormValid)
                            .padding(.horizontal, 30)

                            VStack(spacing: 12) {
                                Button(action: {
                                    // Apple sign-in logic to be implemented
                                }) {
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

                                Button(action: handleGoogleDeletion) {
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
                            }
                            .padding(.horizontal, 30)

                            if !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .foregroundColor(.red)
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 30)
                            }
                        }
                        .padding(.top, 20)
                    }
                }
            }
        }
    }

    var emailField: some View {
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
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            .submitLabel(.next)
            .onSubmit { focusedField = .password }
    }

    var passwordField: some View {
        ZStack(alignment: .trailing) {
            Group {
                if isPasswordVisible {
                    TextField("", text: $password)
                        .placeholder(when: password.isEmpty) {
                            Text("Password").foregroundColor(.gray)
                        }
                        .focused($focusedField, equals: .password)
                } else {
                    SecureField("", text: $password)
                        .placeholder(when: password.isEmpty) {
                            Text("Password").foregroundColor(.gray)
                        }
                        .focused($focusedField, equals: .password)
                }
            }
            .foregroundColor(.black)
            .padding()
            .background(Color.white)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            .submitLabel(.go)
            .onSubmit { reauthenticate() }

            Button(action: { isPasswordVisible.toggle() }) {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    .resizable()
                    .frame(width: 18, height: 18)
                    .foregroundColor(.gray)
                    .padding(.trailing, 12)
            }
        }
    }

    func reauthenticate() {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "User not logged in."
            return
        }

        isLoading = true
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let credential = EmailAuthProvider.credential(withEmail: trimmedEmail, password: trimmedPassword)

        user.reauthenticate(with: credential) { _, error in
            if let error = error {
                DispatchQueue.main.async {
                    isLoading = false
                    errorMessage = "Incorrect email or password."
                }
                return
            }

            user.delete { error in
                if let error = error {
                    DispatchQueue.main.async {
                        isLoading = false
                        errorMessage = "Error deleting Firebase account: \(error.localizedDescription)"
                    }
                    return
                }

                deleteUserFromMongo(uid: user.uid) {
                    DispatchQueue.main.async {
                        isLoading = false
                        isLoggedIn = false
                        UIApplication.shared.windows.first?.rootViewController = UIHostingController(rootView: LoginView())
                    }
                }
            }
        }
    }

    func handleGoogleDeletion() {
        authViewModel.reauthenticateWithGoogle { success in
            DispatchQueue.main.async {
                if success, let user = Auth.auth().currentUser {
                    user.delete { error in
                        if let error = error {
                            errorMessage = "Error deleting Firebase account: \(error.localizedDescription)"
                            return
                        }

                        deleteUserFromMongo(uid: user.uid) {
                            isLoggedIn = false
                            UIApplication.shared.windows.first?.rootViewController = UIHostingController(rootView: LoginView())
                        }
                    }
                } else {
                    errorMessage = "Google re-authentication failed."
                }
            }
        }
    }
}
