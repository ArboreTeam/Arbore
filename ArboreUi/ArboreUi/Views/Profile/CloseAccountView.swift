// filepath: /Users/hugomichel/Documents/Arbore/ArboreUi/ArboreUi/Views/Profile/CloseAccountView.swift
import SwiftUI
import FirebaseAuth

struct CloseAccountView: View {
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @Environment(\.dismiss) var dismiss
    @State private var deletionError: String?
    @State private var needsReAuth = false

    var body: some View {
        ZStack {
            // Fond sombre légèrement texturé (gradient subtil)
            LinearGradient(
                colors: [Color(hex: "#111314"), Color(hex: "#171A1A")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with close button
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text("Close Account")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(LinearGradient(
                    colors: [Color(hex: "#111314"), Color(hex: "#171A1A")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "trash.circle.fill")
                                    .font(.system(size: 42))
                                    .foregroundColor(.red)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Close Account")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundColor(.white)
                                    Text("This action is permanent and cannot be undone.")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08), lineWidth: 1))

                        // Bannière d'avertissement
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Warning")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text("Closing your account will permanently delete all your data and linked content.")
                                        .foregroundColor(.white.opacity(0.95))
                                        .font(.system(size: 13))
                                }
                                Spacer(minLength: 0)
                            }

                            Text("For security, you must re-enter your email and password before we proceed.")
                                .foregroundColor(.white.opacity(0.9))
                                .font(.system(size: 12))
                                .padding(.top, 2)
                        }
                        .padding(16)
                        .background(
                            LinearGradient(
                                colors: [Color.red.opacity(0.45), Color.red.opacity(0.30)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.10), lineWidth: 1))

                        // Conséquences (liste avec icônes)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "list.bullet.rectangle.fill")
                                    .foregroundColor(.white)
                                Text("What will happen")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                ConsequenceRow(icon: "person.crop.circle.badge.minus",
                                               text: "Your profile, preferences and backups will be deleted.")
                                ConsequenceRow(icon: "photo.on.rectangle",
                                               text: "Uploaded content (e.g. plant scans) will be permanently removed.")
                                ConsequenceRow(icon: "lock.fill",
                                               text: "You'll be signed out on all devices.")
                                ConsequenceRow(icon: "icloud.slash.fill",
                                               text: "Cloud sync will be disabled and data erased from our servers.")
                            }
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08), lineWidth: 1))

                        // Zone d'action
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Ready to close your account?")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)

                            Button(action: { needsReAuth = true }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 16, weight: .bold))
                                    Text("Close My Account")
                                        .font(.system(size: 16, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.red)
                                )
                                .shadow(color: Color.red.opacity(0.35), radius: 12, x: 0, y: 6)
                            }
                            .buttonStyle(.plain)

                            if let deletionError = deletionError {
                                Text("❌ \(deletionError)")
                                    .foregroundColor(.red)
                                    .font(.system(size: 12))
                                    .padding(.top, 2)
                            }

                            // Lien secondaire
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.white.opacity(0.7))
                                Text("Changed your mind? You can cancel anytime before confirming.")
                                    .foregroundColor(.white.opacity(0.7))
                                    .font(.system(size: 12))
                            }
                            .padding(.top, 2)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08), lineWidth: 1))

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

// MARK: - UI helpers
private struct ConsequenceRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.white.opacity(0.9))
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22)
            Text(text)
                .foregroundColor(.white.opacity(0.9))
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}