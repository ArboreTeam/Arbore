// filepath: /Users/hugomichel/Documents/Arbore/ArboreUi/ArboreUi/Views/Profile/CloseAccountView.swift
import SwiftUI
import FirebaseAuth

struct CloseAccountView: View {
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @EnvironmentObject var themeManager: ThemeManager // Ajout de themeManager
    @Environment(\.dismiss) var dismiss
    @State private var deletionError: String?
    @State private var needsReAuth = false

    var body: some View {
        ZStack {
            // Fond sombre du thème
            themeManager.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with close button - Uniforme
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text("Close Account")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) { // Augmentation de l'espacement

                        // Header (Mise à jour des couleurs et coins)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "trash.circle.fill")
                                    .font(.system(size: 48)) // Plus grande
                                    .foregroundColor(.red)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Close Account")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundColor(themeManager.textColor)
                                    Text("This action is permanent and cannot be undone.")
                                        .font(.system(size: 13))
                                        .foregroundColor(themeManager.secondaryTextColor)
                                }
                            }
                        }
                        .padding(18) // Rembourrage uniforme
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.gray.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        )
                        .cornerRadius(18)


                        // Bannière d'avertissement (Mise à jour des couleurs et coins)
                        VStack(alignment: .leading, spacing: 10) { // Augmentation de l'espacement
                            HStack(alignment: .top, spacing: 12) { // Augmentation de l'espacement
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 20)) // Plus grande
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Warning")
                                        .font(.system(size: 17, weight: .bold)) // Plus audacieux
                                        .foregroundColor(.white)
                                    Text("Closing your account will permanently delete all your data and linked content.")
                                        .foregroundColor(.white.opacity(0.95))
                                        .font(.system(size: 14)) // Plus grand
                                }
                                Spacer(minLength: 0)
                            }

                            Text("For security, you must re-enter your email and password before we proceed.")
                                .foregroundColor(.white.opacity(0.9))
                                .font(.system(size: 13)) // Plus grand
                                .padding(.top, 4)
                        }
                        .padding(18) // Rembourrage uniforme
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.red.opacity(0.40)) // Fond plus lisible
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.15), lineWidth: 1))
                        )
                        .cornerRadius(18)

                        // Conséquences (liste avec icônes) (Mise à jour des coins et couleurs)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                Image(systemName: "list.bullet.rectangle.fill")
                                    .foregroundColor(themeManager.textColor)
                                Text("What will happen")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(themeManager.textColor)
                                Spacer()
                            }
                            
                            VStack(alignment: .leading, spacing: 14) {
                                ConsequenceRow(icon: "person.crop.circle.badge.minus",
                                                 text: "Your profile, preferences and backups will be deleted.", iconColor: .orange)
                                ConsequenceRow(icon: "photo.fill.on.rectangle.fill", // Nouvelle icône
                                                 text: "Uploaded content (e.g. plant scans) will be permanently removed.", iconColor: .yellow)
                                ConsequenceRow(icon: "lock.fill",
                                                 text: "You'll be signed out on all devices.", iconColor: .red)
                                ConsequenceRow(icon: "cloud.slash.fill", // Nouvelle icône
                                                 text: "Cloud sync will be disabled and data erased from our servers.", iconColor: .blue)
                            }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.gray.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        )
                        .cornerRadius(18)

                        // Zone d'action (Mise à jour des coins et du bouton)
                        VStack(alignment: .leading, spacing: 16) { // Augmentation de l'espacement
                            Text("Ready to close your account?")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(themeManager.textColor)

                            Button(action: { needsReAuth = true }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 18, weight: .bold))
                                    Text("Close My Account")
                                        .font(.system(size: 18, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16) // Plus de rembourrage
                                .background(
                                    RoundedRectangle(cornerRadius: 14) // Coins uniformes
                                        .fill(Color.red)
                                )
                                .shadow(color: Color.red.opacity(0.5), radius: 10, x: 0, y: 6)
                            }
                            .buttonStyle(.plain)

                            if let deletionError = deletionError {
                                Text("❌ \(deletionError)")
                                    .foregroundColor(.red)
                                    .font(.system(size: 13))
                                    .padding(.top, 4)
                            }

                            // Lien secondaire
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(themeManager.secondaryTextColor.opacity(0.8))
                                Text("Changed your mind? You can cancel anytime before confirming.")
                                    .foregroundColor(themeManager.secondaryTextColor.opacity(0.8))
                                    .font(.system(size: 13))
                            }
                            .padding(.top, 4)
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.gray.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        )
                        .cornerRadius(18)

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            
            // Re-auth écran plein
            .fullScreenCover(isPresented: $needsReAuth) {
                ReAuthView(onSuccess: {
                    needsReAuth = false
                    deleteAccount()
                })
            }
        }
        .interactiveDismissDisabled()
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

// MARK: - UI helpers (Mise à jour pour inclure la couleur des icônes)
private struct ConsequenceRow: View {
    let icon: String
    let text: String
    let iconColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) { // Augmentation de l'espacement
            Image(systemName: icon)
                .foregroundColor(iconColor) // Utiliser une couleur d'icône distincte
                .font(.system(size: 18, weight: .semibold)) // Plus grand
                .frame(width: 24)
            Text(text)
                .foregroundColor(.white.opacity(0.9))
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
