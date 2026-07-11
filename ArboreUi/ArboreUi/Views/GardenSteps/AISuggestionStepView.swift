//
//  AISuggestionStepView.swift
//  ArboreUi
//
//  AI-powered garden suggestion step in the wizard.
//  Shows recommended plants with compatibility scores after filter selection.
//

import SwiftUI

struct AISuggestionStepView: View {
    @ObservedObject var state: GardenWizardState
    let allPlants: [Plant]
    /// Dernier step du wizard : à l'activation du CTA, le parent ouvre
    /// `GardenARPlacementView` sur le jardin tout neuf créé au step
    /// `scanMethod`. La sélection de plantes est passée en `selectedPlants`.
    let onPlaceInAR: ([Plant]) -> Void
    let onBack: () -> Void

    /// Plants accepted by the user for the garden
    @Binding var selectedPlants: [Plant]

    @Environment(\.colorScheme) private var colorScheme

    @State private var suggestion: GardenSuggestion?
    @State private var isGenerating = true
    @State private var acceptedPlantIds: Set<String> = []
    @State private var showAllPlants = false

    // Engine
    private let engine = GardenSuggestionEngine(targetPlantCount: 7)

    // MARK: - Colors

    private var cardBg: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.white
    }

    private var subtitleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.65) : .secondary
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.gardenBackground.ignoresSafeArea()

            if isGenerating {
                generatingView
            } else if let suggestion = suggestion {
                suggestionResultView(suggestion)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isGenerating {
                bottomBar
            }
        }
        .onAppear {
            generateSuggestion()
        }
    }

    // MARK: - Generating Animation

    private var generatingView: some View {
        VStack(spacing: 28) {
            Spacer()

            // Animated plant icon
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.gardenAccent.opacity(0.3),
                                Color.gardenAccent.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 30,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                // Rotating ring
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        AngularGradient(
                            colors: [Color.gardenPrimary, Color.gardenAccent, Color.gardenPrimary],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(isGenerating ? 360 : 0))
                    .animation(
                        .linear(duration: 1.5).repeatForever(autoreverses: false),
                        value: isGenerating
                    )

                // Center icon
                Image(systemName: "leaf.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.gardenPrimary, Color.gardenAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(isGenerating ? 1.1 : 0.9)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: isGenerating
                    )
            }

            VStack(spacing: 10) {
                Text(L10n.t("AI_SUGGESTION_LOADING_TITLE"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .primary)

                Text(L10n.t("AI_SUGGESTION_LOADING_SUBTITLE"))
                    .font(.system(size: 15))
                    .foregroundColor(subtitleColor)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Suggestion Result

    private func suggestionResultView(_ suggestion: GardenSuggestion) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {

                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(Color.gardenAccent)

                        Text(L10n.t("AI_SUGGESTION_RESULT_TITLE"))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .primary)
                    }

                    Text(suggestion.summary.components(separatedBy: "\n").first ?? "")
                        .font(.system(size: 15))
                        .foregroundColor(subtitleColor)
                        .lineSpacing(3)
                }
                .padding(.top, 12)

                // Confidence badge
                confidenceBadge(score: suggestion.confidenceScore)

                // Plant cards
                VStack(spacing: 12) {
                    let plantsToShow = showAllPlants ? suggestion.plants : Array(suggestion.plants.prefix(5))

                    ForEach(Array(plantsToShow.enumerated()), id: \.element.id) { index, suggested in
                        SuggestedPlantCard(
                            suggested: suggested,
                            isAccepted: acceptedPlantIds.contains(suggested.plant.id),
                            index: index
                        ) {
                            togglePlant(suggested.plant)
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }

                    if suggestion.plants.count > 5 && !showAllPlants {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                showAllPlants = true
                            }
                        } label: {
                            HStack(spacing: 8) {
                            Text(L10n.f("AI_SUGGESTION_SEE_OTHERS_FORMAT", suggestion.plants.count - 5))
                                    .font(.system(size: 15, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(Color.gardenPrimary)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.gardenPrimary.opacity(0.3), lineWidth: 1.5)
                            )
                        }
                    }
                }

                // Accept all / Deselect all
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if acceptedPlantIds.count == suggestion.plants.count {
                                acceptedPlantIds.removeAll()
                            } else {
                                acceptedPlantIds = Set(suggestion.plants.map(\.plant.id))
                            }
                        }
                    } label: {
                        let allSelected = acceptedPlantIds.count == suggestion.plants.count
                        HStack(spacing: 6) {
                            Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                            Text(allSelected ? "Tout désélectionner" : "Tout sélectionner")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(Color.gardenPrimary)
                    }

                    Spacer()

                    Text(L10n.f("AI_SUGGESTION_SELECTED_COUNT_FORMAT", acceptedPlantIds.count))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(subtitleColor)
                }
                .padding(.horizontal, 4)

                Spacer(minLength: 120)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Confidence Badge

    private func confidenceBadge(score: Double) -> some View {
        let percentage = Int(score * 100)
        let color: Color = score > 0.75
            ? Color.gardenAccent
            : score > 0.5 ? .orange : .red

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 3)
                    .frame(width: 36, height: 36)

                Circle()
                    .trim(from: 0, to: score)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))

                Text("\(percentage)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("AI_SUGGESTION_COMPATIBILITY_TITLE"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .primary)

                Text(score > 0.75 ? L10n.t("AI_SUGGESTION_COMPATIBILITY_EXCELLENT")
                     : score > 0.5 ? L10n.t("AI_SUGGESTION_COMPATIBILITY_GOOD")
                     : L10n.t("AI_SUGGESTION_COMPATIBILITY_MODERATE"))
                    .font(.system(size: 12))
                    .foregroundColor(subtitleColor)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Button(action: {
                let plantsForPlacement = acceptedPlantsForPlacement()
                selectedPlants = plantsForPlacement
                onPlaceInAR(plantsForPlacement)
            }) {
                HStack {
                    Text(acceptedPlantIds.isEmpty
                         ? L10n.t("AI_SUGGESTION_PLACE_EMPTY")
                         : L10n.f("AI_SUGGESTION_PLACE_COUNT_FORMAT", acceptedPlantIds.count))
                    Image(systemName: "arkit")
                }
            }
            .buttonStyle(PrimaryWizardButtonStyle(isEnabled: true))

            Button(L10n.t("COMMON_BACK")) { onBack() }
                .buttonStyle(SecondaryWizardButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 32)
        .background(
            LinearGradient(
                colors: [
                    Color.gardenBackground.opacity(0.0),
                    Color.gardenBackground.opacity(0.9),
                    Color.gardenBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Actions

    private func generateSuggestion() {
        isGenerating = true

        // Build the wizard DTO from current state
        let dto = GardenWizardDTO(
            style: state.style?.rawValue ?? "",
            spaceType: state.spaceType?.rawValue ?? "",
            exposure: state.exposure?.rawValue,
            maintenance: state.maintenance?.rawValue,
            safety: state.safetySelections.map { $0.rawValue },
            soil: state.soil?.rawValue,
            scanMethod: state.scanMethod?.rawValue
        )

        // Simulate a brief "AI thinking" delay for UX delight,
        // actual computation is < 50ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let result = engine.suggest(
                from: dto,
                plants: allPlants,
                locale: Locale.current.language.languageCode?.identifier ?? "fr"
            )

            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                self.suggestion = result
                // Auto-accept all plants initially
                self.acceptedPlantIds = Set(result.plants.map(\.plant.id))
                self.isGenerating = false
            }
        }
    }

    private func togglePlant(_ plant: Plant) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if acceptedPlantIds.contains(plant.id) {
                acceptedPlantIds.remove(plant.id)
            } else {
                acceptedPlantIds.insert(plant.id)
            }
        }
    }

    private func acceptedPlantsForPlacement() -> [Plant] {
        guard let suggestion else { return [] }
        return suggestion.plants
            .filter { acceptedPlantIds.contains($0.plant.id) }
            .map(\.plant)
    }
}

