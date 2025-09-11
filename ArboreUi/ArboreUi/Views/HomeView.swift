import SwiftUI
import FirebaseAuth

struct HomeView: View {
    @ObservedObject var plantService = PlantService()
    @StateObject var userService = UserService()
    @State private var showARScan = false
    @State private var userName: String = ""
    @State private var userError: String? = nil
    @State private var currentUID: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    if let error = userError {
                        Text("❌ Erreur: \(error)")
                            .foregroundColor(.red)
                            .font(.footnote)
                            .padding(.top, 80)
                    } else {
                        Text("🌿 Bienvenue, \(userName.isEmpty ? "Utilisateur" : userName) !")
                            .font(.largeTitle)
                            .bold()
                            .padding(.top, 80)
                    }

                    Image("plantes")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                        .cornerRadius(15)
                        .padding(.horizontal)

                    Button(action: {
                        showARScan.toggle()
                    }) {
                        HStack {
                            Image(systemName: "camera.viewfinder")
                            Text("Scanner une plante")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 10)

                    Text("🔔 N'oublie pas d’arroser ton Monstera aujourd’hui !")
                        .padding()
                        .background(Color.yellow.opacity(0.3))
                        .cornerRadius(10)
                        .padding(.horizontal)

                    VStack(alignment: .leading) {
                        Text("🌱 Plantes populaires")
                            .font(.headline)
                            .padding(.top, 10)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 15) {
                                ForEach(plantService.plants) { plant in
                                    PlantCard(plant: plant)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("💧 Plantes à arroser bientôt")
                            .font(.headline)
                            .padding(.top, 10)

                        VStack(spacing: 8) {
                            ForEach(plantService.plants.prefix(2)) { plant in
                                WaterReminderRow(plantName: plant.name, daysLeft: Int.random(in: 1...5))
                            }
                        }
                        .padding(.horizontal)
                    }

                    VStack(alignment: .leading) {
                        Text("🔍 Dernières plantes visitées")
                            .font(.headline)
                            .padding(.top, 10)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 15) {
                                ForEach(plantService.plants.prefix(3)) { plant in
                                    PlantCard(plant: plant)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.bottom, 100)
            }
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
            .onAppear {
                plantService.fetchPlants()

                if let uid = Auth.auth().currentUser?.uid {
                    self.currentUID = uid
                    userService.fetchUser(by: uid) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let user):
                                self.userName = user.name.components(separatedBy: " ").first ?? ""
                            case .failure(let error):
                                self.userError = "Impossible de récupérer l'utilisateur : \(error.localizedDescription)"
                            }
                        }
                    }
                } else {
                    self.userError = "Utilisateur non connecté."
                }
            }
            .fullScreenCover(isPresented: $showARScan) {
                ScanAR()
            }
        }
    }
}
