//
//  ARQualityObserver.swift
//  ArboreUi
//
//  Observer global du thermal state iOS. Installé une fois au démarrage
//  de l'app (cf. AppDelegate), il écoute `ProcessInfo.thermalStateDidChangeNotification`
//  et republie une notification métier `.arboreThermalCritical` lorsque
//  le système rapporte `.serious` ou `.critical`. Les composants UI
//  intéressés (banner, vues AR) s'abonnent à cette notification métier
//  plutôt qu'à la notification système — cela centralise la politique
//  de seuils dans un seul fichier.
//
//  Aucun accès direct à l'UI ni à ARKit ici : couplage faible volontaire,
//  l'observer est utilisable depuis n'importe quel contexte (preview,
//  test unitaire, debug menu) sans tirer SwiftUI.
//

import Foundation

extension Notification.Name {
    /// Le thermal state du système a basculé sur un niveau qui justifie
    /// un avertissement visible à l'utilisateur. Posée par
    /// `ARQualityObserver` lorsque l'état rapporté est `.serious` ou
    /// `.critical`.
    static let arboreThermalCritical = Notification.Name("ArboreThermalCritical")

    /// Le thermal state est redescendu sur un niveau sain (`.nominal` ou
    /// `.fair`). Permet à l'UI de masquer le banner d'avertissement.
    static let arboreThermalRecovered = Notification.Name("ArboreThermalRecovered")
}

/// Observer global du thermal state. Singleton car il n'y a aucune raison
/// d'avoir plus d'un observer actif en même temps — l'API
/// `NotificationCenter` rebroadcast à tous les listeners.
final class ARQualityObserver {

    static let shared = ARQualityObserver()

    private var token: NSObjectProtocol?
    /// Dernier état connu rapporté à l'UI. Utilisé pour ne notifier qu'en
    /// transition (éviter le spam si iOS republie le même niveau).
    private var lastBroadcastWasCritical = false

    private init() {}

    /// Démarre l'observation. À appeler une seule fois, typiquement depuis
    /// `AppDelegate.didFinishLaunchingWithOptions`. Idempotent : appels
    /// successifs sont sans effet.
    func start() {
        guard token == nil else { return }
        token = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleThermalChange()
        }
        // Lit l'état courant au démarrage pour gérer le cas du device déjà
        // chaud à l'ouverture de l'app.
        handleThermalChange()
    }

    /// Arrête l'observation. Utile dans les tests et en cas de teardown
    /// explicite. En production, l'observer vit toute la durée de l'app.
    func stop() {
        if let token = token {
            NotificationCenter.default.removeObserver(token)
        }
        token = nil
        lastBroadcastWasCritical = false
    }

    private func handleThermalChange() {
        let state = ProcessInfo.processInfo.thermalState
        let isCritical: Bool
        switch state {
        case .serious, .critical:
            isCritical = true
        case .nominal, .fair:
            isCritical = false
        @unknown default:
            isCritical = false
        }

        // Ne broadcast qu'en transition pour limiter le bruit.
        guard isCritical != lastBroadcastWasCritical else { return }
        lastBroadcastWasCritical = isCritical

        if isCritical {
            NotificationCenter.default.post(name: .arboreThermalCritical, object: state)
        } else {
            NotificationCenter.default.post(name: .arboreThermalRecovered, object: state)
        }
    }
}
