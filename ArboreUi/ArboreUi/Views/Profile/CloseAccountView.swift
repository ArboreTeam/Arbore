import SwiftUI
import FirebaseAuth

struct CloseAccountView: View {
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @State private var deletionError: String?
    @State private var needsReAuth = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#1A1A1A")
                    .ignoresSafeArea()
                
                VStack(alignment: .leading) {
                    Text("Close Account")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.white)
                        .padding(.top, 20)
                        .padding(.horizontal)

                    List {
                        Section(header: Text("Warning").foregroundColor(.red)) {
                            Text("Closing your account will permanently delete all your data. This action cannot be undone.")
                                .foregroundColor(.red)
                            Text("For security reasons, you need to re-enter your email and password before we can proceed with account deletion.")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.footnote)
                                .padding(.top, 4)
                        }
                        .listRowBackground(Color(hex: "#2A2A2A"))

                        Section {
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
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                            .padding()

                            if let deletionError = deletionError {
                                Text("❌ \(deletionError)")
                                    .foregroundColor(.red)
                                    .font(.footnote)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color(hex: "#1A1A1A"))
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
    
    private func deleteAccount() {
        guard let user = Auth.auth().currentUser else { return }
        
        user.delete { error in
            if let error = error {
                self.deletionError = error.localizedDescription
                return
            }
            
            isLoggedIn = false
        }
    }
}
