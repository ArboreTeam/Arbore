import Foundation
import FirebaseAuth
import UIKit

final class ArborePushTokenService {
    static let shared = ArborePushTokenService()

    private let defaults: UserDefaults
    private let tokenKey = "arbore.apns.deviceToken"
    private let tokenPendingUploadKey = "arbore.apns.deviceToken.pendingUpload"
    private let endpoint = "/devices/apns-token"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var currentToken: String? {
        defaults.string(forKey: tokenKey)
    }

    func register(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        guard token != currentToken || defaults.bool(forKey: tokenPendingUploadKey) else { return }

        defaults.set(token, forKey: tokenKey)
        defaults.set(true, forKey: tokenPendingUploadKey)

        Task {
            await uploadPendingTokenIfNeeded()
        }
    }

    func handleRegistrationFailure(_ error: Error) {
        defaults.set(true, forKey: tokenPendingUploadKey)
        print("APNs registration failed: \(error)")
    }

    func uploadPendingTokenIfNeeded() async {
        guard defaults.bool(forKey: tokenPendingUploadKey),
              let token = currentToken,
              !token.isEmpty else { return }

        do {
            let body: [String: Any] = [
                "token": token,
                "platform": "ios",
                "environment": AppConfig.environment,
                "appVersion": AppConfig.appVersion,
                "buildNumber": AppConfig.buildNumber,
                "bundleIdentifier": Bundle.main.bundleIdentifier ?? "com.arboreteam.arbore",
                "deviceModel": UIDevice.current.model,
                "systemVersion": UIDevice.current.systemVersion
            ]

            let _: PushTokenUploadResponse = try await NetworkManager.shared.request(
                endpoint: endpoint,
                method: .POST,
                body: body
            )
            defaults.set(false, forKey: tokenPendingUploadKey)
        } catch {
            defaults.set(true, forKey: tokenPendingUploadKey)
            print("APNs token upload deferred: \(error)")
        }
    }

    func markTokenForRefresh() {
        defaults.set(true, forKey: tokenPendingUploadKey)
    }
}

private struct PushTokenUploadResponse: Decodable {
    let success: Bool?
    let message: String?
}
