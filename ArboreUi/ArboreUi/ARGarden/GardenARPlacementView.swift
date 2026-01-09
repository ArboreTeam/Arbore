import SwiftUI
import ARKit
import SceneKit
import Foundation
import simd

// MARK: - Mode & Notifications
enum GardenARMode {
    case create
    case reopen
}

extension Notification.Name {
    static let gardenARValidate = Notification.Name("gardenARValidate")
    static let gardenARUndo = Notification.Name("gardenARUndo")
    static let gardenARDelete = Notification.Name("gardenARDelete")
}

// MARK: - Local store
fileprivate enum GardenLocalStore {
    static func worldMapURL(for gardenId: String) -> URL {
        documentsURL().appendingPathComponent("worldmap_\(gardenId).bin")
    }
    static func sceneURL(for gardenId: String) -> URL {
        documentsURL().appendingPathComponent("scene_\(gardenId).json")
    }
    private static func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

// MARK: - Vue Principale
struct GardenARPlacementView: View {
    let selectedPlants: [Plant]
    let uid: String
    let wizard: GardenWizardDTO
    let gardenName: String
    let thumbnailKey: String?
    let existingGardenId: String?
    let mode: GardenARMode
    let onValidated: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var selectedPlantForPlacement: Plant? = nil
    @State private var hasSelectedNode = false
    @State private var selectedNodeName: String? = nil

    var body: some View {
        ZStack {
            GardenARPlacementContainerView(
                selectedPlant: $selectedPlantForPlacement,
                hasSelectedNode: $hasSelectedNode,
                selectedNodeName: $selectedNodeName,
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
            
            VStack(spacing: 0) {
                topBar
                Spacer()
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

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left").modifier(GlassButtonStyle())
            }
            Spacer()
            HStack(spacing: 0) {
                Button { NotificationCenter.default.post(name: .gardenARUndo, object: nil) } label: {
                    Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44)
                }
                Divider().frame(height: 24).background(.white.opacity(0.2))
                Button { /* Redo logic if needed */ } label: {
                    Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44)
                }
            }
            .background(.black.opacity(0.5)).clipShape(Capsule()).foregroundColor(.white)
            Spacer()
            Button { NotificationCenter.default.post(name: .gardenARValidate, object: nil) } label: {
                Image(systemName: "checkmark").modifier(GlassButtonStyle(isGreen: true))
            }
        }
        .padding(.horizontal, 20).padding(.top, 10)
    }

    private var editingHUD: some View {
        VStack(spacing: 12) {
            if let name = selectedNodeName {
                Text(name).font(.system(size: 14, weight: .bold)).foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 8).background(.black.opacity(0.7)).clipShape(Capsule())
            }
            HStack(spacing: 15) {
                ActionButton(icon: "360.75", active: true)
                ActionButton(icon: "arrow.up.and.down.and.arrow.left.and.right", active: false)
                ActionButton(icon: "arrow.up.and.down", active: false)
                Button { NotificationCenter.default.post(name: .gardenARDelete, object: nil) } label: {
                    Image(systemName: "trash").foregroundColor(.white).frame(width: 48, height: 48).background(.red.opacity(0.7)).clipShape(Circle())
                }
            }
            .padding(10).background(.ultraThinMaterial).clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
        }
        .padding(.bottom, 30)
    }

    private var bottomDock: some View {
        HStack(alignment: .bottom) {
            VStack(spacing: 4) {
                Image(systemName: "layers").modifier(GlassButtonStyle())
                Text("Layers").font(.system(size: 10, weight: .medium)).foregroundColor(.white.opacity(0.8))
            }
            Spacer()
            Button { showPicker = true } label: {
                ZStack {
                    Circle().fill(Color(hex: "#2BEE79")).frame(width: 68, height: 68).shadow(color: Color(hex: "#2BEE79").opacity(0.4), radius: 15)
                    Image(systemName: "plus").font(.system(size: 30, weight: .bold)).foregroundColor(.black)
                }
            }
            .offset(y: -10)
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "camera").modifier(GlassButtonStyle())
                Text("Snap").font(.system(size: 10, weight: .medium)).foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 40).padding(.bottom, 20)
    }
}

