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
    let generated: Bool?   // true = modèle 3D généré par IA, nil/false = legacy
    let upAxis: String?    // "Y" (default, nil) ou "Z" (Blender exports qui doivent être redressés)
    let source: String?    // libellé de provenance optionnel (catalogue curé) ; nil = legacy/beta
    let sourceUrl: String? // URL d'origine optionnelle (conservée pour mise à jour)
    let flags: PlantFlags? // drapeaux structurés pour la reco wizard ; nil = legacy (fallback mots-clés)
    /// Données horticoles vérifiables utilisées par le moteur de compatibilité.
    /// Les champs sont volontairement optionnels : une donnée absente reste
    /// inconnue et ne doit jamais devenir une compatibilité supposée.
    let botanicalProfile: PlantBotanicalProfile?
    let hasHeavy: Bool?    // true = une version 3D haute définition existe (LOD : swap depuis le léger en AR)
    /// true = le maillage ne contient PAS son pot (sortie d'atelier recoupée).
    /// nil/false = pot inclus dans le modèle, comportement historique.
    let potless: Bool?
    /// Socle mesuré où poser le pot. nil = pose non calculable, aucun pot servi.
    let potBase: PlantPotBase?
    /// Hauteur réelle de l'exemplaire, mesurée **depuis la terre** et non
    /// depuis le bas du pot : le pot change, la plante non. nil = non mesurée,
    /// on retombe alors sur la hauteur par défaut du placement.
    let heightMeters: Double?
    /// Empreintes du contenu des fichiers servis, pour l'invalidation du cache.
    let versions: PlantAssetVersions?
    /// Pot résolu par le serveur pour une plante recoupée. Présent seulement
    /// sur la fiche détaillée : la liste du catalogue ne le porte pas.
    let pot: Pot?

    enum CodingKeys: String, CodingKey {
        case id
        case name, type, imageURLs, description, modelURL, translations, generated, upAxis, source, sourceUrl, flags, botanicalProfile, hasHeavy
        case potless, potBase, heightMeters, versions, pot
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

        self.translations = Plant.traductionsUtilisables(dans: container)

        self.generated = try container.decodeIfPresent(Bool.self, forKey: .generated)
        self.upAxis = try container.decodeIfPresent(String.self, forKey: .upAxis)
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
        self.sourceUrl = try container.decodeIfPresent(String.self, forKey: .sourceUrl)
        self.flags = try container.decodeIfPresent(PlantFlags.self, forKey: .flags)
        self.botanicalProfile = try container.decodeIfPresent(PlantBotanicalProfile.self, forKey: .botanicalProfile)
        self.hasHeavy = try container.decodeIfPresent(Bool.self, forKey: .hasHeavy)
        self.potless = try container.decodeIfPresent(Bool.self, forKey: .potless)
        self.potBase = try container.decodeIfPresent(PlantPotBase.self, forKey: .potBase)
        self.heightMeters = try container.decodeIfPresent(Double.self, forKey: .heightMeters)
        self.versions = try container.decodeIfPresent(PlantAssetVersions.self, forKey: .versions)
        self.pot = try container.decodeIfPresent(Pot.self, forKey: .pot)
    }

    /// Vrai si le maillage attend qu'on lui pose un pot.
    var attendUnPot: Bool { potless == true }

    /// Clé dynamique : le bloc `translations` est indexé par code de langue,
    /// et rien ne borne l'ensemble des langues à l'avance.
    private struct CodeDeLangue: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    /// Décode `translations` **langue par langue**, en écartant celles qui ne
    /// tiennent pas — issue #489.
    ///
    /// ## Le défaut que ce garde-fou corrige
    ///
    /// `PlantTranslation` déclare `description` et `plantType` NON optionnels.
    /// Décoder le bloc d'un seul coup — `decodeIfPresent([String: PlantTranslation])` —
    /// fait donc échouer TOUT le dictionnaire dès qu'une seule langue est
    /// partielle. Et comme cette erreur remonte l'`init(from:)`, ce n'est pas la
    /// traduction fautive qui est perdue : c'est **la plante entière**, qui
    /// disparaît du catalogue.
    ///
    /// Un `$set` maladroit sur `translations.de` d'une seule fiche suffisait à
    /// l'effacer de l'app. Les scripts d'écriture se gardent de le faire, mais
    /// la discipline d'un script ne protège pas d'une commande tapée à la main
    /// dans `mongosh` un soir de correctif.
    ///
    /// Ici, une langue illisible ne coûte que cette langue. Les appelants
    /// retombent tous sur `en` (`PlantDetailView.translation(for:)`,
    /// `ManageGardenView.preferredTranslation(for:)`), donc le lecteur voit une
    /// fiche complète dans une autre langue — au lieu de rien du tout.
    ///
    /// ## Ce que ce garde-fou ne fait délibérément PAS
    ///
    /// Il ne juge pas le contenu. Une traduction dont `description` est vide est
    /// conservée, alors qu'elle affichera peu de chose.
    ///
    /// La tentation était forte de l'écarter au profit du repli sur `en`, plus
    /// complet. C'est une erreur : un bloc de langue ne porte pas que de la
    /// prose, il porte aussi des données structurées que le catalogue consomme —
    /// `care.difficulty` en tête, dont `careDifficulty(locale:)` dépend pour
    /// filtrer. Jeter la langue entière parce que son texte est vide reviendrait
    /// à jeter sa difficulté avec, et à faire disparaître la plante des filtres
    /// pour régler un problème d'affichage.
    ///
    /// Un décodeur ne détruit pas de la donnée valide pour arranger une vue. La
    /// complétude est vérifiée en amont par les scripts d'écriture, qui voient
    /// la source ; le repli sur un champ vide se règle à la lecture, là où le
    /// contexte existe.
    private static func traductionsUtilisables(
        dans container: KeyedDecodingContainer<CodingKeys>
    ) -> [String: PlantTranslation] {
        guard let bloc = try? container.nestedContainer(keyedBy: CodeDeLangue.self,
                                                        forKey: .translations) else {
            return [:]
        }

        var retenues: [String: PlantTranslation] = [:]
        for cle in bloc.allKeys {
            guard let traduction = try? bloc.decode(PlantTranslation.self, forKey: cle) else {
                #if DEBUG
                print("⚠️ Plant: traduction « \(cle.stringValue) » illisible — langue ignorée, la fiche est conservée")
                #endif
                continue
            }
            retenues[cle.stringValue] = traduction
        }
        return retenues
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

// MARK: - Recommendation flags

/// Structured booleans driving the wizard recommendation (filter + scoring).
/// Tolerant decode: any missing key defaults to false.
struct PlantFlags: Codable {
    let toxicToPets: Bool
    let toxicToChildren: Bool
    let easyCare: Bool
    let shadeTolerant: Bool
    let fullSunTolerant: Bool
    let droughtTolerant: Bool
    let humidityLoving: Bool
    let flowering: Bool
    let climbing: Bool
    let trailing: Bool
    let compact: Bool
    let airPurifying: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func f(_ k: CodingKeys) -> Bool { (try? c.decode(Bool.self, forKey: k)) ?? false }
        toxicToPets = f(.toxicToPets)
        toxicToChildren = f(.toxicToChildren)
        easyCare = f(.easyCare)
        shadeTolerant = f(.shadeTolerant)
        fullSunTolerant = f(.fullSunTolerant)
        droughtTolerant = f(.droughtTolerant)
        humidityLoving = f(.humidityLoving)
        flowering = f(.flowering)
        climbing = f(.climbing)
        trailing = f(.trailing)
        compact = f(.compact)
        airPurifying = f(.airPurifying)
    }
}

