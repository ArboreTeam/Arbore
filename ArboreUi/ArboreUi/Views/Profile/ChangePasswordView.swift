import SwiftUI

struct ChangePasswordView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""

    var body: some View {
        ZStack {
            themeManager.backgroundColor // Utiliser le thème manager
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar - Uniforme
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text("Change Password")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor) // Assurer un fond uni pour la barre

                // Content
                ScrollView {
                    VStack(spacing: 24) { // Augmentation de l'espacement
                        
                        // Current Password
                        secureInputField(title: "CURRENT PASSWORD", placeholder: "Enter current password", text: $currentPassword)

                        // New Passwords
                        VStack(alignment: .leading, spacing: 16) {
                            Text("NEW PASSWORD")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .padding(.horizontal, 4)
                            
                            secureInputFieldContent(placeholder: "Enter new password", text: $newPassword)
                            secureInputFieldContent(placeholder: "Confirm new password", text: $confirmPassword)
                        }
                        .padding(.horizontal, 16)

                        Spacer(minLength: 8)

                        // Update Button (Style vert et audacieux)
                        Button(action: {
                            // Logic to change password
                            dismiss()
                        }) {
                            Text("Update Password")
                                .font(.system(size: 17, weight: .bold)) // Plus audacieux
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16) // Plus de rembourrage
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.green) // Couleur verte principale
                                )
                                .shadow(color: Color.green.opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .padding(.top, 20)
                }
            }
        }
        .interactiveDismissDisabled()
    }
    
    // MARK: - Secure Input Field (Refonte pour un style plus professionnel/glassmorphism)
    private func secureInputField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(themeManager.secondaryTextColor)
                .padding(.horizontal, 4)
            
            secureInputFieldContent(placeholder: placeholder, text: text)
        }
        .padding(.horizontal, 16)
    }
    
    private func secureInputFieldContent(placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.gray.opacity(0.12)) // Fond en verre-morphisme subtil
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1) // Bordure légère
                    )
            )
            .foregroundColor(themeManager.textColor)
    }
}

#Preview {
    ChangePasswordView()
        .environmentObject(ThemeManager())
}
