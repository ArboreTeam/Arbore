import SwiftUI
import ARKit
import SceneKit // ✅ On passe à SceneKit pour la stabilité sur iPhone 16/17 Pro
import Combine
import PhotosUI

// 🆕 Extension pour les notifications
extension Notification.Name {
    static let saveWorldMapForMeasurement = Notification.Name("saveWorldMapForMeasurement")
}

// MARK: - 1. État et géométrie du tracé
final class GardenManager: ObservableObject {
    @Published var points: [SIMD3<Float>] = []
    @Published var area: Float = 0.0
    @Published var perimeter: Float = 0.0
    @Published var canPlacePoint = false
    @Published var currentCameraDirection: SIMD3<Float>?
    @Published var currentAmbientIntensity: Double?

    let placePointSignal = PassthroughSubject<Void, Never>()
    private var placementHistory: [SIMD3<Float>] = []

    @discardableResult
    func addPoint(_ rawPoint: SIMD3<Float>) -> Bool {
        var point = rawPoint

        // Les raycasts successifs peuvent varier légèrement en hauteur. Sur un
        // même sol, on stabilise le nouveau point sur le plan déjà établi.
        if !points.isEmpty {
            let referenceY = points.map(\.y).reduce(0, +) / Float(points.count)
            if abs(point.y - referenceY) < 0.25 {
                point.y = referenceY
            }
        }

        // Évite les doubles poses involontaires au même endroit.
        let isTooClose = points.contains { existing in
            let dx = existing.x - point.x
            let dz = existing.z - point.z
            return sqrt(dx * dx + dz * dz) < 0.12
        }
        guard !isTooClose else { return false }

        placementHistory.append(point)
        points = Self.orderedBoundaryPoints(placementHistory)
        calculateStats()
        return true
    }

    func requestPointPlacement() {
        placePointSignal.send()
    }

    func undoLastPoint() {
        guard placementHistory.popLast() != nil else { return }
        points = Self.orderedBoundaryPoints(placementHistory)
        calculateStats()
    }

    func reset() {
        placementHistory.removeAll()
        points.removeAll()
        area = 0.0
        perimeter = 0.0
    }

    private func calculateStats() {
        guard points.count > 1 else {
            area = 0
            perimeter = 0
            return
        }

        var tempPerimeter: Float = 0
        for index in 0..<(points.count - 1) {
            tempPerimeter += Self.horizontalDistance(points[index], points[index + 1])
        }
        if points.count > 2 {
            tempPerimeter += Self.horizontalDistance(points[points.count - 1], points[0])
        }
        perimeter = tempPerimeter
        area = Self.polygonAreaXZ(points)
    }

    static func polygonAreaXZ(_ points: [SIMD3<Float>]) -> Float {
        guard points.count > 2 else { return 0 }
        var sum: Float = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            sum += points[index].x * next.z - points[index].z * next.x
        }
        return abs(sum) * 0.5
    }

    /// Conserve l'ordre naturel suivi par l'utilisateur tant qu'il produit un
    /// contour valide. Un passage 2-opt inverse uniquement les portions qui se
    /// croisent : le cas courant du rectangle posé en diagonale est corrigé
    /// sans déformer un contour concave correctement parcouru.
    static func orderedBoundaryPoints(_ input: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard input.count >= 3 else { return input }
        var ordered = input

        guard ordered.count >= 4 else { return ordered }

        var changed = true
        var pass = 0
        let maximumPasses = ordered.count * ordered.count

        while changed, pass < maximumPasses {
            changed = false
            pass += 1

            crossingSearch: for firstIndex in ordered.indices {
                let firstNext = (firstIndex + 1) % ordered.count
                guard firstIndex + 2 < ordered.count else { continue }

                for secondIndex in (firstIndex + 2)..<ordered.count {
                    let secondNext = (secondIndex + 1) % ordered.count

                    // Deux arêtes qui partagent un sommet ne se croisent pas.
                    if firstIndex == secondNext || firstNext == secondIndex {
                        continue
                    }

                    if segmentsIntersectXZ(
                        ordered[firstIndex],
                        ordered[firstNext],
                        ordered[secondIndex],
                        ordered[secondNext]
                    ) {
                        ordered.replaceSubrange(
                            firstNext...secondIndex,
                            with: ordered[firstNext...secondIndex].reversed()
                        )
                        changed = true
                        break crossingSearch
                    }
                }
            }
        }

        return ordered
    }

    private static func horizontalDistance(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Float {
        let dx = lhs.x - rhs.x
        let dz = lhs.z - rhs.z
        return sqrt(dx * dx + dz * dz)
    }

    private static func segmentsIntersectXZ(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>,
        _ d: SIMD3<Float>
    ) -> Bool {
        func orientation(_ p: SIMD3<Float>, _ q: SIMD3<Float>, _ r: SIMD3<Float>) -> Float {
            (q.x - p.x) * (r.z - p.z) - (q.z - p.z) * (r.x - p.x)
        }

        let first = orientation(a, b, c)
        let second = orientation(a, b, d)
        let third = orientation(c, d, a)
        let fourth = orientation(c, d, b)
        let epsilon: Float = 0.0001

        guard abs(first) > epsilon,
              abs(second) > epsilon,
              abs(third) > epsilon,
              abs(fourth) > epsilon else {
            return false
        }

        return (first > 0) != (second > 0) && (third > 0) != (fourth > 0)
    }
}

