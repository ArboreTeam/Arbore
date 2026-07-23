import SwiftUI

/// Trois questions déclaratives maximum, choisies selon l'espace. Cette étape
/// vient après la localisation : elle ne redemande jamais une donnée déjà
/// mesurée ou déduite par Arbore.
struct EssentialQuestionsStepView: View {
    @ObservedObject var state: GardenWizardState
    let onContinue: () -> Void
    let onBack: () -> Void
    let onProgressChange: (_ currentIndex: Int, _ total: Int) -> Void

    @State private var selections: [EssentialQuestionID: String] = [:]
    @State private var currentQuestionIndex = 0

    private var questions: [EssentialQuestion] {
        switch state.spaceType {
        case .garden:
            return [.plantingMode, .drainage, .safety]
        case .balcony, .terrace:
            return [.wind, .containerProject, .safety]
        case .interior:
            return [.indoorHumidity, .nearbyHeat, .safety]
        case .none:
            return []
        }
    }

    private var currentQuestion: EssentialQuestion? {
        guard questions.indices.contains(currentQuestionIndex) else { return nil }
        return questions[currentQuestionIndex]
    }

    private var isLastQuestion: Bool {
        currentQuestionIndex == questions.count - 1
    }

    var body: some View {
        ZStack {
            Color.gardenBackground
                .ignoresSafeArea()

            if let currentQuestion {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.t(currentQuestion.titleKey))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(ArboreDesign.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(L10n.t("ESSENTIAL_QUESTIONS_SUBTITLE"))
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 24)

                    ScrollView(showsIndicators: false) {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 16
                        ) {
                            ForEach(currentQuestion.options) { option in
                                EssentialAnswerCard(
                                    option: option,
                                    isSelected: isSelected(option, for: currentQuestion.id)
                                ) {
                                    select(option, for: currentQuestion.id)
                                }
                            }
                        }
                        .id(currentQuestion.id)
                        .padding(.horizontal, 24)
                        .padding(.top, 15)
                        .padding(.bottom, 120)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: continueToNextQuestion) {
                    HStack {
                        Text(L10n.t("COMMON_CONTINUE"))
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryWizardButtonStyle(isEnabled: true))

                Button(L10n.t("COMMON_BACK"), action: goBack)
                    .buttonStyle(SecondaryWizardButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .background(
                LinearGradient(
                    colors: [
                        Color.gardenBackground.opacity(0),
                        Color.gardenBackground.opacity(0.99),
                        Color.gardenBackground
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 260)
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .onAppear {
            restorePersistedSelections()
            currentQuestionIndex = min(currentQuestionIndex, max(questions.count - 1, 0))
            reportProgress()
        }
        .onChange(of: state.spaceType) { _, _ in
            currentQuestionIndex = 0
            reportProgress(index: 0)
        }
    }

    private func continueToNextQuestion() {
        guard !isLastQuestion else {
            onContinue()
            return
        }

        let nextIndex = currentQuestionIndex + 1
        withAnimation(.easeInOut(duration: 0.22)) {
            currentQuestionIndex = nextIndex
        }
        reportProgress(index: nextIndex)
    }

    private func goBack() {
        guard currentQuestionIndex > 0 else {
            onBack()
            return
        }

        let previousIndex = currentQuestionIndex - 1
        withAnimation(.easeInOut(duration: 0.22)) {
            currentQuestionIndex = previousIndex
        }
        reportProgress(index: previousIndex)
    }

    private func reportProgress(index: Int? = nil) {
        guard !questions.isEmpty else { return }
        onProgressChange(index ?? currentQuestionIndex, questions.count)
    }

    private func isSelected(_ option: EssentialOption, for question: EssentialQuestionID) -> Bool {
        guard question == .safety else {
            return selections[question] == option.id
        }

        switch option.id {
        case "pets":
            return state.safetySelections.contains(.pets)
        case "children":
            return state.safetySelections.contains(.children)
        case "none":
            return state.safetySelections.contains(.none)
        case "unknown":
            return selections[.safety] == "unknown"
        default:
            return false
        }
    }

    private func select(_ option: EssentialOption, for question: EssentialQuestionID) {
        withAnimation(.easeInOut(duration: 0.18)) {
            selections[question] = option.id
        }

        switch question {
        case .plantingMode:
            state.conditionalAnswers.plantingMode = option.id == "unknown"
                ? nil
                : GardenPlantingModeDTO(rawValue: option.id)
        case .drainage:
            state.conditionalAnswers.drainage = option.id == "unknown"
                ? nil
                : GardenDrainageDTO(rawValue: option.id)
        case .wind:
            state.conditionalAnswers.windExposure = option.id == "unknown"
                ? nil
                : GardenWindExposureDTO(rawValue: option.id)
        case .containerProject:
            state.conditionalAnswers.containerProject = option.id == "unknown"
                ? nil
                : GardenContainerProjectDTO(rawValue: option.id)
        case .indoorHumidity:
            state.conditionalAnswers.indoorHumidity = option.id == "unknown"
                ? nil
                : GardenIndoorHumidityDTO(rawValue: option.id)
        case .nearbyHeat:
            state.conditionalAnswers.nearbyHeat = option.id == "unknown"
                ? nil
                : GardenNearbyHeatDTO(rawValue: option.id)
        case .safety:
            applySafety(option.id)
        }
    }

    private func applySafety(_ optionID: String) {
        switch optionID {
        case "pets":
            selections[.safety] = nil
            state.safetySelections.remove(.none)
            if state.safetySelections.contains(.pets) {
                state.safetySelections.remove(.pets)
            } else {
                state.safetySelections.insert(.pets)
            }
        case "children":
            selections[.safety] = nil
            state.safetySelections.remove(.none)
            if state.safetySelections.contains(.children) {
                state.safetySelections.remove(.children)
            } else {
                state.safetySelections.insert(.children)
            }
        case "none":
            selections[.safety] = "none"
            state.safetySelections = [.none]
        default:
            selections[.safety] = "unknown"
            state.safetySelections = []
        }
    }

    private func restorePersistedSelections() {
        guard selections.isEmpty else { return }

        selections[.plantingMode] = state.conditionalAnswers.plantingMode?.rawValue
        selections[.drainage] = state.conditionalAnswers.drainage?.rawValue
        selections[.wind] = state.conditionalAnswers.windExposure?.rawValue
        selections[.containerProject] = state.conditionalAnswers.containerProject?.rawValue
        selections[.indoorHumidity] = state.conditionalAnswers.indoorHumidity?.rawValue
        selections[.nearbyHeat] = state.conditionalAnswers.nearbyHeat?.rawValue

        if state.safetySelections == [.pets] {
            selections[.safety] = nil
        } else if state.safetySelections == [.children] {
            selections[.safety] = nil
        } else if state.safetySelections.contains(.pets), state.safetySelections.contains(.children) {
            selections[.safety] = nil
        } else if state.safetySelections.contains(.none) {
            selections[.safety] = "none"
        }
    }
}

private enum EssentialQuestionID: String, Identifiable {
    case plantingMode
    case drainage
    case wind
    case containerProject
    case indoorHumidity
    case nearbyHeat
    case safety

    var id: String { rawValue }
}

private struct EssentialOption: Identifiable {
    let id: String
    let titleKey: String
    let icon: String
}

private struct EssentialQuestion: Identifiable {
    let id: EssentialQuestionID
    let titleKey: String
    let icon: String
    let options: [EssentialOption]

    static let unknown = EssentialOption(
        id: "unknown",
        titleKey: "ESSENTIAL_OPTION_UNKNOWN",
        icon: "questionmark"
    )

    static let plantingMode = EssentialQuestion(
        id: .plantingMode,
        titleKey: "ESSENTIAL_GARDEN_PLANTING_QUESTION",
        icon: "leaf.circle",
        options: [
            EssentialOption(id: GardenPlantingModeDTO.inGround.rawValue, titleKey: "ESSENTIAL_PLANTING_IN_GROUND", icon: "leaf.fill"),
            EssentialOption(id: GardenPlantingModeDTO.containers.rawValue, titleKey: "ESSENTIAL_PLANTING_CONTAINERS", icon: "shippingbox.fill"),
            EssentialOption(id: GardenPlantingModeDTO.both.rawValue, titleKey: "ESSENTIAL_OPTION_BOTH", icon: "square.grid.2x2.fill"),
            unknown
        ]
    )

    static let drainage = EssentialQuestion(
        id: .drainage,
        titleKey: "ESSENTIAL_GARDEN_DRAINAGE_QUESTION",
        icon: "drop.circle",
        options: [
            EssentialOption(id: GardenDrainageDTO.fast.rawValue, titleKey: "ESSENTIAL_DRAINAGE_FAST", icon: "bolt.fill"),
            EssentialOption(id: GardenDrainageDTO.normal.rawValue, titleKey: "ESSENTIAL_DRAINAGE_NORMAL", icon: "drop.fill"),
            EssentialOption(id: GardenDrainageDTO.slow.rawValue, titleKey: "ESSENTIAL_DRAINAGE_SLOW", icon: "water.waves"),
            unknown
        ]
    )

    static let wind = EssentialQuestion(
        id: .wind,
        titleKey: "ESSENTIAL_BALCONY_WIND_QUESTION",
        icon: "wind",
        options: [
            EssentialOption(id: GardenWindExposureDTO.sheltered.rawValue, titleKey: "ESSENTIAL_WIND_SHELTERED", icon: "house.fill"),
            EssentialOption(id: GardenWindExposureDTO.sometimesWindy.rawValue, titleKey: "ESSENTIAL_WIND_SOMETIMES", icon: "wind"),
            EssentialOption(id: GardenWindExposureDTO.veryExposed.rawValue, titleKey: "ESSENTIAL_WIND_EXPOSED", icon: "tornado"),
            unknown
        ]
    )

    static let containerProject = EssentialQuestion(
        id: .containerProject,
        titleKey: "ESSENTIAL_BALCONY_POTS_QUESTION",
        icon: "shippingbox",
        options: [
            EssentialOption(id: GardenContainerProjectDTO.existingPots.rawValue, titleKey: "ESSENTIAL_POTS_EXISTING", icon: "shippingbox.fill"),
            EssentialOption(id: GardenContainerProjectDTO.newComposition.rawValue, titleKey: "ESSENTIAL_POTS_NEW", icon: "sparkles"),
            EssentialOption(id: GardenContainerProjectDTO.both.rawValue, titleKey: "ESSENTIAL_OPTION_BOTH", icon: "square.grid.2x2.fill"),
            unknown
        ]
    )

    static let indoorHumidity = EssentialQuestion(
        id: .indoorHumidity,
        titleKey: "ESSENTIAL_INTERIOR_HUMIDITY_QUESTION",
        icon: "humidity",
        options: [
            EssentialOption(id: GardenIndoorHumidityDTO.dry.rawValue, titleKey: "ESSENTIAL_HUMIDITY_DRY", icon: "sun.max.fill"),
            EssentialOption(id: GardenIndoorHumidityDTO.normal.rawValue, titleKey: "ESSENTIAL_HUMIDITY_NORMAL", icon: "drop.halffull"),
            EssentialOption(id: GardenIndoorHumidityDTO.humid.rawValue, titleKey: "ESSENTIAL_HUMIDITY_HUMID", icon: "drop.fill"),
            unknown
        ]
    )

    static let nearbyHeat = EssentialQuestion(
        id: .nearbyHeat,
        titleKey: "ESSENTIAL_INTERIOR_HEAT_QUESTION",
        icon: "heater.vertical",
        options: [
            EssentialOption(id: GardenNearbyHeatDTO.none.rawValue, titleKey: "ESSENTIAL_HEAT_NONE", icon: "checkmark"),
            EssentialOption(id: GardenNearbyHeatDTO.radiator.rawValue, titleKey: "ESSENTIAL_HEAT_RADIATOR", icon: "flame.fill"),
            EssentialOption(id: GardenNearbyHeatDTO.underfloorHeating.rawValue, titleKey: "ESSENTIAL_HEAT_FLOOR", icon: "wave.3.up"),
            unknown
        ]
    )

    static let safety = EssentialQuestion(
        id: .safety,
        titleKey: "ESSENTIAL_SAFETY_QUESTION",
        icon: "checkmark.shield",
        options: [
            EssentialOption(id: "pets", titleKey: "ESSENTIAL_SAFETY_PETS", icon: "pawprint.fill"),
            EssentialOption(id: "children", titleKey: "ESSENTIAL_SAFETY_CHILDREN", icon: "person.fill"),
            EssentialOption(id: "none", titleKey: "ESSENTIAL_SAFETY_NONE", icon: "checkmark.shield.fill"),
            unknown
        ]
    )
}

private struct EssentialAnswerCard: View {
    let option: EssentialOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        ArboreDesign.Colors.primaryGreen.opacity(0.72),
                        Color.gardenAccent.opacity(0.32),
                        ArboreDesign.Colors.card
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: option.icon)
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundColor(.white.opacity(0.20))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(18)

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.58)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Text(L10n.t(option.titleKey))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.8), radius: 4)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .padding(14)
            }
            .frame(width: 160, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        isSelected ? Color.gardenAccent : .clear,
                        lineWidth: isSelected ? 3 : 0
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(Color.gardenAccent)
                            .frame(width: 26, height: 26)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(10)
                }
            }
            .shadow(
                color: isSelected
                    ? Color.gardenAccent.opacity(0.4)
                    : Color.black.opacity(0.12),
                radius: isSelected ? 12 : 6,
                x: 0,
                y: 4
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
