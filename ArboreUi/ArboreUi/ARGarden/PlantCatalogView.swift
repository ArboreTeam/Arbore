import SwiftUI

struct PlantCatalogARView: View {
    let placementMode: ARPlacementMode
    let wizard: GardenWizardDTO
    let onSelect: (Plant) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var searchText = ""
    @State private var catalogEntries: [PlantCatalogEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var detailPlant: Plant?
    @State private var suitabilityPlant: Plant?
    @State private var scope: PlantCatalogScope = .adapted
    @State private var filters = PlantCatalogFilters()
    @State private var showFilters = false

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private func resultsTitle(count: Int) -> String {
        let key = count == 1 ? "CATALOG_RESULTS_SINGLE" : "CATALOG_RESULTS_PLURAL"
        return String(format: NSLocalizedString(key, comment: "Catalog result count"), count)
    }

    private var evaluator: PlantSuitabilityEvaluator {
        PlantSuitabilityEvaluator(wizard: wizard)
    }

    private var filteredEntries: [PlantCatalogEntry] {
        var list = catalogEntries

        if !filters.isEmpty {
            list = list.filter { filters.matches($0.traits) }
        }

        if scope == .adapted {
            list = list.filter { $0.suitability.isRecommended }
        }

        if !normalizedSearch.isEmpty {
            list = list.filter { matchesSearch($0) }
        }

        // catalogEntries is sorted once when the index is built. Filtering
        // preserves that order, so sorting again during rendering is wasteful.
        return list
    }

    private var quickFilters: [PlantCatalogQuickPreference] {
        [.flowering, .compact, .easyCare]
    }

    var body: some View {
        NavigationStack {
            catalogPage
                .navigationBarHidden(true)
                .sheet(item: $detailPlant) { plant in
                    PlantDetailView(plantID: plant.id, previewPlant: plant)
                }
                .sheet(item: $suitabilityPlant) { plant in
                    PlantSuitabilityDetailSheet(
                        plant: plant,
                        suitability: evaluator.evaluate(plant),
                        onPlace: { selectAndDismiss(plant) },
                        onViewDetails: { showPlantDetailsAfterSuitabilitySheet(plant) }
                    )
                    .environmentObject(themeManager)
                }
                .sheet(isPresented: $showFilters) {
                    PlantCatalogPreferenceSheet(
                        currentFilters: filters,
                        wizard: wizard,
                        placementMode: placementMode,
                        resultCount: { candidateFilters in
                            catalogEntries.filter { entry in
                                candidateFilters.matches(entry.traits)
                                    && (scope == .all || entry.suitability.isRecommended)
                                    && matchesSearch(entry)
                            }.count
                        },
                        onApply: { filters = $0 }
                    )
                    .environmentObject(themeManager)
                }
                .onAppear {
                    if catalogEntries.isEmpty {
                        fetchPlants()
                    }
                }
        }
    }

    private var catalogPage: some View {
        let displayedEntries = filteredEntries

        return ZStack {
            themeManager.backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                catalogHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 12)

                searchBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                scopePicker
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                quickFilterBar
                    .padding(.bottom, 12)

                HStack {
                    modeBadge
                    Spacer(minLength: 10)
                    Text(resultsTitle(count: displayedEntries.count))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                content(entries: displayedEntries)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var catalogHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("AR_PLANT_CATALOG_TITLE"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(themeManager.textColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.textColor)
                    .frame(width: 42, height: 42)
                    .background(themeManager.cardBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                            .stroke(themeManager.separatorColor.opacity(0.85), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
        }
    }

    private var modeBadge: some View {
        Label(L10n.f("AR_PLANT_CATALOG_MODE_BADGE_FORMAT", placementMode.label), systemImage: placementMode.icon)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(themeManager.brandPrimary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(themeManager.brandPrimary.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                    .stroke(themeManager.brandPrimary.opacity(0.22), lineWidth: 1)
            )
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(themeManager.secondaryTextColor)

            TextField(L10n.t("AR_PLANT_CATALOG_SEARCH_PLACEHOLDER"), text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .foregroundColor(themeManager.textColor)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                .buttonStyle(.plain)
            }

            Rectangle()
                .fill(themeManager.separatorColor.opacity(0.8))
                .frame(width: 1, height: 24)

            Button { showFilters = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(filters.isEmpty ? themeManager.secondaryTextColor : themeManager.brandPrimary)
                        .frame(width: 34, height: 34)

                    if filters.count > 0 {
                        Text("\(filters.count)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(themeManager.brandPrimary)
                            .clipShape(Circle())
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("AR_CATALOG_FILTERS_TITLE"))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(themeManager.cardBackgroundColor)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
    }

    private var scopePicker: some View {
        Picker(L10n.t("AR_CATALOG_SCOPE_ACCESSIBILITY"), selection: $scope) {
            Text(L10n.t("AR_CATALOG_SCOPE_ADAPTED")).tag(PlantCatalogScope.adapted)
            Text(L10n.t("AR_CATALOG_SCOPE_ALL")).tag(PlantCatalogScope.all)
        }
        .pickerStyle(.segmented)
        .tint(themeManager.brandPrimary)
    }

    private var quickFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickFilters) { filter in
                    PlantCatalogQuickChip(
                        preference: filter,
                        isSelected: isQuickPreferenceSelected(filter)
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            toggleQuickPreference(filter)
                        }
                    }
                }

                Button { showFilters = true } label: {
                    HStack(spacing: 6) {
                        Text(L10n.t("AR_CATALOG_FILTER_MORE"))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 13)
                    .frame(height: 36)
                    .background(themeManager.cardBackgroundColor)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(themeManager.separatorColor.opacity(0.8), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
        }
    }

    private func content(entries: [PlantCatalogEntry]) -> some View {
        Group {
            if isLoading {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView().tint(themeManager.brandPrimary)
                    Text(L10n.t("COMMON_LOADING"))
                        .foregroundColor(themeManager.secondaryTextColor)
                    Spacer()
                }
            } else if let errorMessage {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(themeManager.secondaryTextColor)
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(themeManager.secondaryTextColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Button(L10n.t("COMMON_RETRY")) { fetchPlants(forceRefresh: true) }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 42)
                        .background(themeManager.brandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
                    Spacer()
                }
            } else {
                ScrollView(showsIndicators: false) {
                    if entries.isEmpty {
                        VStack(spacing: 14) {
                            Spacer(minLength: 60)
                            Image(systemName: scope == .adapted ? "leaf.circle" : placementMode.icon)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(themeManager.secondaryTextColor)
                            Text(emptyStateTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)

                            if scope == .adapted {
                                Button(L10n.t("AR_CATALOG_SHOW_ALL_PLANTS")) {
                                    withAnimation(.easeInOut(duration: 0.18)) { scope = .all }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(themeManager.brandPrimary)
                            } else if !filters.isEmpty {
                                Button(L10n.t("AR_CATALOG_RESET_FILTERS")) {
                                    withAnimation(.easeInOut(duration: 0.18)) { filters = PlantCatalogFilters() }
                                }
                                .buttonStyle(.bordered)
                                .tint(themeManager.brandPrimary)
                            }
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(entries) { entry in
                                ZStack(alignment: .topLeading) {
                                    Button {
                                        choose(entry)
                                    } label: {
                                        PlantCard(plant: entry.plant)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        suitabilityPlant = entry.plant
                                    } label: {
                                        PlantSuitabilityBadge(level: entry.suitability.level)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(10)
                                }
                                .contextMenu {
                                    Button {
                                        choose(entry)
                                    } label: {
                                        Label(L10n.t("AR_PLANT_CATALOG_PLACE"), systemImage: "plus")
                                    }

                                    Button {
                                        detailPlant = entry.plant
                                    } label: {
                                        Label(L10n.t("AR_PLANT_CATALOG_VIEW_DETAILS"), systemImage: "info.circle")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
    }

    private var emptyStateTitle: String {
        if scope == .adapted {
            return L10n.t("AR_CATALOG_NO_ADAPTED_PLANTS")
        }
        if !filters.isEmpty || !searchText.isEmpty {
            return L10n.t("AR_CATALOG_NO_FILTER_RESULTS")
        }
        return L10n.t("AR_PLANT_CATALOG_NO_COMPATIBLE_PLANTS")
    }

    private var normalizedSearch: String {
        searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func matchesSearch(_ entry: PlantCatalogEntry) -> Bool {
        normalizedSearch.isEmpty || entry.traits.searchableText.contains(normalizedSearch)
    }

    private func isQuickPreferenceSelected(_ preference: PlantCatalogQuickPreference) -> Bool {
        switch preference {
        case .flowering:
            return filters.appearances.contains(.flowering)
        case .compact:
            return filters.scale == .compact
        case .easyCare:
            return filters.careLevel == .minimal
        }
    }

    private func toggleQuickPreference(_ preference: PlantCatalogQuickPreference) {
        switch preference {
        case .flowering:
            if filters.appearances.contains(.flowering) {
                filters.appearances.remove(.flowering)
            } else {
                filters.appearances.insert(.flowering)
            }
        case .compact:
            filters.scale = filters.scale == .compact ? nil : .compact
        case .easyCare:
            filters.careLevel = filters.careLevel == .minimal ? nil : .minimal
        }
    }

    private func choose(_ entry: PlantCatalogEntry) {
        if scope == .all && entry.suitability.level == .unsuitable {
            suitabilityPlant = entry.plant
        } else {
            selectAndDismiss(entry.plant)
        }
    }

    private func selectAndDismiss(_ plant: Plant) {
        suitabilityPlant = nil
        onSelect(plant)
        dismiss()
    }

    private func showPlantDetailsAfterSuitabilitySheet(_ plant: Plant) {
        suitabilityPlant = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            detailPlant = plant
        }
    }

    private func fetchPlants(forceRefresh: Bool = false) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                if !forceRefresh,
                   let cachedPlants = await PlantCatalogMemoryCache.shared.value() {
                    let entries = await PlantCatalogBuilder.entries(
                        from: cachedPlants,
                        wizard: wizard,
                        placementMode: placementMode
                    )
                    await MainActor.run {
                        self.catalogEntries = entries
                        self.isLoading = false
                    }
                    return
                }

                let plants: [Plant] = try await NetworkManager.shared.request(
                    endpoint: "/plants",
                    method: .GET
                )

                let indexedPlants = await PlantCatalogBuilder.index(plants)
                await PlantCatalogMemoryCache.shared.store(indexedPlants)
                let entries = await PlantCatalogBuilder.entries(
                    from: indexedPlants,
                    wizard: wizard,
                    placementMode: placementMode
                )

                await MainActor.run {
                    self.catalogEntries = entries
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = L10n.f("AR_PLANT_CATALOG_ERROR_FORMAT", error.localizedDescription)
                    self.isLoading = false
                }
            }
        }
    }
}

private enum PlantCatalogScope: String, CaseIterable, Identifiable {
    case adapted
    case all

    var id: String { rawValue }
}

private struct PlantCatalogEntry: Identifiable {
    let plant: Plant
    let suitability: PlantSuitability
    let traits: PlantCatalogTraitsSnapshot

    var id: String { plant.id }
}

private struct PlantCatalogIndexedPlant {
    let plant: Plant
    let traits: PlantCatalogTraitsSnapshot
    let supportedModes: Set<ARPlacementMode>
}

/// Short-lived in-memory cache: reopening the AR catalog no longer downloads
/// and re-indexes the same payload. The backend remains the source of truth on
/// the next app launch or after the cache expires.
private actor PlantCatalogMemoryCache {
    static let shared = PlantCatalogMemoryCache()

    private var indexedPlants: [PlantCatalogIndexedPlant]?
    private var storedAt: Date?
    private let lifetime: TimeInterval = 15 * 60

    func value() -> [PlantCatalogIndexedPlant]? {
        guard let indexedPlants, let storedAt,
              Date().timeIntervalSince(storedAt) < lifetime else {
            self.indexedPlants = nil
            self.storedAt = nil
            return nil
        }
        return indexedPlants
    }

    func store(_ plants: [PlantCatalogIndexedPlant]) {
        indexedPlants = plants
        storedAt = Date()
    }
}

private enum PlantCatalogBuilder {
    static func index(_ plants: [Plant]) async -> [PlantCatalogIndexedPlant] {
        await Task.detached(priority: .userInitiated) {
            PlantCatalogTraits.clearSearchableTextCache()
            return plants.map { plant in
                PlantCatalogIndexedPlant(
                    plant: plant,
                    traits: PlantCatalogTraits.snapshot(for: plant),
                    supportedModes: PlantPlacementCompatibility.supportedModes(for: plant)
                )
            }
        }.value
    }

    static func entries(
        from indexedPlants: [PlantCatalogIndexedPlant],
        wizard: GardenWizardDTO,
        placementMode: ARPlacementMode
    ) async -> [PlantCatalogEntry] {
        await Task.detached(priority: .userInitiated) {
            let evaluator = PlantSuitabilityEvaluator(wizard: wizard)
            return indexedPlants
                .filter { $0.supportedModes.contains(placementMode) }
                .map { indexed in
                    PlantCatalogEntry(
                        plant: indexed.plant,
                        suitability: evaluator.evaluate(indexed.plant, traits: indexed.traits),
                        traits: indexed.traits
                    )
                }
                .sorted(by: precedes)
        }.value
    }

    private static func precedes(_ lhs: PlantCatalogEntry, _ rhs: PlantCatalogEntry) -> Bool {
        if lhs.suitability.level != rhs.suitability.level {
            return lhs.suitability.level > rhs.suitability.level
        }
        if lhs.suitability.score != rhs.suitability.score {
            return (lhs.suitability.score ?? -1) > (rhs.suitability.score ?? -1)
        }
        let lhsHasModel = lhs.plant.modelURL?.isEmpty == false
        let rhsHasModel = rhs.plant.modelURL?.isEmpty == false
        if lhsHasModel != rhsHasModel { return lhsHasModel }
        return lhs.plant.name.localizedCaseInsensitiveCompare(rhs.plant.name) == .orderedAscending
    }
}

private struct PlantSuitabilityBadge: View {
    let level: PlantSuitabilityLevel

    @EnvironmentObject private var themeManager: ThemeManager

    private var title: String {
        switch level {
        case .suitable: return L10n.t("AR_CATALOG_SUITABILITY_GOOD")
        case .needsReview: return L10n.t("AR_CATALOG_SUITABILITY_REVIEW")
        case .unsuitable: return L10n.t("AR_CATALOG_SUITABILITY_UNSUITABLE")
        }
    }

    private var icon: String {
        switch level {
        case .suitable: return "checkmark"
        case .needsReview: return "questionmark"
        case .unsuitable: return "exclamationmark"
        }
    }

    private var color: Color {
        switch level {
        case .suitable: return themeManager.brandPrimary
        case .needsReview: return .orange
        case .unsuitable: return .red
        }
    }

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 25)
            .background(color.opacity(0.94))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
    }
}

private struct PlantSuitabilityDetailSheet: View {
    let plant: Plant
    let suitability: PlantSuitability
    let onPlace: () -> Void
    let onViewDetails: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.backgroundColor.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            PlantSuitabilityBadge(level: suitability.level)
                            Text(plant.name)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(themeManager.textColor)
                            Text(L10n.t("AR_CATALOG_SUITABILITY_EXPLANATION"))
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(themeManager.secondaryTextColor)
                        }

                        if !suitability.positiveReasonKeys.isEmpty {
                            reasonSection(
                                titleKey: "AR_CATALOG_MATCHES_TITLE",
                                keys: suitability.positiveReasonKeys,
                                icon: "checkmark.circle.fill",
                                color: themeManager.brandPrimary
                            )
                        }

                        if !suitability.warningReasonKeys.isEmpty {
                            reasonSection(
                                titleKey: "AR_CATALOG_WARNINGS_TITLE",
                                keys: suitability.warningReasonKeys,
                                icon: "exclamationmark.triangle.fill",
                                color: suitability.level == .unsuitable ? .red : .orange
                            )
                        }

                        if !suitability.missingDataKeys.isEmpty {
                            reasonSection(
                                titleKey: "AR_CATALOG_MISSING_DATA_TITLE",
                                keys: suitability.missingDataKeys,
                                icon: "questionmark.circle.fill",
                                color: .orange
                            )
                        } else if suitability.positiveReasonKeys.isEmpty && suitability.warningReasonKeys.isEmpty {
                            Text(L10n.t("AR_CATALOG_REASON_NOT_ENOUGH_DATA"))
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 110)
                }
            }
            .navigationTitle(L10n.t("AR_CATALOG_COMPATIBILITY_TITLE"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("COMMON_CANCEL")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        onPlace()
                    } label: {
                        Text(
                            suitability.level == .unsuitable
                                ? L10n.t("AR_CATALOG_PLACE_ANYWAY")
                                : L10n.t("AR_PLANT_CATALOG_PLACE")
                        )
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(themeManager.brandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(L10n.t("AR_PLANT_CATALOG_VIEW_DETAILS"), action: onViewDetails)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(themeManager.brandPrimary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(themeManager.backgroundColor.opacity(0.97))
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func reasonSection(titleKey: String, keys: [String], icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t(titleKey))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(themeManager.textColor)

            ForEach(keys, id: \.self) { key in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon)
                        .foregroundColor(color)
                    Text(L10n.t(key))
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(themeManager.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(themeManager.cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let gardenARSave = Notification.Name("gardenARSave")
    static let gardenARLoad = Notification.Name("gardenARLoad")
}

// MARK: - Matrix <-> [Float]


// MARK: - Files

func documentsURL(_ fileName: String) -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(fileName)
}

let worldMapFileURL = documentsURL("garden_worldmap.arexperience")
let sceneFileURL    = documentsURL("garden_scene.json")

// MARK: - Bundle model lookup (same logic as Plant.localModelURL)

func resourceURLFromModelURLString(_ modelURL: String) -> URL? {
    let file = modelURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !file.isEmpty else { return nil }

    let ext  = (file as NSString).pathExtension
    let name = (file as NSString).deletingPathExtension
    let finalExt = ext.isEmpty ? "usdz" : ext

    let url = Bundle.main.url(forResource: name, withExtension: finalExt)
    if url == nil {
        print("❌ USDZ introuvable dans le bundle: \(name).\(finalExt)")
    }
    return url
}
