import SwiftUI
import ARKit
import SceneKit
import FirebaseAuth

// MARK: - ShareSheet (Partage de photo)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - SinglePlantARContainer (Le Moteur AR)

struct SinglePlantARContainer: UIViewRepresentable {
    let modelURL: URL
    @Binding var shouldCapture: Bool
    @Binding var capturedImage: UIImage?
    @Binding var isImageReady: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> ARSCNView {
        // 1. Initialisation SceneKit (Stable sur iPhone 16 Pro)
        let sceneView = ARSCNView(frame: UIScreen.main.bounds)
        sceneView.autoenablesDefaultLighting = true
        
        // 2. Configuration AR
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal] // On cherche le sol
        config.environmentTexturing = .automatic
        
        // Anti-Ecran Noir : on laisse la config standard sans forcer le LiDAR
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            // config.frameSemantics.insert(.sceneDepth) // Désactivé pour stabilité
        }
        
        sceneView.session.delegate = context.coordinator
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        
        // 3. Ajout du Geste "Tap" (Pour poser la plante)
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        sceneView.addGestureRecognizer(tapGesture)
        
        // 4. Coaching Overlay (Aide visuelle pour trouver le sol)
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.goal = .horizontalPlane
        coachingOverlay.session = sceneView.session
        coachingOverlay.activatesAutomatically = true
        sceneView.addSubview(coachingOverlay)
        
        // Stockage pour la capture
        context.coordinator.arView = sceneView
        
        return sceneView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Gestion de la capture photo
        if shouldCapture {
            DispatchQueue.main.async {
                let image = uiView.snapshot()
                self.capturedImage = image
                self.isImageReady = true
                self.shouldCapture = false
            }
        }
    }

    // MARK: - Teardown
    // SwiftUI invokes this when ARViewWrapper is dismissed. Without it the
    // ARSession kept running after the user left the AR flow, the loaded
    // USDZ scene stayed parented to the ARSCNView, and the camera pipeline
    // kept delivering frames into a dangling delegate. Repeatedly entering
    // and leaving the AR view compounded the leak and was the main cause
    // of the jetsam OOM crash reported by iOS on the iPhone 17 Pro.
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
        uiView.session.delegate = nil
        uiView.scene.rootNode.childNodes.forEach { $0.removeFromParentNode() }
        uiView.scene = SCNScene() // drop the loaded USDZ geometry entirely
        coordinator.currentPlantNode = nil
        coordinator.arView = nil
        print("🧹 SinglePlantARContainer dismantled — AR session paused, scene cleared")
    }

    // MARK: - Coordinator (Logique)
    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        var parent: SinglePlantARContainer
        weak var arView: ARSCNView?

        // Référence à la plante actuelle pour la déplacer si besoin
        var currentPlantNode: SCNNode?

        init(_ parent: SinglePlantARContainer) {
            self.parent = parent
        }

        deinit {
            currentPlantNode = nil
            print("🧹 SinglePlantARContainer.Coordinator deinit")
        }
        
        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView = arView else { return }
            let location = sender.location(in: arView)
            
            // 1. Raycast vers le sol
            guard let query = arView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal),
                  let result = arView.session.raycast(query).first else {
                print("⚠️ Aucun sol détecté. Bougez l'iPhone.")
                return
            }
            
            // 2. Placer le modèle
            placeModel(at: result.worldTransform)
        }
        
        func placeModel(at transform: simd_float4x4) {
            guard let arView = arView else { return }
            
            // A. Si la plante existe déjà, on la déplace
            if let existingNode = currentPlantNode {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.5
                
                // Mise à jour de la position
                existingNode.simdTransform = transform
                
                // Force la verticalité (on ignore la rotation du sol si elle est penchée)
                let pos = SCNVector3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                existingNode.position = pos
                existingNode.rotation = SCNVector4(0, 1, 0, 0)
                
                SCNTransaction.commit()
                
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return
            }
            
            // B. Sinon, on charge et on crée la plante
            do {
                let scene = try SCNScene(url: parent.modelURL, options: nil)
                
                // Conteneur principal
                let containerNode = SCNNode()
                
                // Ajout du contenu 3D
                let modelNode = SCNNode()
                for child in scene.rootNode.childNodes {
                    modelNode.addChildNode(child)
                }
                
                // --- CORRECTION TAILLE ET PIVOT ---
                
                // 1. Calculer la taille réelle
                let (minVec, maxVec) = modelNode.boundingBox
                let rawHeight = maxVec.y - minVec.y
                
                // 2. Mise à l'échelle (Cible : 50 cm)
                let targetHeight: Float = 0.50
                let scale = (rawHeight > 0) ? (targetHeight / rawHeight) : 1.0
                modelNode.scale = SCNVector3(scale, scale, scale)
                
                // 3. Correction Pivot (Poser les pieds au sol)
                // On remonte le modèle de la valeur de son point le plus bas
                modelNode.position.y = -minVec.y * scale
                
                // --- FIN CORRECTION ---
                
                containerNode.addChildNode(modelNode)
                
                // Placement initial
                containerNode.simdTransform = transform
                containerNode.position = SCNVector3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                
                // Animation d'apparition (Pop)
                containerNode.scale = SCNVector3(0,0,0)
                arView.scene.rootNode.addChildNode(containerNode)
                
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.5
                containerNode.scale = SCNVector3(1, 1, 1)
                SCNTransaction.commit()
                
                // Sauvegarde de la référence
                currentPlantNode = containerNode
                
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                print("✅ Plante placée avec succès")
                
            } catch {
                print("❌ Erreur chargement modèle: \(error)")
            }
        }
    }
}

