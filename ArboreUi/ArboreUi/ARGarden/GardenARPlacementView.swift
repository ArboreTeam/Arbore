import SwiftUI
import ARKit
import SceneKit
import Foundation
import simd

// NOTE: Les modèles de données (PersistedARScene, PersistedPlant)
// et GardenLocalStore doivent être présents dans le fichier "GardenDataModels.swift".

// MARK: - 1. Extensions & Utilitaires
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

// MARK: - 2. Vue Principale SwiftUI
struct GardenARPlacementView: View {
    let selectedPlants: [Plant]
    let uid: String
    let wizard: GardenWizardDTO
    let gardenName: String
    let thumbnailKey: String?
    let existingGardenId: String?
    let mode: GardenARMode
    
    // 🆕 Données de mesure du jardin
    let boundaryPoints: [SIMD3<Float>]
    let area: Float
    let perimeter: Float
    let measurementWorldMapId: String?  // 🆕 ID pour charger la WorldMap de mesure
    
    let onValidated: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var selectedPlantForPlacement: Plant? = nil
    @State private var hasSelectedNode = false
    @State private var selectedNodeName: String? = nil
    @State private var isSaving = false

    // Model download state
    @State private var downloadedModelURL: URL? = nil
    @State private var isDownloadingModel = false
    @State private var isRelocating = false

    var body: some View {
        ZStack {
            // --- Vue AR ---
            GardenARPlacementContainerView(
                selectedPlant: $selectedPlantForPlacement,
                downloadedModelURL: $downloadedModelURL,
                isDownloadingModel: $isDownloadingModel,
                hasSelectedNode: $hasSelectedNode,
                selectedNodeName: $selectedNodeName,
                isSaving: $isSaving,
                isRelocating: $isRelocating,
                uid: uid,
                wizard: wizard,
                gardenName: gardenName,
                thumbnailKey: thumbnailKey,
                existingGardenId: existingGardenId,
                mode: mode,
                boundaryPoints: boundaryPoints,
                area: area,
                perimeter: perimeter,
                measurementWorldMapId: measurementWorldMapId,
                onValidated: {
                    dismiss()
                    onValidated()
                }
            )
            .ignoresSafeArea()

            // --- Relocalization overlay ---
            if isRelocating {
                gardenLoadingOverlay
            }

            // --- HUD Interface ---
            VStack(spacing: 0) {
                // 1. Barre du haut
                topBar

                Spacer()

                // 2. Indicateur de sauvegarde
                if isSaving {
                    savingIndicator
                }

                // 3. Menu d'édition (si une plante est sélectionnée)
                if hasSelectedNode {
                    editingHUD.transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 4. Dock du bas (Bouton Ajouter)
                bottomDock
            }
        }
        .sheet(isPresented: $showPicker) {
            PlantCatalogARView(wizardFilter: wizard) { plant in
                selectedPlantForPlacement = plant
                // Pré-télécharger le modèle 3D de la plante sélectionnée
                Task {
                    isDownloadingModel = true
                    downloadedModelURL = nil
                    do {
                        let url = try await plant.getModelURL()
                        downloadedModelURL = url
                        print("✅ Model pre-downloaded for: \(plant.name)")
                    } catch {
                        print("❌ Failed to pre-download model for \(plant.name): \(error)")
                        // Fallback to bundle if download fails
                        downloadedModelURL = plant.localModelURL
                    }
                    isDownloadingModel = false
                }
            }
            .presentationDetents([.large])
            .presentationBackground(.clear)
        }
        .onAppear {
            if selectedPlantForPlacement == nil {
                selectedPlantForPlacement = selectedPlants.first
                // Pré-télécharger le premier modèle
                if let first = selectedPlants.first {
                    Task {
                        isDownloadingModel = true
                        do {
                            let url = try await first.getModelURL(forceDownload: false)
                            downloadedModelURL = url
                        } catch {
                            downloadedModelURL = first.localModelURL
                        }
                        isDownloadingModel = false
                    }
                }
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
            
            HStack(spacing: 20) {
                Button { NotificationCenter.default.post(name: .gardenARUndo, object: nil) } label: {
                    Image(systemName: "arrow.uturn.backward").modifier(GlassButtonStyle())
                }
                Button { NotificationCenter.default.post(name: .gardenARRedo, object: nil) } label: {
                    Image(systemName: "arrow.uturn.forward").modifier(GlassButtonStyle())
                }
            }
            
            Spacer()
            
            Button {
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

                    if isDownloadingModel {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
            }
            .disabled(isDownloadingModel)
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

    @State private var leafPulse = false

    private var gardenLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.green)
                    .scaleEffect(leafPulse ? 1.15 : 0.9)
                    .opacity(leafPulse ? 1.0 : 0.6)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: leafPulse)

                Text(NSLocalizedString("GARDEN_LOADING_TITLE", comment: ""))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(NSLocalizedString("GARDEN_LOADING_SUBTITLE", comment: ""))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.1)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 20)
        }
        .onAppear { leafPulse = true }
        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
    }
}