// MARK: - Verified botanical compatibility data

/// Provenance attached to an individual botanical value. Keeping provenance
/// per field avoids presenting a partly sourced plant sheet as fully verified.
/// Confiance accordée à une valeur, en vocabulaire fermé et ORDONNÉ.
///
/// Le champ était une chaîne libre, et le lecteur exigeait l'égalité exacte
/// avec `high` tandis que les écrivains produisaient `authoritative`,
/// `authoritative-genus` et `derived`. Aucune des trois ne correspondait :
/// chaque contrôle de provenance échouait, et **plus aucune plante ne pouvait
/// être déclarée adaptée** (#647 §1).
///
/// La mesure a montré que les deux vocabulaires ne divergeaient pas par
/// négligence — la coupure suivait exactement les champs. La toxicité venait
/// d'une source nommée (`authoritative`, 13 valeurs ; `authoritative-genus`,
/// 25), les trois axes horticoles étaient tous `derived` (335). L'un disait
/// d'où vient la valeur, l'autre combien on lui fait confiance. D'où la
/// correspondance appliquée en base : `authoritative` → `high`,
/// `authoritative-genus` → `moderate`, `derived` → `low`.
enum PlantDataReliability: String, Codable, Comparable {
    case low
    case moderate
    case high

    private var rang: Int {
        switch self {
        case .low: return 0
        case .moderate: return 1
        case .high: return 2
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rang < rhs.rang }

    /// Une valeur non reconnue vaut le PLANCHER, jamais le plafond.
    ///
    /// Une provenance a été consignée, mais son mot de confiance nous est
    /// inconnu : la traiter comme la plus faible est le seul choix qui ne
    /// surclasse rien. L'absence du champ, elle, reste `nil` et continue de
    /// faire échouer le contrôle — ne pas écrire de provenance et en écrire une
    /// qu'on ne sait pas lire sont deux situations différentes.
    init(from decoder: Decoder) throws {
        let brut = try decoder.singleValueContainer().decode(String.self)
        let cle = brut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = PlantDataReliability(rawValue: cle) ?? .low
    }
}

struct PlantDataEvidence: Codable, Equatable {
    let sourceName: String?
    let sourceURL: String?
    /// ISO-8601 date (`YYYY-MM-DD` or a full timestamp).
    let reviewedAt: String?
    /// `low`, `moderate` ou `high`. `nil` = aucune provenance consignée.
    let reliability: PlantDataReliability?
}

/// A sourced scalar value. Generic facts keep the JSON schema consistent
/// across strings, booleans and numbers.
struct PlantFact<Value: Codable & Equatable>: Codable, Equatable {
    let value: Value
    let evidence: PlantDataEvidence?
}

/// Verdict de toxicité STOCKÉ, en valeurs closes.
///
/// Le schéma annonçait déjà ces quatre valeurs. Les écrivains ont pourtant
/// rempli le champ de prose sourcée, et le client avait poussé un analyseur de
/// sous-chaînes pour s'en sortir. Cet analyseur était inversable — « unsafe »
/// contient « safe » — et aucun ordre de passes ne rend sûre une décision de
/// sécurité tirée d'une chaîne libre (#778). Le verdict est donc une donnée,
/// pas une lecture.
enum PlantToxicityValue: String, Codable, Equatable {
    case safe
    case toxic
    case irritant
    case unknown

