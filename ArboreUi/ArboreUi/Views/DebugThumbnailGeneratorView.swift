import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

#if DEBUG

@MainActor
struct DebugThumbnailGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var generator = PlantThumbnailGenerator()
    @State private var plants: [Plant] = []
    @State private var cachedPlantIDs: [String] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var generationProgress = ""
    @State private var showFileExportInfo = false
    @State private var isUploading = false

    private static let uploadMaxPixelSize = 900
    private static let uploadRetryCount = 3
    private static let uploadSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 900
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 1
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private var missingPlants: [Plant] {
        let cachedIDs = Set(cachedPlantIDs)
        return plants.filter { !cachedIDs.contains($0.id) }
    }

    private var canGenerateMissing: Bool {
        !isLoading && !missingPlants.isEmpty
    }

    private var canUploadCached: Bool {
        !isUploading && !cachedPlantIDs.isEmpty
    }

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
                    Text(isLoading ? "Loading plants..." : "Catalogue plants: \(plants.count)")
                        .font(.caption)
                    Text("Cached PNGs: \(cachedPlantIDs.count)")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text(plants.isEmpty ? "Missing: -" : "Missing: \(missingPlants.count)")
                        .font(.caption)
                        .foregroundColor(.orange)
                    if let loadError {
                        Text(loadError)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                    .disabled(!canGenerateMissing)

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
                    .disabled(!canUploadCached)

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
                    if plants.isEmpty && !cachedPlantIDs.isEmpty {
                        Section("Cached thumbnails") {
                            ForEach(cachedPlantIDs, id: \.self) { plantID in
                                cachedThumbnailRow(plantID: plantID)
                            }
                        }
                    } else {
                        ForEach(plants) { plant in
                            plantRow(plant, hasThumbnail: cachedPlantIDs.contains(plant.id))
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Thumbnail Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: loadPlants) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("Reload")
                }
            }
            .onAppear {
                refreshCacheState()
                loadPlants()
                // Monitor generation
                generator.onThumbnailGenerated = {
                    refreshCacheState()
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

    private func plantRow(_ plant: Plant, hasThumbnail: Bool) -> some View {
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
            thumbnailStatusIcon(hasThumbnail: hasThumbnail)
        }
        .padding(.vertical, 8)
    }

    private func cachedThumbnailRow(plantID: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cached PNG")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(plantID)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
            thumbnailStatusIcon(hasThumbnail: true)
        }
        .padding(.vertical, 8)
    }

    private func thumbnailStatusIcon(hasThumbnail: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: hasThumbnail ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(hasThumbnail ? .green : .orange)
            Text(hasThumbnail ? "✓" : "✗")
                .font(.caption)
                .foregroundColor(hasThumbnail ? .green : .orange)
        }
    }

    private func refreshCacheState() {
        cachedPlantIDs = PlantThumbnailCache.cachedPlantIDs()
    }

    private func loadPlants() {
        Task {
            isLoading = true
            loadError = nil
            refreshCacheState()
            do {
                let allPlants = try await loadAllPlants()
                self.plants = allPlants.sorted { $0.name < $1.name }
            } catch {
                loadError = "Plant list unavailable: \(error.localizedDescription)"
                print("❌ Failed to load plants:", error)
            }
            refreshCacheState()
            isLoading = false
        }
    }

    private func generateAllMissing() {
        let missing = missingPlants
        print("🎬 Starting generation of \(missing.count) thumbnails...")
        generationProgress = "Generating \(missing.count) thumbnails..."
        generator.enqueue(plants: missing)
    }

    private func cacheClear() {
        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlantThumbs", isDirectory: true)

        try? FileManager.default.removeItem(at: cacheDir)
        cachedPlantIDs = []
        generationProgress = "Cache cleared"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            loadPlants()
        }
    }

    private func uploadCachedToBackend() {
        Task {
            isUploading = true

            refreshCacheState()
            let plantIDs = cachedPlantIDs
            generationProgress = "Uploading 0/\(plantIDs.count)..."

            var uploaded = 0
            var failed = 0
            let token: String

            do {
                token = try await NetworkManager.shared.getFirebaseToken()
            } catch {
                generationProgress = "Upload failed: Firebase token unavailable"
                isUploading = false
                print("❌ Failed to get Firebase token for thumbnail upload:", error)
                return
            }

            for (index, plantID) in plantIDs.enumerated() {
                do {
                    try await uploadThumbnail(plantID: plantID, token: token)
                    uploaded += 1
                } catch {
                    failed += 1
                    print("❌ Upload thumbnail failed for \(plantID):", error)
                }

                generationProgress = "Uploading \(index + 1)/\(plantIDs.count)... OK: \(uploaded), Failed: \(failed)"
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            generationProgress = "Upload done. Success: \(uploaded), Failed: \(failed)"
            refreshCacheState()
            isUploading = false
        }
    }

    private func uploadThumbnail(plantID: String, token: String) async throws {
        let fileURL = PlantThumbnailCache.url(for: plantID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NetworkError.serverError("Missing local thumbnail for \(plantID)")
        }

        guard let url = URL(string: NetworkManager.shared.baseURL + "/models/thumbnails/\(plantID)") else {
            throw NetworkError.invalidURL
        }

        var lastError: Error?

        for attempt in 1...Self.uploadRetryCount {
            do {
                try await performThumbnailUpload(
                    plantID: plantID,
                    fileURL: fileURL,
                    endpointURL: url,
                    token: token
                )
                return
            } catch {
                lastError = error
                guard attempt < Self.uploadRetryCount, Self.isRetryableUploadError(error) else {
                    throw error
                }

                generationProgress = "Retry \(attempt + 1)/\(Self.uploadRetryCount): \(plantID)"
                try await Task.sleep(nanoseconds: UInt64(attempt * 2) * 1_000_000_000)
            }
        }

        throw lastError ?? NetworkError.serverError("Upload failed for \(plantID)")
    }

    private func performThumbnailUpload(
        plantID: String,
        fileURL: URL,
        endpointURL: URL,
        token: String
    ) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        let uploadFileURL = try await Task.detached(priority: .utility) {
            try Self.makeMultipartUploadFile(
                plantID: plantID,
                sourceFileURL: fileURL,
                boundary: boundary
            )
        }.value
        defer {
            try? FileManager.default.removeItem(at: uploadFileURL)
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue(NetworkManager.shared.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await Self.uploadSession.upload(for: request, fromFile: uploadFileURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError("Upload failed for \(plantID)")
        }
    }

    private nonisolated static func makeMultipartUploadFile(
        plantID: String,
        sourceFileURL: URL,
        boundary: String
    ) throws -> URL {
        let uploadFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(plantID)-\(UUID().uuidString).multipart", isDirectory: false)

        FileManager.default.createFile(atPath: uploadFileURL.path, contents: nil)

        let payload = try optimizedPNGData(for: sourceFileURL)
        let prefix =
            "--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"thumbnail\"; filename=\"\(plantID).png\"\r\n" +
            "Content-Type: image/png\r\n\r\n"
        let suffix = "\r\n--\(boundary)--\r\n"

        let output = try FileHandle(forWritingTo: uploadFileURL)
        defer {
            try? output.close()
        }

        output.write(Data(prefix.utf8))
        output.write(payload)
        output.write(Data(suffix.utf8))

        return uploadFileURL
    }

    private nonisolated static func optimizedPNGData(for fileURL: URL) throws -> Data {
        try autoreleasepool {
            let fallback = { try Data(contentsOf: fileURL) }
            let sourceOptions: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]

            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions as CFDictionary) else {
                return try fallback()
            }

            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: uploadMaxPixelSize
            ]

            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                thumbnailOptions as CFDictionary
            ) else {
                return try fallback()
            }

            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else {
                return try fallback()
            }

            CGImageDestinationAddImage(destination, thumbnail, nil)
            guard CGImageDestinationFinalize(destination) else {
                return try fallback()
            }

            return data as Data
        }
    }

    private nonisolated static func isRetryableUploadError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        return [
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorDNSLookupFailed
        ].contains(nsError.code)
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
