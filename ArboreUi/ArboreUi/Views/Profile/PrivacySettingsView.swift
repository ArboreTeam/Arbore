import SwiftUI
import FirebaseAuth

struct PrivacySettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    // Consentements persistés localement avec AppStorage
    @AppStorage("privacy_profilePublic") internal var profilePublic: Bool = true
    @AppStorage("privacy_showActivity") internal var showActivity: Bool = true
    @AppStorage("privacy_shareData") internal var shareData: Bool = false

    @State internal var showPrivacyPolicy: Bool = false
    @State internal var isSyncing: Bool = false
    @State internal var hasLoadedFromBackend: Bool = false

    var body: some View {
        ZStack {
            themeManager.backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text(NSLocalizedString("PRIVACYSETTINGS_TITLE", comment: ""))
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
                            Text(NSLocalizedString("PRIVACYSETTINGS_HEADER_TITLE", comment: ""))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(themeManager.textColor)

                            Text(NSLocalizedString("PRIVACYSETTINGS_HEADER_SUBTITLE", comment: ""))
                                .font(.system(size: 15))
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        .padding(.top, 18)

                        // Profile Visibility
                        PrivacySectionCard(
                            title: NSLocalizedString("PRIVACYSETTINGS_SECTION_PROFILE", comment: ""),
                            icon: "person.crop.circle.fill",
                            content: {
                                ToggleRow(
                                    icon: "globe.europe.africa.fill",
                                    title: NSLocalizedString("PRIVACYSETTINGS_PUBLICPROFILE_TITLE", comment: ""),
                                    subtitle: NSLocalizedString("PRIVACYSETTINGS_PUBLICPROFILE_SUB", comment: ""),
                                    isOn: $profilePublic
                                )
                                .onChange(of: profilePublic) { _, newValue in
                                    recordConsentChange(type: "profilePublic", granted: newValue)
                                }
                            },
                            themeManager: themeManager
                        )

                        // Activity Sharing
                        PrivacySectionCard(
                            title: NSLocalizedString("PRIVACYSETTINGS_SECTION_ACTIVITY", comment: ""),
                            icon: "waveform.path.ecg.rectangle.fill",
                            content: {
                                ToggleRow(
                                    icon: "list.bullet.rectangle.portrait",
                                    title: NSLocalizedString("PRIVACYSETTINGS_ACTIVITY_TITLE", comment: ""),
                                    subtitle: NSLocalizedString("PRIVACYSETTINGS_ACTIVITY_SUB", comment: ""),
                                    isOn: $showActivity
                                )
                                .onChange(of: showActivity) { _, newValue in
                                    recordConsentChange(type: "showActivity", granted: newValue)
                                }
                            },
                            themeManager: themeManager
                        )

                        // Data Sharing
                        PrivacySectionCard(
                            title: NSLocalizedString("PRIVACYSETTINGS_SECTION_DATASHARING", comment: ""),
                            icon: "chart.bar.doc.horizontal.fill",
                            content: {
                                ToggleRow(
                                    icon: "chart.bar.doc.horizontal.fill",
                                    title: NSLocalizedString("PRIVACYSETTINGS_DATASHARING_TITLE", comment: ""),
                                    subtitle: NSLocalizedString("PRIVACYSETTINGS_DATASHARING_SUB", comment: ""),
                                    isOn: $shareData
                                )
                                .onChange(of: shareData) { _, newValue in
                                    recordConsentChange(type: "analytics", granted: newValue)
                                }
                            },
                            themeManager: themeManager
                        )

                        // Link to Privacy Policy
                        Button(action: { showPrivacyPolicy = true }) {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.green)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(NSLocalizedString("PRIVACYSETTINGS_READ_POLICY", comment: ""))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(themeManager.textColor)

                                    Text(NSLocalizedString("PRIVACYSETTINGS_READ_POLICY_SUB", comment: ""))
                                        .font(.system(size: 13))
                                        .foregroundColor(themeManager.secondaryTextColor)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(themeManager.secondaryTextColor.opacity(0.7))
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.gray.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        )
                        .cornerRadius(18)
                        .buttonStyle(.plain)

                        // Info note
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("PRIVACYSETTINGS_NOTE_TITLE", comment: ""))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(themeManager.textColor)

                            Text(NSLocalizedString("PRIVACYSETTINGS_NOTE_TEXT", comment: ""))
                                .font(.system(size: 13))
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.gray.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        )
                        .cornerRadius(18)

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .fullScreenCover(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
                .environmentObject(themeManager)
                .interactiveDismissDisabled()
        }
        .onAppear {
            if !hasLoadedFromBackend {
                loadConsentsFromBackend()
                hasLoadedFromBackend = true
            }
        }
    }

    // MARK: - Consent Management

    /// Enregistre localement la modification d'un consentement avec horodatage
    internal func recordConsentChange(type: String, granted: Bool) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let key = "consent_\(type)_lastChanged"

        // Sauvegarder la date de dernière modification
        UserDefaults.standard.set(timestamp, forKey: key)

        // Sauvegarder l'historique (pour traçabilité RGPD)
        var history = UserDefaults.standard.array(forKey: "consent_history") as? [[String: String]] ?? []
        history.append([
            "type": type,
            "granted": String(granted),
            "timestamp": timestamp,
            "version": AppConfig.privacyPolicyVersion
        ])
        UserDefaults.standard.set(history, forKey: "consent_history")

        print("✅ Consent recorded: \(type) = \(granted) at \(timestamp)")

        syncConsentToBackend(type: type, granted: granted, timestamp: timestamp)
    }

    /// Synchronisation avec le backend (POST /consents)
    internal func syncConsentToBackend(type: String, granted: Bool, timestamp: String) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("⚠️ No user logged in, skipping backend sync")
            return
        }

        let consentData: [String: Any] = [
            "uid": uid,
            "consentType": type,
            "granted": granted,
            "version": AppConfig.privacyPolicyVersion,
            "timestamp": timestamp
        ]

        guard let url = URL(string: AppConfig.consentsEndpoint) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: consentData)
        } catch {
            print("❌ Error serializing consent data: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Error syncing consent to backend: \(error)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 {
                print("✅ Consent synced to backend successfully")
            } else {
                print("⚠️ Backend sync returned non-201 status")
            }
        }.resume()
    }

    /// Charge les consentements depuis le backend au démarrage (synchronisation multi-appareils)
    internal func loadConsentsFromBackend() {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("⚠️ No user logged in, skipping backend load")
            return
        }

        guard let url = URL(string: "\(AppConfig.consentsEndpoint)/\(uid)/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("⚠️ Error loading consents from backend: \(error)")
                return
            }

            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("⚠️ Backend returned non-200 status when loading consents")
                return
            }

            do {
                // Le backend retourne {"uid": "...", "consents": [...]}
                let response = try JSONDecoder().decode(BackendConsentsResponse.self, from: data)

                DispatchQueue.main.async {
                    for consent in response.consents {
                        switch consent.consentType {
                            case "profilePublic":
                                self.profilePublic = consent.granted
                            case "showActivity":
                                self.showActivity = consent.granted
                            case "analytics":
                                self.shareData = consent.granted
                            default:
                                break
                        }
                    }
                    print("✅ Consents loaded from backend: \(response.consents.count) items")
                }
            } catch {
                print("❌ Error decoding consents: \(error)")
            }
        }.resume()
    }
}

// MARK: - Backend Consent Models
struct BackendConsent: Codable {
    let consentType: String
    let granted: Bool
    let timestamp: String
    let version: String
}

struct BackendConsentsResponse: Codable {
    let uid: String
    let consents: [BackendConsent]
}

// MARK: - Section Card
private struct PrivacySectionCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    let themeManager: ThemeManager

    init(title: String, icon: String, @ViewBuilder content: () -> Content, themeManager: ThemeManager) {
        self.title = title
        self.icon = icon
        self.content = content()
        self.themeManager = themeManager
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.green)

                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(themeManager.textColor)

                Spacer()
            }

            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.gray.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
        .cornerRadius(18)
    }
}

// MARK: - Toggle Row
private struct ToggleRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.textColor)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(themeManager.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.green)
        }
    }
}
