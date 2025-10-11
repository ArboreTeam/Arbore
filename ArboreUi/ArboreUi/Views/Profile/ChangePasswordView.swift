import SwiftUI

struct ChangePasswordView: View {
    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    
    var body: some View {
        ZStack {
            Color(hex: "#1A1A1A")
                .ignoresSafeArea()
            
            VStack(alignment: .leading) {
                Text("Change Password")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.top, 20)
                    .padding(.horizontal)
                
                List {
                    Section(header: Text("Current Password").foregroundColor(.white.opacity(0.7))) {
                        SecureField("Enter current password", text: $currentPassword)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color(hex: "#2A2A2A"))
                    
                    Section(header: Text("New Password").foregroundColor(.white.opacity(0.7))) {
                        SecureField("Enter new password", text: $newPassword)
                            .foregroundColor(.white)
                        SecureField("Confirm new password", text: $confirmPassword)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color(hex: "#2A2A2A"))
                    
                    Section {
                        Button(action: {
                            // Logic to change password
                        }) {
                            Text("Update Password")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: "#263826"))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .padding()
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color(hex: "#1A1A1A"))
            }
        }
    }
}
