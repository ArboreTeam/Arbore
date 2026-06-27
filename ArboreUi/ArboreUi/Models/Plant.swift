import Foundation
import simd

// MARK: - Root Plant model

struct Plant: Identifiable, Codable {
    let id: String
    let name: String
    let type: String
    let imageURLs: [String]
    let description: String
    let modelURL: String?
    let translations: [String: PlantTranslation]   // fr / en / es / de
    let generated: Bool?   // true = modèle 3D généré par IA (Meshy), nil/false = legacy
    let upAxis: String?    // "Y" (default, nil) ou "Z" (Blender exports qui doivent être redressés)
    let source: String?    // "botanic" = plante scrapée depuis botanic.com ; nil = legacy/beta
    let sourceUrl: String? // URL botanic.com d'origine (conservée pour ré-scrape/màj)

    enum CodingKeys: String, CodingKey {
        case id
        case name, type, imageURLs, description, modelURL, translations, generated, upAxis, source, sourceUrl
    }

    // Décode avec fallback safe
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Plante inconnue"
        self.type = try container.decodeIfPresent(String.self, forKey: .type) ?? "Type inconnu"

        self.imageURLs = try container
            .decodeIfPresent([String].self, forKey: .imageURLs)?
            .filter { !$0.isEmpty }
            ?? ["https://via.placeholder.com/300x200?text=Plante"]

        self.description = try container.decodeIfPresent(String.self, forKey: .description)
            ?? "Description non disponible."

        self.modelURL = try container.decodeIfPresent(String.self, forKey: .modelURL)

        self.translations = try container.decodeIfPresent([String: PlantTranslation].self, forKey: .translations)
            ?? [:]

        self.generated = try container.decodeIfPresent(Bool.self, forKey: .generated)
        self.upAxis = try container.decodeIfPresent(String.self, forKey: .upAxis)
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
        self.sourceUrl = try container.decodeIfPresent(String.self, forKey: .sourceUrl)
    }

    // ✅ Helper pour reconstruire une plante minimale au moment du restore
    static func stubForRestore(id: String, name: String, type: String, modelURL: String) -> Plant {
        // Astuce: on encode/décode vite fait ou on fait une init privée.
        // Ici on fait une init "manuelle" via un petit hack : un JSON minimal.
        let json: [String: Any] = [
            "id": id,
            "name": name,
            "type": type,
            "imageURLs": [],
            "description": "",
            "modelURL": modelURL,
            "translations": [:]
        ]
        let data = try? JSONSerialization.data(withJSONObject: json, options: [])
        let decoded = (data.flatMap { try? JSONDecoder().decode(Plant.self, from: $0) })
        return decoded ?? PlantFallback(id: id, name: name, type: type, modelURL: modelURL).asPlant()
    }
}

// MARK: - Translations & sub-objects

struct PlantTranslation: Codable {
    let description: String
    let plantType: String
    let sun: SunInfo?
    let water: WaterInfo?
    let soilAndPot: SoilAndPotInfo?
    let health: HealthInfo?
    let lifeCycle: LifeCycleInfo?
    let care: CareInfo?
}

struct SunInfo: Codable {
    let lightType: String?
    let durationPerDay: String?
    let orientation: String?
    let windowDistance: String?
    let recommendedRooms: [String]?
    let tips: [String]?
}

struct WaterInfo: Codable {
    let frequency: String?
    let amount: String?
    let method: String?
    let humidity: String?
    let signsLack: String?
    let signsExcess: String?
    let recommendedWater: String?
}

struct SoilAndPotInfo: Codable {
    let substrate: String?
    let drainage: String?
    let potSize: String?
    let repotFrequency: String?
    let repotSigns: String?
}

struct HealthInfo: Codable {
    let commonProblems: [String]?
    let symptomsAndCauses: [String]?
    let pests: [String]?
    let treatments: [String]?
    let prevention: [String]?
}

struct LifeCycleInfo: Codable {
    let growth: String?
    let flowering: String?
    let dormancy: String?
    let fertilizer: String?
    let pruning: String?
}

