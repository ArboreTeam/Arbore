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
    
    // Placeholder gradient colors for style cards
    var gradientColors: [Color] {
        switch self {
        case .modern: return [Color(hex: "#4A7C59"), Color(hex: "#2C5530")]
        case .floral: return [Color(hex: "#FF6B6B"), Color(hex: "#FFE66D")]
        case .wild: return [Color(hex: "#8B7355"), Color(hex: "#D4A574")]
        case .zen: return [Color(hex: "#6B8E7D"), Color(hex: "#3D5A47")]
        case .mediterranean: return [Color(hex: "#E8B55C"), Color(hex: "#D4891D")]
        case .noPreference: return [Color(hex: "#A8A8A8"), Color(hex: "#6D6D6D")]
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
    @Published var scanMethod: ScanMethod?   // ⬅️ nouvelle propriété
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
    case scanMethod   // ⬅️ nouveau
    case summary
    
    var id: Int { rawValue }
}

struct GardenWizardView: View {
    @StateObject private var state = GardenWizardState()
    @State private var currentStep: GardenWizardStep = .intro

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let onFinish: (GardenWizardState) -> Void
    
    var visibleSteps: [GardenWizardStep] {
        var steps: [GardenWizardStep] = [.intro, .style, .spaceType]

        guard let spaceType = state.spaceType else {
            return [.intro, .style, .spaceType, .exposure, .maintenance, .safety, .soil, .scanMethod, .summary]
        }

        switch spaceType {
        case .interior:
            steps.append(contentsOf: [.maintenance, .safety, .scanMethod, .summary])
        case .balcony:
            steps.append(contentsOf: [.exposure, .maintenance, .safety, .scanMethod, .summary])
        case .garden:
            steps.append(contentsOf: [.exposure, .maintenance, .safety, .soil, .scanMethod, .summary])
        }

        return steps
    }
    
    var currentIndex: Int {
        visibleSteps.firstIndex(of: currentStep) ?? 0
    }
    
    func goToNext() {
        let nextIndex = currentIndex + 1
        if nextIndex < visibleSteps.count {
            withAnimation(.easeInOut) {
                currentStep = visibleSteps[nextIndex]
            }
        }
    }
    
    func goToPrevious() {
        let prevIndex = currentIndex - 1
        if prevIndex >= 0 {
            withAnimation(.easeInOut) {
                currentStep = visibleSteps[prevIndex]
            }
        }
    }
    
    // Couleur de la croix : noir en light, blanc en dark
    private var closeColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.gardenBackground
                .ignoresSafeArea()
            
            // --- Contenu du wizard ---
            VStack(spacing: 0) {
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

                    if visibleSteps.contains(.exposure) {
                        ExposureStepView(state: state, onNext: goToNext, onBack: goToPrevious)
                            .tag(GardenWizardStep.exposure)
                    }

                    MaintenanceStepView(state: state, onNext: goToNext, onBack: goToPrevious)
                        .tag(GardenWizardStep.maintenance)

                    SafetyStepView(state: state, onNext: goToNext, onBack: goToPrevious)
                        .tag(GardenWizardStep.safety)

                    if visibleSteps.contains(.soil) {
                        SoilStepView(state: state, onNext: goToNext, onBack: goToPrevious)
                            .tag(GardenWizardStep.soil)
                    }

                    ScanMethodStepView(state: state, onNext: goToNext, onBack: goToPrevious)
                        .tag(GardenWizardStep.scanMethod)

                    WizardSummaryStepView(
                        state: state,
                        onFinish: { onFinish(state) },
                        onBack: goToPrevious
                    )
                    .tag(GardenWizardStep.summary)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            
            // --- Bouton de fermeture global (visible sur toutes les étapes) ---
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(closeColor)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(closeColor.opacity(0.08))   // léger fond pour le contraste
                    )
            }
            .padding(.top, 16)
            .padding(.leading, 20)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
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
                    // Background track
                    Capsule()
                        .fill(Color.black.opacity(0.1))
                        .frame(height: 4)
                    
                    // Progress fill
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
    
    // Init avec valeurs par défaut pour subtitle / gradient
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
    
    // Fond de la carte
    private var cardBackground: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.06)   // carte sombre en dark
        : Color.white                 // carte blanche en light
    }
    
    // Couleurs de texte
    private var titleColor: Color {
        colorScheme == .dark ? .white : .primary
    }
    
    private var subtitleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.7) : .secondary
    }
    
    // Fond du carré emoji
    private var iconBackground: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.08)
        : Color.gardenPrimary.opacity(0.1)
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon/Emoji container
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
                
                // Selection indicator
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

// MARK: - Style Card with Image Background

struct StyleCard: View {
    let style: GardenStyle
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Background gradient (placeholder for image)
                LinearGradient(
                    colors: style.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    LinearGradient(
                        colors: [Color.black.opacity(0.1), Color.black.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                // Content
                VStack(alignment: .leading, spacing: 8) {
                    Text(style.emoji)
                        .font(.system(size: 32))
                    
                    Text(style.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .padding(20)
                
                // Selection indicator
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.gardenAccent)
                                    .frame(width: 32, height: 32)
                                
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(12)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: 160, height: 200)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(isSelected ? Color.gardenAccent : Color.clear, lineWidth: 3)
            )
            .shadow(
                color: isSelected ? Color.gardenAccent.opacity(0.4) : Color.black.opacity(0.1),
                radius: isSelected ? 12 : 4,
                x: 0, y: 4
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3), value: isSelected)
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
            GardenWizardView { state in
                print("Wizard completed")
            }
        }
    }
}
