import SwiftUI
import FirebaseAuth

func deleteUserFromMongo(uid: String, completion: @escaping () -> Void) {
    Task {
        do {
            try await NetworkManager.shared.requestWithoutAuthNoResponse(
                endpoint: "/users/\(uid)",
                method: .DELETE
            )
            print("✅ User deleted from MongoDB")
        } catch {
            print("❌ MongoDB deletion error: \(error.localizedDescription)")
        }

        await MainActor.run {
            completion()
        }
    }
}
