import SwiftUI
import ARKit
import SceneKit
import Foundation
import os
import simd
import UIKit
import AVFoundation
import AVKit

// NOTE: Les modèles de données (PersistedARScene, PersistedPlant)
// et GardenLocalStore doivent être présents dans le fichier "GardenDataModels.swift".

// MARK: - 1. Extensions & Utilitaires
enum GardenARMode {
    case create
    case reopen
}

private enum ARShareCaptureMode: String, CaseIterable, Identifiable {
    case photo
    case video

    var id: String { rawValue }

    var label: String {
        switch self {
        case .photo: return L10n.t("AR_SHARE_CAMERA_MODE_PHOTO")
        case .video: return L10n.t("AR_SHARE_CAMERA_MODE_VIDEO")
        }
    }
}

private enum GardenShareCaptureKind {
    case photo
    case video
}

private struct GardenShareCapture: Identifiable {
    let id: UUID
    let kind: GardenShareCaptureKind
    let image: UIImage?
    let videoURL: URL?
    let mediaURL: URL?
    let thumbnail: UIImage?
    let thumbnailURL: URL?
    let createdAt: Date
    let requiresPlaybackRotation: Bool

    var isVideo: Bool { kind == .video }

    static func photo(
        _ image: UIImage,
        id: UUID = UUID(),
        mediaURL: URL? = nil,
        createdAt: Date = Date()
    ) -> GardenShareCapture {
        GardenShareCapture(
            id: id,
            kind: .photo,
            image: image,
            videoURL: nil,
            mediaURL: mediaURL,
            thumbnail: image,
            thumbnailURL: nil,
            createdAt: createdAt,
            requiresPlaybackRotation: false
        )
    }

    static func video(
        url: URL,
        thumbnail: UIImage?,
        id: UUID = UUID(),
        thumbnailURL: URL? = nil,
        createdAt: Date = Date(),
        requiresPlaybackRotation: Bool = false
    ) -> GardenShareCapture {
        GardenShareCapture(
            id: id,
            kind: .video,
            image: nil,
            videoURL: url,
            mediaURL: url,
            thumbnail: thumbnail,
            thumbnailURL: thumbnailURL,
            createdAt: createdAt,
            requiresPlaybackRotation: requiresPlaybackRotation
        )
    }
}

extension Notification.Name {
    static let gardenARValidate = Notification.Name("gardenARValidate")
    static let gardenARUndo = Notification.Name("gardenARUndo")
    static let gardenARRedo = Notification.Name("gardenARRedo")
    static let gardenARDelete = Notification.Name("gardenARDelete")
    static let gardenARRotate = Notification.Name("gardenARRotate")
    static let gardenARScaleUp = Notification.Name("gardenARScaleUp")
    static let gardenARScaleDown = Notification.Name("gardenARScaleDown")
    static let gardenARDeselect = Notification.Name("gardenARDeselect")
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
    /// Appelé quand la sauvegarde est refusée faute de compte (#391). Séparé de
    /// `onValidated` pour que l'appelant ne puisse pas confondre les deux : le
    /// jardin reste en local, mais rien n'est parti sur le serveur.
    var onAccountRequired: () -> Void = {}

    // Temporary kill-switch: suggested-garden plants should no longer be
    // auto-placed when entering AR. Flip back to true to restore the old flow.
    private let automaticSuggestionPlacementEnabled = false
    
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var selectedPlantForPlacement: Plant? = nil
    @State private var placementMode: ARPlacementMode = .floor
    @State private var placementFeedback: String? = nil
    @State private var isPlacementDockExpanded = true
    @State private var dockCollapseTask: Task<Void, Never>? = nil
    @State private var hasSelectedNode = false
    @State private var selectedNodeName: String? = nil
    @State private var isSaving = false
    @State private var shouldCaptureSharePhoto = false
    @State private var capturedShareImage: UIImage?
    @State private var capturedShareVideoURL: URL?
    @State private var capturedShareVideoThumbnail: UIImage?
    @State private var shareCaptures: [GardenShareCapture] = []
    @State private var selectedShareCaptureID: UUID?
    @State private var showSharePreview = false
    @State private var isCapturingSharePhoto = false
    @State private var isShareCameraMode = false
    @State private var shareCaptureMode: ARShareCaptureMode = .photo
    @State private var shouldStartShareVideoRecording = false
    @State private var shouldStopShareVideoRecording = false
    @State private var isRecordingShareVideo = false
    @State private var shareVideoRecordingStartedAt: Date?
    @State private var loadedShareCaptureStorageKey: String?

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
    /// #391 — sauvegarde refusée faute de compte (session invité).
    @State private var showAccountRequired: Bool = false

    // Debug overlays — four independent toggles surfaced via the
    // bottom-sheet that opens on tap of the `cube.transparent` button.
    // Each persists across sessions via @AppStorage. Cf #186 + #187.
    @AppStorage("arDebugSurfaceViz") private var surfaceVizEnabled: Bool = false
    @AppStorage("arDebugSemSegViz")  private var semSegVizEnabled: Bool = false
    @AppStorage("arDebugDepthViz")   private var depthVizEnabled: Bool = false
    @AppStorage("arDebugFusedViz")   private var fusedVizEnabled: Bool = false
    // Voxel scan accumulates depth+semseg into a 3D point cloud that
    // persists across frames. `scanView` hides the camera feed so the
    // user can inspect the voxel cloud as a 3D model. Cf #187.
    @AppStorage("arDebugVoxelScan")  private var voxelScanEnabled: Bool = false
    @AppStorage("arDebugScanView")   private var scanViewEnabled: Bool = false
    // Issue #189 — TSDF iso-surface reconstruction (multi-view fusion).
    // Independent of the raw voxel point cloud above ; both can be on at
    // the same time for visual comparison.
    @AppStorage("arDebugTSDFScan")   private var tsdfScanEnabled: Bool = false
    @State private var showDebugPanel = false

    // 🤖 AI Auto-placement
    @State private var isAutoPlacing = false
    @State private var autoPlaceToast: String? = nil
    /// Per-plant progress during staggered auto-placement.
    @State private var autoPlacePlaced: Int = 0
    @State private var autoPlaceTotal: Int = 0
    @State private var autoPlaceCurrentName: String = ""

    private var latestShareCapture: GardenShareCapture? {
        shareCaptures.first
    }