// MARK: - 2. LE MOTEUR AR (Fix SceneKit)

struct ARViewContainerGarden: UIViewRepresentable {
    @ObservedObject var manager: GardenManager
    
    func makeUIView(context: Context) -> ARSCNView {
        // 1. Initialisation SceneKit (ARSCNView au lieu de ARView)
        // Cela évite le bug "écran noir" dû aux shaders RealityKit sur les puces A18
        let sceneView = ARSCNView(frame: .zero)
        
        // 2. Configuration
        sceneView.autoenablesDefaultLighting = true
        sceneView.delegate = context.coordinator
        sceneView.session.delegate = context.coordinator
        
        // 3. Configuration AR Standard (Optimisée)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal] // On garde juste horizontal pour le jardin
        
        // 🔧 Optimisations pour réduire la charge
        config.isAutoFocusEnabled = true
        config.environmentTexturing = .none  // Désactivé pour alléger
        config.frameSemantics = []  // Pas de depth/segmentation
        
        // Ne pas activer le LiDAR explicitement
        // if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
        //     config.frameSemantics.insert(.sceneDepth)
        // }
        
        context.coordinator.arView = sceneView
        context.coordinator.setupSubscriptions()
        
        // 5. Lancement
        DispatchQueue.main.async {
            sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }
        
        return sceneView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
    
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager)
    }
    
    // MARK: - Coordinator SceneKit
    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        var arView: ARSCNView?
        var manager: GardenManager
        var cancellables = Set<AnyCancellable>()
        var worldMapObserver: NSObjectProtocol?
        private var lastTargetingUpdate: TimeInterval = 0
        private let boundaryRootName = "arbore.measurement.boundary"
        
        init(manager: GardenManager) {
            self.manager = manager
            super.init()
            
            // 🆕 Observer pour sauvegarder la WorldMap
            worldMapObserver = NotificationCenter.default.addObserver(
                forName: .saveWorldMapForMeasurement,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let gardenId = notification.object as? String else { return }
                self?.saveWorldMap(for: gardenId)
            }
        }
        
        deinit {
            if let observer = worldMapObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        
        // 🆕 Fonction pour sauvegarder la WorldMap
        private func saveWorldMap(for gardenId: String) {
            print("🗺️ saveWorldMap appelée pour: \(gardenId)")
            guard let arView = arView else {
                print("❌ arView est nil!")
                return
            }
            
            print("🗺️ Sauvegarde WorldMap pour mesure (ID: \(gardenId))...")
            arView.session.getCurrentWorldMap { worldMap, error in
                if let map = worldMap {
                    do {
                        let mapData = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                        let url = GardenLocalStore.worldMapURL(for: gardenId)
                        try mapData.write(to: url)
                        print("✅ WorldMap sauvegardée pour mesure: \(gardenId)")
                        print("📁 Fichier: \(url.path)")
                    } catch {
                        print("❌ Erreur sauvegarde WorldMap mesure: \(error)")
                    }
                } else if let error = error {
                    print("❌ Erreur récupération WorldMap: \(error)")
                } else {
                    print("⚠️ WorldMap est nil sans erreur")
                }
            }
        }
        
        func setupSubscriptions() {
            manager.placePointSignal
                .receive(on: RunLoop.main)
                .sink { [weak self] in
                    self?.placePointAtCenter()
                }
                .store(in: &cancellables)

            manager.$points
                .receive(on: RunLoop.main)
                .sink { [weak self] points in
                    self?.renderBoundary(points)
                }
                .store(in: &cancellables)
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let cameraTransform = frame.camera.transform
            let direction = SIMD3<Float>(
                -cameraTransform.columns.2.x,
                -cameraTransform.columns.2.y,
                -cameraTransform.columns.2.z
            )
            let intensity = frame.lightEstimate.map { Double($0.ambientIntensity) }

            DispatchQueue.main.async { [weak self] in
                self?.manager.currentCameraDirection = direction
                self?.manager.currentAmbientIntensity = intensity
            }
        }

        private func placePointAtCenter() {
            guard let arView else { return }
            let location = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            guard let result = raycastResult(at: location) else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                manager.canPlacePoint = false
                return
            }

            let position = SIMD3<Float>(
                result.worldTransform.columns.3.x,
                result.worldTransform.columns.3.y,
                result.worldTransform.columns.3.z
            )

            if manager.addPoint(position) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }

        private func raycastResult(at location: CGPoint) -> ARRaycastResult? {
            guard let arView else { return nil }

            // On privilégie un vrai plan détecté. Le plan estimé reste un
            // secours pour ne pas bloquer l'utilisateur sur un sol peu texturé.
            if let query = arView.raycastQuery(
                from: location,
                allowing: .existingPlaneGeometry,
                alignment: .horizontal
            ), let result = arView.session.raycast(query).first {
                return result
            }

            if let query = arView.raycastQuery(
                from: location,
                allowing: .estimatedPlane,
                alignment: .horizontal
            ) {
                return arView.session.raycast(query).first
            }

            return nil
        }

        private func renderBoundary(_ points: [SIMD3<Float>]) {
            guard let arView else { return }
            arView.scene.rootNode.childNode(withName: boundaryRootName, recursively: false)?.removeFromParentNode()

            let root = SCNNode()
            root.name = boundaryRootName
            arView.scene.rootNode.addChildNode(root)

            for (index, point) in points.enumerated() {
                let sphere = SCNSphere(radius: index == 0 ? 0.045 : 0.035)
                sphere.firstMaterial?.diffuse.contents = index == 0 ? UIColor.white : Self.arboreGreen
                sphere.firstMaterial?.emission.contents = index == 0
                    ? UIColor.white.withAlphaComponent(0.5)
                    : Self.arboreGreen.withAlphaComponent(0.45)

                let node = SCNNode(geometry: sphere)
                node.simdPosition = point + SIMD3<Float>(0, 0.035, 0)
                root.addChildNode(node)

                if index == 0 {
                    let ring = SCNTorus(ringRadius: 0.075, pipeRadius: 0.006)
                    ring.firstMaterial?.diffuse.contents = Self.arboreGreen
                    ring.firstMaterial?.emission.contents = Self.arboreGreen.withAlphaComponent(0.5)
                    let ringNode = SCNNode(geometry: ring)
                    ringNode.simdPosition = point + SIMD3<Float>(0, 0.012, 0)
                    root.addChildNode(ringNode)
                }
            }

            guard points.count >= 2 else { return }
            for index in 0..<(points.count - 1) {
                root.addChildNode(makeSegment(from: points[index], to: points[index + 1]))
            }
            if points.count >= 3 {
                root.addChildNode(makeSegment(from: points[points.count - 1], to: points[0]))
            }
        }

        private func makeSegment(from start: SIMD3<Float>, to end: SIMD3<Float>) -> SCNNode {
            let raisedStart = start + SIMD3<Float>(0, 0.018, 0)
            let raisedEnd = end + SIMD3<Float>(0, 0.018, 0)
            let vector = raisedEnd - raisedStart
            let length = simd_length(vector)

            let cylinder = SCNCylinder(radius: 0.009, height: CGFloat(max(length, 0.001)))
            cylinder.firstMaterial?.diffuse.contents = Self.arboreGreen
            cylinder.firstMaterial?.emission.contents = Self.arboreGreen.withAlphaComponent(0.6)

            let node = SCNNode(geometry: cylinder)
            node.simdPosition = (raisedStart + raisedEnd) / 2
            if length > 0.0001 {
                node.simdOrientation = simd_quatf(
                    from: SIMD3<Float>(0, 1, 0),
                    to: simd_normalize(vector)
                )
            }
            return node
        }

        private static let arboreGreen = UIColor(
            red: 46 / 255,
            green: 125 / 255,
            blue: 80 / 255,
            alpha: 1
        )

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard time - lastTargetingUpdate >= 0.12, let arView else { return }
            lastTargetingUpdate = time
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            let isAvailable = raycastResult(at: center) != nil
            DispatchQueue.main.async { [weak self] in
                guard let self, self.manager.canPlacePoint != isAvailable else { return }
                self.manager.canPlacePoint = isAvailable
            }
        }
        
        // Gestion des erreurs
        func session(_ session: ARSession, didFailWithError error: Error) {
            print("❌ Erreur AR: \(error.localizedDescription)")
        }
        
        // 🆕 Détecter quand l'AR est prêt (plane détectée)
        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            guard anchor is ARPlaneAnchor else { return }
            print("✅ Plan AR détecté - L'AR est prête!")
        }
    }
}

