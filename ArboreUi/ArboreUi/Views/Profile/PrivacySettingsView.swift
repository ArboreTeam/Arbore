import SwiftUI
import FirebaseAuth

struct PrivacySettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    // Consentements persistés localement avec AppStorage. Défauts = source unique
    // ConsentDefaults (privacy-by-default, RGPD Art. 25 — issue #218). Ces défauts
    // ne s'appliquent qu'aux clés absentes : les choix déjà faits par un utilisateur
    // existant sont préservés.
    @AppStorage("privacy_profilePublic") internal var profilePublic: Bool = ConsentDefaults.profilePublic
    @AppStorage("privacy_showActivity") internal var showActivity: Bool = ConsentDefaults.showActivity
    @AppStorage("privacy_shareData") internal var shareData: Bool = ConsentDefaults.analytics
    @AppStorage("privacy_marketing") internal var marketingConsent: Bool = ConsentDefaults.marketing
    @AppStorage("privacy_camera") internal var cameraConsent: Bool = ConsentDefaults.camera
    @AppStorage("privacy_ai") internal var aiConsent: Bool = ConsentDefaults.ai
    @AppStorage("privacy_notifications") internal var notificationsConsent: Bool = ConsentDefaults.notifications

    @State internal var showPrivacyPolicy: Bool = false
    @State internal var isSyncing: Bool = false
    @State internal var hasLoadedFromBackend: Bool = false

    var body: some View {
        SettingsPage(title: NSLocalizedString("PRIVACYSETTINGS_TITLE", comment: "")) {
            SettingsIntroCard(
                systemImage: "hand.raised",
                title: NSLocalizedString("PRIVACYSETTINGS_HEADER_TITLE", comment: ""),
                message: NSLocalizedString("PRIVACYSETTINGS_HEADER_SUBTITLE", comment: "")
            )

            SettingsSectionCard(
                title: NSLocalizedString("PRIVACYSETTINGS_SECTION_PROFILE", comment: ""),
                systemImage: "person.crop.circle"
            ) {
                SettingsToggleRow(
                    systemImage: "globe.europe.africa",
                    title: NSLocalizedString("PRIVACYSETTINGS_PUBLICPROFILE_TITLE", comment: ""),
                    subtitle: NSLocalizedString("PRIVACYSETTINGS_PUBLICPROFILE_SUB", comment: ""),
                    isOn: $profilePublic
                )
                .onChange(of: profilePublic) { _, newValue in
                    recordConsentChange(type: "profilePublic", granted: newValue)
                }
            }

            SettingsSectionCard(
                title: NSLocalizedString("PRIVACYSETTINGS_SECTION_ACTIVITY", comment: ""),
                systemImage: "waveform.path.ecg.rectangle"
            ) {
                SettingsToggleRow(
                    systemImage: "list.bullet.rectangle.portrait",
                    title: NSLocalizedString("PRIVACYSETTINGS_ACTIVITY_TITLE", comment: ""),
                    subtitle: NSLocalizedString("PRIVACYSETTINGS_ACTIVITY_SUB", comment: ""),
                    isOn: $showActivity
                )
                .onChange(of: showActivity) { _, newValue in
                    recordConsentChange(type: "showActivity", granted: newValue)
                }
            }

            SettingsSectionCard(
                title: NSLocalizedString("PRIVACYSETTINGS_SECTION_DATASHARING", comment: ""),
                systemImage: "chart.bar.doc.horizontal"
            ) {
                SettingsToggleRow(
                    systemImage: "chart.bar.doc.horizontal",
                    title: NSLocalizedString("PRIVACYSETTINGS_DATASHARING_TITLE", comment: ""),
                    subtitle: NSLocalizedString("PRIVACYSETTINGS_DATASHARING_SUB", comment: ""),
                    isOn: $shareData
                )
                .onChange(of: shareData) { _, newValue in
                    recordConsentChange(type: "analytics", granted: newValue)
                    // Ce toggle gouverne le crash reporting Sentry : on démarre /
                    // coupe le SDK selon le consentement diagnostic (issue #226).
                    SentryManager.updateConsent(granted: newValue, uid: Auth.auth().currentUser?.uid)
                }
            }

            SettingsSectionCard(
                title: NSLocalizedString("PRIVACYSETTINGS_SECTION_MARKETING", comment: ""),
                systemImage: "envelope"
            ) {
                SettingsToggleRow(
                    systemImage: "megaphone",
                    title: NSLocalizedString("PRIVACYSETTINGS_MARKETING_TITLE", comment: ""),
                    subtitle: NSLocalizedString("PRIVACYSETTINGS_MARKETING_SUB", comment: ""),
                    isOn: $marketingConsent
                )
                .onChange(of: marketingConsent) { _, newValue in
                    recordConsentChange(type: "marketing", granted: newValue)
                }
            }

            SettingsSectionCard(
                title: NSLocalizedString("PRIVACYSETTINGS_SECTION_CAMERA", comment: ""),
                systemImage: "camera"
            ) {
                SettingsToggleRow(
                    systemImage: "arkit",
                    title: NSLocalizedString("PRIVACYSETTINGS_CAMERA_TITLE", comment: ""),
                    subtitle: NSLocalizedString("PRIVACYSETTINGS_CAMERA_SUB", comment: ""),
                    isOn: $cameraConsent
                )
                .onChange(of: cameraConsent) { _, newValue in
                    recordConsentChange(type: "camera", granted: newValue)
                }
            }

            SettingsSectionCard(
                title: NSLocalizedString("PRIVACYSETTINGS_SECTION_AI", comment: ""),
                systemImage: "brain.head.profile",
                tint: ArboreDesign.Colors.accentGold
            ) {
                SettingsToggleRow(
                    systemImage: "sparkles",
                    title: NSLocalizedString("PRIVACYSETTINGS_AI_TITLE", comment: ""),
                    subtitle: NSLocalizedString("PRIVACYSETTINGS_AI_SUB", comment: ""),
                    isOn: $aiConsent,
                    tint: ArboreDesign.Colors.accentGold
                )
                .onChange(of: aiConsent) { _, newValue in
                    recordConsentChange(type: "ai", granted: newValue)
                }
            }

            SettingsSectionCard(
                title: NSLocalizedString("PRIVACYSETTINGS_SECTION_NOTIFICATIONS", comment: ""),
                systemImage: "bell"
            ) {
                SettingsToggleRow(
                    systemImage: "bell.badge",
                    title: NSLocalizedString("PRIVACYSETTINGS_NOTIFICATIONS_TITLE", comment: ""),
                    subtitle: NSLocalizedString("PRIVACYSETTINGS_NOTIFICATIONS_SUB", comment: ""),
                    isOn: $notificationsConsent
                )
                .onChange(of: notificationsConsent) { _, newValue in
                    recordConsentChange(type: "notifications", granted: newValue)
                }
            }

            Button(action: { showPrivacyPolicy = true }) {
                SettingsRow(
                    systemImage: "doc.text",
                    title: NSLocalizedString("PRIVACYSETTINGS_READ_POLICY", comment: ""),
                    subtitle: NSLocalizedString("PRIVACYSETTINGS_READ_POLICY_SUB", comment: "")
                )
            }
            .buttonStyle(.plain)

            SettingsSectionCard(
                title: NSLocalizedString("PRIVACYSETTINGS_NOTE_TITLE", comment: ""),
                systemImage: "info.circle"
            ) {
                Text(NSLocalizedString("PRIVACYSETTINGS_NOTE_TEXT", comment: ""))
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        guard Auth.auth().currentUser != nil else {
            print("⚠️ No user logged in, skipping backend sync")
            return
        }

        Task {
            do {
                // Le UID n'est plus envoyé dans le body - il vient du token Firebase
                let consentData: [String: Any] = [
                    "consentType": type,
                    "granted": granted,
                    "version": AppConfig.privacyPolicyVersion,
                    "timestamp": timestamp
                ]

                try await NetworkManager.shared.requestNoResponse(
                    endpoint: "/consents",
                    method: .POST,
                    body: consentData
                )

                print("✅ Consent synced to backend successfully")
            } catch {
                print("❌ Error syncing consent to backend: \(error)")
            }
        }
    }

    /// Charge les consentements depuis le backend au démarrage (synchronisation multi-appareils)
    internal func loadConsentsFromBackend() {
        guard Auth.auth().currentUser != nil else {
            print("⚠️ No user logged in, skipping backend load")
            return
        }

        Task {
            do {
                // Le UID n'est plus dans l'URL - il vient du token Firebase
                let response: BackendConsentsResponse = try await NetworkManager.shared.request(
                    endpoint: "/consents/latest",
                    method: .GET
                )

                await MainActor.run {
                    if let consents = response.consents {
                        for consent in consents {
                            switch consent.consentType {
                            case "profilePublic":
                                self.profilePublic = consent.granted
                            case "showActivity":
                                self.showActivity = consent.granted
                            case "analytics":
                                self.shareData = consent.granted
                            case "marketing":
                                self.marketingConsent = consent.granted
                            case "camera":
                                self.cameraConsent = consent.granted
                            case "ai":
                                self.aiConsent = consent.granted
                            case "notifications":
                                self.notificationsConsent = consent.granted
                            default:
                                break
                            }
                        }
                        print("✅ Consents loaded from backend: \(consents.count) items")
                    } else {
                        print("ℹ️ No consents found in backend (first time user)")
                    }
                }
            } catch {
                print("⚠️ Error loading consents from backend: \(error)")
            }
        }
    }
}
