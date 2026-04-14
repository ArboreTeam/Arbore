import SwiftUI
import FirebaseAuth
import GoogleSignIn

struct CloseAccountView: View {
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var deletionError: String?
    @State private var needsReAuth = false

    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text(NSLocalizedString("CLOSE_ACCOUNT_TITLE", comment: ""))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "trash.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.red)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("CLOSE_ACCOUNT_TITLE", comment: ""))
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundColor(themeManager.textColor)

                                    Text(NSLocalizedString("CLOSE_ACCOUNT_SUBTITLE", comment: ""))
                                        .font(.system(size: 13))
                                        .foregroundColor(themeManager.secondaryTextColor)
                                }
                            }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.gray.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.separatorColor.opacity(0.3), lineWidth: 1))
                        )
                        .cornerRadius(18)

                        // Warning Banner
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 20))

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(NSLocalizedString("CLOSE_ACCOUNT_WARNING_TITLE", comment: ""))
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.white)

                                    Text(NSLocalizedString("CLOSE_ACCOUNT_WARNING_TEXT", comment: ""))
                                        .foregroundColor(.white.opacity(0.95))
                                        .font(.system(size: 14))
                                }
                            }

                            Text(NSLocalizedString("CLOSE_ACCOUNT_WARNING_REAUTH", comment: ""))
                                .foregroundColor(.white.opacity(0.9))
                                .font(.system(size: 13))
                                .padding(.top, 4)
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.red.opacity(0.40))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.15), lineWidth: 1))
                        )
                        .cornerRadius(18)

                        // What will happen
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                Image(systemName: "list.bullet.rectangle.fill")
                                    .foregroundColor(themeManager.textColor)
                                Text(NSLocalizedString("CLOSE_ACCOUNT_WHAT_HAPPENS_TITLE", comment: ""))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(themeManager.textColor)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 14) {
                                ConsequenceRow(
                                    icon: "person.crop.circle.badge.minus",
                                    text: NSLocalizedString("CLOSE_ACCOUNT_CONSEQUENCE_PROFILE", comment: ""),
                                    iconColor: .orange
                                )

                                ConsequenceRow(
                                    icon: "photo.fill.on.rectangle.fill",
                                    text: NSLocalizedString("CLOSE_ACCOUNT_CONSEQUENCE_UPLOADS", comment: ""),
                                    iconColor: .yellow
                                )

                                ConsequenceRow(
                                    icon: "lock.fill",
                                    text: NSLocalizedString("CLOSE_ACCOUNT_CONSEQUENCE_SIGNOUT", comment: ""),
                                    iconColor: .red
                                )

                                ConsequenceRow(
                                    icon: "icloud.slash.fill",
                                    text: NSLocalizedString("CLOSE_ACCOUNT_CONSEQUENCE_CLOUD", comment: ""),
                                    iconColor: .blue
                                )
                            }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.gray.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.separatorColor.opacity(0.3), lineWidth: 1))
                        )
                        .cornerRadius(18)

                        // Final action
                        VStack(alignment: .leading, spacing: 16) {
                            Text(NSLocalizedString("CLOSE_ACCOUNT_READY_TITLE", comment: ""))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(themeManager.textColor)

                            Button(action: { needsReAuth = true }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 18, weight: .bold))
                                    Text(NSLocalizedString("CLOSE_ACCOUNT_BUTTON", comment: ""))
                                        .font(.system(size: 18, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.red)
                                )
                                .shadow(color: Color.red.opacity(0.5), radius: 10, x: 0, y: 6)
                            }
                            .buttonStyle(.plain)

                            if let deletionError = deletionError {
                                Text("❌ \(deletionError)")
                                    .foregroundColor(.red)
                                    .font(.system(size: 13))
                            }

                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(themeManager.secondaryTextColor.opacity(0.8))

                                Text(NSLocalizedString("CLOSE_ACCOUNT_CANCEL_HINT", comment: ""))
                                    .foregroundColor(themeManager.secondaryTextColor.opacity(0.8))
                                    .font(.system(size: 13))
                            }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.gray.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.separatorColor.opacity(0.3), lineWidth: 1))
                        )
                        .cornerRadius(18)

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }

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
        Task {
            await performCompleteAccountDeletion()
        }
    }

    private func performCompleteAccountDeletion() async {
        guard let user = Auth.auth().currentUser else {
            deletionError = "User not authenticated"
            return
        }

        // 1. Get Firebase token
        guard let token = await getFirebaseToken() else {
            deletionError = "Failed to get authentication token"
            return
        }

        // 2. Call backend to delete all MongoDB data
        let endpoint = "\(AppConfig.baseURL)/users"
        guard let url = URL(string: endpoint) else {
            deletionError = "Invalid URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                deletionError = "Invalid response from server"
                return
            }

            if httpResponse.statusCode != 200 {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                deletionError = "Backend deletion failed: \(errorMessage)"
                return
            }

            // 3. Clean local data
            cleanLocalData()

            // 4. Delete Firebase Auth account
            do {
                // Sign out from Google and Firebase first so tokens don't linger.
                // Without this, a subsequent Google sign-in reuses the stale token
                // against the now-deleted Firebase account, causing a crash.
                GIDSignIn.sharedInstance.signOut()
                try? Auth.auth().signOut()

                try await user.delete()

                // 5. Dismiss all UIKit-presented VCs (CloseAccountView, ReAuthView, etc.)
                //    before flipping isLoggedIn. If we flip first, SwiftUI replaces
                //    MainView() while UIKit still holds those VCs as "presented" —
                //    any GIDSignIn call immediately after would land on a zombie VC.
                DispatchQueue.main.async {
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController,
                       rootVC.presentedViewController != nil {
                        rootVC.dismiss(animated: false) {
                            self.isLoggedIn = false
                        }
                    } else {
                        self.isLoggedIn = false
                    }
                }
            } catch {
                deletionError = "Failed to delete Firebase account: \(error.localizedDescription)"
            }

        } catch {
            deletionError = "Network error: \(error.localizedDescription)"
        }
    }

    private func getFirebaseToken() async -> String? {
        guard let user = Auth.auth().currentUser else { return nil }

        do {
            let token = try await user.getIDToken()
            return token
        } catch {
            print("Error getting Firebase token: \(error)")
            return nil
        }
    }

    private func cleanLocalData() {
        // Clean UserDefaults - all privacy and consent data
        let defaults = UserDefaults.standard

        // Remove privacy settings
        defaults.removeObject(forKey: "privacy_profilePublic")
        defaults.removeObject(forKey: "privacy_showActivity")
        defaults.removeObject(forKey: "privacy_shareData")

        // Remove consent history
        defaults.removeObject(forKey: "consent_history")

        // Remove all consent timestamps
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys {
            if key.hasPrefix("consent_") || key.hasPrefix("privacy_") {
                defaults.removeObject(forKey: key)
            }
        }

        // Clean FileManager cache (if exists)
        // Note: PlantThumbnailCache needs to be implemented if you have image caching

        defaults.synchronize()

        // Remove AR scene files from Documents/ so the "Jardin" tab
        // (ManageGardenView → GardenLocalStorageService) no longer lists
        // orphan scenes from the deleted account.
        cleanLocalSceneFiles()

        print("✅ Local data cleaned")
    }

    private func cleanLocalSceneFiles() {
        let fm = FileManager.default
        guard let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        do {
            let fileURLs = try fm.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            var removed = 0
            for url in fileURLs where url.lastPathComponent.hasPrefix("scene_") {
                try? fm.removeItem(at: url)
                removed += 1
            }
            print("🧹 Removed \(removed) local scene file(s)")
        } catch {
            print("⚠️ Failed to scan documents directory for scene files: \(error)")
        }
    }
}

// MARK: - Consequence row

private struct ConsequenceRow: View {
    let icon: String
    let text: String
    let iconColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 24)

            Text(text)
                .foregroundColor(.white.opacity(0.9))
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
