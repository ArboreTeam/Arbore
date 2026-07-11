import SwiftUI
import RoomPlan
import simd

struct LiDARScanWizardView: View {
    // Entrées du wizard
    let uid: String
    let selectedPlants: [Plant]
    let wizard: GardenWizardDTO
    let gardenName: String
    let thumbnailKey: String?
    /// Callback wizard : appelé quand le scan est validé ET que
    /// `POST /gardens` a renvoyé un id Mongo. Fournit (serverId, boundary,
    /// area, perimeter). Si nil, on retombe sur le flow legacy (nested AR placement).
    let onTraceValidated: ((String, [SIMD3<Float>], Float, Float) -> Void)?
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
    @State private var extractedBoundaryPoints: [SIMD3<Float>] = []
    @State private var extractedArea: Float = 0.0
    @State private var extractedPerimeter: Float = 0.0
    // UUID pour la WorldMap et l'identification du jardin AR (avant POST)
    @State private var tempGardenId = UUID().uuidString
    // Manual finish button — visible after a short delay so the user
    // can stop the scan at will instead of waiting for RoomPlan to
    // decide it's done (which may never happen in complex scenes).
    @State private var showFinishButton = false
    @State private var scanStartTimer: Timer? = nil

    init(
        uid: String,
        selectedPlants: [Plant],
        wizard: GardenWizardDTO,
        gardenName: String,
        thumbnailKey: String?,
        onTraceValidated: ((String, [SIMD3<Float>], Float, Float) -> Void)? = nil,
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
                    // Show "Terminer le scan" after 3 s of scanning
                    scanStartTimer?.invalidate()
                    scanStartTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.35)) {
                                showFinishButton = true
                            }
                        }
                    }
                }
                .onDisappear {
                    scanStartTimer?.invalidate()
                    scanStartTimer = nil
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
                        Text(L10n.t("LIDAR_SCAN_TITLE"))
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(L10n.t("LIDAR_SCAN_SUBTITLE"))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()

                    // "Terminer le scan" button — top right, out of the way
                    // of the 3D room rendering at the bottom.
                    if showFinishButton && !isProcessing && !captureController.showSaveButton {
                        Button(action: {
                            finishScanManually()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(L10n.t("COMMON_FINISH"))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                                    )
                            )
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                        }
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 50)
                .animation(.easeOut(duration: 0.3), value: showFinishButton)

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
                        Text(L10n.t("LIDAR_SCAN_PROCESSING"))
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
                            Text(L10n.t("LIDAR_SCAN_DONE"))
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
                boundaryPoints: extractedBoundaryPoints,
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
    /// Called when the user taps "Terminer le scan". Stops the RoomPlan
    /// session (which triggers `captureView(didPresent:error:)` filling
    /// `finalResult`) then processes whatever was captured so far.
    private func finishScanManually() {
        showFinishButton = false
        captureController.stopSession()
        // Give RoomPlan a beat to finalize its CapturedRoom result
        // via the delegate before we read `finalResult`.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            processScanAndContinue()
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

            let measurements = Self.extractMeasurements(from: captureController.finalResult)
            let boundary = measurements.boundary
            let area = measurements.area
            let perimeter = measurements.perimeter

            print("📐 LiDAR: Surface calculée \(area) m², Périmètre \(perimeter) m, boundary \(boundary.count) points")

            DispatchQueue.main.async {
                self.extractedBoundaryPoints = boundary
                self.extractedArea = area
                self.extractedPerimeter = perimeter

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if onTraceValidated != nil {
                        // 🆕 Flow wizard : POST /gardens et callback.
                        Task { await self.createGardenAfterScan(boundary: boundary, area: area, perimeter: perimeter) }
                    } else {
                        // Legacy : ouvrir la nested placement view.
                        isProcessing = false
                        showARPlacement = true
                    }
                }
            }
        }
    }

    @MainActor
    private func createGardenAfterScan(boundary: [SIMD3<Float>], area: Float, perimeter: Float) async {
        // Écrit la scene JSON avec aire/périmètre et une boundary 2D dérivée du scan RoomPlan.
        let scene = PersistedARScene(
            savedAt: Date(),
            plants: [],
            boundaryPoints: boundary.map { [$0.x, $0.y, $0.z] },
            area: area,
            perimeter: perimeter
        )
        let tempSceneURL = GardenLocalStore.sceneURL(for: tempGardenId)
        try? JSONEncoder().encode(scene).write(to: tempSceneURL)

        let createDTO = GardenCreateDTO(
            name: gardenName,
            wizard: wizard,
            plants: [],
            thumbnailKey: thumbnailKey,
            measurements: GardenMeasurementsDTO(
                boundaryPoints: boundary.map { [$0.x, $0.y, $0.z] },
                area: area,
                perimeter: perimeter
            )
        )

        do {
            let created = try await GardenAPI.shared.createGarden(createDTO)
            let serverId = created.id ?? tempGardenId

            if serverId != tempGardenId {
                migrateLocalFiles(from: tempGardenId, to: serverId)
            }

            isProcessing = false
            onTraceValidated?(serverId, boundary, area, perimeter)
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

    private static func extractMeasurements(from room: CapturedRoom?) -> (boundary: [SIMD3<Float>], area: Float, perimeter: Float) {
        var area: Float = 0
        var perimeter: Float = 0
        var floorCorners: [SIMD3<Float>] = []

        if let room {
            for floor in room.floors {
                let width = max(Float(floor.dimensions.x), 0)
                let depth = max(Float(floor.dimensions.y), 0)
                guard width > 0, depth > 0 else { continue }

                area += width * depth
                floorCorners.append(contentsOf: rectangleCorners(transform: floor.transform, width: width, depth: depth))
            }

            for wall in room.walls {
                perimeter += max(Float(wall.dimensions.x), 0)
            }
        }

        var boundary = convexHullXZ(floorCorners)

        if area <= 0, !boundary.isEmpty {
            area = polygonArea(boundary)
        }
        if perimeter <= 0, !boundary.isEmpty {
            perimeter = polygonPerimeter(boundary)
        }
        if area <= 0 {
            area = 10.0
        }
        if perimeter <= 0 {
            perimeter = 12.6
        }
        if boundary.count < 3 {
            boundary = fallbackBoundary(area: area, perimeter: perimeter)
        }

        return (boundary, area, perimeter)
    }

    private static func rectangleCorners(transform: simd_float4x4, width: Float, depth: Float) -> [SIMD3<Float>] {
        let halfW = width / 2
        let halfD = depth / 2
        let localCorners = [
            SIMD4<Float>(-halfW, -halfD, 0, 1),
            SIMD4<Float>(halfW, -halfD, 0, 1),
            SIMD4<Float>(halfW, halfD, 0, 1),
            SIMD4<Float>(-halfW, halfD, 0, 1)
        ]

        return localCorners.map { local in
            let world = transform * local
            return SIMD3<Float>(world.x, world.y, world.z)
        }
    }

    private static func convexHullXZ(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard points.count > 3 else { return points }

        var seen = Set<String>()
        let unique = points.filter { point in
            let key = "\(Int((point.x * 1000).rounded())):\(Int((point.z * 1000).rounded()))"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
        .sorted {
            if abs($0.x - $1.x) > 0.0001 { return $0.x < $1.x }
            return $0.z < $1.z
        }

        guard unique.count > 3 else { return unique }

        func cross(_ origin: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
            (a.x - origin.x) * (b.z - origin.z) - (a.z - origin.z) * (b.x - origin.x)
        }

        var lower: [SIMD3<Float>] = []
        for point in unique {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }

        var upper: [SIMD3<Float>] = []
        for point in unique.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }

        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    private static func polygonArea(_ boundary: [SIMD3<Float>]) -> Float {
        guard boundary.count >= 3 else { return 0 }

        var sum: Float = 0
        for index in boundary.indices {
            let next = boundary[(index + 1) % boundary.count]
            sum += boundary[index].x * next.z - next.x * boundary[index].z
        }
        return abs(sum) * 0.5
    }

    private static func polygonPerimeter(_ boundary: [SIMD3<Float>]) -> Float {
        guard boundary.count >= 2 else { return 0 }

        var total: Float = 0
        for index in boundary.indices {
            let next = boundary[(index + 1) % boundary.count]
            total += simd_length(next - boundary[index])
        }
        return total
    }

    private static func fallbackBoundary(area: Float, perimeter: Float) -> [SIMD3<Float>] {
        let safeArea = max(Double(area), 1.0)
        let halfPerimeter = max(Double(perimeter) / 2.0, 4.0)
        let discriminant = halfPerimeter * halfPerimeter - 4.0 * safeArea

        let width: Double
        let depth: Double
        if discriminant >= 0 {
            width = max((halfPerimeter + discriminant.squareRoot()) / 2.0, 1.0)
            depth = max(safeArea / width, 1.0)
        } else {
            width = safeArea.squareRoot()
            depth = width
        }

        let halfW = Float(width / 2.0)
        let halfD = Float(depth / 2.0)
        return [
            SIMD3<Float>(-halfW, 0, -halfD),
            SIMD3<Float>(halfW, 0, -halfD),
            SIMD3<Float>(halfW, 0, halfD),
            SIMD3<Float>(-halfW, 0, halfD)
        ]
    }
}
