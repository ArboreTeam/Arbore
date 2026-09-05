import SwiftUI

enum PlantCatalogQuickPreference: String, CaseIterable, Identifiable {
    case flowering
    case compact
    case easyCare

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .flowering: return "AR_CATALOG_QUICK_FLOWERING"
        case .compact: return "AR_CATALOG_QUICK_COMPACT"
        case .easyCare: return "AR_CATALOG_QUICK_EASY"
        }
    }

    var icon: String {
        switch self {
        case .flowering: return "camera.macro"
        case .compact: return "arrow.down.right.and.arrow.up.left"
        case .easyCare: return "hand.thumbsup.fill"
        }
    }
}

struct PlantCatalogQuickChip: View {
    let preference: PlantCatalogQuickPreference
    let isSelected: Bool
    let action: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        Button(action: action) {
            Label(L10n.t(preference.titleKey), systemImage: preference.icon)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : themeManager.secondaryTextColor)
                .lineLimit(1)
                .padding(.horizontal, 13)
                .frame(height: 36)
                .background(isSelected ? themeManager.brandPrimary : themeManager.cardBackgroundColor)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? themeManager.brandPrimary : themeManager.separatorColor.opacity(0.8),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

struct PlantCatalogPreferenceSheet: View {
    let wizard: GardenWizardDTO
    let placementMode: ARPlacementMode
    let resultCount: (PlantCatalogFilters) -> Int
    let onApply: (PlantCatalogFilters) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var draft: PlantCatalogFilters

    init(
        currentFilters: PlantCatalogFilters,
        wizard: GardenWizardDTO,
        placementMode: ARPlacementMode,
        resultCount: @escaping (PlantCatalogFilters) -> Int,
        onApply: @escaping (PlantCatalogFilters) -> Void
    ) {
        self.wizard = wizard
        self.placementMode = placementMode
        self.resultCount = resultCount
        self.onApply = onApply
        _draft = State(initialValue: currentFilters)
    }

    private var availableGoals: [PlantCatalogGoal] {
        if placementMode == .ceiling {
            return [.addColor, .focalPoint]
        }
        if placementMode == .wall {
            return [.addColor, .createPrivacy, .focalPoint]
        }

        switch GardenSpaceType(rawValue: wizard.spaceType) {
        case .interior:
            return [.addColor, .addVolume, .createCascade, .focalPoint]
        case .balcony, .terrace:
            return [
                .addColor, .createPrivacy, .addVolume, .coverWall,
                .createCascade, .attractPollinators, .edibleAromatic, .focalPoint
            ]
        case .garden:
            return [
                .addColor, .createPrivacy, .addVolume, .coverWall, .coverGround,
                .attractPollinators, .edibleAromatic, .focalPoint
            ]
        case .none:
            return PlantCatalogGoal.allCases
        }
    }

    private var availableKinds: [PlantCatalogKind] {
        guard placementMode == .floor else { return [] }

        switch GardenSpaceType(rawValue: wizard.spaceType) {
        case .interior:
            return [.greenPlant, .floweringPlant, .cactusSucculent, .palm, .fern, .orchid, .climbing]
        case .balcony, .terrace:
            return [
                .floweringPlant, .tree, .shrub, .perennial, .annual,
                .grass, .climbing, .aromaticEdible
            ]
        case .garden:
            return [
                .tree, .shrub, .perennial, .annual, .grass,
                .groundcover, .climbing, .aromaticEdible, .floweringPlant
            ]
        case .none:
            return PlantCatalogKind.allCases
        }
    }

    private var availableHabits: [PlantCatalogHabit] {
        placementMode == .floor ? PlantCatalogHabit.allCases : []
    }

