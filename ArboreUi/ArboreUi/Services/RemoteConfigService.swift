//
//  RemoteConfigService.swift
//  ArboreUi
//
//  Charge la configuration distante (GET /config, issue #236) au lancement de
//  l'app, la met en cache pour un usage hors-ligne, et l'expose à la fois comme
//  ObservableObject (UI) et via un singleton synchrone (couches modèle :
//  GardenCareKind, WateringFrequency, GardenSuggestionEngine).
//
//  Chaque accesseur renvoie une valeur de repli codée en dur si la config
//  distante n'est pas encore chargée : l'app reste 100 % fonctionnelle offline
//  ou si le backend est injoignable.
//

import Foundation
import Combine

final class RemoteConfigService: ObservableObject {

    /// Singleton accessible depuis les couches modèle (sans injection SwiftUI).
    static let shared = RemoteConfigService()

    /// Config courante (nil tant que rien n'a été chargé ni mis en cache).
    /// Lue de façon synchrone par les couches modèle, écrite sur le main thread.
    @Published private(set) var config: RemoteConfig?

    /// Indique si l'utilisateur dispose d'un abonnement premium. Toujours false
    /// pendant la bêta (aucun paiement) ; branché plus tard sur l'état d'achat
    /// (cf. #4). Utilisé pour décider du verrouillage des options premium.
    @Published var isPremiumMember = false

    private let cacheKey = "arbore.remoteConfig.v1"
    private let defaults = UserDefaults.standard

    private init() {
        // Au démarrage, on tente immédiatement de restaurer le dernier cache
        // pour que les accesseurs synchrones aient une valeur avant le réseau.
        config = loadCachedConfig()
    }

    // MARK: - Chargement

    /// Récupère la config depuis le backend et met à jour le cache. Silencieux :
    /// en cas d'échec on conserve la config en cache (ou les repli codés en dur).
    func load() async {
        do {
            let fetched: RemoteConfig = try await NetworkManager.shared.requestWithoutAuth(
                endpoint: "/config",
                method: .GET
            )
            await MainActor.run { self.config = fetched }
            cache(fetched)
        } catch {
            #if DEBUG
            print("ℹ️ RemoteConfig: échec du chargement (\(error)), repli sur le cache/les valeurs par défaut.")
            #endif
        }
    }

    // MARK: - Cache (offline)

    private func cache(_ config: RemoteConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    private func loadCachedConfig() -> RemoteConfig? {
        guard let data = defaults.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(RemoteConfig.self, from: data)
    }

    // MARK: - Accesseurs (couche modèle)

    /// Intervalle de soin distant (jours) pour une clé `GardenCareKind`,
    /// ou nil si indisponible → l'appelant utilise sa valeur par défaut.
    func careIntervalDays(forKind kind: String) -> Int? {
        config?.care.intervalsDays[kind]
    }

    /// Nombre de jours distant pour une fréquence d'arrosage,
    /// ou nil si indisponible → l'appelant utilise sa valeur par défaut.
    func wateringDays(forFrequency frequency: String) -> Int? {
        config?.care.wateringFrequencyDays[frequency]
    }

    /// Poids distants du moteur de suggestion, ou nil si indisponible.
    var suggestionWeights: RemoteConfig.SuggestionEngine.Weights? {
        config?.suggestionEngine.weights
    }

    // MARK: - Membership / gating

    /// Tier d'un style de jardin ("free" par défaut si la config est absente).
    func tier(forStyleKey key: String) -> String {
        config?.wizard.gardenStyles.first { $0.value == key }?.tier ?? "free"
    }

    /// Un style est verrouillé seulement si le gating est actif, que l'option
    /// est premium, et que l'utilisateur n'est pas abonné. En bêta
    /// (`enforced == false`) cette méthode renvoie toujours false → tout reste
    /// accessible, conformément au comportement attendu.
    func isStyleLocked(forKey key: String) -> Bool {
        guard let config, config.membership.enforced else { return false }
        guard tier(forStyleKey: key) == "premium" else { return false }
        return !isPremiumMember
    }
}