    /// Toute valeur non reconnue devient `unknown`, jamais `safe`.
    ///
    /// C'est ce qui rend la migration sans danger : les fiches historiques
    /// portent de la prose dans ce champ, elle se décode en « inconnu », et la
    /// plante retombe sur ses drapeaux au lieu d'être déclarée inoffensive par
    /// accident. Un décodage strict ferait au contraire échouer tout le profil
    /// botanique de la fiche.
    init(from decoder: Decoder) throws {
        let brut = try decoder.singleValueContainer().decode(String.self)
        let cle = brut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = PlantToxicityValue(rawValue: cle) ?? .unknown
    }
}

/// Fait de toxicité : le verdict qui décide, et la prose qui explique.
///
/// `detail` porte la phrase sourcée produite par la recherche. Elle est
/// informative — rien ne la lit pour décider.
struct PlantToxicityFact: Codable, Equatable {
    let value: PlantToxicityValue
    let detail: String?
    let evidence: PlantDataEvidence?

    /// Un `value` absent vaut « inconnu », et ne fait pas échouer le décodage.
    ///
    /// Sans ça, une fiche dont le champ serait vide emporterait avec elle TOUT
    /// son profil botanique — soleil, température, dimensions — pour une seule
    /// clé manquante. Le profil est optionnel de bout en bout précisément pour
    /// se migrer par morceaux.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decodeIfPresent(PlantToxicityValue.self, forKey: .value) ?? .unknown
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        evidence = try c.decodeIfPresent(PlantDataEvidence.self, forKey: .evidence)
    }

