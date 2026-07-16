import SwiftUI

/// Trois questions déclaratives maximum, choisies selon l'espace. Cette étape
/// vient après la localisation : elle ne redemande jamais une donnée déjà
/// mesurée ou déduite par Arbore.
struct EssentialQuestionsStepView: View {
    @ObservedObject var state: GardenWizardState
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var selections: [EssentialQuestionID: String] = [:]

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

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.t("ESSENTIAL_QUESTIONS_TITLE"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(ArboreDesign.Colors.textPrimary)

                Text(L10n.t("ESSENTIAL_QUESTIONS_SUBTITLE"))
                    .font(.system(size: 15))
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(questions) { question in
                        EssentialQuestionCard(
                            question: question,
                            selection: selections[question.id]
                        ) { option in
                            select(option, for: question.id)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 140)
            }
        }
        .background(Color.gardenBackground)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(action: onContinue) {
                    HStack(spacing: 9) {
                        Text(L10n.t("ESSENTIAL_QUESTIONS_CONTINUE"))
                        Image(systemName: "sparkles")
                    }
                }
                .buttonStyle(PrimaryWizardButtonStyle(isEnabled: true))

                Button {
                    resetAnswers()
                    onSkip()
                } label: {
                    Text(L10n.t("ESSENTIAL_QUESTIONS_SKIP"))
                }
                .buttonStyle(SecondaryWizardButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 24)
            .background(
                LinearGradient(
                    colors: [
                        Color.gardenBackground.opacity(0),
                        Color.gardenBackground.opacity(0.98),
                        Color.gardenBackground
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 190)
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .onAppear(perform: restorePersistedSelections)
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
            state.safetySelections = [.pets]
        case "children":
            state.safetySelections = [.children]
        case "both":
            state.safetySelections = [.pets, .children]
        case "none":
            state.safetySelections = [.none]
        default:
            state.safetySelections = []
        }
    }

    private func resetAnswers() {
        selections = [:]
        state.conditionalAnswers = GardenConditionalAnswersDTO()
        state.safetySelections = []
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
            selections[.safety] = "pets"
        } else if state.safetySelections == [.children] {
            selections[.safety] = "children"
        } else if state.safetySelections.contains(.pets), state.safetySelections.contains(.children) {
            selections[.safety] = "both"
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
}

private struct EssentialQuestion: Identifiable {
    let id: EssentialQuestionID
    let titleKey: String
    let icon: String
    let options: [EssentialOption]

    static let unknown = EssentialOption(id: "unknown", titleKey: "ESSENTIAL_OPTION_UNKNOWN")

    static let plantingMode = EssentialQuestion(
        id: .plantingMode,
        titleKey: "ESSENTIAL_GARDEN_PLANTING_QUESTION",
        icon: "leaf.circle",
        options: [
            EssentialOption(id: GardenPlantingModeDTO.inGround.rawValue, titleKey: "ESSENTIAL_PLANTING_IN_GROUND"),
            EssentialOption(id: GardenPlantingModeDTO.containers.rawValue, titleKey: "ESSENTIAL_PLANTING_CONTAINERS"),
            EssentialOption(id: GardenPlantingModeDTO.both.rawValue, titleKey: "ESSENTIAL_OPTION_BOTH"),
            unknown
        ]
    )

    static let drainage = EssentialQuestion(
        id: .drainage,
        titleKey: "ESSENTIAL_GARDEN_DRAINAGE_QUESTION",
        icon: "drop.circle",
        options: [
            EssentialOption(id: GardenDrainageDTO.fast.rawValue, titleKey: "ESSENTIAL_DRAINAGE_FAST"),
            EssentialOption(id: GardenDrainageDTO.normal.rawValue, titleKey: "ESSENTIAL_DRAINAGE_NORMAL"),
            EssentialOption(id: GardenDrainageDTO.slow.rawValue, titleKey: "ESSENTIAL_DRAINAGE_SLOW"),
            unknown
        ]
    )

    static let wind = EssentialQuestion(
        id: .wind,
        titleKey: "ESSENTIAL_BALCONY_WIND_QUESTION",
        icon: "wind",
        options: [
            EssentialOption(id: GardenWindExposureDTO.sheltered.rawValue, titleKey: "ESSENTIAL_WIND_SHELTERED"),
            EssentialOption(id: GardenWindExposureDTO.sometimesWindy.rawValue, titleKey: "ESSENTIAL_WIND_SOMETIMES"),
            EssentialOption(id: GardenWindExposureDTO.veryExposed.rawValue, titleKey: "ESSENTIAL_WIND_EXPOSED"),
            unknown
        ]
    )

