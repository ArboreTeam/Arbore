import SwiftUI
import RoomPlan

// MARK: - Theme Colors

extension Color {
    static let gardenPrimary = ArboreDesign.Colors.primaryGreen
    static let gardenAccent = ArboreDesign.Colors.secondaryGreen
    static let gardenCardBorder = ArboreDesign.Colors.primaryGreen.opacity(0.2)

    static var gardenBackground: Color {
        ArboreDesign.Colors.background
    }
}

// MARK: - Answer Models

enum ScanMethod: String {
    case gardenPerimeter   // ton GardenMeasureView
    case roomScan          // LiDAR / RoomPlan
}

enum GardenStyle: String, CaseIterable, Identifiable {
    case modern = "Moderne & minimaliste"
    case floral = "Fleuri & coloré"
    case wild = "Champêtre & sauvage"
    case zen = "Zen & japonais"
    case mediterranean = "Méditerranéen"
    case noPreference = "Sans préférence"

    var id: String { rawValue }

    /// Clé stable (nom de cas) utilisée pour mapper l'option sur la config
    /// distante (tier free/premium, issue #236). Indépendante du libellé affiché.
    var key: String {
        switch self {
        case .modern: return "modern"
        case .floral: return "floral"
        case .wild: return "wild"
        case .zen: return "zen"
        case .mediterranean: return "mediterranean"
        case .noPreference: return "noPreference"
        }
    }

    var iconName: String {
        switch self {
        case .modern: return "square.grid.2x2"
        case .floral: return "camera.macro"
        case .wild: return "leaf"
        case .zen: return "wind"
        case .mediterranean: return "sun.max"
        case .noPreference: return "sparkles"
        }
    }
    
    var title: String {
        switch self {
        case .modern: return L10n.t("WIZARD_STYLE_MODERN_TITLE")
        case .floral: return L10n.t("WIZARD_STYLE_FLORAL_TITLE")
        case .wild: return L10n.t("WIZARD_STYLE_WILD_TITLE")
        case .zen: return L10n.t("WIZARD_STYLE_ZEN_TITLE")
        case .mediterranean: return L10n.t("WIZARD_STYLE_MEDITERRANEAN_TITLE")
        case .noPreference: return L10n.t("WIZARD_STYLE_NO_PREFERENCE_TITLE")
        }
    }
    
    var subtitle: String {
        switch self {
        case .modern: return L10n.t("WIZARD_STYLE_MODERN_SUBTITLE")
        case .floral: return L10n.t("WIZARD_STYLE_FLORAL_SUBTITLE")
        case .wild: return L10n.t("WIZARD_STYLE_WILD_SUBTITLE")
        case .zen: return L10n.t("WIZARD_STYLE_ZEN_SUBTITLE")
        case .mediterranean: return L10n.t("WIZARD_STYLE_MEDITERRANEAN_SUBTITLE")
        case .noPreference: return L10n.t("WIZARD_STYLE_NO_PREFERENCE_SUBTITLE")
        }
    }
    
    /// 🔹 Nom de l'image dans tes assets (à adapter à tes fichiers)
    var imageName: String {
        switch self {
        case .modern:        return "modern"
        case .floral:        return "fleuri"
        case .wild:          return "sauvage"
        case .zen:           return "zen"
        case .mediterranean: return "mediterraneen"
        case .noPreference:  return ""  // pas d’image, fond uni
        }
    }
}

enum GardenSpaceType: String, CaseIterable, Identifiable {
    case interior = "Intérieur d'appartement"
    case balcony = "Terrasse / balcon"
    case terrace = "Terrasse"
    case garden = "Jardin extérieur"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .interior: return "house"
        case .balcony: return "building.2"
        case .terrace: return "chair.lounge"
        case .garden: return "house.and.flag"
        }
    }

    var title: String {
        switch self {
        case .interior: return L10n.t("WIZARD_SPACE_INTERIOR_TITLE")
        case .balcony: return L10n.t("WIZARD_SPACE_BALCONY_TITLE")
        case .terrace: return L10n.t("WIZARD_SPACE_TERRACE_TITLE")
        case .garden: return L10n.t("WIZARD_SPACE_GARDEN_TITLE")
        }
    }

    var subtitle: String {
        switch self {
        case .interior: return L10n.t("WIZARD_SPACE_INTERIOR_SUBTITLE")
        case .balcony: return L10n.t("WIZARD_SPACE_BALCONY_SUBTITLE")
        case .terrace: return L10n.t("WIZARD_SPACE_TERRACE_SUBTITLE")
        case .garden: return L10n.t("WIZARD_SPACE_GARDEN_SUBTITLE")
        }
    }

    var imageName: String {
        switch self {
        case .interior: return "space_interior"
        case .balcony: return "space_balcony"
        case .terrace: return "space_terrace"
        case .garden: return "space_garden"
        }
    }
}

