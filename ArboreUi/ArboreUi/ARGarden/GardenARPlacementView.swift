import SwiftUI
import ARKit
import SceneKit
import Foundation
import simd

// MARK: - Modèles de Données (DÉFINIS UNE SEULE FOIS ICI)
struct PersistedARScene: Codable {
    let savedAt: Date
    let plants: [PersistedPlant]
}

struct PersistedPlant: Codable {
    let plantID: String
    let plantName: String
    let modelURLString: String
    let position: [Float]
    let rotation: [Float]
    let scale: [Float]
    let transform: [Float]
}

// MARK: - Mode & Notifications
enum GardenARMode {
    case create
    case reopen
}

extension Notification.Name {
    static let gardenARValidate = Notification.Name("gardenARValidate")
    static let gardenARUndo = Notification.Name("gardenARUndo")
    static let gardenARDelete = Notification.Name("gardenARDelete")
    static let gardenARRotate = Notification.Name("gardenARRotate")
    static let gardenARScaleUp = Notification.Name("gardenARScaleUp")
    static let gardenARScaleDown = Notification.Name("gardenARScaleDown")
}

// MARK: - Stockage Local
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

// MARK: - Vue Principale SwiftUI
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
                    Image(systemName: "trash").foregroundColor(.white).frame(width: 48, height: 48).background(.red.opacity(0.7)).clipShape(Circle())
                }
            }
            .padding(10).background(.ultraThinMaterial).clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
        }
        .padding(.bottom, 30)
    }

    private var bottomDock: some View {
        HStack {
            Spacer()
            Button { showPicker = true } label: {
                ZStack {
                    Circle().fill(Color(hex: "#2BEE79")).frame(width: 68, height: 68).shadow(color: Color(hex: "#2BEE79").opacity(0.4), radius: 15)
                    Image(systemName: "plus").font(.system(size: 30, weight: .bold)).foregroundColor(.black)
                }
            }
            Spacer()
        }
        .padding(.bottom, 20)
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

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapToPlace(_:)))
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPressToSelect(_:)))
        longPress.minimumPressDuration = 0.4
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        
        [tap, longPress, pan].forEach { sceneView.addGestureRecognizer($0) }

        context.coordinator.arView = sceneView
        context.coordinator.setupReticle()
        context.coordinator.parentProps = self
        
        let nc = NotificationCenter.default
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.handleValidateNotif), name: .gardenARValidate, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.handleDelete), name: .gardenARDelete, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.handleRotateAction), name: .gardenARRotate, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.handleScaleUpAction), name: .gardenARScaleUp, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.handleScaleDownAction), name: .gardenARScaleDown, object: nil)

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
        private var isRestoring = false

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

        // MARK: - Actions de Transformation
        @objc func handleRotateAction() {
            guard let node = selectedNode else { return }
            node.runAction(SCNAction.rotateBy(x: 0, y: .pi/4, z: 0, duration: 0.2))
        }

        @objc func handleScaleUpAction() {
            guard let node = selectedNode else { return }
            node.runAction(SCNAction.scale(by: 1.1, duration: 0.2))
        }

        @objc func handleScaleDownAction() {
            guard let node = selectedNode else { return }
            node.runAction(SCNAction.scale(by: 0.9, duration: 0.2))
        }

        @objc func handleDelete() {
            selectedNode?.removeFromParentNode()
            deselectAll()
        }

        @objc func handleTapToPlace(_ gesture: UITapGestureRecognizer) {
            guard let transform = lastReticleTransform, let plant = parentProps?.selectedPlant else {
                deselectAll()
                return
            }
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
            let location = gesture.location(in: arView)
            if let query = arView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal),
               let result = arView.session.raycast(query).first {
                node.simdWorldPosition = simd_float3(result.worldTransform.columns.3.x, result.worldTransform.columns.3.y, result.worldTransform.columns.3.z)
            }
        }

        func addPlant(at transform: simd_float4x4, plant: Plant) {
            guard let arView = arView, let url = plant.localModelURL else { return }
            do {
                let scene = try SCNScene(url: url, options: nil)
                let container = SCNNode()
                // FIX: .alphanumerics au lieu de .alphanumeric
                let encodedURL = plant.modelURL?.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
                container.name = "plant_\(plant.id)_\(plant.name)_\(encodedURL)"

                for child in scene.rootNode.childNodes { container.addChildNode(child) }
                container.simdTransform = transform

                if !isRestoring {
                    let (minVec, maxVec) = container.boundingBox
                    let rawHeight = maxVec.y - minVec.y
                    if rawHeight > 0 {
                        let scaleFactor = 0.8 / rawHeight
                        container.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
                        container.pivot = SCNMatrix4MakeTranslation(0, minVec.y, 0)
                    }
                }
                arView.scene.rootNode.addChildNode(container)
                selectNode(container)
            } catch { print(error) }
        }

        @objc func handleValidateNotif() {
            guard let arView = arView, let props = parentProps else { return }
            let plantNodes = arView.scene.rootNode.childNodes.filter { $0.name?.starts(with: "plant_") == true }

            let placedDTOs = plantNodes.map { node -> PlacedPlantDTO in
                let parts = node.name?.components(separatedBy: "_") ?? []
                return PlacedPlantDTO(plantId: parts[safe: 1] ?? "", x: Double(node.position.x), y: Double(node.position.y), z: Double(node.position.z), note: parts[safe: 2] ?? "")
            }

            let persistedPlants = plantNodes.map { node -> PersistedPlant in
                let parts = node.name?.components(separatedBy: "_") ?? []
                return PersistedPlant(
                    plantID: parts[safe: 1] ?? "",
                    plantName: parts[safe: 2] ?? "",
                    modelURLString: (parts[safe: 3] ?? "").removingPercentEncoding ?? "",
                    position: [node.position.x, node.position.y, node.position.z],
                    rotation: [node.eulerAngles.x, node.eulerAngles.y, node.eulerAngles.z],
                    scale: [node.scale.x, node.scale.y, node.scale.z],
                    transform: matrixToFloatArray(node.simdTransform)
                )
            }

            Task {
                do {
                    let created = try await GardenAPI.shared.createGarden(GardenCreateDTO(uid: props.uid, name: props.gardenName, wizard: props.wizard, plants: placedDTOs, thumbnailKey: props.thumbnailKey))
                    let finalId = props.existingGardenId ?? created.id ?? UUID().uuidString
                    arView.session.getCurrentWorldMap { map, _ in
                        guard let map = map else { return }
                        let mapData = try? NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                        try? mapData?.write(to: GardenLocalStore.worldMapURL(for: finalId))
                        let sceneData = PersistedARScene(savedAt: Date(), plants: persistedPlants)
                        if let json = try? JSONEncoder().encode(sceneData) { try? json.write(to: GardenLocalStore.sceneURL(for: finalId)) }
                        DispatchQueue.main.async { props.onValidated() }
                    }
                } catch { print(error) }
            }
        }

        func loadGardenFromDisk(gardenId: String) {
            guard let arView = arView else { return }
            isRestoring = true
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
                    // CORRECTION ICI : on utilise directement p.transform car ce n'est pas un optionnel
                    // Mais floatArrayToMatrix, elle, retourne un optionnel donc on garde le if let pour elle.
                    if let transform = floatArrayToMatrix(p.transform) {
                        let stub = Plant.stubForRestore(id: p.plantID, name: p.plantName, type: "", modelURL: p.modelURLString)
                        addPlant(at: transform, plant: stub)
                        
                        // On réapplique l'échelle sauvegardée sur le dernier nœud ajouté
                        if let node = arView.scene.rootNode.childNodes.last {
                            node.scale = SCNVector3(p.scale[0], p.scale[1], p.scale[2])
                        }
                    }
                }
            } catch {
                print("Erreur chargement disque : \(error)")
            }
            isRestoring = false
        }

        private func selectNode(_ node: SCNNode) {
            deselectAll()
            selectedNode = node
            parentProps?.hasSelectedNode = true
            parentProps?.selectedNodeName = node.name?.components(separatedBy: "_")[safe: 2] ?? "Plante"
        }
        private func deselectAll() {
            selectedNode = nil
            parentProps?.hasSelectedNode = false
            parentProps?.selectedNodeName = nil
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

// MARK: - Fonctions Globales Utilitaires
func matrixToFloatArray(_ m: simd_float4x4) -> [Float] { [m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.0.w, m.columns.1.x, m.columns.1.y, m.columns.1.z, m.columns.1.w, m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.2.w, m.columns.3.x, m.columns.3.y, m.columns.3.z, m.columns.3.w] }
func floatArrayToMatrix(_ a: [Float]) -> simd_float4x4? { guard a.count == 16 else { return nil }; return simd_float4x4(simd_float4(a[0], a[1], a[2], a[3]), simd_float4(a[4], a[5], a[6], a[7]), simd_float4(a[8], a[9], a[10], a[11]), simd_float4(a[12], a[13], a[14], a[15])) }

// MARK: - Extensions Secours
extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

struct ActionButton: View {
    let icon: String
    let active: Bool
    var body: some View {
        Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundColor(active ? .black : .white)
            .frame(width: 48, height: 48).background(active ? Color(hex: "#2BEE79") : .white.opacity(0.15)).clipShape(Circle())
    }
}

struct GlassButtonStyle: ViewModifier {
    var isGreen: Bool = false
    func body(content: Content) -> some View {
        content.font(.system(size: 18, weight: .bold)).foregroundColor(.white).frame(width: 44, height: 44)
            .background(isGreen ? Color(hex: "#2BEE79") : .black.opacity(0.35)).clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
    }
}
