import SwiftUI
import ARKit
import SceneKit // ✅ SceneKit pour la stabilité
import Combine
import Foundation
import simd

// MARK: - Vue Principale (Interface)
struct GardenARPlacementView: View {
    let selectedPlants: [Plant]
    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false
    @State private var selectedPlantForPlacement: Plant? = nil

    var body: some View {
        ZStack {
            // ✅ Container SceneKit
            GardenARPlacementContainerView(selectedPlant: $selectedPlantForPlacement)
                .ignoresSafeArea()

            if !showPicker {
                bottomGradient
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
            }
            .safeAreaInset(edge: .bottom) {
                bottomContent
            }
        }
        .sheet(isPresented: $showPicker) {
            // Assure-toi que cette vue existe dans ton projet
            PlantCatalogARView { plant in
                selectedPlantForPlacement = plant
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(.clear)
        }
        .onAppear {
            if selectedPlantForPlacement == nil {
                selectedPlantForPlacement = selectedPlants.first
            }
        }
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.20))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 1))
            }

            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            titlePill.padding(.top, 6)
        }
    }

    private var titlePill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: "#2BEE79"))
                .frame(width: 8, height: 8)
                .shadow(color: Color(hex: "#2BEE79").opacity(0.8), radius: 8)

            Text("PLACEMENT AR")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .tracking(1.1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.20))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
    }

    // MARK: - Bottom UI
    private var bottomGradient: some View {
        VStack {
            Spacer()
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.40), .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 320)
        }
    }

    private var bottomContent: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text("Touchez une surface pour placer une plante")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.90))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 2)

                if let p = selectedPlantForPlacement {
                    Text("Plante active : \(p.name)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.80))
                } else {
                    Text("Aucune plante sélectionnée")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.80))
                }
            }

            // Save / Load Buttons
            HStack(spacing: 12) {
                Button {
                    NotificationCenter.default.post(name: .gardenARSave, object: nil)
                } label: {
                    Text("Save")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: 44)
                        .background(Color.black.opacity(0.25))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
                }

                Button {
                    NotificationCenter.default.post(name: .gardenARLoad, object: nil)
                } label: {
                    Text("Load")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: 44)
                        .background(Color.black.opacity(0.25))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
                }
            }
            .padding(.top, 2)

            Button { showPicker = true } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.12))
                            .frame(width: 34, height: 34)
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(hex: "#102217"))
                    }

                    Text("Choisir une plante")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: "#102217"))
                }
                .padding(.horizontal, 18)
                .frame(height: 64)
                .background(Color(hex: "#2BEE79"))
                .clipShape(Capsule())
                .shadow(color: Color(hex: "#2BEE79").opacity(0.35), radius: 18, x: 0, y: 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }
}

// MARK: - AR View Container (SceneKit Version)

