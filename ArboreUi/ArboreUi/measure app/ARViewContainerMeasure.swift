import SwiftUI
import ARKit
import SceneKit // ✅ On passe à SceneKit pour la stabilité sur iPhone 16/17 Pro
import Combine
import PhotosUI

// 🆕 Extension pour les notifications
extension Notification.Name {
    static let saveWorldMapForMeasurement = Notification.Name("saveWorldMapForMeasurement")
}

// MARK: - 1. LE CERVEAU (ViewModel)
// (Inchangé, il fonctionne très bien)
class GardenManager: ObservableObject {
    @Published var points: [SIMD3<Float>] = []
    @Published var area: Float = 0.0
    @Published var perimeter: Float = 0.0
    
    let resetSignal = PassthroughSubject<Void, Never>()
    
    func addPoint(_ point: SIMD3<Float>) {
        DispatchQueue.main.async {
            self.points.append(point)
            self.calculateStats()
        }
    }
    
    func reset() {
        points.removeAll()
        area = 0.0
        perimeter = 0.0
        resetSignal.send()
    }
    
    private func calculateStats() {
        guard points.count > 1 else { return }
        
        // Périmètre
        var tempPerimeter: Float = 0
        for i in 0..<points.count-1 {
            tempPerimeter += distance(points[i], points[i+1])
        }
        if points.count > 2 {
            tempPerimeter += distance(points.last!, points.first!)
        }
        self.perimeter = tempPerimeter
        
        // Surface (Shoelace)
        guard points.count > 2 else { self.area = 0; return }
        var tempArea: Float = 0.0
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            let tempAreaVal = (points[i].x * points[j].z) - (points[i].z * points[j].x)
            tempArea += tempAreaVal
        }
        self.area = abs(tempArea) / 2.0
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
        
        // 4. Gestion du Tap
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        sceneView.addGestureRecognizer(tapGesture)
        
        context.coordinator.arView = sceneView
        context.coordinator.setupSubscription()
        
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
        var cancellable: AnyCancellable?
        var worldMapObserver: NSObjectProtocol?
        
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
        
        func setupSubscription() {
            // Reset : On supprime tous les noeuds enfants de la scène
            cancellable = manager.resetSignal.sink { [weak self] in
                self?.arView?.scene.rootNode.childNodes.forEach { node in
                    // On garde les lumières ou caméras par défaut, on supprime juste nos sphères
                    if node.geometry is SCNSphere {
                        node.removeFromParentNode()
                    }
                }
            }
        }
        
        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView = self.arView else { return }
            let location = sender.location(in: arView)