enum SunExposure: String, CaseIterable, Identifiable {
    case fullSun = "Soleil direct (6h+)"
    case partialShade = "Mi-ombre"
    case shade = "Ombragé"
    case unknown = "Je ne sais pas"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .fullSun: return "sun.max"
        case .partialShade: return "cloud.sun"
        case .shade: return "cloud"
        case .unknown: return "questionmark.circle"
        }
    }
    
    var title: String {
        switch self {
        case .fullSun: return L10n.t("WIZARD_EXPOSURE_FULLSUN_TITLE")
        case .partialShade: return L10n.t("WIZARD_EXPOSURE_PARTIAL_TITLE")
        case .shade: return L10n.t("WIZARD_EXPOSURE_SHADE_TITLE")
        case .unknown: return L10n.t("WIZARD_EXPOSURE_UNKNOWN_TITLE")
        }
    }
    
    var subtitle: String {
        switch self {
        case .fullSun: return L10n.t("WIZARD_EXPOSURE_FULLSUN_SUBTITLE")
        case .partialShade: return L10n.t("WIZARD_EXPOSURE_PARTIAL_SUBTITLE")
        case .shade: return L10n.t("WIZARD_EXPOSURE_SHADE_SUBTITLE")
        case .unknown: return L10n.t("WIZARD_EXPOSURE_UNKNOWN_SUBTITLE")
        }
    }
}

enum MaintenanceLevel: String, CaseIterable, Identifiable {
    case veryEasy = "Très facile"
    case easy = "Facile"
    case demanding = "Exigeant"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .veryEasy: return "hand.thumbsup"
        case .easy: return "leaf"
        case .demanding: return "wrench.and.screwdriver"
        }
    }
    
    var title: String {
        switch self {
        case .veryEasy: return L10n.t("WIZARD_MAINTENANCE_VERY_EASY_TITLE")
        case .easy: return L10n.t("WIZARD_MAINTENANCE_EASY_TITLE")
        case .demanding: return L10n.t("WIZARD_MAINTENANCE_DEMANDING_TITLE")
        }
    }
    
    var subtitle: String {
        switch self {
        case .veryEasy: return L10n.t("WIZARD_MAINTENANCE_VERY_EASY_SUBTITLE")
        case .easy: return L10n.t("WIZARD_MAINTENANCE_EASY_SUBTITLE")
        case .demanding: return L10n.t("WIZARD_MAINTENANCE_DEMANDING_SUBTITLE")
        }
    }
}

enum SafetyOption: String, CaseIterable, Identifiable {
    case pets = "Éviter les plantes toxiques pour les animaux"
    case children = "Éviter les plantes dangereuses pour les enfants"
    case none = "Aucune contrainte"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .pets: return "pawprint"
        case .children: return "person.2"
        case .none: return "checkmark.shield"
        }
    }
    
    var title: String {
        switch self {
        case .pets: return L10n.t("WIZARD_SAFETY_PETS_TITLE")
        case .children: return L10n.t("WIZARD_SAFETY_CHILDREN_TITLE")
        case .none: return L10n.t("WIZARD_SAFETY_NONE_TITLE")
        }
    }
}

enum SoilType: String, CaseIterable, Identifiable {
    case rich = "Riche"
    case dry = "Sec"
    case rocky = "Rocailleux"
    case waterRetentive = "Retient l'eau"
    case unknown = "Je ne sais pas"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .rich: return "leaf"
        case .dry: return "sun.max"
        case .rocky: return "mountain.2"
        case .waterRetentive: return "drop"
        case .unknown: return "questionmark.circle"
        }
    }
    
    var title: String {
        switch self {
        case .rich: return L10n.t("WIZARD_SOIL_RICH_TITLE")
        case .dry: return L10n.t("WIZARD_SOIL_DRY_TITLE")
        case .rocky: return L10n.t("WIZARD_SOIL_ROCKY_TITLE")
        case .waterRetentive: return L10n.t("WIZARD_SOIL_WATER_RETENTIVE_TITLE")
        case .unknown: return L10n.t("WIZARD_SOIL_UNKNOWN_TITLE")
        }
    }
}

