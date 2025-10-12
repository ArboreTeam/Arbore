import SwiftUI
import ARKit
import RealityKit
import FirebaseAuth

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ARViewWrapper: View {
    let modelURL: URL
    @Environment(\.presentationMode) var presentationMode
    @State private var showShareSheet = false
    @State private var capturedImage: UIImage?
    @State private var arView = ARView(frame: .zero)
    @State private var isImageReady = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ARViewContainer(arView: $arView, modelURL: modelURL)
                .edgesIgnoringSafeArea(.all)

            // Bouton Retour en haut à gauche
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .padding()

            // Bouton Prendre une photo centré en bas
            VStack {
                Spacer()
                Button(action: captureARView) {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.title)
                        Text("Prendre une photo")
                            .fontWeight(.bold)
                    }
                    .padding()
                    .background(Color.white.opacity(0.8))
                    .foregroundColor(.black)
                    .cornerRadius(12)
                    .shadow(radius: 5)
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: isImageReady) { ready in
            if ready {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showShareSheet = true
                }
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            isImageReady = false
        }) {
            if let image = capturedImage {
                ShareSheet(items: [image])
            }
        }
    }

    private func captureARView() {
        arView.snapshot(saveToHDR: false) { image in
            DispatchQueue.main.async {
                if let image = image {
                    capturedImage = image
                    isImageReady = true
                } else {
                    print("❌ Erreur lors de la capture de l'ARView")
                }
            }
        }
    }
}

struct ARPage: View {
    let plant: Plant
    @State private var navigateToLogin = false
    @State private var userName: String = "Utilisateur"

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.secondarySystemBackground)
                    .edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    Image("plantes")
                        .resizable()
                        .frame(height: UIScreen.main.bounds.height * 0.35)
                        .clipped()
                        .frame(height: 180)

                    VStack(spacing: 20) {
                        Spacer(minLength: 40)
                        Text("Bonjour, \(userName) \u{1F44B}")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        Spacer(minLength: 20)

                        Image(systemName: "arkit")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.green)

                        Text("AR Experience")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        Text("Discover trees in augmented reality")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        Spacer(minLength: 20)

                        NavigationLink(destination: destinationView()) {
                            HStack {
                                Image(systemName: "camera.viewfinder")
                                Text("Launch AR")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green.opacity(0.9))
                            .foregroundColor(.white)
                            .cornerRadius(15)
                            .shadow(radius: 3)
                        }

                        if ARWorldTrackingConfiguration.isSupported {
                            Text("AR Ready")
                                .foregroundColor(.green)
                        } else {
                            Text("AR Not Supported")
                                .foregroundColor(.red)
                        }

                        Button(action: { logout() }) {
                            Text("Logout")
                                .fontWeight(.bold)
                                .frame(width: 120, height: 40)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.red, Color.pink]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(10)
                                .shadow(radius: 5)
                        }
                        .padding(.horizontal, 40)
                        .frame(minHeight: 150, maxHeight: 200)
                        .transition(.opacity)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .offset(y: -40)
                    .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                }
            }
            .navigationBarBackButtonHidden(true)
            .fullScreenCover(isPresented: $navigateToLogin) {
                LoginView()
                    .transition(.move(edge: .trailing))
                    .animation(.easeInOut(duration: 0.5))
            }
            .onAppear {
                fetchUserName()
            }
        }
    }

    private func fetchUserName() {
        if let user = Auth.auth().currentUser {
            if let displayName = user.displayName {
                userName = displayName
            } else if let email = user.email {
                userName = email.components(separatedBy: "@").first ?? "Utilisateur"
            }
        }
    }

    func deleteCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier!
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            print("🔑 Identifiants supprimés du Keychain.")
        } else {
            print("❌ Erreur lors de la suppression des identifiants du Keychain.")
        }
    }
    
    public func logout() {
        do {
            try Auth.auth().signOut()
            print("Utilisateur déconnecté avec succès")
            //deleteCredentials() // Supprimez les identifiants sauvegardés
            withAnimation(.easeInOut(duration: 0.5)) {
                navigateToLogin = true
            }
        } catch let signOutError as NSError {
            print("Erreur de déconnexion: \(signOutError.localizedDescription)")
        }
    }
    
    @ViewBuilder
    private func destinationView() -> some View {
        // Try multiple approaches to find the plant2.usdz file
        let modelURL = findModelURL()
        
        if let url = modelURL {
            ARViewWrapper(modelURL: url)
        } else {
            ARViewWrapper(modelURL: URL(string: "fallback://test")!)
        }
    }
    
    private func findModelURL() -> URL? {
        // Method 1: Try finding in Assets subdirectory
        if let bundleURL = Bundle.main.url(forResource: "plant2", withExtension: "usdz", subdirectory: "Assets") {
            print("✅ Found plant2.usdz in Assets subdirectory: \(bundleURL)")
            return bundleURL
        }
        // Method 2: Try finding in main bundle without subdirectory
        else if let bundleURL = Bundle.main.url(forResource: "plant2", withExtension: "usdz") {
            print("✅ Found plant2.usdz in main bundle: \(bundleURL)")
            return bundleURL
        }
        // Method 3: Try manual path construction
        else if let bundlePath = Bundle.main.path(forResource: "plant2", ofType: "usdz", inDirectory: "Assets") {
            let url = URL(fileURLWithPath: bundlePath)
            print("✅ Found plant2.usdz via path construction: \(url)")
            return url
        }
        
        print("❌ Could not find plant2.usdz file - using fallback")
        return nil
    }
}