// MARK: - Suggested Plant Card

struct SuggestedPlantCard: View {
    let suggested: SuggestedPlant
    let isAccepted: Bool
    let index: Int
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    private var cardBg: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.white
    }

    private var scoreColor: Color {
        if suggested.score > 0.75 { return Color.gardenAccent }
        if suggested.score > 0.5 { return .orange }
        return .red
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 14) {
                // Plant thumbnail
                plantThumbnail

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggested.plant.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .primary)
                        .lineLimit(1)

                    Text(suggested.plant.type)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    // Reasons (first one)
                    if let reason = suggested.reasons.first {
                        Text(reason)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.gardenPrimary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Score + checkbox
                VStack(spacing: 8) {
                    // Score ring
                    ZStack {
                        Circle()
                            .stroke(scoreColor.opacity(0.2), lineWidth: 2.5)
                            .frame(width: 32, height: 32)

                        Circle()
                            .trim(from: 0, to: suggested.score)
                            .stroke(scoreColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .frame(width: 32, height: 32)
                            .rotationEffect(.degrees(-90))

                        Text("\(Int(suggested.score * 100))")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(scoreColor)
                    }

                    // Checkbox
                    ZStack {
                        Circle()
                            .stroke(
                                isAccepted ? Color.gardenPrimary : Color.gray.opacity(0.3),
                                lineWidth: 2
                            )
                            .frame(width: 22, height: 22)

                        if isAccepted {
                            Circle()
                                .fill(Color.gardenPrimary)
                                .frame(width: 14, height: 14)

                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isAccepted ? Color.gardenPrimary.opacity(0.4) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .shadow(
                color: isAccepted
                    ? Color.gardenPrimary.opacity(0.15)
                    : Color.black.opacity(colorScheme == .dark ? 0.4 : 0.05),
                radius: isAccepted ? 8 : 4,
                x: 0, y: 2
            )
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(Double(index) * 0.08)) {
                appeared = true
            }
        }
    }

    // MARK: - Plant Thumbnail

    @ViewBuilder
    private var plantThumbnail: some View {
        let imageURL = suggested.plant.imageURLs.first

        if let urlString = imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                case .failure:
                    plantPlaceholder

                case .empty:
                    ProgressView()
                        .frame(width: 52, height: 52)

                @unknown default:
                    plantPlaceholder
                }
            }
        } else {
            plantPlaceholder
        }
    }

    private var plantPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.gardenPrimary.opacity(0.1))
                .frame(width: 52, height: 52)

            Image(systemName: "leaf.fill")
                .font(.system(size: 20))
                .foregroundColor(Color.gardenPrimary.opacity(0.5))
        }
    }
}

// MARK: - Category Badge (unused for now, available for future use)

struct PlantCategoryBadge: View {
    let category: SuggestedPlant.PlantCategory

    var icon: String {
        switch category {
        case .tall: return "arrow.up"
        case .medium: return "arrow.left.and.right"
        case .low: return "arrow.down"
        case .groundCover: return "rectangle.fill"
        case .climbing: return "arrow.up.right"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(category.displayName)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(Color.gardenPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.gardenPrimary.opacity(0.1))
        )
    }
}
