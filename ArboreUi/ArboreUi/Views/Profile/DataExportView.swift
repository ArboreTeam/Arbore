import SwiftUI
import FirebaseAuth

struct DataExportView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    @State private var isExporting = false
    @State private var exportError: String? = nil
    @State private var exportSuccess = false
    @State private var exportedData: String? = nil
    @State private var exportedFileURL: URL? = nil
    @State private var showShareSheet = false

    var body: some View {
        SettingsPage(title: NSLocalizedString("DATA_EXPORT_TITLE", comment: "Download My Data")) {
            SettingsIntroCard(
                systemImage: "square.and.arrow.down",
                title: NSLocalizedString("DATA_EXPORT_TITLE", comment: "Download My Data"),
                message: NSLocalizedString("DATA_EXPORT_DESCRIPTION", comment: "Export all your data")
            )

            SettingsSectionCard(
                title: L10n.t("DATA_EXPORT_INCLUDE_TITLE"),
                systemImage: "doc.zipper"
            ) {
                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                    ExportInfoRow(icon: "person", text: L10n.t("DATA_EXPORT_INCLUDE_ACCOUNT"))
                    SettingsDivider()
                    ExportInfoRow(icon: "leaf", text: L10n.t("DATA_EXPORT_INCLUDE_GARDENS"))
                    SettingsDivider()
                    ExportInfoRow(icon: "checkmark.shield", text: L10n.t("DATA_EXPORT_INCLUDE_PRIVACY"))
                    SettingsDivider()
                    ExportInfoRow(icon: "calendar.badge.clock", text: L10n.t("DATA_EXPORT_INCLUDE_METADATA"))
                }
            }

            if exportSuccess, let fileURL = exportedFileURL {
                AppCard {
                    VStack(spacing: ArboreDesign.Spacing.md) {
                        SettingsIconBadge(
                            systemImage: "checkmark.circle",
                            tint: ArboreDesign.Colors.success,
                            size: 56
                        )

                        Text(L10n.t("DATA_EXPORT_SUCCESS"))
                            .font(ArboreDesign.Typography.cardTitle)
                            .foregroundColor(ArboreDesign.Colors.textPrimary)

                        ShareLink(item: fileURL) {
                            Label(L10n.t("DATA_EXPORT_SHARE_FILE"), systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.arboreSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if let error = exportError {
                AppCard {
                    SettingsInfoRow(
                        systemImage: "exclamationmark.triangle",
                        title: error,
                        tint: ArboreDesign.Colors.danger
                    )
                }
            }

            Button(action: { Task { await exportData() } }) {
                HStack(spacing: ArboreDesign.Spacing.xs) {
                    if isExporting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "square.and.arrow.down")
                        Text(exportSuccess ? L10n.t("DATA_EXPORT_AGAIN") : L10n.t("DATA_EXPORT_DOWNLOAD"))
                    }
                }
            }
            .disabled(isExporting)
            .buttonStyle(AppButtonStyle(variant: .primary, isEnabled: !isExporting))

            Text(L10n.t("DATA_EXPORT_GDPR_NOTE"))
                .font(ArboreDesign.Typography.caption)
                .foregroundColor(ArboreDesign.Colors.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func exportData() async {
        isExporting = true
        exportError = nil
        exportSuccess = false

        guard let token = await getFirebaseToken() else {
            exportError = L10n.t("DATA_EXPORT_TOKEN_ERROR")
            isExporting = false
            return
        }

        let endpoint = "\(AppConfig.baseURL)/users/export"

        guard let url = URL(string: endpoint) else {
            exportError = L10n.t("DATA_EXPORT_INVALID_URL")
            isExporting = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                exportError = "Invalid response from server"
                isExporting = false
                return
            }

            if httpResponse.statusCode == 200 {
                let fileName = "arbore_data_export_\(ISO8601DateFormatter().string(from: Date())).json"
                if let fileURL = saveToDocuments(data: data, fileName: fileName) {
                    exportedFileURL = fileURL
                }
                exportSuccess = true
                exportError = nil
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                exportError = "Export failed: \(errorMessage)"
            }
        } catch {
            exportError = "Network error: \(error.localizedDescription)"
        }

        isExporting = false
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

    @discardableResult
    private func saveToDocuments(data: Data, fileName: String) -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL)
            print("✅ Data saved to: \(fileURL.path)")
            return fileURL
        } catch {
            print("❌ Error saving file: \(error)")
            exportError = "Failed to save file: \(error.localizedDescription)"
            return nil
        }
    }
}

struct ExportInfoRow: View {
    let icon: String
    let text: String

    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        SettingsInfoRow(systemImage: icon, title: text)
    }
}

#Preview {
    DataExportView()
        .environmentObject(ThemeManager())
}
