import SwiftUI
import FirebaseAuth

struct CloseAccountView: View {
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @State private var deletionError: String?
    @State private var needsReAuth = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                Text("Close Account")
                    .font(.largeTitle)
                    .bold()
                    .padding(.top, 20)
                    .padding(.horizontal)

                List {
                    Section(header: Text("Warning")) {
                        Text("Closing your account will permanently delete all your data. This action cannot be undone.")
                            .foregroundColor(.red)
                        Text("For security reasons, you need to re-enter your email and password before we can proceed with account deletion.")
                            .foregroundColor(.primary)
                            .font(.footnote)
                            .padding(.top, 4)
                    }

                    Button(action: {
                        needsReAuth = true
                    }) {
                        Text("Close My Account")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding()

                    if let deletionError = deletionError {
                        Text("❌ \(deletionError)")
                            .foregroundColor(.red)
                            .font(.footnote)
                            .padding(.horizontal)
                    }
                }
            }
            .fullScreenCover(isPresented: $needsReAuth) {
                ReAuthView(onSuccess: {
                    needsReAuth = false
                    deleteAccount()
                })
            }
        }
    }
}
