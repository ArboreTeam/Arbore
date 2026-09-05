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
            return [.plantingMode, .drainage, .wateringCapacity]
        case .balcony, .terrace:
            return [.wind, .maximumContainerSize, .wateringCapacity]
        case .interior:
            return [.directSunDuration, .indoorHumidity, .nearbyHeat]
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

    private var climateAnalysisStatus: EssentialClimateAnalysisStatus? {
        guard state.location != nil else { return nil }

        if state.isClimateEnrichmentPending {
            return EssentialClimateAnalysisStatus(
                icon: "cloud.sun.fill",
                title: L10n.t("CLIMATE_STATUS_ANALYZING_TITLE"),
                detail: L10n.t("CLIMATE_STATUS_ANALYZING_DETAIL"),
                tint: ArboreDesign.Colors.primaryGreen,
                isLoading: true
            )
        }

        if let detail = GardenSiteProfileResolver.climateText(
            state.siteProfile?.climate,
            location: state.location
        ) {
            return EssentialClimateAnalysisStatus(
                icon: "checkmark.seal.fill",
                title: L10n.t("CLIMATE_STATUS_READY_TITLE"),
                detail: detail,
                tint: ArboreDesign.Colors.primaryGreen,
                isLoading: false
            )
        }

        if state.climateEnrichmentFailed {
            return EssentialClimateAnalysisStatus(
                icon: "exclamationmark.triangle.fill",
                title: L10n.t("CLIMATE_STATUS_UNAVAILABLE_TITLE"),
                detail: L10n.t("CLIMATE_STATUS_UNAVAILABLE_DETAIL"),
                tint: .orange,
                isLoading: false
            )
        }

        return nil
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

                        if let climateAnalysisStatus {
                            EssentialClimateAnalysisStatusView(status: climateAnalysisStatus)
                                .padding(.top, 10)
                        }
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
        selections[question] == option.id
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
        case .maximumContainerSize:
            state.conditionalAnswers.maximumContainerSize = option.id == "unknown"
                ? nil
                : GardenContainerSizeDTO(rawValue: option.id)
        case .wateringCapacity:
            state.conditionalAnswers.wateringCapacity = option.id == "unknown"
                ? nil
                : GardenWateringCapacityDTO(rawValue: option.id)
        case .directSunDuration:
            state.conditionalAnswers.directSunDuration = option.id == "unknown"
                ? nil
                : GardenDirectSunDurationDTO(rawValue: option.id)
        case .indoorHumidity:
            state.conditionalAnswers.indoorHumidity = option.id == "unknown"
                ? nil
                : GardenIndoorHumidityDTO(rawValue: option.id)
        case .nearbyHeat:
            state.conditionalAnswers.nearbyHeat = option.id == "unknown"
                ? nil
                : GardenNearbyHeatDTO(rawValue: option.id)
        }
    }

    private func restorePersistedSelections() {
        guard selections.isEmpty else { return }

        selections[.plantingMode] = state.conditionalAnswers.plantingMode?.rawValue
        selections[.drainage] = state.conditionalAnswers.drainage?.rawValue
        selections[.wind] = state.conditionalAnswers.windExposure?.rawValue
        selections[.maximumContainerSize] = state.conditionalAnswers.maximumContainerSize?.rawValue
        selections[.wateringCapacity] = state.conditionalAnswers.wateringCapacity?.rawValue
        selections[.directSunDuration] = state.conditionalAnswers.directSunDuration?.rawValue
        selections[.indoorHumidity] = state.conditionalAnswers.indoorHumidity?.rawValue
        selections[.nearbyHeat] = state.conditionalAnswers.nearbyHeat?.rawValue
    }
}

private struct EssentialClimateAnalysisStatus {
    let icon: String
    let title: String
    let detail: String?
    let tint: Color
    let isLoading: Bool
}

private struct EssentialClimateAnalysisStatusView: View {
    let status: EssentialClimateAnalysisStatus

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(status.tint.opacity(0.13))
                    .frame(width: 34, height: 34)

                if status.isLoading {
                    ProgressView()
                        .tint(status.tint)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: status.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(status.tint)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(ArboreDesign.Colors.textPrimary)

                if let detail = status.detail {
                    Text(detail)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(status.tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(status.tint.opacity(0.18), lineWidth: 1)
        )
    }
}

private enum EssentialQuestionID: String, Identifiable {
    case plantingMode
    case drainage
    case wind
    case maximumContainerSize
    case wateringCapacity
    case directSunDuration
    case indoorHumidity
    case nearbyHeat

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

    static let maximumContainerSize = EssentialQuestion(
        id: .maximumContainerSize,
        titleKey: "ESSENTIAL_BALCONY_POT_SIZE_QUESTION",
        icon: "shippingbox",
        options: [
            EssentialOption(id: GardenContainerSizeDTO.small.rawValue, titleKey: "ESSENTIAL_POT_SIZE_SMALL", icon: "cube.fill"),
            EssentialOption(id: GardenContainerSizeDTO.medium.rawValue, titleKey: "ESSENTIAL_POT_SIZE_MEDIUM", icon: "shippingbox.fill"),
            EssentialOption(id: GardenContainerSizeDTO.large.rawValue, titleKey: "ESSENTIAL_POT_SIZE_LARGE", icon: "shippingbox.and.arrow.backward.fill"),
            unknown
        ]
    )

    static let wateringCapacity = EssentialQuestion(
        id: .wateringCapacity,
        titleKey: "ESSENTIAL_WATERING_CAPACITY_QUESTION",
        icon: "drop.circle",
        options: [
            EssentialOption(id: GardenWateringCapacityDTO.low.rawValue, titleKey: "ESSENTIAL_WATERING_LOW", icon: "calendar"),
            EssentialOption(id: GardenWateringCapacityDTO.regular.rawValue, titleKey: "ESSENTIAL_WATERING_REGULAR", icon: "drop.fill"),
            EssentialOption(id: GardenWateringCapacityDTO.frequent.rawValue, titleKey: "ESSENTIAL_WATERING_FREQUENT", icon: "drop.triangle.fill"),
            unknown
        ]
    )

    static let directSunDuration = EssentialQuestion(
        id: .directSunDuration,
        titleKey: "ESSENTIAL_INTERIOR_DIRECT_SUN_QUESTION",
        icon: "sun.max",
        options: [
            EssentialOption(id: GardenDirectSunDurationDTO.none.rawValue, titleKey: "ESSENTIAL_DIRECT_SUN_NONE", icon: "moon.fill"),
            EssentialOption(id: GardenDirectSunDurationDTO.oneToThreeHours.rawValue, titleKey: "ESSENTIAL_DIRECT_SUN_1_3", icon: "sun.min.fill"),
            EssentialOption(id: GardenDirectSunDurationDTO.fourToSixHours.rawValue, titleKey: "ESSENTIAL_DIRECT_SUN_4_6", icon: "sun.max.fill"),
            EssentialOption(id: GardenDirectSunDurationDTO.moreThanSixHours.rawValue, titleKey: "ESSENTIAL_DIRECT_SUN_6_PLUS", icon: "sun.max.trianglebadge.exclamationmark.fill"),
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
            EssentialOption(id: GardenNearbyHeatDTO.airConditioning.rawValue, titleKey: "ESSENTIAL_HEAT_AIR_CONDITIONING", icon: "snowflake"),
            EssentialOption(id: GardenNearbyHeatDTO.heatingAndAirConditioning.rawValue, titleKey: "ESSENTIAL_HEAT_BOTH", icon: "thermometer.medium"),
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