    /// Le verdict exploitable, ou `nil` quand il n'est pas établi.
    /// `irritant` compte comme toxique : c'est une atteinte, pas une nuance.
    var verdict: Plant.ToxicityVerdict? {
        switch value {
        case .safe: return .safe
        case .toxic, .irritant: return .toxic
        case .unknown: return nil
        }
    }
}

struct PlantRangeFact: Codable, Equatable {
    let minimum: Double?
    let maximum: Double?
    let unit: String?
    let evidence: PlantDataEvidence?

    var hasValue: Bool {
        minimum != nil || maximum != nil
    }
}

/// Canonical compatibility profile. Free-form prose remains useful for the
/// detail sheet, but only these sourced fields may certify a plant as adapted.
struct PlantBotanicalProfile: Codable, Equatable {
    /// `indoor`, `outdoor`, or both.
    let environments: PlantFact<[String]>?
    let minimumTemperatureC: PlantFact<Double>?
    let directSunHours: PlantRangeFact?
    let indoorHumidityPercent: PlantRangeFact?
    let wateringIntervalDays: PlantRangeFact?
    /// Expected values: `fast`, `normal`, `slow`, `any`.
    let drainage: PlantFact<String>?
    let matureHeightCm: PlantRangeFact?
    let matureWidthCm: PlantRangeFact?
    let minimumPotVolumeLiters: PlantFact<Double>?
    let minimumPotDepthCm: PlantFact<Double>?
    /// Expected values: `low`, `moderate`, `high`.
    let windTolerance: PlantFact<String>?
    let droughtTolerance: PlantFact<String>?
    let saltTolerance: PlantFact<String>?
    /// Verdicts STOCKÉS, en valeurs closes (`safe`, `toxic`, `irritant`,
    /// `unknown`). Ces quatre valeurs étaient déjà le contrat annoncé ici ;
    /// elles sont désormais typées, donc ni devinées ni analysées (#778).
    let petToxicity: PlantToxicityFact?
    let childToxicity: PlantToxicityFact?
    /// Incremented when the canonical schema changes.
    let schemaVersion: Int?
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
    /// Empreinte du fichier servi pour ce niveau de détail, quand elle existe.
    /// Elle indexe le cache : un contenu neuf devient un fichier neuf (#294).
    func empreinte(pour lod: ModelLOD) -> String? {
        lod == .heavy ? versions?.modelHeavy : versions?.model
    }

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
                // L'empreinte ne vaut que pour le modelURL déclaré. Les
                // candidats reconstruits depuis le nom de la plante visent un
                // AUTRE fichier : leur coller cette empreinte ferait passer
                // pour « à jour » un contenu qui n'a jamais été mesuré.
                let version = (candidate == rawModelURL) ? empreinte(pour: .light) : nil
                return try await ModelCacheManager.shared.getModelURL(
                    for: candidate, version: version, forceDownload: forceDownload)
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

// MARK: - Niveau d'entretien (#485)

extension Plant {

    /// Niveau d'entretien d'une plante, tel qu'un filtre peut l'exploiter.
    enum CareDifficulty {
        case easy
        case moderate
        case demanding
    }

    /// Résout le niveau d'entretien, ou `nil` si la donnée est absente.
    ///
    /// Deux sources, dans cet ordre :
    ///
    /// 1. `care.difficulty`, qui porte les trois niveaux. Le backend ne le
    ///    sérialisait pas jusqu'à #485 et aucune fiche ne le renseigne encore.
    /// 2. `flags.easyCare`, présent sur 98 des 124 fiches. Binaire, donc
    ///    incapable de distinguer « intermédiaire » — d'où le repli, pas le
    ///    remplacement.
    ///
    /// **`nil` signifie « inconnu », pas « ne correspond pas ».** La distinction
    /// est tout l'objet de #485 : le filtre du catalogue traitait l'absence de
    /// donnée comme un échec de correspondance et excluait donc la totalité du
    /// catalogue. Un filtre ne doit jamais cacher ce qu'il ne sait pas juger.
    func careDifficulty(locale: String = "fr") -> CareDifficulty? {
        // La langue demandée d'abord, puis n'importe quelle autre.
        //
        // La difficulté est une CATÉGORIE, pas de la prose : la lire dans une
        // autre langue reste juste, puisque la reconnaissance est multilingue.
        // Sans ce repli, une fiche traduite en français seulement perdrait sa
        // difficulté pour un utilisateur anglophone — la donnée existe, elle
        // serait simplement ignorée.
        let candidates = [translations[locale]] + translations
            .filter { $0.key != locale }
            .sorted { $0.key < $1.key }        // ordre stable, pas au hasard du dictionnaire
            .map { $0.value }

        if let raw = candidates
            .compactMap({ $0?.care?.difficulty?.lowercased() })
            .first(where: { !$0.isEmpty }) {
            // Mots-clés des quatre langues servies par le catalogue.
            let easy = ["facile", "easy", "simple", "einfach", "leicht", "fácil", "facil", "débutant"]
            let moderate = ["intermé", "medium", "modér", "mittel", "moderat", "intermedio"]
            let demanding = ["exigeant", "difficile", "hard", "expert", "anspruchsvoll", "schwer", "dificil", "difícil"]

            // « Exigeant » d'abord : « pas facile » contient « facile ».
            if demanding.contains(where: raw.contains) { return .demanding }
            if moderate.contains(where: raw.contains) { return .moderate }
            if easy.contains(where: raw.contains) { return .easy }
        }

        if let flags = flags {
            return flags.easyCare ? .easy : .demanding
        }

        return nil
    }
}

// MARK: - Toxicité (#488)

extension Plant {

