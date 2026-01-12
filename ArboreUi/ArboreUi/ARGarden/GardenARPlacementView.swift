import SwiftUI
import ARKit
import SceneKit
import Foundation
import simd

// MARK: - Modèles de Données pour la Persistance
struct PersistedARScene: Codable {
    let savedAt: Date
    let plants: [PersistedPlant]
}

struct PersistedPlant: Codable {
    let plantID: String
    let plantName: String
    let modelURLString: String // L'URL ou le nom du fichier .usdz
    let position: [Float]      // [x, y, z]
    let rotation: [Float]      // [x, y, z] (Euler angles)
    let scale: [Float]         // [x, y, z]
    let transform: [Float]     // Matrice 4x4 aplatie (16 floats)
}

// MARK: - Mode & Notifications
enum GardenARMode {
    case create
    case reopen
}

extension Notification.Name {
    static let gardenARValidate = Notification.Name("gardenARValidate")
    static let gardenARUndo = Notification.Name("gardenARUndo")
    static let gardenARRedo = Notification.Name("gardenARRedo")
    static let gardenARDelete = Notification.Name("gardenARDelete")
    static let gardenARRotate = Notification.Name("gardenARRotate")
    static let gardenARScaleUp = Notification.Name("gardenARScaleUp")
    static let gardenARScaleDown = Notification.Name("gardenARScaleDown")
}

