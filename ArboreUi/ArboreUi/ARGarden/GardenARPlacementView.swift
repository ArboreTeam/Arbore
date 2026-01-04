import SwiftUI
import ARKit
import SceneKit
import Foundation
import simd

// MARK: - Notifications
extension Notification.Name {
    static let gardenARValidate = Notification.Name("gardenARValidate")
}

// MARK: - Local store URLs (par gardenId)
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

// MARK: - Mode
enum GardenARMode {
    case create
    case reopen
}

// MARK: - Vue Principale (Interface)
struct GardenARPlacementView: View {
    let selectedPlants: [Plant]

    let uid: String
    let wizard: GardenWizardDTO
    let gardenName: String
    let thumbnailKey: String?

    /// ✅ si reopen, tu passes l’id mongo
    let existingGardenId: String?
    let mode: GardenARMode

    /// callback vers parent
    let onValidated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var selectedPlantForPlacement: Plant? = nil

    var body: some View {
        ZStack {
            GardenARPlacementContainerView(
                selectedPlant: $selectedPlantForPlacement,
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

            if !showPicker {
                bottomGradient.ignoresSafeArea()
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

            Button {
                NotificationCenter.default.post(name: .gardenARValidate, object: nil)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color(hex: "#2BEE79").opacity(0.90))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 1))
                    .shadow(color: Color(hex: "#2BEE79").opacity(0.35), radius: 10, x: 0, y: 6)
            }
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

// MARK: - Container
fileprivate struct GardenARPlacementContainerView: UIViewRepresentable {
    @Binding var selectedPlant: Plant?

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
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(GardenCoordinator.handleTapPlace(_:))
        )
        sceneView.addGestureRecognizer(tapGesture)

        context.coordinator.arView = sceneView
        context.coordinator.setupReticle()
        context.coordinator.currentPlant = selectedPlant

        context.coordinator.uid = uid
        context.coordinator.wizard = wizard
        context.coordinator.gardenName = gardenName
        context.coordinator.thumbnailKey = thumbnailKey
        context.coordinator.mode = mode
        context.coordinator.existingGardenId = existingGardenId
        context.coordinator.onValidated = onValidated

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(GardenCoordinator.handleValidateNotif),
            name: .gardenARValidate,
            object: nil
        )