fileprivate struct GardenARPlacementContainerView: UIViewRepresentable {
    @Binding var selectedPlant: Plant?

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)

        // Configuration
        sceneView.autoenablesDefaultLighting = true
        sceneView.delegate = context.coordinator
        sceneView.session.delegate = context.coordinator

        // Configuration AR Standard
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        
        // Pas de LiDAR explicite pour éviter les conflits graphiques
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            // config.frameSemantics.insert(.sceneDepth) // Désactivé
        }

        DispatchQueue.main.async {
            sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }

        // Gesture
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(GardenCoordinator.handleTapPlace(_:))
        )
        sceneView.addGestureRecognizer(tapGesture)

        context.coordinator.arView = sceneView
        context.coordinator.setupReticle()
        context.coordinator.currentPlant = selectedPlant

        // Notifications
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(GardenCoordinator.handleSaveNotif),
            name: .gardenARSave,
            object: nil
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(GardenCoordinator.handleLoadNotif),
            name: .gardenARLoad,
            object: nil
        )

        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.currentPlant = selectedPlant
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: GardenCoordinator) {
        uiView.session.pause()
    }

    func makeCoordinator() -> GardenCoordinator {
        GardenCoordinator(self)
    }

    // MARK: - Coordinator SceneKit
    final class GardenCoordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        var parent: GardenARPlacementContainerView
        weak var arView: ARSCNView?

        var currentPlant: Plant?
        private var placedPlants: [PersistedPlant] = []

        // SceneKit Nodes
        private var reticleNode: SCNNode?
        private var lastReticleTransform: simd_float4x4?

        init(_ parent: GardenARPlacementContainerView) {
            self.parent = parent
            super.init()
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        // MARK: - ARSessionDelegate
        func session(_ session: ARSession, didFailWithError error: Error) {
            print("❌ AR Error: \(error.localizedDescription)")
        }

        func sessionWasInterrupted(_ session: ARSession) {
            print("⚠️ AR Interrupted")
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            print("✅ AR Resumed")
        }

        // MARK: - Reticle Logic (SceneKit)
        func setupReticle() {
            let planeGeo = SCNPlane(width: 0.22, height: 0.22)
            
            if let image = UIImage(named: "placement_ring") {
                planeGeo.firstMaterial?.diffuse.contents = image
            } else {
                planeGeo.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.8)
                planeGeo.cornerRadius = 0.11
            }
            
            planeGeo.firstMaterial?.lightingModel = .constant
            planeGeo.firstMaterial?.writesToDepthBuffer = false
            planeGeo.firstMaterial?.readsFromDepthBuffer = false
            
            let node = SCNNode(geometry: planeGeo)
            node.eulerAngles.x = -.pi / 2
            node.opacity = 0
            
            reticleNode = node
            arView?.scene.rootNode.addChildNode(node)
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let arView = arView, let reticleNode = reticleNode else { return }
            
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            
            if let query = arView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .horizontal),
               let result = arView.session.raycast(query).first {
                
                lastReticleTransform = result.worldTransform
                
                reticleNode.simdTransform = result.worldTransform
                reticleNode.position.y += 0.005
                
                let scale = 1.0 + 0.05 * Float(sin(time * 5.0))
                reticleNode.scale = SCNVector3(scale, scale, scale)
                
                if reticleNode.opacity < 1.0 { reticleNode.opacity += 0.1 }
                
            } else {
                lastReticleTransform = nil
                if reticleNode.opacity > 0 { reticleNode.opacity -= 0.1 }
            }
        }

        // MARK: - Tap & Place
        @objc func handleTapPlace(_ sender: UITapGestureRecognizer) {
            guard let arView = arView, let transform = lastReticleTransform else {
                print("⚠️ Pas de surface détectée pour placer la plante")
                return
            }
            
            guard let plant = currentPlant else { return }
            
            if let modelURL = plant.localModelURL {
                addPlantNode(at: transform, modelURL: modelURL, plant: plant)
            } else {
                addFallbackCylinder(at: transform)
            }
        }
        
        func addPlantNode(at transform: simd_float4x4, modelURL: URL, plant: Plant) {
                    guard let arView = arView else { return }
                    
                    do {
                        // 1. Chargement de la scène
                        let scene = try SCNScene(url: modelURL, options: nil)
                        
                        // 2. Création d'un wrapper (Conteneur principal)
                        // C'est lui qu'on va déplacer sur le sol.
                        let containerNode = SCNNode()
                        containerNode.name = "plant_\(plant.id)"
                        
                        // 3. Création du noeud du modèle (Contenu visuel)
                        let modelNode = SCNNode()
                        for child in scene.rootNode.childNodes {
                            modelNode.addChildNode(child)
                        }
                        
                        // 4. CALCUL DE LA BOITE ENGLOBANTE (Bounding Box)
                        // Cela nous donne la vraie taille brute du modèle
                        let (minVec, maxVec) = modelNode.boundingBox
                        let rawHeight = maxVec.y - minVec.y
                        
                        // 5. MISE A L'ECHELLE (SCALE)
                        // On veut que la plante fasse une taille réaliste (ex: 50cm = 0.5m)
                        // Si la hauteur brute est 0 (bug modèle), on met 1 par défaut.
                        let targetHeight: Float = 0.5 // 50 cm
                        let scaleFactor = (rawHeight > 0) ? (targetHeight / rawHeight) : 1.0
                        
                        modelNode.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
                        
                        // 6. CORRECTION DU PIVOT (Pivot Point)
                        // On décale le modèle vers le haut pour que ses pieds (minVec.y) soient à 0
                        // Sinon, le modèle est centré sur le point d'ancrage (donc à moitié dans le sol)
                        modelNode.position.y = -minVec.y * scaleFactor
                        
                        // 7. Assemblage
                        containerNode.addChildNode(modelNode)
                        
                        // 8. PLACEMENT FINAL
                        // On applique la position détectée par l'AR (le sol) au conteneur
                        containerNode.simdTransform = transform
                        
                        // On s'assure qu'il est bien vertical (ignore la rotation du sol si le sol est un peu penché)
                        // On garde juste la position X, Y, Z
                        let position = SCNVector3(
                            transform.columns.3.x,
                            transform.columns.3.y,
                            transform.columns.3.z
                        )
                        containerNode.position = position
                        // On réinitialise la rotation pour qu'elle soit droite, face caméra si besoin (optionnel)
                        containerNode.rotation = SCNVector4(0, 1, 0, 0)
                        
                        // 9. Ajout à la scène
                        arView.scene.rootNode.addChildNode(containerNode)
                        
                        // 10. Persistence & Feedback
                        let persisted = PersistedPlant(
                            plantID: plant.id,
                            plantName: plant.name,
                            modelURLString: plant.modelURL ?? "",
                            transform: matrixToFloatArray(transform)
                        )
                        placedPlants.append(persisted)
                        
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        
                        print("✅ Plante placée : Hauteur brute \(rawHeight)m -> Redimensionnée à \(targetHeight)m")
                        
                    } catch {
                        print("❌ Erreur chargement USDZ SceneKit: \(error)")
                    }
                }
        
        func addFallbackCylinder(at transform: simd_float4x4) {
            let cylinder = SCNCylinder(radius: 0.05, height: 0.2)
            cylinder.firstMaterial?.diffuse.contents = UIColor(Color(hex: "#2BEE79"))
            
            let node = SCNNode(geometry: cylinder)
            node.simdTransform = transform
            node.position.y += 0.1
            
            arView?.scene.rootNode.addChildNode(node)
        }

        // MARK: - Save / Load Logic
        
        @objc func handleSaveNotif() {
            guard let arView = arView else { return }
            
            arView.session.getCurrentWorldMap { [weak self] worldMap, error in
                guard let self = self, let map = worldMap else { return }
                
                do {
                    let mapData = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                    try mapData.write(to: worldMapFileURL, options: [.atomic])
                    
                    let sceneData = PersistedARScene(savedAt: Date(), plants: self.placedPlants)
                    let json = try JSONEncoder().encode(sceneData)
                    try json.write(to: sceneFileURL, options: [.atomic])
                    
                    print("✅ Sauvegarde SceneKit réussie")
                    // ✅ CORRECTION ICI : Utilisation de UINotificationFeedbackGenerator
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } catch {
                    print("❌ Erreur sauvegarde: \(error)")
                }
            }
        }
        
        @objc func handleLoadNotif() {
            guard let arView = arView else { return }
            
            do {
                let mapData = try Data(contentsOf: worldMapFileURL)
                guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: mapData) else { return }
                
                let sceneJson = try Data(contentsOf: sceneFileURL)
                let persistedScene = try JSONDecoder().decode(PersistedARScene.self, from: sceneJson)
                
                let config = ARWorldTrackingConfiguration()
                config.planeDetection = [.horizontal, .vertical]
                config.initialWorldMap = worldMap
                
                arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
                
                arView.scene.rootNode.childNodes.forEach { node in
                    if node.name?.starts(with: "plant_") == true {
                        node.removeFromParentNode()
                    }
                }
                self.placedPlants.removeAll()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    for p in persistedScene.plants {
                        guard let transform = floatArrayToMatrix(p.transform) else { continue }
                        
                        let tempPlant = Plant.stubForRestore(
                            id: p.plantID,
                            name: p.plantName,
                            type: "",
                            modelURL: p.modelURLString
                        )
                        
                        if let url = resourceURLFromModelURLString(p.modelURLString) {
                            self.addPlantNode(at: transform, modelURL: url, plant: tempPlant)
                        }
                    }
                }
                
                print("✅ Chargement SceneKit réussi")
                // ✅ CORRECTION ICI : Utilisation de UINotificationFeedbackGenerator
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                
            } catch {
                print("❌ Erreur chargement: \(error)")
            }
        }
    }
}