    /// Verdict de toxicité pour un public donné.
    enum ToxicityVerdict {
        case toxic
        case safe
    }

    /// Toxicité pour les animaux, ou `nil` si elle n'est pas établie.
    ///
    /// Deux sources, dans cet ordre :
    ///
    /// 1. `botanicalProfile.petToxicity.value` — le verdict STOCKÉ, en valeur
    ///    close, avec sa provenance. Rien n'est analysé : le champ dit
    ///    `safe`, `toxic`, `irritant` ou `unknown`, et c'est tout.
    /// 2. `flags.toxicToPets` — repli pour les fiches qui n'ont pas encore de
    ///    verdict stocké, et pour celles dont le verdict est `unknown`.
    ///
    /// **`nil` signifie « non établie ».** Contrairement au filtre de difficulté
    /// (#485), où l'inconnu n'exclut pas, l'inconnu doit ici EXCLURE : le coût
    /// des deux erreurs n'est pas le même. Masquer une plante inoffensive prive
    /// d'un choix ; en proposer une toxique à quelqu'un qui a demandé le
    /// contraire rompt une promesse.
    ///
    /// Le `false` du repli reste ambigu — il a longtemps voulu dire à la fois
    /// « sûre » et « non recherchée ». La convention de remplissage lève
    /// désormais le drapeau sur une toxicité non tranchée, ce qui rend ce repli
    /// prudent ; le trancher pour de bon demande une migration, suivie en #780.
    func petToxicity() -> ToxicityVerdict? {
        if let verdict = botanicalProfile?.petToxicity?.verdict {
            return verdict
        }
        if let flags = flags {
            return flags.toxicToPets ? .toxic : .safe
        }
        return nil
    }

    /// Contrainte de sûreté déclarée par le questionnaire du jardin.
    ///
    /// Elle existe pour qu'un seul endroit lise les libellés du questionnaire.
    /// Il y en avait trois, avec trois tolérances différentes :
    /// `WizardPlantFilter` comparait la chaîne entière
    /// (« Éviter les plantes toxiques pour les animaux »), les deux
    /// `appendSafetyCriteria` cherchaient « animaux » ou « pets » après
    /// normalisation. Un libellé retouché aurait désarmé l'un sans toucher aux
    /// autres, en silence.
    struct HouseholdSafetyRequirement: Equatable {
        let pets: Bool
        let children: Bool

        var isEmpty: Bool { !pets && !children }

        init(pets: Bool, children: Bool) {
            self.pets = pets
            self.children = children
        }

        /// Lit les réponses du questionnaire, dans les quatre langues servies.
        init(wizardSafety: [String]?) {
            guard let brut = wizardSafety, !brut.isEmpty else {
                self.init(pets: false, children: false)
                return
            }
            let valeurs = brut.map {
                $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .lowercased()
            }
            // « Aucune contrainte » est une réponse, pas une absence.
            if valeurs.contains(where: { $0.contains("aucune contrainte") || $0.contains("none") }) {
                self.init(pets: false, children: false)
                return
            }
            self.init(
                pets: valeurs.contains { $0.contains("animaux") || $0.contains("pets") },
                children: valeurs.contains { $0.contains("enfants") || $0.contains("children") }
            )
        }
    }

