import Foundation
import Firebase

struct UserResponse: Decodable {
    let user: User
}

class UserService: ObservableObject {
    @Published var currentUser: User? = nil
    @Published var fetchError: String? = nil

    func fetchUser(by uid: String, completion: @escaping (Result<User, Error>) -> Void) {
        guard let url = URL(string: "http://79.137.92.154:8080/users/\(uid)") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ Erreur réseau: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Réponse invalide du serveur")
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            guard let data = data else {
                print("❌ Données vides reçues du serveur")
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            if httpResponse.statusCode == 404 {
                print("❌ Utilisateur non trouvé")
                completion(.failure(URLError(.fileDoesNotExist)))
                return
            }

            do {
                print("✅ Réponse brute du serveur :", String(data: data, encoding: .utf8) ?? "nil")
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let wrapper = try decoder.decode(UserResponse.self, from: data)
                let user = wrapper.user
                DispatchQueue.main.async {
                    self.currentUser = user
                }
                completion(.success(user))
            } catch {
                print("❌ Erreur de décodage: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }.resume()
    }

    func fetchCurrentUser() {
        if let uid = Auth.auth().currentUser?.uid {
            fetchUser(by: uid) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let user):
                        self.currentUser = user
                    case .failure(let error):
                        self.fetchError = error.localizedDescription
                    }
                }
            }
        } else {
            self.fetchError = "Utilisateur non connecté."
        }
    }
}
