//
//  AppDelegate.swift
//  ArboreUi
//
//  Created by Hugo Rath on 16/03/2025.
//

import FirebaseAuth
import SwiftUI
import FirebaseCore
import GoogleSignIn
import GoogleSignInSwift
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool{
        // Sentry en premier (issue #205), AVANT Firebase, pour capturer aussi un
        // éventuel crash pendant l'init de Firebase. No-op si pas de DSN ou si
        // l'utilisateur n'a pas consenti au diagnostic (opt-in RGPD, issue #226) ;
        // réactivé par SentryManager.updateConsent dès qu'il accepte.
        SentryManager.start()

        FirebaseApp.configure()
        NotificationManager.shared.configureCategories()
        UNUserNotificationCenter.current().delegate = self

        // Le contexte user Sentry suit l'état d'auth Firebase (login → UID,
        // logout → nil). Centralisé ici : inutile de toucher chaque écran de
        // connexion/déconnexion.
        Auth.auth().addStateDidChangeListener { _, user in
            if let uid = user?.uid {
                SentryManager.setUser(uid: uid)
            } else {
                SentryManager.clearUser()
            }
        }

        // Release heavy RealityKit caches when iOS signals memory pressure.
        // Without this, the singleton ThumbnailRenderHost's ARView accumulates
        // GPU buffers from every rendered plant and the app gets jetsam'd.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                ThumbnailRenderHost.shared.releaseScene()
                print("⚠️ Memory warning: released thumbnail scene")
            }
        }

        // Start global thermal state observation. Republishes
        // `.arboreThermalCritical` and `.arboreThermalRecovered` for any
        // UI component subscribed (cf. ThermalStateBanner). Issue #82.
        ARQualityObserver.shared.start()

        return true
    }

    @available(iOS 9.0, *)

    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }

        if url.scheme?.lowercased() == "arbore" {
            Task { @MainActor in
                NotificationRouter.shared.handle(url: url)
            }
            return true
        }

        return false
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            NotificationRouter.shared.presentInAppNotification(from: notification)
        }
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task {
            await NotificationManager.shared.handleNotificationAction(response)
            await MainActor.run {
                NotificationRouter.shared.handle(response: response)
                completionHandler()
            }
        }
    }
}