        // ✅ REOPEN : auto-load dès l’ouverture
        if mode == .reopen, let id = existingGardenId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                context.coordinator.loadGardenFromDisk(gardenId: id)
            }
        }

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

    // MARK: - Coordinator
    final class GardenCoordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        var parent: GardenARPlacementContainerView
        weak var arView: ARSCNView?

        var currentPlant: Plant?
        private var placedPlants: [PersistedPlant] = []

        // Backend/meta
        var uid: String = ""
        var wizard: GardenWizardDTO = GardenWizardDTO(style: "", spaceType: "", exposure: nil, maintenance: nil, safety: [], soil: nil, scanMethod: nil)
        var gardenName: String = "Mon jardin"
        var thumbnailKey: String? = nil

        var mode: GardenARMode = .create
        var existingGardenId: String? = nil
        var onValidated: (() -> Void)? = nil

        private var reticleNode: SCNNode?
        private var lastReticleTransform: simd_float4x4?

        init(_ parent: GardenARPlacementContainerView) {
            self.parent = parent
            super.init()
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        // MARK: Reticle
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

        // MARK: Place
        @objc func handleTapPlace(_ sender: UITapGestureRecognizer) {
            guard let transform = lastReticleTransform else { return }
            guard let plant = currentPlant else { return }

            if let modelURL = plant.localModelURL {
                addPlantNode(at: transform, modelURL: modelURL, plant: plant)
            }
        }

        func addPlantNode(at transform: simd_float4x4, modelURL: URL, plant: Plant) {
            guard let arView = arView else { return }

            do {
                let scene = try SCNScene(url: modelURL, options: nil)

                let containerNode = SCNNode()
                containerNode.name = "plant_\(plant.id)"

                let modelNode = SCNNode()
                for child in scene.rootNode.childNodes { modelNode.addChildNode(child) }

                let (minVec, maxVec) = modelNode.boundingBox
                let rawHeight = maxVec.y - minVec.y

                let targetHeight: Float = 0.5
                let scaleFactor = (rawHeight > 0) ? (targetHeight / rawHeight) : 1.0
                modelNode.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
                modelNode.position.y = -minVec.y * scaleFactor

                containerNode.addChildNode(modelNode)
                containerNode.simdTransform = transform

                arView.scene.rootNode.addChildNode(containerNode)

                let persisted = PersistedPlant(
                    plantID: plant.id,
                    plantName: plant.name,
                    modelURLString: plant.modelURL ?? "",
                    transform: matrixToFloatArray(transform)
                )
                placedPlants.append(persisted)
            } catch {
                print("❌ addPlantNode error:", error)
            }
        }

        // MARK: - LOAD FROM DISK (reopen)
        func loadGardenFromDisk(gardenId: String) {
            guard let arView = arView else { return }

            do {
                let mapURL = GardenLocalStore.worldMapURL(for: gardenId)
                let sceneURL = GardenLocalStore.sceneURL(for: gardenId)

                let mapData = try Data(contentsOf: mapURL)
                guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: mapData) else {
                    print("❌ worldMap decode failed")
                    return
                }

                let sceneJson = try Data(contentsOf: sceneURL)
                let persistedScene = try JSONDecoder().decode(PersistedARScene.self, from: sceneJson)

                let config = ARWorldTrackingConfiguration()
                config.planeDetection = [.horizontal, .vertical]
                config.environmentTexturing = .automatic
                config.initialWorldMap = worldMap

                arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

                // clear old nodes
                arView.scene.rootNode.childNodes.forEach { node in
                    if node.name?.starts(with: "plant_") == true { node.removeFromParentNode() }
                }
                placedPlants.removeAll()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
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

                print("✅ Reopen load ok for garden:", gardenId)
            } catch {
                print("❌ loadGardenFromDisk error:", error)
            }
        }

        // MARK: - VALIDATE (create + save local map)
        @objc func handleValidateNotif() {
            guard let arView = arView else { return }

            // ✅ extrait x/y/z depuis ta matrice 4x4 (col-major)
            func extractPosition(_ t: [Float]) -> (Double?, Double?, Double?) {
                guard t.count >= 16 else { return (nil, nil, nil) }
                return (Double(t[12]), Double(t[13]), Double(t[14]))
            }

            // 1) plants pour Mongo (TON modèle actuel)
            let placed: [PlacedPlantDTO] = placedPlants.map { p in
                let (x, y, z) = extractPosition(p.transform)
                return PlacedPlantDTO(
                    plantId: p.plantID,
                    x: x,
                    y: y,
                    z: z,
                    note: p.plantName
                )
            }

            // ✅ 2) payload CREATE attendu par ton API
            let payload = GardenCreateDTO(
                uid: uid,
                name: gardenName,
                wizard: wizard,
                plants: placed,
                thumbnailKey: thumbnailKey
            )

            Task {
                do {
                    // ✅ 3) Create garden
                    let created = try await GardenAPI.shared.createGarden(payload)
                    guard let gardenId = created.id else {
                        print("❌ createGarden returned nil id")
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        return
                    }

                    // ✅ 4) Save worldmap + scene localement avec gardenId
                    arView.session.getCurrentWorldMap { [weak self] worldMap, error in
                        guard let self = self, let map = worldMap else {
                            print("❌ getCurrentWorldMap failed:", error?.localizedDescription ?? "nil")
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                            return
                        }

                        do {
                            let mapData = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                            try mapData.write(to: GardenLocalStore.worldMapURL(for: gardenId), options: [.atomic])

                            let sceneData = PersistedARScene(savedAt: Date(), plants: self.placedPlants)
                            let json = try JSONEncoder().encode(sceneData)
                            try json.write(to: GardenLocalStore.sceneURL(for: gardenId), options: [.atomic])

                            print("✅ Saved local worldmap+scene for gardenId:", gardenId)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)

                            DispatchQueue.main.async {
                                self.onValidated?()
                            }
                        } catch {
                            print("❌ local save error:", error)
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        }
                    }

                } catch {
                    print("❌ createGarden failed:", error)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}