// MARK: - Wizard State

final class GardenWizardState: ObservableObject {
    @Published var style: GardenStyle?
    @Published var spaceType: GardenSpaceType?
    @Published var exposure: SunExposure?
    @Published var maintenance: MaintenanceLevel?
    @Published var safetySelections: Set<SafetyOption> = []
    @Published var soil: SoilType?
    @Published var scanMethod: ScanMethod?
    @Published var location: GardenLocationDTO?
    @Published var lightExposure: GardenLightExposureDTO?
    @Published var siteProfile: GardenSiteProfileDTO?
    @Published var isClimateEnrichmentPending = false
    @Published var climateEnrichmentFailed = false
    @Published var conditionalAnswers = GardenConditionalAnswersDTO()

    /// ID Mongo du jardin créé au step `scanMethod` une fois le tracé validé.
    /// Le tracé entraîne un `POST /gardens` avec `plants: []` ; cet identifiant
    /// est ensuite utilisé par le step `aiSuggestion` puis par
    /// `GardenARPlacementView` pour ouvrir le jardin en mode `.create` avec
    /// la WorldMap déjà sauvée sur disque.
    @Published var createdGardenId: String?

    /// Données mesurées au step `scanMethod` et persistées dans Mongo via le
    /// `POST /gardens` ci-dessus. Conservées en mémoire pour passer à
    /// `GardenARPlacementView` qui les recevra par paramètres.
    @Published var measuredBoundaryPoints: [SIMD3<Float>] = []
    @Published var measuredArea: Float = 0
    @Published var measuredPerimeter: Float = 0
}

// MARK: - Wizard Steps

enum GardenWizardStep: Int, CaseIterable, Identifiable {
    case intro
    case style
    case spaceType
    case exposure
    case maintenance
    case safety
    case soil
    case scanMethod      // Choose perimeter vs LiDAR room scan, then trace.
    case aiSuggestion    // 🤖 AI garden suggestion step — last step, exposes the
                         //   "Placer mes plantes en AR" CTA.

    var id: Int { rawValue }
}

struct GardenWizardView: View {
    @StateObject private var state = GardenWizardState()
    @State private var currentStep: GardenWizardStep = .intro

    // Step `scanMethod` déclenche immédiatement l'un de ces deux flows
    // selon la méthode choisie par l'utilisateur :
    // - perimeter → ouvre ARViewContainerMesure pour tracer la boundary
    // - roomScan  → ouvre LiDARScanWizardView pour le scan RoomPlan
    // À la fin de l'AR (tracé validé + POST /gardens réussi), le wizard
    // récupère le `createdGardenId` via `state.createdGardenId` et avance
    // automatiquement vers `aiSuggestion`.
    @State private var showPerimeterFlow = false
    @State private var showLiDARFlow = false
    @State private var showLocationFlow = false

    // Step `aiSuggestion` est désormais le dernier step du wizard. Au tap
    // sur « Placer mes plantes en AR », on ouvre `GardenARPlacementView`
    // en mode `.create` avec le `createdGardenId` posé au step `scanMethod`,
    // ce qui chargera la WorldMap déjà sauvée et déclenchera
    // l'auto-placement IA des plantes sélectionnées.
    struct FinalPlacementData: Identifiable {
        let id = UUID()
        let gardenId: String
        let plants: [Plant]
    }
    @State private var finalPlacementData: FinalPlacementData? = nil

    // 🤖 AI Suggestion: all catalogue plants + user's selection
    @State private var allCataloguePlants: [Plant] = []
    @State private var aiSelectedPlants: [Plant] = []
    @State private var finalPlacementPlants: [Plant] = []

    /// Les mises à jour intermédiaires du wizard sont sérialisées. Sans cela,
    /// le PUT de localisation et celui des questions pouvaient terminer dans
    /// l'ordre inverse et réécrire un snapshot plus ancien sur le backend.
    @State private var pendingWizardPersistence: Task<Void, Never>?
    @State private var pendingClimateEnrichment: Task<Void, Never>?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // ✅ router tab
    @EnvironmentObject private var tabRouter: TabRouter

    let uid: String
    let selectedPlants: [Plant]
    let onFinish: (GardenWizardState) -> Void