    private var visibleSections: [PlantPreferenceSection] {
        var sections: [PlantPreferenceSection] = [.goals]
        if !availableKinds.isEmpty { sections.append(.kinds) }
        sections.append(contentsOf: [.appearance, .dimensions, .care])
        return sections
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.backgroundColor.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        automaticAdaptationCard

                        Text(L10n.t("AR_CATALOG_PREFERENCES_TITLE"))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(themeManager.secondaryTextColor)
                            .tracking(0.7)

                        VStack(spacing: 10) {
                            ForEach(visibleSections) { section in
                                NavigationLink(value: section) {
                                    PlantPreferenceCategoryRow(
                                        section: section,
                                        summary: summary(for: section),
                                        selectionCount: selectionCount(for: section)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle(L10n.t("AR_CATALOG_FILTERS_TITLE"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(themeManager.textColor)
                    .accessibilityLabel(L10n.t("COMMON_CANCEL"))
                }

                ToolbarItem(placement: .primaryAction) {
                    if !draft.isEmpty {
                        Button(L10n.t("AR_CATALOG_RESET_FILTERS")) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                draft = PlantCatalogFilters()
                            }
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(themeManager.brandPrimary)
                    }
                }
            }
            .navigationDestination(for: PlantPreferenceSection.self) { section in
                PlantPreferenceSectionView(
                    section: section,
                    filters: $draft,
                    availableGoals: availableGoals,
                    availableKinds: availableKinds,
                    availableHabits: availableHabits
                )
                .environmentObject(themeManager)
            }
            .safeAreaInset(edge: .bottom) {
                applyButton
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var automaticAdaptationCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(themeManager.brandPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.t("AR_CATALOG_AUTO_ADAPTATION_TITLE"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(themeManager.textColor)

                Text(L10n.f("AR_CATALOG_AUTO_ADAPTATION_FORMAT", automaticCriteriaCount))
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L10n.t("AR_CATALOG_AUTO_ADAPTATION_NOTE"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(themeManager.brandPrimary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(themeManager.brandPrimary.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(themeManager.brandPrimary.opacity(0.20), lineWidth: 1)
        )
    }

    private var automaticCriteriaCount: Int {
        var count = wizard.spaceType.isEmpty ? 0 : 1
        if wizard.location != nil { count += 1 }
        if wizard.siteProfile?.sunlight != nil { count += 1 }
        if wizard.siteProfile?.wind != nil || wizard.conditionalAnswers?.windExposure != nil { count += 1 }
        if wizard.siteProfile?.availableHeight != nil { count += 1 }
        if wizard.conditionalAnswers?.plantingMode != nil || wizard.conditionalAnswers?.maximumContainerSize != nil { count += 1 }
        if wizard.conditionalAnswers?.drainage != nil || wizard.conditionalAnswers?.indoorHumidity != nil { count += 1 }
        if wizard.conditionalAnswers?.wateringCapacity != nil { count += 1 }
        if wizard.conditionalAnswers?.directSunDuration != nil { count += 1 }
        if wizard.safety?.isEmpty == false { count += 1 }
        return max(count, 1)
    }

    private var applyButton: some View {
        Button {
            onApply(draft)
            dismiss()
        } label: {
            Text(applyButtonTitle)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(themeManager.brandPrimary)
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(themeManager.backgroundColor.opacity(0.97))
    }

    private var applyButtonTitle: String {
        let count = resultCount(draft)
        return count == 1
            ? L10n.t("AR_CATALOG_APPLY_FILTERS_SINGLE")
            : L10n.f("AR_CATALOG_APPLY_FILTERS_FORMAT", count)
    }

    private func selectionCount(for section: PlantPreferenceSection) -> Int {
        switch section {
        case .goals: return draft.goals.count
        case .kinds: return draft.kinds.count
        case .appearance: return draft.appearances.count + draft.colors.count
        case .dimensions: return draft.habits.count + (draft.scale == nil ? 0 : 1)
        case .care: return draft.careOptions.count + (draft.careLevel == nil ? 0 : 1)
        }
    }

    private func summary(for section: PlantPreferenceSection) -> String {
        let keys: [String]
        switch section {
        case .goals:
            keys = draft.goals.map(\.titleKey)
        case .kinds:
            keys = draft.kinds.map(\.titleKey)
        case .appearance:
            keys = draft.appearances.map(\.titleKey) + draft.colors.map(\.titleKey)
        case .dimensions:
            keys = (draft.scale.map { [$0.titleKey] } ?? []) + draft.habits.map(\.titleKey)
        case .care:
            keys = (draft.careLevel.map { [$0.titleKey] } ?? []) + draft.careOptions.map(\.titleKey)
        }

        let titles = keys.map { L10n.t($0) }.sorted()
        guard !titles.isEmpty else { return L10n.t("AR_CATALOG_NO_PREFERENCE") }
        guard titles.count > 2 else { return titles.joined(separator: " · ") }
        return L10n.f("AR_CATALOG_FILTER_SUMMARY_MORE_FORMAT", titles.prefix(2).joined(separator: " · "), titles.count - 2)
    }
}

enum PlantPreferenceSection: String, CaseIterable, Identifiable, Hashable {
    case goals
    case kinds
    case appearance
    case dimensions
    case care

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .goals: return "AR_CATALOG_PREF_GOALS_TITLE"
        case .kinds: return "AR_CATALOG_PREF_KINDS_TITLE"
        case .appearance: return "AR_CATALOG_PREF_APPEARANCE_TITLE"
        case .dimensions: return "AR_CATALOG_PREF_DIMENSIONS_TITLE"
        case .care: return "AR_CATALOG_PREF_CARE_TITLE"
        }
    }

    var subtitleKey: String {
        switch self {
        case .goals: return "AR_CATALOG_PREF_GOALS_SUBTITLE"
        case .kinds: return "AR_CATALOG_PREF_KINDS_SUBTITLE"
        case .appearance: return "AR_CATALOG_PREF_APPEARANCE_SUBTITLE"
        case .dimensions: return "AR_CATALOG_PREF_DIMENSIONS_SUBTITLE"
        case .care: return "AR_CATALOG_PREF_CARE_SUBTITLE"
        }
    }

    var icon: String {
        switch self {
        case .goals: return "sparkles"
        case .kinds: return "leaf.fill"
        case .appearance: return "paintpalette.fill"
        case .dimensions: return "arrow.up.left.and.arrow.down.right"
        case .care: return "hand.raised.fill"
        }
    }
}

private struct PlantPreferenceCategoryRow: View {
    let section: PlantPreferenceSection
    let summary: String
    let selectionCount: Int

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: section.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(selectionCount > 0 ? .white : themeManager.brandPrimary)
                .frame(width: 42, height: 42)
                .background(selectionCount > 0 ? themeManager.brandPrimary : themeManager.brandPrimary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t(section.titleKey))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(themeManager.textColor)

                Text(summary)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(selectionCount > 0 ? themeManager.brandPrimary : themeManager.secondaryTextColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if selectionCount > 0 {
                Text("\(selectionCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(themeManager.brandPrimary)
                    .frame(width: 26, height: 26)
                    .background(themeManager.brandPrimary.opacity(0.10))
                    .clipShape(Circle())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(themeManager.secondaryTextColor.opacity(0.65))
        }
        .padding(15)
        .background(themeManager.cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(themeManager.separatorColor.opacity(0.65), lineWidth: 1)
        )
    }
}

private struct PlantPreferenceSectionView: View {
    let section: PlantPreferenceSection
    @Binding var filters: PlantCatalogFilters
    let availableGoals: [PlantCatalogGoal]
    let availableKinds: [PlantCatalogKind]
    let availableHabits: [PlantCatalogHabit]

    @EnvironmentObject private var themeManager: ThemeManager
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            themeManager.backgroundColor.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text(L10n.t(section.subtitleKey))
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(themeManager.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)

                    sectionContent
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(L10n.t(section.titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if sectionSelectionCount > 0 {
                    Button(L10n.t("AR_CATALOG_CLEAR_SECTION")) { clearSection() }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(themeManager.brandPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .goals:
            optionGrid(availableGoals) { value in
                PlantPreferenceOptionCard(
                    title: L10n.t(value.titleKey),
                    subtitle: nil,
                    icon: value.icon,
                    isSelected: filters.goals.contains(value)
                ) { toggle(value, in: &filters.goals) }
            }

        case .kinds:
            optionGrid(availableKinds) { value in
                PlantPreferenceOptionCard(
                    title: L10n.t(value.titleKey),
                    subtitle: nil,
                    icon: value.icon,
                    isSelected: filters.kinds.contains(value)
                ) { toggle(value, in: &filters.kinds) }
            }

        case .appearance:
            preferenceGroup(titleKey: "AR_CATALOG_APPEARANCE_TRAITS_TITLE") {
                optionGrid(PlantCatalogAppearance.allCases) { value in
                    PlantPreferenceOptionCard(
                        title: L10n.t(value.titleKey),
                        subtitle: nil,
                        icon: value.icon,
                        isSelected: filters.appearances.contains(value)
                    ) { toggle(value, in: &filters.appearances) }
                }
            }

            preferenceGroup(titleKey: "AR_CATALOG_COLORS_TITLE") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(PlantCatalogColor.allCases) { color in
                        PlantColorPreferenceCard(
                            color: color,
                            isSelected: filters.colors.contains(color)
                        ) { toggle(color, in: &filters.colors) }
                    }
                }
            }

        case .dimensions:
            preferenceGroup(titleKey: "AR_CATALOG_SCALE_TITLE") {
                VStack(spacing: 10) {
                    ForEach(PlantCatalogScale.allCases) { value in
                        PlantPreferenceChoiceRow(
                            title: L10n.t(value.titleKey),
                            subtitle: L10n.t(value.subtitleKey),
                            icon: value.icon,
                            isSelected: filters.scale == value
                        ) {
                            filters.scale = filters.scale == value ? nil : value
                        }
                    }
                }
            }

            if !availableHabits.isEmpty {
                preferenceGroup(titleKey: "AR_CATALOG_HABIT_TITLE") {
                    optionGrid(availableHabits) { value in
                        PlantPreferenceOptionCard(
                            title: L10n.t(value.titleKey),
                            subtitle: nil,
                            icon: value.icon,
                            isSelected: filters.habits.contains(value)
                        ) { toggle(value, in: &filters.habits) }
                    }
                }
            }

        case .care:
            preferenceGroup(titleKey: "AR_CATALOG_CARE_LEVEL_TITLE") {
                VStack(spacing: 10) {
                    ForEach(PlantCatalogCareLevel.allCases) { value in
                        PlantPreferenceChoiceRow(
                            title: L10n.t(value.titleKey),
                            subtitle: L10n.t(value.subtitleKey),
                            icon: value.icon,
                            isSelected: filters.careLevel == value
                        ) {
                            filters.careLevel = filters.careLevel == value ? nil : value
                        }
                    }
                }
            }

            preferenceGroup(titleKey: "AR_CATALOG_CARE_OPTIONS_TITLE") {
                optionGrid(PlantCatalogCareOption.allCases) { value in
                    PlantPreferenceOptionCard(
                        title: L10n.t(value.titleKey),
                        subtitle: nil,
                        icon: value.icon,
                        isSelected: filters.careOptions.contains(value)
                    ) { toggle(value, in: &filters.careOptions) }
                }
            }
        }
    }

    private var sectionSelectionCount: Int {
        switch section {
        case .goals: return filters.goals.count
        case .kinds: return filters.kinds.count
        case .appearance: return filters.appearances.count + filters.colors.count
        case .dimensions: return filters.habits.count + (filters.scale == nil ? 0 : 1)
        case .care: return filters.careOptions.count + (filters.careLevel == nil ? 0 : 1)
        }
    }

    private func clearSection() {
        withAnimation(.easeInOut(duration: 0.18)) {
            switch section {
            case .goals:
                filters.goals.removeAll()
            case .kinds:
                filters.kinds.removeAll()
            case .appearance:
                filters.appearances.removeAll()
                filters.colors.removeAll()
            case .dimensions:
                filters.scale = nil
                filters.habits.removeAll()
            case .care:
                filters.careLevel = nil
                filters.careOptions.removeAll()
            }
        }
    }

    private func toggle<Value: Hashable>(_ value: Value, in set: inout Set<Value>) {
        withAnimation(.easeInOut(duration: 0.16)) {
            if set.contains(value) {
                set.remove(value)
            } else {
                set.insert(value)
            }
        }
    }

    private func optionGrid<Value: Identifiable, Content: View>(
        _ values: [Value],
        @ViewBuilder content: @escaping (Value) -> Content
    ) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(values, content: content)
        }
    }

    private func preferenceGroup<Content: View>(
        titleKey: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t(titleKey))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(themeManager.textColor)
            content()
        }
    }
}

private struct PlantPreferenceOptionCard: View {
    let title: String
    let subtitle: String?
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? .white : themeManager.brandPrimary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(isSelected ? .white : themeManager.secondaryTextColor.opacity(0.55))
                }

                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(isSelected ? .white : themeManager.textColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(isSelected ? .white.opacity(0.82) : themeManager.secondaryTextColor)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(isSelected ? themeManager.brandPrimary : themeManager.cardBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? themeManager.brandPrimary : themeManager.separatorColor.opacity(0.65),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PlantPreferenceChoiceRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isSelected ? .white : themeManager.brandPrimary)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? themeManager.brandPrimary : themeManager.brandPrimary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(themeManager.textColor)
                    Text(subtitle)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(themeManager.secondaryTextColor)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? themeManager.brandPrimary : themeManager.secondaryTextColor.opacity(0.45))
            }
            .padding(14)
            .background(themeManager.cardBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? themeManager.brandPrimary.opacity(0.55) : themeManager.separatorColor.opacity(0.65), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PlantColorPreferenceCard: View {
    let color: PlantCatalogColor
    let isSelected: Bool
    let action: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color.swatch)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)

                Text(L10n.t(color.titleKey))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(themeManager.textColor)

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? themeManager.brandPrimary : themeManager.secondaryTextColor.opacity(0.4))
            }
            .padding(.horizontal, 13)
            .frame(height: 48)
            .background(themeManager.cardBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(isSelected ? themeManager.brandPrimary.opacity(0.55) : themeManager.separatorColor.opacity(0.65), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

extension PlantCatalogGoal {
    var titleKey: String {
        switch self {
        case .addColor: return "AR_CATALOG_GOAL_COLOR"
        case .createPrivacy: return "AR_CATALOG_GOAL_PRIVACY"
        case .addVolume: return "AR_CATALOG_GOAL_VOLUME"
        case .coverWall: return "AR_CATALOG_GOAL_WALL"
        case .createCascade: return "AR_CATALOG_GOAL_CASCADE"
        case .coverGround: return "AR_CATALOG_GOAL_GROUNDCOVER"
        case .attractPollinators: return "AR_CATALOG_GOAL_POLLINATORS"
        case .edibleAromatic: return "AR_CATALOG_GOAL_EDIBLE"
        case .focalPoint: return "AR_CATALOG_GOAL_FOCAL"
        }
    }

    var icon: String {
        switch self {
        case .addColor: return "paintpalette.fill"
        case .createPrivacy: return "rectangle.split.3x1.fill"
        case .addVolume: return "circle.grid.2x2.fill"
        case .coverWall: return "rectangle.portrait.fill"
        case .createCascade: return "arrow.down.right"
        case .coverGround: return "square.grid.3x3.fill"
        case .attractPollinators: return "ladybug.fill"
        case .edibleAromatic: return "carrot.fill"
        case .focalPoint: return "sparkles"
        }
    }
}

extension PlantCatalogKind {
    var titleKey: String {
        switch self {
        case .greenPlant: return "AR_CATALOG_KIND_GREEN"
        case .floweringPlant: return "AR_CATALOG_KIND_FLOWERING"
        case .cactusSucculent: return "AR_CATALOG_KIND_SUCCULENT"
        case .palm: return "AR_CATALOG_KIND_PALM"
        case .fern: return "AR_CATALOG_KIND_FERN"
        case .orchid: return "AR_CATALOG_KIND_ORCHID"
        case .tree: return "AR_CATALOG_KIND_TREE"
        case .shrub: return "AR_CATALOG_KIND_SHRUB"
        case .perennial: return "AR_CATALOG_KIND_PERENNIAL"
        case .annual: return "AR_CATALOG_KIND_ANNUAL"
        case .grass: return "AR_CATALOG_KIND_GRASS"
        case .groundcover: return "AR_CATALOG_KIND_GROUNDCOVER"
        case .climbing: return "AR_CATALOG_KIND_CLIMBING"
        case .aromaticEdible: return "AR_CATALOG_KIND_EDIBLE"
        }
    }

    var icon: String {
        switch self {
        case .greenPlant: return "leaf.fill"
        case .floweringPlant: return "camera.macro"
        case .cactusSucculent: return "sun.max.fill"
        case .palm: return "tree.fill"
        case .fern: return "leaf.arrow.triangle.circlepath"
        case .orchid: return "camera.macro.circle.fill"
        case .tree: return "tree.fill"
        case .shrub: return "cloud.fill"
        case .perennial: return "calendar.badge.clock"
        case .annual: return "calendar"
        case .grass: return "lines.measurement.horizontal"
        case .groundcover: return "square.grid.3x3.fill"
        case .climbing: return "arrow.up.right"
        case .aromaticEdible: return "carrot.fill"
        }
    }
}

extension PlantCatalogAppearance {
    var titleKey: String {
        switch self {
        case .flowering: return "AR_CATALOG_APPEARANCE_FLOWERING"
        case .variegated: return "AR_CATALOG_APPEARANCE_VARIEGATED"
        case .evergreen: return "AR_CATALOG_APPEARANCE_EVERGREEN"
        case .fragrant: return "AR_CATALOG_APPEARANCE_FRAGRANT"
        case .decorativeFoliage: return "AR_CATALOG_APPEARANCE_FOLIAGE"
        }
    }

    var icon: String {
        switch self {
        case .flowering: return "camera.macro"
        case .variegated: return "circle.lefthalf.filled"
        case .evergreen: return "leaf.fill"
        case .fragrant: return "wind"
        case .decorativeFoliage: return "leaf.circle.fill"
        }
    }
}

extension PlantCatalogColor {
    var titleKey: String { "AR_CATALOG_COLOR_\(rawValue.uppercased())" }

    var swatch: Color {
        switch self {
        case .white: return Color(white: 0.94)
        case .yellow: return Color(red: 0.96, green: 0.78, blue: 0.18)
        case .orange: return Color(red: 0.95, green: 0.46, blue: 0.16)
        case .red: return Color(red: 0.78, green: 0.15, blue: 0.18)
        case .pink: return Color(red: 0.91, green: 0.40, blue: 0.61)
        case .purple: return Color(red: 0.50, green: 0.26, blue: 0.65)
        case .blue: return Color(red: 0.22, green: 0.48, blue: 0.82)
        case .green: return Color(red: 0.23, green: 0.55, blue: 0.31)
        case .dark: return Color(red: 0.12, green: 0.15, blue: 0.13)
        }
    }
}

extension PlantCatalogScale {
    var titleKey: String {
        switch self {
        case .compact: return "AR_CATALOG_SCALE_COMPACT"
        case .balanced: return "AR_CATALOG_SCALE_BALANCED"
        case .statement: return "AR_CATALOG_SCALE_STATEMENT"
        }
    }

    var subtitleKey: String { titleKey + "_SUBTITLE" }

    var icon: String {
        switch self {
        case .compact: return "arrow.down.right.and.arrow.up.left"
        case .balanced: return "arrow.left.and.right"
        case .statement: return "arrow.up.left.and.arrow.down.right"
        }
    }
}

extension PlantCatalogHabit {
    var titleKey: String {
        switch self {
        case .upright: return "AR_CATALOG_HABIT_UPRIGHT"
        case .spreading: return "AR_CATALOG_HABIT_SPREADING"
        case .climbing: return "AR_CATALOG_HABIT_CLIMBING"
        case .trailing: return "AR_CATALOG_HABIT_TRAILING"
        }
    }

    var icon: String {
        switch self {
        case .upright: return "arrow.up"
        case .spreading: return "arrow.left.and.right"
        case .climbing: return "arrow.up.right"
        case .trailing: return "arrow.down.right"
        }
    }
}

extension PlantCatalogCareLevel {
    var titleKey: String {
        switch self {
        case .minimal: return "AR_CATALOG_CARE_MINIMAL"
        case .regular: return "AR_CATALOG_CARE_REGULAR"
        }
    }

    var subtitleKey: String { titleKey + "_SUBTITLE" }

    var icon: String {
        switch self {
        case .minimal: return "hand.thumbsup.fill"
        case .regular: return "calendar.badge.clock"
        }
    }
}

extension PlantCatalogCareOption {
    var titleKey: String {
        switch self {
        case .lowWater: return "AR_CATALOG_CARE_LOW_WATER"
        case .slowGrowth: return "AR_CATALOG_CARE_SLOW_GROWTH"
        case .littlePruning: return "AR_CATALOG_CARE_LITTLE_PRUNING"
        case .longBloom: return "AR_CATALOG_CARE_LONG_BLOOM"
        }
    }

    var icon: String {
        switch self {
        case .lowWater: return "drop.fill"
        case .slowGrowth: return "tortoise.fill"
        case .littlePruning: return "scissors"
        case .longBloom: return "calendar.badge.clock"
        }
    }
}