// MARK: - Stockage Local (Gestionnaire de Fichiers)
fileprivate enum GardenLocalStore {
    static func worldMapURL(for gardenId: String) -> URL {
        documentsURL().appendingPathComponent("worldmap_\(gardenId).arexperience")
    }
    static func sceneURL(for gardenId: String) -> URL {
        documentsURL().appendingPathComponent("scene_\(gardenId).json")
    }
    private static func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

// MARK: - Vue Principale SwiftUI
struct GardenARPlacementView: View {
    let selectedPlants: [Plant]
    let uid: String
    let wizard: GardenWizardDTO
    let gardenName: String
    let thumbnailKey: String?
    let existingGardenId: String? // Important pour la sauvegarde/restauration
    let mode: GardenARMode
    let onValidated: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var selectedPlantForPlacement: Plant? = nil
    @State private var hasSelectedNode = false
    @State private var selectedNodeName: String? = nil
    @State private var isSaving = false // Feedback visuel

    var body: some View {
        ZStack {
            // Vue AR
            GardenARPlacementContainerView(
                selectedPlant: $selectedPlantForPlacement,
                hasSelectedNode: $hasSelectedNode,
                selectedNodeName: $selectedNodeName,
                isSaving: $isSaving,
                uid: uid,
                wizard: wizard,
                gardenName: gardenName,
                thumbnailKey: thumbnailKey,
                existingGardenId: existingGardenId,
                mode: mode,
                onValidated: {
                    dismiss()
                    onValidated()
                }
            )
            .ignoresSafeArea()
            
            // Interface Utilisateur (HUD)
            VStack(spacing: 0) {
                topBar
                Spacer()
                
                if isSaving {
                    savingIndicator
                }
                
                if hasSelectedNode {
                    editingHUD.transition(.move(edge: .bottom).combined(with: .opacity))
                }
                bottomDock
            }
        }
        .sheet(isPresented: $showPicker) {
            PlantCatalogARView { plant in
                selectedPlantForPlacement = plant
            }
            .presentationDetents([.large])
            .presentationBackground(.clear)
        }
        .onAppear {
            if selectedPlantForPlacement == nil {
                selectedPlantForPlacement = selectedPlants.first
            }
        }
    }

    // MARK: - Composants UI
    
    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left").modifier(GlassButtonStyle())
            }
            Spacer()
            
            // Undo / Redo
            HStack(spacing: 20) {
                Button { NotificationCenter.default.post(name: .gardenARUndo, object: nil) } label: {
                    Image(systemName: "arrow.uturn.backward").modifier(GlassButtonStyle())
                }
                Button { NotificationCenter.default.post(name: .gardenARRedo, object: nil) } label: {
                    Image(systemName: "arrow.uturn.forward").modifier(GlassButtonStyle())
                }
            }
            
            Spacer()
            
            // Bouton Valider (Sauvegarder)
            Button {
                // Déclenche la notification de sauvegarde
                NotificationCenter.default.post(name: .gardenARValidate, object: nil)
            } label: {
                Image(systemName: "checkmark").modifier(GlassButtonStyle(isGreen: true))
            }
            .disabled(isSaving)
            .opacity(isSaving ? 0.5 : 1)
        }
        .padding(.horizontal, 20).padding(.top, 10)
    }

    private var editingHUD: some View {
        VStack(spacing: 12) {
            if let name = selectedNodeName {
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.7))
                    .clipShape(Capsule())
            }
            HStack(spacing: 12) {
                Button { NotificationCenter.default.post(name: .gardenARRotate, object: nil) } label: {
                    ActionButton(icon: "rotate.right", active: false)
                }
                Button { NotificationCenter.default.post(name: .gardenARScaleUp, object: nil) } label: {
                    ActionButton(icon: "plus.magnifyingglass", active: false)
                }
                Button { NotificationCenter.default.post(name: .gardenARScaleDown, object: nil) } label: {
                    ActionButton(icon: "minus.magnifyingglass", active: false)
                }
                Button { NotificationCenter.default.post(name: .gardenARDelete, object: nil) } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(.red.opacity(0.7))
                        .clipShape(Circle())
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
        }
        .padding(.bottom, 30)
    }

    private var bottomDock: some View {
        HStack {
            Spacer()
            Button { showPicker = true } label: {
                ZStack {
                    Circle().fill(Color(hex: "#2BEE79"))
                        .frame(width: 68, height: 68)
                        .shadow(color: Color(hex: "#2BEE79").opacity(0.4), radius: 15)
                    Image(systemName: "plus")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            Spacer()
        }
        .padding(.bottom, 20)
    }
    
    private var savingIndicator: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(.white)
            Text("Sauvegarde du jardin...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(12)
        .background(.black.opacity(0.6))
        .cornerRadius(12)
        .padding(.bottom, 10)
    }
}

// MARK: - Container AR (Logique SceneKit/ARKit)
fileprivate struct GardenARPlacementContainerView: UIViewRepresentable {
    @Binding var selectedPlant: Plant?
    @Binding var hasSelectedNode: Bool
    @Binding var selectedNodeName: String?
    @Binding var isSaving: Bool // Bind pour afficher le loader
    
    let uid: String
    let wizard: GardenWizardDTO
    let gardenName: String
    let thumbnailKey: String?
    let existingGardenId: String?
    let mode: GardenARMode
    let onValidated: () -> Void

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.autoenablesDefaultLighting = true
        sceneView.delegate = context.coordinator
        sceneView.session.delegate = context.coordinator
        
        // Configuration AR
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        
        // Si on rouvre, on essaiera de charger la WorldMap plus tard,
        // mais on lance une config clean d'abord.
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // Gestes
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapToPlace(_:)))
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPressToSelect(_:)))
        longPress.minimumPressDuration = 0.4
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        
        [tap, longPress, pan].forEach { sceneView.addGestureRecognizer($0) }

        context.coordinator.arView = sceneView
        context.coordinator.setupReticle()
        context.coordinator.parentProps = self
        context.coordinator.setupObservers()

        // Chargement différé si mode "reopen"
        if mode == .reopen, let id = existingGardenId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                context.coordinator.loadGardenFromDisk(gardenId: id)
            }
        }
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator (Le cerveau)
    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate, UIGestureRecognizerDelegate {
        var parentProps: GardenARPlacementContainerView?
        weak var arView: ARSCNView?
        
        private var reticleNode: SCNNode?
        private var lastReticleTransform: simd_float4x4?
        private var selectedNode: SCNNode?
        private var isRestoring = false // Pour éviter de déclencher des sélections pendant le chargement

        // Undo/Redo Stacks
        private var undoStack: [[PersistedPlant]] = []
        private var redoStack: [[PersistedPlant]] = []

        init(_ parent: GardenARPlacementContainerView) { self.parentProps = parent }

        func setupObservers() {
            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(handleValidateNotif), name: .gardenARValidate, object: nil)
            nc.addObserver(self, selector: #selector(handleDelete), name: .gardenARDelete, object: nil)
            nc.addObserver(self, selector: #selector(handleRotateAction), name: .gardenARRotate, object: nil)
            nc.addObserver(self, selector: #selector(handleScaleUpAction), name: .gardenARScaleUp, object: nil)
            nc.addObserver(self, selector: #selector(handleScaleDownAction), name: .gardenARScaleDown, object: nil)
            nc.addObserver(self, selector: #selector(handleUndo), name: .gardenARUndo, object: nil)
            nc.addObserver(self, selector: #selector(handleRedo), name: .gardenARRedo, object: nil)
        }
        
        func setupReticle() {
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.08, pipeRadius: 0.005))
            ring.geometry?.firstMaterial?.diffuse.contents = UIColor(hex: "#2BEE79")
            ring.opacity = 0
            reticleNode = ring
            arView?.scene.rootNode.addChildNode(ring)
        }

        // Boucle de rendu (60 fps)
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let arView = arView, let reticle = reticleNode else { return }
            
            // Raycast au centre de l'écran pour le placement
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            if let query = arView.raycastQuery(from: center, allowing: .existingPlaneGeometry, alignment: .horizontal),
               let result = arView.session.raycast(query).first {
                lastReticleTransform = result.worldTransform
                reticle.simdTransform = result.worldTransform
                reticle.opacity = 1
            } else {
                lastReticleTransform = nil
                reticle.opacity = 0
            }
        }
        
        // MARK: - Capture & Restauration (Le cœur de la sauvegarde)
        
        // 1. Capture l'état actuel de la scène
        private func captureCurrentState() -> [PersistedPlant] {
            guard let arView = arView else { return [] }
            
            // Filtrer uniquement les nœuds qui sont des plantes (identifiés par leur nom)
            let plantNodes = arView.scene.rootNode.childNodes.filter { $0.name?.starts(with: "plant_") == true }
            
            return plantNodes.map { node -> PersistedPlant in
                // Le nom est formaté : plant_{id}_{name}_{url}
                let parts = node.name?.components(separatedBy: "_") ?? []
                
                return PersistedPlant(
                    plantID: parts[safe: 1] ?? "unknown",
                    plantName: parts[safe: 2] ?? "Plante",
                    modelURLString: (parts[safe: 3] ?? "").removingPercentEncoding ?? "",
                    position: [node.position.x, node.position.y, node.position.z],
                    rotation: [node.eulerAngles.x, node.eulerAngles.y, node.eulerAngles.z],
                    scale: [node.scale.x, node.scale.y, node.scale.z],
                    transform: matrixToFloatArray(node.simdTransform) // On sauve aussi la matrice complète
                )
            }
        }

        // 2. Gestion de la sauvegarde au clic sur "Valider"
        @objc func handleValidateNotif() {
            guard let arView = arView, let props = parentProps else { return }
            
            // --- DIAGNOSTIC DEBOGAGE ---
            // On vérifie si ARKit a assez de données pour créer une map
            if let frame = arView.session.currentFrame {
                switch frame.worldMappingStatus {
                case .notAvailable, .limited:
                    print("⚠️ [AR DEBUG] Status: LIMITED. ARKit ne connait pas assez l'environnement.")
                    print("👉 Conseil : Bougez le téléphone latéralement pour scanner la zone avant de sauvegarder.")
                case .extending:
                    print("ℹ️ [AR DEBUG] Status: EXTENDING. La carte s'agrandit, c'est bon.")
                case .mapped:
                    print("✅ [AR DEBUG] Status: MAPPED. Environnement bien scanné.")
                @unknown default:
                    break
                }
            }
            // ---------------------------

            props.isSaving = true // Active le loader visuel
            
            // 1. Capturer les plantes
            let plantsForSave = captureCurrentState()
            
            // 2. Préparer les DTO pour l'API
            let placedDTOs = plantsForSave.map { p in
                PlacedPlantDTO(plantId: p.plantID, x: Double(p.position[0]), y: Double(p.position[1]), z: Double(p.position[2]), note: p.plantName)
            }

            // 3. Processus de sauvegarde (API + Local)
            Task {
                // A. Gestion de l'ID (Création ou Mise à jour API)
                var finalId: String
                do {
                    if let existing = props.existingGardenId {
                        finalId = existing
                        // Si tu as une route update, mets-la ici. Sinon on recrée/écrase via create si l'API le permet.
                         _ = try await GardenAPI.shared.createGarden(GardenCreateDTO(uid: props.uid, name: props.gardenName, wizard: props.wizard, plants: placedDTOs, thumbnailKey: props.thumbnailKey))
                    } else {
                        let created = try await GardenAPI.shared.createGarden(GardenCreateDTO(uid: props.uid, name: props.gardenName, wizard: props.wizard, plants: placedDTOs, thumbnailKey: props.thumbnailKey))
                        finalId = created.id ?? UUID().uuidString
                    }
                } catch {
                    print("⚠️ [API ERROR] Le serveur a échoué, mais on continue en local : \(error)")
                    finalId = props.existingGardenId ?? UUID().uuidString
                }
                
                // B. Sauvegarde LOCALE (Critique pour la persistance AR)
                await arView.session.getCurrentWorldMap { worldMap, error in
                    
                    // Gestion des erreurs ARKit
                    if let error = error {
                        print("❌ [AR ERROR] Impossible de générer la WorldMap : \(error.localizedDescription)")
                    }
                    
                    // Sauvegarde de la WorldMap (.arexperience)
                    if let map = worldMap {
                        do {
                            let mapData = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                            try mapData.write(to: GardenLocalStore.worldMapURL(for: finalId))
                            
                            let size = ByteCountFormatter.string(fromByteCount: Int64(mapData.count), countStyle: .file)
                            print("💾 [DISK SUCCESS] WorldMap sauvegardée (\(size)) pour ID: \(finalId)")
                        } catch {
                            print("❌ [DISK ERROR] Échec écriture fichier Map : \(error)")
                        }
                    } else {
                        print("⚠️ [AR WARNING] Map est nil. L'environnement n'a pas été scanné suffisamment ou le tracking est perdu.")
                    }
                    
                    // Sauvegarde du JSON (Positions des plantes)
                    // On le fait même si la map échoue, pour avoir au moins les plantes (même si elles flottent mal)
                    do {
                        let sceneData = PersistedARScene(savedAt: Date(), plants: plantsForSave)
                        let jsonData = try JSONEncoder().encode(sceneData)
                        try jsonData.write(to: GardenLocalStore.sceneURL(for: finalId))
                        print("📄 [DISK SUCCESS] Fichier JSON de scène sauvegardé.")
                    } catch {
                        print("❌ [DISK ERROR] Échec écriture JSON : \(error)")
                    }
                    
                    // C. Finalisation UI
                    DispatchQueue.main.async {
                        props.isSaving = false
                        props.onValidated()
                    }
                }
            }
        }
        
        // 3. Chargement depuis le disque
        func loadGardenFromDisk(gardenId: String) {
            guard let arView = arView else { return }
            print("📂 Chargement du jardin: \(gardenId)")
            
            isRestoring = true // Bloque les sélections
            
            do {
                // a. Charger la WorldMap AR
                let mapUrl = GardenLocalStore.worldMapURL(for: gardenId)
                if FileManager.default.fileExists(atPath: mapUrl.path) {
                    let mapData = try Data(contentsOf: mapUrl)
                    if let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: mapData) as? ARWorldMap {
                        print("🌍 WorldMap trouvée et chargée")
                        let config = ARWorldTrackingConfiguration()
                        config.initialWorldMap = worldMap
                        config.planeDetection = [.horizontal]
                        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
                    }
                } else {
                    print("⚠️ Pas de WorldMap trouvée, on charge juste les positions relatives.")
                }
                
                // b. Charger les plantes (JSON)
                let sceneUrl = GardenLocalStore.sceneURL(for: gardenId)
                if FileManager.default.fileExists(atPath: sceneUrl.path) {
                    let sceneJson = try Data(contentsOf: sceneUrl)
                    let sceneData = try JSONDecoder().decode(PersistedARScene.self, from: sceneJson)
                    
                    // Restauration visuelle
                    restoreScene(from: sceneData.plants)
                    print("🌱 \(sceneData.plants.count) plantes restaurées.")
                }
                
            } catch {
                print("❌ Erreur chargement disque : \(error)")
            }
            
            isRestoring = false
        }
        
        // 4. Recréation des noeuds 3D
        private func restoreScene(from plants: [PersistedPlant]) {
            guard let arView = arView else { return }
            
            // Nettoyer la scène existante
            arView.scene.rootNode.childNodes.forEach { node in
                if node.name?.starts(with: "plant_") == true {
                    node.removeFromParentNode()
                }
            }
            deselectAll()
            
            // Re-créer chaque plante
            for p in plants {
                // Reconstruire la matrice de position
                if let transform = floatArrayToMatrix(p.transform) {
                    // Créer un "faux" objet Plant pour réutiliser la fonction addPlant
                    // Note: assure-toi que p.modelURLString est valide
                    let stub = Plant.stubForRestore(id: p.plantID, name: p.plantName, type: "", modelURL: p.modelURLString)
                    
                    isRestoring = true
                    // On passe l'échelle sauvegardée pour qu'elle soit identique
                    addPlant(at: transform, plant: stub, finalScale: SCNVector3(p.scale[0], p.scale[1], p.scale[2]))
                    isRestoring = false
                }
            }
        }
        
        // MARK: - Gestion Undo / Redo
        private func saveStateForUndo() {
            let currentState = captureCurrentState()
            undoStack.append(currentState)
            redoStack.removeAll() // Nouvelle action casse le redo futur
            
            // Limite la taille de la pile (optionnel)
            if undoStack.count > 10 { undoStack.removeFirst() }
        }
        
        @objc func handleUndo() {
            guard let previousState = undoStack.popLast() else { return }
            let currentState = captureCurrentState()
            redoStack.append(currentState)
            restoreScene(from: previousState)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        
        @objc func handleRedo() {
            guard let nextState = redoStack.popLast() else { return }
            let currentState = captureCurrentState()
            undoStack.append(currentState)
            restoreScene(from: nextState)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        // MARK: - Actions de Transformation (Rotate, Scale, Delete)
        @objc func handleRotateAction() {
            guard let node = selectedNode else { return }
            saveStateForUndo()
            node.runAction(SCNAction.rotateBy(x: 0, y: .pi/4, z: 0, duration: 0.2))
        }

        @objc func handleScaleUpAction() {
            guard let node = selectedNode else { return }
            saveStateForUndo()
            node.runAction(SCNAction.scale(by: 1.1, duration: 0.2))
        }

        @objc func handleScaleDownAction() {
            guard let node = selectedNode else { return }
            saveStateForUndo()
            node.runAction(SCNAction.scale(by: 0.9, duration: 0.2))
        }

        @objc func handleDelete() {
            guard let node = selectedNode else { return }
            saveStateForUndo()
            node.removeFromParentNode()
            deselectAll()
        }

        // MARK: - Interactions (Tap, Long Press, Pan)
        @objc func handleTapToPlace(_ gesture: UITapGestureRecognizer) {
            guard let transform = lastReticleTransform, let plant = parentProps?.selectedPlant else {
                deselectAll()
                return
            }
            saveStateForUndo()
            addPlant(at: transform, plant: plant)
        }

        @objc func handleLongPressToSelect(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let arView = arView else { return }
            let location = gesture.location(in: arView)
            let hits = arView.hitTest(location, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            
            if let result = hits.first(where: { isPlantNode($0.node) }) {
                selectNode(findPlantRoot(result.node))
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let node = selectedNode, let arView = arView else { return }
            
            if gesture.state == .began {
                saveStateForUndo()
            }
            
            let location = gesture.location(in: arView)
            // On déplace l'objet sur le plan horizontal détecté
            if let query = arView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal),
               let result = arView.session.raycast(query).first {
                // On met à jour seulement la position (colonnes.3), on garde la rotation/scale
                node.simdWorldPosition = simd_float3(result.worldTransform.columns.3.x, result.worldTransform.columns.3.y, result.worldTransform.columns.3.z)
            }
        }

        // Fonction générique pour ajouter une plante
        func addPlant(at transform: simd_float4x4, plant: Plant, finalScale: SCNVector3? = nil) {
            guard let arView = arView, let url = plant.localModelURL else {
                print("⚠️ Impossible de charger le modèle pour: \(plant.name)")
                return
            }
            
            do {
                let scene = try SCNScene(url: url, options: nil)
                let container = SCNNode()
                // Encodage de l'URL dans le nom pour la persistance
                let encodedURL = plant.modelURL?.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "default"
                container.name = "plant_\(plant.id)_\(plant.name)_\(encodedURL)"

                for child in scene.rootNode.childNodes { container.addChildNode(child) }
                container.simdTransform = transform

                // Gestion de l'échelle (soit restaurée, soit calculée par défaut)
                if let scale = finalScale {
                    container.scale = scale
                } else if !isRestoring {
                    // Calcul auto de la taille pour que ça ne soit pas géant
                    let (minVec, maxVec) = container.boundingBox
                    let rawHeight = maxVec.y - minVec.y
                    if rawHeight > 0 {
                        let targetHeight: Float = 0.5 // 50cm par défaut
                        let scaleFactor = targetHeight / rawHeight
                        container.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
                        // Ajuster le pivot pour que la base soit au sol
                        container.pivot = SCNMatrix4MakeTranslation(0, minVec.y, 0)
                    }
                }
                
                arView.scene.rootNode.addChildNode(container)
                
                if !isRestoring {
                    selectNode(container)
                }
            } catch {
                print("❌ Erreur chargement modèle 3D: \(error)")
            }
        }

        // Helpers de sélection
        private func selectNode(_ node: SCNNode) {
            deselectAll()
            selectedNode = node
            parentProps?.hasSelectedNode = true
            parentProps?.selectedNodeName = node.name?.components(separatedBy: "_")[safe: 2] ?? "Plante"
            
            // Petit effet visuel de sélection (ex: bounding box jaune)
            let box = SCNBox(width: 0.3, height: 0.01, length: 0.3, chamferRadius: 0)
            let boxNode = SCNNode(geometry: box)
            boxNode.geometry?.firstMaterial?.diffuse.contents = UIColor.yellow.withAlphaComponent(0.3)
            boxNode.position = SCNVector3(0, 0.01, 0)
            boxNode.name = "selection_indicator"
            // node.addChildNode(boxNode) // Décommenter si tu veux un highlight visuel
        }
        
        private func deselectAll() {
            // Nettoyer indicateurs visuels si besoin
            selectedNode?.childNode(withName: "selection_indicator", recursively: false)?.removeFromParentNode()
            
            selectedNode = nil
            parentProps?.hasSelectedNode = false
            parentProps?.selectedNodeName = nil
        }
        
        private func isPlantNode(_ node: SCNNode) -> Bool {
            var current: SCNNode? = node
            while current != nil {
                if current?.name?.starts(with: "plant_") == true { return true }
                current = current?.parent
            }
            return false
        }
        
        private func findPlantRoot(_ node: SCNNode) -> SCNNode {
            var curr = node
            while let p = curr.parent, p.name?.starts(with: "plant_") == false { curr = p }
            return curr.parent?.name?.starts(with: "plant_") == true ? curr.parent! : curr
        }
    }
}

// MARK: - Extensions & Utilitaires Manquants

// 1. Extension pour l'accès sécurisé aux tableaux (évite les crashs "Index out of range")
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// 2. Fonctions de conversion Matrice <-> Tableau de Float (pour le JSON)
func matrixToFloatArray(_ m: simd_float4x4) -> [Float] {
    [
        m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.0.w,
        m.columns.1.x, m.columns.1.y, m.columns.1.z, m.columns.1.w,
        m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.2.w,
        m.columns.3.x, m.columns.3.y, m.columns.3.z, m.columns.3.w
    ]
}

func floatArrayToMatrix(_ a: [Float]) -> simd_float4x4? {
    guard a.count == 16 else { return nil }
    return simd_float4x4(
        simd_float4(a[0], a[1], a[2], a[3]),
        simd_float4(a[4], a[5], a[6], a[7]),
        simd_float4(a[8], a[9], a[10], a[11]),
        simd_float4(a[12], a[13], a[14], a[15])
    )
}

// 3. Style des boutons (HUD)
struct ActionButton: View {
    let icon: String
    let active: Bool
    
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(active ? .black : .white)
            .frame(width: 48, height: 48)
            // Assure-toi d'avoir ton extension Color(hex:) quelque part dans le projet,
            // sinon remplace Color(hex: "#2BEE79") par Color.green
            .background(active ? Color(hex: "#2BEE79") : .white.opacity(0.15))
            .clipShape(Circle())
    }
}

// 4. Modifier pour les boutons "Glass" (Retour, Undo, Validate)
struct GlassButtonStyle: ViewModifier {
    var isGreen: Bool = false
    
    func body(content: Content) -> some View {
        content
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 44, height: 44)
            .background(isGreen ? Color(hex: "#2BEE79") : .black.opacity(0.35))
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
    }
}
