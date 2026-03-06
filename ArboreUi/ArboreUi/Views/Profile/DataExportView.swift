import SwiftUI
import FirebaseAuth

struct DataExportView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    @State private var isExporting = false
    @State private var exportError: String? = nil
    @State private var exportSuccess = false
    @State private var exportedData: String? = nil

    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(themeManager.secondaryTextColor)
                    }
                    Spacer()
                }
                .padding()

                ScrollView {
                    VStack(spacing: 24) {
                        // Icon
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 100, height: 100)

                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.blue)
                        }
                        .padding(.top, 20)

                        // Title
                        Text(NSLocalizedString("DATA_EXPORT_TITLE", comment: "Download My Data"))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(themeManager.textColor)
                            .multilineTextAlignment(.center)

                        // Description
                        VStack(alignment: .leading, spacing: 16) {
                            Text(NSLocalizedString("DATA_EXPORT_DESCRIPTION", comment: "Export all your data"))
                                .font(.system(size: 16))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Your export will include:")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(themeManager.textColor)

                                ExportInfoRow(icon: "person.fill", text: "Account information (name, email)", color: .green)
                                ExportInfoRow(icon: "leaf.fill", text: "All your gardens and plants", color: .green)
                                ExportInfoRow(icon: "checkmark.shield.fill", text: "Privacy consent history", color: .blue)
                                ExportInfoRow(icon: "calendar.badge.clock", text: "Timestamps and metadata", color: .orange)
                            }
                            .padding()
                            .background(themeManager.textColor.opacity(0.05))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)

                        // Success message
                        if exportSuccess {
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.green)

                                Text("Export successful!")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.green)

                                Text("Your data has been saved to your device")
                                    .font(.system(size: 14))
                                    .foregroundColor(themeManager.secondaryTextColor)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        // Error message
                        if let error = exportError {
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                                .padding(.horizontal)
                        }

                        // Export button
                        Button(action: { Task { await exportData() } }) {
                            HStack(spacing: 12) {
                                if isExporting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "square.and.arrow.down.fill")
                                        .font(.system(size: 18, weight: .bold))
                                    Text(exportSuccess ? "Export Again" : "Download My Data")
                                        .font(.system(size: 17, weight: .bold))
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color.blue,
                                        Color.blue.opacity(0.8)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(14)
                            .shadow(color: Color.blue.opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        .disabled(isExporting)
                        .padding(.horizontal)
                        .padding(.top, 8)

                        // GDPR info
                        Text("This feature is part of your GDPR rights (Article 20 - Data Portability)")
                            .font(.system(size: 12))
                            .foregroundColor(themeManager.secondaryTextColor.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 40)
                    }
                }
            }
        }
    }

    private func exportData() async {
        isExporting = true
        exportError = nil
        exportSuccess = false

        guard let token = await getFirebaseToken() else {
            exportError = "Failed to get authentication token"
            isExporting = false
            return
        }

        let endpoint = "\(AppConfig.baseURL)/users/export"

        guard let url = URL(string: endpoint) else {
            exportError = "Invalid URL"
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
                // Save JSON to device
                let fileName = "arbore_data_export_\(ISO8601DateFormatter().string(from: Date())).json"
                saveToDocuments(data: data, fileName: fileName)

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

    private func saveToDocuments(data: Data, fileName: String) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
            print("✅ Data saved to: \(fileURL.path)")

            // Share the file
            DispatchQueue.main.async {
                shareFile(url: fileURL)
            }
        } catch {
            print("❌ Error saving file: \(error)")
            exportError = "Failed to save file: \(error.localizedDescription)"
        }
    }

    private func shareFile(url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

struct ExportInfoRow: View {
    let icon: String
    let text: String
    let color: Color

    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 24)

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(themeManager.textColor)

            Spacer()
        }
    }
}

#Preview {
    DataExportView()
        .environmentObject(ThemeManager())
}