    private var visibleSteps: [GardenWizardStep] {
        var steps: [GardenWizardStep] = [.intro, .style, .spaceType, .exposure, .maintenance, .safety]

        if state.spaceType == .garden {
            steps.append(.soil)
        }

        // 🆕 Ordre inversé : on trace d'abord (scanMethod déclenche le
        // tracé AR + crée le jardin en base avec sa boundary), puis on
        // suggère des plantes en s'appuyant sur les vraies dimensions
        // mesurées. L'étape summary a été retirée — l'AI suggestion est
        // désormais la dernière étape et expose le CTA placement.
        steps.append(contentsOf: [.scanMethod, .aiSuggestion])
        return steps
    }

    private var currentIndex: Int {
        visibleSteps.firstIndex(of: currentStep) ?? 0
    }

    private func goToNext() {
        let nextIndex = currentIndex + 1
        if nextIndex < visibleSteps.count {
            withAnimation(.easeInOut) { currentStep = visibleSteps[nextIndex] }
        }
    }

    private func goToPrevious() {
        let prevIndex = currentIndex - 1
        if prevIndex >= 0 {
            withAnimation(.easeInOut) { currentStep = visibleSteps[prevIndex] }
        }
    }

    /// Déclenché par le CTA primaire du step `scanMethod`. Ouvre la
    /// fullScreenCover AR correspondant à la méthode choisie. À la fin de
    /// l'AR, le callback `onTraceValidated` (cf. plus bas dans la view)
    /// pose `state.createdGardenId` puis appelle `goToNext()` pour avancer
    /// vers `aiSuggestion`.
    private func startScanFlow() {
        switch state.scanMethod {
        case .roomScan:
            showLiDARFlow = true
        case .gardenPerimeter, .none:
            showPerimeterFlow = true
        }
    }

