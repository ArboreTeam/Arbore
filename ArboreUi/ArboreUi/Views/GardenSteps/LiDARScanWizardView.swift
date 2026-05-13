import SwiftUI
import RoomPlan

struct LiDARScanWizardView: View {
    // Entrées du wizard
    let uid: String
    let selectedPlants: [Plant]
    let wizard: GardenWizardDTO
    let gardenName: String
    let thumbnailKey: String?
    /// Callback wizard : appelé quand le scan est validé ET que
    /// `POST /gardens` a renvoyé un id Mongo. Fournit (serverId, area,
    /// perimeter). Si nil, on retombe sur le flow legacy (nested AR placement).
    let onTraceValidated: ((String, Float, Float) -> Void)?
    let onCancel: (() -> Void)?
    /// Callback legacy conservé pour compatibilité avec un éventuel appel
    /// hors-wizard. Ignoré quand `onTraceValidated` est fourni.
    let onSuccess: () -> Void

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var tabRouter: TabRouter

    // State LiDAR
    @State private var captureController = RoomCaptureController()
    @State private var isProcessing = false
    @State private var showARPlacement = false
    @State private var createGardenError: String? = nil

    // Mesures extraites
    @State private var extractedArea: Float = 0.0
    @State private var extractedPerimeter: Float = 0.0
    // UUID pour la WorldMap et l'identification du jardin AR (avant POST)
    @State private var tempGardenId = UUID().uuidString

    init(
        uid: String,
        selectedPlants: [Plant],
        wizard: GardenWizardDTO,
        gardenName: String,
        thumbnailKey: String?,
        onTraceValidated: ((String, Float, Float) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onSuccess: @escaping () -> Void = {}
    ) {
        self.uid = uid
        self.selectedPlants = selectedPlants
        self.wizard = wizard
        self.gardenName = gardenName
        self.thumbnailKey = thumbnailKey
        self.onTraceValidated = onTraceValidated
        self.onCancel = onCancel
        self.onSuccess = onSuccess
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            // Caméra LiDAR pleine vue
            CameraCaptureView()
                .environment(captureController)
                .ignoresSafeArea()
                .onAppear {
                    captureController.showSaveButton = false
                    captureController.isScanComplete = false
                    captureController.startSession()
                }
                .onDisappear {
                    captureController.stopSession()
                }

            // Interface
            VStack {
                HStack(alignment: .top) {
                    Button(action: {
                        onCancel?()
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Spacer()

                    VStack {
                        Text("Scan 3D")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Balayez les murs et l'espace de votre jardin/pièce.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()

                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 24)
                .padding(.top, 50)

                Spacer()

                if let err = createGardenError {
                    Text(err)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.bottom, 12)
                }

                if isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("Calcul des mesures...")
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .padding(.bottom, 50)
                } else if captureController.showSaveButton {
                    Button(action: {
                        captureController.stopSession()
                        processScanAndContinue()
                    }) {
                        HStack {
                            Text("Scanner le jardin terminé")
                            Image(systemName: "checkmark")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 24)
                        .background(Color.blue)
                        .cornerRadius(30)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        // Legacy nested AR placement — utilisé uniquement si la view est
        // appelée hors-wizard (onTraceValidated == nil).
        .fullScreenCover(isPresented: $showARPlacement) {
            GardenARPlacementView(
                selectedPlants: selectedPlants,
                uid: uid,
                wizard: wizard,
                gardenName: gardenName,
                thumbnailKey: thumbnailKey,
                existingGardenId: nil,
                mode: .create,
                boundaryPoints: [],
                area: extractedArea,
                perimeter: extractedPerimeter,
                measurementWorldMapId: tempGardenId,
                onValidated: {
                    showARPlacement = false
                    tabRouter.selectedTab = .home
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        onSuccess()
                    }
                }
            )
        }
    }

    private func processScanAndContinue() {
        isProcessing = true
        print("🗺️ LiDAR: Sauvegarde WorldMap pour AR Placement avec ID \(tempGardenId)")
        captureController.roomCaptureView.captureSession.arSession.getCurrentWorldMap { worldMap, error in
            if let map = worldMap {
                do {
                    let mapData = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                    let url = GardenLocalStore.worldMapURL(for: tempGardenId)
                    try mapData.write(to: url)
                    print("✅ WorldMap LiDAR sauvegardée")
                } catch {
                    print("❌ Erreur sauvegarde WorldMap LiDAR: \(error)")
                }
            }

            var area: Float = 0.0
            var perimeter: Float = 0.0

            if let room = captureController.finalResult {
                for floor in room.floors {
                    area += Float(floor.dimensions.x * floor.dimensions.y)
                }
                for wall in room.walls {
                    perimeter += Float(wall.dimensions.x)
                }
            }

            if area == 0 {
                area = 10.0
                perimeter = 12.6
            }

            self.extractedArea = area
            self.extractedPerimeter = perimeter
            print("📐 LiDAR: Surface calculée \(area) m², Périmètre \(perimeter) m")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if onTraceValidated != nil {
                    // 🆕 Flow wizard : POST /gardens et callback.
                    Task { await self.createGardenAfterScan(area: area, perimeter: perimeter) }
                } else {
                    // Legacy : ouvrir la nested placement view.
                    isProcessing = false
                    showARPlacement = true
                }
            }
        }
    }

    @MainActor
    private func createGardenAfterScan(area: Float, perimeter: Float) async {
        // Écrit la scene JSON avec aire/périmètre (pas de boundary 2D en LiDAR).
        let scene = PersistedARScene(
            savedAt: Date(),
            plants: [],
            boundaryPoints: [],
            area: area,
            perimeter: perimeter
        )
        let tempSceneURL = GardenLocalStore.sceneURL(for: tempGardenId)
        try? JSONEncoder().encode(scene).write(to: tempSceneURL)

        let createDTO = GardenCreateDTO(
            name: gardenName,
            wizard: wizard,
            plants: [],
            thumbnailKey: thumbnailKey
        )

        do {
            let created = try await GardenAPI.shared.createGarden(createDTO)
            let serverId = created.id ?? tempGardenId

            if serverId != tempGardenId {
                migrateLocalFiles(from: tempGardenId, to: serverId)
            }

            isProcessing = false
            onTraceValidated?(serverId, area, perimeter)
        } catch {
            print("❌ POST /gardens (LiDAR) a échoué: \(error)")
            isProcessing = false
            createGardenError = "Impossible de sauvegarder le jardin. Vérifie ta connexion et réessaie."
        }
    }

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
                print("⚠️ worldmap copy (LiDAR) failed: \(error)")
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
                print("⚠️ scene copy (LiDAR) failed: \(error)")
            }
        }
    }
}