            // Two-tier raycast (cf audit AR finding Y-10 / issue #171) :
            // prefer .existingPlaneGeometry (real detected plane) over
            // .estimatedPlane (ARKit's best-guess from feature points,
            // ±10-30 cm en zone faible texture). Le Y de la boundary sert
            // ensuite de référence dans GardenMorpher.morph(floorY:), donc
            // une erreur de quelques cm propagée à tous les points de la
            // boundary contamine durablement les futurs morphs.
            let result: ARRaycastResult? = {
                if let q = arView.raycastQuery(from: location, allowing: .existingPlaneGeometry, alignment: .horizontal),
                   let r = arView.session.raycast(q).first {
                    return r
                }
                if let q = arView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal),
                   let r = arView.session.raycast(q).first {
                    return r
                }
                return nil
            }()

            if let firstResult = result {
                // 1. Création visuelle (Sphère verte) en SceneKit
                let sphereGeometry = SCNSphere(radius: 0.05)
                sphereGeometry.firstMaterial?.diffuse.contents = UIColor.green
                sphereGeometry.firstMaterial?.lightingModel = .physicallyBased
                
                let sphereNode = SCNNode(geometry: sphereGeometry)
                // Positionnement via la matrice de transformation du raycast
                sphereNode.simdTransform = firstResult.worldTransform
                
                // Petit ajustement Y pour que la sphère soit posée "sur" le sol et non "dedans"
                sphereNode.position.y += 0.05
                
                arView.scene.rootNode.addChildNode(sphereNode)
                
                // 2. Enregistrement des données
                let position = SIMD3<Float>(
                    firstResult.worldTransform.columns.3.x,
                    firstResult.worldTransform.columns.3.y,
                    firstResult.worldTransform.columns.3.z
                )
                manager.addPoint(position)
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
                Text("PLAN DU JARDIN").font(.headline).tracking(4).foregroundColor(.black).padding(.top, 40)
                VStack {
                    Text("\(String(format: "%.2f", manager.area)) m²").font(.system(size: 60, weight: .bold)).foregroundColor(.black)
                    Text("Périmètre: \(String(format: "%.2f", manager.perimeter)) m").font(.subheadline).foregroundColor(.gray)
                }
                Divider().padding(.horizontal)
                ZStack {
                    GridShape().stroke(Color.gray.opacity(0.1))
                    GardenShape(points: manager.points).stroke(Color.black, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 400).padding()
                Spacer()
                Text("Généré via GardenAR").font(.caption2).foregroundColor(.gray).padding(.bottom, 20)
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
    let onSuccess: () -> Void

    /// Callback du wizard (`QuestionnaireView`) : appelé quand le tracé est
    /// validé ET que `POST /gardens` a renvoyé un id Mongo. Fournit l'id
    /// serveur + les mesures pour que le wizard passe à l'étape suivante.
    /// Si nil, on retombe sur le flow historique (nested
    /// `GardenARPlacementView`) qui POST en fin de placement.
    let onTraceValidated: ((String, [SIMD3<Float>], Float, Float) -> Void)?
    /// Callback wizard : appelé si l'utilisateur dismiss sans valider.
    let onCancel: (() -> Void)?

    @StateObject var gardenManager = GardenManager()
    @State private var showFullScreenPlan = false
    @State private var saveSuccess = false
    @State private var showARPlacement = false
    @State private var arIsReady = false  // 🆕 Indicateur AR
    @State private var isCreatingGarden = false
    @State private var createGardenError: String? = nil

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
        gardenName: String = "Mon jardin",
        thumbnailKey: String? = nil,
        existingGardenId: String? = nil,
        measurementOnly: Bool = false,
        onSuccess: @escaping () -> Void = {},
        onTraceValidated: ((String, [SIMD3<Float>], Float, Float) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.selectedPlants = selectedPlants
        self.uid = uid
        self.wizard = wizard
        self.gardenName = gardenName
        self.thumbnailKey = thumbnailKey
        self.existingGardenId = existingGardenId
        self.measurementOnly = measurementOnly
        self.onSuccess = onSuccess
        self.onTraceValidated = onTraceValidated
        self.onCancel = onCancel
    }

    // 🆕 Crée le jardin en base APRÈS le tracé : sauvegarde locale, POST
    // /gardens, migration des fichiers tempId → serverId, puis callback
    // au wizard. Conçu pour ne PAS chaîner sur `GardenARPlacementView` —
    // c'est le wizard qui ouvrira la placement view ensuite, après l'étape
    // `aiSuggestion`.
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
        let createDTO = GardenCreateDTO(
            name: gardenName,
            wizard: wizard,
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
            onTraceValidated?(serverId, boundary, gardenManager.area, gardenManager.perimeter)
        } catch {
            print("❌ POST /gardens a échoué: \(error)")
            createGardenError = "Impossible de sauvegarder le jardin. Vérifie ta connexion et réessaie."
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

    private func saveMeasurementsOnly() {
        guard let existingGardenId else {
            showARPlacement = true
            return
        }

        saveWorldMapForPlacement()

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
            let data = try JSONEncoder().encode(scene)
            try data.write(to: sceneURL)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                presentationMode.wrappedValue.dismiss()
                onSuccess()
            }
        } catch {
            print("❌ Erreur sauvegarde mesures 2D: \(error)")
        }
    }

    var body: some View {
        ZStack {
            // Fond gris système
            Color(UIColor.systemGray6).edgesIgnoringSafeArea(.all)

            // --- AR VIEW CORRIGÉE (SceneKit) ---
            ARViewContainerGarden(manager: gardenManager)
                .edgesIgnoringSafeArea(.all)

            // --- INTERFACE UI ---
            VStack {
                // Header
                HStack(alignment: .top) {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Spacer()
                    
                    // 🆕 Indicateur AR Status
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("AR Active")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        
                        Text("Touchez le sol pour placer des points")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.4))
                            .cornerRadius(6)
                    }
                    
                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("SURFACE TOTALE")
                            .font(.system(size: 10, weight: .bold)).tracking(1.5)
                            .foregroundStyle(.white.opacity(0.6))
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.2f", gardenManager.area))
                                .font(.system(size: 42, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            Text("m²")
                                .font(.headline).foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    Spacer()

                    Button(action: { gardenManager.reset() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)

                Spacer()

                // Footer
                HStack(spacing: 0) {
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: "ruler").font(.caption).foregroundColor(.green)
                            Text("Relevés").font(.caption).fontWeight(.bold).textCase(.uppercase).foregroundColor(.white.opacity(0.6))
                        }.padding(.bottom, 5)

                        if gardenManager.points.count < 2 {
                            Text("Placez des points...")
                                .font(.caption).italic().foregroundColor(.white.opacity(0.4))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                        } else {
                            ScrollView(showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(1..<gardenManager.points.count, id: \.self) { i in
                                        HStack {
                                            Circle().fill(Color.green).frame(width: 6, height: 6)
                                            Text("P\(i) → P\(i+1)")
                                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                                .foregroundColor(.white.opacity(0.9))
                                            Spacer()
                                            Text(String(format: "%.2f m", distance(gardenManager.points[i], gardenManager.points[i-1])))
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, .white.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom))
                        .frame(width: 1)
                        .padding(.vertical, 20)

                    // Droite : aperçu + boutons
                    VStack(spacing: 10) {
                        Button(action: { showFullScreenPlan = true }) {
                            VStack {
                                ZStack {
                                    if gardenManager.points.isEmpty {
                                        Image(systemName: "square.dashed")
                                            .font(.largeTitle)
                                            .foregroundColor(.white.opacity(0.3))
                                    } else {
                                        GardenShape(points: gardenManager.points)
                                            .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                            .padding(10)
                                            .shadow(color: .green.opacity(0.6), radius: 8)
                                    }
                                }
                                .frame(height: 70)

                                Text("VOIR PLAN")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .frame(width: 120)
                            .contentShape(Rectangle())
                        }

                        Button {
                            print("🎯 Bouton CONTINUER cliqué")
                            if measurementOnly {
                                // Flow re-mesure depuis ManageGardenView — inchangé.
                                saveMeasurementsOnly()
                            } else if onTraceValidated != nil {
                                // 🆕 Flow wizard : POST /gardens immédiatement et
                                // rendre la main au wizard pour passer à l'étape
                                // suivante. Pas de nested AR placement view ici.
                                Task { await createGardenAfterTrace() }
                            } else {
                                // Fallback legacy : nested AR placement chain
                                // (utilisé quand la vue est appelée hors-wizard).
                                saveWorldMapForPlacement()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    print("🎯 Ouverture GardenARPlacementView avec ID: \(tempGardenId)")
                                    showARPlacement = true
                                }
                            }
                        } label: {
                            Text("CONTINUER")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 120)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.green.opacity(canContinue ? 1 : 0.35))
                                )
                        }
                        .disabled(!canContinue)
                    }
                    .padding(.trailing, 12)
                    .frame(width: 140)
                }
                .frame(height: 160)
                .background(.ultraThinMaterial)
                .cornerRadius(30)
                .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .statusBar(hidden: true)
        .onAppear {
            print("🎯 ARViewContainerMesure: Vue chargée - AR devrait démarrer")
            print("🎯 Points actuels: \(gardenManager.points.count)")
        }

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
                    Text("Plan Vue du Dessus").font(.title2).bold()
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
                        Text("Sauvegarder dans Photos")
                    }
                    .font(.headline).foregroundColor(.white).padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(15)
                }.padding()

                if saveSuccess {
                    Text("✅ Image sauvegardée !")
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
        gardenManager.points.count >= 3 // Corrigé à 3 pour avoir un polygone valide
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