struct CareInfo: Codable {
    let difficulty: String?
    let weekly: [String]?
    let monthly: [String]?
    let yearly: [String]?
    let extraTips: [String]?
}

extension Plant {

    /// Obtient l'URL locale du modèle 3D (télécharge depuis le backend si nécessaire)
    /// - Parameter forceDownload: Si true, force un nouveau téléchargement depuis le backend
    /// - Returns: L'URL locale du fichier USDZ
    func getModelURL(forceDownload: Bool = false) async throws -> URL {
        let rawModelURL = modelURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var candidates: [String] = []

        if !rawModelURL.isEmpty {
            candidates.append(rawModelURL)

            // Si un nom est fourni sans extension, on tente aussi avec .usdz
            if (rawModelURL as NSString).pathExtension.isEmpty {
                candidates.append(rawModelURL + ".usdz")
            }
        }

        // Fallback: reconstruire des noms probables depuis le nom de plante
        let nameTrimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nameTrimmed.isEmpty {
            candidates.append(nameTrimmed + ".usdz")
            candidates.append(nameTrimmed.replacingOccurrences(of: " ", with: "_") + ".usdz")
            candidates.append(nameTrimmed.replacingOccurrences(of: " ", with: "-") + ".usdz")
        }

        // Dédupliquer en conservant l'ordre
        var uniqueCandidates: [String] = []
        var seen = Set<String>()
        for candidate in candidates {
            let clean = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            if !seen.contains(clean) {
                uniqueCandidates.append(clean)
                seen.insert(clean)
            }
        }

        guard !uniqueCandidates.isEmpty else {
            throw ModelCacheError.invalidModelURL
        }

        var lastError: Error = ModelCacheError.invalidModelURL

        // Essayer chaque candidat jusqu'à trouver un fichier valide côté backend
        for candidate in uniqueCandidates {
            do {
                return try await ModelCacheManager.shared.getModelURL(for: candidate, forceDownload: forceDownload)
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError
    }

    /// Synchronous bundle-only lookup (non-deprecated replacement for localModelURL).
    var bundleModelURL: URL? {
        guard let modelURL, !modelURL.isEmpty else { return nil }

        let file = modelURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let ext  = (file as NSString).pathExtension
        let name = (file as NSString).deletingPathExtension
        let finalExt = ext.isEmpty ? "usdz" : ext

        return Bundle.main.url(forResource: name, withExtension: finalExt)
    }

    /// URL locale du modèle (ancienne version synchrone - deprecated)
    /// Fallback vers le bundle iOS pour compatibilité
    @available(*, deprecated, message: "Use getModelURL() async instead")
    var localModelURL: URL? {
        guard let modelURL, !modelURL.isEmpty else { return nil }

        let file = modelURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let ext  = (file as NSString).pathExtension
        let name = (file as NSString).deletingPathExtension
        let finalExt = ext.isEmpty ? "usdz" : ext

        let url = Bundle.main.url(forResource: name, withExtension: finalExt)

        if url == nil {
            print("❌ USDZ introuvable dans le bundle: \(name).\(finalExt)")
        } else {
            print("✅ USDZ trouvé: \(name).\(finalExt)")
        }
        return url
    }
}

// MARK: - Fallback helper (only for restore safety)

fileprivate struct PlantFallback {
    let id: String
    let name: String
    let type: String
    let modelURL: String

    func asPlant() -> Plant {
        let json: [String: Any] = [
            "id": id,
            "name": name,
            "type": type,
            "imageURLs": [],
            "description": "",
            "modelURL": modelURL,
            "translations": [:]
        ]
        let data = try? JSONSerialization.data(withJSONObject: json, options: [])
        return (data.flatMap { try? JSONDecoder().decode(Plant.self, from: $0) })
            ?? (try! JSONDecoder().decode(Plant.self, from: try! JSONSerialization.data(withJSONObject: [
                "id": UUID().uuidString,
                "name": "Plante",
                "type": "",
                "imageURLs": [],
                "description": "",
                "modelURL": modelURL,
                "translations": [:]
            ])))
    }
}
