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

            // La raison du premier échec, affichée telle quelle. Sur un appareil
            // TestFlight la console n'est pas lisible : sans ça, 271 refus
            // ressemblent à « Failed: 271 » et la cause reste invisible.
            var premiereRaison: String?

            for (index, plantID) in plantIDs.enumerated() {
                do {
                    try await uploadThumbnail(plantID: plantID, token: token)
                    uploaded += 1
                } catch {
                    failed += 1
                    if premiereRaison == nil {
                        premiereRaison = (error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription
                    }
                    print("❌ Upload thumbnail failed for \(plantID):", error)
                }

                generationProgress = "Uploading \(index + 1)/\(plantIDs.count)... OK: \(uploaded), Failed: \(failed)"
                if let premiereRaison {
                    generationProgress += "\n\(premiereRaison)"
                }
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

                // Le délai annoncé par le serveur, pas un délai deviné.
                //
                // Le limiteur rend un en-tête `Retry-After` qui dit exactement
                // quand la fenêtre se réouvre. L'attente en `attempt * 2`
                // secondes ne dépassait jamais six secondes, là où une fenêtre
                // d'une minute en demande jusqu'à soixante : les trois essais
                // se consommaient dans la même fenêtre fermée, et la vignette
                // était perdue alors qu'attendre aurait suffi.
                let attente = (error as? ThumbnailUploadError)?.attenteConseillee
                    ?? Double(attempt * 2)
                generationProgress = "Retry \(attempt + 1)/\(Self.uploadRetryCount) "
                    + "dans \(Int(attente.rounded())) s : \(plantID)"
                try await Task.sleep(nanoseconds: UInt64(attente * 1_000_000_000))
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

        let (data, response) = try await Self.uploadSession.upload(for: request, fromFile: uploadFileURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError("Upload failed for \(plantID)")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let entete = httpResponse.value(forHTTPHeaderField: "Retry-After")
            throw ThumbnailUploadError(plantID: plantID,
                                       statusCode: httpResponse.statusCode,
                                       corps: Self.messageServeur(data),
                                       retryAfter: entete.flatMap(Double.init))
        }
    }

    /// Message d'erreur rendu par le backend, s'il en rend un.
    ///
    /// `uploadPlantThumbnail` répond en JSON `{error, code}` ; on retient les
    /// deux, le code étant le seul qui distingue un refus de rôle d'un refus de
    /// cadence. Un corps non-JSON est tronqué plutôt que jeté : un reverse proxy
    /// peut répondre en HTML, et la première ligne suffit à le reconnaître.
    private nonisolated static func messageServeur(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let message = objet["error"] as? String
            let code = objet["code"] as? String
            switch (message, code) {
            case let (m?, c?): return "\(m) [\(c)]"
            case let (m?, nil): return m
            case let (nil, c?): return c
            default: break
            }
        }
        return String(decoding: data.prefix(200), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// Réduction déléguée à `ReductionVignette`, partagée avec la génération
    /// hors app (#524) : les deux chemins doivent produire le même gabarit.
    private nonisolated static func optimizedPNGData(for fileURL: URL) throws -> Data {
        try ReductionVignette.reduire(fichier: fileURL)
    }

    private nonisolated static func isRetryableUploadError(_ error: Error) -> Bool {
        if let refus = error as? ThumbnailUploadError {
            return refus.estReessayable
        }

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

/// Échec d'un envoi de vignette, avec de quoi le diagnostiquer sur l'appareil.
///
/// Le cas qui a motivé ce type : 271 refus d'affilée sur la build interne, tous
/// des 403, invisibles parce que l'erreur ne portait que le nom de la plante.
/// Le code HTTP est ce qui sépare « ce compte n'est pas administrateur » de
/// « tu envoies trop vite », et les deux se corrigent différemment.
struct ThumbnailUploadError: LocalizedError {
    let plantID: String
    let statusCode: Int
    let corps: String?
    /// Secondes annoncées par l'en-tête `Retry-After`, quand le serveur en rend un.
    let retryAfter: Double?

    init(plantID: String, statusCode: Int, corps: String?, retryAfter: Double? = nil) {
        self.plantID = plantID
        self.statusCode = statusCode
        self.corps = corps
        self.retryAfter = retryAfter
    }

    /// Combien attendre avant de réessayer. Borné : un `Retry-After` aberrant
    /// — ou hostile — ne doit pas figer l'envoi pendant des heures.
    var attenteConseillee: Double? {
        guard let retryAfter, retryAfter.isFinite, retryAfter > 0 else { return nil }
        return min(retryAfter + 1, 90)
    }

    var errorDescription: String? {
        var texte = "HTTP \(statusCode) — \(plantID)"
        if let corps, !corps.isEmpty {
            texte += " : \(corps)"
        }
        if let indice = Self.indice(pour: statusCode) {
            texte += "\n\(indice)"
        }
        return texte
    }

    private static func indice(pour code: Int) -> String? {
        switch code {
        case 401:
            return "Jeton Firebase refusé — reconnecte-toi."
        case 403:
            return "Ce compte n'a pas le rôle administrateur. "
                + "Son UID Firebase doit figurer dans ARBORE_ADMIN_UIDS côté serveur, "
                + "ou porter la revendication admin."
        case 413:
            return "Vignette trop lourde pour la limite du serveur."
        case 429:
            return "Cadence trop élevée : l'envoi réessaie de lui-même."
        default:
            return nil
        }
    }

    /// Vaut-il la peine de réessayer ? Une cadence et une panne passagère, oui ;
    /// un refus de rôle, non — il se répéterait à l'identique 51 fois.
    var estReessayable: Bool {
        statusCode == 429 || (500...599).contains(statusCode)
    }
}

#Preview {
    DebugThumbnailGeneratorView()
}

#endif
