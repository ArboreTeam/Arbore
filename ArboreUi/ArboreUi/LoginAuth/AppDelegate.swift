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

class AppDelegate: NSObject, UIApplicationDelegate{
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool{
        FirebaseApp.configure()

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

        return true
    }

    @available(iOS 9.0, *)

    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}