    private var shareCaptureStorageKey: String {
        if let existingGardenId, !existingGardenId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "garden_\(existingGardenId)"
        }
        if let thumbnailKey, !thumbnailKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "thumbnail_\(thumbnailKey)"
        }
        let fallbackName = gardenName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return fallbackName.isEmpty ? "draft_default" : "draft_\(fallbackName)"
    }
    /// Issue #169 — set true the first time AI auto-placement actually
    /// triggers (i.e. the reticle reached the floor + stability). Used
    /// to hide the "Pointez vers le sol" coaching banner once the user
    /// successfully fired the batch. Stays true for the rest of the
    /// session ; placement won't re-trigger anyway (Coordinator gates
    /// it with `didAutoPlace`).
    @State private var hasTriggeredAutoPlace = false
    /// #169 follow-up — diagnostic state of the AI auto-placement
    /// trigger, computed in the Coordinator's `renderer(_:updateAtTime:)`
    /// and bubbled up here so the coaching banner can show *which*
    /// condition is currently blocking the auto-place instead of a
    /// generic "Pointez vers le sol" that lies when the user IS
    /// pointing at the floor.
    @State private var autoPlaceCoaching: AutoPlaceCoachingState = .analyzing
    
    // 💡 Lux widget
    @State private var currentLux: Int = 0

    var body: some View {
        if gardenUnavailable {
            gardenUnavailableView
        } else {
            placementBody
                .sheet(isPresented: $showDebugPanel) {
                    debugPanelSheet
                        .presentationDetents([.height(380)])
                        .presentationDragIndicator(.visible)
                }
                .accountRequiredAlert(isPresented: $showAccountRequired) {
                    // Le jardin reste sur l'appareil : ce sont des fichiers
                    // locaux, indépendants de la session (#391, section 4).
                    GuestSession.exitToAuthentication()
                    dismiss()
                }
        }
    }

    /// True when any debug overlay is on — drives the topBar button color.
    private var anyDebugVizOn: Bool {
        surfaceVizEnabled || semSegVizEnabled || depthVizEnabled
            || fusedVizEnabled || voxelScanEnabled || scanViewEnabled
            || tsdfScanEnabled
    }

    /// Bottom-sheet that surfaces the four debug toggles. Each is
    /// persisted via @AppStorage so the dev keeps their pick across
    /// app restarts.
    @ViewBuilder
    private var debugPanelSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "cube.transparent.fill")
                Text("Debug overlays").font(.title2.bold())
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            VStack(spacing: 4) {
                Toggle(isOn: $surfaceVizEnabled) {
                    Label("ARKit surfaces", systemImage: "square.stack.3d.up")
                }
                Toggle(isOn: $semSegVizEnabled) {
                    Label("SemSeg mask (DETR)", systemImage: "paintpalette")
                }
                Toggle(isOn: $depthVizEnabled) {
                    Label("Depth heatmap (DA V2)", systemImage: "rectangle.stack.fill")
                }
                Toggle(isOn: $fusedVizEnabled) {
                    Label("Fused 3D regions", systemImage: "cube")
                }
                Divider().padding(.vertical, 6)
                Toggle(isOn: $voxelScanEnabled) {
                    Label("Voxel scan (accumulate)", systemImage: "square.grid.3x3.fill")
                }
                Toggle(isOn: $scanViewEnabled) {
                    Label("Scan view (hide camera)", systemImage: "eye.slash")
                }
                .disabled(!voxelScanEnabled)
                Toggle(isOn: $tsdfScanEnabled) {
                    Label("TSDF iso-surface (#189)", systemImage: "shippingbox.fill")
                }
            }
            .padding(.horizontal, 20)
            .toggleStyle(.switch)

            Divider().padding(.horizontal, 20)
            VStack(alignment: .leading, spacing: 4) {
                Text("Phase 1 = ARKit-native plane classification.").font(.caption)
                Text("Phase 3 = ML inference @ ~0.5 Hz, requires models in bundle.").font(.caption)
                Text("Long-press the topBar button to panic-off everything.").font(.caption)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 20)

            Spacer(minLength: 8)
        }
        .padding(.bottom, 12)
    }

    private var placementBody: some View {
        ZStack {
            // --- Vue AR ---
            GardenARPlacementContainerView(
                selectedPlant: $selectedPlantForPlacement,
                downloadedModelURL: $downloadedModelURL,
                isDownloadingModel: $isDownloadingModel,
                placementMode: $placementMode,
                placementFeedback: $placementFeedback,
                isRelocating: $isRelocating,
                hasSelectedNode: $hasSelectedNode,
                selectedNodeName: $selectedNodeName,
                isSaving: $isSaving,
                relocationPhase: $relocationPhase,
                newBoundaryPoints: $newBoundaryPoints,
                newBoundaryArea: $newBoundaryArea,
                distortionWarnings: $distortionWarnings,
                isAutoPlacing: $isAutoPlacing,
                autoPlaceCoaching: $autoPlaceCoaching,
                autoPlaceToast: $autoPlaceToast,
                autoPlacePlaced: $autoPlacePlaced,
                autoPlaceTotal: $autoPlaceTotal,
                autoPlaceCurrentName: $autoPlaceCurrentName,
                currentLux: $currentLux,
                shouldCaptureSharePhoto: $shouldCaptureSharePhoto,
                capturedShareImage: $capturedShareImage,
                capturedShareVideoURL: $capturedShareVideoURL,
                isCapturingSharePhoto: $isCapturingSharePhoto,
                shouldStartShareVideoRecording: $shouldStartShareVideoRecording,
                shouldStopShareVideoRecording: $shouldStopShareVideoRecording,
                isRecordingShareVideo: $isRecordingShareVideo,
                shareVideoRecordingStartedAt: $shareVideoRecordingStartedAt,
                isShareCameraMode: $isShareCameraMode,
                surfaceVizEnabled: $surfaceVizEnabled,
                semSegVizEnabled: $semSegVizEnabled,
                depthVizEnabled: $depthVizEnabled,
                fusedVizEnabled: $fusedVizEnabled,
                voxelScanEnabled: $voxelScanEnabled,
                scanViewEnabled: $scanViewEnabled,
                tsdfScanEnabled: $tsdfScanEnabled,
                plantsToAutoPlace: automaticSuggestionPlacementEnabled ? selectedPlants : [],
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
                },
                // La session invité reste sur place : le jardin est en local,
                // seule la synchronisation serveur a été refusée. Fermer la vue
                // donnerait l'impression d'une perte (#391).
                onAccountRequired: { showAccountRequired = true }
            )
            .ignoresSafeArea()

            // --- Phase-based overlays (Issue #111) ---
            if mode == .reopen {
                switch relocationPhase {
                case .scanning where isRelocating:
                    ScanningCoachingOverlay(
                        onReplaceManually: {
                            NotificationCenter.default.post(name: .gardenAREnterManualReplacement, object: nil)
                        }
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

            if isShareCameraMode {
                shareCameraOverlay
                    .transition(.opacity)
            } else {
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

                    if let placementFeedback {
                        placementFeedbackBanner(placementFeedback)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        self.placementFeedback = nil
                                    }
                                }
                            }
                    }

                    // Issue #169 — AI placement coaching. Visible whenever
                    // the user lands on the AR screen with AI plants queued
                    // but hasn't yet pointed at the floor long enough to
                    // trigger the batch. Disappears as soon as auto-place
                    // fires (the autoPlacingOverlay + toast take over).
                    if automaticSuggestionPlacementEnabled,
                       mode == .create,
                       !selectedPlants.isEmpty,
                       !isAutoPlacing,
                       !hasTriggeredAutoPlace {
                        awaitingFloorPointBanner
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            .transition(.opacity)
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

                    // 3b. Phase-specific action row — shown above the bottom
                    // dock. One row per manual-replacement phase.
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
        }
        .overlay(alignment: .top) {
            // Statut thermique discret (#82). Invisible par défaut, apparait
            // brièvement sur .arboreThermalCritical posée par
            // ARQualityObserver, se masque sur .arboreThermalRecovered.
            ThermalStateBanner()
        }
        .fullScreenCover(isPresented: $showPicker) {
            PlantCatalogARView(placementMode: placementMode, wizard: wizard) { plant in
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
        }
        .onChange(of: capturedShareImage) { _, image in
            guard let image else { return }
            let capture = GardenShareCaptureStore.savePhoto(
                image,
                for: shareCaptureStorageKey
            ) ?? GardenShareCapture.photo(image)
            insertShareCapture(capture)
            isCapturingSharePhoto = false
            capturedShareVideoThumbnail = nil
        }
        .onChange(of: capturedShareVideoURL) { _, url in
            guard let url else { return }
            isRecordingShareVideo = false
            shareVideoRecordingStartedAt = nil
            Task {
                let thumbnail = await GardenShareVideoThumbnailer.thumbnail(for: url)
                guard capturedShareVideoURL == url else { return }
                capturedShareVideoThumbnail = thumbnail
                let capture = GardenShareCaptureStore.saveVideo(
                    at: url,
                    thumbnail: thumbnail,
                    for: shareCaptureStorageKey
                ) ?? GardenShareCapture.video(url: url, thumbnail: thumbnail)
                insertShareCapture(capture)
            }
        }
        .onChange(of: shareCaptureStorageKey) { _, _ in
            loadPersistedShareCaptures()
        }
        .onChange(of: isAutoPlacing) { _, new in
            // Issue #169 — latch the "auto-place fired at least once"
            // flag so the coaching banner doesn't re-appear after the
            // batch finishes (isAutoPlacing flips back to false).
            if new { hasTriggeredAutoPlace = true }
        }
        .fullScreenCover(isPresented: $showSharePreview) {
            if !shareCaptures.isEmpty {
                GardenShareGalleryView(
                    captures: shareCaptures,
                    selectedCaptureID: selectedShareCaptureID,
                    onRetake: {
                        showSharePreview = false
                        isShareCameraMode = true
                    },
                    onDelete: { capture in
                        deleteShareCapture(capture)
                    },
                    onClose: {
                        showSharePreview = false
                    }
                )
            }
        }
        .onAppear {
            loadPersistedShareCaptures()
            disableBetaDebugVisualizations()

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
                Text(L10n.t("AR_GARDEN_UNAVAILABLE_TITLE"))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(L10n.t("AR_GARDEN_UNAVAILABLE_MESSAGE"))
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Spacer()
                Button { dismiss() } label: {
                    Text(L10n.t("COMMON_BACK"))
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
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left").modifier(GlassButtonStyle())
            }
            .buttonStyle(.plain)

            Spacer()

            if !topBarShouldShowOnlyBack {
                undoRedoControl

                Button {
                    NotificationCenter.default.post(name: .gardenARValidate, object: nil)
                } label: {
                    Image(systemName: "checkmark").modifier(GlassButtonStyle(isGreen: true))
                }
                .disabled(isSaving)
                .opacity(isSaving ? 0.5 : 1)
                .buttonStyle(.plain)
            } else {
                // Keep the trailing slot at the same width so the back button
                // stays visually anchored on the left, no bar reflow.
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var undoRedoControl: some View {
        HStack(spacing: 2) {
            Button { NotificationCenter.default.post(name: .gardenARUndo, object: nil) } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Button { NotificationCenter.default.post(name: .gardenARRedo, object: nil) } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(3)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .background(
                    Capsule()
                        .fill(ArboreDesign.Colors.card.opacity(0.70))
                )
        )
        .overlay(Capsule().stroke(ArboreDesign.Colors.border.opacity(0.82), lineWidth: 1))
    }

    private var shareCameraOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    exitShareCameraMode()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.34), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("COMMON_CLOSE"))

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            if isRecordingShareVideo, let startedAt = shareVideoRecordingStartedAt {
                recordingDurationBadge(startedAt: startedAt)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()

            ZStack(alignment: .bottom) {
                HStack {
                    shareGalleryButton
                    Spacer()
                    Color.clear.frame(width: 64, height: 64)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 32)

                VStack(spacing: 13) {
                    shareShutterButton
                    shareCaptureModeSelector
                }
                .padding(.bottom, 24)
            }
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.28), .clear, .black.opacity(0.42)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private var shareGalleryButton: some View {
        Button {
            guard latestShareCapture != nil else { return }
            showSharePreview = true
        } label: {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.42))
                    .frame(width: 54, height: 54)
                    .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 1))

                if let thumbnail = latestShareCapture?.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                } else if latestShareCapture != nil {
                    Circle()
                        .fill(.black.opacity(0.62))
                        .frame(width: 48, height: 48)
                }

                if latestShareCapture?.isVideo == true {
                    Image(systemName: "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(latestShareCapture == nil)
        .opacity(latestShareCapture == nil ? 0.35 : 1)
        .accessibilityLabel(L10n.t("AR_SHARE_OPEN_LAST_CAPTURE"))
    }

    private func recordingDurationBadge(startedAt: Date) -> some View {
        TimelineView(.periodic(from: startedAt, by: 0.25)) { timeline in
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: "#E5484D"))
                    .frame(width: 8, height: 8)

                Text(formattedRecordingDuration(from: startedAt, to: timeline.date))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(.black.opacity(0.46), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        }
    }

    private var shareShutterButton: some View {
        Button {
            switch shareCaptureMode {
            case .photo:
                captureGardenSharePhoto()
            case .video:
                toggleShareVideoRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.82), lineWidth: 6)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(shareCaptureMode == .video ? Color(hex: "#E5484D") : .white)
                    .frame(width: isRecordingShareVideo ? 30 : 62, height: isRecordingShareVideo ? 30 : 62)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: isRecordingShareVideo ? 8 : 31,
                            style: .continuous
                        )
                    )

                if isCapturingSharePhoto {
                    ProgressView()
                        .tint(.black)
                }
            }
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isRecordingShareVideo)
        }
        .buttonStyle(.plain)
        .disabled(isCapturingSharePhoto)
        .accessibilityLabel(
            shareCaptureMode == .video
            ? L10n.t("AR_SHARE_CAMERA_MODE_VIDEO")
            : L10n.t("AR_CAPTURE_GARDEN_PHOTO_ACCESSIBILITY")
        )
    }

    private var shareCaptureModeSelector: some View {
        HStack(spacing: 18) {
            ForEach(ARShareCaptureMode.allCases) { mode in
                Button {
                    guard !isRecordingShareVideo else { return }
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                        shareCaptureMode = mode
                    }
                } label: {
                    Text(mode.label.uppercased())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(shareCaptureMode == mode ? Color(hex: "#F5D84B") : .white.opacity(0.82))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(shareCaptureMode == mode ? .white.opacity(0.13) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.black.opacity(0.34), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
    }

    private var bottomDock: some View {
        Group {
            if hasSelectedNode {
                editDockContent
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                placementDockContent
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(10)
        .background(dockBackground)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: hasSelectedNode)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isPlacementDockExpanded)
        .onAppear {
            schedulePlacementDockCollapse()
        }
        .onDisappear {
            dockCollapseTask?.cancel()
        }
        .onChange(of: hasSelectedNode) { _, isSelected in
            if isSelected {
                dockCollapseTask?.cancel()
            } else {
                wakePlacementDock()
            }
        }
    }

    private var placementDockContent: some View {
        HStack(spacing: 8) {
            Group {
                if isPlacementDockExpanded {
                    placementModeSelector
                } else {
                    activePlacementModeButton
                }
            }
            .frame(maxWidth: .infinity)

            arDockIconButton(
                systemImage: "camera.fill",
                isLoading: isCapturingSharePhoto,
                size: 48,
                action: {
                    wakePlacementDock()
                    enterShareCameraMode()
                }
            )
            .disabled(isCapturingSharePhoto)
            .accessibilityLabel(L10n.t("AR_CAPTURE_GARDEN_PHOTO_ACCESSIBILITY"))

            Button {
                wakePlacementDock()
                showPicker = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                        .fill(ArboreDesign.Colors.primaryGreen)
                        .overlay(
                            RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                                .stroke(.white.opacity(0.16), lineWidth: 1)
                        )

                    if isDownloadingModel {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 54, height: 48)
            }
            .disabled(isDownloadingModel)
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("COMMON_ADD"))
        }
    }

    private var editDockContent: some View {
        HStack(spacing: 8) {
            Text(selectedNodeName ?? L10n.t("AR_EDIT_SELECTED_PLANT"))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(ArboreDesign.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)

            HStack(spacing: 6) {
                arDockIconButton(systemImage: "xmark", size: 44) {
                    NotificationCenter.default.post(name: .gardenARDeselect, object: nil)
                }
                .accessibilityLabel(L10n.t("AR_EDIT_EXIT"))

                editToolButton(systemImage: "rotate.right", size: 44) {
                    NotificationCenter.default.post(name: .gardenARRotate, object: nil)
                }
                .accessibilityLabel(L10n.t("AR_EDIT_ROTATE"))

                editToolButton(systemImage: "plus.magnifyingglass", size: 44) {
                    NotificationCenter.default.post(name: .gardenARScaleUp, object: nil)
                }
                .accessibilityLabel(L10n.t("AR_EDIT_SCALE_UP"))

                editToolButton(systemImage: "minus.magnifyingglass", size: 44) {
                    NotificationCenter.default.post(name: .gardenARScaleDown, object: nil)
                }
                .accessibilityLabel(L10n.t("AR_EDIT_SCALE_DOWN"))

                editToolButton(systemImage: "trash", isDestructive: true, size: 44) {
                    NotificationCenter.default.post(name: .gardenARDelete, object: nil)
                }
                .accessibilityLabel(L10n.t("COMMON_DELETE"))
            }
        }
    }

    private var dockBackground: some View {
        RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
            .fill(.ultraThinMaterial)
            .background(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                    .fill(ArboreDesign.Colors.card.opacity(0.76))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                    .stroke(ArboreDesign.Colors.border.opacity(0.85), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
    }

    private func arDockIconButton(
        systemImage: String,
        isLoading: Bool = false,
        size: CGFloat = 48,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                    .fill(ArboreDesign.Colors.softSurface.opacity(0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                            .stroke(ArboreDesign.Colors.border.opacity(0.85), lineWidth: 1)
                    )

                if isLoading {
                    ProgressView()
                        .tint(ArboreDesign.Colors.primaryGreen)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(ArboreDesign.Colors.textPrimary)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }

    private func editToolButton(
        systemImage: String,
        isDestructive: Bool = false,
        size: CGFloat = 48,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(isDestructive ? .white : ArboreDesign.Colors.textPrimary)
                .frame(width: size, height: size)
                .background(isDestructive ? ArboreDesign.Colors.danger : ArboreDesign.Colors.softSurface.opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                        .stroke(isDestructive ? .white.opacity(0.14) : ArboreDesign.Colors.border.opacity(0.85), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func loadPersistedShareCaptures() {
        let storageKey = shareCaptureStorageKey
        guard loadedShareCaptureStorageKey != storageKey else { return }
        loadedShareCaptureStorageKey = storageKey

        let persistedCaptures = GardenShareCaptureStore.load(for: storageKey)
        shareCaptures = persistedCaptures.sorted { $0.createdAt > $1.createdAt }
        selectedShareCaptureID = shareCaptures.first?.id
    }

    private func insertShareCapture(_ capture: GardenShareCapture) {
        shareCaptures.removeAll { $0.id == capture.id }
        shareCaptures.insert(capture, at: 0)
        shareCaptures.sort { $0.createdAt > $1.createdAt }
        selectedShareCaptureID = capture.id
    }

    private func deleteShareCapture(_ capture: GardenShareCapture) {
        GardenShareCaptureStore.delete(capture, for: shareCaptureStorageKey)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            shareCaptures.removeAll { $0.id == capture.id }
        }
        selectedShareCaptureID = shareCaptures.first?.id
        if shareCaptures.isEmpty {
            showSharePreview = false
        }
    }

    private func captureGardenSharePhoto() {
        capturedShareImage = nil
        capturedShareVideoURL = nil
        capturedShareVideoThumbnail = nil
        isCapturingSharePhoto = true
        shouldCaptureSharePhoto = true
    }

    private func enterShareCameraMode() {
        NotificationCenter.default.post(name: .gardenARDeselect, object: nil)
        dockCollapseTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            isShareCameraMode = true
        }
    }

    private func exitShareCameraMode() {
        if isRecordingShareVideo {
            shouldStopShareVideoRecording = true
            shareVideoRecordingStartedAt = nil
        }
        withAnimation(.easeOut(duration: 0.18)) {
            isShareCameraMode = false
        }
        schedulePlacementDockCollapse(after: 1.2)
    }

    private func resetShareCapture() {
        capturedShareImage = nil
        capturedShareVideoURL = nil
        capturedShareVideoThumbnail = nil
        isCapturingSharePhoto = false
        shouldCaptureSharePhoto = false
        shouldStartShareVideoRecording = false
        shouldStopShareVideoRecording = false
        isRecordingShareVideo = false
        shareVideoRecordingStartedAt = nil
    }

    private func toggleShareVideoRecording() {
        if isRecordingShareVideo {
            shouldStopShareVideoRecording = true
            shareVideoRecordingStartedAt = nil
        } else {
            capturedShareImage = nil
            capturedShareVideoURL = nil
            capturedShareVideoThumbnail = nil
            shareVideoRecordingStartedAt = Date()
            shouldStartShareVideoRecording = true
        }
    }

    private func formattedRecordingDuration(from start: Date, to end: Date) -> String {
        let totalSeconds = max(0, Int(end.timeIntervalSince(start)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func wakePlacementDock() {
        guard !hasSelectedNode else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            isPlacementDockExpanded = true
        }
        schedulePlacementDockCollapse()
    }

    private func schedulePlacementDockCollapse(after seconds: Double = 3.4) {
        guard !hasSelectedNode else { return }
        dockCollapseTask?.cancel()
        dockCollapseTask = Task {
            let delay = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    isPlacementDockExpanded = false
                }
            }
        }
    }

    private func disableBetaDebugVisualizations() {
        surfaceVizEnabled = false
        semSegVizEnabled = false
        depthVizEnabled = false
        fusedVizEnabled = false
        voxelScanEnabled = false
        scanViewEnabled = false
        tsdfScanEnabled = false
    }
    
    private var savingIndicator: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(.white)
            Text(L10n.t("AR_SAVING_GARDEN"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(12)
        .background(.black.opacity(0.6))
        .cornerRadius(12)
        .padding(.bottom, 10)
    }

    private var placementModeSelector: some View {
        HStack(spacing: 6) {
            ForEach(ARPlacementMode.allCases) { mode in
                let isActive = placementMode == mode
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                        placementMode = mode
                    }
                    placementFeedback = compatibilityFeedback(for: mode)
                    schedulePlacementDockCollapse()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12, weight: .bold))
                        Text(mode.label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .foregroundStyle(isActive ? Color.white : ArboreDesign.Colors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .padding(.horizontal, 3)
                    .background(isActive ? ArboreDesign.Colors.primaryGreen : ArboreDesign.Colors.softSurface.opacity(0.64))
                    .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                            .stroke(
                                isActive ? .white.opacity(0.14) : ArboreDesign.Colors.border.opacity(0.74),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(ArboreDesign.Colors.card.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                .stroke(ArboreDesign.Colors.border.opacity(0.78), lineWidth: 1)
        )
    }

    private var activePlacementModeButton: some View {
        Button {
            wakePlacementDock()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: placementMode.icon)
                    .font(.system(size: 13, weight: .bold))
                Text(L10n.f("AR_PLANT_CATALOG_MODE_BADGE_FORMAT", placementMode.label))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundStyle(ArboreDesign.Colors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 10)
            .background(ArboreDesign.Colors.softSurface.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                    .stroke(ArboreDesign.Colors.border.opacity(0.78), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func compatibilityFeedback(for mode: ARPlacementMode) -> String? {
        guard let plant = selectedPlantForPlacement,
              mode.needsPlantCompatibility,
              !PlantPlacementCompatibility.supports(plant, mode: mode) else {
            return nil
        }

        switch mode {
        case .wall:
            return L10n.t("AR_PLACEMENT_INCOMPATIBLE_WALL")
        case .ceiling:
            return L10n.t("AR_PLACEMENT_INCOMPATIBLE_HANGING")
        case .floor:
            return nil
        }
    }

    private func placementFeedbackBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: "#FFB020"))

            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(hex: "#FFB020").opacity(0.32), lineWidth: 1)
        )
    }

    // MARK: - 🤖 Auto-Placement Overlay

    /// #169 follow-up — diagnostic states reflecting which condition
    /// of the AI auto-placement trigger is currently blocking. Bubbled
    /// from the Coordinator on transition only (not every frame) via
    /// `parentProps?.autoPlaceCoaching = ...`. Equatable so the
    /// Coordinator can dedupe-suppress identical updates.
    enum AutoPlaceCoachingState: Equatable {
        /// ARKit is relocalizing against the measurement WorldMap loaded in
        /// `makeUIView` (mode `.create`). Until `trackingState == .normal`
        /// the floor anchors from the saved map aren't restored, so the
        /// auto-place gate can't fire. The user must sweep the space to let
        /// ARKit re-match its mapped viewpoint. Without this state the banner
        /// stayed on `analyzing` and gave no hint that movement was needed.
        case relocalizing
        /// No `ARPlaneAnchor` classified as floor yet. ARKit is still
        /// scanning ; the user should keep moving the phone.
        case analyzing
        /// Floor known, but the reticle has no `.geometry` quality —
        /// either no raycast hit, or hit only an `.estimatedPlane`
        /// (ARKit hasn't bound it to a real `ARPlaneAnchor` yet).
        case adjustReticle
        /// Reticle solidly on a horizontal `.geometry` surface but its
        /// Y is > 20 cm above the floor (user pointing at a table /
        /// rug edge / cushion). `deltaCm` is the rounded-to-5 height
        /// delta so the banner doesn't flicker on every cm of movement.
        case pointLower(deltaCm: Int)
        /// All gates pass — accumulating frames toward the
        /// `stablePlaneThreshold`. Banner becomes a progress bar.
        case stabilizing(progress: Int, threshold: Int)

        var symbolName: String {
            switch self {
            case .relocalizing: return "arrow.triangle.2.circlepath"
            case .analyzing: return "viewfinder.circle"
            case .adjustReticle: return "viewfinder"
            case .pointLower: return "arrow.down"
            case .stabilizing: return "checkmark.circle"
            }
        }

        var tint: Color {
            switch self {
            case .analyzing, .adjustReticle, .relocalizing: return Color(hex: "#FFB020")
            case .pointLower: return Color(hex: "#FF8030")
            case .stabilizing: return Color(hex: "#2BEE79")
            }
        }

        var title: String {
            switch self {
            case .relocalizing:
                return L10n.t("AR_AUTOPLACE_RELOCALIZING_TITLE")
            case .analyzing:
                return L10n.t("AR_AUTOPLACE_ANALYZING_TITLE")
            case .adjustReticle:
                return L10n.t("AR_AUTOPLACE_ADJUST_RETICLE_TITLE")
            case .pointLower(let cm):
                return L10n.f("AR_AUTOPLACE_POINT_LOWER_TITLE_FORMAT", cm)
            case .stabilizing(let p, let t):
                return L10n.f("AR_AUTOPLACE_STABILIZING_TITLE_FORMAT", p, t)
            }
        }

        var subtitle: String {
            switch self {
            case .relocalizing:
                return L10n.t("AR_AUTOPLACE_RELOCALIZING_SUBTITLE")
            case .analyzing:
                return L10n.t("AR_AUTOPLACE_ANALYZING_SUBTITLE")
            case .adjustReticle:
                return L10n.t("AR_AUTOPLACE_ADJUST_RETICLE_SUBTITLE")
            case .pointLower:
                return L10n.t("AR_AUTOPLACE_POINT_LOWER_SUBTITLE")
            case .stabilizing:
                return L10n.t("AR_AUTOPLACE_STABILIZING_SUBTITLE")
            }
        }
    }

    /// Issue #169 follow-up — coaching banner driven by the diagnostic
    /// state computed in the Coordinator (`AutoPlaceCoachingState`).
    /// The original static banner ("Pointez vers le sol") was lying when
    /// the user WAS pointing at the floor but another gate was failing
    /// (no .geometry quality yet, no floor classified, reticle slightly
    /// too high, etc.) — silent failure mode with no actionable hint.
    ///
    /// This version reflects the actual blocking condition so the user
    /// can self-correct. Gate logic itself unchanged (cf. #169 fix in
    /// `renderer(_:updateAtTime:)` — same ±20 cm tolerance, same
    /// .geometry requirement, same 15-frame stability).
    private var awaitingFloorPointBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: autoPlaceCoaching.symbolName)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(autoPlaceCoaching.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(autoPlaceCoaching.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(autoPlaceCoaching.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(autoPlaceCoaching.tint.opacity(0.25), lineWidth: 1)
                )
        )
        .background(Color.black.opacity(0.55).clipShape(RoundedRectangle(cornerRadius: 14)))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .animation(.easeInOut(duration: 0.2), value: autoPlaceCoaching)
    }

    private var autoPlacingOverlay: some View {
        let progress: Double = autoPlaceTotal > 0
            ? Double(autoPlacePlaced) / Double(autoPlaceTotal)
            : 0

        return ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                // Animated progress ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 4)
                        .frame(width: 56, height: 56)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color(hex: "#2BEE79"),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.35), value: progress)

                    if autoPlaceTotal > 0 {
                        Text("\(autoPlacePlaced)/\(autoPlaceTotal)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    } else {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                    }
                }

                VStack(spacing: 6) {
                    Text(autoPlaceTotal > 0
                         ? L10n.t("AR_AUTOPLACE_PLACING")
                         : L10n.t("AR_AUTOPLACE_DOWNLOADING_MODELS"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    if !autoPlaceCurrentName.isEmpty {
                        Text("🌱 \(autoPlaceCurrentName)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "#2BEE79"))
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .id("plantName_\(autoPlaceCurrentName)")
                    }

                    if autoPlaceTotal > 0 {
                        Text(L10n.f("AR_AUTOPLACE_PLACED_FORMAT", autoPlacePlaced, autoPlaceTotal))
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: autoPlaceCurrentName)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color(hex: "#2BEE79").opacity(0.3), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 24)
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
//
// Internal access (was fileprivate) so that the Coordinator's methods
// can be split across multiple files via extensions — see
// `GardenARPlacementView+SceneUnderstanding.swift` and
// `GardenARPlacementView+ManualReplacement.swift`.
struct GardenARPlacementContainerView: UIViewRepresentable {
    @Binding var selectedPlant: Plant?
    @Binding var downloadedModelURL: URL?
    @Binding var isDownloadingModel: Bool
    @Binding var placementMode: ARPlacementMode
    @Binding var placementFeedback: String?
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
    /// #169 follow-up — Coordinator writes here on transition only.
    @Binding var autoPlaceCoaching: GardenARPlacementView.AutoPlaceCoachingState
    @Binding var autoPlaceToast: String?
    /// Per-plant staggered placement progress.
    @Binding var autoPlacePlaced: Int
    @Binding var autoPlaceTotal: Int
    @Binding var autoPlaceCurrentName: String
    @Binding var currentLux: Int
    @Binding var shouldCaptureSharePhoto: Bool
    @Binding var capturedShareImage: UIImage?
    @Binding var capturedShareVideoURL: URL?
    @Binding var isCapturingSharePhoto: Bool
    @Binding var shouldStartShareVideoRecording: Bool
    @Binding var shouldStopShareVideoRecording: Bool
    @Binding var isRecordingShareVideo: Bool
    @Binding var shareVideoRecordingStartedAt: Date?
    @Binding var isShareCameraMode: Bool

    /// Phase 1 (#186) — colour each detected plane by its `SurfaceType`.
    @Binding var surfaceVizEnabled: Bool
    /// Phase 3 (#187) — 2D mask overlay from DETR Semantic Segmentation.
    @Binding var semSegVizEnabled: Bool
    /// Phase 3 (#187) — 2D heatmap overlay from Depth Anything V2.
    @Binding var depthVizEnabled: Bool
    /// Phase 3 (#187) — 3D bbox + label overlay from SemSeg+Depth fusion.
    @Binding var fusedVizEnabled: Bool
    /// Phase 3 (#187) — accumulate backprojected depth into a voxel cloud.
    @Binding var voxelScanEnabled: Bool
    /// Phase 3 (#187) — hide the AR camera feed so the user sees only
    /// the voxel cloud (works only with `voxelScanEnabled` on).
    @Binding var scanViewEnabled: Bool
    /// Issue #189 — TSDF iso-surface reconstruction (multi-view fusion).
    @Binding var tsdfScanEnabled: Bool

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
    /// Appelé quand la sauvegarde est refusée faute de compte (#391). Séparé de
    /// `onValidated` pour que l'appelant ne puisse pas confondre les deux : le
    /// jardin reste en local, mais rien n'est parti sur le serveur.
    var onAccountRequired: () -> Void = {}

    func makeUIView(context: Context) -> ARSCNView {
        let isCreate = self.mode == .create
        let mapId = self.measurementWorldMapId ?? "nil"
        AppLog.gardenLoad.notice("🤖 [makeUIView] boundaryPoints=\(self.boundaryPoints.count) isCreate=\(isCreate) mapId=\(mapId) plantsCount=\(self.plantsToAutoPlace.count)")
        let sceneView = ARSCNView(frame: .zero)
        sceneView.autoenablesDefaultLighting = true
        sceneView.delegate = context.coordinator
        sceneView.session.delegate = context.coordinator
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
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
            context.coordinator.isWaitingForWorldMapLoad = true
            let mapURL = GardenLocalStore.worldMapURL(for: mapId)
            DispatchQueue.global(qos: .userInitiated).async {
                guard FileManager.default.fileExists(atPath: mapURL.path),
                      let mapData = try? Data(contentsOf: mapURL),
                      let worldMap = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: mapData)
                else {
                    AppLog.gardenLoad.notice("WorldMap missing or unreadable id=\(mapId, privacy: .public)")
                    DispatchQueue.main.async {
                        context.coordinator.isWaitingForWorldMapLoad = false
                    }
                    return
                }
                DispatchQueue.main.async {
                    let restartConfig = ARWorldTrackingConfiguration()
                    restartConfig.planeDetection = [.horizontal, .vertical]
                    restartConfig.environmentTexturing = ARQuality.recommended.environmentTexturing
                    restartConfig.initialWorldMap = worldMap
                    sceneView.session.run(restartConfig, options: [.resetTracking, .removeExistingAnchors])
                    context.coordinator.worldMapLoadedAt = CACurrentMediaTime()
                    context.coordinator.isWaitingForWorldMapLoad = false
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
        context.coordinator.parentProps = self
        context.coordinator.updateCachedBounds()
        context.coordinator.setShareCameraMode(isShareCameraMode)
        // BETA #191: ARKit surface viz + Scene Understanding wiring paused
        // for beta — even if a stale @AppStorage flag is still true on a
        // dev device, the calls below stay no-op'd so no guizmo can appear.
        // Restore on post-jury reactivation.
        /*
        context.coordinator.syncSurfaceVizEnabled(surfaceVizEnabled, sceneView: uiView)
        context.coordinator.syncSceneUnderstanding(
            semSegEnabled: semSegVizEnabled,
            depthEnabled: depthVizEnabled,
            fusedEnabled: fusedVizEnabled,
            voxelScanEnabled: voxelScanEnabled,
            scanViewEnabled: scanViewEnabled,
            tsdfScanEnabled: tsdfScanEnabled,
            sceneView: uiView
        )
        */

        if shouldCaptureSharePhoto {
            DispatchQueue.main.async {
                capturedShareImage = uiView.snapshot()
                isCapturingSharePhoto = false
                shouldCaptureSharePhoto = false
            }
        }

        if shouldStartShareVideoRecording {
            DispatchQueue.main.async {
                do {
                    try context.coordinator.startShareVideoRecording(in: uiView) { url in
                        capturedShareVideoURL = url
                        isRecordingShareVideo = false
                    }
                    isRecordingShareVideo = true
                } catch {
                    placementFeedback = L10n.t("AR_SHARE_VIDEO_FAILED")
                    isRecordingShareVideo = false
                    shareVideoRecordingStartedAt = nil
                }
                shouldStartShareVideoRecording = false
            }
        }

        if shouldStopShareVideoRecording {
            DispatchQueue.main.async {
                context.coordinator.stopShareVideoRecording { url in
                    if let url {
                        capturedShareVideoURL = url
                    } else {
                        placementFeedback = L10n.t("AR_SHARE_VIDEO_FAILED")
                    }
                    isRecordingShareVideo = false
                    shareVideoRecordingStartedAt = nil
                }
                shouldStopShareVideoRecording = false
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
        coordinator.cancelAllHeavyUpgrades()
        coordinator.cancelShareVideoRecording()
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.arView = nil
    }

    // MARK: - Coordinator
        final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate, UIGestureRecognizerDelegate {
            var parentProps: GardenARPlacementContainerView?
            weak var arView: ARSCNView?
            
            private var reticleNode: SCNNode?
            private var lastReticleTransform: simd_float4x4?
            private var lastReticleHit: SurfaceRaycastHit?
            private var currentReticleReliability: PlacementReliability = .unavailable
            private var reticleStabilityKey: String?
            private var reticleStableSince: TimeInterval?
            private var reticleLastPosition: SIMD3<Float>?
            // Quality of the surface under the reticle. Drives color feedback
            // and decides whether boundary taps are accepted reliably.
            private enum ReticleQuality: String { case none, estimated, geometry }
            private struct SurfaceRaycastHit {
                let placementTransform: simd_float4x4
                let reticleTransform: simd_float4x4
                let quality: ReticleQuality
                let source: SurfaceHitSource
                let surfaceType: SurfaceType?
                let placementMode: ARPlacementMode
                let planeAnchorId: UUID?
                let planeTransform: simd_float4x4?
                let planeFeatures: PlaneFeatures?
            }
            private var reticleQuality: ReticleQuality = .none
            /// Combined quality + surfaceType key used to detect a "real"
            /// transition (so we only re-apply the reticle's diffuse colour
            /// when it actually needs to change). Issue #186.
            private var lastReticleColorKey: String = ""
            // Rate-limit "no surface" warnings during boundary tracing.
            private var lastNoSurfaceWarnAt: TimeInterval = 0
            private var selectedNode: SCNNode?
            /// LOD : swaps (heavy↔light) en cours, indexés par instanceId, avec leur LOD
            /// CIBLE — pour ne pas les annuler/redémarrer à tort, appliquer la bonne
            /// hystérésis pendant le download, et annuler le download au bon niveau.
            private struct InFlightLODSwap { let task: Task<Void, Never>; let target: ModelLOD }
            private var heavyUpgradeTasks: [UUID: InFlightLODSwap] = [:]
            /// LOD : throttle de l'évaluation per-frame (temps de rendu du dernier passage).
            private var lastLODEvalAt: TimeInterval = 0
            /// LOD : dernier instant de chauffe (thermal ≥ .serious / Low Power). -1 = jamais.
            /// Sert au cooldown : on ne ré-autorise les upgrades qu'après un retour au frais soutenu.
            private var lodLastHotAt: TimeInterval = -1
            private var isRestoring = false
            var isWaitingForWorldMapLoad = false
            var worldMapLoadedAt: TimeInterval = 0
            private var lastAutoPlaceLogTime: TimeInterval = 0

            private var undoStack: [[PersistedPlant]] = []
            private var redoStack: [[PersistedPlant]] = []
            // Cached on main thread to avoid UIKit access from SceneKit render queue
            private var cachedViewCenter: CGPoint = .zero
            // Tracks upAxis per planted plant ID for capture/restore
            private var plantUpAxisMap: [String: String] = [:]
            // Garden ID pending restore after WorldMap relocalization
            var pendingRestoreGardenId: String?

            // Issue #186 — surface classification cache + viz controller.
            //
            // `planeAnchors` keeps the ARPlaneAnchor itself (ARKit owns it,
            // we keep a reference so the viz can replay without going
            // through `session.currentFrame` — that lookup retains an
            // ARFrame every call and triggers the "delegate is retaining
            // N ARFrames" warning under fast plane updates).
            // `planeFeatures` snapshots geometric features per anchor.
            // `planeTypes` records the heuristic verdict.
            // `floorY` is the lowest Y among horizontal planes seen so far.
            //
            // **Threading** : `renderer(_:updateAtTime:)` runs on the SCN
            // render queue while mutations happen on the main queue. Direct
            // dict access from both = Swift Dictionary internal storage
            // gets corrupted, manifests as
            // `-[__NSCFNumber objectForKey:]` crashes on tagged pointers.
            // `surfacesLock` serialises every read + write below.
            private let surfacesLock = OSAllocatedUnfairLock()
            private var planeAnchors: [UUID: ARPlaneAnchor] = [:]
            private var planeFeatures: [UUID: PlaneFeatures] = [:]
            private var planeTypes: [UUID: SurfaceType] = [:]
            private var floorY: Float?
            private let surfaceViz = SurfaceVizController()
            /// Cached camera Y to avoid `session.currentFrame` reads in the
            /// classification hot path. Updated each frame in `renderer(_:updateAtTime:)`.
            private var lastCameraY: Float = 1.6

            // Issue #187 — SemSeg + Depth scene understanding pipeline.
            // The controller stays nil until at least one of the three
            // Phase 3 overlays is toggled on (cf syncSceneUnderstanding) ;
            // each overlay starts/stops independently of the others. The
            // controller exposes a single onSnapshot callback that fans
            // out to whichever overlays are active when the snapshot
            // arrives.
            // Accessed by the SceneUnderstanding+sync extension (split
            // out to its own file) — internal access required so cross-
            // file extensions can reach them.
            var sceneCtl: SceneUnderstandingController?
            let semSegOverlay = SemSegOverlay()
            let depthOverlay = DepthOverlay()
            let fusedOverlay = FusedSceneOverlay()
            let voxelOverlay = VoxelOverlay()
            /// Shared with the sceneCtl when voxel-scan is enabled.
            /// Survives a voxelScan toggle-off so the user can keep
            /// admiring their scan with no live accumulation. Reset
            /// on each OFF→ON edge (fresh scan) and on view dismantle.
            var voxelGrid: VoxelGrid?
            /// Last seen value of `voxelScanEnabled` — used to detect
            /// OFF→ON edges (clear + start fresh) and ON→OFF edges
            /// (pause accumulation, keep cloud visible).
            var voxelScanWasOn = false

            // Issue #189 — TSDF iso-surface reconstruction. Same coexist
            // pattern as the voxel cloud above : grid + overlay survive
            // a toggle-off so the user can keep viewing their mesh.
            let tsdfOverlay = TSDFOverlay()
            var tsdfGrid: TSDFGrid?
            var tsdfScanWasOn = false

            // Issue #113 — ARAnchor-based placement.
            // anchor.identifier (UUID, unique per placement) → its ARAnchor.
            // Keyed by UUID and not by plantId because the user can place multiple
            // instances of the same catalog plant.
            private var plantAnchorMap: [UUID: ARAnchor] = [:]
            // anchor.identifier → pending visual to attach when ARKit creates the anchor's node.
            private var anchorPendingPlacements: [UUID: PendingPlantPlacement] = [:]
            private let shareVideoRecorder = GardenARShareVideoRecorder()
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
                let placementMode: ARPlacementMode?
                let surfaceAnchor: PersistedSurfaceAnchor?
                let instanceId: UUID  // anchor.identifier — used so the loaded node can find its anchor
                let autoSelect: Bool  // false for batch placements (AI auto-place) to avoid orange-halo flicker
                var hasHeavy: Bool = false  // LOD: si true, on charge la version lourde en fond puis on swap
            }

            // 🤖 AI Auto-placement
            private var didAutoPlace = false
            private var stablePlaneFrameCount = 0
            private let stablePlaneThreshold = 15  // ~0.5s at 30fps before auto-placing
            /// #169 follow-up — last value pushed to `parentProps.autoPlaceCoaching`.
            /// We only dispatch on transition, not every frame (60 fps update
            /// would tank SwiftUI re-renders). `nil` = nothing pushed yet.
            private var lastAutoPlaceCoaching: GardenARPlacementView.AutoPlaceCoachingState?

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
                nc.addObserver(self, selector: #selector(handleDeselectAction), name: .gardenARDeselect, object: nil)
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

            func startShareVideoRecording(
                in sceneView: ARSCNView,
                completion: @escaping (URL?) -> Void
            ) throws {
                try shareVideoRecorder.start(sceneView: sceneView, completion: completion)
            }

            func stopShareVideoRecording(completion: @escaping (URL?) -> Void) {
                shareVideoRecorder.stop(completion: completion)
            }

            func cancelShareVideoRecording() {
                shareVideoRecorder.stop { _ in }
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

            func setShareCameraMode(_ isActive: Bool) {
                guard isActive else { return }
                reticleNode?.opacity = 0
                lastReticleHit = nil
                lastReticleTransform = nil
                resetReticleReliability()
            }

            // MARK: - WorldMap relocalization tracking
            // Internal access for the ManualReplacement extension (#188 P3.1).
            var didRestoreGarden = false

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
                // BETA #191: Scene Understanding ML tick disabled for beta.
                // No DA V2 / DETR inference runs, no calibration anchors
                // are collected. Re-enable with the rest of the pipeline
                // when post-jury reactivation lands. Original block below.
                /*
                // Issue #187 / #186 Niveau 2 — opportunistic SemSeg + Depth
                // inference. 1 Hz internal throttle, no-op when sceneCtl
                // is nil (no Phase-3 overlay enabled).
                //
                // We feed the calibrator with two sources of world-space
                // anchors :
                //  - all known ARPlaneAnchor centroids (5-15 indoors)
                //  - a sample of `frame.rawFeaturePoints` (~50-500 raw
                //    VIO points per frame ; we cap to 30 random ones to
                //    keep the LS fit fast and balanced).
                //
                // The controller then fits `1/metric = a·raw + b` by
                // least squares against ALL these anchors at once —
                // way more robust than the single-floor-centroid we
                // used to pass (which was the source of the device
                // calibration drift we saw on #188).
                let planeCentroids: [SIMD3<Float>] = surfacesLock.withLock {
                    self.planeFeatures.values.map(\.center)
                }
                var anchors = planeCentroids
                if let cloud = frame.rawFeaturePoints {
                    let pts = cloud.points
                    if pts.count <= 30 {
                        anchors.append(contentsOf: pts)
                    } else {
                        // Stride-sample evenly to avoid bias toward the
                        // first part of the cloud.
                        let step = max(1, pts.count / 30)
                        anchors.reserveCapacity(anchors.count + 30)
                        for i in stride(from: 0, to: pts.count, by: step) {
                            anchors.append(pts[i])
                        }
                    }
                }
                sceneCtl?.tick(frame: frame, calibrationAnchors: anchors)
                */

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

                let mapStatusOK = mapStatus == .mapped || mapStatus == .extending
                let trackingNormal: Bool = {
                    if case .normal = trackingState { return true }
                    return false
                }()

                // 🤖 AI Auto-placement for boundaries: trigger once tracking is normal
                // AND the floor is detected (or boundary Y is available as fallback).
                // Bug fix #198: we used to trigger on trackingNormal alone, before
                // ARKit had a floor plane → Y=0 (session origin, chest height) → plants in the air.
                if let props = parentProps,
                   props.mode == .create,
                   props.measurementWorldMapId != nil,
                   props.boundaryPoints.count >= 3,
                   !didAutoPlace,
                   !isWaitingForWorldMapLoad,
                   trackingNormal,
                   !props.plantsToAutoPlace.isEmpty {

                    let timeSinceLoad = CACurrentMediaTime() - worldMapLoadedAt
                    if timeSinceLoad > 0.5 {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self, !self.didAutoPlace else { return }
                            // Prefer ARKit floor; boundary Y is a reliable fallback.
                            let hasFloor = self.detectedFloorY() != nil
                            let hasBoundaryY = !props.boundaryPoints.isEmpty
                            if hasFloor || hasBoundaryY {
                                self.didAutoPlace = true
                                self.autoPlaceAIPlants(at: nil)
                            } else {
                                // Floor not yet detected — retry after 1 s.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                                    guard let self = self, !self.didAutoPlace else { return }
                                    self.didAutoPlace = true
                                    self.autoPlaceAIPlants(at: nil)
                                }
                            }
                        }
                    }
                }

                // 🤖 Coaching pendant la relocalisation (mode .create). Tant que la
                // WorldMap de mesure n'est pas chargée OU que le tracking n'est pas
                // .normal, l'auto-placement ne peut pas se déclencher : on l'indique
                // à l'utilisateur ("balaie la zone") au lieu de laisser la bannière
                // coincée sur "analyse". Dès que la relocalisation aboutit, le
                // renderer reprend la main avec ses états fins (analyzing/…).
                if let props = parentProps,
                   props.mode == .create,
                   props.measurementWorldMapId != nil,
                   !props.plantsToAutoPlace.isEmpty,
                   !didAutoPlace,
                   isWaitingForWorldMapLoad || !trackingNormal {
                    if lastAutoPlaceCoaching != .relocalizing {
                        lastAutoPlaceCoaching = .relocalizing
                        DispatchQueue.main.async { [weak self] in
                            self?.parentProps?.autoPlaceCoaching = .relocalizing
                        }
                    }
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

            private func activePlacementMode() -> ARPlacementMode {
                if parentProps?.relocationPhase.isManualReplacement == true {
                    return .floor
                }
                return parentProps?.placementMode ?? .floor
            }

            private func raycastHit(at point: CGPoint, mode: ARPlacementMode) -> SurfaceRaycastHit? {
                guard let arView = arView else { return nil }

                let alignment: ARRaycastQuery.TargetAlignment
                switch mode {
                case .floor, .ceiling:
                    alignment = .horizontal
                case .wall:
                    alignment = .vertical
                }

                let concreteTargets: [(ARRaycastQuery.Target, ReticleQuality, SurfaceHitSource)] = [
                    (.existingPlaneGeometry, .geometry, .existingPlaneGeometry),
                    (.existingPlaneInfinite, .estimated, .existingPlaneInfinite)
                ]

                var blockedCandidate: SurfaceRaycastHit?
                for (target, quality, source) in concreteTargets {
                    if let hit = raycastHit(
                        at: point,
                        mode: mode,
                        allowing: target,
                        alignment: alignment,
                        quality: quality,
                        source: source
                    ) {
                        if surfaceAccepted(hit) {
                            return hit
                        }
                        blockedCandidate = blockedCandidate ?? hit
                    }
                }

                // White walls/ceilings often fail to grow a full ARPlaneAnchor.
                // Let ARKit provide an estimated plane in the requested
                // orientation, but keep the mode-specific compatibility checks
                // before the user can commit the placement.
                if let hit = raycastHit(
                    at: point,
                    mode: mode,
                    allowing: .estimatedPlane,
                    alignment: alignment,
                    quality: .estimated,
                    source: .estimatedPlane
                ) {
                    if surfaceAccepted(hit) {
                        return hit
                    }
                    blockedCandidate = blockedCandidate ?? hit
                }

                if let hit = syntheticFallbackHit(at: point, mode: mode) {
                    return hit
                }

                return blockedCandidate
            }

            private func raycastHit(
                at point: CGPoint,
                mode: ARPlacementMode,
                allowing target: ARRaycastQuery.Target,
                alignment: ARRaycastQuery.TargetAlignment,
                quality: ReticleQuality,
                source: SurfaceHitSource
            ) -> SurfaceRaycastHit? {
                guard let arView = arView,
                      let query = arView.raycastQuery(from: point, allowing: target, alignment: alignment),
                      let result = arView.session.raycast(query).first else {
                    return nil
                }

                let inferredSurface = inferredSurfaceType(
                    for: result,
                    mode: mode,
                    target: target
                )

                if mode == .ceiling,
                   inferredSurface != .ceiling,
                   target == .estimatedPlane {
                    return nil
                }

                let plane = result.anchor as? ARPlaneAnchor
                let features = plane.map(PlaneFeatures.init)
                return SurfaceRaycastHit(
                    placementTransform: placementTransform(for: result, mode: mode, surfaceType: inferredSurface),
                    reticleTransform: result.worldTransform,
                    quality: quality,
                    source: source,
                    surfaceType: inferredSurface,
                    placementMode: mode,
                    planeAnchorId: plane?.identifier,
                    planeTransform: plane?.transform,
                    planeFeatures: features
                )
            }

            private func inferredSurfaceType(
                for result: ARRaycastResult,
                mode: ARPlacementMode,
                target: ARRaycastQuery.Target
            ) -> SurfaceType? {
                if let surfaceType = resolvedSurfaceType(for: result) {
                    return surfaceType
                }

                guard target == .estimatedPlane else { return nil }

                switch mode {
                case .floor:
                    let hitY = result.worldTransform.columns.3.y
                    let cameraY = currentCameraPosition()?.y ?? lastCameraY
                    if hitY > cameraY + 0.9 {
                        return .ceiling
                    }
                    return .floor
                case .wall:
                    return .wall
                case .ceiling:
                    let hitY = result.worldTransform.columns.3.y
                    let cameraY = currentCameraPosition()?.y ?? lastCameraY
                    return hitY > cameraY + 0.25 ? .ceiling : nil
                }
            }

            private func syntheticFallbackHit(at point: CGPoint, mode: ARPlacementMode) -> SurfaceRaycastHit? {
                guard let ray = viewRay(from: point) else { return nil }

                switch mode {
                case .floor:
                    return nil
                case .wall:
                    let flatDirection = SIMD3<Float>(ray.direction.x, 0, ray.direction.z)
                    guard simd_length(flatDirection) > 0.2 else { return nil }

                    let distance: Float = 1.45
                    let position = ray.origin + ray.direction * distance
                    let normal = -simd_normalize(flatDirection)
                    let transform = wallAlignedTransform(position: position, normal: normal)
                    return SurfaceRaycastHit(
                        placementTransform: transform,
                        reticleTransform: transform,
                        quality: .estimated,
                        source: .syntheticFallback,
                        surfaceType: .wall,
                        placementMode: mode,
                        planeAnchorId: nil,
                        planeTransform: nil,
                        planeFeatures: nil
                    )
                case .ceiling:
                    guard ray.direction.y > 0.08 else { return nil }
                    let ceilingY = fallbackCeilingY()
                    let t = (ceilingY - ray.origin.y) / ray.direction.y
                    guard t > 0.2, t < 6.0 else { return nil }

                    let position = ray.origin + ray.direction * t
                    let transform = uprightTransform(at: SIMD4<Float>(position.x, position.y, position.z, 1))
                    return SurfaceRaycastHit(
                        placementTransform: transform,
                        reticleTransform: transform,
                        quality: .estimated,
                        source: .syntheticFallback,
                        surfaceType: .ceiling,
                        placementMode: mode,
                        planeAnchorId: nil,
                        planeTransform: nil,
                        planeFeatures: nil
                    )
                }
            }

            private func viewRay(from point: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? {
                guard let arView = arView else { return nil }
                let nearPoint = arView.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
                let farPoint = arView.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
                let origin = SIMD3<Float>(nearPoint.x, nearPoint.y, nearPoint.z)
                let far = SIMD3<Float>(farPoint.x, farPoint.y, farPoint.z)
                let direction = far - origin
                guard simd_length(direction) > 0.001 else { return nil }
                return (origin, simd_normalize(direction))
            }

            private func fallbackCeilingY() -> Float {
                let snapshot = surfacesLock.withLock { () -> (floor: Float?, ceilings: [Float]) in
                    let ceilingHeights = self.planeTypes.compactMap { entry -> Float? in
                        guard entry.value == .ceiling else { return nil }
                        return self.planeFeatures[entry.key]?.center.y
                    }
                    return (self.floorY, ceilingHeights)
                }

                if let knownCeiling = snapshot.ceilings.min() {
                    return knownCeiling
                }

                let cameraY = currentCameraPosition()?.y ?? lastCameraY
                if let floorY = snapshot.floor {
                    let commonCeilingY = floorY + 2.45
                    if commonCeilingY > cameraY + 0.45 {
                        return commonCeilingY
                    }
                }

                return cameraY + 1.25
            }

            private func resolvedSurfaceType(for result: ARRaycastResult) -> SurfaceType? {
                guard let plane = result.anchor as? ARPlaneAnchor else { return nil }
                if let cached = surfacesLock.withLock({ self.planeTypes[plane.identifier] }) {
                    return cached
                }

                let features = PlaneFeatures(plane)
                let verticals = surfacesLock.withLock {
                    self.planeFeatures.values.filter { $0.alignment == .vertical }
                }
                return SurfaceClassifier.classify(
                    plane: features,
                    floorY: surfacesLock.withLock { self.floorY },
                    cameraY: lastCameraY,
                    nearbyVerticals: verticals
                )
            }

            private func placementTransform(
                for result: ARRaycastResult,
                mode: ARPlacementMode,
                surfaceType: SurfaceType?
            ) -> simd_float4x4 {
                switch mode {
                case .wall:
                    return wallAlignedTransform(from: result)
                case .ceiling:
                    return uprightTransform(at: result.worldTransform.columns.3)
                case .floor:
                    return result.worldTransform
                }
            }

            private func wallAlignedTransform(from result: ARRaycastResult) -> simd_float4x4 {
                var position = result.worldTransform.columns.3
                var normal: SIMD3<Float>

                if let plane = result.anchor as? ARPlaneAnchor {
                    normal = PlaneFeatures(plane).normal
                } else {
                    let c1 = result.worldTransform.columns.1
                    normal = SIMD3<Float>(c1.x, c1.y, c1.z)
                }

                normal.y = 0
                if simd_length(normal) < 0.001 {
                    normal = SIMD3<Float>(0, 0, 1)
                } else {
                    normal = simd_normalize(normal)
                }

                if let cameraPos = currentCameraPosition() {
                    let delta = cameraPos - SIMD3<Float>(position.x, position.y, position.z)
                    if simd_length(delta) > 0.001 {
                        let toCamera = simd_normalize(delta)
                        if simd_dot(normal, toCamera) < 0 {
                            normal = -normal
                        }
                    }
                }

                position.x += normal.x * 0.025
                position.z += normal.z * 0.025

                return wallAlignedTransform(
                    position: SIMD3<Float>(position.x, position.y, position.z),
                    normal: normal
                )
            }

            private func wallAlignedTransform(position: SIMD3<Float>, normal inputNormal: SIMD3<Float>) -> simd_float4x4 {
                var normal = inputNormal
                normal.y = 0
                if simd_length(normal) < 0.001 {
                    normal = SIMD3<Float>(0, 0, 1)
                } else {
                    normal = simd_normalize(normal)
                }

                let up = SIMD3<Float>(0, 1, 0)
                let xAxis = simd_normalize(simd_cross(up, normal))
                return matrixFromBasis(
                    x: xAxis,
                    y: up,
                    z: normal,
                    position: position
                )
            }

            private func uprightTransform(at position4: SIMD4<Float>) -> simd_float4x4 {
                let position = SIMD3<Float>(position4.x, position4.y, position4.z)
                let up = SIMD3<Float>(0, 1, 0)
                var forward = SIMD3<Float>(0, 0, 1)

                if let cameraPos = currentCameraPosition() {
                    let flat = SIMD3<Float>(cameraPos.x - position.x, 0, cameraPos.z - position.z)
                    if simd_length(flat) > 0.001 {
                        forward = simd_normalize(flat)
                    }
                }

                let xAxis = simd_normalize(simd_cross(up, forward))
                return matrixFromBasis(x: xAxis, y: up, z: forward, position: position)
            }

            private func matrixFromBasis(
                x: SIMD3<Float>,
                y: SIMD3<Float>,
                z: SIMD3<Float>,
                position: SIMD3<Float>
            ) -> simd_float4x4 {
                simd_float4x4(
                    SIMD4<Float>(x.x, x.y, x.z, 0),
                    SIMD4<Float>(y.x, y.y, y.z, 0),
                    SIMD4<Float>(z.x, z.y, z.z, 0),
                    SIMD4<Float>(position.x, position.y, position.z, 1)
                )
            }

            private func currentCameraPosition() -> SIMD3<Float>? {
                guard let transform = arView?.session.currentFrame?.camera.transform else { return nil }
                let c = transform.columns.3
                return SIMD3<Float>(c.x, c.y, c.z)
            }

            private func surfaceAccepted(_ hit: SurfaceRaycastHit) -> Bool {
                guard let surfaceType = hit.surfaceType else {
                    return false
                }
                return hit.placementMode.acceptedSurfaceTypes.contains(surfaceType)
            }

            private func placementBlockedMessage(for hit: SurfaceRaycastHit, plant: Plant?) -> String? {
                if let plant,
                   hit.placementMode.needsPlantCompatibility,
                   !PlantPlacementCompatibility.supports(plant, mode: hit.placementMode) {
                    switch hit.placementMode {
                    case .wall:
                        return L10n.t("AR_PLACEMENT_INCOMPATIBLE_WALL")
                    case .ceiling:
                        return L10n.t("AR_PLACEMENT_INCOMPATIBLE_HANGING")
                    case .floor:
                        break
                    }
                }

                if !surfaceAccepted(hit) {
                    switch hit.placementMode {
                    case .floor:
                        return L10n.t("AR_PLACEMENT_SURFACE_NEEDS_FLOOR")
                    case .wall:
                        return L10n.t("AR_PLACEMENT_SURFACE_NEEDS_WALL")
                    case .ceiling:
                        return L10n.t("AR_PLACEMENT_SURFACE_NEEDS_HANGING_SUPPORT")
                    }
                }

                return nil
            }

            private func noSurfaceMessage(for mode: ARPlacementMode) -> String {
                switch mode {
                case .floor:
                    return L10n.t("AR_PLACEMENT_SURFACE_NEEDS_FLOOR")
                case .wall:
                    return L10n.t("AR_PLACEMENT_SURFACE_NEEDS_WALL")
                case .ceiling:
                    return L10n.t("AR_PLACEMENT_SURFACE_NEEDS_HANGING_SUPPORT")
                }
            }

            private func updatePlacementReliability(
                for hit: SurfaceRaycastHit,
                trackingNormal: Bool,
                time: TimeInterval
            ) -> PlacementReliability {
                let position = worldPosition(from: hit.placementTransform)
                let key = [
                    hit.placementMode.rawValue,
                    hit.surfaceType?.rawValue ?? "nil",
                    hit.source.rawValue,
                    hit.planeAnchorId?.uuidString ?? "no-plane"
                ].joined(separator: "|")
                let movedTooMuch: Bool
                if let previous = reticleLastPosition {
                    movedTooMuch = simd_distance(previous, position) > 0.04
                } else {
                    movedTooMuch = true
                }

                if key != reticleStabilityKey || movedTooMuch {
                    reticleStabilityKey = key
                    reticleStableSince = time
                }
                reticleLastPosition = position

                let stableDuration = max(0, time - (reticleStableSince ?? time))
                let area = hit.planeFeatures.map { $0.extentWidth * $0.extentDepth }
                let distance = currentCameraPosition().map { simd_distance($0, position) }
                let reliability = PlacementReliabilityScorer.evaluate(
                    source: hit.source,
                    trackingNormal: trackingNormal,
                    surfaceAccepted: surfaceAccepted(hit),
                    planeArea: area,
                    cameraDistance: distance,
                    stableDuration: stableDuration
                )
                currentReticleReliability = reliability
                return reliability
            }

            private func immediatePlacementReliability(for hit: SurfaceRaycastHit) -> PlacementReliability {
                let area = hit.planeFeatures.map { $0.extentWidth * $0.extentDepth }
                let position = worldPosition(from: hit.placementTransform)
                let distance = currentCameraPosition().map { simd_distance($0, position) }
                return PlacementReliabilityScorer.evaluate(
                    source: hit.source,
                    trackingNormal: true,
                    surfaceAccepted: surfaceAccepted(hit),
                    planeArea: area,
                    cameraDistance: distance,
                    stableDuration: PlacementReliabilityScorer.fullStabilityDuration
                )
            }

            private func resetReticleReliability() {
                currentReticleReliability = .unavailable
                reticleStabilityKey = nil
                reticleStableSince = nil
                reticleLastPosition = nil
            }

            private func placementReliabilityMessage(for reliability: PlacementReliability) -> String {
                switch reliability.reason {
                case .ready:
                    return ""
                case .trackingLimited:
                    return L10n.t("AR_ANCHOR_TRACKING_LIMITED")
                case .incompatibleSurface:
                    return L10n.t("AR_ANCHOR_CONFIDENCE_LOW")
                case .unstableSurface:
                    return L10n.t("AR_ANCHOR_SURFACE_UNSTABLE")
                case .lowConfidence:
                    return L10n.t("AR_ANCHOR_CONFIDENCE_LOW")
                }
            }

            private func persistedSurfaceAnchor(
                for hit: SurfaceRaycastHit,
                reliability: PlacementReliability
            ) -> PersistedSurfaceAnchor {
                let position = worldPosition(from: hit.placementTransform)
                return surfaceAnchorMetadata(
                    source: hit.source,
                    reliabilityScore: reliability.score,
                    normal: surfaceNormal(for: hit),
                    features: hit.planeFeatures,
                    planeTransform: hit.planeTransform,
                    position: position
                )
            }

            private func surfaceAnchorMetadata(
                source: SurfaceHitSource,
                reliabilityScore: Float,
                normal: SIMD3<Float>,
                features: PlaneFeatures?,
                planeTransform: simd_float4x4?,
                position: SIMD3<Float>
            ) -> PersistedSurfaceAnchor {
                let localOffset: [Float]? = planeTransform.map { transform in
                    let local = simd_inverse(transform) * SIMD4<Float>(position.x, position.y, position.z, 1)
                    return [local.x, local.y, local.z]
                }
                return PersistedSurfaceAnchor(
                    source: source.rawValue,
                    reliabilityScore: reliabilityScore,
                    normal: [normal.x, normal.y, normal.z],
                    center: features.map { [$0.center.x, $0.center.y, $0.center.z] },
                    extent: features.map { [$0.extentWidth, $0.extentDepth] },
                    localOffset: localOffset,
                    worldPosition: [position.x, position.y, position.z]
                )
            }

            private struct SurfacePlaneSnapshot {
                let anchor: ARPlaneAnchor
                let features: PlaneFeatures
                let type: SurfaceType
            }

            private func surfacePlaneSnapshots() -> [SurfacePlaneSnapshot] {
                surfacesLock.withLock {
                    self.planeAnchors.compactMap { id, anchor in
                        guard let features = self.planeFeatures[id],
                              let type = self.planeTypes[id] else {
                            return nil
                        }
                        return SurfacePlaneSnapshot(anchor: anchor, features: features, type: type)
                    }
                }
            }

            private func refinedTransformForPersistedSurface(
                _ transform: simd_float4x4,
                plant: PersistedPlant
            ) -> (transform: simd_float4x4, didRefine: Bool) {
                guard let surfaceAnchor = plant.surfaceAnchor,
                      let mode = ARPlacementMode.fromPersisted(plant.placementMode),
                      let match = bestMatchingPlane(for: surfaceAnchor, mode: mode, savedSurfaceType: plant.surfaceType) else {
                    return (transform, false)
                }

                let originalPosition = worldPosition(from: transform)
                let snappedPosition: SIMD3<Float>
                if let offset = surfaceAnchor.localOffset, offset.count >= 3 {
                    let world = match.anchor.transform * SIMD4<Float>(offset[0], offset[1], offset[2], 1)
                    snappedPosition = SIMD3<Float>(world.x, world.y, world.z)
                } else {
                    let normal = match.features.normal
                    let delta = originalPosition - match.features.center
                    snappedPosition = originalPosition - normal * simd_dot(delta, normal)
                }

                var refined: simd_float4x4
                switch mode {
                case .wall:
                    var normal = match.features.normal
                    if let camera = currentCameraPosition() {
                        let toCamera = camera - snappedPosition
                        if simd_length(toCamera) > 0.001,
                           simd_dot(normal, simd_normalize(toCamera)) < 0 {
                            normal = -normal
                        }
                    }
                    refined = wallAlignedTransform(position: snappedPosition + normal * 0.025, normal: normal)
                case .ceiling:
                    refined = uprightTransform(at: SIMD4<Float>(snappedPosition.x, snappedPosition.y, snappedPosition.z, 1))
                case .floor:
                    refined = transform
                    refined.columns.3 = SIMD4<Float>(snappedPosition.x, snappedPosition.y, snappedPosition.z, 1)
                }

                AppLog.gardenLoad.notice("""
                    surfaceRefine plant=\(plant.plantName, privacy: .public) \
                    mode=\(mode.rawValue, privacy: .public) \
                    savedSource=\(surfaceAnchor.source, privacy: .public) \
                    targetSurface=\(match.type.rawValue, privacy: .public) \
                    delta=\(simd_distance(originalPosition, snappedPosition), format: .fixed(precision: 3), privacy: .public)
                    """)
                return (refined, true)
            }

            private func bestMatchingPlane(
                for surfaceAnchor: PersistedSurfaceAnchor,
                mode: ARPlacementMode,
                savedSurfaceType: String?
            ) -> SurfacePlaneSnapshot? {
                let savedPosition = vector3(from: surfaceAnchor.worldPosition)
                let savedCenter = surfaceAnchor.center.flatMap(vector3(from:))
                let savedNormal = surfaceAnchor.normal.count >= 3
                    ? simd_normalize(SIMD3<Float>(surfaceAnchor.normal[0], surfaceAnchor.normal[1], surfaceAnchor.normal[2]))
                    : nil
                let preferredType = savedSurfaceType.flatMap(SurfaceType.init(rawValue:))
                let candidates = surfacePlaneSnapshots().filter { snapshot in
                    mode.acceptedSurfaceTypes.contains(snapshot.type)
                        || (preferredType != nil && snapshot.type == preferredType)
                }

                return candidates.min { lhs, rhs in
                    surfacePlaneMatchScore(lhs, savedPosition: savedPosition, savedCenter: savedCenter, savedNormal: savedNormal, preferredType: preferredType)
                        < surfacePlaneMatchScore(rhs, savedPosition: savedPosition, savedCenter: savedCenter, savedNormal: savedNormal, preferredType: preferredType)
                }.flatMap { best in
                    let score = surfacePlaneMatchScore(best, savedPosition: savedPosition, savedCenter: savedCenter, savedNormal: savedNormal, preferredType: preferredType)
                    return score < 1.25 ? best : nil
                }
            }

            private func surfacePlaneMatchScore(
                _ snapshot: SurfacePlaneSnapshot,
                savedPosition: SIMD3<Float>?,
                savedCenter: SIMD3<Float>?,
                savedNormal: SIMD3<Float>?,
                preferredType: SurfaceType?
            ) -> Float {
                var score: Float = 0
                if let savedCenter {
                    score += min(simd_distance(snapshot.features.center, savedCenter), 2.0)
                } else if let savedPosition {
                    let planeDistance = abs(simd_dot(savedPosition - snapshot.features.center, snapshot.features.normal))
                    score += min(planeDistance * 4, 1.2)
                    score += min(simd_distance(snapshot.features.center, savedPosition) * 0.12, 0.5)
                }
                if let savedNormal {
                    let dot = abs(simd_dot(snapshot.features.normal, savedNormal))
                    score += (1 - min(max(dot, 0), 1)) * 0.8
                }
                if let preferredType, snapshot.type != preferredType {
                    score += 0.25
                }
                return score
            }

            private func vector3(from values: [Float]?) -> SIMD3<Float>? {
                guard let values, values.count >= 3 else { return nil }
                return SIMD3<Float>(values[0], values[1], values[2])
            }

            private func surfaceNormal(for hit: SurfaceRaycastHit) -> SIMD3<Float> {
                if let normal = hit.planeFeatures?.normal, simd_length(normal) > 0.001 {
                    return normal
                }
                switch hit.placementMode {
                case .wall:
                    let z = hit.placementTransform.columns.2
                    let normal = SIMD3<Float>(z.x, z.y, z.z)
                    return simd_length(normal) > 0.001 ? simd_normalize(normal) : SIMD3<Float>(0, 0, 1)
                case .ceiling:
                    return SIMD3<Float>(0, -1, 0)
                case .floor:
                    return SIMD3<Float>(0, 1, 0)
                }
            }

            private func worldPosition(from transform: simd_float4x4) -> SIMD3<Float> {
                SIMD3<Float>(
                    transform.columns.3.x,
                    transform.columns.3.y,
                    transform.columns.3.z
                )
            }

            private func pushPlacementFeedback(_ message: String) {
                DispatchQueue.main.async { [weak self] in
                    withAnimation(.easeOut(duration: 0.2)) {
                        self?.parentProps?.placementFeedback = message
                    }
                }
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }

            func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
                guard let arView = arView, let reticle = reticleNode else { return }

                // Refresh the cached camera Y used by SurfaceClassifier.
                // Light estimation is kept as an internal auto-placement
                // signal only; the HUD no longer displays lux.
                if let frame = arView.session.currentFrame {
                    let rawLux = frame.lightEstimate?.ambientIntensity ?? 0
                    let lux = rawLux.isFinite ? Int(rawLux) : 0
                    let camCol = frame.camera.transform.columns.3
                    lastCameraY = camCol.y
                    if abs(lux - (parentProps?.currentLux ?? 0)) >= 25 {
                        DispatchQueue.main.async { [weak self] in
                            self?.parentProps?.currentLux = lux
                        }
                    }
                    // LOD adaptatif : ré-évalue le light/heavy de chaque plante ~4 Hz
                    // (thermique + budget + distance). Calcul + swaps sur le main thread.
                    if time - lastLODEvalAt >= PlantLODPolicy.evalInterval {
                        lastLODEvalAt = time
                        let camPos = SIMD3<Float>(camCol.x, camCol.y, camCol.z)
                        DispatchQueue.main.async { [weak self] in self?.evaluateLOD(cameraPosition: camPos) }
                    }
                }

                if parentProps?.isShareCameraMode == true {
                    reticle.opacity = 0
                    lastReticleHit = nil
                    lastReticleTransform = nil
                    resetReticleReliability()
                    return
                }

                let center = cachedViewCenter
                let trackingNormal: Bool = {
                    if let trackingState = arView.session.currentFrame?.camera.trackingState,
                       case .normal = trackingState {
                        return true
                    }
                    return false
                }()

                let now = CACurrentMediaTime()
                if now - lastAutoPlaceLogTime > 1.5 {
                    lastAutoPlaceLogTime = now
                    let trackingStateDesc = arView.session.currentFrame?.camera.trackingState.logDescription ?? "nil"
                    let propsDesc = parentProps == nil ? "nil" : "non-nil"
                    let modeDesc = parentProps?.mode == .create ? "create" : "reopen"
                    let mapIdDesc = parentProps?.measurementWorldMapId ?? "nil"
                    let boundaryCount = parentProps?.boundaryPoints.count ?? 0
                    let plantsCount = parentProps?.plantsToAutoPlace.count ?? 0
                    AppLog.plants.notice("🤖 [AUTOPLACE CHECK] props=\(propsDesc, privacy: .public) mode=\(modeDesc, privacy: .public) mapId=\(mapIdDesc, privacy: .public) boundaryPoints=\(boundaryCount, privacy: .public) didAutoPlace=\(self.didAutoPlace, privacy: .public) isWaiting=\(self.isWaitingForWorldMapLoad, privacy: .public) trackingState=\(trackingStateDesc, privacy: .public) plantsToAutoPlace=\(plantsCount, privacy: .public) trackingNormal=\(trackingNormal, privacy: .public)")
                }

                let requestedMode = activePlacementMode()
                let currentHit = raycastHit(at: center, mode: requestedMode)

                lastReticleHit = currentHit
                lastReticleTransform = currentHit?.placementTransform
                if let hit = currentHit {
                    let t = hit.placementTransform
                    let newQuality = hit.quality
                    let newSurfaceType = hit.surfaceType
                    let acceptsCurrentSurface = surfaceAccepted(hit)
                    let reliability = updatePlacementReliability(
                        for: hit,
                        trackingNormal: trackingNormal,
                        time: time
                    )

                    reticle.simdTransform = hit.reticleTransform
                    reticle.opacity = (newQuality == .geometry) ? 1.0 : 0.6

                    // 🤖 AI Auto-placement: Place instantly as soon as a surface is found,
                    // without requiring the user to aim specifically at the floor or wait for stability.
                    let currentProps = parentProps
                    let acceptsEstimatedSurface = currentProps.map { self.acceptsEstimatedAutoPlace(for: $0) } ?? false
                    let hasAutoPlaceSurface = acceptsCurrentSurface
                        && (newQuality == .geometry || (newQuality == .estimated && acceptsEstimatedSurface))
                    
                    let timeSinceLoad = CACurrentMediaTime() - worldMapLoadedAt
                    
                    if !didAutoPlace,
                       !isWaitingForWorldMapLoad,
                       trackingNormal,
                       timeSinceLoad > 0.5,
                       hasAutoPlaceSurface,
                       let props = currentProps,
                       props.mode == .create,
                       !props.plantsToAutoPlace.isEmpty {
                        didAutoPlace = true
                        let transform = t
                        DispatchQueue.main.async { [weak self] in
                            self?.autoPlaceAIPlants(at: transform)
                        }
                    }

                    // #169 follow-up — bubble the diagnostic state up so the
                    // coaching banner reflects which condition is currently
                    // blocking the trigger. Only push on transition to keep
                    // SwiftUI re-renders cheap (was 60 fps churn otherwise).
                    if !didAutoPlace,
                       let props = parentProps,
                       props.mode == .create,
                       !props.plantsToAutoPlace.isEmpty {
                        let newCoaching = self.computeCoachingState(
                            props: props,
                            reticleTransform: t,
                            reticleQuality: newQuality,
                            stableFrames: stablePlaneFrameCount,
                            threshold: stablePlaneThreshold
                        )
                        if newCoaching != lastAutoPlaceCoaching {
                            lastAutoPlaceCoaching = newCoaching
                            DispatchQueue.main.async { [weak self] in
                                self?.parentProps?.autoPlaceCoaching = newCoaching
                            }
                        }
                    }

                    // Update color only on transition (avoid per-frame material churn).
                    //
                    // Issue #186 — when the reticle sits on a classified
                    // plane, the colour reflects the surface type (orange
                    // wall, green table, …). Falls back to the prior
                    // green/amber logic for unclassified hits.
                    let transitionKey = "\(requestedMode.rawValue)|\(newQuality.rawValue)|\(newSurfaceType?.rawValue ?? "")|\(acceptsCurrentSurface)|\(reliability.level.rawValue)|\(reliability.reason.rawValue)"
                    if transitionKey != lastReticleColorKey {
                        lastReticleColorKey = transitionKey
                        reticleQuality = newQuality
                        let color: UIColor
                        switch reliability.reason {
                        case .ready:
                            color = acceptsCurrentSurface
                                ? (newSurfaceType?.debugColor ?? UIColor(hex: "#2BEE79"))
                                : UIColor(hex: "#FF4B4B")
                        case .unstableSurface, .lowConfidence:
                            color = UIColor(hex: "#FFB020")
                        case .trackingLimited, .incompatibleSurface:
                            color = UIColor(hex: "#FF4B4B")
                        }
                        reticle.geometry?.firstMaterial?.diffuse.contents = color
                    }
                } else {
                    reticle.opacity = 0
                    resetReticleReliability()
                    // Reset stability counter if we lose the plane
                    if !didAutoPlace { stablePlaneFrameCount = 0 }

                    // #169 follow-up — no raycast hit at all : show the
                    // weakest diagnostic state so the banner stays
                    // honest instead of frozen on the last good value.
                    if !didAutoPlace,
                       let props = parentProps,
                       props.mode == .create,
                       !props.plantsToAutoPlace.isEmpty {
                        let newCoaching: GardenARPlacementView.AutoPlaceCoachingState =
                            (self.autoPlaceFloorY(for: props) == nil) ? .analyzing : .adjustReticle
                        if newCoaching != lastAutoPlaceCoaching {
                            lastAutoPlaceCoaching = newCoaching
                            DispatchQueue.main.async { [weak self] in
                                self?.parentProps?.autoPlaceCoaching = newCoaching
                            }
                        }
                    }
                }
            }

            /// #169 follow-up — pure mapping from the trigger conditions to
            /// the diagnostic state shown in the coaching banner. Called
            /// from `renderer(_:updateAtTime:)` when at least the reticle
            /// has a transform ; the no-transform case is handled inline.
            private func acceptsEstimatedAutoPlace(for props: GardenARPlacementContainerView) -> Bool {
                props.wizard.scanMethod == ScanMethod.roomScan.rawValue
                    || (props.measurementWorldMapId != nil && props.boundaryPoints.count >= 3)
            }

            private func measurementFloorY(for props: GardenARPlacementContainerView) -> Float? {
                guard !props.boundaryPoints.isEmpty else { return nil }
                let total = props.boundaryPoints.reduce(Float(0)) { $0 + $1.y }
                return total / Float(props.boundaryPoints.count)
            }

            private func autoPlaceFloorY(for props: GardenARPlacementContainerView) -> Float? {
                detectedFloorY() ?? measurementFloorY(for: props)
            }

            private func computeCoachingState(
                props: GardenARPlacementContainerView,
                reticleTransform t: simd_float4x4,
                reticleQuality: ReticleQuality,
                stableFrames: Int,
                threshold: Int
            ) -> GardenARPlacementView.AutoPlaceCoachingState {
                guard let floorY = self.autoPlaceFloorY(for: props) else {
                    return .analyzing
                }
                let hasUsableSurface = reticleQuality == .geometry
                    || (reticleQuality == .estimated && acceptsEstimatedAutoPlace(for: props))
                guard hasUsableSurface else {
                    return .adjustReticle
                }
                let deltaM = t.columns.3.y - floorY
                if deltaM > 0.20 {
                    // Round to nearest 5 cm so the banner doesn't flicker
                    // on each cm of hand-shake. Min 5 cm to avoid
                    // displaying "0 cm trop haut" when delta is in
                    // (0.20, 0.025] m.
                    let rounded = max(5, Int((deltaM * 100 / 5).rounded()) * 5)
                    return .pointLower(deltaCm: rounded)
                }
                if deltaM < -0.20 {
                    // Reticle BELOW the floor — pathological (would
                    // mean a plane lower than the detected floor was
                    // hit). Fall back to a generic message.
                    return .adjustReticle
                }
                return .stabilizing(progress: min(stableFrames, threshold), threshold: threshold)
            }

            // MARK: - 🤖 AI Auto-Placement

            /// Automatically places all AI-selected plants in a style-aware layout.
            private func autoPlaceAIPlants(at centerTransform: simd_float4x4?) {
                guard let props = parentProps else { return }
                // Don't pre-filter on modelURL — getModelURL() has fallback
                // logic that resolves from the plant name alone (e.g.
                // "Monstera.usdz"). Plants without an explicit modelURL are
                // still downloadable. The download loop below handles failures
                // gracefully (async download → bundle fallback → skip).
                let plants = props.plantsToAutoPlace
                guard !plants.isEmpty else { return }

                props.isAutoPlacing = true
                // Reset progress counters
                props.autoPlacePlaced = 0
                props.autoPlaceTotal = 0
                props.autoPlaceCurrentName = ""

                let style = props.wizard.style.lowercased()
                let lux = props.currentLux
                let boundaryPoints = props.boundaryPoints

                // ── Résolution du Y de placement ────────────────────────────
                // Priorité : floor ARKit détecté > moyenne Y boundary > Y reticle > 0.
                // Bug fix #198: l'ancien code utilisait Y=0 (origine de session,
                // hauteur poitrine) quand le sol n'était pas encore détecté.
                let placementY: Float
                if let floorY = detectedFloorY() {
                    placementY = floorY
                } else if !boundaryPoints.isEmpty {
                    placementY = boundaryPoints.reduce(0) { $0 + $1.y } / Float(boundaryPoints.count)
                } else if let t = centerTransform {
                    placementY = autoPlaceFloorY(for: props) ?? t.columns.3.y
                } else {
                    placementY = 0
                }

                // ── Calcul des positions world-space absolues ─────────────────
                // Bug fix #198 : calculateWorldPositions renvoie des coordonnées
                // ARKit ABSOLUES — plus d'offset à ajouter (l'ancien
                // calculateBoundaryLayout retournait des offsets relatifs au
                // centroïde, mais autoPlaceAIPlants ajoutait ensuite centerX/Z
                // = le centroïde → double centroïde → plantes hors boundary).
                let worldPositions = calculateWorldPositions(
                    plants: plants,
                    style: style,
                    lux: lux,
                    boundaryPoints: boundaryPoints,
                    centerTransform: centerTransform,
                    placementY: placementY
                )

                Task { [weak self] in
                    guard let self = self else { return }

                    // Download all models in parallel
                    var downloadedModels: [(plant: Plant, url: URL, worldPos: SIMD3<Float>)] = []

                    await withTaskGroup(of: (Plant, URL?, SIMD3<Float>)?.self) { group in
                        for (index, plant) in plants.enumerated() {
                            let pos = index < worldPositions.count
                                ? worldPositions[index]
                                : SIMD3<Float>(
                                    worldPositions.first?.x ?? 0,
                                    placementY,
                                    worldPositions.first?.z ?? 0
                                  )
                            group.addTask {
                                do {
                                    let url = try await plant.getModelURL(forceDownload: false)
                                    return (plant, url, pos)
                                } catch {
                                    // Try bundle fallback
                                    let fallback = plant.bundleModelURL
                                    if fallback == nil {
                                        AppLog.plants.warning(
                                            "autoPlace: no model for plant=\(plant.name, privacy: .public) id=\(plant.id, privacy: .public) modelURL=\(plant.modelURL ?? "<nil>", privacy: .public) error=\(String(describing: error), privacy: .public)"
                                        )
                                    }
                                    return (plant, fallback, pos)
                                }
                            }
                        }

                        for await result in group {
                            if let result = result, let url = result.1 {
                                downloadedModels.append((plant: result.0, url: url, worldPos: result.2))
                            }
                        }
                    }

                    // ── Staggered placement ─────────────────────────────────
                    // Place models one-by-one with a short delay between each
                    // so the main thread has breathing room for SceneKit's USDZ
                    // loading + halo cache + rendering. This prevents the UI
                    // freeze that occurred when all anchors were added in one
                    // synchronous burst.
                    await MainActor.run {
                        guard !downloadedModels.isEmpty else {
                            // All plants failed to resolve a model — tell the user
                            // instead of silently dismissing the overlay.
                            props.isAutoPlacing = false
                            props.autoPlacePlaced = 0
                            props.autoPlaceTotal = 0
                            props.autoPlaceCurrentName = ""
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                props.autoPlaceToast = "Aucun modèle 3D disponible — ajoutez vos plantes manuellement"
                            }
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            return
                        }

                        self.saveStateForUndo()

                        // Initialize progress with total count
                        props.autoPlaceTotal = downloadedModels.count
                        props.autoPlacePlaced = 0

                        // Re-fetch floor Y at placement time so any plane
                        // discovered during model download is taken into account.
                        let finalY: Float = self.detectedFloorY() ?? placementY

                        // Stagger: place one plant every ~250ms to let the main
                        // thread breathe between USDZ loads. Each dispatch gives
                        // SceneKit a full run-loop cycle to finish loading the
                        // previous model before the next anchor is added.
                        let staggerDelay: TimeInterval = 0.25
                        let totalCount = downloadedModels.count
                        let skipped = plants.count - totalCount

                        for (idx, item) in downloadedModels.enumerated() {
                            let delay = staggerDelay * Double(idx)
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                                guard let self = self else { return }

                                // Update progress UI
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    props.autoPlaceCurrentName = item.plant.name
                                }

                                // Build a rigid identity-rotation transform at the
                                // world-space position computed by calculateWorldPositions.
                                // No centerX/centerZ offset here — positions are absolute.
                                var transform = centerTransform ?? matrix_identity_float4x4
                                if centerTransform == nil {
                                    transform.columns.0 = [1, 0, 0, 0]
                                    transform.columns.1 = [0, 1, 0, 0]
                                    transform.columns.2 = [0, 0, 1, 0]
                                }
                                transform.columns.3.x = item.worldPos.x
                                transform.columns.3.y = finalY
                                transform.columns.3.z = item.worldPos.z

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
                                    surfaceType: SurfaceType.floor.rawValue,
                                    surfaceHeight: finalY,
                                    placementMode: .floor,
                                    autoSelect: false,   // batch — no halo flicker
                                    hasHeavy: item.plant.hasHeavy == true
                                )

                                // Light haptic per plant
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                                // Update placed counter
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    props.autoPlacePlaced = idx + 1
                                }

                                // Final plant → dismiss overlay after a short beat
                                if idx == totalCount - 1 {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        props.isAutoPlacing = false
                                        props.autoPlaceCurrentName = ""
                                        let toastText: String
                                        if skipped > 0 {
                                            toastText = "\(totalCount) plantes placées (\(skipped) sans modèle) — Déplacez-les !"
                                        } else {
                                            toastText = "\(totalCount) plantes placées — Déplacez-les !"
                                        }
                                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                            props.autoPlaceToast = toastText
                                        }
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            /// Retourne des positions ABSOLUES en world space (SIMD3<Float>),
            /// prêtes à être utilisées directement dans un simd_float4x4 transform.
            ///
            /// Bug fix #198 : les anciennes méthodes retournaient des offsets 2D
            /// relatifs au centroïde, et autoPlaceAIPlants les additionnait au
            /// centroïde → double centroïde → toutes les plantes hors boundary.
            ///
            /// Nouveautés :
            ///  - Prise en compte du lux (currentLux) pour orienter les plantes
            ///    héliophiles vers la zone exposée de la boundary.
            ///  - Poisson-disk sampling avec distance minimale adaptative
            ///    = sqrt(area / count) × 0.65 pour une distribution harmonieuse.
            private func calculateWorldPositions(
                plants: [Plant],
                style: String,
                lux: Int,
                boundaryPoints: [SIMD3<Float>],
                centerTransform: simd_float4x4?,
                placementY: Float
            ) -> [SIMD3<Float>] {
                let count = plants.count
                guard count > 0 else { return [] }

                if count == 1 {
                    let cx = boundaryPoints.isEmpty
                        ? (centerTransform?.columns.3.x ?? 0)
                        : boundaryPoints.reduce(0) { $0 + $1.x } / Float(boundaryPoints.count)
                    let cz = boundaryPoints.isEmpty
                        ? (centerTransform?.columns.3.z ?? 0)
                        : boundaryPoints.reduce(0) { $0 + $1.z } / Float(boundaryPoints.count)
                    return [SIMD3<Float>(cx, placementY, cz)]
                }

                // Chemin avec boundary → Poisson-disk world space
                if boundaryPoints.count >= 3 {
                    return calculateBoundaryWorldPositions(
                        plants: plants,
                        lux: lux,
                        boundaryPoints: boundaryPoints,
                        placementY: placementY
                    )
                }

                // Chemin sans boundary → offsets style autour du reticle/origine
                let originX = centerTransform?.columns.3.x ?? 0
                let originZ = centerTransform?.columns.3.z ?? 0
                let spacing: Float = 0.7

                let offsets: [SIMD2<Float>]
                if style.contains("zen") || style.contains("japonais") {
                    offsets = calculateZenLayout(count: count, spacing: spacing)
                } else if style.contains("moderne") || style.contains("minimaliste") {
                    offsets = calculateGridLayout(count: count, spacing: spacing)
                } else if style.contains("champêtre") || style.contains("sauvage") {
                    offsets = calculateWildLayout(count: count, spacing: spacing)
                } else {
                    offsets = calculateCircleLayout(count: count, spacing: spacing)
                }

                return offsets.map { off in
                    SIMD3<Float>(originX + off.x, placementY, originZ + off.y)
                }
            }

            /// Calculate layout positions based on garden style.
            /// Returns array of (x, z) offsets from center.
            /// Utilisé uniquement pour le chemin sans boundary (mode reticle).
            private func calculateLayoutPositions(count: Int, style: String, boundaryPoints: [SIMD3<Float>]) -> [SIMD2<Float>] {
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
            
            /// Poisson-disk sampling dans le polygone de boundary.
            ///
            /// Bug fix #198 : retourne des positions ABSOLUES en world space ARKit
            /// (x, placementY, z) — pas d'offsets relatifs au centroïde.
            /// L'ancienne calculateBoundaryLayout retournait `point - centroid`,
            /// et autoPlaceAIPlants ajoutait centerX/Z (= le centroïde) → résultat
            /// à 2 × centroïde, hors boundary.
            ///
            /// Nouveautés :
            ///  - Distance minimale adaptative = sqrt(area / count) × 0.65
            ///    (s'adapte à la taille réelle du jardin mesuré).
            ///  - Prise en compte du lux : plantes héliophiles placées en priorité
            ///    dans la zone la plus exposée de la boundary (Z max en hémisphère N).
            ///  - Fallback cercle autour du centroïde si le sampling échoue.
            private func calculateBoundaryWorldPositions(
                plants: [Plant],
                lux: Int,
                boundaryPoints: [SIMD3<Float>],
                placementY: Float
            ) -> [SIMD3<Float>] {
                let count = plants.count
                let polygon2D = boundaryPoints.map { SIMD2<Float>($0.x, $0.z) }

                // ── Centroïde world space ──────────────────────────────────────
                let centroidX = polygon2D.reduce(0) { $0 + $1.x } / Float(polygon2D.count)
                let centroidZ = polygon2D.reduce(0) { $0 + $1.y } / Float(polygon2D.count)

                // ── Surface (shoelace) ─────────────────────────────────────────
                var area: Float = 0
                let n = polygon2D.count
                for i in 0..<n {
                    let j = (i + 1) % n
                    area += polygon2D[i].x * polygon2D[j].y
                    area -= polygon2D[j].x * polygon2D[i].y
                }
                area = abs(area) / 2.0

                // ── Distance minimale Poisson-disk ─────────────────────────────
                // Chaque plante occupe environ area/count m² → rayon idéal ×0.65
                // pour garder de l'espace visuel entre modèles 3D.
                let idealSpacing = (area > 0 && count > 0)
                    ? max(0.35, sqrt(area / Float(count)) * 0.65)
                    : 0.7

                // ── Bounding box ───────────────────────────────────────────────
                let minX = polygon2D.map { $0.x }.min() ?? (centroidX - 1)
                let maxX = polygon2D.map { $0.x }.max() ?? (centroidX + 1)
                let minZ = polygon2D.map { $0.y }.min() ?? (centroidZ - 1)
                let maxZ = polygon2D.map { $0.y }.max() ?? (centroidZ + 1)
                let midZ  = (minZ + maxZ) / 2

                // ── Tri des plantes par besoin en lumière ──────────────────────
                // Valeur : 2 = plein soleil, 1 = mi-ombre, 0 = ombre.
                // On utilise le nom comme heuristique (pas de modèle Plant dédié).
                func lightNeed(_ plant: Plant) -> Int {
                    let name = plant.name.lowercased()
                    let sunKw = ["soleil", "cactus", "succulente", "lavande", "rosier",
                                 "tomate", "basilic", "géranium", "pelargonium",
                                 "agave", "yucca", "bougainvillée", "palm", "olivier"]
                    let shdKw = ["fougère", "hostas", "begonia", "impatiens",
                                 "monstera", "pothos", "alocasia", "ficus",
                                 "calathea", "dieffenbachia", "broméliacée", "ivy",
                                 "lierre", "spathiphyllum", "zamioculcas"]
                    if sunKw.contains(where: { name.contains($0) }) { return 2 }
                    if shdKw.contains(where: { name.contains($0) }) { return 0 }
                    return 1
                }

                // Lux élevé (>500) : plantes soleil en zones exposées (Z max),
                // ombre en zones intérieures (Z min). Inversé pour lux faible.
                let sortedPlants = plants.sorted { a, b in
                    lux > 500
                        ? lightNeed(a) > lightNeed(b)
                        : lightNeed(a) < lightNeed(b)
                }

                // ── Poisson-disk sampling ──────────────────────────────────────
                var worldPositions: [SIMD2<Float>] = []
                var minDist = idealSpacing
                var attempts = 0
                let maxAttempts = max(3000, count * 600)

                while worldPositions.count < count && attempts < maxAttempts {
                    let idx = worldPositions.count
                    let need = idx < sortedPlants.count ? lightNeed(sortedPlants[idx]) : 1

                    // Zone Z de tirage selon besoin en lumière
                    let zLo: Float
                    let zHi: Float
                    if lux > 500 {
                        switch need {
                        case 2:  (zLo, zHi) = (midZ, maxZ)        // plein soleil → zone exposée
                        case 0:  (zLo, zHi) = (minZ, midZ)        // ombre → zone intérieure
                        default: (zLo, zHi) = (minZ, maxZ)        // mi-ombre → toute la zone
                        }
                    } else {
                        switch need {
                        case 0:  (zLo, zHi) = (minZ, maxZ)        // ombre → partout (lux faible = bien)
                        case 2:  (zLo, zHi) = (centroidZ - 0.3, centroidZ + 0.3) // soleil → centre
                        default: (zLo, zHi) = (minZ, maxZ)
                        }
                    }

                    let rx = Float.random(in: minX...maxX)
                    let rz = Float.random(in: max(minZ, zLo)...min(maxZ, zHi))
                    let candidate = SIMD2<Float>(rx, rz)

                    if pointInPolygon(candidate, polygon: polygon2D) {
                        let tooClose = worldPositions.contains {
                            simd_distance($0, candidate) < minDist
                        }
                        if !tooClose {
                            worldPositions.append(candidate)
                        }
                    }

                    attempts += 1
                    // Relaxation progressive : −5% toutes les 200 tentatives.
                    if attempts % 200 == 0 { minDist *= 0.95 }
                }

                // Fallback : compléter avec un cercle autour du centroïde
                // si le sampling ne remplit pas tous les slots.
                if worldPositions.count < count {
                    let missing = count - worldPositions.count
                    let fallbackR: Float = max(0.3, idealSpacing * 0.5)
                    for i in 0..<missing {
                        let angle = (2.0 * Float.pi * Float(i)) / Float(missing)
                        worldPositions.append(SIMD2<Float>(
                            centroidX + cos(angle) * fallbackR,
                            centroidZ + sin(angle) * fallbackR
                        ))
                    }
                    AppLog.plants.notice(
                        "autoPlace: boundary sampling added \(missing, privacy: .public) fallback positions"
                    )
                }

                AppLog.plants.notice(
                    "autoPlace: \(worldPositions.count, privacy: .public) positions, area=\(String(format: "%.2f", area), privacy: .public)m² minDist=\(String(format: "%.2f", idealSpacing), privacy: .public)m lux=\(lux, privacy: .public)"
                )

                // Retourner en SIMD3 world space absolu (x, Y_sol, z).
                // Bug fix #198 : pas d'offset centroïde — positions absolues.
                return worldPositions.map { SIMD3<Float>($0.x, placementY, $0.y) }
            }

            // calculateBoundaryLayout conservé pour compatibilité (appelé
            // uniquement depuis calculateLayoutPositions, qui lui-même n'est
            // plus appelé depuis autoPlaceAIPlants — il reste disponible pour
            // d'éventuels futurs usages).
            private func calculateBoundaryLayout(count: Int, boundaryPoints: [SIMD3<Float>]) -> [SIMD2<Float>] {
                var points: [SIMD2<Float>] = []
                let polygon2D = boundaryPoints.map { SIMD2<Float>($0.x, $0.z) }
                
                // Centroid
                let centroidX = polygon2D.reduce(0) { $0 + $1.x } / Float(polygon2D.count)
                let centroidY = polygon2D.reduce(0) { $0 + $1.y } / Float(polygon2D.count)
                let centroid = SIMD2<Float>(centroidX, centroidY)
                
                // Bounding Box
                let minX = polygon2D.map { $0.x }.min() ?? 0
                let maxX = polygon2D.map { $0.x }.max() ?? 0
                let minY = polygon2D.map { $0.y }.min() ?? 0
                let maxY = polygon2D.map { $0.y }.max() ?? 0
                
                var minDistance: Float = 0.7
                var attempts = 0
                
                while points.count < count && attempts < 2000 {
                    let rx = Float.random(in: minX...maxX)
                    let ry = Float.random(in: minY...maxY)
                    let candidate = SIMD2<Float>(rx, ry)
                    
                    if pointInPolygon(candidate, polygon: polygon2D) {
                        let tooClose = points.contains { simd_distance($0, candidate) < minDistance }
                        if !tooClose {
                            points.append(candidate)
                        }
                    }
                    
                    attempts += 1
                    if attempts % 100 == 0 { minDistance *= 0.9 }
                }
                
                // Return offsets relative to centroid
                return points.map { $0 - centroid }
            }

            private func pointInPolygon(_ p: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Bool {
                guard polygon.count >= 3 else { return false }
                var inside = false
                var j = polygon.count - 1
                for i in 0..<polygon.count {
                    let pi = polygon[i]
                    let pj = polygon[j]
                    if ((pi.y > p.y) != (pj.y > p.y)) &&
                       (p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x) {
                        inside.toggle()
                    }
                    j = i
                }
                return inside
            }


            /// Returns the Y of the largest detected horizontal plane (the floor).
            /// Falls back to nil if no horizontal planes are detected yet.
            /// Used to classify a plant as `floor` vs `elevated` independently
            /// of the session's Y=0 origin (which depends on where the user
            /// held the phone at session start, not on the actual floor).
            /// Two-tier raycast that prefers a real detected plane
            /// (.existingPlaneGeometry — surveyed surface, reliable) over
            /// ARKit's feature-point guess (.estimatedPlane). When the
            /// estimated fallback fires, we lock Y to detectedFloorY() because
            /// the estimated Y can drift 10-30 cm in low-texture / low-light
            /// areas (cf audit AR finding Y-4). XZ from the estimate is kept
            /// since the user's intent is captured by the screen position.
            ///
            /// Returns nil if no surface at all is detected — callers should
            /// refuse the action (drag, tap-teleport, boundary point) rather
            /// than fall back to a stale value.
            @MainActor
            private func resolvedFloorRaycast(at point: CGPoint) -> simd_float3? {
                guard let arView = arView else { return nil }

                if let q = arView.raycastQuery(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal),
                   let r = arView.session.raycast(q).first {
                    let c = r.worldTransform.columns.3
                    return SIMD3<Float>(c.x, c.y, c.z)
                }
                if let q = arView.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .horizontal),
                   let r = arView.session.raycast(q).first,
                   let floorY = detectedFloorY() {
                    let c = r.worldTransform.columns.3
                    return SIMD3<Float>(c.x, floorY, c.z)
                }
                return nil
            }

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

                    // Prefer explicit multi-surface metadata captured when
                    // the plant was placed or dragged. Legacy nodes fall back
                    // to the old floor/elevated heuristic.
                    let inferredSurfaceType: String
                    if let floorY = floorY {
                        inferredSurfaceType = (worldPos.y - floorY) > Self.elevationThresholdMeters ? "elevated" : "floor"
                    } else {
                        inferredSurfaceType = "floor"
                    }
                    let surfaceType = node.arboreSurfaceType ?? inferredSurfaceType
                    let placementMode = node.arborePlacementMode
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
                        mode=\(placementMode ?? "nil", privacy: .public) \
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
                        surfaceHeight: surfaceHeight,
                        placementMode: placementMode,
                        surfaceAnchor: node.arboreSurfaceAnchor,
                        hasHeavy: node.arboreHasHeavy
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
                        let measurementsForSave = self.measurementsForSave(id: tempID, props: props)
                        
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
                                            thumbnailKey: props.thumbnailKey,
                                            measurements: measurementsForSave
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
                                            thumbnailKey: props.thumbnailKey,
                                            measurements: measurementsForSave
                                        )
                                    )

                                    if let newId = created.id {
                                        finalServerID = newId
                                    }
                                    AppLog.gardenSave.notice("api created garden id=\(finalServerID, privacy: .public)")
                                }
                            } catch {
                                AppLog.gardenSave.error("api save failed — keeping local tempID error=\(String(describing: error), privacy: .public)")

                                // #391 — une session invité n'a pas accès à
                                // /gardens. Le reste du `catch` conservait
                                // l'enregistrement local et poursuivait jusqu'à
                                // `onValidated()`, ce qui annonçait un succès
                                // alors que rien n'était parti sur le serveur.
                                // Pour un invité ce n'est pas une panne mais une
                                // limite connue : on l'annonce au lieu de la
                                // masquer.
                                if error.isAccountRequired {
                                    await MainActor.run {
                                        props.isSaving = false
                                        props.onAccountRequired()
                                    }
                                    return
                                }
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
                    // #394 — enregistre le propriétaire dès l'écriture, pour
                    // qu'aucune autre session ne voie ce jardin.
                    LocalDataOwnership.claim(id)
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

            private func measurementsForSave(id: String, props: GardenARPlacementContainerView) -> GardenMeasurementsDTO? {
                var boundaryPointsArray: [[Float]] = props.boundaryPoints.map { [$0.x, $0.y, $0.z] }
                var savedArea: Float = props.area
                var savedPerimeter: Float = props.perimeter

                if boundaryPointsArray.isEmpty {
                    let existingURL = GardenLocalStore.sceneURL(for: id)
                    if let existingData = try? Data(contentsOf: existingURL),
                       let existingScene = try? JSONDecoder().decode(PersistedARScene.self, from: existingData).normalizedToWorldFrame() {
                        boundaryPointsArray = existingScene.boundaryPoints ?? []
                        savedArea = existingScene.area ?? savedArea
                        savedPerimeter = existingScene.perimeter ?? savedPerimeter
                    }
                }

                guard !boundaryPointsArray.isEmpty || savedArea > 0 || savedPerimeter > 0 else {
                    return nil
                }

                return GardenMeasurementsDTO(
                    boundaryPoints: boundaryPointsArray.isEmpty ? nil : boundaryPointsArray,
                    area: savedArea > 0 ? savedArea : nil,
                    perimeter: savedPerimeter > 0 ? savedPerimeter : nil
                )
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
                        if persistedPlants.isEmpty {
                            self.isRestoring = false
                            return
                        }
                        // #113 part 2 — Reduce save→reopen drift on X/Y/Z.
                        //
                        // The WorldMap restored by ARKit already contains the
                        // plant_* ARAnchors created in the previous session.
                        // They re-surface in `session.currentFrame.anchors`
                        // with their transforms expressed in the freshly
                        // *relocalized* world frame — i.e. no extra drift
                        // beyond ARKit's relocalization residual.
                        //
                        // Up to now, `restoreScene` ignored those and re-built
                        // anchors from scratch using the JSON transforms,
                        // which were saved in the *original* session's frame.
                        // The relocalization shift (1-3 cm typical) was baked
                        // into every restored anchor → visible drift.
                        //
                        // The claim pass below matches each restored anchor
                        // to its JSON metadata, attaches the model directly
                        // to the existing anchor's node, and returns the
                        // unmatched leftovers (plants whose anchor didn't
                        // come back — e.g. WorldMap was saved without them,
                        // or scene JSON has more plants than the WorldMap)
                        // for the legacy `restoreScene` path.
                        let leftover = self.claimWorldMapAnchors(from: persistedPlants)
                        if leftover.isEmpty {
                            // All plants restored from the WorldMap. No need
                            // to run the fallback path (which would call
                            // `removeAllPlantAnchors` and nuke what we just
                            // attached).
                            self.isRestoring = false
                        } else {
                            // Pass `clearExisting: false` so the snap-to-plane
                            // fallback doesn't blow away the WorldMap-restored
                            // anchors we just claimed.
                            self.restoreScene(from: leftover, clearExisting: false)
                        }
                    }
                }
            }

            /// Issue #113 part 2 — claim plant_* anchors restored from the
            /// WorldMap by matching them to entries in the just-loaded scene
            /// JSON. Side effects per match : register the anchor in
            /// `plantAnchorMap`, kick off async model resolution + attach
            /// the 3D model to the anchor's existing SCNNode (preserving
            /// the relocalized transform — no recreation drift).
            ///
            /// Returns the persistedPlants that had no matching WorldMap
            /// anchor ; caller passes them to `restoreScene` to recreate
            /// from scratch via `placeObject`.
            ///
            /// Matching rule : anchor.name format is `plant_<plantID>` (cf.
            /// `placeObject`). For each restored anchor we keep only the
            /// candidate PersistedPlants with the same plantID, then pick
            /// the one whose saved position is closest to the anchor's
            /// current world position. This handles multiple instances of
            /// the same catalog plant (e.g. three Succulent placed in a
            /// row) — even with relocalization drift the per-instance
            /// distance distinguishes them as long as they're > a few cm
            /// apart, which is always the case in practice.
            @MainActor
            private func claimWorldMapAnchors(from persistedPlants: [PersistedPlant]) -> [PersistedPlant] {
                guard let arView = arView,
                      let frame = arView.session.currentFrame else {
                    return persistedPlants
                }

                // Anchors in the current frame named "plant_*" that we
                // haven't registered ourselves (= came from the WorldMap,
                // and `session(_:didAdd:)` couldn't find a pending
                // placement to attach them to).
                let unclaimed = frame.anchors.filter { a in
                    guard let n = a.name, n.starts(with: "plant_") else { return false }
                    return self.plantAnchorMap[a.identifier] == nil
                }
                if unclaimed.isEmpty {
                    AppLog.gardenLoad.notice("worldMapClaim: 0 unclaimed plant anchors — full fallback for \(persistedPlants.count, privacy: .public) plants")
                    return persistedPlants
                }

                var remaining = persistedPlants
                var matched = 0

                for anchor in unclaimed {
                    guard let name = anchor.name else { continue }
                    let plantID = String(name.dropFirst("plant_".count))
                    let anchorPos = SIMD3<Float>(anchor.transform.columns.3.x,
                                                 anchor.transform.columns.3.y,
                                                 anchor.transform.columns.3.z)
                    guard let bestIdx = remaining.indices
                        .filter({ remaining[$0].plantID == plantID })
                        .min(by: { lhs, rhs in
                            let lpos = SIMD3<Float>(remaining[lhs].position[0], remaining[lhs].position[1], remaining[lhs].position[2])
                            let rpos = SIMD3<Float>(remaining[rhs].position[0], remaining[rhs].position[1], remaining[rhs].position[2])
                            return simd_distance(lpos, anchorPos) < simd_distance(rpos, anchorPos)
                        })
                    else {
                        AppLog.gardenLoad.notice("worldMapClaim: restored anchor plantID=\(plantID, privacy: .public) has no JSON match")
                        continue
                    }
                    let match = remaining.remove(at: bestIdx)
                    matched += 1
                    self.plantAnchorMap[anchor.identifier] = anchor
                    self.attachModelToRestoredAnchor(anchor: anchor, persistedPlant: match)
                }

                AppLog.gardenLoad.notice("worldMapClaim: matched=\(matched, privacy: .public) leftover=\(remaining.count, privacy: .public)")
                return remaining
            }

            /// Async model resolution + attach for a single WorldMap-restored
            /// anchor. Mirrors the model-URL fallback chain that
            /// `restoreScene` already uses (remote → local resolver).
            @MainActor
            private func attachModelToRestoredAnchor(anchor: ARAnchor, persistedPlant p: PersistedPlant) {
                guard let arView = arView, !p.modelURLString.isEmpty else { return }
                guard let node = arView.node(for: anchor) else {
                    AppLog.gardenLoad.error("attach: no SCNNode for anchor=\(anchor.identifier.uuidString.prefix(8), privacy: .public)")
                    return
                }
                let finalScale = SCNVector3(p.scale[0], p.scale[1], p.scale[2])
                let anchorTransform = anchor.transform

                Task { [weak self] in
                    guard let self = self else { return }
                    let modelURL: URL? = await {
                        do {
                            return try await ModelCacheManager.shared.getModelURL(for: p.modelURLString, forceDownload: false)
                        } catch {
                            AppLog.plants.error("worldMapAttach: download failed url=\(p.modelURLString, privacy: .public) error=\(String(describing: error), privacy: .public)")
                            return await MainActor.run(body: { self.resolveLocalModelURL(p.modelURLString) })
                        }
                    }()
                    guard let modelURL = modelURL else {
                        AppLog.plants.error("worldMapAttach: model unresolvable url=\(p.modelURLString, privacy: .public)")
                        return
                    }
                    await MainActor.run {
                        let pending = PendingPlantPlacement(
                            modelURL: modelURL,
                            plantId: p.plantID,
                            plantName: p.plantName,
                            finalScale: finalScale,
                            modelURLString: p.modelURLString,
                            upAxis: p.upAxis,
                            allowRetry: true,
                            isRestore: true,
                            surfaceType: p.surfaceType,
                            surfaceHeight: p.surfaceHeight,
                            placementMode: ARPlacementMode.fromPersisted(p.placementMode),
                            surfaceAnchor: p.surfaceAnchor,
                            instanceId: anchor.identifier,
                            autoSelect: false,
                            hasHeavy: p.hasHeavy == true
                        )
                        self.instantiatePlantNode(into: node, pending: pending, anchorTransform: anchorTransform)
                    }
                }
            }
            
            private func restoreScene(from plants: [PersistedPlant], clearExisting: Bool = true) {
                guard let arView = arView else {
                    isRestoring = false
                    return
                }

                if clearExisting {
                    // Undo/redo + legacy load paths : wipe everything before
                    // recreating. The fresh-from-disk load path passes
                    // `clearExisting: false` to preserve the WorldMap-restored
                    // anchors that `claimWorldMapAnchors` just attached
                    // models to (cf. #113 part 2).
                    removeAllPlantAnchors()
                    arView.scene.rootNode.childNodes.forEach { node in
                        if node.name?.starts(with: "plant_") == true {
                            node.removeFromParentNode()
                        }
                    }
                    deselectAll()
                }

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
                            let placementMode = ARPlacementMode.fromPersisted(p.placementMode)

                            switch placementMode {
                            case .some(.floor):
                                // Use the freshly detected floor Y if available;
                                // accept up to 15cm drift to allow re-anchoring
                                // a plant that was on a slightly mis-detected floor
                                // last session.
                                snapTarget = currentFloorY
                                snapTolerance = 0.15
                            case .some(.wall), .some(.ceiling):
                                // Wall and ceiling placements depend on full
                                // transform orientation, not just a Y snap.
                                // The WorldMap claim path is preferred; if this
                                // fallback runs, keep the saved transform.
                                snapTarget = nil
                                snapTolerance = 0
                            default:
                                switch p.surfaceType {
                                case SurfaceType.floor.rawValue:
                                    snapTarget = currentFloorY
                                    snapTolerance = 0.15
                                case "elevated",
                                     SurfaceType.shelf.rawValue,
                                     SurfaceType.table.rawValue,
                                     SurfaceType.windowsill.rawValue,
                                     SurfaceType.furniture.rawValue:
                                    snapTarget = p.surfaceHeight ?? savedY
                                    snapTolerance = 0.05
                                default:
                                    // Legacy data (no surfaceType saved) — keep
                                    // the saved Y untouched.
                                    snapTarget = nil
                                    snapTolerance = 0
                                }
                            }

                            let surfaceRefinement = await MainActor.run {
                                self.refinedTransformForPersistedSurface(transform, plant: p)
                            }
                            transform = surfaceRefinement.transform

                            if surfaceRefinement.didRefine {
                                AppLog.gardenLoad.notice("""
                                    snap plant=\(p.plantName, privacy: .public) \
                                    surface=\(p.surfaceType ?? "nil", privacy: .public) \
                                    restored via saved surface anchor
                                    """)
                            } else if let target = snapTarget,
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
                                            surfaceHeight: p.surfaceHeight,
                                            placementMode: ARPlacementMode.fromPersisted(p.placementMode),
                                            surfaceAnchor: p.surfaceAnchor,
                                            hasHeavy: p.hasHeavy == true
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
                                                surfaceHeight: p.surfaceHeight,
                                                placementMode: ARPlacementMode.fromPersisted(p.placementMode),
                                                surfaceAnchor: p.surfaceAnchor,
                                                hasHeavy: p.hasHeavy == true
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
            func removeAllPlantAnchors() {
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
            func resolveLocalModelURL(_ raw: String) -> URL? {
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

            @objc func handleDeselectAction() {
                deselectAll()
            }

            /// Re-computes the pivot Y from the node's current scale. The pivot
            /// is set once at placement to make the visible base land at the
            /// anchor's position, but it doesn't track scale changes — which
            /// is why pinching/zooming a plant after placement made it float
            /// (or sink) by `(1 - scaleRatio) * |minY|`. Call this every time
            /// the user changes a plant's scale.
            private func refreshPivotForScale(node: SCNNode) {
                let attachByTop = ARPlacementMode.fromPersisted(node.arborePlacementMode) == .ceiling
                let key = attachByTop ? "arboreOriginalMaxY" : "arboreOriginalMinY"
                guard let originalY = node.value(forKey: key) as? Float else { return }
                let pivotY = node.scale.y * originalY
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
                // LOD : couper un upgrade heavy éventuellement en cours pour ce placement
                // (sinon le download + parse continuent inutilement après suppression).
                if let uuid = instanceId(of: node), let inflight = heavyUpgradeTasks[uuid] {
                    inflight.task.cancel()
                    heavyUpgradeTasks[uuid] = nil
                    if let f = node.arboreModelURLString {
                        let lod = inflight.target
                        Task { await ModelCacheManager.shared.cancelDownload(for: f, lod: lod) }
                    }
                }
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
                    if let transform = lastReticleHit?.placementTransform ?? lastReticleTransform {
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
                    // to a fresh surface raycast under the reticle. Going via
                    // resolvedFloorRaycast (instead of reusing lastReticleTransform)
                    // ensures the teleport-Y benefits from the floor-locked
                    // fallback when the reticle was on a low-texture area
                    // (cf audit AR finding Y-5 / issue #171).
                    if let node = selectedNode,
                       let p = resolvedFloorRaycast(at: center) {
                        saveStateForUndo()
                        node.simdWorldPosition = p
                        // Pivot can become stale after teleport if the plant
                        // was previously scaled and the new surface is at a
                        // different height — recompute it.
                        refreshPivotForScale(node: node)
                        recordDraggedTransform(for: node)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        deselectAll()
                        return
                    }
                    deselectAll()
                    return
                }

                guard let hit = lastReticleHit else {
                    AppLog.plants.debug("tap ignored — no surface under reticle")
                    pushPlacementFeedback(noSurfaceMessage(for: activePlacementMode()))
                    deselectAll()
                    return
                }
                guard let plant = parentProps?.selectedPlant else {
                    AppLog.plants.debug("tap ignored — no plant selected from picker")
                    deselectAll()
                    return
                }

                if let blocked = placementBlockedMessage(for: hit, plant: plant) {
                    AppLog.plants.notice("""
                        tap placement blocked mode=\(hit.placementMode.rawValue, privacy: .public) \
                        surface=\(hit.surfaceType?.rawValue ?? "nil", privacy: .public) \
                        plant=\(plant.name, privacy: .public)
                        """)
                    pushPlacementFeedback(blocked)
                    return
                }

                let reliability = currentReticleReliability
                guard reliability.isPlaceable else {
                    AppLog.plants.notice("""
                        tap placement blocked reliability score=\(reliability.score, format: .fixed(precision: 2), privacy: .public) \
                        reason=\(reliability.reason.rawValue, privacy: .public) \
                        stable=\(reliability.stableDuration, format: .fixed(precision: 2), privacy: .public) \
                        source=\(hit.source.rawValue, privacy: .public)
                        """)
                    let message = placementReliabilityMessage(for: reliability)
                    pushPlacementFeedback(message.isEmpty ? L10n.t("AR_ANCHOR_CONFIDENCE_LOW") : message)
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
                placeObject(
                    at: hit.placementTransform,
                    modelURL: url,
                    id: plant.id,
                    name: plant.name,
                    modelURLString: plant.modelURL,
                    upAxis: plant.upAxis,
                    surfaceType: hit.surfaceType?.rawValue ?? hit.placementMode.rawValue,
                    surfaceHeight: hit.placementTransform.columns.3.y,
                    placementMode: hit.placementMode,
                    surfaceAnchor: persistedSurfaceAnchor(for: hit, reliability: reliability),
                    hasHeavy: plant.hasHeavy == true
                )
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
                // Uses resolvedFloorRaycast which prefers real planes and
                // locks Y to detectedFloorY() when falling back to estimated
                // (cf audit AR finding Y-4 / issue #171).
                let location = gesture.location(in: arView)
                let mode = ARPlacementMode.fromPersisted(node.arborePlacementMode)
                    ?? parentProps?.placementMode
                    ?? .floor
                if let hit = raycastHit(at: location, mode: mode),
                   placementBlockedMessage(for: hit, plant: nil) == nil {
                    let currentScale = node.scale
                    node.simdWorldTransform = hit.placementTransform
                    node.scale = currentScale
                    node.arboreSurfaceType = hit.surfaceType?.rawValue ?? mode.rawValue
                    node.arborePlacementMode = mode.rawValue
                    let reliability = immediatePlacementReliability(for: hit)
                    node.arboreSurfaceAnchor = persistedSurfaceAnchor(for: hit, reliability: reliability)
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
                    // Re-apply pivot offset in case the plant has been scaled
                    // and the new surface differs in height (Y-5 in audit).
                    refreshPivotForScale(node: node)
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
                placementMode: ARPlacementMode? = nil,
                surfaceAnchor: PersistedSurfaceAnchor? = nil,
                autoSelect: Bool = true,
                hasHeavy: Bool = false
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
                    placementMode: placementMode,
                    surfaceAnchor: surfaceAnchor,
                    instanceId: anchor.identifier,
                    autoSelect: autoSelect,
                    hasHeavy: hasHeavy
                )
                plantAnchorMap[anchor.identifier] = anchor
                arView.session.add(anchor: anchor)

                AppLog.arAnchor.notice("""
                        placeObject id=\(id, privacy: .public) \
                    anchor=\(anchor.identifier.uuidString.prefix(8), privacy: .public) \
                    isRestore=\(self.isRestoring, privacy: .public) \
                    rigid=\(rigidTransform.logDescription, privacy: .public) \
                    surface=\(surfaceType ?? "nil", privacy: .public) \
                    mode=\(placementMode?.rawValue ?? "nil", privacy: .public) \
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
                    container.arboreSurfaceType = pending.surfaceType
                    container.arborePlacementMode = pending.placementMode?.rawValue
                    container.arboreSurfaceAnchor = pending.surfaceAnchor
                    container.arboreHasHeavy = pending.hasHeavy

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
                    // Hauteur intrinsèque (avant le halo) pour le LOD distance.
                    container.arboreModelRawHeight = Double(max(0, rawHeight))

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
                    let attachByTop = pending.placementMode == .ceiling

                    if let scale = pending.finalScale {
                        container.scale = scale
                        if rawHeight > 0 {
                            let pivotY = scale.y * (attachByTop ? maxVec.y : minVec.y)
                            container.pivot = SCNMatrix4MakeTranslation(0, pivotY, 0)
                        }
                        AppLog.plants.debug("""
                            restoreScale plant=\(pending.plantName, privacy: .public) \
                            scale=\(scale.logDescription, privacy: .public) \
                            pivotY=\(rawHeight > 0 ? scale.y * (attachByTop ? maxVec.y : minVec.y) : 0, format: .fixed(precision: 3), privacy: .public)
                            """)
                    } else if !pending.isRestore {
                        if rawHeight > 0 {
                            let scaleFactor = Self.autoScaleTargetHeightMeters / rawHeight
                            container.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
                            container.pivot = SCNMatrix4MakeTranslation(
                                0,
                                scaleFactor * (attachByTop ? maxVec.y : minVec.y),
                                0
                            )
                            AppLog.plants.debug("""
                                autoScale plant=\(pending.plantName, privacy: .public) \
                                scaleFactor=\(scaleFactor, format: .fixed(precision: 3), privacy: .public) \
                                pivotY=\(scaleFactor * (attachByTop ? maxVec.y : minVec.y), format: .fixed(precision: 3), privacy: .public)
                                """)
                        }
                    }
                    // Stash the unscaled minY so refreshPivotForScale can
                    // recompute the pivot after the user pinches/zooms.
                    if rawHeight > 0 {
                        container.setValue(NSNumber(value: minVec.y), forKey: "arboreOriginalMinY")
                        container.setValue(NSNumber(value: maxVec.y), forKey: "arboreOriginalMaxY")
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
                    // bottom dock switches to edit mode (rotate / scale +- / delete)
                    // immediately. Batch placements (AI auto-place,
                    // morph-confirm) pass false to avoid the orange-halo
                    // flicker as we loop through plants. Restore is also
                    // skipped — autoSelect is meaningless during reload.
                    if !pending.isRestore && pending.autoSelect {
                        selectNode(container)
                    }

                    // LOD adaptatif : le modèle LÉGER est posé immédiatement. L'upgrade
                    // vers le heavy (et les downgrades) est piloté par evaluateLOD() depuis
                    // renderer(_:updateAtTime:), selon thermique + budget K + distance.
                    container.arboreCurrentLOD = PlantLODPolicy.LOD.light.rawValue

                    AppLog.arAnchor.notice("""
                        instantiated plant=\(pending.plantName, privacy: .public) \
                        anchor=\(pending.instanceId.uuidString.prefix(8), privacy: .public) \
                        world=\(container.simdWorldTransform.logDescription, privacy: .public) \
                        local=\(container.simdTransform.logDescription, privacy: .public)
                        """)
            }

            // MARK: - LOD adaptatif (light ↔ heavy)

            /// Programme un swap vers le LOD cible : télécharge le modèle (cache) en fond
            /// et l'échange une fois prêt. Fail-safe : toute erreur laisse le modèle
            /// courant en place. ⚠️ Comportement AR à valider on-device (non testable CI).
            private func scheduleLODSwap(filename: String, upAxis: String?, instanceId: UUID,
                                         parentNode: SCNNode, to lod: PlantLODPolicy.LOD) {
                guard !filename.isEmpty else { return }
                heavyUpgradeTasks[instanceId]?.task.cancel()
                let modelLOD: ModelLOD = (lod == .heavy) ? .heavy : .light
                let task = Task { [weak self, weak parentNode] in
                    do {
                        let url = try await ModelCacheManager.shared.getModelURL(for: filename, lod: modelLOD)
                        if Task.isCancelled { return }
                        let scene = try SCNScene(url: url, options: nil)
                        if Task.isCancelled { return }
                        await MainActor.run {
                            guard let self else { return }
                            self.heavyUpgradeTasks[instanceId] = nil
                            guard let parentNode else { return }
                            self.swapModel(scene: scene, instanceId: instanceId, upAxis: upAxis, parentNode: parentNode, to: lod)
                        }
                    } catch {
                        await MainActor.run { self?.heavyUpgradeTasks[instanceId] = nil }
                    }
                }
                heavyUpgradeTasks[instanceId] = InFlightLODSwap(task: task, target: modelLOD)
            }

            /// Remplace le node courant d'une plante par sa variante au LOD cible, avec un
            /// court fondu croisé, puis libère l'ancien. Position/rotation/échelle reprises
            /// de l'ancien (placement + pinch-zoom) ; pivot RE-DÉRIVÉ de la bbox du nouveau
            /// modèle (robuste si les bbox light/heavy diffèrent légèrement).
            /// Hypothèse à valider on-device : même origine/échelle model-space et même
            /// up-axis entre les LOD (garanti par le même source Meshy).
            private func swapModel(scene: SCNScene, instanceId: UUID, upAxis: String?,
                                   parentNode: SCNNode, to lod: PlantLODPolicy.LOD) {
                // Le node a pu être supprimé entre-temps → on abandonne.
                guard let current = parentNode.childNodes.first(where: { $0.arboreInstanceId == instanceId }) else { return }
                if current.arboreCurrentLOD == lod.rawValue { return } // déjà au bon LOD

                let next = SCNNode()
                next.name = current.name
                next.arborePlantId = current.arborePlantId
                next.arborePlantName = current.arborePlantName
                next.arboreInstanceId = current.arboreInstanceId
                next.arboreModelURLString = current.arboreModelURLString
                next.arboreSurfaceType = current.arboreSurfaceType
                next.arborePlacementMode = current.arborePlacementMode
                next.arboreSurfaceAnchor = current.arboreSurfaceAnchor
                next.arboreHasHeavy = current.arboreHasHeavy
                next.arboreCurrentLOD = lod.rawValue
                next.arboreLODLockedUntil = CACurrentMediaTime() + PlantLODPolicy.swapDebounce

                let wrapper = SCNNode()
                for child in scene.rootNode.childNodes { wrapper.addChildNode(child) }
                let effectiveAxis = upAxis ?? plantUpAxisMap[current.arborePlantId ?? ""]
                if effectiveAxis?.uppercased() == "Z" { wrapper.eulerAngles.x = -.pi / 2 }
                next.addChildNode(wrapper)
                stripPotIfNeeded(from: next)

                next.simdTransform = current.simdTransform  // encode déjà T·R·S
                let (minV, maxV) = next.boundingBox
                if maxV.y - minV.y > 0 {
                    let attachByTop = ARPlacementMode.fromPersisted(next.arborePlacementMode) == .ceiling
                    next.pivot = SCNMatrix4MakeTranslation(
                        0,
                        next.scale.y * (attachByTop ? maxV.y : minV.y),
                        0
                    )
                    next.setValue(NSNumber(value: minV.y), forKey: "arboreOriginalMinY")
                    next.setValue(NSNumber(value: maxV.y), forKey: "arboreOriginalMaxY")
                } else {
                    next.pivot = current.pivot
                }
                // Hauteur intrinsèque mesurée AVANT le halo (pour le LOD distance).
                next.arboreModelRawHeight = Double(max(0, maxV.y - minV.y))

                buildHaloCache(for: next, source: wrapper)
                if parentProps?.relocationPhase == .adjusting {
                    applyOutline(to: next, color: Self.outlineDefaultColor)
                }

                // Fondu croisé : révèle le nouveau, masque l'ancien, puis le retire. On
                // sort l'ancien du hit-test (name → nil) pour qu'un tap ne le sélectionne
                // pas pendant le fondu (l'identité passe par arboreInstanceId, pas le name).
                let wasSelected = (selectedNode === current)
                next.opacity = 0
                parentNode.addChildNode(next)
                current.name = nil

                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.25
                next.opacity = 1
                current.opacity = 0
                SCNTransaction.completionBlock = { [weak current] in current?.removeFromParentNode() }
                SCNTransaction.commit()

                if wasSelected { selectNode(next) }
                AppLog.arAnchor.notice("LOD swap → \(lod.rawValue, privacy: .public) anchor=\(instanceId.uuidString.prefix(8), privacy: .public)")
            }

            /// Annule tous les swaps LOD en cours (teardown / reset de scène).
            func cancelAllHeavyUpgrades() {
                for (_, s) in heavyUpgradeTasks { s.task.cancel() }
                heavyUpgradeTasks.removeAll()
            }

            // MARK: LOD evaluation (per-frame, throttlée ~4 Hz)

            private struct LODCandidate {
                let node: SCNNode
                let parent: SCNNode
                let instanceId: UUID
                let filename: String
                let upAxis: String?
                let distance: Float
                let height: Float
                let currentlyHeavy: Bool
                let isSelected: Bool
                let lockedUntil: Double
            }

            /// Énumère les plantes à variante heavy avec distance/hauteur/LOD courant.
            private func collectLODCandidates(cameraPosition: SIMD3<Float>) -> [LODCandidate] {
                guard let arView else { return [] }
                var out: [LODCandidate] = []
                func consider(_ node: SCNNode, parent: SCNNode) {
                    guard node.name?.hasPrefix("plant_") == true,
                          node.arboreHasHeavy,
                          let id = node.arboreInstanceId,
                          let filename = node.arboreModelURLString, !filename.isEmpty else { return }
                    let pos = node.simdWorldPosition
                    let distance = simd_length(pos - cameraPosition)
                    // Hauteur pré-halo × scale courant (zoom-aware) ; évite le +4% du halo.
                    let height = Float(node.arboreModelRawHeight) * node.scale.y
                    out.append(LODCandidate(
                        node: node, parent: parent, instanceId: id, filename: filename,
                        upAxis: plantUpAxisMap[node.arborePlantId ?? ""],
                        distance: distance, height: height,
                        currentlyHeavy: node.arboreCurrentLOD == PlantLODPolicy.LOD.heavy.rawValue,
                        isSelected: node === selectedNode,
                        lockedUntil: node.arboreLODLockedUntil))
                }
                for rootChild in arView.scene.rootNode.childNodes {
                    consider(rootChild, parent: arView.scene.rootNode)
                    for c in rootChild.childNodes { consider(c, parent: rootChild) }
                }
                return out
            }

            /// Évalue et applique le LOD de chaque plante (thermique → budget K → distance).
            /// Sur le main thread, throttlée depuis renderer(_:updateAtTime:).
            private func evaluateLOD(cameraPosition: SIMD3<Float>) {
                let candidates = collectLODCandidates(cameraPosition: cameraPosition)
                guard !candidates.isEmpty else { return }

                let now = CACurrentMediaTime()
                let thermal = ProcessInfo.processInfo.thermalState
                let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                let critical = (thermal == .critical)
                let hot = critical || thermal == .serious || lowPower

                // Cooldown : downgrade immédiat à chaud ; upgrades ré-autorisés seulement
                // après un retour au frais soutenu (reco Apple — pas d'hystérésis native).
                if hot { lodLastHotAt = now }
                let upgradesAllowed = !hot && (lodLastHotAt < 0 || now - lodLastHotAt >= PlantLODPolicy.coolStableBeforeUpgrade)

                // « Effectivement heavy » = déjà heavy OU heavy en cours de download. On lui
                // applique la bande large d'hystérésis (pas d'annulation du download au moindre
                // jitter) et la stickiness de budget.
                func effectivelyHeavy(_ c: LODCandidate) -> Bool {
                    c.currentlyHeavy || heavyUpgradeTasks[c.instanceId]?.target == .heavy
                }

                // Ensemble désiré-heavy (chaîne de précédence).
                var desiredHeavy = Set<UUID>()
                if !critical {
                    let eligible = candidates.filter { c in
                        c.isSelected || PlantLODPolicy.isWithinHeavy(distance: c.distance, height: c.height, currentlyHeavy: effectivelyHeavy(c))
                    }.sorted { a, b in
                        if a.isSelected != b.isSelected { return a.isSelected } // sélection prioritaire
                        // Stickiness : un heavy en place garde un bonus de distance pour ne pas
                        // se faire déloger du budget par une candidate à peine plus proche.
                        let da = effectivelyHeavy(a) ? a.distance * (1 - PlantLODPolicy.budgetStickiness) : a.distance
                        let db = effectivelyHeavy(b) ? b.distance * (1 - PlantLODPolicy.budgetStickiness) : b.distance
                        return da < db
                    }
                    if hot {
                        // .serious / Low Power : seule la plante sélectionnée peut être heavy.
                        if let sel = eligible.first(where: { $0.isSelected }), effectivelyHeavy(sel) || upgradesAllowed {
                            desiredHeavy.insert(sel.instanceId)
                        }
                    } else {
                        let budget = PlantLODPolicy.heavyBudget(tier: DeviceCapabilities.tier)
                        var granted = 0
                        for c in eligible where granted < budget {
                            // Garde un heavy existant ; n'AJOUTE un nouveau que si autorisé.
                            if effectivelyHeavy(c) || upgradesAllowed {
                                desiredHeavy.insert(c.instanceId)
                                granted += 1
                            }
                        }
                    }
                }

                // Application : upgrade / downgrade / annulation, avec debounce et garde
                // sur le LOD cible déjà en vol (pour ne pas annuler/redémarrer à tort).
                for c in candidates {
                    let wantHeavy = desiredHeavy.contains(c.instanceId)
                    let inFlightTarget = heavyUpgradeTasks[c.instanceId]?.target
                    if wantHeavy {
                        if !c.currentlyHeavy && inFlightTarget != .heavy && now >= c.lockedUntil {
                            scheduleLODSwap(filename: c.filename, upAxis: c.upAxis, instanceId: c.instanceId, parentNode: c.parent, to: .heavy)
                        }
                    } else {
                        // Annule un download HEAVY dont on ne veut plus (jamais un downgrade en cours).
                        if inFlightTarget == .heavy {
                            heavyUpgradeTasks[c.instanceId]?.task.cancel()
                            heavyUpgradeTasks[c.instanceId] = nil
                            let f = c.filename
                            Task { await ModelCacheManager.shared.cancelDownload(for: f, lod: .heavy) }
                        }
                        if c.currentlyHeavy && heavyUpgradeTasks[c.instanceId]?.target != .light && now >= c.lockedUntil {
                            scheduleLODSwap(filename: c.filename, upAxis: c.upAxis, instanceId: c.instanceId, parentNode: c.parent, to: .light)
                        }
                    }
                }
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
                                surfaceHeight: pending.surfaceHeight,
                                placementMode: pending.placementMode,
                                surfaceAnchor: pending.surfaceAnchor,
                                hasHeavy: pending.hasHeavy
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
                if let plane = anchor as? ARPlaneAnchor {
                    DispatchQueue.main.async { [weak self] in
                        self?.bumpRestoreDebounce()
                        self?.handlePlaneAnchorChange(plane)
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

            func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
                if let plane = anchor as? ARPlaneAnchor {
                    DispatchQueue.main.async { [weak self] in
                        self?.handlePlaneAnchorChange(plane)
                    }
                }
            }

            func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
                DispatchQueue.main.async { [weak self] in
                    _ = self?.anchorPendingPlacements.removeValue(forKey: anchor.identifier)
                    if anchor is ARPlaneAnchor {
                        self?.handlePlaneAnchorRemoved(anchor.identifier)
                    }
                }
            }

            /// Issue #186 — refresh classification + debug viz for a plane.
            ///
            /// Called from didAdd / didUpdate on the main thread. Each call
            /// :
            ///  1. extracts a `PlaneFeatures` snapshot,
            ///  2. updates the global `floorY` reference if the plane is a
            ///     new lowest horizontal,
            ///  3. (re)classifies it, possibly cascading a re-classification
            ///     of previously cached planes whose verdict depended on
            ///     `floorY`,
            ///  4. notifies the debug viz controller of the new verdict.
            ///
            /// Reclassification is O(n) over the cached planes but only
            /// happens when `floorY` actually shifts — rare, since the
            /// lowest plane stabilises quickly. Typical scene = 10-30
            /// planes, so even a full pass is ~µs of work.
            func handlePlaneAnchorChange(_ anchor: ARPlaneAnchor) {
                let features = PlaneFeatures(anchor)
                let cameraY = lastCameraY

                // All mutations + the classification read happen under the
                // surfaces lock so the SCN renderer thread can't observe a
                // half-rebuilt dictionary (cf #186 crash log).
                struct ChangeResult {
                    let kind: SurfaceType
                    let previous: SurfaceType?
                    let floorChanged: Bool
                    let verticals: [PlaneFeatures]
                }
                let result = surfacesLock.withLock { () -> ChangeResult in
                    self.planeAnchors[anchor.identifier] = anchor
                    self.planeFeatures[anchor.identifier] = features

                    var floorChanged = false
                    if features.alignment == .horizontal {
                        if self.floorY == nil || features.center.y < (self.floorY ?? .infinity) - 0.01 {
                            self.floorY = features.center.y
                            floorChanged = true
                        }
                    }
                    let verticals = self.planeFeatures.values.filter { $0.alignment == .vertical }
                    let kind = SurfaceClassifier.classify(
                        plane: features,
                        floorY: self.floorY,
                        cameraY: cameraY,
                        nearbyVerticals: verticals
                    )
                    let previous = self.planeTypes[anchor.identifier]
                    self.planeTypes[anchor.identifier] = kind
                    return ChangeResult(kind: kind, previous: previous,
                                        floorChanged: floorChanged, verticals: verticals)
                }

                if result.previous != result.kind {
                    AppLog.surfaces.notice("plane=\(anchor.identifier.uuidString.prefix(8), privacy: .public) \(result.previous?.rawValue ?? "—", privacy: .public) → \(result.kind.rawValue, privacy: .public) y=\(features.center.y, privacy: .public)")
                }
                if surfaceViz.isActive {
                    surfaceViz.upsert(anchor: anchor, type: result.kind)
                }
                if result.floorChanged {
                    reclassifyCachedPlanes(except: anchor.identifier,
                                            cameraY: cameraY,
                                            verticals: result.verticals)
                }
                maybeReanchorEstimatedPlants(to: anchor, type: result.kind)
            }

            private func maybeReanchorEstimatedPlants(to anchor: ARPlaneAnchor, type: SurfaceType) {
                let features = PlaneFeatures(anchor)
                var restoredCount = 0

                for node in currentPlantNodes() {
                    guard let metadata = node.arboreSurfaceAnchor,
                          let source = SurfaceHitSource(rawValue: metadata.source),
                          source.isEstimatedLike else {
                        continue
                    }

                    let mode = ARPlacementMode.fromPersisted(node.arborePlacementMode)
                        ?? (type == .wall ? .wall : (type == .ceiling ? .ceiling : .floor))
                    guard mode.acceptedSurfaceTypes.contains(type) else { continue }

                    let position = SIMD3<Float>(
                        node.simdWorldPosition.x,
                        node.simdWorldPosition.y,
                        node.simdWorldPosition.z
                    )
                    let planeDistance = abs(simd_dot(position - features.center, features.normal))
                    let maxDistance: Float = (mode == .wall) ? 0.18 : 0.12
                    guard planeDistance <= maxDistance else { continue }

                    let snapped = position - features.normal * simd_dot(position - features.center, features.normal)
                    let currentScale = node.scale
                    let transform: simd_float4x4
                    switch mode {
                    case .wall:
                        var normal = features.normal
                        if let camera = currentCameraPosition() {
                            let toCamera = camera - snapped
                            if simd_length(toCamera) > 0.001,
                               simd_dot(normal, simd_normalize(toCamera)) < 0 {
                                normal = -normal
                            }
                        }
                        transform = wallAlignedTransform(position: snapped + normal * 0.025, normal: normal)
                    case .ceiling:
                        transform = uprightTransform(at: SIMD4<Float>(snapped.x, snapped.y, snapped.z, 1))
                    case .floor:
                        var preserved = stripScale(from: node.simdWorldTransform)
                        preserved.columns.3 = SIMD4<Float>(snapped.x, snapped.y, snapped.z, 1)
                        transform = preserved
                    }

                    node.simdWorldTransform = transform
                    node.scale = currentScale
                    node.arboreSurfaceType = type.rawValue
                    node.arborePlacementMode = mode.rawValue
                    node.arboreSurfaceAnchor = surfaceAnchorMetadata(
                        source: .existingPlaneGeometry,
                        reliabilityScore: 0.9,
                        normal: features.normal,
                        features: features,
                        planeTransform: anchor.transform,
                        position: worldPosition(from: transform)
                    )
                    recordDraggedTransform(for: node)
                    refreshPivotForScale(node: node)
                    restoredCount += 1

                    AppLog.arAnchor.notice("""
                        reanchor plant=\(node.arborePlantName ?? node.name ?? "plant", privacy: .public) \
                        surface=\(type.rawValue, privacy: .public) \
                        plane=\(anchor.identifier.uuidString.prefix(8), privacy: .public) \
                        distance=\(planeDistance, format: .fixed(precision: 3), privacy: .public)
                        """)
                }

                if restoredCount > 0 {
                    DispatchQueue.main.async { [weak self] in
                        withAnimation(.easeOut(duration: 0.2)) {
                            self?.parentProps?.placementFeedback = L10n.t("AR_ANCHOR_SURFACE_RESTORED")
                        }
                    }
                }
            }

            private func currentPlantNodes() -> [SCNNode] {
                guard let arView = arView else { return [] }
                return arView.scene.rootNode.childNodes.flatMap { rootChild -> [SCNNode] in
                    if rootChild.name?.starts(with: "plant_") == true {
                        return [rootChild]
                    }
                    return rootChild.childNodes.filter {
                        $0.name?.starts(with: "plant_") == true
                    }
                }
            }

            private func reclassifyCachedPlanes(except skipId: UUID, cameraY: Float, verticals: [PlaneFeatures]) {
                // Build the list of (id, anchor, newKind) entries under the
                // lock, then push the viz updates outside the lock.
                struct Update { let id: UUID; let anchor: ARPlaneAnchor; let kind: SurfaceType }
                let updates: [Update] = surfacesLock.withLock {
                    var out: [Update] = []
                    for (id, features) in self.planeFeatures where id != skipId {
                        let kind = SurfaceClassifier.classify(
                            plane: features,
                            floorY: self.floorY,
                            cameraY: cameraY,
                            nearbyVerticals: verticals
                        )
                        let previous = self.planeTypes[id]
                        if previous != kind {
                            self.planeTypes[id] = kind
                            if let anchor = self.planeAnchors[id] {
                                out.append(Update(id: id, anchor: anchor, kind: kind))
                            }
                            AppLog.surfaces.debug("reclassify \(id.uuidString.prefix(8), privacy: .public) \(previous?.rawValue ?? "—", privacy: .public) → \(kind.rawValue, privacy: .public)")
                        }
                    }
                    return out
                }
                if surfaceViz.isActive {
                    for u in updates {
                        surfaceViz.upsert(anchor: u.anchor, type: u.kind)
                    }
                }
            }

            func handlePlaneAnchorRemoved(_ id: UUID) {
                surfacesLock.withLock {
                    self.planeAnchors.removeValue(forKey: id)
                    self.planeFeatures.removeValue(forKey: id)
                    self.planeTypes.removeValue(forKey: id)
                    if let floor = self.floorY {
                        let candidates = self.planeFeatures.values
                            .filter { $0.alignment == .horizontal }
                            .map { $0.center.y }
                        if let newFloor = candidates.min(), abs(newFloor - floor) > 0.001 {
                            self.floorY = newFloor
                        } else if candidates.isEmpty {
                            self.floorY = nil
                        }
                    }
                }
                surfaceViz.remove(id: id)
            }

            /// Issue #186 — bring the surface debug viz in sync with the
            /// SwiftUI toggle. Idempotent. Uses the cached `planeAnchors`
            /// dictionary so we never touch `session.currentFrame` (which
            /// retains an ARFrame on each access).
            func syncSurfaceVizEnabled(_ enabled: Bool, sceneView: ARSCNView) {
                if enabled {
                    if !surfaceViz.isActive {
                        surfaceViz.start(in: sceneView.scene)
                        // Replay every cached classification — the viz starts
                        // empty even if planes were detected before toggle-on.
                        // Snapshot the dictionaries under the lock to avoid
                        // mutating-while-iterating with the AR session thread.
                        struct Replay { let anchor: ARPlaneAnchor; let kind: SurfaceType }
                        let replay: [Replay] = surfacesLock.withLock {
                            self.planeTypes.compactMap { (id, kind) in
                                self.planeAnchors[id].map { Replay(anchor: $0, kind: kind) }
                            }
                        }
                        for r in replay {
                            surfaceViz.upsert(anchor: r.anchor, type: r.kind)
                        }
                    }
                } else {
                    surfaceViz.stop()
                }
            }

            // syncSceneUnderstanding + applySceneSnapshot moved to
            // GardenARPlacementView+SceneUnderstanding.swift (#188 P3.1).

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
            func applyOutlinesToAllPlants() {
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

            func deselectAll() {
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

            // MARK: - Manual Replacement (Issue #111) — state only ;
            // handlers moved to GardenARPlacementView+ManualReplacement.swift
            // (#188 P3.1). Internal access required so the extension in
            // that file can reach the storage.

            // Old garden data loaded from JSON (no WorldMap dependency).
            var oldBoundaryPoints: [SIMD3<Float>] = []
            var oldPersistedPlants: [PersistedPlant] = []
            var oldDataLoaded = false

            // Snapshot taken right after morphing, used to revert manual adjustments.
            var preMorphAdjustment: [String: simd_float4x4] = [:]
            // List of morphed plants pending confirmation. Keyed by index, NOT
            // plantId — multiple instances of the same catalog plant must
            // each survive (dedup-by-id was a bug: 5 Arecas collapsed to 1).
            var pendingMorphedPlants: [MorphedPlant] = []

            // Manual-replacement handlers moved to GardenARPlacementView+ManualReplacement.swift (#188 P3.1).
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

struct GlassButtonStyle: ViewModifier {
    var isGreen: Bool = false
    func body(content: Content) -> some View {
        content
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(isGreen ? .white : ArboreDesign.Colors.textPrimary)
            .frame(width: 42, height: 42)
            .background(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                    .fill(isGreen ? ArboreDesign.Colors.primaryGreen : ArboreDesign.Colors.card.opacity(0.72))
                    .background(
                        RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                    .stroke(isGreen ? .white.opacity(0.16) : ArboreDesign.Colors.border.opacity(0.82), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 4)
    }
}

private struct GardenShareRenderOptions: Equatable {
    var showsBranding: Bool = false
}

private enum GardenARShareComposer {
    static func compose(snapshot: UIImage, options: GardenShareRenderOptions) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: snapshot.size, format: format)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: snapshot.size)
            snapshot.draw(in: rect)

            if options.showsBranding {
                drawGradient(in: context.cgContext, rect: rect)
                drawBranding(in: context.cgContext, rect: rect, snapshot: snapshot)
            }
        }
    }
}

private enum GardenShareCaptureStore {
    private struct Index: Codable {
        var captures: [Record] = []
    }

    private struct Record: Codable {
        let id: UUID
        let kind: String
        let fileName: String
        let thumbnailFileName: String?
        let createdAt: Date
        let orientationVersion: Int?
    }

    private static let directoryPrefix = "ar_share_captures_"
    private static let indexFileName = "index.json"
    private static let currentVideoOrientationVersion = 2

    static func load(for storageKey: String) -> [GardenShareCapture] {
        let directory = directoryURL(for: storageKey)
        let index = readIndex(from: directory)

        return index.captures
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { record in
                let mediaURL = directory.appendingPathComponent(record.fileName)
                guard FileManager.default.fileExists(atPath: mediaURL.path) else { return nil }

                switch record.kind {
                case "photo":
                    guard let image = UIImage(contentsOfFile: mediaURL.path) else { return nil }
                    return GardenShareCapture.photo(
                        image,
                        id: record.id,
                        mediaURL: mediaURL,
                        createdAt: record.createdAt
                    )
                case "video":
                    let needsLegacyRotation = record.orientationVersion == nil
                    let thumbnail = record.thumbnailFileName.flatMap { fileName -> UIImage? in
                        let thumbnailURL = directory.appendingPathComponent(fileName)
                        return UIImage(contentsOfFile: thumbnailURL.path)
                    }
                    let thumbnailURL = record.thumbnailFileName.map { directory.appendingPathComponent($0) }
                    return GardenShareCapture.video(
                        url: mediaURL,
                        thumbnail: needsLegacyRotation ? thumbnail?.rotated180() : thumbnail,
                        id: record.id,
                        thumbnailURL: thumbnailURL,
                        createdAt: record.createdAt,
                        requiresPlaybackRotation: needsLegacyRotation
                    )
                default:
                    return nil
                }
            }
    }

    static func savePhoto(
        _ image: UIImage,
        for storageKey: String,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> GardenShareCapture? {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }

        let directory = directoryURL(for: storageKey)
        let fileName = "\(id.uuidString).jpg"
        let mediaURL = directory.appendingPathComponent(fileName)

        do {
            try ensureDirectoryExists(directory)
            try data.write(to: mediaURL, options: [.atomic])
            upsert(
                Record(
                    id: id,
                    kind: "photo",
                    fileName: fileName,
                    thumbnailFileName: nil,
                    createdAt: createdAt,
                    orientationVersion: nil
                ),
                in: directory
            )
            return GardenShareCapture.photo(
                image,
                id: id,
                mediaURL: mediaURL,
                createdAt: createdAt
            )
        } catch {
            AppLog.gardenSave.error("share photo save failed error=\(String(describing: error), privacy: .public)")
            return nil
        }
    }

    static func saveVideo(
        at sourceURL: URL,
        thumbnail: UIImage?,
        for storageKey: String,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> GardenShareCapture? {
        let directory = directoryURL(for: storageKey)
        let fileName = "\(id.uuidString).mp4"
        let mediaURL = directory.appendingPathComponent(fileName)
        let thumbnailFileName = thumbnail.map { _ in "\(id.uuidString)_thumb.jpg" }
        let thumbnailURL = thumbnailFileName.map { directory.appendingPathComponent($0) }

        do {
            try ensureDirectoryExists(directory)
            let sourceIsAlreadyPersistent = sourceURL.standardizedFileURL.path == mediaURL.standardizedFileURL.path
            if !sourceIsAlreadyPersistent {
                if FileManager.default.fileExists(atPath: mediaURL.path) {
                    try FileManager.default.removeItem(at: mediaURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: mediaURL)
            }
            if let thumbnail, let thumbnailURL, let data = thumbnail.jpegData(compressionQuality: 0.82) {
                try data.write(to: thumbnailURL, options: [.atomic])
            }

            upsert(
                Record(
                    id: id,
                    kind: "video",
                    fileName: fileName,
                    thumbnailFileName: thumbnailFileName,
                    createdAt: createdAt,
                    orientationVersion: currentVideoOrientationVersion
                ),
                in: directory
            )
            return GardenShareCapture.video(
                url: mediaURL,
                thumbnail: thumbnail,
                id: id,
                thumbnailURL: thumbnailURL,
                createdAt: createdAt
            )
        } catch {
            AppLog.gardenSave.error("share video save failed error=\(String(describing: error), privacy: .public)")
            return nil
        }
    }

    static func delete(_ capture: GardenShareCapture, for storageKey: String) {
        let directory = directoryURL(for: storageKey)
        var index = readIndex(from: directory)
        guard let record = index.captures.first(where: { $0.id == capture.id }) else {
            removeLooseFiles(for: capture)
            return
        }

        let mediaURL = directory.appendingPathComponent(record.fileName)
        try? FileManager.default.removeItem(at: mediaURL)
        if let thumbnailFileName = record.thumbnailFileName {
            let thumbnailURL = directory.appendingPathComponent(thumbnailFileName)
            try? FileManager.default.removeItem(at: thumbnailURL)
        }

        index.captures.removeAll { $0.id == capture.id }
        writeIndex(index, to: directory)
    }

    private static func removeLooseFiles(for capture: GardenShareCapture) {
        if let mediaURL = capture.mediaURL {
            try? FileManager.default.removeItem(at: mediaURL)
        }
        if let thumbnailURL = capture.thumbnailURL {
            try? FileManager.default.removeItem(at: thumbnailURL)
        }
    }

    private static func upsert(_ record: Record, in directory: URL) {
        var index = readIndex(from: directory)
        index.captures.removeAll { $0.id == record.id }
        index.captures.insert(record, at: 0)
        index.captures.sort { $0.createdAt > $1.createdAt }
        writeIndex(index, to: directory)
    }

    private static func readIndex(from directory: URL) -> Index {
        let url = directory.appendingPathComponent(indexFileName)
        guard let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(Index.self, from: data) else {
            return Index()
        }
        return index
    }

    private static func writeIndex(_ index: Index, to directory: URL) {
        do {
            try ensureDirectoryExists(directory)
            let data = try JSONEncoder().encode(index)
            try data.write(to: directory.appendingPathComponent(indexFileName), options: [.atomic])
        } catch {
            AppLog.gardenSave.error("share capture index write failed error=\(String(describing: error), privacy: .public)")
        }
    }

    private static func directoryURL(for storageKey: String) -> URL {
        let sanitizedKey = storageKey
            .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        let folderName = directoryPrefix + (sanitizedKey.isEmpty ? "default" : sanitizedKey)
        return documentsURL().appendingPathComponent(folderName, isDirectory: true)
    }

    private static func ensureDirectoryExists(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

private final class GardenARShareVideoRecorder {
    private let fps: Int32 = 30
    private let videoTimescale: CMTimeScale = 600
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var timer: Timer?
    private weak var sceneView: ARSCNView?
    private var recordingStartedAt: CFTimeInterval = 0
    private var lastPresentationSeconds: Double = -1
    private var outputURL: URL?
    private var targetSize: CGSize = .zero
    private var completion: ((URL?) -> Void)?

    func start(sceneView: ARSCNView, completion: @escaping (URL?) -> Void) throws {
        stop { _ in }

        let firstFrame = sceneView.snapshot()
        let size = Self.targetSize(for: firstFrame.size)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("arbore_ar_share_\(UUID().uuidString).mp4")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        input.transform = CGAffineTransform(rotationAngle: .pi)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        guard writer.canAdd(input) else { throw CocoaError(.fileWriteUnknown) }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        self.sceneView = sceneView
        self.recordingStartedAt = CACurrentMediaTime()
        self.lastPresentationSeconds = -1
        self.outputURL = url
        self.targetSize = size
        self.completion = completion

        append(firstFrame, at: .zero)
        let timer = Timer(timeInterval: 1 / Double(fps), repeats: true) { [weak self] _ in
            self?.captureFrame()
        }
        timer.tolerance = 1 / Double(fps * 4)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop(completion: @escaping (URL?) -> Void) {
        timer?.invalidate()
        timer = nil

        guard let writer, let input else {
            completion(nil)
            return
        }

        let url = outputURL
        let storedCompletion = self.completion
        self.writer = nil
        self.input = nil
        self.adaptor = nil
        self.sceneView = nil
        self.outputURL = nil
        self.completion = nil

        input.markAsFinished()
        writer.finishWriting {
            DispatchQueue.main.async {
                let result = writer.status == .completed ? url : nil
                storedCompletion?(result)
                completion(result)
            }
        }
    }

    private func captureFrame() {
        guard let sceneView else { return }
        let elapsed = max(0, CACurrentMediaTime() - recordingStartedAt)
        let time = CMTime(seconds: elapsed, preferredTimescale: videoTimescale)
        append(sceneView.snapshot(), at: time)
    }

    private func append(_ image: UIImage, at time: CMTime) {
        let presentationSeconds = time.seconds
        guard presentationSeconds.isFinite,
              presentationSeconds > lastPresentationSeconds + 0.001 else {
            return
        }
        guard let input, let adaptor, input.isReadyForMoreMediaData,
              let buffer = image.pixelBuffer(renderSize: targetSize, pixelBufferPool: adaptor.pixelBufferPool) else {
            return
        }
        adaptor.append(buffer, withPresentationTime: time)
        lastPresentationSeconds = presentationSeconds
    }

    private static func targetSize(for source: CGSize) -> CGSize {
        let maxLongSide: CGFloat = 1280
        let ratio = min(1, maxLongSide / max(source.width, source.height))
        func even(_ value: CGFloat) -> Int {
            max(2, Int((value * ratio).rounded(.down)) / 2 * 2)
        }
        return CGSize(width: even(source.width), height: even(source.height))
    }
}

private enum GardenShareVideoThumbnailer {
    static func thumbnail(for url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)

        return await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: .zero) { cgImage, _, _ in
                guard let cgImage else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: UIImage(cgImage: cgImage))
            }
        }
    }
}

private extension UIImage {
    func pixelBuffer(renderSize: CGSize, pixelBufferPool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status: CVReturn
        if let pixelBufferPool {
            status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
        } else {
            let attrs: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(renderSize.width),
                Int(renderSize.height),
                kCVPixelFormatType_32BGRA,
                attrs as CFDictionary,
                &pixelBuffer
            )
        }
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(renderSize.width),
            height: Int(renderSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true
        let normalizedFrame = UIGraphicsImageRenderer(size: renderSize, format: rendererFormat)
            .image { _ in
                draw(in: CGRect(origin: .zero, size: renderSize))
            }

        guard let cgImage = normalizedFrame.cgImage else { return nil }
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: renderSize.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(origin: .zero, size: renderSize))
        return pixelBuffer
    }

    func rotated180() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width, y: size.height)
            context.cgContext.rotate(by: .pi)
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private extension GardenARShareComposer {
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
        let logoSize = rect.width * 0.112
        let spacing = rect.width * 0.026
        let font = UIFont.systemFont(ofSize: rect.width * 0.058, weight: .bold)
        let text = "arbore"
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let groupWidth = logoSize + spacing + textSize.width
        let groupX = rect.midX - groupWidth / 2
        let logoY = rect.maxY - bottomInset - logoSize

        cgContext.saveGState()
        let logoRect = CGRect(x: groupX, y: logoY, width: logoSize, height: logoSize)
        if let logo = UIImage(named: "arbore_logo") {
            logo.draw(in: logoRect)
        } else {
            UIColor(red: 0.13, green: 0.27, blue: 0.19, alpha: 1).setFill()
            UIBezierPath(roundedRect: logoRect, cornerRadius: logoSize * 0.22).fill()
        }
        cgContext.restoreGState()

        let textX = logoRect.maxX + spacing
        let textY = logoRect.midY - textSize.height / 2
        drawText(
            text,
            in: CGRect(x: textX, y: textY, width: textSize.width + 4, height: textSize.height),
            font: font,
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

private struct GardenShareGalleryView: View {
    let captures: [GardenShareCapture]
    let selectedCaptureID: UUID?
    let onRetake: () -> Void
    let onDelete: (GardenShareCapture) -> Void
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editingCaptureID: UUID?
    @State private var showsBranding = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var capturePendingDeletion: GardenShareCapture?
    @State private var showDeleteConfirmation = false

    init(
        captures: [GardenShareCapture],
        selectedCaptureID: UUID?,
        onRetake: @escaping () -> Void,
        onDelete: @escaping (GardenShareCapture) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.captures = captures
        self.selectedCaptureID = selectedCaptureID
        self.onRetake = onRetake
        self.onDelete = onDelete
        self.onClose = onClose
    }

    private var editingCapture: GardenShareCapture? {
        guard let editingCaptureID else { return nil }
        return captures.first { $0.id == editingCaptureID }
    }

    private var galleryColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]
    }

    var body: some View {
        ZStack {
            ArboreDesign.Colors.background.ignoresSafeArea()

            if let editingCapture {
                editSharePage(editingCapture)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                galleryPage
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onChange(of: captures.count) { _, _ in
            if let editingCaptureID, !captures.contains(where: { $0.id == editingCaptureID }) {
                self.editingCaptureID = nil
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if !shareItems.isEmpty {
                ShareSheet(items: shareItems)
            }
        }
        .confirmationDialog(
            L10n.t("AR_SHARE_DELETE_CONFIRM_TITLE"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.t("COMMON_DELETE"), role: .destructive) {
                guard let capture = capturePendingDeletion else { return }
                if editingCaptureID == capture.id {
                    editingCaptureID = nil
                }
                onDelete(capture)
                capturePendingDeletion = nil
            }
            Button(L10n.t("COMMON_CANCEL"), role: .cancel) {
                capturePendingDeletion = nil
            }
        }
    }

    private var galleryPage: some View {
        VStack(spacing: 0) {
            galleryHeader

            if captures.isEmpty {
                Spacer()
                ContentUnavailableView(
                    L10n.t("AR_SHARE_GALLERY_EMPTY"),
                    systemImage: "photo.on.rectangle.angled"
                )
                .foregroundStyle(ArboreDesign.Colors.textSecondary)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: galleryColumns, spacing: 14) {
                        ForEach(captures) { capture in
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    showsBranding = false
                                    withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                                        editingCaptureID = capture.id
                                    }
                                } label: {
                                    galleryCaptureCard(capture)
                                }
                                .buttonStyle(.plain)

                                deleteCaptureButton(capture)
                                    .padding(9)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 18)
                }
            }

            retakeButton
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
        }
    }

    private var galleryHeader: some View {
        HStack {
            Button {
                dismiss()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ArboreDesign.Colors.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(ArboreDesign.Colors.softSurface, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(L10n.t("AR_SHARE_GALLERY_TITLE"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(ArboreDesign.Colors.textPrimary)

                Text(String(format: L10n.t("AR_SHARE_GALLERY_COUNT_FORMAT"), captures.count))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(ArboreDesign.Colors.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.82)

            Spacer()

            Color.clear.frame(width: 42, height: 42)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private func deleteCaptureButton(_ capture: GardenShareCapture) -> some View {
        Button {
            capturePendingDeletion = capture
            showDeleteConfirmation = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(ArboreDesign.Colors.danger.opacity(0.92), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("COMMON_DELETE"))
    }

    private func galleryCaptureCard(_ capture: GardenShareCapture) -> some View {
        let isHighlighted = capture.id == selectedCaptureID
        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(ArboreDesign.Colors.card)

            GeometryReader { proxy in
                if let thumbnail = capture.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Image(systemName: capture.isVideo ? "video.fill" : "photo.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(ArboreDesign.Colors.textSecondary)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.62)],
                startPoint: .center,
                endPoint: .bottom
            )

            mediaTypeBadge(capture)
                .padding(10)
        }
        .aspectRatio(0.74, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    isHighlighted ? ArboreDesign.Colors.primaryGreen : ArboreDesign.Colors.border.opacity(0.72),
                    lineWidth: isHighlighted ? 3 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func editSharePage(_ capture: GardenShareCapture) -> some View {
        VStack(spacing: 14) {
            editHeader(capture)

            editMediaPreview(capture)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 18)

            if capture.image != nil {
                brandingControl
                    .padding(.horizontal, 18)
            }

            editActionRow(capture)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
        }
    }

    private func editHeader(_ capture: GardenShareCapture) -> some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                    editingCaptureID = nil
                }
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ArboreDesign.Colors.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(ArboreDesign.Colors.softSurface, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(L10n.t("AR_SHARE_MEDIA"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(ArboreDesign.Colors.textPrimary)

                Text(capture.isVideo ? L10n.t("AR_SHARE_CAPTURE_VIDEO_LABEL") : L10n.t("AR_SHARE_CAPTURE_PHOTO_LABEL"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(ArboreDesign.Colors.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.82)

            Spacer()

            Button {
                shareCurrentMedia(capture)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ArboreDesign.Colors.primaryGreen)
                    .frame(width: 42, height: 42)
                    .background(ArboreDesign.Colors.softSurface, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    @ViewBuilder
    private func editMediaPreview(_ capture: GardenShareCapture) -> some View {
        ZStack(alignment: .topTrailing) {
            if let image = renderedImage(for: capture) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let videoURL = capture.videoURL {
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .rotationEffect(.degrees(capture.requiresPlaybackRotation ? 180 : 0))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let thumbnail = capture.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            mediaTypeBadge(capture)
                .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ArboreDesign.Colors.border.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.20), radius: 20, x: 0, y: 12)
    }

    private var brandingControl: some View {
        Toggle(isOn: $showsBranding) {
            Label(L10n.t("AR_SHARE_BRANDING_TOGGLE"), systemImage: "leaf.fill")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(ArboreDesign.Colors.textPrimary)
        }
        .tint(ArboreDesign.Colors.primaryGreen)
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(ArboreDesign.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                .stroke(ArboreDesign.Colors.border.opacity(0.65), lineWidth: 1)
        )
    }

    private func editActionRow(_ capture: GardenShareCapture) -> some View {
        VStack(spacing: 10) {
            Button {
                shareCurrentMedia(capture)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text(L10n.t("AR_SHARE_MEDIA"))
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(ArboreDesign.Colors.primaryGreen)
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
            }
            .buttonStyle(.plain)

            retakeButton
        }
    }

    private var retakeButton: some View {
        Button {
            dismiss()
            onRetake()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "camera.rotate")
                Text(L10n.t("AR_RETAKE_CAPTURE"))
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(ArboreDesign.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(ArboreDesign.Colors.softSurface)
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func mediaTypeBadge(_ capture: GardenShareCapture) -> some View {
        Label(
            capture.isVideo ? L10n.t("AR_SHARE_CAPTURE_VIDEO_LABEL") : L10n.t("AR_SHARE_CAPTURE_PHOTO_LABEL"),
            systemImage: capture.isVideo ? "video.fill" : "camera.fill"
        )
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.black.opacity(0.42), in: Capsule())
    }

    private func renderedImage(for capture: GardenShareCapture) -> UIImage? {
        guard let image = capture.image else { return nil }
        guard showsBranding else { return image }
        return GardenARShareComposer.compose(
            snapshot: image,
            options: GardenShareRenderOptions(showsBranding: true)
        )
    }

    private func shareCurrentMedia(_ capture: GardenShareCapture) {
        var items: [Any] = []
        if let image = renderedImage(for: capture) {
            items.append(image)
        } else if let videoURL = capture.videoURL {
            items.append(videoURL)
        }

        guard !items.isEmpty else { return }
        shareItems = items
        showShareSheet = true
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
    var arboreSurfaceType: String? {
        get { value(forKey: "arboreSurfaceType") as? String }
        set { setValue(newValue, forKey: "arboreSurfaceType") }
    }
    var arborePlacementMode: String? {
        get { value(forKey: "arborePlacementMode") as? String }
        set { setValue(newValue, forKey: "arborePlacementMode") }
    }
    var arboreSurfaceAnchor: PersistedSurfaceAnchor? {
        get {
            guard let raw = value(forKey: "arboreSurfaceAnchorJSON") as? String,
                  let data = raw.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(PersistedSurfaceAnchor.self, from: data)
        }
        set {
            guard let newValue,
                  let data = try? JSONEncoder().encode(newValue),
                  let raw = String(data: data, encoding: .utf8) else {
                setValue(nil, forKey: "arboreSurfaceAnchorJSON")
                return
            }
            setValue(raw, forKey: "arboreSurfaceAnchorJSON")
        }
    }
    /// LOD : une version heavy existe pour cette plante (propagé à la sauvegarde
    /// pour que la ré-ouverture du jardin re-déclenche l'upgrade).
    var arboreHasHeavy: Bool {
        get { (value(forKey: "arboreHasHeavy") as? Bool) ?? false }
        set { setValue(newValue, forKey: "arboreHasHeavy") }
    }
    /// LOD courant effectivement affiché ("light" / "heavy"). Défaut "light".
    var arboreCurrentLOD: String {
        get { (value(forKey: "arboreCurrentLOD") as? String) ?? PlantLODPolicy.LOD.light.rawValue }
        set { setValue(newValue, forKey: "arboreCurrentLOD") }
    }
    /// Debounce anti-yoyo : pas de nouveau swap LOD avant ce timestamp (CACurrentMediaTime).
    var arboreLODLockedUntil: Double {
        get { (value(forKey: "arboreLODLockedUntil") as? Double) ?? 0 }
        set { setValue(newValue, forKey: "arboreLODLockedUntil") }
    }
    /// Hauteur intrinsèque (bbox non scalée, mesurée AVANT le halo) du modèle, pour
    /// le calcul de distance LOD : hauteur_monde = arboreModelRawHeight × scale.y.
    var arboreModelRawHeight: Double {
        get { (value(forKey: "arboreModelRawHeight") as? Double) ?? 0 }
        set { setValue(newValue, forKey: "arboreModelRawHeight") }
    }
}
