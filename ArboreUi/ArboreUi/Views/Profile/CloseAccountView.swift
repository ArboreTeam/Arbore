import SwiftUI
import SwiftData
import FirebaseAuth
import GoogleSignIn

struct CloseAccountView: View {
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var deletionError: String?
    @State private var needsReAuth = false

    var body: some View {
        SettingsPage(title: NSLocalizedString("CLOSE_ACCOUNT_TITLE", comment: "")) {
            SettingsIntroCard(
                systemImage: "trash",
                title: NSLocalizedString("CLOSE_ACCOUNT_TITLE", comment: ""),
                message: NSLocalizedString("CLOSE_ACCOUNT_SUBTITLE", comment: ""),
                tint: ArboreDesign.Colors.danger
            )

            SettingsSectionCard(
                title: NSLocalizedString("CLOSE_ACCOUNT_WARNING_TITLE", comment: ""),
                systemImage: "exclamationmark.triangle",
                tint: ArboreDesign.Colors.danger
            ) {
                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
                    Text(NSLocalizedString("CLOSE_ACCOUNT_WARNING_TEXT", comment: ""))
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(NSLocalizedString("CLOSE_ACCOUNT_WARNING_REAUTH", comment: ""))
                        .font(ArboreDesign.Typography.caption)
                        .foregroundColor(ArboreDesign.Colors.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsSectionCard(
                title: NSLocalizedString("CLOSE_ACCOUNT_WHAT_HAPPENS_TITLE", comment: ""),
                systemImage: "list.bullet.rectangle"
            ) {
                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                    ConsequenceRow(
                        icon: "person.crop.circle.badge.minus",
                        text: NSLocalizedString("CLOSE_ACCOUNT_CONSEQUENCE_PROFILE", comment: "")
                    )
                    SettingsDivider()
                    ConsequenceRow(
                        icon: "photo.on.rectangle",
                        text: NSLocalizedString("CLOSE_ACCOUNT_CONSEQUENCE_UPLOADS", comment: "")
                    )
                    SettingsDivider()
                    ConsequenceRow(
                        icon: "lock",
                        text: NSLocalizedString("CLOSE_ACCOUNT_CONSEQUENCE_SIGNOUT", comment: ""),
                        iconColor: ArboreDesign.Colors.danger
                    )
                    SettingsDivider()
                    ConsequenceRow(
                        icon: "icloud.slash",
                        text: NSLocalizedString("CLOSE_ACCOUNT_CONSEQUENCE_CLOUD", comment: "")
                    )
                }
            }

            SettingsSectionCard(
                title: NSLocalizedString("CLOSE_ACCOUNT_READY_TITLE", comment: ""),
                systemImage: "trash",
                tint: ArboreDesign.Colors.danger
            ) {
                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                    Button(action: { needsReAuth = true }) {
                        HStack(spacing: ArboreDesign.Spacing.xs) {
                            Image(systemName: "trash")
                            Text(NSLocalizedString("CLOSE_ACCOUNT_BUTTON", comment: ""))
                        }
                    }
                    .buttonStyle(.arboreDanger)

                    if let deletionError = deletionError {
                        SettingsInfoRow(
                            systemImage: "exclamationmark.triangle",
                            title: deletionError,
                            tint: ArboreDesign.Colors.danger
                        )
                    }

                    HStack(spacing: ArboreDesign.Spacing.xs) {
                        Image(systemName: "questionmark.circle")
                        Text(NSLocalizedString("CLOSE_ACCOUNT_CANCEL_HINT", comment: ""))
                    }
                    .font(ArboreDesign.Typography.caption)
                    .foregroundColor(ArboreDesign.Colors.textMuted)
                }
            }
        }
        .fullScreenCover(isPresented: $needsReAuth) {
            ReAuthView(onSuccess: {
                needsReAuth = false
                deleteAccount()
            })
        }
        .interactiveDismissDisabled()
    }

    private func deleteAccount() {
        Task {
            await performCompleteAccountDeletion()
        }
    }

    private func performCompleteAccountDeletion() async {
        guard Auth.auth().currentUser != nil else {
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
		request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                deletionError = "Invalid response from server"
                return
            }

            if httpResponse.statusCode != 200 {
                deletionError = BackendErrorMessage.humanReadable(
                    from: data,
                    fallback: L10n.t("CLOSE_ACCOUNT_ERROR_GENERIC")
                )
                return
            }

            // The backend has now removed MongoDB data, the legacy community
            // records and the Firebase Auth identity. Only local state remains.
			await NotificationManager.shared.cancelAllArboreNotifications()
            cleanLocalData()

			GIDSignIn.sharedInstance.signOut()
			try? Auth.auth().signOut()
			SentryManager.clearUser()

			// Dismiss all UIKit-presented VCs before replacing the root view.
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
        let defaults = UserDefaults.standard
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys {
			if key.hasPrefix("consent_")
				|| key.hasPrefix("privacy_")
				|| key.hasPrefix("gardenPurchaseCart.")
				|| [
					"gardenProjects",
					"wateringRoutines",
					"plantCareRoutines",
					"gardenCareActions",
					"consent_history",
					"isLoggedIn"
				].contains(key) {
                defaults.removeObject(forKey: key)
            }
        }

		cleanChatData()
        cleanLocalSceneFiles()

        print("✅ Local data cleaned")
    }

	private func cleanChatData() {
		do {
			let conversations = try modelContext.fetch(FetchDescriptor<ChatConversation>())
			for conversation in conversations {
				modelContext.delete(conversation)
			}
			try modelContext.save()
		} catch {
			print("⚠️ Failed to delete local chat history: \(error)")
		}
	}

    private func cleanLocalSceneFiles() {
        let fm = FileManager.default
        guard let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        do {
            let fileURLs = try fm.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            var removed = 0
			let personalPrefixes = ["scene_", "worldmap_", "wizard_", "ar_share_captures_"]
			for url in fileURLs where personalPrefixes.contains(where: url.lastPathComponent.hasPrefix) {
				try fm.removeItem(at: url)
				removed += 1
            }
			let temporaryURLs = try fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil)
			for url in temporaryURLs where url.lastPathComponent.hasPrefix("arbore_ar_share_") {
				try? fm.removeItem(at: url)
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
    var iconColor: Color = ArboreDesign.Colors.primaryGreen

    var body: some View {
        SettingsInfoRow(
            systemImage: icon,
            title: text,
            tint: iconColor
        )
    }
}