    static let containerProject = EssentialQuestion(
        id: .containerProject,
        titleKey: "ESSENTIAL_BALCONY_POTS_QUESTION",
        icon: "shippingbox",
        options: [
            EssentialOption(id: GardenContainerProjectDTO.existingPots.rawValue, titleKey: "ESSENTIAL_POTS_EXISTING"),
            EssentialOption(id: GardenContainerProjectDTO.newComposition.rawValue, titleKey: "ESSENTIAL_POTS_NEW"),
            EssentialOption(id: GardenContainerProjectDTO.both.rawValue, titleKey: "ESSENTIAL_OPTION_BOTH"),
            unknown
        ]
    )

    static let indoorHumidity = EssentialQuestion(
        id: .indoorHumidity,
        titleKey: "ESSENTIAL_INTERIOR_HUMIDITY_QUESTION",
        icon: "humidity",
        options: [
            EssentialOption(id: GardenIndoorHumidityDTO.dry.rawValue, titleKey: "ESSENTIAL_HUMIDITY_DRY"),
            EssentialOption(id: GardenIndoorHumidityDTO.normal.rawValue, titleKey: "ESSENTIAL_HUMIDITY_NORMAL"),
            EssentialOption(id: GardenIndoorHumidityDTO.humid.rawValue, titleKey: "ESSENTIAL_HUMIDITY_HUMID"),
            unknown
        ]
    )

    static let nearbyHeat = EssentialQuestion(
        id: .nearbyHeat,
        titleKey: "ESSENTIAL_INTERIOR_HEAT_QUESTION",
        icon: "heater.vertical",
        options: [
            EssentialOption(id: GardenNearbyHeatDTO.none.rawValue, titleKey: "ESSENTIAL_HEAT_NONE"),
            EssentialOption(id: GardenNearbyHeatDTO.radiator.rawValue, titleKey: "ESSENTIAL_HEAT_RADIATOR"),
            EssentialOption(id: GardenNearbyHeatDTO.underfloorHeating.rawValue, titleKey: "ESSENTIAL_HEAT_FLOOR"),
            unknown
        ]
    )

    static let safety = EssentialQuestion(
        id: .safety,
        titleKey: "ESSENTIAL_SAFETY_QUESTION",
        icon: "checkmark.shield",
        options: [
            EssentialOption(id: "pets", titleKey: "ESSENTIAL_SAFETY_PETS"),
            EssentialOption(id: "children", titleKey: "ESSENTIAL_SAFETY_CHILDREN"),
            EssentialOption(id: "both", titleKey: "ESSENTIAL_OPTION_BOTH"),
            EssentialOption(id: "none", titleKey: "ESSENTIAL_SAFETY_NONE"),
            unknown
        ]
    )
}

private struct EssentialQuestionCard: View {
    let question: EssentialQuestion
    let selection: String?
    let onSelect: (EssentialOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: question.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
                    .frame(width: 32, height: 32)
                    .background(ArboreDesign.Colors.primaryGreen.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(L10n.t(question.titleKey))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            EssentialOptionsLayout(spacing: 7) {
                ForEach(question.options) { option in
                    EssentialOptionChip(
                        title: L10n.t(option.titleKey),
                        isSelected: selection == option.id
                    ) {
                        onSelect(option)
                    }
                }
            }
        }
        .padding(14)
        .background(ArboreDesign.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
        )
    }
}

private struct EssentialOptionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                }

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : ArboreDesign.Colors.textPrimary)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(
                isSelected
                    ? ArboreDesign.Colors.primaryGreen
                    : ArboreDesign.Colors.softSurface
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Color.clear : ArboreDesign.Colors.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Petit flow layout pour garder toutes les réponses visibles sans carrousel
/// horizontal. Les puces passent simplement à la ligne sur les petits iPhone.
private struct EssentialOptionsLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > width {
                totalHeight += rowHeight + spacing
                maxWidth = max(maxWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }

        totalHeight += rowHeight
        maxWidth = max(maxWidth, rowWidth)
        return CGSize(width: min(maxWidth, width), height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
