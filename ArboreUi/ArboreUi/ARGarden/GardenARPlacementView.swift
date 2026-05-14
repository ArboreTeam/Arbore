import SwiftUI
import ARKit
import SceneKit
import Foundation
import simd
import UIKit

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
    // Manual replacement (Issue #111)
    static let gardenAREnterManualReplacement = Notification.Name("gardenAREnterManualReplacement")
    static let gardenARCancelManualReplacement = Notification.Name("gardenARCancelManualReplacement")
    static let gardenARBoundaryUndoLast = Notification.Name("gardenARBoundaryUndoLast")
    static let gardenARValidateNewBoundary = Notification.Name("gardenARValidateNewBoundary")
    static let gardenARConfirmMorphedPlacement = Notification.Name("gardenARConfirmMorphedPlacement")
    static let gardenARRevertToMorphed = Notification.Name("gardenARRevertToMorphed")
    static let gardenARLoadOldData = Notification.Name("gardenARLoadOldData")
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
    @State private var shouldCaptureSharePhoto = false
    @State private var capturedShareImage: UIImage?
    @State private var showShareSheet = false
    @State private var showSharePreview = false
    @State private var isCapturingSharePhoto = false

    // Model download state
    @State private var downloadedModelURL: URL? = nil
    @State private var isDownloadingModel = false
    @State private var isRelocating = false

    // Manual replacement (Issue #111) state
    @State private var relocationPhase: RelocationPhase = .scanning
    @State private var newBoundaryPoints: [SIMD3<Float>] = []
    @State private var newBoundaryArea: Float = 0
    @State private var distortionWarnings: [DistortionWarning] = []

    // Set when reopening a garden whose local AR data was wiped (e.g. after
    // app reinstall or device change). The backend keeps the plant list for
    // the card, but the WorldMap and scene JSON are local-only — there's no
    // way to relocalize or morph without them. We surface a clear message
    // instead of letting the user spin on the scanning overlay forever.
    @State private var gardenUnavailable: Bool = false

    // 🤖 AI Auto-placement
    @State private var isAutoPlacing = false
    @State private var autoPlaceToast: String? = nil
    
    // 💡 Lux widget
    @State private var currentLux: Int = 0

    var body: some View {
        if gardenUnavailable {
            gardenUnavailableView
        } else {
            placementBody
        }
    }

    private var placementBody: some View {
        ZStack {
            // --- Vue AR ---
            GardenARPlacementContainerView(
                selectedPlant: $selectedPlantForPlacement,
                downloadedModelURL: $downloadedModelURL,
                isDownloadingModel: $isDownloadingModel,
                isRelocating: $isRelocating,
                hasSelectedNode: $hasSelectedNode,
                selectedNodeName: $selectedNodeName,
                isSaving: $isSaving,
                relocationPhase: $relocationPhase,
                newBoundaryPoints: $newBoundaryPoints,
                newBoundaryArea: $newBoundaryArea,
                distortionWarnings: $distortionWarnings,
                isAutoPlacing: $isAutoPlacing,
                autoPlaceToast: $autoPlaceToast,
                currentLux: $currentLux,
                shouldCaptureSharePhoto: $shouldCaptureSharePhoto,
                capturedShareImage: $capturedShareImage,
                isCapturingSharePhoto: $isCapturingSharePhoto,
                plantsToAutoPlace: selectedPlants,
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

            // --- Phase-based overlays (Issue #111) ---
            if mode == .reopen {
                switch relocationPhase {
                case .scanning where isRelocating:
                    ScanningCoachingOverlay(
                        onReplaceManually: {
                            NotificationCenter.default.post(name: .gardenAREnterManualReplacement, object: nil)
                        },
                        onCancel: { dismiss() }
                    )
                case .tracingBoundary, .morphingPreview, .adjusting:
                    // Hint + actions for these phases live inside the HUD
                    // VStack below — they reflow naturally under topBar and
                    // above the editing/save area, no overlap.
                    EmptyView()
                default:
                    EmptyView()
                }
            }

            // 🤖 Auto-placement overlay
            if isAutoPlacing {
                autoPlacingOverlay
            }

            // --- HUD Interface ---
            VStack(spacing: 0) {
                // 1. Barre du haut
                topBar

                // 1b. Phase-specific hint banner — sits directly under topBar
                // so it never collides with back/undo/redo. One banner per
                // phase (only the matching case renders).
                if mode == .reopen {
                    Group {
                        switch relocationPhase {
                        case .tracingBoundary:
                            BoundaryTracingHintBanner(
                                pointCount: newBoundaryPoints.count,
                                area: newBoundaryArea
                            )
                        case .morphingPreview:
                            MorphingPreviewHintBanner(warnings: distortionWarnings)
                        case .adjusting:
                            AdjustingHintBanner()
                        default:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.opacity)
                }

                // 💡 Lux widget — only in placement contexts (.create or
                // post-relocalization .scanning). Hidden during manual
                // replacement phases and during initial relocalization
                // coaching to keep the HUD focused.
                if !relocationPhase.isManualReplacement && !isRelocating {
                    luxWidget
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                }

                Spacer()

                // 🤖 Auto-place toast
                if let toast = autoPlaceToast {
                    autoPlaceToastView(toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                                withAnimation(.easeOut(duration: 0.4)) {
                                    autoPlaceToast = nil
                                }
                            }
                        }
                }

                // 2. Indicateur de sauvegarde
                if isSaving {
                    savingIndicator
                }

                // 3. Menu d'édition (si une plante est sélectionnée)
                if hasSelectedNode {
                    editingHUD.transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 3b. Phase-specific action row — sits directly under the
                // editingHUD (when a plant is selected) or just above the
                // safe-area bottom. One row per phase.
                if mode == .reopen {
                    Group {
                        switch relocationPhase {
                        case .tracingBoundary:
                            BoundaryTracingActionButtons(
                                pointCount: newBoundaryPoints.count,
                                onCancel: {
                                    NotificationCenter.default.post(name: .gardenARCancelManualReplacement, object: nil)
                                },
                                onUndoLast: {
                                    NotificationCenter.default.post(name: .gardenARBoundaryUndoLast, object: nil)
                                },
                                onValidate: {
                                    NotificationCenter.default.post(name: .gardenARValidateNewBoundary, object: nil)
                                }
                            )
                        case .morphingPreview:
                            MorphingPreviewActionButtons(
                                onCancel: {
                                    NotificationCenter.default.post(name: .gardenARCancelManualReplacement, object: nil)
                                },
                                onConfirm: {
                                    NotificationCenter.default.post(name: .gardenARConfirmMorphedPlacement, object: nil)
                                }
                            )
                        case .adjusting:
                            AdjustingActionButtons(
                                onRevert: {
                                    NotificationCenter.default.post(name: .gardenARRevertToMorphed, object: nil)
                                },
                                onValidate: {
                                    NotificationCenter.default.post(name: .gardenARValidate, object: nil)
                                }
                            )
                        default:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.opacity)
                }

                // 4. Dock du bas (Bouton Ajouter) — caché pendant les
                // phases de manual-replacement (Issue #111) ET pendant
                // la relocalisation initiale (sinon le `+` chevauche le
                // bouton "Replacer manuellement" de la coaching overlay).
                if !relocationPhase.isManualReplacement && !isRelocating {
                    bottomDock
                }
            }
        }
        .overlay(alignment: .top) {
            // Banner thermal critique (#82). Invisible par défaut, apparait
            // sur .arboreThermalCritical posée par ARQualityObserver, se
            // masque sur .arboreThermalRecovered.
            ThermalStateBanner()
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
                        AppLog.plants.notice("model pre-downloaded plant=\(plant.name, privacy: .public)")
                    } catch {
                        AppLog.plants.error("model pre-download failed plant=\(plant.name, privacy: .public) error=\(String(describing: error), privacy: .public)")
                        // Fallback to bundle if download fails
                        downloadedModelURL = plant.bundleModelURL
                    }
                    isDownloadingModel = false
                }
            }
            .presentationDetents([.large])
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $showShareSheet) {
            if let capturedShareImage {
                ShareSheet(items: [capturedShareImage])
            }
        }
        .onChange(of: capturedShareImage) { _, image in
            guard image != nil else { return }
            showSharePreview = true
        }
        .fullScreenCover(isPresented: $showSharePreview) {
            if let capturedShareImage {
                GardenSharePreviewView(
                    image: capturedShareImage,
                    onRetake: {
                        showSharePreview = false
                        self.capturedShareImage = nil
                    },
                    onShare: {
                        showShareSheet = true
                    }
                )
            }
        }
        .onAppear {
            if mode == .reopen, let id = existingGardenId {
                // Issue: local-only AR data is wiped on app reinstall — the
                // garden card still shows because the backend keeps the plant
                // list, but we can't relocalize or morph without the WorldMap
                // + scene JSON. Bail out early with a clear message rather
                // than spinning forever on the scanning overlay.
                let mapURL = GardenLocalStore.worldMapURL(for: id)
                let sceneURL = GardenLocalStore.sceneURL(for: id)
                let mapMissing = !FileManager.default.fileExists(atPath: mapURL.path)
                let sceneMissing = !FileManager.default.fileExists(atPath: sceneURL.path)
                if mapMissing && sceneMissing {
                    AppLog.gardenLoad.notice("""
                        garden=\(id, privacy: .public) unavailable — \
                        local AR data missing (likely app reinstall)
                        """)
                    gardenUnavailable = true
                    return
                }
                isRelocating = true
                relocationPhase = .scanning
                NotificationCenter.default.post(name: .gardenARLoadOldData, object: id)
            }
            if selectedPlantForPlacement == nil {
                selectedPlantForPlacement = selectedPlants.first
                if let first = selectedPlants.first {
                    Task {
                        isDownloadingModel = true
                        do {
                            let url = try await first.getModelURL(forceDownload: false)
                            downloadedModelURL = url
                        } catch {
                            downloadedModelURL = first.bundleModelURL
                        }
                        isDownloadingModel = false
                    }
                }
            }
        }
    }

    // MARK: - Composants UI

    private var gardenUnavailableView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "icloud.slash")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Jardin indisponible")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Ce jardin a été créé sur un autre appareil ou avant une réinstallation. Les données AR (carte de l'environnement et placement des plantes) ne sont stockées que localement et ont été supprimées.\n\nRecréez le jardin pour pouvoir le visualiser à nouveau.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Spacer()
                Button { dismiss() } label: {
                    Text("Retour")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 13)
                                .fill(.white.opacity(0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13)
                                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                                )
                        )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    /// True whenever the topBar should show ONLY the back button — i.e.,
    /// during any phase that already provides its own contextual actions
    /// (relocalization coaching, manual-replacement phases). Avoids the
    /// classic confusion of a generic "Validate" checkmark sitting next to
    /// a phase-specific "Confirmer le placement" button.
    private var topBarShouldShowOnlyBack: Bool {
        if isRelocating { return true }
        switch relocationPhase {
        case .tracingBoundary, .morphingPreview, .adjusting, .completed:
            return true
        case .scanning:
            return false
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left").modifier(GlassButtonStyle())
            }
            Spacer()

            if !topBarShouldShowOnlyBack {
                HStack(spacing: 20) {
                    Button { NotificationCenter.default.post(name: .gardenARUndo, object: nil) } label: {
                        Image(systemName: "arrow.uturn.backward").modifier(GlassButtonStyle())
                    }
                    Button { NotificationCenter.default.post(name: .gardenARRedo, object: nil) } label: {
                        Image(systemName: "arrow.uturn.forward").modifier(GlassButtonStyle())
                    }
                }
            }

            Spacer()

            if !topBarShouldShowOnlyBack {
                Button {
                    NotificationCenter.default.post(name: .gardenARValidate, object: nil)
                } label: {
                    Image(systemName: "checkmark").modifier(GlassButtonStyle(isGreen: true))
                }
                .disabled(isSaving)
                .opacity(isSaving ? 0.5 : 1)
            } else {
                // Keep the trailing slot at the same width so the back button
                // stays visually anchored on the left, no bar reflow.
                Color.clear.frame(width: 44, height: 44)
            }
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

            Button { captureGardenSharePhoto() } label: {
                ZStack {
                    Circle().fill(.black.opacity(0.62))
                        .frame(width: 58, height: 58)
                        .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))

                    if isCapturingSharePhoto {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .disabled(isCapturingSharePhoto)
            .accessibilityLabel("Prendre une photo du jardin")

            Spacer(minLength: 26)

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

    private func captureGardenSharePhoto() {
        capturedShareImage = nil
        isCapturingSharePhoto = true
        shouldCaptureSharePhoto = true
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

    // MARK: - 💡 Lux Widget

    private var luxWidget: some View {
        let luxLabel: String
        let luxColor: Color
        let luxIcon: String

        if currentLux > 1000 {
            luxLabel = "Soleil direct"
            luxColor = .orange
            luxIcon = "sun.max.fill"
        } else if currentLux > 300 {
            luxLabel = "Lumière vive"
            luxColor = .yellow
            luxIcon = "sun.min.fill"
        } else if currentLux > 50 {
            luxLabel = "Lumière diffuse"
            luxColor = .green
            luxIcon = "cloud.sun.fill"
        } else {
            luxLabel = "Faible luminosité"
            luxColor = .blue
            luxIcon = "moon.fill"
        }

        return HStack(spacing: 8) {
            Image(systemName: luxIcon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(luxColor)

            Text("\(currentLux) lux")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.numericText(value: Double(currentLux)))

            Text("·")
                .foregroundColor(.white.opacity(0.4))

            Text(luxLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .animation(.easeInOut(duration: 0.3), value: currentLux)
    }

    // MARK: - 🤖 Auto-Placement Overlay

    private var autoPlacingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.3)

                Text("Placement des plantes…")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text("L'IA place vos \(selectedPlants.count) plantes")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 20)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
    }

    private func autoPlaceToastView(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(hex: "#2BEE79"))

            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.black.opacity(0.7))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(hex: "#2BEE79").opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 10)
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

    // Manual replacement state (Issue #111)
    @Binding var relocationPhase: RelocationPhase
    @Binding var newBoundaryPoints: [SIMD3<Float>]
    @Binding var newBoundaryArea: Float
    @Binding var distortionWarnings: [DistortionWarning]

    // 🤖 AI Auto-placement bindings
    @Binding var isAutoPlacing: Bool
    @Binding var autoPlaceToast: String?
    @Binding var currentLux: Int
    @Binding var shouldCaptureSharePhoto: Bool
    @Binding var capturedShareImage: UIImage?
    @Binding var isCapturingSharePhoto: Bool
    let plantsToAutoPlace: [Plant]

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
        config.environmentTexturing = ARQuality.recommended.environmentTexturing
        
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // Load WorldMap on a background thread so main thread is not blocked.
        // Once loaded, restart the session with the world map as initialWorldMap.
        // For mode .create with measurement: load measurementWorldMapId.
        // For mode .reopen: load the saved garden's own WorldMap.
        // We load it here (rather than later in loadGardenFromDisk) so that the
        // session's relocalization runs ONCE; then we wait for it to fully
        // complete (camera.trackingState == .normal) before adding plant
        // ARAnchors. Adding anchors mid-relocalization locks them to the wrong
        // real-world location and produces 90°/180° garden rotations.
        let worldMapToLoad: String? = {
            if let measurement = measurementWorldMapId { return measurement }
            if mode == .reopen, let gardenId = existingGardenId { return gardenId }
            return nil
        }()
        if let mapId = worldMapToLoad {
            let mapURL = GardenLocalStore.worldMapURL(for: mapId)
            DispatchQueue.global(qos: .userInitiated).async {
                guard FileManager.default.fileExists(atPath: mapURL.path),
                      let mapData = try? Data(contentsOf: mapURL),
                      let worldMap = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: mapData)
                else {
                    AppLog.gardenLoad.notice("WorldMap missing or unreadable id=\(mapId, privacy: .public)")
                    return
                }
                DispatchQueue.main.async {
                    let restartConfig = ARWorldTrackingConfiguration()
                    restartConfig.planeDetection = [.horizontal]
                    restartConfig.environmentTexturing = ARQuality.recommended.environmentTexturing
                    restartConfig.initialWorldMap = worldMap
                    sceneView.session.run(restartConfig, options: [.resetTracking, .removeExistingAnchors])
                    AppLog.gardenLoad.notice("WorldMap loaded id=\(mapId, privacy: .public)")
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
            context.coordinator.pendingRestoreGardenId = id
        }
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.updateCachedBounds()

        if shouldCaptureSharePhoto {
            DispatchQueue.main.async {
                let rawSnapshot = uiView.snapshot()
                let brandedSnapshot = GardenARShareComposer.compose(
                    snapshot: rawSnapshot,
                    gardenName: gardenName
                )
                capturedShareImage = brandedSnapshot
                isCapturingSharePhoto = false
                shouldCaptureSharePhoto = false
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// SwiftUI calls this when the view goes away. We pause the AR session
    /// (silences "ARSession is being deallocated without being paused"
    /// warnings) and detach the delegates so any in-flight callbacks don't
    /// reach a half-torn-down coordinator. Selector-based notification
    /// observers are NOT auto-removed by Foundation, so we drop them too
    /// to avoid leaks across repeated open/close cycles.
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        AppLog.arSession.notice("dismantle — pausing session, removing observers")
        uiView.session.pause()
        uiView.session.delegate = nil
        uiView.delegate = nil
        coordinator.cancelPendingRestore()
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.arView = nil
    }

    // MARK: - Coordinator
        final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate, UIGestureRecognizerDelegate {
            var parentProps: GardenARPlacementContainerView?
            weak var arView: ARSCNView?
            
            private var reticleNode: SCNNode?
            private var lastReticleTransform: simd_float4x4?
            // Quality of the surface under the reticle. Drives color feedback
            // and decides whether boundary taps are accepted reliably.
            private enum ReticleQuality { case none, estimated, geometry }
            private var reticleQuality: ReticleQuality = .none
            // Rate-limit "no surface" warnings during boundary tracing.
            private var lastNoSurfaceWarnAt: TimeInterval = 0
            private var selectedNode: SCNNode?
            private var isRestoring = false

            private var undoStack: [[PersistedPlant]] = []
            private var redoStack: [[PersistedPlant]] = []
            // Cached on main thread to avoid UIKit access from SceneKit render queue
            private var cachedViewCenter: CGPoint = .zero
            // Tracks upAxis per planted plant ID for capture/restore
            private var plantUpAxisMap: [String: String] = [:]
            // Garden ID pending restore after WorldMap relocalization
            var pendingRestoreGardenId: String?

            // Issue #113 — ARAnchor-based placement.
            // anchor.identifier (UUID, unique per placement) → its ARAnchor.
            // Keyed by UUID and not by plantId because the user can place multiple
            // instances of the same catalog plant.
            private var plantAnchorMap: [UUID: ARAnchor] = [:]
            // anchor.identifier → pending visual to attach when ARKit creates the anchor's node.
            private var anchorPendingPlacements: [UUID: PendingPlantPlacement] = [:]
            // anchor.identifier → world transform set by the most recent drag /
            // tap-teleport. captureCurrentState reads this in priority over
            // anchor.transform so saves persist the user's final position even
            // if rebaseAnchorAtCurrentPosition fails silently (e.g. when the
            // model URL can't be resolved from the node name).
            private var pendingDragTransform: [UUID: simd_float4x4] = [:]

            struct PendingPlantPlacement {
                let modelURL: URL
                let plantId: String
                let plantName: String
                let finalScale: SCNVector3?
                let modelURLString: String?
                let upAxis: String?
                let allowRetry: Bool
                let isRestore: Bool   // captured at queue-time (placeObject's isRestoring may flip async)
                let surfaceType: String?
                let surfaceHeight: Float?
                let instanceId: UUID  // anchor.identifier — used so the loaded node can find its anchor
                let autoSelect: Bool  // false for batch placements (AI auto-place) to avoid orange-halo flicker
            }

            // 🤖 AI Auto-placement
            private var didAutoPlace = false
            private var stablePlaneFrameCount = 0
            private let stablePlaneThreshold = 15  // ~0.5s at 30fps before auto-placing

            init(_ parent: GardenARPlacementContainerView) { self.parentProps = parent }

            private func dumpNodeTree(_ node: SCNNode, indent: String = "") {
                let name = node.name ?? "<no name>"
                let geo = (node.geometry != nil) ? " (geo)" : ""
                print("\(indent)- \(name)\(geo)")
                node.childNodes.forEach { dumpNodeTree($0, indent: indent + "  ") }
            }

            func currentPlantCount() -> Int {
                guard let arView else { return 0 }
                return arView.scene.rootNode.childNodes.reduce(0) { total, rootChild in
                    if rootChild.name?.starts(with: "plant_") == true {
                        return total + 1
                    }

                    return total + rootChild.childNodes.filter {
                        $0.name?.starts(with: "plant_") == true
                    }.count
                }
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
                // Manual replacement observers (Issue #111)
                nc.addObserver(self, selector: #selector(handleEnterManualReplacement), name: .gardenAREnterManualReplacement, object: nil)
                nc.addObserver(self, selector: #selector(handleCancelManualReplacement), name: .gardenARCancelManualReplacement, object: nil)
                nc.addObserver(self, selector: #selector(handleBoundaryUndoLast), name: .gardenARBoundaryUndoLast, object: nil)
                nc.addObserver(self, selector: #selector(handleValidateNewBoundary), name: .gardenARValidateNewBoundary, object: nil)
                nc.addObserver(self, selector: #selector(handleConfirmMorphedPlacement), name: .gardenARConfirmMorphedPlacement, object: nil)
                nc.addObserver(self, selector: #selector(handleRevertToMorphed), name: .gardenARRevertToMorphed, object: nil)
                nc.addObserver(self, selector: #selector(handleLoadOldData(_:)), name: .gardenARLoadOldData, object: nil)
            }

            @objc func handleLoadOldData(_ note: Notification) {
                guard let id = note.object as? String else { return }
                loadOldGardenData(gardenId: id)
            }
            
            func setupReticle() {
                let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.08, pipeRadius: 0.005))
                ring.geometry?.firstMaterial?.diffuse.contents = UIColor(hex: "#2BEE79")
                ring.opacity = 0
                reticleNode = ring
                arView?.scene.rootNode.addChildNode(ring)
            }

            // MARK: - WorldMap relocalization tracking
            private var didRestoreGarden = false

            // Throttle session-state logs (called ~60 Hz). We keep last seen
            // values and only emit a `notice` line when something changes.
            private var lastLoggedMapStatus: ARFrame.WorldMappingStatus = .notAvailable
            private var lastLoggedTrackingState: String = ""

            // Debounce restore until ARKit's plane detection has settled.
            // After relocalization completes, ARKit keeps adding/refining
            // planes for a few hundred ms. If we restore too early, plants
            // sitting on a desk snap to the floor (or to a half-detected plane)
            // because `restoreScene`'s nearest-plane lookup runs before the
            // correct plane exists.
            //
            // Pattern: when relocalization completes, schedule restore after
            // `restoreDebounceDelay`. Each new ARPlaneAnchor that arrives
            // BEFORE we fire pushes the deadline back (planes are still being
            // discovered). A `restoreMaxWait` failsafe guarantees we
            // eventually fire even if planes never stop arriving (rare but
            // possible on cluttered scenes).
            private var restoreScheduled = false
            private var restoreDebounceWorkItem: DispatchWorkItem?
            private var restoreMaxWaitWorkItem: DispatchWorkItem?
            private let restoreDebounceDelay: TimeInterval = 1.5
            private let restoreMaxWait: TimeInterval = 4.0

            func session(_ session: ARSession, didUpdate frame: ARFrame) {
                let mapStatus = frame.worldMappingStatus
                let trackingState = frame.camera.trackingState

                // mapStatus oscillates rapidly (mapped ↔ extending) during
                // normal use — log at .debug to avoid spamming Console.
                if mapStatus != lastLoggedMapStatus {
                    AppLog.arSession.debug("""
                        mapStatus \(self.lastLoggedMapStatus.logDescription, privacy: .public) \
                        → \(mapStatus.logDescription, privacy: .public)
                        """)
                    lastLoggedMapStatus = mapStatus
                }
                // trackingState transitions are rarer and load-bearing
                // (relocalization completion) — keep at .notice.
                let trackingDesc = trackingState.logDescription
                if trackingDesc != lastLoggedTrackingState {
                    AppLog.arSession.notice("""
                        trackingState \(self.lastLoggedTrackingState, privacy: .public) \
                        → \(trackingDesc, privacy: .public)
                        """)
                    lastLoggedTrackingState = trackingDesc
                }

                guard let gardenId = pendingRestoreGardenId, !didRestoreGarden else { return }
                // If the user already took manual control, ignore relocalization events.
                if let phase = parentProps?.relocationPhase, phase.isManualReplacement { return }

                // Wait for FULL relocalization completion before placing plant
                // anchors (Issue #113). Two signals must be true together:
                //  - worldMappingStatus is .mapped or .extending (env understood)
                //  - camera.trackingState is .normal (relocalization finished —
                //    not still in .limited(.relocalizing))
                // Adding ARAnchors while still relocalizing locks them to the
                // wrong real-world location, which manifests as the whole
                // garden being rotated 90° or 180° once relocalization settles.
                let mapStatusOK = mapStatus == .mapped || mapStatus == .extending
                let trackingNormal: Bool = {
                    if case .normal = trackingState { return true }
                    return false
                }()
                guard mapStatusOK, trackingNormal else { return }

                if !restoreScheduled {
                    restoreScheduled = true
                    let timing = String(format: "debounce %.1fs, maxWait %.1fs",
                                        restoreDebounceDelay, restoreMaxWait)
                    AppLog.arSession.notice("""
                        relocalized garden=\(gardenId, privacy: .public) \
                        map=\(mapStatus.logDescription, privacy: .public) \
                        tracking=\(trackingDesc, privacy: .public) — \
                        scheduling restore (\(timing, privacy: .public))
                        """)
                    scheduleRestore(gardenId: gardenId)
                }
            }

            /// Schedules the deferred restore: a debounced primary timer (reset
            /// every time a new ARPlaneAnchor arrives) plus a max-wait failsafe.
            /// Both fire `executePendingRestore`; whichever runs first cancels
            /// the other.
            private func scheduleRestore(gardenId: String) {
                // Cancel any prior schedule (defensive — caller already gates
                // on `restoreScheduled`, but never trust the call site).
                restoreDebounceWorkItem?.cancel()
                restoreMaxWaitWorkItem?.cancel()

                let debounce = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    AppLog.arSession.notice("restore fired (debounce settled) garden=\(gardenId, privacy: .public)")
                    self.executePendingRestore(gardenId: gardenId)
                }
                let maxWait = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    AppLog.arSession.notice("restore fired (max-wait reached) garden=\(gardenId, privacy: .public)")
                    self.executePendingRestore(gardenId: gardenId)
                }
                restoreDebounceWorkItem = debounce
                restoreMaxWaitWorkItem = maxWait
                DispatchQueue.main.asyncAfter(deadline: .now() + restoreDebounceDelay, execute: debounce)
                DispatchQueue.main.asyncAfter(deadline: .now() + restoreMaxWait, execute: maxWait)
            }

            /// Called when a new plane is discovered while restore is pending —
            /// extends the debounce window so we wait for the scene to settle.
            private func bumpRestoreDebounce() {
                guard restoreScheduled, !didRestoreGarden,
                      let gardenId = pendingRestoreGardenId else { return }
                restoreDebounceWorkItem?.cancel()
                let debounce = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    AppLog.arSession.notice("restore fired (debounce settled after plane bump) garden=\(gardenId, privacy: .public)")
                    self.executePendingRestore(gardenId: gardenId)
                }
                restoreDebounceWorkItem = debounce
                DispatchQueue.main.asyncAfter(deadline: .now() + restoreDebounceDelay, execute: debounce)
            }

            private func executePendingRestore(gardenId: String) {
                guard !didRestoreGarden else { return }
                restoreDebounceWorkItem?.cancel()
                restoreMaxWaitWorkItem?.cancel()
                restoreDebounceWorkItem = nil
                restoreMaxWaitWorkItem = nil
                didRestoreGarden = true
                pendingRestoreGardenId = nil
                DispatchQueue.main.async {
                    self.parentProps?.isRelocating = false
                }
                loadGardenFromDisk(gardenId: gardenId)
            }

            /// Cancels any pending restore work — used by manual replacement
            /// and by dismantle.
            func cancelPendingRestore() {
                restoreDebounceWorkItem?.cancel()
                restoreMaxWaitWorkItem?.cancel()
                restoreDebounceWorkItem = nil
                restoreMaxWaitWorkItem = nil
                restoreScheduled = false
            }

            func updateCachedBounds() {
                guard let arView = arView else { return }
                cachedViewCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            }

            func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
                guard let arView = arView, let reticle = reticleNode else { return }

                // 💡 Update Lux from ARKit light estimation
                if let lightEstimate = arView.session.currentFrame?.lightEstimate {
                    let lux = Int(lightEstimate.ambientIntensity)
                    DispatchQueue.main.async { [weak self] in
                        withAnimation(.linear(duration: 0.2)) {
                            self?.parentProps?.currentLux = lux
                        }
                    }
                }

                let center = cachedViewCenter

                // Two-tier raycast: prefer a real detected plane (.existingPlaneGeometry,
                // surveyed surface — reliable). Fall back to .estimatedPlane (ARKit
                // guesses a plausible plane from feature points — less precise but
                // usable in low-light or poorly-textured scenes). Both keep the
                // reticle interactive; only the color changes.
                var newQuality: ReticleQuality = .none
                var newTransform: simd_float4x4?

                if let q = arView.raycastQuery(from: center, allowing: .existingPlaneGeometry, alignment: .horizontal),
                   let r = arView.session.raycast(q).first {
                    newQuality = .geometry
                    newTransform = r.worldTransform
                } else if let q = arView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .horizontal),
                          let r = arView.session.raycast(q).first {
                    newQuality = .estimated
                    newTransform = r.worldTransform
                }

                lastReticleTransform = newTransform
                if let t = newTransform {
                    reticle.simdTransform = t
                    reticle.opacity = (newQuality == .geometry) ? 1.0 : 0.6

                    // 🤖 AI Auto-placement: wait for stable plane detection AND
                    // require the user to be pointing close to the actual floor
                    // (cf issue #169). Without this gate the AI batch lands on
                    // whatever the reticle happens to hit when stability is
                    // reached — typically a desk if the user holds the phone
                    // naturally. We accept ±20 cm of reticle slack around the
                    // detected floor; if the user points at a piece of
                    // furniture, nothing fires and the user lowers the phone.
                    let reticleNearFloor: Bool = {
                        guard let floorY = self.detectedFloorY() else { return false }
                        return abs(t.columns.3.y - floorY) <= 0.20
                    }()
                    if !didAutoPlace,
                       newQuality == .geometry,
                       let props = parentProps,
                       props.mode == .create,
                       !props.plantsToAutoPlace.isEmpty,
                       reticleNearFloor {
                        stablePlaneFrameCount += 1
                        if stablePlaneFrameCount >= stablePlaneThreshold {
                            didAutoPlace = true
                            let transform = t
                            DispatchQueue.main.async { [weak self] in
                                self?.autoPlaceAIPlants(at: transform)
                            }
                        }
                    } else if !didAutoPlace {
                        // Lost floor proximity (user tilted up) — reset counter
                        // so the next "valid" pointing has to re-accumulate
                        // stability. Avoids triggering on a brief floor hit.
                        if let props = parentProps,
                           props.mode == .create,
                           !props.plantsToAutoPlace.isEmpty,
                           !reticleNearFloor {
                            stablePlaneFrameCount = 0
                        }
                    }

                    // Update color only on transition (avoid per-frame material churn).
                    if newQuality != reticleQuality {
                        reticleQuality = newQuality
                        let color: UIColor
                        switch newQuality {
                        case .geometry:  color = UIColor(hex: "#2BEE79")  // green: solid surface
                        case .estimated: color = UIColor(hex: "#FFB020")  // amber: approximate
                        case .none:      color = UIColor(hex: "#2BEE79")  // hidden anyway
                        }
                        reticle.geometry?.firstMaterial?.diffuse.contents = color
                    }
                } else {
                    reticle.opacity = 0
                    // Reset stability counter if we lose the plane
                    if !didAutoPlace { stablePlaneFrameCount = 0 }
                }
            }

            // MARK: - 🤖 AI Auto-Placement

            /// Automatically places all AI-selected plants in a style-aware layout.
            private func autoPlaceAIPlants(at centerTransform: simd_float4x4) {
                guard let props = parentProps else { return }
                let plants = props.plantsToAutoPlace.filter { $0.modelURL != nil && !($0.modelURL?.isEmpty ?? true) }
                guard !plants.isEmpty else { return }

                props.isAutoPlacing = true
                let style = props.wizard.style.lowercased()
                let count = plants.count

                // Calculate positions based on style
                let positions = calculateLayoutPositions(count: count, style: style)

                // Extract center position from transform. The Y is overridden by
                // the detected floor when available (cf issue #169) — the
                // reticle is only used for the XZ origin of the layout.
                let centerX = centerTransform.columns.3.x
                let centerZ = centerTransform.columns.3.z

                Task { [weak self] in
                    guard let self = self else { return }

                    // Download all models in parallel
                    var downloadedModels: [(plant: Plant, url: URL, offset: SIMD2<Float>)] = []

                    await withTaskGroup(of: (Plant, URL?, SIMD2<Float>)?.self) { group in
                        for (index, plant) in plants.enumerated() {
                            let offset = index < positions.count ? positions[index] : SIMD2<Float>(0, 0)
                            group.addTask {
                                do {
                                    let url = try await plant.getModelURL(forceDownload: false)
                                    return (plant, url, offset)
                                } catch {
                                    // Try bundle fallback
                                    return (plant, plant.bundleModelURL, offset)
                                }
                            }
                        }

                        for await result in group {
                            if let result = result, let url = result.1 {
                                downloadedModels.append((plant: result.0, url: url, offset: result.2))
                            }
                        }
                    }

                    // Place all models on main thread
                    await MainActor.run {
                        self.saveStateForUndo()

                        // Floor Y is re-fetched here (not snapshotted at trigger
                        // time) so that any plane discovered during the model
                        // download still benefits the placement. Fallback to
                        // the reticle Y only in the unlikely case the floor
                        // anchor was removed between trigger and execute.
                        let placementY: Float = self.detectedFloorY() ?? centerTransform.columns.3.y

                        for item in downloadedModels {
                            var transform = centerTransform
                            transform.columns.3.x = centerX + item.offset.x
                            transform.columns.3.y = placementY
                            transform.columns.3.z = centerZ + item.offset.y

                            if let axis = item.plant.upAxis {
                                self.plantUpAxisMap[item.plant.id] = axis
                            }

                            self.placeObject(
                                at: transform,
                                modelURL: item.url,
                                id: item.plant.id,
                                name: item.plant.name,
                                modelURLString: item.plant.modelURL,
                                upAxis: item.plant.upAxis,
                                autoSelect: false   // batch — no halo flicker
                            )
                        }

                        // No deselectAll needed — autoSelect:false kept all
                        // plants unselected to begin with.

                        props.isAutoPlacing = false
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            props.autoPlaceToast = "\(downloadedModels.count) plantes placées — Déplacez-les !"
                        }

                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }

            /// Calculate layout positions based on garden style.
            /// Returns array of (x, z) offsets from center.
            private func calculateLayoutPositions(count: Int, style: String) -> [SIMD2<Float>] {
                guard count > 0 else { return [] }
                if count == 1 { return [SIMD2<Float>(0, 0)] }

                let spacing: Float = 0.7 // meters between plants (enough for 3D model width)

                // Zen / Japanese → asymmetric triangle-based
                if style.contains("zen") || style.contains("japonais") {
                    return calculateZenLayout(count: count, spacing: spacing)
                }

                // Modern → grid
                if style.contains("moderne") || style.contains("minimaliste") {
                    return calculateGridLayout(count: count, spacing: spacing)
                }

                // Wild / Champêtre → randomized with noise
                if style.contains("champêtre") || style.contains("sauvage") {
                    return calculateWildLayout(count: count, spacing: spacing)
                }

                // Default (fleuri, méditerranéen, etc.) → circle
                return calculateCircleLayout(count: count, spacing: spacing)
            }

            private func calculateCircleLayout(count: Int, spacing: Float) -> [SIMD2<Float>] {
                let radius = spacing * Float(count) / (2.0 * .pi)
                let effectiveRadius = max(radius, 0.5) // Min 50cm radius
                return (0..<count).map { i in
                    let angle = (2.0 * .pi * Float(i)) / Float(count)
                    return SIMD2<Float>(
                        cos(angle) * effectiveRadius,
                        sin(angle) * effectiveRadius
                    )
                }
            }

            private func calculateGridLayout(count: Int, spacing: Float) -> [SIMD2<Float>] {
                let cols = Int(ceil(sqrt(Double(count))))
                let totalWidth = Float(cols - 1) * spacing
                return (0..<count).map { i in
                    let row = i / cols
                    let col = i % cols
                    return SIMD2<Float>(
                        Float(col) * spacing - totalWidth / 2,
                        Float(row) * spacing - totalWidth / 2
                    )
                }
            }

            private func calculateZenLayout(count: Int, spacing: Float) -> [SIMD2<Float>] {
                // Asymmetric: first plant center, others in organic triangle offsets
                var positions: [SIMD2<Float>] = [SIMD2<Float>(0, 0)]
                let offsets: [SIMD2<Float>] = [
                    SIMD2<Float>(-0.6, 0.5),
                    SIMD2<Float>(0.7, 0.3),
                    SIMD2<Float>(-0.3, -0.7),
                    SIMD2<Float>(0.5, -0.4),
                    SIMD2<Float>(-0.8, -0.2),
                    SIMD2<Float>(0.2, 0.8),
                ]
                for i in 1..<count {
                    let idx = (i - 1) % offsets.count
                    let scale = 1.0 + Float(i / offsets.count) * 0.5
                    positions.append(offsets[idx] * scale)
                }
                return positions
            }

            private func calculateWildLayout(count: Int, spacing: Float) -> [SIMD2<Float>] {
                // Circle base with random noise
                let base = calculateCircleLayout(count: count, spacing: spacing)
                return base.map { pos in
                    let noiseX = Float.random(in: -0.2...0.2)
                    let noiseZ = Float.random(in: -0.2...0.2)
                    return SIMD2<Float>(pos.x + noiseX, pos.y + noiseZ)
                }
            }
            
            /// Returns the Y of the largest detected horizontal plane (the floor).
            /// Falls back to nil if no horizontal planes are detected yet.
            /// Used to classify a plant as `floor` vs `elevated` independently
            /// of the session's Y=0 origin (which depends on where the user
            /// held the phone at session start, not on the actual floor).
            @MainActor
            private func detectedFloorY() -> Float? {
                guard let frame = arView?.session.currentFrame else { return nil }
                let horizontals = frame.anchors.compactMap { $0 as? ARPlaneAnchor }
                    .filter { $0.alignment == .horizontal }
                guard !horizontals.isEmpty else { return nil }
                // The floor is the LOWEST horizontal plane large enough to be a
                // plausible floor (≥ 0.5 m²). The previous heuristic of "largest
                // plane wins" failed in rooms where a desk, bed or sofa top
                // happened to be bigger than the partially-detected floor —
                // causing the whole garden to snap onto the furniture at
                // restore time (cf issue #168). If no plane meets the area
                // threshold, fall back to the lowest among all horizontals so
                // that early-session restores still get a usable reference.
                let minFloorArea: Float = 0.5  // m²
                let candidates = horizontals.filter {
                    $0.planeExtent.width * $0.planeExtent.height >= minFloorArea
                }
                let pool = candidates.isEmpty ? horizontals : candidates
                let lowest = pool.min(by: {
                    $0.transform.columns.3.y < $1.transform.columns.3.y
                })
                return lowest?.transform.columns.3.y
            }

            // MARK: - Capture Précise (Crucial pour la Map 2D)
            private func captureCurrentState() -> [PersistedPlant] {
                guard let arView = arView else { return [] }
                // Plants are now children of anchor nodes (Issue #113), so we
                // walk one level deeper. Older flows that still attach plants
                // to rootNode directly are also covered.
                let plantNodes: [SCNNode] = arView.scene.rootNode.childNodes.flatMap { rootChild -> [SCNNode] in
                    if rootChild.name?.starts(with: "plant_") == true {
                        return [rootChild]
                    }
                    return rootChild.childNodes.filter { $0.name?.starts(with: "plant_") == true }
                }
                // Cache the floor Y once per capture for elevation classification.
                let floorY = detectedFloorY()

                return plantNodes.map { node -> PersistedPlant in
                    // Identity now lives on the node via KVC (audit item 7).
                    // Legacy fallback: parse the old name format if KVC is empty.
                    let plantId = self.plantId(of: node)
                    let plantNameValue = self.plantName(of: node) ?? "Plante"
                    let modelFileName: String = {
                        if let raw = node.arboreModelURLString { return raw }
                        let parts = node.name?.components(separatedBy: "_") ?? []
                        let rawURLString = (parts[safe: 3] ?? "").removingPercentEncoding ?? ""
                        if let url = URL(string: rawURLString) {
                            return url.lastPathComponent
                        }
                        return (rawURLString as NSString).lastPathComponent
                    }()

                    // Issue #113 — Save the ANCHOR's transform, not
                    // node.simdWorldTransform.
                    //
                    // simdWorldTransform of the container reflects the geometry
                    // ORIGIN position (with the pivot offset baked in), which
                    // is *not* the visual base. If we save it and use it as the
                    // new anchor.transform on restore, we accumulate the pivot
                    // offset on every save→restore cycle (the plant climbs
                    // higher and higher). Saving anchor.transform is invariant.
                    let anchorTransform: simd_float4x4
                    if let uuid = self.instanceId(of: node) {
                        if let override = pendingDragTransform[uuid] {
                            // The user dragged or tap-teleported this plant.
                            // Trust the override — it's the visual position they
                            // last saw, regardless of whether the underlying
                            // anchor was rebased successfully (Issue #111).
                            anchorTransform = override
                        } else if let anchor = plantAnchorMap[uuid] {
                            anchorTransform = anchor.transform
                        } else {
                            anchorTransform = stripScale(from: node.simdWorldTransform)
                        }
                    } else {
                        // Legacy node attached directly to rootNode (older saves
                        // before the ARAnchor migration). Fall back to its world
                        // transform with scale stripped.
                        anchorTransform = stripScale(from: node.simdWorldTransform)
                    }

                    let worldPos = SIMD3<Float>(anchorTransform.columns.3.x,
                                                anchorTransform.columns.3.y,
                                                anchorTransform.columns.3.z)
                    let worldEuler = node.eulerAngles
                    let worldScale = SIMD3<Float>(node.scale.x, node.scale.y, node.scale.z)

                    // Surface detection (Issue #113) — RELATIVE to the detected
                    // floor plane, not to the session's Y=0 origin (which can
                    // be anywhere depending on where the user held the phone
                    // at session start). A plant > 10cm above floor = elevated.
                    let surfaceType: String
                    if let floorY = floorY {
                        surfaceType = (worldPos.y - floorY) > Self.elevationThresholdMeters ? "elevated" : "floor"
                    } else {
                        // No floor detected yet — default to `floor`. The
                        // previous fallback `worldPos.y > threshold` assumed
                        // Y=0 was the floor, which is wrong: Y=0 is the
                        // device pose at session start, and a phone held at
                        // chest height puts the real floor at ~Y=-1.5 m,
                        // mis-classifying every plant as `elevated` (cf
                        // issue #168). A `floor` mis-classification is safer:
                        // it falls back to re-snapping at next restore once a
                        // floor plane is detected, while an `elevated` one
                        // freezes a stale `surfaceHeight` reference.
                        surfaceType = "floor"
                    }
                    let surfaceHeight: Float = worldPos.y

                    // captureCurrentState is invoked on every undo snapshot and
                    // by every gesture — it can fire dozens of times per
                    // second during a scale animation. Keep these at .debug
                    // so notice-level logs stay readable.
                    AppLog.gardenSave.debug("""
                        capture plant=\(plantNameValue, privacy: .public) \
                        id=\(plantId, privacy: .public) \
                        anchorPos=\(worldPos.logDescription, privacy: .public) \
                        scale=\(worldScale.logDescription, privacy: .public) \
                        surface=\(surfaceType, privacy: .public) \
                        surfaceY=\(surfaceHeight, format: .fixed(precision: 3), privacy: .public)
                        """)

                    return PersistedPlant(
                        plantID: plantId,
                        plantName: plantNameValue,
                        modelURLString: modelFileName,
                        position: [worldPos.x, worldPos.y, worldPos.z],
                        rotation: [worldEuler.x, worldEuler.y, worldEuler.z],
                        scale: [worldScale.x, worldScale.y, worldScale.z],
                        transform: matrixToFloatArray(anchorTransform),
                        upAxis: plantUpAxisMap[plantId],
                        surfaceType: surfaceType,
                        surfaceHeight: surfaceHeight
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
                        AppLog.gardenSave.notice("local save tempID=\(tempID, privacy: .public) plants=\(plantsForSave.count, privacy: .public)")
                        self.saveToDisk(id: tempID, plants: plantsForSave, arView: arView)
                        
                        let placedDTOs = plantsForSave.map { p in
                            PlacedPlantDTO(plantId: p.plantID, x: Double(p.position[0]), y: Double(p.position[1]), z: Double(p.position[2]), note: p.plantName)
                        }
                        
                        Task {
                            var finalServerID: String = tempID

                            // 2. Appel API — la décision POST vs PUT repose
                            //    désormais sur la présence de `existingGardenId`,
                            //    pas sur `mode == .reopen`. Le wizard pré-crée
                            //    le jardin au step `scanMethod` et passe son id
                            //    ici, même en `mode = .create`.
                            do {
                                if let existingId = props.existingGardenId {
                                    // Mise à jour d'un jardin existant (.reopen
                                    // OU .create avec id pré-créé au tracé).
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
                                    AppLog.gardenSave.notice("api updated garden id=\(existingId, privacy: .public)")
                                } else {
                                    // Création d'un nouveau jardin — chemin
                                    // legacy quand la view est ouverte hors
                                    // wizard. Le wizard moderne fournit
                                    // toujours un `existingGardenId`.
                                    let created = try await GardenAPI.shared.createGarden(
                                        GardenCreateDTO(
                                            name: props.gardenName,
                                            wizard: props.wizard,
                                            plants: placedDTOs,
                                            thumbnailKey: props.thumbnailKey
                                        )
                                    )

                                    if let newId = created.id {
                                        finalServerID = newId
                                    }
                                    AppLog.gardenSave.notice("api created garden id=\(finalServerID, privacy: .public)")
                                }
                            } catch {
                                AppLog.gardenSave.error("api save failed — keeping local tempID error=\(String(describing: error), privacy: .public)")
                            }
                            
                            // 3. SYNCHRONISATION FICHIERS
                            // Si le serveur a changé l'ID (ex: 67 -> 68), on doit copier les fichiers
                            if finalServerID != tempID {
                                AppLog.gardenSave.notice("migrating files temp=\(tempID, privacy: .public) → server=\(finalServerID, privacy: .public)")
                                
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
                                        AppLog.gardenSave.notice("files migrated to id=\(finalServerID, privacy: .public)")

                                        // Supprimer les fichiers temporaires pour éviter les doublons
                                        try? FileManager.default.removeItem(at: oldMap)
                                        try? FileManager.default.removeItem(at: GardenLocalStore.sceneURL(for: tempID))

                                    } catch {
                                        AppLog.gardenSave.error("worldmap copy failed error=\(String(describing: error), privacy: .public)")
                                    }
                                } else {
                                    // Pas de WorldMap à migrer, supprimer quand même le JSON temp
                                    try? FileManager.default.removeItem(at: GardenLocalStore.sceneURL(for: tempID))
                                }
                            }
                            
                            DispatchQueue.main.async {
                                self.pendingDragTransform.removeAll()
                                self.removeOutlinesFromAllPlants()
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
                    // Convention #170 : tout est persisté en frame monde ARKit
                    // (cf doc en tête de GardenLocalStore.swift). Plus de
                    // normalisation par centroïde : ni les `plants` capturés
                    // depuis `captureCurrentState`, ni les `boundaryPoints`
                    // rechargés du JSON existant. Le morpher recalcule les
                    // centroïdes à la volée pour son MVC.
                    //
                    // Pré-fix : ce site soustrayait le centroïde de la
                    // boundary à `position` et `boundaryPoints` mais pas à
                    // `transform`, produisant un JSON en 2 frames incompatibles
                    // (issues #170 / #136).
                    var boundaryPointsArray: [[Float]]
                    var savedArea: Float = props.area
                    var savedPerimeter: Float = props.perimeter

                    if !props.boundaryPoints.isEmpty {
                        // Mode création : boundary fraîchement mesurée, world frame.
                        boundaryPointsArray = props.boundaryPoints.map { [$0.x, $0.y, $0.z] }
                    } else {
                        // Mode reopen : on relit la boundary existante. Migration
                        // legacy → world frame appliquée si nécessaire.
                        let existingURL = GardenLocalStore.sceneURL(for: id)
                        if let existingData = try? Data(contentsOf: existingURL),
                           let existingScene = try? JSONDecoder().decode(PersistedARScene.self, from: existingData).normalizedToWorldFrame() {
                            boundaryPointsArray = existingScene.boundaryPoints ?? []
                            savedArea = existingScene.area ?? props.area
                            savedPerimeter = existingScene.perimeter ?? props.perimeter
                            AppLog.gardenSave.debug("boundary reloaded from existing JSON points=\(boundaryPointsArray.count, privacy: .public)")
                        } else {
                            boundaryPointsArray = []
                        }
                    }

                    let sceneData = PersistedARScene(
                        savedAt: Date(),
                        plants: plants,
                        boundaryPoints: boundaryPointsArray,
                        area: savedArea,
                        perimeter: savedPerimeter
                    )
                    let jsonData = try JSONEncoder().encode(sceneData)
                    try jsonData.write(to: GardenLocalStore.sceneURL(for: id))
                    AppLog.gardenSave.notice("scene JSON written id=\(id, privacy: .public) boundary=\(boundaryPointsArray.count, privacy: .public)")
                } catch {
                    AppLog.gardenSave.error("scene JSON write failed error=\(String(describing: error), privacy: .public)")
                }
                
                // 2. WorldMap (Asynchrone via ARKit)
                arView.session.getCurrentWorldMap { worldMap, error in
                    if let map = worldMap {
                        do {
                            let mapData = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                            try mapData.write(to: GardenLocalStore.worldMapURL(for: id))
                            AppLog.gardenSave.notice("worldmap written id=\(id, privacy: .public)")
                        } catch {
                            AppLog.gardenSave.error("worldmap write failed error=\(String(describing: error), privacy: .public)")
                        }
                    }
                }
            }
            
            // MARK: - Restauration (Chargement)
            //
            // Issue #113 — IMPORTANT: by the time this runs, the session has
            // already been started with the saved WorldMap as initialWorldMap
            // (see makeUIView), and the relocalization has fully completed
            // (camera.trackingState == .normal — checked in session(_:didUpdate:)).
            // We do NOT restart the session here. Restarting after relocalization
            // would re-trigger relocalizing state, and adding plant anchors
            // mid-relocalization locks them to the wrong real-world location
            // (manifesting as 90°/180° garden rotations after settle).
            func loadGardenFromDisk(gardenId: String) {
                guard arView != nil else { return }
                AppLog.gardenLoad.notice("loading garden id=\(gardenId, privacy: .public)")

                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else { return }

                    let sceneUrl = GardenLocalStore.sceneURL(for: gardenId)
                    var persistedPlants: [PersistedPlant] = []

                    if FileManager.default.fileExists(atPath: sceneUrl.path) {
                        do {
                            let sceneJson = try Data(contentsOf: sceneUrl)
                            let sceneData = try JSONDecoder().decode(PersistedARScene.self, from: sceneJson)
                                .normalizedToWorldFrame()  // migration legacy (#170)
                            persistedPlants = sceneData.plants
                            AppLog.gardenLoad.notice("scene JSON loaded plants=\(persistedPlants.count, privacy: .public)")
                        } catch {
                            AppLog.gardenLoad.error("scene JSON unreadable error=\(String(describing: error), privacy: .public)")
                        }
                    } else {
                        AppLog.gardenLoad.notice("scene JSON missing path=\(sceneUrl.path, privacy: .public)")
                    }

                    DispatchQueue.main.async {
                        self.isRestoring = true
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

                // Nettoyage : retirer toutes les anciennes plantes (anchors + nodes legacy).
                removeAllPlantAnchors()
                arView.scene.rootNode.childNodes.forEach { node in
                    if node.name?.starts(with: "plant_") == true {
                        node.removeFromParentNode()
                    }
                }
                deselectAll()

                Task {
                    // Smart snap-to-plane (Option 1) — applies to BOTH floor and
                    // elevated plants, using the currently detected floor as a
                    // Y reference instead of the session's arbitrary Y=0 origin.
                    //
                    // Strategy:
                    //  - floor plants     → snap to current detected floor Y
                    //                       (corrects vertical relocalization drift)
                    //  - elevated plants  → snap to the closest detected plane
                    //                       within ±5cm of the saved Y (the
                    //                       furniture surface, presumably re-detected)
                    //  - if no matching plane is found → keep the saved Y
                    //    (graceful degradation; usually <5cm off)
                    let currentFloorY: Float? = await MainActor.run(body: { self.detectedFloorY() })

                    await withTaskGroup(of: Void.self) { group in
                        for p in plants {
                            guard var transform = floatArrayToMatrix(p.transform), !p.modelURLString.isEmpty else { continue }

                            let savedY = transform.columns.3.y
                            let snapTarget: Float?
                            let snapTolerance: Float

                            switch p.surfaceType {
                            case "floor":
                                // Use the freshly detected floor Y if available;
                                // accept up to 15cm drift to allow re-anchoring
                                // a plant that was on a slightly mis-detected floor
                                // last session.
                                snapTarget = currentFloorY
                                snapTolerance = 0.15
                            case "elevated":
                                // Look for a plane near the saved furniture Y.
                                snapTarget = p.surfaceHeight ?? savedY
                                snapTolerance = 0.05
                            default:
                                // Legacy data (no surfaceType saved) — keep the
                                // saved Y untouched.
                                snapTarget = nil
                                snapTolerance = 0
                            }

                            if let target = snapTarget,
                               let snappedY = await MainActor.run(body: { self.findNearestPlaneY(target: target, tolerance: snapTolerance) }) {
                                transform.columns.3.y = snappedY
                                AppLog.gardenLoad.notice("""
                                    snap plant=\(p.plantName, privacy: .public) \
                                    surface=\(p.surfaceType ?? "nil", privacy: .public) \
                                    savedY=\(savedY, format: .fixed(precision: 3), privacy: .public) \
                                    target=\(target, format: .fixed(precision: 3), privacy: .public) \
                                    snappedY=\(snappedY, format: .fixed(precision: 3), privacy: .public) \
                                    delta=\(snappedY - savedY, format: .fixed(precision: 3), privacy: .public)
                                    """)
                            } else {
                                AppLog.gardenLoad.notice("""
                                    snap plant=\(p.plantName, privacy: .public) \
                                    surface=\(p.surfaceType ?? "nil", privacy: .public) \
                                    savedY=\(savedY, format: .fixed(precision: 3), privacy: .public) \
                                    target=\(snapTarget ?? -999, format: .fixed(precision: 3), privacy: .public) \
                                    snappedY=nil (no plane within tolerance, kept savedY)
                                    """)
                            }

                            let finalScale = SCNVector3(p.scale[0], p.scale[1], p.scale[2])
                            let captured = transform
                            group.addTask {
                                do {
                                    let remoteURL = try await ModelCacheManager.shared.getModelURL(for: p.modelURLString, forceDownload: false)
                                    await MainActor.run {
                                        self.placeObject(
                                            at: captured,
                                            modelURL: remoteURL,
                                            id: p.plantID,
                                            name: p.plantName,
                                            finalScale: finalScale,
                                            modelURLString: p.modelURLString,
                                            upAxis: p.upAxis,
                                            surfaceType: p.surfaceType,
                                            surfaceHeight: p.surfaceHeight
                                        )
                                    }
                                } catch {
                                    AppLog.plants.error("model download failed url=\(p.modelURLString, privacy: .public) error=\(String(describing: error), privacy: .public)")
                                    if let fallbackURL = await MainActor.run(body: { self.resolveLocalModelURL(p.modelURLString) }) {
                                        await MainActor.run {
                                            self.placeObject(
                                                at: captured,
                                                modelURL: fallbackURL,
                                                id: p.plantID,
                                                name: p.plantName,
                                                finalScale: finalScale,
                                                modelURLString: p.modelURLString,
                                                upAxis: p.upAxis,
                                                surfaceType: p.surfaceType,
                                                surfaceHeight: p.surfaceHeight
                                            )
                                        }
                                    } else {
                                        AppLog.plants.error("model unresolvable url=\(p.modelURLString, privacy: .public)")
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

            /// Issue #113 — Finds the Y of the closest detected horizontal plane
            /// to the target height, within `tolerance` (in meters). Returns
            /// nil if no plane is close enough.
            @MainActor
            private func findNearestPlaneY(target: Float, tolerance: Float) -> Float? {
                guard let frame = arView?.session.currentFrame else { return nil }
                let allHorizontal = frame.anchors.compactMap { $0 as? ARPlaneAnchor }
                    .filter { $0.alignment == .horizontal }
                let allYs = allHorizontal.map { $0.transform.columns.3.y }
                let inRange = allYs.filter { abs($0 - target) <= tolerance }

                AppLog.gardenLoad.debug("""
                    planeScan target=\(target, format: .fixed(precision: 3), privacy: .public) \
                    tolerance=\(tolerance, format: .fixed(precision: 3), privacy: .public) \
                    nHorizontal=\(allHorizontal.count, privacy: .public) \
                    allYs=\(allYs.map { String(format: "%.3f", $0) }.joined(separator: ","), privacy: .public) \
                    inRange=\(inRange.count, privacy: .public)
                    """)

                return inRange.min(by: { abs($0 - target) < abs($1 - target) })
            }

            /// Removes every ARAnchor we tracked (so all plant nodes disappear via
            /// ARKit), and clears our id→anchor map.
            @MainActor
            private func removeAllPlantAnchors() {
                guard let arView = arView else { return }
                for anchor in plantAnchorMap.values {
                    arView.session.remove(anchor: anchor)
                }
                plantAnchorMap.removeAll()
                anchorPendingPlacements.removeAll()
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
                    AppLog.plants.debug("model resolved from bundle file=\(fileName, privacy: .public)")
                    return bundleURL
                }

                // 3. Fallback : Documents directory (fichiers téléchargés runtime)
                let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: docsURL.path) {
                    AppLog.plants.debug("model resolved from documents file=\(fileName, privacy: .public)")
                    return docsURL
                }

                AppLog.plants.error("model file not found name=\(fileName, privacy: .public)")
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
                let action = SCNAction.scale(by: 1.1, duration: 0.2)
                node.runAction(action) { [weak self] in
                    self?.refreshPivotForScale(node: node)
                }
            }

            @objc func handleScaleDownAction() {
                guard let node = selectedNode else { return }
                saveStateForUndo()
                let action = SCNAction.scale(by: 0.9, duration: 0.2)
                node.runAction(action) { [weak self] in
                    self?.refreshPivotForScale(node: node)
                }
            }

            /// Re-computes the pivot Y from the node's current scale. The pivot
            /// is set once at placement to make the visible base land at the
            /// anchor's position, but it doesn't track scale changes — which
            /// is why pinching/zooming a plant after placement made it float
            /// (or sink) by `(1 - scaleRatio) * |minY|`. Call this every time
            /// the user changes a plant's scale.
            private func refreshPivotForScale(node: SCNNode) {
                guard let origMinY = node.value(forKey: "arboreOriginalMinY") as? Float else { return }
                let pivotY = node.scale.y * origMinY
                node.pivot = SCNMatrix4MakeTranslation(0, pivotY, 0)
            }

            @objc func handleDelete() {
                guard let node = selectedNode, let arView = arView else { return }
                saveStateForUndo()
                // Issue #113 — also remove the backing ARAnchor so ARKit stops
                // tracking it (otherwise the anchor stays alive and burns CPU).
                // Lookup is by per-instance UUID (not catalog plantId) so deleting
                // one of two same-species plants targets the correct one.
                let pid = plantId(of: node)
                if let uuid = instanceId(of: node),
                   let anchor = plantAnchorMap[uuid] {
                    arView.session.remove(anchor: anchor)
                    plantAnchorMap.removeValue(forKey: uuid)
                } else {
                    // Legacy node attached directly to rootNode (older saves).
                    node.removeFromParentNode()
                }
                // Only forget the upAxis if no other instance of this plant id
                // remains in the scene — multiple Pothos plants share an axis.
                let stillHasInstances: Bool = {
                    let candidates: [SCNNode] = arView.scene.rootNode.childNodes.flatMap { rootChild -> [SCNNode] in
                        var nodes: [SCNNode] = []
                        if rootChild.name?.hasPrefix("plant_") == true { nodes.append(rootChild) }
                        nodes.append(contentsOf: rootChild.childNodes.filter { $0.name?.hasPrefix("plant_") == true })
                        return nodes
                    }
                    return candidates.contains { plantId(of: $0) == pid && $0 !== node }
                }()
                if !stillHasInstances {
                    plantUpAxisMap.removeValue(forKey: pid)
                }
                deselectAll()
            }

            @objc func handleTapToPlace(_ gesture: UITapGestureRecognizer) {
                // During manual boundary tracing, taps add boundary points (Issue #111).
                if parentProps?.relocationPhase == .tracingBoundary {
                    if let transform = lastReticleTransform {
                        // Accept both .geometry and .estimated hits — the user
                        // gets visual feedback via the reticle color (green vs.
                        // amber) so they know when the surface is approximate.
                        addBoundaryPoint(at: transform)
                    } else {
                        // Throttle this log: ARKit can drop the raycast for
                        // many tap-frames in low light, and 25 lines/session
                        // drowns out everything else.
                        let now = CACurrentMediaTime()
                        if now - lastNoSurfaceWarnAt > Self.noSurfaceWarnIntervalSeconds {
                            lastNoSurfaceWarnAt = now
                            AppLog.manualReplace.notice("boundary tap ignored — no surface under reticle")
                        }
                    }
                    return
                }

                // Block taps during morphing preview to avoid accidental placements.
                if parentProps?.relocationPhase == .morphingPreview { return }

                // Adjusting phase (Issue #111) — reticle-centric selection.
                // The user aims a plant at the screen-center reticle and taps:
                //  - reticle on a plant  → select it (orange outline)
                //  - reticle on a surface, plant already selected → teleport
                //    the selected plant to the reticle's world position
                //  - reticle on empty   → deselect
                // The tap location itself is ignored, so a slightly-off finger
                // position never fires the wrong action.
                if parentProps?.relocationPhase == .adjusting,
                   let arView = arView {
                    let center = cachedViewCenter
                    let hits = arView.hitTest(center, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
                    if let hit = hits.first(where: { isPlantNode($0.node) }) {
                        let root = findPlantRoot(hit.node)
                        if root !== selectedNode {
                            selectNode(root)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        return
                    }
                    // No plant under the reticle — teleport the selected one
                    // to the reticle's last surface raycast (lastReticleTransform).
                    if let node = selectedNode, let transform = lastReticleTransform {
                        saveStateForUndo()
                        let p = transform.columns.3
                        node.simdWorldPosition = simd_float3(p.x, p.y, p.z)
                        recordDraggedTransform(for: node)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        deselectAll()
                        return
                    }
                    deselectAll()
                    return
                }

                guard let transform = lastReticleTransform else {
                    AppLog.plants.debug("tap ignored — no surface under reticle")
                    deselectAll()
                    return
                }
                guard let plant = parentProps?.selectedPlant else {
                    AppLog.plants.debug("tap ignored — no plant selected from picker")
                    deselectAll()
                    return
                }

                // Utiliser l'URL pré-téléchargée si disponible, sinon fallback au bundle
                guard let url = parentProps?.downloadedModelURL ?? plant.bundleModelURL else {
                    AppLog.plants.error("model URL nil plant=\(plant.name, privacy: .public) modelURL=\(plant.modelURL ?? "nil", privacy: .public)")
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

                // Update the visual position only when the raycast hits a
                // surface. If it misses (finger over a textureless or non-floor
                // area), keep the last visual position — don't snap back.
                let location = gesture.location(in: arView)
                if let query = arView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal),
                   let result = arView.session.raycast(query).first {
                    let p = result.worldTransform.columns.3
                    node.simdWorldPosition = simd_float3(p.x, p.y, p.z)
                }

                // Persist final position on .ended regardless of last raycast.
                // We no longer recreate the underlying ARAnchor here — the
                // override map alone is enough for save persistence, and
                // skipping the rebase removes a whole class of races (the new
                // node didn't exist when capture ran), kills the USDZ-reload
                // cost on every drag, and preserves the .adjusting outline
                // halos (which used to disappear with the destroyed node).
                if gesture.state == .ended || gesture.state == .cancelled {
                    recordDraggedTransform(for: node)
                }
            }

            /// Records the node's current world transform as the source of
            /// truth for the next save. Called on drag-end and tap-teleport.
            /// captureCurrentState reads `pendingDragTransform[uuid]` in
            /// priority over the (now never-updated) anchor.transform.
            private func recordDraggedTransform(for node: SCNNode) {
                guard let uuid = instanceId(of: node) else { return }
                pendingDragTransform[uuid] = stripScale(from: node.simdWorldTransform)
                AppLog.plants.debug("""
                    pendingDragTransform set anchor=\(uuid.uuidString.prefix(8), privacy: .public) \
                    t=\(node.simdWorldPosition.logDescription, privacy: .public)
                    """)
            }

            /// Strips any scale from a 4x4 transform, leaving only translation
            /// and rotation. Critical for ARAnchor.transform: if the saved or
            /// captured transform has a scale baked in (legacy data, or our own
            /// post-auto-scale capture), using it as anchor.transform would
            /// double-apply the scale once the container's own scale is set.
            private func stripScale(from matrix: simd_float4x4) -> simd_float4x4 {
                var result = matrix
                let c0 = SIMD3<Float>(result.columns.0.x, result.columns.0.y, result.columns.0.z)
                let c1 = SIMD3<Float>(result.columns.1.x, result.columns.1.y, result.columns.1.z)
                let c2 = SIMD3<Float>(result.columns.2.x, result.columns.2.y, result.columns.2.z)
                let l0 = simd_length(c0); let l1 = simd_length(c1); let l2 = simd_length(c2)
                guard l0 > 1e-6, l1 > 1e-6, l2 > 1e-6 else { return matrix }
                let n0 = c0 / l0, n1 = c1 / l1, n2 = c2 / l2
                result.columns.0 = SIMD4<Float>(n0.x, n0.y, n0.z, 0)
                result.columns.1 = SIMD4<Float>(n1.x, n1.y, n1.z, 0)
                result.columns.2 = SIMD4<Float>(n2.x, n2.y, n2.z, 0)
                return result
            }

            /// Issue #113 — Plants are now anchored via `ARAnchor` so ARKit's drift
            /// correction applies to each one individually. The visual model is
            /// loaded asynchronously when ARKit creates the anchor's node
            /// (see `renderer(_:didAdd:for:)` below).
            func placeObject(
                at transform: simd_float4x4,
                modelURL: URL,
                id: String,
                name: String,
                finalScale: SCNVector3? = nil,
                modelURLString: String? = nil,
                allowRetry: Bool = true,
                upAxis: String? = nil,
                surfaceType: String? = nil,
                surfaceHeight: Float? = nil,
                autoSelect: Bool = true
            ) {
                guard let arView = arView else { return }

                if modelURL.isFileURL && !FileManager.default.fileExists(atPath: modelURL.path) {
                    AppLog.plants.error("placeObject — model file missing path=\(modelURL.path, privacy: .public)")
                    return
                }

                // Always feed a rigid (no-scale) transform to ARAnchor so the
                // container's own scale doesn't get multiplied by a baked-in scale.
                let rigidTransform = stripScale(from: transform)
                let anchor = ARAnchor(name: "plant_\(id)", transform: rigidTransform)
                anchorPendingPlacements[anchor.identifier] = PendingPlantPlacement(
                    modelURL: modelURL,
                    plantId: id,
                    plantName: name,
                    finalScale: finalScale,
                    modelURLString: modelURLString,
                    upAxis: upAxis,
                    allowRetry: allowRetry,
                    isRestore: isRestoring,
                    surfaceType: surfaceType,
                    surfaceHeight: surfaceHeight,
                    instanceId: anchor.identifier,
                    autoSelect: autoSelect
                )
                plantAnchorMap[anchor.identifier] = anchor
                arView.session.add(anchor: anchor)

                AppLog.arAnchor.notice("""
                    placeObject id=\(id, privacy: .public) \
                    anchor=\(anchor.identifier.uuidString.prefix(8), privacy: .public) \
                    isRestore=\(self.isRestoring, privacy: .public) \
                    rigid=\(rigidTransform.logDescription, privacy: .public) \
                    surface=\(surfaceType ?? "nil", privacy: .public) \
                    surfaceY=\(surfaceHeight ?? -1, format: .fixed(precision: 3), privacy: .public) \
                    finalScale=\(finalScale?.logDescription ?? "auto", privacy: .public)
                    """)
            }

            /// Loads a USDZ and attaches it as a child of an anchor's node.
            ///
            /// USDZ loading (file IO + scene parsing) happens on a background
            /// queue. Without this, complex models loaded synchronously on the
            /// main thread back-pressured ARKit's frame delivery and triggered
            /// the "delegate retaining N ARFrames" warnings in Console.
            private func instantiatePlantNode(into parentNode: SCNNode, pending: PendingPlantPlacement, anchorTransform: simd_float4x4) {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    do {
                        let scene = try SCNScene(url: pending.modelURL, options: nil)
                        DispatchQueue.main.async {
                            self?.attachLoadedPlantScene(scene, into: parentNode, pending: pending, anchorTransform: anchorTransform)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self?.handlePlantLoadFailure(error: error, pending: pending, anchorTransform: anchorTransform)
                        }
                    }
                }
            }

            /// Main-thread completion of `instantiatePlantNode` once the USDZ
            /// is loaded. Sets up the container, pivot, scale, halo cache,
            /// then attaches to the anchor's node.
            private func attachLoadedPlantScene(_ scene: SCNScene, into parentNode: SCNNode, pending: PendingPlantPlacement, anchorTransform: simd_float4x4) {
                    let container = SCNNode()
                    // Name is now just a marker for filtering — identity lives
                    // in KVC properties (audit item 7). The plantId is appended
                    // for human-readable debug logs only; never parsed.
                    container.name = "plant_\(pending.plantId)"
                    container.arborePlantId = pending.plantId
                    container.arborePlantName = pending.plantName
                    container.arboreInstanceId = pending.instanceId
                    container.arboreModelURLString = pending.modelURLString
                        ?? pending.modelURL.lastPathComponent

                    let wrapper = SCNNode()
                    for child in scene.rootNode.childNodes { wrapper.addChildNode(child) }
                    let effectiveAxis = pending.upAxis ?? plantUpAxisMap[pending.plantId]
                    if effectiveAxis?.uppercased() == "Z" {
                        wrapper.eulerAngles.x = -.pi / 2
                    }
                    container.addChildNode(wrapper)
                    stripPotIfNeeded(from: container)

                    let (minVec, maxVec) = container.boundingBox
                    let rawHeight = maxVec.y - minVec.y

                    AppLog.plants.debug("""
                        bbox plant=\(pending.plantName, privacy: .public) \
                        min=\(SCNVector3(minVec.x, minVec.y, minVec.z).logDescription, privacy: .public) \
                        max=\(SCNVector3(maxVec.x, maxVec.y, maxVec.z).logDescription, privacy: .public) \
                        rawH=\(rawHeight, format: .fixed(precision: 3), privacy: .public)
                        """)

                    // Issue #113 — pivot SCALE-CORRECTED so the visual base
                    // lands exactly at the anchor's position.
                    //
                    // Naive pivot `T(0, minY, 0)` does NOT fully compensate for
                    // node.scale: the visible base ends up at
                    //   anchor.y + (1 - scale) * |minY|
                    // For a centered model (minY = -0.695) at scale 0.36, that's
                    // 44 cm above the surface — visible "levitating" plant.
                    //
                    // Empirical SceneKit formula used for rendering:
                    //   simdWorldTransform = parent.world * pivot.inverse * transform
                    // so a pivot of `T(0, scaleFactor * minY, 0)` makes the
                    // base vertex (0, minY, 0) land exactly at anchor.t.
                    if let scale = pending.finalScale {
                        container.scale = scale
                        if rawHeight > 0 {
                            let pivotY = scale.y * minVec.y
                            container.pivot = SCNMatrix4MakeTranslation(0, pivotY, 0)
                        }
                        AppLog.plants.debug("""
                            restoreScale plant=\(pending.plantName, privacy: .public) \
                            scale=\(scale.logDescription, privacy: .public) \
                            pivotY=\(rawHeight > 0 ? scale.y * minVec.y : 0, format: .fixed(precision: 3), privacy: .public)
                            """)
                    } else if !pending.isRestore {
                        if rawHeight > 0 {
                            let scaleFactor = Self.autoScaleTargetHeightMeters / rawHeight
                            container.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
                            container.pivot = SCNMatrix4MakeTranslation(0, scaleFactor * minVec.y, 0)
                            AppLog.plants.debug("""
                                autoScale plant=\(pending.plantName, privacy: .public) \
                                scaleFactor=\(scaleFactor, format: .fixed(precision: 3), privacy: .public) \
                                pivotY=\(scaleFactor * minVec.y, format: .fixed(precision: 3), privacy: .public)
                                """)
                        }
                    }
                    // Stash the unscaled minY so refreshPivotForScale can
                    // recompute the pivot after the user pinches/zooms.
                    if rawHeight > 0 {
                        container.setValue(NSNumber(value: minVec.y), forKey: "arboreOriginalMinY")
                    }

                    // Build the cached halo NOW, while we still have a clean
                    // reference to `wrapper` (no halo recursion). flattenedClone
                    // collapses the wrapper's geometry into a single SCNGeometry
                    // baked at scale=1, which then inherits container.scale when
                    // attached. One-time cost per plant, ~ms-range.
                    buildHaloCache(for: container, source: wrapper)
                    // If we entered .adjusting before this load completed
                    // (rare race: pictureMorph confirm placed the anchor, USDZ
                    // finished loading after phase change), reveal the default
                    // outline so the new plant matches the others.
                    if parentProps?.relocationPhase == .adjusting {
                        applyOutline(to: container, color: Self.outlineDefaultColor)
                    }
                    // Container's local transform stays identity — its world
                    // transform is the anchor's transform, which ARKit corrects
                    // for drift automatically.
                    parentNode.addChildNode(container)
                    // Auto-select per the placement's explicit `autoSelect`
                    // flag. Catalogue taps pass true (default) so the
                    // editingHUD (rotate / scale +- / delete) appears
                    // immediately. Batch placements (AI auto-place,
                    // morph-confirm) pass false to avoid the orange-halo
                    // flicker as we loop through plants. Restore is also
                    // skipped — autoSelect is meaningless during reload.
                    if !pending.isRestore && pending.autoSelect {
                        selectNode(container)
                    }

                    AppLog.arAnchor.notice("""
                        instantiated plant=\(pending.plantName, privacy: .public) \
                        anchor=\(pending.instanceId.uuidString.prefix(8), privacy: .public) \
                        world=\(container.simdWorldTransform.logDescription, privacy: .public) \
                        local=\(container.simdTransform.logDescription, privacy: .public)
                        """)
            }

            /// Called on the main thread when SCNScene loading fails. Attempts a
            /// single force-redownload retry if the placement allows it.
            private func handlePlantLoadFailure(error: Error, pending: PendingPlantPlacement, anchorTransform: simd_float4x4) {
                AppLog.plants.error("model load failed plant=\(pending.plantName, privacy: .public) error=\(String(describing: error), privacy: .public)")
                guard pending.allowRetry, let raw = pending.modelURLString else { return }
                // The anchor whose load failed is now orphaned. Remove it
                // before queuing the retry so ARKit doesn't track a dead
                // placement and our maps stay consistent.
                let staleId = pending.instanceId
                if let stale = plantAnchorMap.removeValue(forKey: staleId) {
                    arView?.session.remove(anchor: stale)
                }
                Task { [weak self] in
                    do {
                        let freshURL = try await ModelCacheManager.shared.getModelURL(for: raw, forceDownload: true)
                        await MainActor.run {
                            self?.placeObject(
                                at: anchorTransform,
                                modelURL: freshURL,
                                id: pending.plantId,
                                name: pending.plantName,
                                finalScale: pending.finalScale,
                                modelURLString: raw,
                                allowRetry: false,
                                upAxis: pending.upAxis,
                                surfaceType: pending.surfaceType,
                                surfaceHeight: pending.surfaceHeight
                            )
                        }
                    } catch {
                        AppLog.plants.error("retry download failed plant=\(pending.plantName, privacy: .public) error=\(String(describing: error), privacy: .public)")
                    }
                }
            }

            // MARK: - ARSCNViewDelegate (anchor lifecycle)
            //
            // ARKit calls these on the rendering thread. We marshal the work to
            // the main thread so the dictionaries (`anchorPendingPlacements`,
            // `plantAnchorMap`) are only ever mutated from one thread, avoiding
            // Swift Dictionary races with main-thread mutators (placeObject,
            // handleDelete, undo/redo). The one-frame latency this introduces
            // is invisible to the user.

            func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
                // While we're waiting to restore a saved garden, every new
                // plane that arrives extends the debounce window. This lets
                // ARKit's plane-detection finish converging before we run the
                // snap-to-plane lookup in restoreScene.
                if anchor is ARPlaneAnchor {
                    DispatchQueue.main.async { [weak self] in
                        self?.bumpRestoreDebounce()
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self,
                          let pending = self.anchorPendingPlacements.removeValue(forKey: anchor.identifier) else {
                        return
                    }
                    self.instantiatePlantNode(into: node, pending: pending, anchorTransform: anchor.transform)
                }
            }

            func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
                DispatchQueue.main.async { [weak self] in
                    _ = self?.anchorPendingPlacements.removeValue(forKey: anchor.identifier)
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

            // MARK: - Selection visuals (cached outline halo)
            //
            // Selection is conveyed by an outline halo on the plant's geometry
            // rather than a floor ring.
            //
            // The halo is built ONCE at instantiation time via
            // `wrapper.flattenedClone()` (collapses all child geometries into a
            // single mesh) — see `attachLoadedPlantScene`. It's stored as a
            // child of the container, named with `outlineHaloName`, scaled
            // `outlineHaloScale`, with `cullMode = .front` and
            // `writesToDepthBuffer = false` on its material so only the
            // back-facing silhouette draws.
            //
            // applyOutline / removeOutline then become O(1) toggles of opacity
            // and material color. No more cloning geometry on every selection,
            // so the "lag at first selection" is gone.
            private static let outlineHaloName = "outline_halo"
            private static let outlineDefaultColor = UIColor(red: 0.36, green: 0.75, blue: 1.0, alpha: 1.0)
            private static let outlineSelectedColor = UIColor(red: 1.0, green: 0.62, blue: 0.10, alpha: 1.0)
            private static let outlineDefaultOpacity: CGFloat = 0.5
            private static let outlineSelectedOpacity: CGFloat = 0.75
            private static let outlineHaloScale: Float = 1.04
            private static let outlineRenderingOrder: Int = 100

            // Surface classification (Issue #113) — a plant whose Y is more than
            // this much above the detected floor is "elevated", otherwise "floor".
            private static let elevationThresholdMeters: Float = 0.10
            // Default visible height for newly-placed plants whose USDZ doesn't
            // declare its own scale. Roughly the size of a desk plant.
            private static let autoScaleTargetHeightMeters: Float = 0.5
            // "No surface" warning rate-limit during boundary tracing.
            private static let noSurfaceWarnIntervalSeconds: TimeInterval = 2.0

            /// Builds the cached halo node once, attached to `container`.
            /// Called from attachLoadedPlantScene right after pivot/scale setup.
            private func buildHaloCache(for container: SCNNode, source wrapper: SCNNode) {
                let halo = wrapper.flattenedClone()
                halo.name = Self.outlineHaloName
                halo.scale = SCNVector3(Self.outlineHaloScale, Self.outlineHaloScale, Self.outlineHaloScale)
                halo.opacity = 0  // hidden until selectNode / applyOutline
                halo.renderingOrder = Self.outlineRenderingOrder
                let mat = SCNMaterial()
                mat.diffuse.contents = Self.outlineDefaultColor.withAlphaComponent(Self.outlineDefaultOpacity)
                mat.transparencyMode = .default
                mat.cullMode = .front
                mat.lightingModel = .constant
                mat.writesToDepthBuffer = false
                mat.isDoubleSided = false
                halo.geometry?.materials = [mat]
                container.addChildNode(halo)
            }

            private func applyOutline(to container: SCNNode,
                                       color: UIColor,
                                       opacity: CGFloat = Coordinator.outlineDefaultOpacity) {
                guard let halo = container.childNode(withName: Self.outlineHaloName, recursively: false) else {
                    return  // legacy node without cached halo — safe no-op
                }
                halo.opacity = 1.0
                halo.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(opacity)
            }

            private func removeOutline(from container: SCNNode) {
                container.childNode(withName: Self.outlineHaloName, recursively: false)?.opacity = 0
            }

            /// Walks every plant in the scene and applies the default blue
            /// outline. Called when entering .adjusting. Cheap enough to run
            /// once per phase entry — for 100+ plants we'd want batching, but
            /// in practice gardens have <30 instances.
            private func applyOutlinesToAllPlants() {
                guard let arView = arView else { return }
                let plants: [SCNNode] = arView.scene.rootNode.childNodes.flatMap { rootChild -> [SCNNode] in
                    if rootChild.name?.starts(with: "plant_") == true { return [rootChild] }
                    return rootChild.childNodes.filter { $0.name?.starts(with: "plant_") == true }
                }
                for plant in plants {
                    applyOutline(to: plant, color: Self.outlineDefaultColor)
                }
            }

            /// Strips outlines from every plant. Called on exit from
            /// .adjusting (validate / cancel / dismiss).
            private func removeOutlinesFromAllPlants() {
                guard let arView = arView else { return }
                let plants: [SCNNode] = arView.scene.rootNode.childNodes.flatMap { rootChild -> [SCNNode] in
                    if rootChild.name?.starts(with: "plant_") == true { return [rootChild] }
                    return rootChild.childNodes.filter { $0.name?.starts(with: "plant_") == true }
                }
                for plant in plants { removeOutline(from: plant) }
            }

            private func selectNode(_ node: SCNNode) {
                // Restore the previously-selected plant to its phase-default
                // outline state (blue in .adjusting, none elsewhere).
                if let prev = selectedNode, prev !== node {
                    if parentProps?.relocationPhase == .adjusting {
                        applyOutline(to: prev, color: Self.outlineDefaultColor)
                    } else {
                        removeOutline(from: prev)
                    }
                }
                selectedNode = node
                parentProps?.hasSelectedNode = true
                parentProps?.selectedNodeName = plantName(of: node) ?? "Plante"
                applyOutline(to: node, color: Self.outlineSelectedColor, opacity: 0.7)
            }

            private func deselectAll() {
                if let node = selectedNode {
                    if parentProps?.relocationPhase == .adjusting {
                        applyOutline(to: node, color: Self.outlineDefaultColor)
                    } else {
                        removeOutline(from: node)
                    }
                }
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
            
            /// Walks up from any descendant (mesh, halo, wrapper, …) to the
            /// nearest ancestor whose name starts with "plant_". Returns the
            /// input node if none exists in the chain.
            private func findPlantRoot(_ node: SCNNode) -> SCNNode {
                var curr: SCNNode? = node
                while let n = curr {
                    if n.name?.hasPrefix("plant_") == true { return n }
                    curr = n.parent
                }
                return node
            }

            // MARK: - Manual Replacement (Issue #111)

            // Old garden data loaded from JSON (no WorldMap dependency).
            private var oldBoundaryPoints: [SIMD3<Float>] = []
            private var oldPersistedPlants: [PersistedPlant] = []
            private var oldDataLoaded = false

            // Snapshot taken right after morphing, used to revert manual adjustments.
            private var preMorphAdjustment: [String: simd_float4x4] = [:]
            // Map plantId → URL string used to instantiate the model post-morph.
            // List of morphed plants pending confirmation. Keyed by index, NOT
            // plantId — multiple instances of the same catalog plant must
            // each survive (dedup-by-id was a bug: 5 Arecas collapsed to 1).
            private var pendingMorphedPlants: [MorphedPlant] = []

            /// Loads scene_{id}.json off the main thread; stores boundary + plants
            /// for use in the manual replacement flow. Independent of WorldMap.
            func loadOldGardenData(gardenId: String) {
                guard !oldDataLoaded else { return }
                let sceneURL = GardenLocalStore.sceneURL(for: gardenId)
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else { return }
                    var boundary: [SIMD3<Float>] = []
                    var plants: [PersistedPlant] = []
                    if FileManager.default.fileExists(atPath: sceneURL.path),
                       let data = try? Data(contentsOf: sceneURL),
                       let scene = try? JSONDecoder().decode(PersistedARScene.self, from: data).normalizedToWorldFrame() {
                        plants = scene.plants
                        boundary = (scene.boundaryPoints ?? []).compactMap { arr in
                            guard arr.count >= 3 else { return nil }
                            return SIMD3<Float>(arr[0], arr[1], arr[2])
                        }
                    }
                    DispatchQueue.main.async {
                        self.oldBoundaryPoints = boundary
                        self.oldPersistedPlants = plants
                        self.oldDataLoaded = true
                    }
                }
            }

            @objc func handleEnterManualReplacement() {
                guard let arView = arView else { return }
                // Stop relying on automatic relocalization.
                cancelPendingRestore()
                pendingRestoreGardenId = nil
                didRestoreGarden = true
                DispatchQueue.main.async {
                    self.parentProps?.isRelocating = false
                    self.parentProps?.relocationPhase = .tracingBoundary
                    self.parentProps?.newBoundaryPoints = []
                    self.parentProps?.newBoundaryArea = 0
                }
                // Clean any partially restored plants (anchors + legacy nodes).
                removeAllPlantAnchors()
                arView.scene.rootNode.childNodes
                    .filter { $0.name?.starts(with: "plant_") == true }
                    .forEach { $0.removeFromParentNode() }
                // Show the OLD boundary as a faint dashed grey outline (visual cue).
                if !oldBoundaryPoints.isEmpty {
                    GhostRenderer.drawBoundary(
                        points: oldBoundaryPoints,
                        color: UIColor.lightGray,
                        opacity: 0.3,
                        in: arView.scene,
                        name: "manual_replacement_old_boundary"
                    )
                }
                clearNewBoundaryVisuals()
            }

            @objc func handleCancelManualReplacement() {
                guard let arView = arView else { return }
                let phase = parentProps?.relocationPhase ?? .scanning
                switch phase {
                case .tracingBoundary:
                    // Wipe everything and return to scanning.
                    clearNewBoundaryVisuals()
                    GhostRenderer.removeBoundary(named: "manual_replacement_old_boundary", from: arView.scene)
                    DispatchQueue.main.async {
                        self.parentProps?.relocationPhase = .scanning
                        self.parentProps?.isRelocating = true
                        self.parentProps?.newBoundaryPoints = []
                        self.parentProps?.newBoundaryArea = 0
                    }
                case .morphingPreview:
                    // Step back one phase: clear ghost plants, return to tracing.
                    arView.scene.rootNode.childNodes
                        .filter { $0.name?.starts(with: "ghost_morphed_") == true }
                        .forEach { $0.removeFromParentNode() }
                    DispatchQueue.main.async {
                        self.parentProps?.relocationPhase = .tracingBoundary
                        self.parentProps?.distortionWarnings = []
                    }
                default:
                    break
                }
            }

            func addBoundaryPoint(at transform: simd_float4x4) {
                let p = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                guard let arView = arView else { return }

                // Add a green sphere marker (same visual as the wizard's measurement view).
                let sphere = SCNSphere(radius: 0.025)
                sphere.firstMaterial?.diffuse.contents = UIColor(hex: "#2BEE79")
                sphere.firstMaterial?.lightingModel = .constant
                let node = SCNNode(geometry: sphere)
                node.simdPosition = p
                node.name = "manual_replacement_new_boundary_point"
                arView.scene.rootNode.addChildNode(node)

                DispatchQueue.main.async {
                    self.parentProps?.newBoundaryPoints.append(p)
                    self.refreshNewBoundaryArea()
                    self.refreshNewBoundaryEdges()
                }
            }

            @objc func handleBoundaryUndoLast() {
                guard let arView = arView else { return }
                // Remove the most recent green sphere if any.
                let spheres = arView.scene.rootNode.childNodes
                    .filter { $0.name == "manual_replacement_new_boundary_point" }
                if let last = spheres.last { last.removeFromParentNode() }

                DispatchQueue.main.async {
                    if let _ = self.parentProps?.newBoundaryPoints.popLast() {
                        self.refreshNewBoundaryArea()
                        self.refreshNewBoundaryEdges()
                    }
                }
            }

            @objc func handleValidateNewBoundary() {
                guard let props = parentProps, let arView = arView else { return }
                let newBoundary = props.newBoundaryPoints
                guard newBoundary.count >= 3 else { return }

                // Validate that the old garden's data finished loading from disk
                // (Issue #111 I1). Without it, GardenMorpher would silently
                // produce an empty result and the user would see nothing happen.
                guard oldDataLoaded else {
                    AppLog.manualReplace.warning("validateNewBoundary blocked — old data not loaded yet")
                    // Stay in tracingBoundary; the user can retry shortly.
                    return
                }
                guard !oldPersistedPlants.isEmpty else {
                    AppLog.manualReplace.warning("validateNewBoundary — old garden has no plants, nothing to morph")
                    DispatchQueue.main.async {
                        self.parentProps?.relocationPhase = .completed
                    }
                    return
                }
                guard !oldBoundaryPoints.isEmpty else {
                    AppLog.manualReplace.warning("validateNewBoundary — old garden has no boundary, falling back to centroid placement")
                    // Morpher's fallback path will place plants near the new
                    // centroid; user can fine-tune in .adjusting.
                    let result = GardenMorpher.morph(
                        oldPlants: oldPersistedPlants,
                        oldBoundary: [],
                        newBoundary: newBoundary,
                        floorY: averageY(of: newBoundary)
                    )
                    self.applyMorphResult(result, in: arView)
                    return
                }

                // The old boundary may have a different vertex count than the new one;
                // if so, resample so MVC weights have matching arities.
                let resampled = resamplePolygon(oldBoundaryPoints, toCount: newBoundary.count)
                let result = GardenMorpher.morph(
                    oldPlants: oldPersistedPlants,
                    oldBoundary: resampled,
                    newBoundary: newBoundary,
                    floorY: averageY(of: newBoundary)
                )

                applyMorphResult(result, in: arView)
            }

            /// Renders morph result as ghost markers and transitions to
            /// `.morphingPreview`. Called from both the normal MVC path and
            /// the no-boundary fallback (Issue #111 I1).
            private func applyMorphResult(_ result: MorphResult, in arView: ARSCNView) {
                arView.scene.rootNode.childNodes
                    .filter { $0.name?.starts(with: "ghost_morphed_") == true }
                    .forEach { $0.removeFromParentNode() }

                pendingMorphedPlants = result.morphedPlants
                for (idx, mp) in result.morphedPlants.enumerated() {
                    drawGhostMarker(for: mp, instanceIndex: idx, in: arView.scene)
                }

                DispatchQueue.main.async {
                    self.parentProps?.distortionWarnings = result.warnings
                    self.parentProps?.relocationPhase = .morphingPreview
                }
            }

            @objc func handleConfirmMorphedPlacement() {
                guard let arView = arView else { return }

                // Take a snapshot of morphed transforms before any user adjustment.
                preMorphAdjustment.removeAll()

                // Hide old-boundary ghost outline and ghost markers.
                arView.scene.rootNode.childNodes
                    .filter { $0.name?.starts(with: "ghost_morphed_") == true }
                    .forEach { $0.removeFromParentNode() }
                GhostRenderer.removeBoundary(named: "manual_replacement_old_boundary", from: arView.scene)
                clearNewBoundaryVisuals()

                // Instantiate real plants concurrently using the existing placement
                // pipeline. Iterate the MorphedPlant list directly — multiple
                // instances of the same catalog plant must each survive (was a
                // dedup bug: 5 Arecas collapsed to 1 because the dict key was
                // the catalog plantId).
                let snapshot = pendingMorphedPlants
                Task {
                    await withTaskGroup(of: Void.self) { group in
                        for mp in snapshot {
                            let persisted = mp.originalPlant
                            let transform = mp.newTransform
                            let finalScale = SCNVector3(persisted.scale[0], persisted.scale[1], persisted.scale[2])
                            group.addTask {
                                do {
                                    let url = try await ModelCacheManager.shared.getModelURL(for: persisted.modelURLString, forceDownload: false)
                                    await MainActor.run {
                                        // Propagate surface info so future
                                        // restores can snap properly (Issue #111 B1).
                                        self.placeObject(
                                            at: transform,
                                            modelURL: url,
                                            id: persisted.plantID,
                                            name: persisted.plantName,
                                            finalScale: finalScale,
                                            modelURLString: persisted.modelURLString,
                                            upAxis: persisted.upAxis,
                                            surfaceType: persisted.surfaceType,
                                            surfaceHeight: persisted.surfaceHeight,
                                            autoSelect: false  // batch — entering .adjusting
                                        )
                                    }
                                } catch {
                                    if let fallback = await MainActor.run(body: { self.resolveLocalModelURL(persisted.modelURLString) }) {
                                        await MainActor.run {
                                            self.placeObject(
                                                at: transform,
                                                modelURL: fallback,
                                                id: persisted.plantID,
                                                name: persisted.plantName,
                                                finalScale: finalScale,
                                                modelURLString: persisted.modelURLString,
                                                upAxis: persisted.upAxis,
                                                surfaceType: persisted.surfaceType,
                                                surfaceHeight: persisted.surfaceHeight,
                                                autoSelect: false
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    await MainActor.run {
                        self.pendingMorphedPlants.removeAll()
                        self.snapshotPreMorphAdjustment()
                        self.parentProps?.relocationPhase = .adjusting
                        self.applyOutlinesToAllPlants()
                    }
                }
            }

            @objc func handleRevertToMorphed() {
                guard let arView = arView else { return }
                // Issue #113 — plants are anchor children; walk one level deeper
                // and revert their world transform (not local).
                let plantNodes: [SCNNode] = arView.scene.rootNode.childNodes.flatMap { rootChild -> [SCNNode] in
                    if rootChild.name?.starts(with: "plant_") == true { return [rootChild] }
                    return rootChild.childNodes.filter { $0.name?.starts(with: "plant_") == true }
                }
                for node in plantNodes {
                    let id = plantId(of: node)
                    if let snapshot = preMorphAdjustment[id] {
                        node.simdWorldTransform = snapshot
                    }
                }
                deselectAll()
            }

            // MARK: - Manual replacement helpers

            private func clearNewBoundaryVisuals() {
                guard let arView = arView else { return }
                arView.scene.rootNode.childNodes
                    .filter { $0.name == "manual_replacement_new_boundary_point" || $0.name == "manual_replacement_new_boundary_edges" }
                    .forEach { $0.removeFromParentNode() }
            }

            private func refreshNewBoundaryArea() {
                let pts = parentProps?.newBoundaryPoints ?? []
                guard pts.count > 2 else {
                    parentProps?.newBoundaryArea = 0
                    return
                }
                var sum: Float = 0
                for i in 0..<pts.count {
                    let j = (i + 1) % pts.count
                    sum += (pts[i].x * pts[j].z) - (pts[i].z * pts[j].x)
                }
                parentProps?.newBoundaryArea = abs(sum) / 2
            }

            private func refreshNewBoundaryEdges() {
                guard let arView = arView else { return }
                let pts = parentProps?.newBoundaryPoints ?? []
                arView.scene.rootNode.childNodes
                    .filter { $0.name == "manual_replacement_new_boundary_edges" }
                    .forEach { $0.removeFromParentNode() }
                guard pts.count >= 2 else { return }
                GhostRenderer.drawBoundary(
                    points: pts,
                    color: UIColor(hex: "#2BEE79"),
                    opacity: 0.85,
                    in: arView.scene,
                    name: "manual_replacement_new_boundary_edges"
                )
            }

            private func drawGhostMarker(for mp: MorphedPlant, instanceIndex: Int, in scene: SCNScene) {
                // Lightweight marker: small floating sphere at the morphed XZ
                // (we don't load USDZ here to keep preview cheap and snappy).
                // The name embeds the instance INDEX so multiple instances of
                // the same catalog plant get distinct, identifiable markers.
                let isWarn = mp.warning != nil
                let color: UIColor = isWarn ? UIColor.systemOrange : UIColor(hex: "#FFD86F")
                let sphere = SCNSphere(radius: 0.06)
                sphere.firstMaterial?.diffuse.contents = color
                sphere.firstMaterial?.emission.contents = color
                sphere.firstMaterial?.lightingModel = .constant
                let node = SCNNode(geometry: sphere)
                node.opacity = 0.7
                node.simdTransform = mp.newTransform
                node.name = "ghost_morphed_\(instanceIndex)_\(mp.plantId)"
                scene.rootNode.addChildNode(node)
            }

            private func snapshotPreMorphAdjustment() {
                guard let arView = arView else { return }
                preMorphAdjustment.removeAll()
                // Walk anchor children too (Issue #113).
                let plantNodes: [SCNNode] = arView.scene.rootNode.childNodes.flatMap { rootChild -> [SCNNode] in
                    if rootChild.name?.starts(with: "plant_") == true { return [rootChild] }
                    return rootChild.childNodes.filter { $0.name?.starts(with: "plant_") == true }
                }
                for node in plantNodes {
                    let id = plantId(of: node)
                    preMorphAdjustment[id] = node.simdWorldTransform
                }
            }

            // Identity readers — prefer KVC values stashed on the node
            // (audit item 7). Legacy fallback parses the name for older nodes
            // that pre-date the KVC migration; safe to remove once we confirm
            // no live garden carries the old name format.
            private func plantId(of node: SCNNode) -> String {
                if let id = node.arborePlantId { return id }
                let parts = (node.name ?? "").components(separatedBy: "_")
                return parts.count >= 2 ? parts[1] : (node.name ?? "")
            }

            private func instanceId(of node: SCNNode) -> UUID? {
                if let id = node.arboreInstanceId { return id }
                let parts = (node.name ?? "").components(separatedBy: "_")
                return parts.last.flatMap(UUID.init(uuidString:))
            }

            private func plantName(of node: SCNNode) -> String? {
                if let n = node.arborePlantName { return n }
                let parts = (node.name ?? "").components(separatedBy: "_")
                return parts[safe: 2]
            }

            private func averageY(of points: [SIMD3<Float>]) -> Float {
                guard !points.isEmpty else { return 0 }
                return points.reduce(Float(0)) { $0 + $1.y } / Float(points.count)
            }

            /// Resamples a polygon to a target vertex count by uniform arc-length
            /// interpolation along its edges. Required because the OLD boundary may
            /// have a different number of vertices than the user-traced new one.
            private func resamplePolygon(_ poly: [SIMD3<Float>], toCount target: Int) -> [SIMD3<Float>] {
                guard poly.count >= 2, target >= 3 else { return poly }
                if poly.count == target { return poly }

                // Total perimeter (closed polygon).
                var perimeter: Float = 0
                let n = poly.count
                for i in 0..<n {
                    perimeter += simd_length(poly[(i + 1) % n] - poly[i])
                }
                guard perimeter > 1e-5 else { return poly }

                let step = perimeter / Float(target)
                var result: [SIMD3<Float>] = []
                var edgeIdx = 0
                var distAlongEdge: Float = 0
                var edgeStart = poly[0]
                var edgeEnd = poly[1 % n]
                var edgeLen = simd_length(edgeEnd - edgeStart)

                for i in 0..<target {
                    let target = Float(i) * step
                    while distAlongEdge + edgeLen < target && edgeIdx < n - 1 {
                        distAlongEdge += edgeLen
                        edgeIdx += 1
                        edgeStart = poly[edgeIdx]
                        edgeEnd = poly[(edgeIdx + 1) % n]
                        edgeLen = simd_length(edgeEnd - edgeStart)
                    }
                    let t = edgeLen > 1e-5 ? (target - distAlongEdge) / edgeLen : 0
                    result.append(edgeStart + (edgeEnd - edgeStart) * simd_clamp(t, 0, 1))
                }
                return result
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

private enum GardenARShareComposer {
    static func compose(snapshot: UIImage, gardenName: String) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: snapshot.size, format: format)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: snapshot.size)
            snapshot.draw(in: rect)

            drawGradient(in: context.cgContext, rect: rect)
            drawBranding(in: context.cgContext, rect: rect, snapshot: snapshot)
        }
    }

    private static func drawGradient(in cgContext: CGContext, rect: CGRect) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            UIColor.clear.cgColor,
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.38).cgColor
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.68, 1.0]

        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else { return }
        cgContext.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
    }

    private static func drawBranding(in cgContext: CGContext, rect: CGRect, snapshot: UIImage) {
        let bottomInset = rect.height * 0.045
        let logoSize = rect.width * 0.12
        let totalWidth = logoSize + rect.width * 0.025 + rect.width * 0.34
        let logoX = rect.midX - totalWidth / 2
        let logoY = rect.maxY - bottomInset - logoSize

        cgContext.saveGState()
        let logoRect = CGRect(x: logoX, y: logoY, width: logoSize, height: logoSize)
        UIBezierPath(roundedRect: logoRect, cornerRadius: logoSize * 0.22).addClip()
        if let logo = UIImage(named: "arbore_logo") {
            logo.draw(in: logoRect)
        } else {
            UIColor(red: 0.13, green: 0.27, blue: 0.19, alpha: 1).setFill()
            cgContext.fill(logoRect)
        }
        cgContext.restoreGState()

        let textX = logoRect.maxX + rect.width * 0.025
        let brandY = logoY + logoSize * 0.04
        drawText(
            "arbore",
            in: CGRect(x: textX, y: brandY, width: rect.width * 0.42, height: logoSize * 0.48),
            font: .systemFont(ofSize: rect.width * 0.058, weight: .bold),
            color: UIColor.white.withAlphaComponent(0.86)
        )
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        (text as NSString).draw(in: rect, withAttributes: attributes)
    }
}

private struct GardenSharePreviewView: View {
    let image: UIImage
    let onRetake: () -> Void
    let onShare: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(hex: "#0D120F").ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    Button {
                        dismiss()
                        onRetake()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("Aperçu du partage")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Spacer()

                    Color.clear.frame(width: 42, height: 42)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 14)
                    .padding(.horizontal, 18)

                VStack(spacing: 12) {
                Button {
                        onShare()
                } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Partager la photo")
                        }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color(hex: "#2F6B46"))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        dismiss()
                        onRetake()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.rotate")
                            Text("Reprendre la photo")
                        }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.86))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                    Text("Vous pouvez reprendre la photo si le cadrage ou la lumière ne vous convient pas.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.56))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - SCNNode KVC identity (Issue #111 audit item 7)
//
// Plants used to encode their identity (plantId, name, model URL, instance
// UUID) into `node.name` separated by underscores, then parsed back via
// `components(separatedBy: "_")[safe: i]`. That broke as soon as a plant
// name contained a space (handled OK), an underscore (would break — Bird
// of Paradise → Bird_of_Paradise), or any other separator we forgot.
//
// We now stash the identity as KVC values on the node directly. The name
// remains "plant_<id>" only as a marker so existing
// `name?.hasPrefix("plant_")` filters keep working.
extension SCNNode {
    var arborePlantId: String? {
        get { value(forKey: "arborePlantId") as? String }
        set { setValue(newValue, forKey: "arborePlantId") }
    }
    var arborePlantName: String? {
        get { value(forKey: "arborePlantName") as? String }
        set { setValue(newValue, forKey: "arborePlantName") }
    }
    var arboreInstanceId: UUID? {
        get {
            (value(forKey: "arboreInstanceId") as? String).flatMap(UUID.init(uuidString:))
        }
        set { setValue(newValue?.uuidString, forKey: "arboreInstanceId") }
    }
    var arboreModelURLString: String? {
        get { value(forKey: "arboreModelURLString") as? String }
        set { setValue(newValue, forKey: "arboreModelURLString") }
    }
}