// MARK: - ARViewWrapper (L'interface autour de la caméra)

struct ARViewWrapper: View {
    let modelURL: URL

    @Environment(\.presentationMode) var presentationMode
    @State private var showShareSheet = false
    @State private var capturedImage: UIImage?
    @State private var isImageReady = false
    
    // Trigger pour la capture
    @State private var captureTrigger = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Vue AR (utilise le container SceneKit)
            SinglePlantARContainer(
                modelURL: modelURL,
                shouldCapture: $captureTrigger,
                capturedImage: $capturedImage,
                isImageReady: $isImageReady
            )
            .ignoresSafeArea(.all)

            // Bouton Retour
            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .padding()

            // Bouton Photo (Bas de l'écran)
            VStack {
                Spacer()
                
                // Instruction text
                Text("Touchez le sol pour placer la plante")
                    .font(.caption)
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(.bottom, 10)
                
                Button(action: {
                    captureTrigger = true
                }) {
                    HStack {
                        Image(systemName: "camera.fill").font(.title)
                        Text("Prendre une photo").fontWeight(.bold)
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
        // Gestion de l'affichage de la photo prise
        .onChange(of: isImageReady) { _, ready in
            if ready {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { showShareSheet = true }
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: { isImageReady = false }) {
            if let image = capturedImage { ShareSheet(items: [image]) }
        }
    }
}

// MARK: - ARPage (Menu Principal)

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
                    // Image d'en-tête
                    Image("plantes")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: UIScreen.main.bounds.height * 0.35)
                        .clipped()
                        .frame(height: 180)

                    // Contenu Carte
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

                        Text("Découvrez cet arbre en réalité augmentée")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        Spacer(minLength: 20)

                        // Bouton Lancer AR
                        NavigationLink(destination: destinationView()) {
                            HStack {
                                Image(systemName: "camera.viewfinder")
                                Text("Lancer l'AR")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green.opacity(0.9))
                            .foregroundColor(.white)
                            .cornerRadius(15)
                            .shadow(radius: 3)
                        }

                        // Indicateur de compatibilité
                        if ARWorldTrackingConfiguration.isSupported {
                            Text("AR Ready")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Text("AR Not Supported")
                                .foregroundColor(.red)
                                .font(.caption)
                        }

                        // Bouton Déconnexion
                        Button(action: { logout() }) {
                            Text("Déconnexion")
                                .fontWeight(.bold)
                                .frame(width: 140, height: 40)
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
                        .frame(minHeight: 100, maxHeight: 150)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .offset(y: -40)
                    .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                }
            }
            .navigationBarBackButtonHidden(true)
            .fullScreenCover(isPresented: $navigateToLogin) {
                // Remplace par ta vraie vue LoginView()
                LoginView()
                    .transition(.move(edge: .trailing))
                    .animation(.easeInOut(duration: 0.5), value: navigateToLogin)
            }
            .onAppear {
                fetchUserName()
            }
        }
    }

    // MARK: - Logic Helpers

    private func fetchUserName() {
        if let user = Auth.auth().currentUser {
            if let displayName = user.displayName {
                userName = displayName
            } else if let email = user.email {
                userName = email.components(separatedBy: "@").first ?? "Utilisateur"
            }
        }
    }
    
    public func logout() {
        do {
            try Auth.auth().signOut()
            print("Utilisateur déconnecté avec succès")
            withAnimation(.easeInOut(duration: 0.5)) {
                navigateToLogin = true
            }
        } catch let signOutError as NSError {
            print("Erreur de déconnexion: \(signOutError.localizedDescription)")
        }
    }
    
    // MARK: - Destination AR Helper

    @ViewBuilder
    private func destinationView() -> some View {
        if let url = plant.bundleModelURL {
            ARViewWrapper(modelURL: url)
        } else if let url = findModelURL() {
            ARViewWrapper(modelURL: url)
        } else {
            VStack {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text("Aucun modèle 3D trouvé.")
                    .padding()
                Text("Fichier cherché : \(plant.modelURL ?? "inconnu")")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
    
    private func findModelURL() -> URL? {
        // 1. Cherche le modèle spécifique à la plante
        if let modelName = plant.modelURL {
            let name = modelName.replacingOccurrences(of: ".usdz", with: "")
            if let url = Bundle.main.url(forResource: name, withExtension: "usdz") {
                return url
            }
        }
        
        // 2. Fallback sur un modèle par défaut (plant2)
        if let bundleURL = Bundle.main.url(forResource: "plant2", withExtension: "usdz") {
            return bundleURL
        }
        
        return nil
    }
}
