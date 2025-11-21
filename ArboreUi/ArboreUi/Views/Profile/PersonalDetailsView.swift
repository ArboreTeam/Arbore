import SwiftUI

struct PersonalDetailsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var fullName: String = "Hugo Michel"
    @State private var phoneNumber: String = ""
    @State private var email: String = ""
    @State private var address: String = ""
    
    var body: some View {
        ZStack {
            themeManager.backgroundColor
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
                    Text("Personal Details")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor) // Assurer un fond uni pour la barre

                // ScrollView content
                ScrollView {
                    VStack(spacing: 24) { // Augmentation de l'espacement pour l'aération

                        // Full Name
                        inputField(title: "FULL NAME", placeholder: "Full Name", text: $fullName)
                        
                        // Phone Number
                        inputField(title: "PHONE NUMBER", placeholder: "Phone Number", text: $phoneNumber, keyboardType: .phonePad)
                        
                        // Email
                        inputField(title: "EMAIL", placeholder: "Email", text: $email, keyboardType: .emailAddress)
                        
                        // Address
                        inputField(title: "ADDRESS", placeholder: "Address", text: $address)
                        
                        Spacer()
                        
                        // Save Button (Style vert et audacieux)
                        Button(action: { dismiss() }) {
                            Text("Save Changes")
                                .font(.system(size: 17, weight: .bold)) // Plus audacieux
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16) // Plus de rembourrage
                                .background(
                                    RoundedRectangle(cornerRadius: 14) // Coins plus arrondis
                                        .fill(Color.green) // Couleur verte principale
                                )
                                .shadow(color: Color.green.opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .padding(.vertical, 20)
                }
            }
        }
        .interactiveDismissDisabled()
    }
    
    // MARK: - Input Field (Refonte pour un style plus professionnel/glassmorphism)
    private func inputField(title: String, placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(themeManager.secondaryTextColor)
                .padding(.horizontal, 4) // Légèrement indenter l'étiquette
            
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
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
        .padding(.horizontal, 16)
    }
}

#Preview {
    PersonalDetailsView()
        .environmentObject(ThemeManager())
}