// MARK: - Container AR
fileprivate struct GardenARPlacementContainerView: UIViewRepresentable {
    @Binding var selectedPlant: Plant?
    @Binding var hasSelectedNode: Bool
    @Binding var selectedNodeName: String?
    
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
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // GESTURES
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapToPlace(_:)))
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPressToSelect(_:)))
        longPress.minimumPressDuration = 0.4
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        let rotate = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRotate(_:)))
        
        pan.delegate = context.coordinator
        [tap, longPress, pan, pinch, rotate].forEach { sceneView.addGestureRecognizer($0) }

        context.coordinator.arView = sceneView
        context.coordinator.setupReticle()
        context.coordinator.parentProps = self
        
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.handleValidateNotif), name: .gardenARValidate, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.handleDelete), name: .gardenARDelete, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.handleUndo), name: .gardenARUndo, object: nil)

        if mode == .reopen, let id = existingGardenId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                context.coordinator.loadGardenFromDisk(gardenId: id)
            }
        }
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate, UIGestureRecognizerDelegate {
        var parentProps: GardenARPlacementContainerView?
        weak var arView: ARSCNView?
        private var reticleNode: SCNNode?
        private var lastReticleTransform: simd_float4x4?
        private var selectedNode: SCNNode?
        private var placedPlants: [PersistedPlant] = []
        private var lastTransform: SCNMatrix4?

        init(_ parent: GardenARPlacementContainerView) { self.parentProps = parent }

        func setupReticle() {
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.08, pipeRadius: 0.005))
            ring.geometry?.firstMaterial?.diffuse.contents = UIColor(hex: "#2BEE79")
            ring.opacity = 0
            reticleNode = ring
            arView?.scene.rootNode.addChildNode(ring)
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let arView = arView, let reticle = reticleNode else { return }
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            
            // On cherche uniquement sur les plans détectés réels pour éviter le "spawn sur soi"
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

        @objc func handleTapToPlace(_ gesture: UITapGestureRecognizer) {
            // SECURITÉ : On n'autorise le placement QUE si le réticule est actif (sol détecté)
            guard let transform = lastReticleTransform, let plant = parentProps?.selectedPlant else {
                deselectAll()
                return
            }
            
            // Évite le spawn trop proche de la caméra
            let cameraPos = arView?.pointOfView?.simdPosition ?? simd_float3(0,0,0)
            let spawnPos = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            if distance(cameraPos, spawnPos) < 0.25 { return }
            
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
            if gesture.state == .began { lastTransform = node.transform }
            let location = gesture.location(in: arView)
            if let query = arView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal),
               let result = arView.session.raycast(query).first {
                node.simdWorldPosition = simd_float3(result.worldTransform.columns.3.x, result.worldTransform.columns.3.y, result.worldTransform.columns.3.z)
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let node = selectedNode else { return }
            let s = Float(gesture.scale)
            node.scale = SCNVector3(node.scale.x * s, node.scale.y * s, node.scale.z * s)
            gesture.scale = 1.0
        }

        @objc func handleRotate(_ gesture: UIRotationGestureRecognizer) {
            guard let node = selectedNode else { return }
            node.eulerAngles.y -= Float(gesture.rotation)
            gesture.rotation = 0
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        func addPlant(at transform: simd_float4x4, plant: Plant) {
            guard let arView = arView, let url = plant.localModelURL else { return }
            do {
                let scene = try SCNScene(url: url, options: nil)
                let container = SCNNode()
                container.name = "plant_\(plant.id)_\(plant.name)"
                
                // On récupère le contenu du modèle
                for child in scene.rootNode.childNodes {
                    container.addChildNode(child)
                }
                
                // --- ÉTAPE 1 : POSITIONNER D'ABORD (CRITIQUE) ---
                // C'est ici que l'erreur se produisait. On applique la position ARKit AVANT de toucher à l'échelle.
                container.simdTransform = transform
                
                // --- ÉTAPE 2 : CALCULER ET APPLIQUER L'ÉCHELLE ---
                let (minVec, maxVec) = container.boundingBox
                let rawHeight = maxVec.y - minVec.y
                
                // On vise 20 cm de haut (0.2m)
                let targetHeight: Float = 0.8
                
                if rawHeight > 0 {
                    let scaleFactor = targetHeight / rawHeight
                    
                    // On applique l'échelle MAINTENANT. Comme la position est déjà définie,
                    // cette ligne ne sera pas écrasée.
                    container.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
                    
                    // Ajustement du pivot pour que ça touche le sol
                    container.pivot = SCNMatrix4MakeTranslation(0, minVec.y, 0)
                    
                    print("DEBUG: Hauteur originale: \(rawHeight), Facteur appliqué: \(scaleFactor)")
                } else {
                    // Si la bounding box échoue (ce qui arrive avec certains .usdz mal formés),
                    // on force une échelle minuscule par sécurité (1%).
                    print("DEBUG: Impossible de calculer la hauteur, application échelle de sécurité.")
                    container.scale = SCNVector3(0.01, 0.01, 0.01)
                }
                
                // Ajouter à la scène
                arView.scene.rootNode.addChildNode(container)
                
                // Persistance
                let p = PersistedPlant(
                    plantID: plant.id,
                    plantName: plant.name,
                    modelURLString: plant.modelURL ?? "",
                    // Attention: on sauvegarde la transform APRES mise à l'échelle
                    transform: matrixToFloatArray(container.simdTransform)
                )
                placedPlants.append(p)
                
                selectNode(container)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                
            } catch {
                print("Erreur spawn: \(error)")
            }
        }

        func selectNode(_ node: SCNNode) {
            deselectAll()
            selectedNode = node
            parentProps?.hasSelectedNode = true
            parentProps?.selectedNodeName = node.name?.components(separatedBy: "_").last ?? "Plante"
        }

        func deselectAll() {
            selectedNode = nil
            parentProps?.hasSelectedNode = false
        }

        @objc func handleDelete() { selectedNode?.removeFromParentNode(); deselectAll() }
        @objc func handleUndo() { if let n = selectedNode, let old = lastTransform { n.transform = old } }

        @objc func handleValidateNotif() {
            guard let arView = arView, let props = parentProps else { return }
            let placed: [PlacedPlantDTO] = arView.scene.rootNode.childNodes
                .filter { $0.name?.starts(with: "plant_") == true }
                .map { node in
                    let parts = node.name?.components(separatedBy: "_") ?? []
                    return PlacedPlantDTO(plantId: parts.count > 1 ? parts[1] : "", x: Double(node.position.x), y: Double(node.position.y), z: Double(node.position.z), note: parts.last ?? "")
                }
            let payload = GardenCreateDTO(uid: props.uid, name: props.gardenName, wizard: props.wizard, plants: placed, thumbnailKey: props.thumbnailKey)
            Task {
                do {
                    let created = try await GardenAPI.shared.createGarden(payload)
                    guard let id = created.id else { return }
                    arView.session.getCurrentWorldMap { map, _ in
                        guard let map = map else { return }
                        let mapData = try? NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                        try? mapData?.write(to: GardenLocalStore.worldMapURL(for: id))
                        let sceneData = PersistedARScene(savedAt: Date(), plants: self.placedPlants)
                        let json = try? JSONEncoder().encode(sceneData)
                        try? json?.write(to: GardenLocalStore.sceneURL(for: id))
                        DispatchQueue.main.async { props.onValidated() }
                    }
                } catch { print(error) }
            }
        }

        func loadGardenFromDisk(gardenId: String) {
            guard let arView = arView else { return }
            do {
                let mapData = try Data(contentsOf: GardenLocalStore.worldMapURL(for: gardenId))
                let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: mapData)
                let sceneJson = try Data(contentsOf: GardenLocalStore.sceneURL(for: gardenId))
                let scene = try JSONDecoder().decode(PersistedARScene.self, from: sceneJson)
                let config = ARWorldTrackingConfiguration()
                config.initialWorldMap = worldMap
                config.planeDetection = [.horizontal]
                arView.session.run(config)
                for p in scene.plants {
                    guard let transform = floatArrayToMatrix(p.transform) else { continue }
                    let stub = Plant.stubForRestore(id: p.plantID, name: p.plantName, type: "", modelURL: p.modelURLString)
                    addPlant(at: transform, plant: stub)
                }
            } catch { print(error) }
        }

        private func isPlantNode(_ node: SCNNode) -> Bool {
            var current: SCNNode? = node
            while current != nil { if current?.name?.starts(with: "plant_") == true { return true }; current = current?.parent }
            return false
        }
        private func findPlantRoot(_ node: SCNNode) -> SCNNode {
            var curr = node
            while let p = curr.parent, p.name?.starts(with: "plant_") == false { curr = p }
            return curr.parent?.name?.starts(with: "plant_") == true ? curr.parent! : curr
        }
    }
}

// MARK: - UI Style
struct GlassButtonStyle: ViewModifier {
    var isGreen: Bool = false
    func body(content: Content) -> some View {
        content.font(.system(size: 18, weight: .bold)).foregroundColor(.white).frame(width: 44, height: 44)
            .background(isGreen ? Color(hex: "#2BEE79") : .black.opacity(0.35)).clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
    }
}

struct ActionButton: View {
    let icon: String
    let active: Bool
    var body: some View {
        Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundColor(active ? .black : .white)
            .frame(width: 48, height: 48).background(active ? Color(hex: "#2BEE79") : .white.opacity(0.15)).clipShape(Circle())
    }
}