    /// Réponse d'une plante à une contrainte de sûreté. Trois branches, et pas
    /// un booléen : un booléen force à ranger l'inconnu avec l'un des deux, et
    /// c'est exactement le piège qui traverse ces données — `toxicToPets:
    /// false` a longtemps voulu dire à la fois « prouvé sûr » et
    /// « pas recherché ».
    enum SafetyOutcome: Equatable {
        /// Le fait est connu, et compatible avec la contrainte.
        case satisfied
        /// Le fait est connu, et incompatible.
        case conflict
        /// Le fait n'est pas établi. L'incertitude est la nôtre, pas celle de
        /// la plante : 44 fiches du catalogue sont dans ce cas.
        case undetermined
    }

    /// LE prédicat de sûreté. Unique, et sans politique d'affichage.
    ///
    /// La distinction porte tout le reste : ceci répond « cette plante est-elle
    /// compatible ? », un fait qui ne dépend d'aucun écran. Ce qu'on en fait —
    /// masquer, marquer, déclasser — est une politique, elle dépend de l'écran,
    /// et elle s'écrit chez l'appelant.
    ///
    /// Le plus défavorable des publics demandés l'emporte : un conflit sur un
    /// seul suffit, et à défaut de conflit un seul indéterminé suffit.
    func safetyOutcome(for requirement: HouseholdSafetyRequirement) -> SafetyOutcome {
        guard !requirement.isEmpty else { return .satisfied }

        var verdicts: [ToxicityVerdict?] = []
        if requirement.pets { verdicts.append(petToxicity()) }
        if requirement.children { verdicts.append(childToxicity()) }

        if verdicts.contains(where: { $0 == .toxic }) { return .conflict }
        if verdicts.contains(where: { $0 == nil }) { return .undetermined }
        return .satisfied
    }

    /// Les deux politiques, NOMMÉES.
    ///
    /// L'asymétrie entre « je te propose ceci » et « tu peux parcourir ceci »
    /// est un choix, et elle doit se lire comme tel plutôt que se déduire d'un
    /// filtre en ligne. Le prédicat, lui, reste unique et sans politique.
    enum HouseholdSafetyPolicy {
        /// Ce que l'utilisateur PARCOURT : catalogues.
        ///
        /// Masque le conflit — il vient de déclarer la contrainte. Laisse voir
        /// l'indéterminé, marqué : l'incertitude est la nôtre, pas celle de la
        /// plante, et 44 fiches du catalogue sont dans ce cas. Les masquer
        /// priverait d'autant de choix tout en cachant notre trou de données.
        case browsable
        /// Ce que l'app PROPOSE : moteur de suggestions.
        ///
        /// Masque le conflit ET l'indéterminé. Quand on recommande, on engage
        /// sa parole ; parcourir n'engage que le regard.
        case offerable

        func admits(_ outcome: SafetyOutcome) -> Bool {
            switch (self, outcome) {
            case (_, .satisfied): return true
            case (_, .conflict): return false
            case (.browsable, .undetermined): return true
            case (.offerable, .undetermined): return false
            }
        }
    }

    /// Cette plante passe-t-elle la politique de cette surface ?
    func isAdmitted(
        by policy: HouseholdSafetyPolicy,
        requirement: HouseholdSafetyRequirement
    ) -> Bool {
        policy.admits(safetyOutcome(for: requirement))
    }

    /// Toxicité pour les enfants, ou `nil` si elle n'est pas établie.
    ///
    /// Même contrat que `petToxicity()`. Les fiches historiques ne portaient
    /// pas ce champ — l'ASPCA ne couvre que chiens, chats et chevaux, et
    /// l'extrapoler aurait été inventer (#489) ; la recherche de 2026-11 le
    /// renseigne depuis des sources distinctes, dont NC State Extension.
    func childToxicity() -> ToxicityVerdict? {
        if let verdict = botanicalProfile?.childToxicity?.verdict {
            return verdict
        }
        if let flags = flags {
            return flags.toxicToChildren ? .toxic : .safe
        }
        return nil
    }

}