    /// Reçoit le jardin créé par la vue de scan, conserve les mesures et
    /// ouvre la capture de localisation avant la suggestion IA.
    private func handleCompletedScan(
        gardenId: String,
        boundary: [SIMD3<Float>],
        area: Float,
        perimeter: Float,
        lightExposure: GardenLightExposureDTO?,
        dismissScan: @escaping () -> Void
    ) {
        state.createdGardenId = gardenId
        state.measuredBoundaryPoints = boundary
        state.measuredArea = area
        state.measuredPerimeter = perimeter
        state.lightExposure = lightExposure
        dismissScan()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            showLocationFlow = true
        }
    }

    private func completeLocationStep(with location: GardenLocationDTO?) {
        let shouldAdvanceToSuggestion = currentStep == .scanMethod
        state.location = location
        showLocationFlow = false
        if let location {
            enqueueClimateEnrichment(for: location)
        } else {
            pendingClimateEnrichment?.cancel()
            pendingClimateEnrichment = nil
            state.isClimateEnrichmentPending = false
            state.climateEnrichmentFailed = false
        }

        // Le jardin existe déjà depuis la fin du scan : on enrichit son
        // wizard avec l'exposition, le profil déduit et la localisation
        // fraîche. La file garantit que le prochain snapshot ne pourra pas
        // être écrasé par celui-ci s'il termine plus tard.
        queueWizardPersistence(wizardDTO)

        if shouldAdvanceToSuggestion {
            Task {
                if pendingClimateEnrichment != nil {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
                await MainActor.run {
                    goToNext()
                }
            }
        }
    }

    private func enqueueClimateEnrichment(for location: GardenLocationDTO) {
        pendingClimateEnrichment?.cancel()
        state.isClimateEnrichmentPending = true
        state.climateEnrichmentFailed = false
        pendingClimateEnrichment = Task {
            do {
                let response = try await GardenAPI.shared.fetchClimateProfile(for: location)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard state.location == location else { return }
                    mergeClimateProfile(response.siteProfile)
                    queueWizardPersistence(wizardDTO)
                    state.isClimateEnrichmentPending = false
                    state.climateEnrichmentFailed = false
                    pendingClimateEnrichment = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                AppLog.gardenSave.warning(
                    "Profil climat indisponible: \(error.localizedDescription, privacy: .public)"
                )
                await MainActor.run {
                    guard state.location == location else { return }
                    state.isClimateEnrichmentPending = false
                    state.climateEnrichmentFailed = true
                    pendingClimateEnrichment = nil
                }
            }
        }
    }

    private func mergeClimateProfile(_ profile: GardenSiteProfileDTO) {
        var merged = state.siteProfile ?? GardenSiteProfileDTO()
        if let climate = profile.climate {
            merged.climate = climate
        }
        if merged.wind == nil {
            merged.wind = profile.wind
        }
        if merged.availableHeight == nil {
            merged.availableHeight = profile.availableHeight
        }
        if merged.plantingZones.isEmpty {
            merged.plantingZones = profile.plantingZones
        }
        state.siteProfile = merged
    }

    private func queueWizardPersistence(_ wizard: GardenWizardDTO) {
        guard let gardenId = state.createdGardenId else { return }
        let previousPersistence = pendingWizardPersistence

        do {
            try GardenLocalStore.saveWizard(wizard, for: gardenId)
        } catch {
            AppLog.gardenSave.warning(
                "Snapshot wizard local non sauvegardé: \(error.localizedDescription, privacy: .public)"
            )
        }

        pendingWizardPersistence = Task {
            await previousPersistence?.value
            do {
                try await GardenAPI.shared.updateGarden(
                    id: gardenId,
                    patch: GardenAPI.GardenPatch(wizard: wizard)
                )
            } catch {
                AppLog.gardenSave.warning(
                    "Mise à jour intermédiaire du wizard différée: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Ouvre directement `GardenARPlacementView` après la dernière question.
    /// La vue AR charge la WorldMap du jardin déjà créé pendant le scan.
    private func startFinalPlacement(with plants: [Plant]) {
        guard let gardenId = state.createdGardenId else { return }
        finalPlacementPlants = plants
        aiSelectedPlants = plants
        let pendingPersistence = pendingWizardPersistence
        Task {
            await pendingPersistence?.value
            await prewarmSelectedPlantModels(plants)
            await MainActor.run {
                finalPlacementData = FinalPlacementData(gardenId: gardenId, plants: plants)
            }
        }
    }

    // ✅ state -> DTO pour AR + backend
    private var wizardDTO: GardenWizardDTO {
        let wizard = GardenWizardDTO(
            style: state.style?.rawValue ?? "",
            spaceType: state.spaceType?.rawValue ?? "",
            exposure: state.exposure?.rawValue,
            maintenance: state.maintenance?.rawValue,
            safety: state.safetySelections.isEmpty
                ? nil
                : state.safetySelections.map(\.rawValue).sorted(),
            soil: state.soil?.rawValue,
            scanMethod: state.scanMethod?.rawValue,
            location: state.location,
            lightExposure: state.lightExposure,
            siteProfile: state.siteProfile,
            conditionalAnswers: state.conditionalAnswers.isEmpty
                ? nil
                : state.conditionalAnswers
        )
        return GardenSiteProfileResolver.wizardByPersistingResolvedProfile(wizard)
    }

    private var gardenName: String { L10n.t("MY_GARDEN_TITLE") }

    /// Si tu veux une clé d’image cohérente: utilise imageName
    private var thumbnailKey: String? { state.style?.imageName }

    /// Charge une seule fois les contraintes durables du foyer. Elles sont
    /// copiées dans le snapshot du jardin afin que le moteur puisse appliquer
    /// les exclusions de toxicité sans ajouter une question au parcours.
    private func loadHouseholdSafetyProfile() async {
        do {
            let response: UserResponse = try await NetworkManager.shared.request(
                endpoint: "/users/\(uid)",
                method: .GET
            )
            guard let safety = response.user?.householdSafety else { return }
            await MainActor.run {
                var selections: Set<SafetyOption> = []
                if safety.avoidPetToxicity { selections.insert(.pets) }
                if safety.avoidChildToxicity { selections.insert(.children) }
                state.safetySelections = selections
            }
        } catch {
            AppLog.gardenSave.warning(
                "Préférences de sécurité du profil indisponibles: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.gardenBackground.ignoresSafeArea()

            VStack(spacing: 0) {

                // Progress header (pas sur intro)
                if currentStep != .intro {
                    WizardProgressHeader(currentIndex: currentIndex, total: visibleSteps.count)
                        .padding(.horizontal, 24)
                        .padding(.top, 60)
                        .padding(.bottom, 12)
                }

                TabView(selection: $currentStep) {
                    IntroStepView(onNext: goToNext)
                        .tag(GardenWizardStep.intro)

                    StyleStepView(state: state, onNext: goToNext, onBack: goToPrevious)
                        .tag(GardenWizardStep.style)

                    SpaceTypeStepView(state: state, onNext: goToNext, onBack: goToPrevious)
                        .tag(GardenWizardStep.spaceType)

                    ExposureStepView(state: state, onNext: goToNext, onBack: goToPrevious)
                        .tag(GardenWizardStep.exposure)

                    MaintenanceStepView(state: state, onNext: goToNext, onBack: goToPrevious)
                        .tag(GardenWizardStep.maintenance)

                    SafetyStepView(state: state, onNext: goToNext, onBack: goToPrevious)
                        .tag(GardenWizardStep.safety)

                    if state.spaceType == .garden {
                        SoilStepView(state: state, onNext: goToNext, onBack: goToPrevious)
                            .tag(GardenWizardStep.soil)
                    }

                    ScanMethodStepView(
                        state: state,
                        onStartScan: startScanFlow,
                        onBack: goToPrevious
                    )
                    .tag(GardenWizardStep.scanMethod)

                    AISuggestionStepView(
                        state: state,
                        allPlants: allCataloguePlants,
                        onPlaceInAR: startFinalPlacement(with:),
                        onBack: goToPrevious,
                        selectedPlants: $aiSelectedPlants
                    )
                    .tag(GardenWizardStep.aiSuggestion)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            // bouton close
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(10)
                    .background(
                        Circle().fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.08))
                    )
            }
            .padding(.top, 16)
            .padding(.leading, 20)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)

        // Mode « tracer le périmètre au sol » — branche non-LiDAR.
        // ARViewContainerMesure trace les coins puis POST /gardens avec la
        // boundary (plants vides à ce stade) et renvoie le `gardenId` créé.
        // On stocke l'id et les mesures dans `state`, on ferme la cover,
        // et le wizard avance automatiquement vers `aiSuggestion`.
        .fullScreenCover(isPresented: $showPerimeterFlow) {
            ARViewContainerMesure(
                selectedPlants: [],
                uid: uid,
                wizard: wizardDTO,
                gardenName: gardenName,
                thumbnailKey: thumbnailKey,
                existingGardenId: nil,
                measurementOnly: false,
                exposureSpaceType: state.spaceType,
                onTraceValidated: { gardenId, boundary, area, perimeter, lightExposure in
                    handleCompletedScan(
                        gardenId: gardenId,
                        boundary: boundary,
                        area: area,
                        perimeter: perimeter,
                        lightExposure: lightExposure,
                        dismissScan: { showPerimeterFlow = false }
                    )
                },
                onCancel: {
                    showPerimeterFlow = false
                }
            )
        }
        // Mode « scan 3D » — branche LiDAR. Même contrat que la branche
        // perimeter : POST /gardens à la fin du scan, callback avec l'id
        // créé, retour au wizard à l'étape aiSuggestion.
        .fullScreenCover(isPresented: $showLiDARFlow) {
            LiDARScanWizardView(
                uid: uid,
                selectedPlants: [],
                wizard: wizardDTO,
                gardenName: gardenName,
                thumbnailKey: thumbnailKey,
                exposureSpaceType: state.spaceType,
                onTraceValidated: { gardenId, boundary, area, perimeter, lightExposure in
                    handleCompletedScan(
                        gardenId: gardenId,
                        boundary: boundary,
                        area: area,
                        perimeter: perimeter,
                        lightExposure: lightExposure,
                        dismissScan: { showLiDARFlow = false }
                    )
                },
                onCancel: {
                    showLiDARFlow = false
                }
            )
        }
        .fullScreenCover(isPresented: $showLocationFlow) {
            GardenLocationCaptureView(
                onReady: { location in
                    completeLocationStep(with: location)
                },
                onSkip: {
                    completeLocationStep(with: nil)
                }
            )
        }
        // Placement final — déclenché par le CTA du step `aiSuggestion`.
        // Ouvre le jardin tout neuf (créé au step `scanMethod`) en mode
        // `.create` pour que la WorldMap soit chargée mais que les plantes
        // soient instanciées à partir de `aiSelectedPlants` (pas du JSON
        // disque qui n'existe pas encore). À la validation finale, la save
        // logic de `GardenARPlacementView` détecte `existingGardenId != nil`
        // et déclenche un `PUT /gardens/:id` au lieu d'un POST.
        .fullScreenCover(item: $finalPlacementData) { data in
            GardenARPlacementView(
                selectedPlants: data.plants,
                uid: uid,
                wizard: wizardDTO,
                gardenName: gardenName,
                thumbnailKey: thumbnailKey,
                existingGardenId: data.gardenId,
                mode: .create,
                boundaryPoints: state.measuredBoundaryPoints,
                area: state.measuredArea,
                perimeter: state.measuredPerimeter,
                measurementWorldMapId: data.gardenId,
                onValidated: {
                    finalPlacementData = nil
                    onFinish(state)
                    tabRouter.selectedTab = .home
                    dismiss()
                }
            )
            .id(data.id)
        }
        // ✅ super important: quand tu ré-ouvres un wizard, on repart de 0
        .onAppear {
            currentStep = .intro
            state.scanMethod = nil
            // Reset des champs liés au tracé pour éviter qu'un ancien tracé
            // ne soit réutilisé sur une session wizard fraîche (sinon, lors
            // du second jardin créé dans la même session app, l'AR placement
            // chargerait la WorldMap du jardin précédent).
            state.createdGardenId = nil
            state.style = nil
            state.measuredBoundaryPoints = []
            state.measuredArea = 0
            state.measuredPerimeter = 0
            state.location = nil
            state.lightExposure = nil
            state.siteProfile = nil
            state.isClimateEnrichmentPending = false
            state.climateEnrichmentFailed = false
            state.conditionalAnswers = GardenConditionalAnswersDTO()
            finalPlacementPlants = []
            aiSelectedPlants = []
            pendingClimateEnrichment?.cancel()
            pendingClimateEnrichment = nil

            // 🤖 Fetch all catalogue plants for AI suggestion
            fetchCataloguePlants()
            Task {
                await loadHouseholdSafetyProfile()
            }
        }
        .onChange(of: state.spaceType) { _, newValue in
            if newValue != .garden {
                state.soil = nil
            }
            state.location = nil
            state.lightExposure = nil
            state.siteProfile = nil
            state.isClimateEnrichmentPending = false
            state.climateEnrichmentFailed = false
            state.conditionalAnswers = GardenConditionalAnswersDTO()
            pendingClimateEnrichment?.cancel()
            pendingClimateEnrichment = nil

            if !visibleSteps.contains(currentStep) {
                currentStep = visibleSteps.last ?? .aiSuggestion
            }
        }
    }

    // MARK: - Fetch Catalogue Plants for AI Suggestion

    /// Loads the full plant catalogue from the backend.
    /// Called once on wizard appear — the data is used by the AI suggestion step.
    private func fetchCataloguePlants() {
        guard allCataloguePlants.isEmpty else { return } // Already loaded
        Task {
            do {
                let plants: [Plant] = try await NetworkManager.shared.request(
                    endpoint: "/plants",
                    method: .GET
                )
                await MainActor.run {
                    self.allCataloguePlants = plants
                }
            } catch {
                print("⚠️ AI Suggestion: Failed to fetch plants — \(error.localizedDescription)")
                // Non-blocking: the AI step will work with empty array and show a message
            }
        }
    }
    
    /// Prefetch USDZ models for selected plants so AR placement can start immediately on first entry.
    private func prewarmSelectedPlantModels(_ plants: [Plant]) async {
        guard !plants.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for plant in plants {
                if let model = plant.modelURL, !model.isEmpty {
                    group.addTask {
                        do {
                            _ = try await ModelCacheManager.shared.getModelURL(for: model)
                        } catch {
                            // Non-blocking: AR will retry on demand if needed
                            print("⚠️ Prefetch model failed for \(model): \(error)")
                        }
                    }
                }
            }
        }
    }
} // <-- Added to properly close GardenWizardView struct

// MARK: - Progress Header

struct WizardProgressHeader: View {
    let currentIndex: Int
    let total: Int
    
    var progress: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(currentIndex + 1) / CGFloat(total)
    }
    
    var body: some View {
        VStack(spacing: 10) {
            Text(L10n.f("WIZARD_STEP_PROGRESS_FORMAT", currentIndex + 1, total))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ArboreDesign.Colors.textSecondary)
                .tracking(1.2)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ArboreDesign.Colors.border)
                        .frame(height: 4)
                    
                    Capsule()
                        .fill(Color.gardenPrimary)
                        .frame(width: geometry.size.width * progress, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Button Styles

struct PrimaryWizardButtonStyle: ButtonStyle {
    let isEnabled: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ArboreDesign.Typography.button)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(isEnabled ? Color.gardenPrimary : ArboreDesign.Colors.textSecondary.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryWizardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ArboreDesign.Typography.button)
            .foregroundColor(Color.gardenPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(ArboreDesign.Colors.softSurface)
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
            .opacity(configuration.isPressed ? 0.5 : 1.0)
    }
}

// MARK: - Improved Selectable Card

struct ImprovedSelectableCard: View {
    let isSelected: Bool
    let systemImage: String
    let title: String
    let subtitle: String?
    let gradient: [Color]?
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        isSelected: Bool,
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        gradient: [Color]? = nil,
        action: @escaping () -> Void
    ) {
        self.isSelected = isSelected
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.gradient = gradient
        self.action = action
    }
    
    private var cardBackground: Color {
        colorScheme == .dark
        ? ArboreDesign.Colors.cardDark
        : ArboreDesign.Colors.cardLight
    }
    
    private var titleColor: Color {
        colorScheme == .dark ? ArboreDesign.Colors.textPrimaryDark : ArboreDesign.Colors.textPrimaryLight
    }
    
    private var subtitleColor: Color {
        colorScheme == .dark ? ArboreDesign.Colors.textSecondaryDark : ArboreDesign.Colors.textSecondaryLight
    }
    
    private var iconBackground: Color {
        colorScheme == .dark
        ? Color.gardenPrimary.opacity(0.28)
        : ArboreDesign.Colors.softGreenBackground
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    if let gradient = gradient {
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: 50, height: 50)
                        .cornerRadius(12)
                    } else {
                        iconBackground
                            .frame(width: 50, height: 50)
                            .cornerRadius(12)
                    }
                    
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(gradient == nil ? Color.gardenPrimary : .white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(titleColor)
                        .multilineTextAlignment(.leading)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(subtitleColor)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.gardenPrimary : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.gardenPrimary)
                            .frame(width: 16, height: 16)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                    .fill(cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                    .stroke(isSelected ? Color.gardenPrimary : ArboreDesign.Colors.border, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(
                color: isSelected
                    ? Color.gardenPrimary.opacity(0.4)
                    : Color.black.opacity(colorScheme == .dark ? 0.6 : 0.05),
                radius: isSelected ? 10 : 4,
                x: 0, y: 2
            )
        }
        .buttonStyle(.plain)
    }
}

struct StyleCard: View {
    let style: GardenStyle
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isNoPreference: Bool {
        style == .noPreference
    }

    /// Fond pour "Sans préférence"
    private var noPrefBackground: LinearGradient {
        let top = colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.white.opacity(0.9)

        let bottom = colorScheme == .dark
            ? Color.white.opacity(0.02)
            : Color.white

        return LinearGradient(
            colors: [top, bottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        if isSelected {
            return Color.gardenAccent
        } else if isNoPreference {
            return Color.white.opacity(colorScheme == .dark ? 0.18 : 0.25)
        } else {
            return .clear
        }
    }

    private var borderWidth: CGFloat {
        if isSelected { return 3 }
        if isNoPreference { return 1 }
        return 0
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {

                // --- BACKGROUND ---
                Group {
                    if isNoPreference {
                        noPrefBackground
                    } else {
                        Image(style.imageName)
                            .resizable()
                            .scaledToFill()
                            .overlay(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.05),
                                        Color.black.opacity(0.55)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
                .frame(width: 160, height: 200)
                .clipped()

                // --- TEXT AREA ---
                VStack(alignment: .leading, spacing: isNoPreference ? 6 : 2) {

                    if isNoPreference {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(
                                colorScheme == .dark
                                ? Color.white.opacity(0.65)
                                : Color.black.opacity(0.45)
                            )
                    }

                    Text(style.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isNoPreference ? (colorScheme == .dark ? ArboreDesign.Colors.textPrimaryDark : ArboreDesign.Colors.textPrimaryLight) : .white)
                        .shadow(color: isNoPreference ? .clear : .black.opacity(0.8), radius: 4)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                .padding(14)

            }
            .frame(width: 160, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(Color.gardenAccent)
                            .frame(width: 26, height: 26)
                        Image(systemName: "checkmark")
                            .foregroundColor(.white)
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(10)
                }
            }
            .shadow(
                color: isSelected
                    ? Color.gardenAccent.opacity(0.4)
                    : Color.black.opacity(0.12),
                radius: isSelected ? 12 : 6,
                x: 0, y: 4
            )
        }
        .buttonStyle(.plain)
    }
}

struct RecapRow: View {
    let systemImage: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.gardenPrimary)
                .frame(width: 28, height: 28)
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Preview

struct QuestionnaireView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            GardenWizardView(
                uid: "TEST_UID",
                selectedPlants: [],
                onFinish: { _ in print("Wizard completed") }
            )
            .environmentObject(TabRouter()) // ✅ preview
        }
    }
}
