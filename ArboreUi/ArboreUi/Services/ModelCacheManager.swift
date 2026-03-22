import Foundation

/// Gère le téléchargement et le cache des modèles 3D USDZ depuis le backend
actor ModelCacheManager {
    static let shared = ModelCacheManager()

    private let cacheDirectory: URL
    private var downloadTasks: [String: Task<URL, Error>] = [:]

    private init() {
        // Créer le dossier de cache dans Documents/Models
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheDirectory = documentsURL.appendingPathComponent("Models", isDirectory: true)

        // Créer le dossier s'il n'existe pas
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Obtient l'URL locale d'un modèle (le télécharge si nécessaire)
    /// - Parameters:
    ///   - modelURL: Le nom du fichier du modèle (ex: "Monstera_Deliciosa.usdz")
    ///   - forceDownload: Si true, forcer un nouveau téléchargement même si un cache existe
    /// - Returns: L'URL locale du fichier téléchargé
    func getModelURL(for modelURL: String, forceDownload: Bool = false) async throws -> URL {
        guard !modelURL.isEmpty else {
            throw ModelCacheError.invalidModelURL
        }

        // Extraire le nom du fichier
        let filename = (modelURL as NSString).lastPathComponent
        let localURL = cacheDirectory.appendingPathComponent(filename)

        let fileExists = FileManager.default.fileExists(atPath: localURL.path)

        // Chemin forcé : on ignore la lecture cache et on tente un nouveau download
        if forceDownload {
            if fileExists {
                // Supprimer pour éviter un conflit de moveItem plus tard (best-effort)
                try? FileManager.default.removeItem(at: localURL)
                print("♻️ Forced re-download, cache cleared for: \(filename)")
            }
        } else if fileExists {
            print("✅ Model found in cache: \(filename)")
            return localURL
        }

        let taskKey = forceDownload ? "force:\(filename)" : filename
        if forceDownload {
            print("⬇️ Forcing download for: \(filename)")
        }

        // Vérifier si un téléchargement est déjà en cours pour ce modèle
        if let existingTask = downloadTasks[taskKey] {
            print("⏳ Download already in progress for: \(filename)")
            return try await existingTask.value
        }

        // Créer une nouvelle tâche de téléchargement
        let task = Task<URL, Error> {
            try await downloadModel(filename: filename, to: localURL)
        }

        downloadTasks[taskKey] = task

        do {
            let result = try await task.value
            downloadTasks[taskKey] = nil
            return result
        } catch {
            downloadTasks[taskKey] = nil
            throw error
        }
    }

    /// Télécharge un modèle depuis le backend
    private func downloadModel(filename: String, to localURL: URL) async throws -> URL {
        print("⬇️ Downloading model: \(filename)")

        // Construire l'URL du backend
        guard let backendURL = URL(string: "\(NetworkManager.shared.baseURL)/models/\(filename)") else {
            throw ModelCacheError.invalidBackendURL
        }

        // Créer la requête avec authentification
        var request = URLRequest(url: backendURL)
        request.setValue(NetworkManager.shared.apiKey, forHTTPHeaderField: "X-API-Key")

        // Ajouter le token Firebase si disponible
        if let token = try? await NetworkManager.shared.getFirebaseToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Télécharger le fichier
        let (tempURL, response) = try await URLSession.shared.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelCacheError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ModelCacheError.httpError(statusCode: httpResponse.statusCode)
        }

        // Déplacer le fichier temporaire vers le cache
        try FileManager.default.moveItem(at: tempURL, to: localURL)

        print("✅ Model downloaded successfully: \(filename)")
        return localURL
    }

    /// Supprime un modèle du cache
    func removeModel(filename: String) throws {
        let localURL = cacheDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
            print("🗑️ Model removed from cache: \(filename)")
        }
    }

    /// Supprime tous les modèles du cache
    func clearCache() throws {
        let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        for file in files {
            try FileManager.default.removeItem(at: file)
        }
        print("🗑️ Cache cleared")
    }

    /// Retourne la taille totale du cache en bytes
    func getCacheSize() throws -> Int64 {
        let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
        var totalSize: Int64 = 0

        for file in files {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            if let size = attributes[.size] as? Int64 {
                totalSize += size
            }
        }

        return totalSize
    }
}

// MARK: - Errors

enum ModelCacheError: LocalizedError {
    case invalidModelURL
    case invalidBackendURL
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidModelURL:
            return "Invalid model URL"
        case .invalidBackendURL:
            return "Invalid backend URL"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        }
    }
}
