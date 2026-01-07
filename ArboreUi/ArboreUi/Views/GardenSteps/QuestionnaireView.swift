import SwiftUI
import RoomPlan

// MARK: - Theme Colors

extension Color {
    static let gardenPrimary = Color(hex: "#2C5530") // Dark green from screenshots
    static let gardenAccent = Color(hex: "#6ECF78")  // Light green accent
    static let gardenCardBorder = Color(hex: "#2C5530").opacity(0.2)

    /// Fond du wizard : F1F5ED en light, #1A1A1A en dark
    static var gardenBackground: Color {
        Color(UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                // #1A1A1A
                return UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
            } else {
                // #F1F5ED
                return UIColor(red: 0.945, green: 0.961, blue: 0.929, alpha: 1.0)
            }
        })
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
    
    // Gardé pour le récap / autres usages, mais plus utilisé dans la carte
    var emoji: String {
        switch self {
        case .modern: return "🏢"
        case .floral: return "🌸"
        case .wild: return "🌾"
        case .zen: return "🌿"
        case .mediterranean: return "🌴"
        case .noPreference: return "✨"
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
    
    var emoji: String {
        switch self {
        case .garden: return "🏡"
        case .balcony: return "☀️"
        case .interior: return "🏠"
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
    
    var emoji: String {
        switch self {
        case .fullSun: return "☀️"
        case .partialShade: return "⛅"
        case .shade: return "🌫️"
        case .unknown: return "🤔"
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
    
    var emoji: String {
        switch self {
        case .veryEasy: return "🫰"
        case .easy: return "🙂"
        case .demanding: return "😅"
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
    
    var emoji: String {
        switch self {
        case .pets: return "🐕"
        case .children: return "👶"
        case .none: return "🚫"
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
    
    var emoji: String {
        switch self {
        case .rich: return "🌱"
        case .dry: return "🏜️"
        case .rocky: return "🪨"
        case .waterRetentive: return "💧"
        case .unknown: return "❓"
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
    case scanMethod
    case summary
    
    var id: Int { rawValue }
}

struct GardenWizardView: View {
    @StateObject private var state = GardenWizardState()
    @State private var currentStep: GardenWizardStep = .intro

    // ouvre l’AR à la fin
    @State private var showPlacementAR = false

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
        // Version "tous les steps"
        [.intro, .style, .spaceType, .exposure, .maintenance, .safety, .soil, .scanMethod, .summary]
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

                    ScanMethodStepView(state: state, onNext: goToNext, onBack: goToPrevious)
                        .tag(GardenWizardStep.scanMethod)

                    WizardSummaryStepView(
                        state: state,
                        onBack: goToPrevious,
                        onStartAR: { showPlacementAR = true },
                        onStartLiDAR: { showPlacementAR = true },
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

        // ✅ AR placement (create)
        .fullScreenCover(isPresented: $showPlacementAR) {
            GardenARPlacementView(
                selectedPlants: selectedPlants,
                uid: uid,
                wizard: wizardDTO,
                gardenName: gardenName,
                thumbnailKey: thumbnailKey,
                existingGardenId: nil,
                mode: .create,
                onValidated: {
                    showPlacementAR = false
                    tabRouter.selectedTab = .garden
                    dismiss()
                }
            )
        }
        // ✅ super important: quand tu ré-ouvres un wizard, on repart de 0
        .onAppear {
            currentStep = .intro
            // si tu veux reset TOTAL du state à chaque nouvelle création :
            // state.style = nil; state.spaceType = nil; etc...
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
                .foregroundColor(.secondary)
                .tracking(1.2)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.1))
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
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isEnabled ? Color.gardenPrimary : Color.secondary)
            .cornerRadius(28)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryWizardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.clear)
            .opacity(configuration.isPressed ? 0.5 : 1.0)
    }
}

// MARK: - Improved Selectable Card

struct ImprovedSelectableCard: View {
    let isSelected: Bool
    let emoji: String
    let title: String
    let subtitle: String?
    let gradient: [Color]?
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        isSelected: Bool,
        emoji: String,
        title: String,
        subtitle: String? = nil,
        gradient: [Color]? = nil,
        action: @escaping () -> Void
    ) {
        self.isSelected = isSelected
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
        self.gradient = gradient
        self.action = action
    }
    
    private var cardBackground: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.06)
        : Color.white
    }
    
    private var titleColor: Color {
        colorScheme == .dark ? .white : .primary
    }
    
    private var subtitleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.7) : .secondary
    }
    
    private var iconBackground: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.08)
        : Color.gardenPrimary.opacity(0.1)
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
                    
                    Text(emoji)
                        .font(.system(size: 24))
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
                RoundedRectangle(cornerRadius: 20)
                    .fill(cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.gardenPrimary : Color.clear, lineWidth: 2)
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
                        .foregroundColor(.white)
                        .shadow(radius: 4)
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
    let emoji: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 24))
            
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