// MARK: - 3. Container AR
fileprivate struct GardenARPlacementContainerView: UIViewRepresentable {
    @Binding var selectedPlant: Plant?
    @Binding var downloadedModelURL: URL?
    @Binding var isDownloadingModel: Bool
    @Binding var isRelocating: Bool
    @Binding var hasSelectedNode: Bool
    @Binding var selectedNodeName: String?
    @Binding var isSaving: Bool

    let uid: String
    let wizard: GardenWizardDTO
    let gardenName: String
    let thumbnailKey: String?
    let existingGardenId: String?
    let mode: GardenARMode
    
    // 🆕 Données de mesure du jardin
    let boundaryPoints: [SIMD3<Float>]
    let area: Float
    let perimeter: Float
    let measurementWorldMapId: String?  // 🆕 ID pour charger la WorldMap de mesure
    
    let onValidated: () -> Void

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.autoenablesDefaultLighting = true
        sceneView.delegate = context.coordinator
        sceneView.session.delegate = context.coordinator
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // Load WorldMap on a background thread so main thread is not blocked.
        // Once loaded, restart the session with the world map.
        if let mapId = measurementWorldMapId {
            let mapURL = GardenLocalStore.worldMapURL(for: mapId)
            DispatchQueue.global(qos: .userInitiated).async {
                guard FileManager.default.fileExists(atPath: mapURL.path),
                      let mapData = try? Data(contentsOf: mapURL),
                      let worldMap = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: mapData)
                else {
                    print("⚠️ WorldMap de mesure introuvable ou illisible: \(mapId)")
                    return
                }
                DispatchQueue.main.async {
                    let restartConfig = ARWorldTrackingConfiguration()
                    restartConfig.planeDetection = [.horizontal]
                    restartConfig.environmentTexturing = .automatic
                    restartConfig.initialWorldMap = worldMap
                    sceneView.session.run(restartConfig, options: [.resetTracking, .removeExistingAnchors])
                    print("✅ WorldMap de mesure chargée (ID: \(mapId))")
                }
            }
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapToPlace(_:)))
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPressToSelect(_:)))
        longPress.minimumPressDuration = 0.4
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        
        [tap, longPress, pan].forEach { sceneView.addGestureRecognizer($0) }

        context.coordinator.arView = sceneView
        context.coordinator.updateCachedBounds()
        context.coordinator.setupReticle()
        context.coordinator.parentProps = self
        context.coordinator.setupObservers()

        if mode == .reopen, let id = existingGardenId {
            if measurementWorldMapId != nil {
                // WorldMap needs relocalization before placing plants.
                // The session delegate will trigger restore once mapped.
                isRelocating = true
                context.coordinator.pendingRestoreGardenId = id
            } else {
                // No WorldMap — restore immediately (positions are relative)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    context.coordinator.loadGardenFromDisk(gardenId: id)
                }
            }
        }
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.updateCachedBounds()
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator
        final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate, UIGestureRecognizerDelegate {
            var parentProps: GardenARPlacementContainerView?
            weak var arView: ARSCNView?
            
            private var reticleNode: SCNNode?
            private var lastReticleTransform: simd_float4x4?
            private var selectedNode: SCNNode?
            private var isRestoring = false

            private var undoStack: [[PersistedPlant]] = []
            private var redoStack: [[PersistedPlant]] = []
            // Cached on main thread to avoid UIKit access from SceneKit render queue
            private var cachedViewCenter: CGPoint = .zero
            // Tracks upAxis per planted plant ID for capture/restore
            private var plantUpAxisMap: [String: String] = [:]
            // Garden ID pending restore after WorldMap relocalization
            private var pendingRestoreGardenId: String?

            init(_ parent: GardenARPlacementContainerView) { self.parentProps = parent }

            private func dumpNodeTree(_ node: SCNNode, indent: String = "") {
                let name = node.name ?? "<no name>"
                let geo = (node.geometry != nil) ? " (geo)" : ""
                print("\(indent)- \(name)\(geo)")
                node.childNodes.forEach { dumpNodeTree($0, indent: indent + "  ") }
            }

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

            // MARK: - WorldMap relocalization tracking
            func session(_ session: ARSession, didUpdate frame: ARFrame) {
                guard let gardenId = pendingRestoreGardenId else { return }
                let status = frame.worldMappingStatus
                if status == .mapped || status == .extending {
                    pendingRestoreGardenId = nil
                    print("✅ WorldMap relocalized (\(status)), restoring garden \(gardenId)")
                    DispatchQueue.main.async {
                        self.parentProps?.isRelocating = false
                    }
                    loadGardenFromDisk(gardenId: gardenId)
                }
            }

            func updateCachedBounds() {
                guard let arView = arView else { return }
                cachedViewCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            }

            func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
                guard let arView = arView, let reticle = reticleNode else { return }

                let center = cachedViewCenter
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
            
            // MARK: - Capture Précise (Crucial pour la Map 2D)
            private func captureCurrentState() -> [PersistedPlant] {
                guard let arView = arView else { return [] }
                let plantNodes = arView.scene.rootNode.childNodes.filter { $0.name?.starts(with: "plant_") == true }
                
                return plantNodes.map { node -> PersistedPlant in
                    // Découpage du nom: plant_{id}_{name}_{url}_{uuid}
                    let parts = node.name?.components(separatedBy: "_") ?? []
                    
                    let rawURLString = (parts[safe: 3] ?? "").removingPercentEncoding ?? ""
                    // Stocker uniquement le nom de fichier (ex: "Pothos.usdz")
                    // pour éviter les chemins absolus invalides après recompilation
                    let modelFileName: String = {
                        if let url = URL(string: rawURLString) {
                            return url.lastPathComponent
                        }
                        return (rawURLString as NSString).lastPathComponent
                    }()

                    let plantId = parts[safe: 1] ?? "unknown"
                    return PersistedPlant(
                        plantID: plantId,
                        plantName: parts[safe: 2] ?? "Plante",
                        modelURLString: modelFileName,
                        position: [node.position.x, node.position.y, node.position.z],
                        rotation: [node.eulerAngles.x, node.eulerAngles.y, node.eulerAngles.z],
                        scale: [node.scale.x, node.scale.y, node.scale.z],
                        transform: matrixToFloatArray(node.simdTransform),
                        upAxis: plantUpAxisMap[plantId]
                    )
                }
            }

            // MARK: - SAUVEGARDE ET VALIDATION
            @objc func handleValidateNotif() {
                        guard let arView = arView, let props = parentProps else { return }
                        props.isSaving = true
                        
                        let plantsForSave = captureCurrentState()
                        
                        // 1. Sauvegarde TEMPORAIRE avec l'ID qu'on connait actuellement
                        let tempID = props.existingGardenId ?? UUID().uuidString
                        print("💾 Sauvegarde locale initiale (ID: \(tempID))")
                        self.saveToDisk(id: tempID, plants: plantsForSave, arView: arView)
                        
                        let placedDTOs = plantsForSave.map { p in
                            PlacedPlantDTO(plantId: p.plantID, x: Double(p.position[0]), y: Double(p.position[1]), z: Double(p.position[2]), note: p.plantName)
                        }
                        
                        Task {
                            var finalServerID: String = tempID
                            
                            // 2. Appel API
                            do {
                                if props.mode == .reopen, let existingId = props.existingGardenId {
                                    // Mise à jour d'un jardin existant
                                    try await GardenAPI.shared.updateGarden(
                                        id: existingId,
                                        patch: GardenAPI.GardenPatch(
                                            name: props.gardenName,
                                            wizard: props.wizard,
                                            plants: placedDTOs,
                                            thumbnailKey: props.thumbnailKey
                                        )
                                    )
                                    finalServerID = existingId
                                    print("✅ API: Jardin mis à jour (ID: \(existingId))")
                                } else {
                                    // Création d'un nouveau jardin
                                    let created = try await GardenAPI.shared.createGarden(
                                        GardenCreateDTO(
                                            name: props.gardenName,
                                            wizard: props.wizard,
                                            plants: placedDTOs,
                                            thumbnailKey: props.thumbnailKey
                                        )
                                    )
                                    
                                    // Si le serveur nous donne un ID, c'est LUI qui a raison.
                                    if let newId = created.id {
                                        finalServerID = newId
                                    }
                                    
                                    print("✅ API Réponse. ID final serveur : \(finalServerID)")
                                }
                            } catch {
                                print("⚠️ API Erreur: \(error). On garde l'ID local par sécurité.")
                            }
                            
                            // 3. SYNCHRONISATION FICHIERS
                            // Si le serveur a changé l'ID (ex: 67 -> 68), on doit copier les fichiers
                            if finalServerID != tempID {
                                print("🔄 Changement d'ID détecté (\(tempID) -> \(finalServerID)). Migration des fichiers...")
                                
                                // A. Réécriture du JSON avec le bon nom
                                self.saveToDisk(id: finalServerID, plants: plantsForSave, arView: arView)
                                
                                // B. Copie de la Map vers le bon nom
                                let oldMap = GardenLocalStore.worldMapURL(for: tempID)
                                let newMap = GardenLocalStore.worldMapURL(for: finalServerID)
                                
                                if FileManager.default.fileExists(atPath: oldMap.path) {
                                    do {
                                        if FileManager.default.fileExists(atPath: newMap.path) {
                                            try FileManager.default.removeItem(at: newMap)
                                        }
                                        try FileManager.default.copyItem(at: oldMap, to: newMap)
                                        print("✅ Fichiers migrés vers l'ID \(finalServerID)")
                                        
                                        // Supprimer les fichiers temporaires pour éviter les doublons
                                        try? FileManager.default.removeItem(at: oldMap)
                                        try? FileManager.default.removeItem(at: GardenLocalStore.sceneURL(for: tempID))
                                        
                                    } catch {
                                        print("❌ Erreur copie Map: \(error)")
                                    }
                                } else {
                                    // Pas de WorldMap à migrer, supprimer quand même le JSON temp
                                    try? FileManager.default.removeItem(at: GardenLocalStore.sceneURL(for: tempID))
                                }
                            }
                            
                            DispatchQueue.main.async {
                                props.isSaving = false
                                props.onValidated()
                            }
                        }
                    }
            
            // Fonction d'écriture disque
            private func saveToDisk(id: String, plants: [PersistedPlant], arView: ARSCNView) {
                guard let props = parentProps else { return }
                
                // 1. JSON (Synchrone, facile)
                do {
                    // 🔄 En mode reopen, props.boundaryPoints est vide.
                    // On recharge les bordures depuis le JSON existant pour les préserver.
                    var boundaryPointsArray: [[Float]]
                    var savedArea: Float = props.area
                    var savedPerimeter: Float = props.perimeter

                    if !props.boundaryPoints.isEmpty {
                        // Mode création : on utilise les bordures fraîchement mesurées
                        boundaryPointsArray = props.boundaryPoints.map { [$0.x, $0.y, $0.z] }
                    } else {
                        // Mode reopen : on relit les bordures déjà sauvegardées dans le JSON
                        let existingURL = GardenLocalStore.sceneURL(for: id)
                        if let existingData = try? Data(contentsOf: existingURL),
                           let existingScene = try? JSONDecoder().decode(PersistedARScene.self, from: existingData) {
                            boundaryPointsArray = existingScene.boundaryPoints ?? []
                            savedArea = existingScene.area ?? props.area
                            savedPerimeter = existingScene.perimeter ?? props.perimeter
                            print("🔄 Bordures rechargées depuis JSON existant: \(boundaryPointsArray.count) points")
                        } else {
                            boundaryPointsArray = []
                        }
                    }

                    var normalizedPlants = plants
                    
                    // 🔧 NORMALISATION : Si on a des bordures fraîches (création), normaliser
                    if !props.boundaryPoints.isEmpty {
                        let sumX = props.boundaryPoints.reduce(0.0) { $0 + $1.x }
                        let sumZ = props.boundaryPoints.reduce(0.0) { $0 + $1.z }
                        let centroidX = sumX / Float(props.boundaryPoints.count)
                        let centroidZ = sumZ / Float(props.boundaryPoints.count)
                        
                        print("🎯 Centroïd bordures: x=\(centroidX), z=\(centroidZ)")
                        
                        // Normaliser les bordures (soustraire le centroïd)
                        boundaryPointsArray = boundaryPointsArray.map { point in
                            [point[0] - centroidX, point[1], point[2] - centroidZ]
                        }
                        
                        // Normaliser les plantes (soustraire le centroïd)
                        normalizedPlants = plants.map { plant in
                            PersistedPlant(
                                plantID: plant.plantID,
                                plantName: plant.plantName,
                                modelURLString: plant.modelURLString,
                                position: [
                                    plant.position[0] - centroidX,
                                    plant.position[1],
                                    plant.position[2] - centroidZ
                                ],
                                rotation: plant.rotation,
                                scale: plant.scale,
                                transform: plant.transform,
                                upAxis: plant.upAxis
                            )
                        }
                        
                        print("✅ Coordonnées normalisées: \(normalizedPlants.count) plantes + \(boundaryPointsArray.count) bordures")
                    }
                    
                    let sceneData = PersistedARScene(
                        savedAt: Date(),
                        plants: normalizedPlants,
                        boundaryPoints: boundaryPointsArray,
                        area: savedArea,
                        perimeter: savedPerimeter
                    )
                    let jsonData = try JSONEncoder().encode(sceneData)
                    try jsonData.write(to: GardenLocalStore.sceneURL(for: id))
                    print("📄 JSON sauvegardé : scene_\(id).json (avec bordures: \(boundaryPointsArray.count) points)")
                } catch {
                    print("❌ Erreur écriture JSON: \(error)")
                }
                
                // 2. WorldMap (Asynchrone via ARKit)
                arView.session.getCurrentWorldMap { worldMap, error in
                    if let map = worldMap {
                        do {
                            let mapData = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                            try mapData.write(to: GardenLocalStore.worldMapURL(for: id))
                            // print("🌍 WorldMap sauvegardée")
                        } catch {
                            print("❌ Erreur écriture Map: \(error)")
                        }
                    }
                }
            }
            
            // MARK: - Restauration (Chargement)
            func loadGardenFromDisk(gardenId: String) {
                guard let arView = arView else { return }
                print("📂 Chargement ID: \(gardenId)")
                
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else { return }
                    
                    // 1. World Map
                    let mapUrl = GardenLocalStore.worldMapURL(for: gardenId)
                    var worldMap: ARWorldMap? = nil
                    
                    if FileManager.default.fileExists(atPath: mapUrl.path) {
                        do {
                            let mapData = try Data(contentsOf: mapUrl)
                            worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: mapData)
                        } catch { print("⚠️ Map ignorée (version incompatible)") }
                    }
                    
                    // 2. Scene JSON
                    let sceneUrl = GardenLocalStore.sceneURL(for: gardenId)
                    var persistedPlants: [PersistedPlant] = []
                    
                    if FileManager.default.fileExists(atPath: sceneUrl.path) {
                        do {
                            let sceneJson = try Data(contentsOf: sceneUrl)
                            let sceneData = try JSONDecoder().decode(PersistedARScene.self, from: sceneJson)
                            persistedPlants = sceneData.plants
                            print("✅ JSON chargé : \(persistedPlants.count) plantes")
                        } catch { print("❌ JSON illisible: \(error)") }
                    } else {
                        print("⚠️ FICHIER JSON ABSENT: \(sceneUrl.path)")
                    }
                    
                    DispatchQueue.main.async {
                        self.isRestoring = true
                        
                        if let map = worldMap {
                            let config = ARWorldTrackingConfiguration()
                            config.initialWorldMap = map
                            config.planeDetection = [.horizontal]
                            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
                        }
                        
                        if !persistedPlants.isEmpty {
                            self.restoreScene(from: persistedPlants)
                        } else {
                            self.isRestoring = false
                        }
                    }
                }
            }
            
            private func restoreScene(from plants: [PersistedPlant]) {
                guard let arView = arView else {
                    isRestoring = false
                    return
                }

                // Nettoyage
                arView.scene.rootNode.childNodes.forEach { node in
                    if node.name?.starts(with: "plant_") == true {
                        node.removeFromParentNode()
                    }
                }
                deselectAll()

                Task {
                    // Download all models concurrently instead of sequentially.
                    await withTaskGroup(of: Void.self) { group in
                        for p in plants {
                            guard let transform = floatArrayToMatrix(p.transform), !p.modelURLString.isEmpty else { continue }
                            let finalScale = SCNVector3(p.scale[0], p.scale[1], p.scale[2])
                            group.addTask {
                                do {
                                    let remoteURL = try await ModelCacheManager.shared.getModelURL(for: p.modelURLString, forceDownload: false)
                                    await MainActor.run {
                                        self.placeObject(at: transform, modelURL: remoteURL, id: p.plantID, name: p.plantName, finalScale: finalScale, modelURLString: p.modelURLString, upAxis: p.upAxis)
                                    }
                                } catch {
                                    print("⚠️ Impossible de télécharger le modèle \(p.modelURLString): \(error)")
                                    if let fallbackURL = self.resolveLocalModelURL(p.modelURLString) {
                                        await MainActor.run {
                                            self.placeObject(at: transform, modelURL: fallbackURL, id: p.plantID, name: p.plantName, finalScale: finalScale, modelURLString: p.modelURLString, upAxis: p.upAxis)
                                        }
                                    } else {
                                        print("❌ Impossible de résoudre le modèle : \(p.modelURLString)")
                                    }
                                }
                            }
                        }
                    }

                    await MainActor.run {
                        self.isRestoring = false
                    }
                }
            }
            
            /// Résout un modelURLString en URL utilisable, quelle que soit sa forme :
            /// - Nom de fichier seul : "Pothos.usdz"     → Bundle.main lookup
            /// - URL absolue bundle  : "file:///...app/Pothos.usdz" → extrait le filename → Bundle
            /// - URL absolue Documents : "file:///...Documents/foo.usdz" → Documents lookup
            private func resolveLocalModelURL(_ raw: String) -> URL? {
                // 1. Extraire le nom de fichier (gère les anciens chemins absolus)
                let fileName: String
                if let url = URL(string: raw), url.isFileURL {
                    fileName = url.lastPathComponent          // ex: "Pothos.usdz"
                } else {
                    fileName = (raw as NSString).lastPathComponent
                }

                guard !fileName.isEmpty else { return nil }

                let ext  = (fileName as NSString).pathExtension
                let name = (fileName as NSString).deletingPathExtension
                let finalExt = ext.isEmpty ? "usdz" : ext

                // 2. Chercher dans le bundle (valide après toute recompilation)
                if let bundleURL = Bundle.main.url(forResource: name, withExtension: finalExt) {
                    print("✅ Modèle résolu depuis le bundle : \(fileName)")
                    return bundleURL
                }

                // 3. Fallback : Documents directory (fichiers téléchargés runtime)
                let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: docsURL.path) {
                    print("✅ Modèle résolu depuis Documents : \(fileName)")
                    return docsURL
                }

                print("❌ Fichier introuvable : \(fileName)")
                return nil
            }

            // MARK: - Actions Standards
            private func saveStateForUndo() {
                let currentState = captureCurrentState()
                undoStack.append(currentState)
                redoStack.removeAll()
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

            @objc func handleTapToPlace(_ gesture: UITapGestureRecognizer) {
                guard let transform = lastReticleTransform else {
                    print("⚠️ Pas de reticle transform (pas de surface détectée)")
                    deselectAll()
                    return
                }
                guard let plant = parentProps?.selectedPlant else {
                    print("⚠️ Aucune plante sélectionnée")
                    deselectAll()
                    return
                }

                // Utiliser l'URL pré-téléchargée si disponible, sinon fallback au bundle
                guard let url = parentProps?.downloadedModelURL ?? plant.localModelURL else {
                    print("❌ Model URL nil pour: \(plant.name) | modelURL: \(plant.modelURL ?? "nil")")
                    deselectAll()
                    return
                }

                saveStateForUndo()
                if let axis = plant.upAxis { plantUpAxisMap[plant.id] = axis }
                placeObject(at: transform, modelURL: url, id: plant.id, name: plant.name, modelURLString: plant.modelURL, upAxis: plant.upAxis)
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
                if gesture.state == .began { saveStateForUndo() }
                let location = gesture.location(in: arView)
                if let query = arView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal),
                   let result = arView.session.raycast(query).first {
                    node.simdWorldPosition = simd_float3(result.worldTransform.columns.3.x, result.worldTransform.columns.3.y, result.worldTransform.columns.3.z)
                }
            }

            func placeObject(at transform: simd_float4x4, modelURL: URL, id: String, name: String, finalScale: SCNVector3? = nil, modelURLString: String? = nil, allowRetry: Bool = true, upAxis: String? = nil) {
                guard let arView = arView else { return }

                if modelURL.isFileURL && !FileManager.default.fileExists(atPath: modelURL.path) {
                    print("❌ Fichier introuvable : \(modelURL.path)")
                    return
                }

                do {
                    let scene = try SCNScene(url: modelURL, options: nil)

                    let container = SCNNode()
                    let encodedURL = modelURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "default"

                    // UUID unique pour éviter les conflits dans la Map
                    let uniqueID = UUID().uuidString
                    container.name = "plant_\(id)_\(name)_\(encodedURL)_\(uniqueID)"

                    // Wrapper node: handles Z-up → Y-up rotation for Blender
                    // exports without interfering with the AR placement transform
                    let wrapper = SCNNode()
                    for child in scene.rootNode.childNodes { wrapper.addChildNode(child) }
                    let effectiveAxis = upAxis ?? plantUpAxisMap[id]
                    if effectiveAxis?.uppercased() == "Z" {
                        wrapper.eulerAngles.x = -.pi / 2
                    }
                    container.addChildNode(wrapper)
                    stripPotIfNeeded(from: container)
                    container.simdTransform = transform

                    if let scale = finalScale {
                        container.scale = scale
                    } else if !isRestoring {
                        let (minVec, maxVec) = container.boundingBox
                        let rawHeight = maxVec.y - minVec.y
                        if rawHeight > 0 {
                            let targetHeight: Float = 0.5
                            let scaleFactor = targetHeight / rawHeight
                            container.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
                            container.pivot = SCNMatrix4MakeTranslation(0, minVec.y, 0)
                        }
                    }
                    arView.scene.rootNode.addChildNode(container)
                    if !isRestoring { selectNode(container) }
                } catch {
                    print("❌ Erreur chargement modèle: \(error)")
                    // Retry once by forcing a redownload in case the cached file is corrupted
                    if allowRetry, let raw = modelURLString {
                        Task { [weak self] in
                            do {
                                let freshURL = try await ModelCacheManager.shared.getModelURL(for: raw, forceDownload: true)
                                await MainActor.run {
                                    self?.placeObject(at: transform, modelURL: freshURL, id: id, name: name, finalScale: finalScale, modelURLString: raw, allowRetry: false)
                                }
                            } catch {
                                print("⚠️ Retry download failed for \(raw): \(error)")
                            }
                        }
                    }
                }
            }

            private func stripPotIfNeeded(from root: SCNNode) {
                guard let props = parentProps else { return }
                let isOutdoor = props.wizard.spaceType == GardenSpaceType.garden.rawValue
                guard isOutdoor else { return }

                // --- keywords pot/support ---
                let removeKeywords = ["pot", "planter", "cachepot", "vase", "container", "stand", "legs"]

                func looksLikePot(_ node: SCNNode) -> Bool {
                    let n = (node.name ?? "").lowercased()
                    return removeKeywords.contains(where: { n.contains($0) })
                }

                // 1) Cas Livistona: ne pas supprimer le container, juste les sous-mesh planter
                var planterTerraBase: SCNNode?
                root.enumerateChildNodes { node, _ in
                    if node.name == "PLANTER_TERRA_BASE" { planterTerraBase = node }
                }
                if let base = planterTerraBase {
                    var toRemove: [SCNNode] = []
                    base.enumerateChildNodes { node, _ in
                        let n = (node.name ?? "").lowercased()
                        if n.contains("livistona") { return }
                        if n.contains("planter") && node.geometry != nil { toRemove.append(node) }
                    }
                    toRemove.forEach { $0.removeFromParentNode() }
                    return
                }

                // 2) Collecte des nodes "pot-like"
                var potNodes: [SCNNode] = []
                root.enumerateChildNodes { node, _ in
                    if looksLikePot(node) { potNodes.append(node) }
                }

                // 3) Pour chaque pot node:
                // - si ça contient des enfants "non-pot" -> on remonte ces enfants (cas où la plante est dedans)
                // - sinon -> on supprime juste le node (cas Pothos / pots classiques)
                for pot in potNodes {
                    guard let parent = pot.parent else { continue }

                    let nonPotChildren = pot.childNodes.filter { !looksLikePot($0) }

                    if !nonPotChildren.isEmpty {
                        for child in nonPotChildren {
                            let worldT = child.simdWorldTransform
                            child.removeFromParentNode()
                            parent.addChildNode(child)
                            child.simdWorldTransform = worldT
                        }
                    }

                    pot.removeFromParentNode()
                }
            }

            private func selectNode(_ node: SCNNode) {
                deselectAll()
                selectedNode = node
                parentProps?.hasSelectedNode = true
                parentProps?.selectedNodeName = node.name?.components(separatedBy: "_")[safe: 2] ?? "Plante"
                
                let box = SCNBox(width: 0.3, height: 0.01, length: 0.3, chamferRadius: 0)
                let boxNode = SCNNode(geometry: box)
                boxNode.geometry?.firstMaterial?.diffuse.contents = UIColor.yellow.withAlphaComponent(0.3)
                boxNode.position = SCNVector3(0, 0.01, 0)
                boxNode.name = "selection_indicator"
                node.addChildNode(boxNode)
            }
            
            private func deselectAll() {
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

// MARK: - 4. Helpers & Styling
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

func matrixToFloatArray(_ m: simd_float4x4) -> [Float] {
    [m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.0.w,
     m.columns.1.x, m.columns.1.y, m.columns.1.z, m.columns.1.w,
     m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.2.w,
     m.columns.3.x, m.columns.3.y, m.columns.3.z, m.columns.3.w]
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

struct ActionButton: View {
    let icon: String
    let active: Bool
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(active ? .black : .white)
            .frame(width: 48, height: 48)
            .background(active ? Color(hex: "#2BEE79") : .white.opacity(0.15))
            .clipShape(Circle())
    }
}

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
