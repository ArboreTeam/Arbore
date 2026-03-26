import SwiftUI
import UIKit

#if DEBUG

@MainActor
struct DebugThumbnailGeneratorView: View {
    @StateObject private var generator = PlantThumbnailGenerator()
    @State private var plants: [Plant] = []
    @State private var isLoading = false
    @State private var selectedPlants: Set<String> = []
    @State private var generationProgress = ""
    @State private var showFileExportInfo = false
    @State private var isUploading = false

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                // Header
                VStack(spacing: 8) {
                    Text("🔧 Debug Thumbnail Generator")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text("⚠️ Dev/Admin only - Hidden in production")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)

                // Status Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plants: \(plants.count)")
                        .font(.caption)
                    Text("With Thumbnails: \(plants.filter { PlantThumbnailCache.exists(for: $0.id) }.count)")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Missing: \(plants.filter { !PlantThumbnailCache.exists(for: $0.id) }.count)")
                        .font(.caption)
                        .foregroundColor(.orange)
                    if !generationProgress.isEmpty {
                        Text(generationProgress)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)

                // Action Buttons
                VStack(spacing: 8) {
                    Button(action: generateAllMissing) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Generate Missing Thumbnails")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(plants.filter { !PlantThumbnailCache.exists(for: $0.id) }.isEmpty)

                    Button(action: { showFileExportInfo = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Thumbnails to Files")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }

                    Button(action: uploadCachedToBackend) {
                        HStack {
                            Image(systemName: "icloud.and.arrow.up")
                            Text(isUploading ? "Uploading..." : "Upload Cached Thumbnails to Backend")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(isUploading || plants.filter { PlantThumbnailCache.exists(for: $0.id) }.isEmpty)

                    Button(action: copyFirebaseTokenToClipboard) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copy Firebase ID Token")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.purple.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }

                    Button(action: cacheClear) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear All Cached Thumbnails")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.red.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal)

                // Plant List
                List {
                    ForEach(plants) { plant in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plant.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(plant.id)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            if PlantThumbnailCache.exists(for: plant.id) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("✓")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.orange)
                                    Text("✗")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Thumbnail Debug")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadPlants()
                // Monitor generation
                generator.onThumbnailGenerated = {
                    generationProgress = "Generated at \(Date().formatted(date: .omitted, time: .standard))"
                }
            }
            .alert("Thumbnails Location", isPresented: $showFileExportInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(
                    "Generated PNGs are in iOS app cache:\n\n" +
                    "Library/Caches/PlantThumbs/\n\n" +
                    "Use Xcode File Inspector or macOS Finder to export."
                )
            }
        }
    }

    private func loadPlants() {
        Task {
            isLoading = true
            do {
                let allPlants = try await loadAllPlants()
                self.plants = allPlants.sorted { $0.name < $1.name }
            } catch {
                print("❌ Failed to load plants:", error)
            }
            isLoading = false
        }
    }

    private func generateAllMissing() {
        let missing = plants.filter { !PlantThumbnailCache.exists(for: $0.id) }
        print("🎬 Starting generation of \(missing.count) thumbnails...")
        generationProgress = "Generating \(missing.count) thumbnails..."
        generator.enqueue(plants: missing)
    }

    private func cacheClear() {
        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlantThumbs", isDirectory: true)

        try? FileManager.default.removeItem(at: cacheDir)
        generationProgress = "Cache cleared"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            loadPlants()
        }
    }

    private func uploadCachedToBackend() {
        Task {
            isUploading = true

            let cachedPlants = plants.filter { PlantThumbnailCache.exists(for: $0.id) }
            generationProgress = "Uploading 0/\(cachedPlants.count)..."

            var uploaded = 0
            var failed = 0

            for (index, plant) in cachedPlants.enumerated() {
                do {
                    try await uploadThumbnail(plantID: plant.id)
                    uploaded += 1
                } catch {
                    failed += 1
                    print("❌ Upload thumbnail failed for \(plant.id):", error)
                }

                generationProgress = "Uploading \(index + 1)/\(cachedPlants.count)..."
            }

            generationProgress = "Upload done. Success: \(uploaded), Failed: \(failed)"
            isUploading = false
        }
    }

    private func uploadThumbnail(plantID: String) async throws {
        guard let image = PlantThumbnailCache.load(for: plantID),
              let pngData = image.pngData() else {
            throw NetworkError.serverError("Missing local thumbnail for \(plantID)")
        }

        guard let url = URL(string: NetworkManager.shared.baseURL + "/models/thumbnails/\(plantID)") else {
            throw NetworkError.invalidURL
        }

        let token = try await NetworkManager.shared.getFirebaseToken()
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(NetworkManager.shared.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"thumbnail\"; filename=\"\(plantID).png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(pngData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError("Upload failed for \(plantID)")
        }
    }

    private func copyFirebaseTokenToClipboard() {
        Task {
            do {
                let token = try await NetworkManager.shared.getFirebaseToken()
                UIPasteboard.general.string = token
                generationProgress = "Firebase ID token copied"
            } catch {
                generationProgress = "Token copy failed"
                print("❌ Failed to copy Firebase ID token:", error)
            }
        }
    }

    private func loadAllPlants() async throws -> [Plant] {
        return try await NetworkManager.shared.request(
            endpoint: "/plants",
            method: .GET
        )
    }
}

#Preview {
    DebugThumbnailGeneratorView()
}

#endif