// MARK: - 3. VISUELS (Shapes) - INCHANGÉ
struct GardenShape: Shape {
    var points: [SIMD3<Float>]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        let xs = points.map { CGFloat($0.x) }
        let zs = points.map { CGFloat($0.z) }
        let minX = xs.min() ?? 0; let maxX = xs.max() ?? 1
        let minZ = zs.min() ?? 0; let maxZ = zs.max() ?? 1
        let width = maxX - minX; let height = maxZ - minZ
        
        // Protection division par zéro
        let wDenom = width == 0 ? 1 : width
        let hDenom = height == 0 ? 1 : height
        
        let scale = min(rect.width / wDenom, rect.height / hDenom) * 0.8
        let offsetX = (rect.width - width * scale) / 2
        let offsetY = (rect.height - height * scale) / 2
        
        func point(at i: Int) -> CGPoint {
            return CGPoint(x: (CGFloat(points[i].x) - minX) * scale + offsetX, y: (CGFloat(points[i].z) - minZ) * scale + offsetY)
        }
        path.move(to: point(at: 0))
        for i in 1..<points.count { path.addLine(to: point(at: i)) }
        path.closeSubpath()
        return path
    }
}

struct GridShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 30
        for x in stride(from: 0, to: rect.width, by: step) {
            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        for y in stride(from: 0, to: rect.height, by: step) {
            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}

struct ExportableView: View {
    @ObservedObject var manager: GardenManager
    var body: some View {
        ZStack {
            Color.white
            VStack(spacing: 20) {
                Text(L10n.t("MEASURE_GARDEN_PLAN_TITLE")).font(.headline).tracking(4).foregroundColor(.black).padding(.top, 40)
                VStack {
                    Text("\(String(format: "%.2f", manager.area)) m²").font(.system(size: 60, weight: .bold)).foregroundColor(.black)
                    Text(L10n.f("MEASURE_PERIMETER_FORMAT", Double(manager.perimeter))).font(.subheadline).foregroundColor(.gray)
                }
                Divider().padding(.horizontal)
                ZStack {
                    GridShape().stroke(Color.gray.opacity(0.1))
                    GardenShape(points: manager.points).stroke(Color.black, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 400).padding()
                Spacer()
                Text(L10n.t("MEASURE_GENERATED_BY")).font(.caption2).foregroundColor(.gray).padding(.bottom, 20)
            }
        }.frame(width: 500, height: 700)
    }
}

// MARK: - 4. UI PRINCIPALE (Avec Correctifs)
struct ARViewContainerMesure: View {
    let selectedPlants: [Plant]

    // 🆕 Paramètres du wizard
    let uid: String
    let wizard: GardenWizardDTO
    let gardenName: String
    let thumbnailKey: String?
    let existingGardenId: String?
    let measurementOnly: Bool
    let exposureSpaceType: GardenSpaceType?
    let onSuccess: () -> Void

    /// Callback du wizard (`QuestionnaireView`) : appelé quand le tracé est
    /// validé ET que `POST /gardens` a renvoyé un id Mongo. Fournit l'id
    /// serveur + les mesures pour que le wizard passe à l'étape suivante.
    /// Si nil, on retombe sur le flow historique (nested
    /// `GardenARPlacementView`) qui POST en fin de placement.
    let onTraceValidated: ((String, [SIMD3<Float>], Float, Float, GardenLightExposureDTO?) -> Void)?
    /// Callback wizard : appelé si l'utilisateur dismiss sans valider.
    let onCancel: (() -> Void)?
    /// Disponible uniquement lorsqu'une autre méthode de mesure est réellement
    /// supportée sur l'appareil (pièce avec RoomPlan).
    let onChangeMethod: (() -> Void)?

    @StateObject var gardenManager = GardenManager()
    @State private var showFullScreenPlan = false
    @State private var saveSuccess = false
    @State private var showARPlacement = false
    @State private var isCreatingGarden = false
    @State private var createGardenError: String? = nil
    @State private var showExposureStep = false
    @State private var capturedLightExposure: GardenLightExposureDTO?

    // 🆕 ID temporaire pour la WorldMap
    @State private var tempGardenId = UUID().uuidString

    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject private var tabRouter: TabRouter

    // Initialiseur avec valeurs par défaut pour compatibilité
    init(
        selectedPlants: [Plant] = [],
        uid: String = "TEST_UID",
        wizard: GardenWizardDTO = GardenWizardDTO(
            style: "",
            spaceType: "",
            exposure: nil,
            maintenance: nil,
            safety: [],
            soil: nil,
            scanMethod: nil
        ),
        gardenName: String = L10n.t("MY_GARDEN_TITLE"),
        thumbnailKey: String? = nil,
        existingGardenId: String? = nil,
        measurementOnly: Bool = false,
        exposureSpaceType: GardenSpaceType? = nil,
        onSuccess: @escaping () -> Void = {},
        onTraceValidated: ((String, [SIMD3<Float>], Float, Float, GardenLightExposureDTO?) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onChangeMethod: (() -> Void)? = nil
    ) {
        self.selectedPlants = selectedPlants
        self.uid = uid
        self.wizard = wizard
        self.gardenName = gardenName
        self.thumbnailKey = thumbnailKey
        self.existingGardenId = existingGardenId
        self.measurementOnly = measurementOnly
        self.exposureSpaceType = exposureSpaceType
        self.onSuccess = onSuccess
        self.onTraceValidated = onTraceValidated
        self.onCancel = onCancel
        self.onChangeMethod = onChangeMethod
    }

    // 🆕 Crée le jardin en base APRÈS le tracé : sauvegarde locale, POST
    // /gardens, migration des fichiers tempId → serverId, puis callback
    // au wizard. Conçu pour ne PAS chaîner sur `GardenARPlacementView` —
    // c'est le wizard qui ouvrira la placement view ensuite, après les
    // questions essentielles.
    @MainActor
    private func createGardenAfterTrace() async {
        guard onTraceValidated != nil else { return }
        isCreatingGarden = true
        createGardenError = nil

        // 1. Demande la sauvegarde de la WorldMap au coordinator AR (notif).
        saveWorldMapForPlacement()
        // Délai pour laisser le temps à ARView de matérialiser le fichier
        // (la sauvegarde est asynchrone côté ARSession.getCurrentWorldMap).
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // 2. Écrit la scene JSON avec la boundary mesurée (sans plantes).
        //    Permet au mode .reopen de retrouver la forme du jardin plus tard.
        let boundary = gardenManager.points
        let scene = PersistedARScene(
            savedAt: Date(),
            plants: [],
            boundaryPoints: boundary.map { [$0.x, $0.y, $0.z] },
            area: gardenManager.area,
            perimeter: gardenManager.perimeter
        )
        let tempSceneURL = GardenLocalStore.sceneURL(for: tempGardenId)
        do {
            try JSONEncoder().encode(scene).write(to: tempSceneURL)
        } catch {
            print("⚠️ scene JSON pré-write a échoué: \(error)")
        }

        // 3. POST /gardens — plants vides à ce stade.
        var completedWizard = wizard
        completedWizard.lightExposure = capturedLightExposure

        let createDTO = GardenCreateDTO(
            name: gardenName,
            wizard: completedWizard,
            plants: [],
            thumbnailKey: thumbnailKey,
            measurements: GardenMeasurementsDTO(
                boundaryPoints: boundary.map { [$0.x, $0.y, $0.z] },
                area: gardenManager.area,
                perimeter: gardenManager.perimeter
            )
        )

        do {
            let created = try await GardenAPI.shared.createGarden(createDTO)
            let serverId = created.id ?? tempGardenId

            // 4. Migration des fichiers tempGardenId → serverId.
            if serverId != tempGardenId {
                migrateLocalFiles(from: tempGardenId, to: serverId)
            }

            // 5. Callback vers le wizard. Pas de presentationMode.dismiss()
            //    ici — c'est le wizard qui contrôle la cover.
            onTraceValidated?(
                serverId,
                boundary,
                gardenManager.area,
                gardenManager.perimeter,
                capturedLightExposure
            )
        } catch {
            print("❌ POST /gardens a échoué: \(error)")
            createGardenError = L10n.t("MEASURE_SAVE_ERROR")
        }
        isCreatingGarden = false
    }

    /// Renomme/copie les fichiers locaux `worldmap_*.arworldmap` et
    /// `scene_*.json` du `tempGardenId` vers le `serverId`. Idempotent.
    private func migrateLocalFiles(from oldId: String, to newId: String) {
        let fm = FileManager.default
        let oldMap = GardenLocalStore.worldMapURL(for: oldId)
        let newMap = GardenLocalStore.worldMapURL(for: newId)
        if fm.fileExists(atPath: oldMap.path) {
            do {
                if fm.fileExists(atPath: newMap.path) { try fm.removeItem(at: newMap) }
                try fm.copyItem(at: oldMap, to: newMap)
                try? fm.removeItem(at: oldMap)
            } catch {
                print("⚠️ worldmap copy failed: \(error)")
            }
        }
        let oldScene = GardenLocalStore.sceneURL(for: oldId)
        let newScene = GardenLocalStore.sceneURL(for: newId)
        if fm.fileExists(atPath: oldScene.path) {
            do {
                if fm.fileExists(atPath: newScene.path) { try fm.removeItem(at: newScene) }
                try fm.copyItem(at: oldScene, to: newScene)
                try? fm.removeItem(at: oldScene)
            } catch {
                print("⚠️ scene copy failed: \(error)")
            }
        }
    }
    
    // 🆕 Fonction pour sauvegarder la WorldMap
    private func saveWorldMapForPlacement() {
        // Note: Cette fonction sera appelée depuis le button handler
        // La sauvegarde réelle se fera via une notification ou callback vers ARViewContainerGarden
        let targetGardenId = existingGardenId ?? tempGardenId
        print("🗺️ Demande de sauvegarde WorldMap pour: \(targetGardenId)")
        print("📢 Envoi notification .saveWorldMapForMeasurement")
        NotificationCenter.default.post(name: .saveWorldMapForMeasurement, object: targetGardenId)
        print("📢 Notification envoyée")
    }

    @MainActor
    private func saveMeasurementsOnly() async {
        guard let existingGardenId else {
            showARPlacement = true
            return
        }

        isCreatingGarden = true
        createGardenError = nil

        let sceneURL = GardenLocalStore.sceneURL(for: existingGardenId)
        let existingPlants: [PersistedPlant]

        // Convention #170 : on lit l'existant en migrant si nécessaire
        // depuis le format legacy (positions shiftées par centroïde) vers
        // le format world frame. Sans cette migration, écrire une nouvelle
        // boundary world-frame à côté de plants legacy produirait un JSON
        // en 2 frames incompatibles (= issue #136 — closed by this).
        if FileManager.default.fileExists(atPath: sceneURL.path),
           let data = try? Data(contentsOf: sceneURL),
           let scene = try? JSONDecoder().decode(PersistedARScene.self, from: data).normalizedToWorldFrame() {
            existingPlants = scene.plants
        } else {
            existingPlants = []
        }

        let boundary = gardenManager.points.map { [$0.x, $0.y, $0.z] }
        let scene = PersistedARScene(
            savedAt: Date(),
            plants: existingPlants,
            boundaryPoints: boundary,
            area: gardenManager.area,
            perimeter: gardenManager.perimeter
        )

        do {
            try await GardenAPI.shared.updateGarden(
                id: existingGardenId,
                patch: GardenAPI.GardenPatch(
                    measurements: GardenMeasurementsDTO(
                        boundaryPoints: boundary,
                        area: gardenManager.area,
                        perimeter: gardenManager.perimeter
                    )
                )
            )

            saveWorldMapForPlacement()
            try? await Task.sleep(nanoseconds: 600_000_000)

            let data = try JSONEncoder().encode(scene)
            try data.write(to: sceneURL)
            isCreatingGarden = false
            presentationMode.wrappedValue.dismiss()
            onSuccess()
        } catch {
            print("❌ Erreur sauvegarde mesures 2D: \(error)")
            createGardenError = L10n.t("MEASURE_SAVE_ERROR")
            isCreatingGarden = false
        }
    }

    var body: some View {
        ZStack {
            ARViewContainerGarden(manager: gardenManager)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.62), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            LinearGradient(
                colors: [.clear, .black.opacity(0.48)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 370)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if !showExposureStep {
                targetReticle
            }

            VStack(spacing: 0) {
                if !showExposureStep {
                    measurementHeader
                }
                Spacer(minLength: 120)
                if !showExposureStep {
                    measurementPanel
                }
            }

            if showExposureStep, let exposureSpaceType {
                GardenExposureCaptureOverlay(spaceType: exposureSpaceType) { magneticYaw in
                    captureLightExposure(magneticYawRadians: magneticYaw)
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .statusBar(hidden: true)
        .onAppear {
            print("🎯 ARViewContainerMesure: Vue chargée - AR devrait démarrer")
            print("🎯 Points actuels: \(gardenManager.points.count)")
        }
        .animation(.easeInOut(duration: 0.2), value: gardenManager.canPlacePoint)
        .animation(.easeInOut(duration: 0.2), value: gardenManager.points.count)

        .fullScreenCover(isPresented: $showARPlacement) {
            GardenARPlacementView(
                selectedPlants: selectedPlants,
                uid: uid,
                wizard: wizard,
                gardenName: gardenName,
                thumbnailKey: thumbnailKey,
                existingGardenId: nil,
                mode: .create,
                boundaryPoints: gardenManager.points,
                area: gardenManager.area,
                perimeter: gardenManager.perimeter,
                measurementWorldMapId: existingGardenId ?? tempGardenId,
                onValidated: {
                    showARPlacement = false
                    tabRouter.selectedTab = .home
                    presentationMode.wrappedValue.dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        onSuccess()
                    }
                }
            )
        }

        .sheet(isPresented: $showFullScreenPlan) {
            VStack {
                HStack {
                    Text(L10n.t("MEASURE_TOP_VIEW_PLAN")).font(.title2).bold()
                    Spacer()
                    Button(action: { showFullScreenPlan = false }) {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.gray.opacity(0.5))
                    }
                }.padding()

                Spacer()

                ZStack {
                    GridShape().stroke(Color.gray.opacity(0.1))
                    GardenShape(points: gardenManager.points)
                        .stroke(Color.black, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        .padding(40)
                }
                .background(Color.white)
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.1), radius: 10)
                .padding()
                .frame(maxHeight: 500)

                Spacer()

                Button(action: { saveToGallery() }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text(L10n.t("MEASURE_SAVE_TO_PHOTOS"))
                    }
                    .font(.headline).foregroundColor(.white).padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(15)
                }.padding()

                if saveSuccess {
                    Text(L10n.t("MEASURE_IMAGE_SAVED"))
                        .font(.caption).bold()
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var canContinue: Bool {
        gardenManager.points.count >= 3
    }

    private var measurementHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: cancelMeasurement) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                }

                Spacer()

                HStack(spacing: 7) {
                    Circle()
                        .fill(gardenManager.canPlacePoint ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(
                        L10n.f(
                            gardenManager.points.count == 1
                                ? "MEASURE_POINT_FORMAT"
                                : "MEASURE_POINTS_FORMAT",
                            gardenManager.points.count
                        )
                    )
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
            }

            if let onChangeMethod {
                Button(action: onChangeMethod) {
                    Label(L10n.t("WIZARD_SCAN_CHANGE_METHOD"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var targetReticle: some View {
        ZStack {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.25))
                    .frame(width: 76, height: 76)

                Circle()
                    .stroke(
                        gardenManager.canPlacePoint ? Color.green : Color.white,
                        style: StrokeStyle(
                            lineWidth: 2.5,
                            lineCap: .round,
                            dash: gardenManager.canPlacePoint ? [] : [7, 6]
                        )
                    )
                    .frame(width: 62, height: 62)

                Circle()
                    .fill(gardenManager.canPlacePoint ? Color.green : Color.white)
                    .frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.35), radius: 3)
            }
            .scaleEffect(gardenManager.canPlacePoint ? 1 : 0.92)

            Text(
                L10n.t(
                    gardenManager.canPlacePoint
                        ? "MEASURE_TARGET_READY"
                        : "MEASURE_TARGET_SEARCHING"
                )
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .offset(y: 58)
        }
        .allowsHitTesting(false)
    }

    private var measurementPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                measurementStat(
                    icon: "point.3.connected.trianglepath.dotted",
                    value: "\(gardenManager.points.count)",
                    label: L10n.t("MEASURE_POINTS_LABEL")
                )
                measurementStat(
                    icon: "square.dashed",
                    value: String(format: "%.2f m²", gardenManager.area),
                    label: L10n.t("MEASURE_AREA_LABEL")
                )
                measurementStat(
                    icon: "ruler",
                    value: String(format: "%.2f m", gardenManager.perimeter),
                    label: L10n.t("MEASURE_PERIMETER_LABEL")
                )
            }

            Button {
                gardenManager.requestPointPlacement()
            } label: {
                Label(L10n.t("MEASURE_ADD_POINT"), systemImage: "plus.circle.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        gardenManager.canPlacePoint
                            ? ArboreDesign.Colors.primaryGreen
                            : Color.gray.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!gardenManager.canPlacePoint)

            HStack(spacing: 10) {
                measurementAction(
                    title: L10n.t("MEASURE_UNDO_POINT"),
                    icon: "arrow.uturn.backward",
                    isEnabled: !gardenManager.points.isEmpty,
                    action: gardenManager.undoLastPoint
                )
                measurementAction(
                    title: L10n.t("MEASURE_RESTART"),
                    icon: "arrow.counterclockwise",
                    isEnabled: !gardenManager.points.isEmpty,
                    action: gardenManager.reset
                )
                measurementAction(
                    title: L10n.t("MEASURE_PLAN"),
                    icon: "map",
                    isEnabled: canContinue,
                    action: { showFullScreenPlan = true }
                )
            }

            if let createGardenError {
                Text(createGardenError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: validateBoundary) {
                HStack(spacing: 9) {
                    if isCreatingGarden {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                    }
                    Text(L10n.t("MEASURE_VALIDATE_BOUNDARY"))
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    Color.black.opacity(canContinue && !isCreatingGarden ? 0.82 : 0.28),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canContinue || isCreatingGarden)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.26), radius: 20, y: 10)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private func measurementStat(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Label(value, systemImage: icon)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity)
    }

    private func measurementAction(
        title: String,
        icon: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(.white.opacity(isEnabled ? 0.95 : 0.38))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(.white.opacity(isEnabled ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func cancelMeasurement() {
        if let onCancel {
            onCancel()
        } else {
            presentationMode.wrappedValue.dismiss()
        }
    }

    private func validateBoundary() {
        guard canContinue, !isCreatingGarden else { return }

        if measurementOnly {
            Task { await saveMeasurementsOnly() }
        } else if onTraceValidated != nil {
            if requiresExposureCapture, capturedLightExposure == nil {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showExposureStep = true
                }
            } else {
                Task { await createGardenAfterTrace() }
            }
        } else {
            saveWorldMapForPlacement()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showARPlacement = true
            }
        }
    }

    private var requiresExposureCapture: Bool {
        guard let exposureSpaceType else { return false }
        return exposureSpaceType != .garden
    }

    private func captureLightExposure(magneticYawRadians: Double?) {
        guard let direction = gardenManager.currentCameraDirection else { return }
        capturedLightExposure = .capture(
            direction: direction,
            magneticYawRadians: magneticYawRadians,
            ambientIntensity: gardenManager.currentAmbientIntensity
        )
        showExposureStep = false
        Task { await createGardenAfterTrace() }
    }

    @MainActor
    private func saveToGallery() {
        let renderer = ImageRenderer(content: ExportableView(manager: gardenManager))
        renderer.scale = 3.0
        if let image = renderer.uiImage {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            withAnimation { saveSuccess = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { saveSuccess = false }
            }
        }
    }
}
