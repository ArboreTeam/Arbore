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
    
    var title: String { rawValue }
    
    var subtitle: String {
        switch self {
        case .modern: return "Lignes épurées et géométriques"
        case .floral: return "Explosion de couleurs et parfums"
        case .wild: return "Naturel et peu d'entretien"
        case .zen: return "Calme et méditation"
        case .mediterranean: return "Résistant et aromatique"
        case .noPreference: return "Je me laisse guider"
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
    case garden = "Jardin extérieur"
    case balcony = "Terrasse / balcon"
    case interior = "Intérieur d'appartement"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .garden: return "house.and.flag"
        case .balcony: return "sun.max"
        case .interior: return "house"
        }
    }
    
    var title: String { rawValue }
    
    var subtitle: String {
        switch self {
        case .garden: return "Pleine terre, grands espaces"
        case .balcony: return "Pots, jardinières"
        case .interior: return "Plantes d'intérieur"
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
    
    var title: String { rawValue }
    
    var subtitle: String {
        switch self {
        case .fullSun: return "Le soleil tape fort toute la journée."
        case .partialShade: return "Quelques heures de soleil le matin ou le soir."
        case .shade: return "Peu ou pas de soleil direct."
        case .unknown: return "On vous aidera à le déterminer plus tard."
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
    
    var title: String { rawValue }
    
    var subtitle: String {
        switch self {
        case .veryEasy: return "Pour ceux qui n'ont pas la main verte. Arrosage minimal."
        case .easy: return "Un peu d'attention, mais rien de compliqué."
        case .demanding: return "Pour les passionnés prêts à y consacrer du temps."
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
    
    var title: String { rawValue }
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
    
    var title: String { rawValue }
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
    case aiSuggestion    // 🤖 AI garden suggestion step
    case scanMethod
    case summary
    
    var id: Int { rawValue }
}

struct GardenWizardView: View {
    @StateObject private var state = GardenWizardState()
    @State private var currentStep: GardenWizardStep = .intro

    // ouvre l’AR à la fin
    @State private var showPlacementAR = false
    @State private var showMeasurementApp = false  // 🆕 Pour lancer l'app de mesure
    @State private var showLiDARScan = false // 🆕 Pour lancer le LiDAR
    
    // 🤖 AI Suggestion: all catalogue plants + user's selection
    @State private var allCataloguePlants: [Plant] = []
    @State private var aiSelectedPlants: [Plant] = []
    
    // 🆕 Stocker les données de mesure
    @State private var measuredBoundaryPoints: [SIMD3<Float>] = []
    @State private var measuredArea: Float = 0.0
    @State private var measuredPerimeter: Float = 0.0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // ✅ router tab
    @EnvironmentObject private var tabRouter: TabRouter

    let uid: String
    let selectedPlants: [Plant]
    let onFinish: (GardenWizardState) -> Void

    // ✅ Steps visibles (logique simple = tous les steps)
    // Si tu avais une logique conditionnelle (interior/balcony/garden), je te la remets juste après.
    private var visibleSteps: [GardenWizardStep] {
        // Version "tous les steps" avec suggestion IA
        [.intro, .style, .spaceType, .exposure, .maintenance, .safety, .soil, .aiSuggestion, .scanMethod, .summary]
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

    // ✅ state -> DTO pour AR + backend
    private var wizardDTO: GardenWizardDTO {
        GardenWizardDTO(
            style: state.style?.rawValue ?? "",
            spaceType: state.spaceType?.rawValue ?? "",
            exposure: state.exposure?.rawValue,
            maintenance: state.maintenance?.rawValue,
            safety: state.safetySelections.map { $0.rawValue },
            soil: state.soil?.rawValue,
            scanMethod: state.scanMethod?.rawValue
        )
    }

    private var gardenName: String { "Mon jardin" }

    /// Si tu veux une clé d’image cohérente: utilise imageName
    private var thumbnailKey: String? { state.style?.imageName }

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

                    SoilStepView(state: state, onNext: goToNext, onBack: goToPrevious)
                        .tag(GardenWizardStep.soil)

                    AISuggestionStepView(
                        state: state,
                        allPlants: allCataloguePlants,
                        onNext: goToNext,
                        onBack: goToPrevious,
                        selectedPlants: $aiSelectedPlants
                    )
                    .tag(GardenWizardStep.aiSuggestion)

                    ScanMethodStepView(state: state, onNext: goToNext, onBack: goToPrevious)
                        .tag(GardenWizardStep.scanMethod)

                    WizardSummaryStepView(
                        state: state,
                        onBack: goToPrevious,
                        onStartAR: {
                            // 🆕 Si gardenPerimeter, lancer d'abord l'app de mesure
                            if state.scanMethod == .gardenPerimeter {
                                showMeasurementApp = true
                            } else {
                                showPlacementAR = true
                            }
                        },
                        onStartLiDAR: { showLiDARScan = true },
                        onFinishWizard: { onFinish(state) },
                        isSaving: false
                    )
                    .tag(GardenWizardStep.summary)
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

        // 🆕 Lancer l'app de mesure d'abord si gardenPerimeter
        .fullScreenCover(isPresented: $showMeasurementApp) {
            ARViewContainerMesure(
                selectedPlants: aiSelectedPlants.isEmpty ? selectedPlants : aiSelectedPlants,
                uid: uid,
                wizard: wizardDTO,
                gardenName: gardenName,
                thumbnailKey: thumbnailKey,
                onSuccess: { dismiss() }
            )
        }
        
        // 🆕 Lancer l'app LiDAR si roomScan
        .fullScreenCover(isPresented: $showLiDARScan) {
            LiDARScanWizardView(
                uid: uid,
                selectedPlants: aiSelectedPlants.isEmpty ? selectedPlants : aiSelectedPlants,
                wizard: wizardDTO,
                gardenName: gardenName,
                thumbnailKey: thumbnailKey,
                onSuccess: { dismiss() }
            )
        }

        // ✅ AR placement (create) - maintenant avec les données de mesure
        .fullScreenCover(isPresented: $showPlacementAR) {
            GardenARPlacementView(
                selectedPlants: aiSelectedPlants.isEmpty ? selectedPlants : aiSelectedPlants,
                uid: uid,
                wizard: wizardDTO,
                gardenName: gardenName,
                thumbnailKey: thumbnailKey,
                existingGardenId: nil,
                mode: .create,
                boundaryPoints: [],  // No boundaries in direct create mode
                area: 0,
                perimeter: 0,
                measurementWorldMapId: nil,  // Pas de mesure en mode direct
                onValidated: {
                    showPlacementAR = false
                    tabRouter.selectedTab = .home
                    dismiss()
                }
            )
        }
        // ✅ super important: quand tu ré-ouvres un wizard, on repart de 0
        .onAppear {
            currentStep = .intro
            // si tu veux reset TOTAL du state à chaque nouvelle création :
            // state.style = nil; state.spaceType = nil; etc...
            
            // 🤖 Fetch all catalogue plants for AI suggestion
            fetchCataloguePlants()
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
}

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
            Text("ÉTAPE \(currentIndex + 1) SUR \(total)")
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
