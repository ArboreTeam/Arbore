import SwiftUI
import FirebaseAuth

func deleteUserFromMongo(uid: String, completion: @escaping () -> Void) {
    guard let url = URL(string: "http://79.137.92.154:8080/users/\(uid)") else {
        completion()
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"

    URLSession.shared.dataTask(with: request) { _, response, error in
        if let error = error {
            print("❌ MongoDB deletion error: \(error.localizedDescription)")
        } else {
            print("✅ User deleted from MongoDB")
        }
        DispatchQueue.main.async {
            completion()
        }
    }.resume()
}
