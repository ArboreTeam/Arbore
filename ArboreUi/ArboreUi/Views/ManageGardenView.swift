//
//  ManageGardenView.swift
//  ArboreUi
//
//  Created on November 25, 2025.
//

import SwiftUI
import Foundation
import UIKit

// MARK: - 1. MODELS (Fusionnés)

// Modèle pour l'affichage de la liste des fichiers
// Modèle pour la Map 2D (Wrapper avec ID unique)
struct DisplayPlant: Identifiable {
    let id = UUID()
    let data: PersistedPlant
}

enum GardenShopCategory: String, Codable, CaseIterable {
    case plant
    case soil
    case watering
    case care
    case accessory

    var title: String {
        switch self {
        case .plant: return L10n.t("SHOP_CATEGORY_PLANTS")
        case .soil: return L10n.t("SHOP_CATEGORY_SOIL")
        case .watering: return L10n.t("SHOP_CATEGORY_WATERING")
        case .care: return L10n.t("SHOP_CATEGORY_CARE")
        case .accessory: return L10n.t("SHOP_CATEGORY_ACCESSORIES")
        }
    }

    var icon: String {
        switch self {
        case .plant: return "leaf.fill"
        case .soil: return "shippingbox.fill"
        case .watering: return "drop.fill"
        case .care: return "scissors"
        case .accessory: return "tray.full.fill"
        }
    }

    var tint: Color {
        switch self {
        case .plant: return ArboreDesign.Colors.primaryGreen
        case .soil: return Color(hex: "#8F6A3D")
        case .watering: return Color(hex: "#3A93B8")
        case .care: return Color(hex: "#D8A85B")
        case .accessory: return Color(hex: "#607466")
        }
    }
}

struct GardenShopItem: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let priceRange: String
    let estimatedPrice: Double
    let category: GardenShopCategory
    let systemIcon: String
    let sourcePlantId: String?
    let sourcePlantName: String?
    let recommendation: String?
    let priority: Int

    init(
        id: String,
        name: String,
        subtitle: String,
        priceRange: String,
        estimatedPrice: Double,
        category: GardenShopCategory,
        systemIcon: String? = nil,
        sourcePlantId: String? = nil,
        sourcePlantName: String? = nil,
        recommendation: String? = nil,
        priority: Int = 1
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.priceRange = priceRange
        self.estimatedPrice = estimatedPrice
        self.category = category
        self.systemIcon = systemIcon ?? category.icon
        self.sourcePlantId = sourcePlantId
        self.sourcePlantName = sourcePlantName
        self.recommendation = recommendation
        self.priority = priority
    }
}

struct GardenCartEntry: Identifiable, Codable, Equatable {
    var id: String { item.id }
    var item: GardenShopItem
    var quantity: Int

    var total: Double {
        item.estimatedPrice * Double(quantity)
    }
}

struct GardenPlantPurchaseGroup: Identifiable {
    let plant: PersistedPlant
    let count: Int

    var id: String {
        "\(plant.plantID)-\(plant.plantName)"
    }
}

// MARK: - 2. SERVICE DE DONNÉES (Scan des fichiers)
class GardenLocalStorageService: ObservableObject {
    @Published var projects: [GardenModel] = []

    func refreshProjects() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: [.contentModificationDateKey])
            let gardenFiles = fileURLs.filter { url in
                url.lastPathComponent.hasPrefix("scene_") && url.pathExtension == "json"
            }
            
            let loadedProjects = gardenFiles.compactMap { url -> GardenModel? in
                let filename = url.deletingPathExtension().lastPathComponent
                let id = filename.replacingOccurrences(of: "scene_", with: "")
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                let modificationDate = attributes?[.modificationDate] as? Date ?? Date()
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                let name = "Jardin du \(formatter.string(from: modificationDate))"
                
                return GardenModel(id: id, name: name, lastModified: modificationDate, thumbnail: "leaf.fill")
            }
            
            DispatchQueue.main.async {
                self.projects = loadedProjects.sorted(by: { $0.lastModified > $1.lastModified })
            }
        } catch {
            print("❌ Erreur scan dossier : \(error)")
        }
    }
}

// MARK: - 3. VUE PRINCIPALE (Liste des Jardins)
struct ManageGardenView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var projectService = GardenLocalStorageService()
    @State private var showingNewProjectSheet = false
    @State private var showingGardenList = false
    @State private var isResolvingInitialGarden = true
    @State private var selectedProject: GardenModel?

    var body: some View {
        NavigationStack {
            AppBackground {
                if showingGardenList {
                    allGardensPickerContent
                } else if let selectedProject {
                    GardenDetailsPage(
                        gardenId: selectedProject.id,
                        gardenName: selectedProject.name,
                        showsBackButton: false,
                        onOpenGardenList: {
                            showingGardenList = true
                        },
                        onGardenRenamed: { newName in
                            updateSelectedGardenName(newName)
                        }
                    )
                    .id(selectedProject.id)
                } else if isResolvingInitialGarden {
                    loadingGardenContent
                } else {
                    emptyGardenContent
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingNewProjectSheet) {
                Text(L10n.t("GARDEN_NEW_PROJECT_WIZARD"))
            }
            .onAppear {
                isResolvingInitialGarden = selectedProject == nil
                projectService.refreshProjects()
                Task {
                    await resolveInitialGarden()
                }
            }
            .onChange(of: projectService.projects.map(\.id)) { _, _ in
                syncSelectedProject()
            }
        }
        .preferredColorScheme(themeManager.colorScheme)
    }

    private var allGardensPickerContent: some View {
        AllGardensView(
            currentGardenId: selectedProject?.id,
            onSelectGarden: { garden in
                selectGarden(garden)
            },
            onDismiss: {
                if selectedProject != nil {
                    showingGardenList = false
                }
            },
            onGardenDeleted: { deletedId in
                handleGardenDeleted(deletedId)
            }
        )
    }
    
    private var loadingGardenContent: some View {
        LoadingView(title: L10n.t("GARDEN_LOADING_PROGRESS"))
    }

    private var emptyGardenContent: some View {
        VStack(spacing: ArboreDesign.Spacing.lg) {
            EmptyStateView(
                systemImage: "leaf",
                title: L10n.t("GARDEN_EMPTY_SELECTION_TITLE"),
                message: L10n.t("GARDEN_EMPTY_SELECTION_MESSAGE"),
                buttonTitle: L10n.t("GARDEN_VIEW_MY_GARDENS"),
                action: { showingGardenList = true }
            )
        }
        .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
    }
    
    private func selectGarden(_ garden: GardenDTO) {
        guard let gardenId = garden.id else { return }

        selectedProject = GardenModel(
            id: gardenId,
            name: garden.name,
            lastModified: garden.updatedAt ?? garden.createdAt ?? Date(),
            thumbnail: "leaf.fill"
        )
        showingGardenList = false
    }

    private func handleGardenDeleted(_ deletedId: String) {
        if selectedProject?.id == deletedId {
            selectedProject = nil
        }

        projectService.refreshProjects()
    }

    private func updateSelectedGardenName(_ newName: String) {
        guard let selectedProject else { return }

        self.selectedProject = GardenModel(
            id: selectedProject.id,
            name: newName,
            lastModified: Date(),
            thumbnail: selectedProject.thumbnail
        )
    }

    private func resolveInitialGarden() async {
        await MainActor.run {
            syncSelectedProject()
        }

        let hasLocalSelection = await MainActor.run {
            selectedProject != nil
        }

        guard !hasLocalSelection else {
            await MainActor.run {
                isResolvingInitialGarden = false
            }
            return
        }

        do {
            let gardens = try await GardenAPI.shared.listGardens()
            let latestGarden = gardens.sorted {
                ($0.updatedAt ?? $0.createdAt ?? .distantPast) > ($1.updatedAt ?? $1.createdAt ?? .distantPast)
            }.first

            await MainActor.run {
                if let latestGarden, selectedProject == nil {
                    selectGarden(latestGarden)
                }
                isResolvingInitialGarden = false
            }
        } catch {
            await MainActor.run {
                isResolvingInitialGarden = false
            }
            print("❌ resolveInitialGarden failed:", error)
        }
    }
    
    private func syncSelectedProject() {
        guard !projectService.projects.isEmpty else {
            selectedProject = nil
            return
        }
        
        if let selectedProject,
           projectService.projects.contains(where: { $0.id == selectedProject.id }) {
            return
        }
        
        selectedProject = projectService.projects.first
        showingGardenList = false
    }
}

// MARK: - 5. VUE DÉTAIL FUSIONNÉE (Tabs + Map + Purchase)
struct GardenDetailsPage: View {
    let gardenId: String
    let gardenName: String
    let showsBackButton: Bool
    let onOpenGardenList: (() -> Void)?
    let onGardenRenamed: ((String) -> Void)?
    
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    
    // ViewModel pour la Map
    @StateObject private var mapViewModel = Garden2DViewModel()
    @StateObject private var wateringStore = WateringRoutineStore.shared
    @State private var mapTextureKind: MapTextureKind = .garden
    @State private var gardenDetails: GardenDTO?
    @State private var showMeasurementApp = false
    @State private var currentGardenName: String
    @State private var renameText = ""
    @State private var showRenameAlert = false
    @State private var isRenamingGarden = false
    @State private var renameError: String?
    @State private var showARShareCapture = false
    @State private var showRoutineCreation = false
    @State private var plantForRoutine: PersistedPlant?
    @State private var visibleCareMonth = Date()
    @State private var selectedCareDate = Date()
    @State private var cartItems: [GardenCartEntry] = []
    @State private var cataloguePlants: [Plant] = []
    @State private var purchaseSearchText = ""
    @State private var isLoadingPurchaseCatalog = false
    @State private var purchaseCatalogError: String?
    @State private var hasLoadedPurchaseCatalog = false
    @State private var showCheckoutSummary = false

    // Caches des données d'achat (issue perf) : ces listes sont coûteuses à
    // calculer (tri du catalogue avec matching wizard). On les recalcule
    // UNIQUEMENT quand leurs entrées changent (catalogue, plantes du jardin,
    // recherche, wizard) via recomputePurchaseData(), au lieu de le refaire à
    // chaque render du body — sinon valider le panier (un simple changement
    // d'état) re-trie tout le catalogue plusieurs fois et fait lager l'app.
    @State private var cachedPurchaseGroups: [GardenPlantPurchaseGroup] = []
    @State private var cachedCatalogueItems: [GardenShopItem] = []
    @State private var cachedRecommendations: [GardenShopItem] = []

    // États pour l'interface "Purchase"
    enum Tab: String, CaseIterable {
        case plan2D = "Plan"
        case tasks = "Soins"
        case purchase = "Achats"

        var title: String {
            switch self {
            case .plan2D: return L10n.t("GARDEN_TAB_PLAN")
            case .tasks: return L10n.t("GARDEN_TAB_CARE")
            case .purchase: return L10n.t("GARDEN_TAB_SHOP")
            }
        }
    }
    
    @State private var selectedTab: Tab = .plan2D
    @State private var sortByPriority = true
    
    private var primary: Color { ArboreDesign.Colors.primaryGreen }
    
    init(
        gardenId: String,
        gardenName: String,
        showsBackButton: Bool = true,
        onOpenGardenList: (() -> Void)? = nil,
        onGardenRenamed: ((String) -> Void)? = nil
    ) {
        self.gardenId = gardenId
        self.gardenName = gardenName
        self.showsBackButton = showsBackButton
        self.onOpenGardenList = onOpenGardenList
        self.onGardenRenamed = onGardenRenamed
        _currentGardenName = State(initialValue: gardenName)
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ArboreDesign.Colors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                gardenDetailHeader
                gardenTabs
                
                // Contenu
                ScrollView {
                    VStack(alignment: .leading, spacing: ArboreDesign.Spacing.lg) {
                        
                        switch selectedTab {
                        case .plan2D:
                            planContent
                            
                        case .purchase:
                            purchaseContent
                            
                        case .tasks:
                            careContent
                        }
                    }
                    .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
                    .padding(.top, ArboreDesign.Spacing.lg)
                    .padding(.bottom, 108)
                }
                .scrollIndicators(.hidden)
            }
            
            // FAB (Floating Action Button)
            Button {
                handleFloatingAction()
            } label: {
                Image(systemName: floatingActionIcon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 56, height: 56)
                    .background(ArboreDesign.Colors.primaryButton)
                    .clipShape(Circle())
                    .shadow(color: ArboreDesign.Colors.primaryGreen.opacity(0.28), radius: 12, x: 0, y: 7)
            }
            .padding(.trailing, ArboreDesign.Spacing.screenHorizontal)
            .padding(.bottom, ArboreDesign.Spacing.md)
        }
        .navigationBarHidden(true)
        .alert(L10n.t("GARDEN_RENAME_TITLE"), isPresented: $showRenameAlert) {
            TextField(L10n.t("GARDEN_RENAME_PLACEHOLDER"), text: $renameText)

            Button(L10n.t("COMMON_CANCEL"), role: .cancel) {}
            Button(L10n.t("COMMON_SAVE")) {
                Task { await renameGarden() }
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text(L10n.t("GARDEN_RENAME_HELP"))
        }
        .alert(L10n.t("SHOP_CHECKOUT_READY_TITLE"), isPresented: $showCheckoutSummary) {
            Button(L10n.t("COMMON_OK"), role: .cancel) {}
        } message: {
            Text(checkoutSummaryText)
        }
        .fullScreenCover(isPresented: $showMeasurementApp) {
            ARViewContainerMesure(
                uid: gardenDetails?.uid ?? "",
                wizard: gardenDetails?.wizard ?? fallbackWizardDTO,
                gardenName: currentGardenName,
                thumbnailKey: gardenDetails?.thumbnailKey,
                existingGardenId: gardenId,
                measurementOnly: true,
                onSuccess: {
                    showMeasurementApp = false
                    mapViewModel.loadGarden(gardenId: gardenId)
                }
            )
        }
        .fullScreenCover(isPresented: $showARShareCapture) {
            GardenARPlacementView(
                selectedPlants: [],
                uid: gardenDetails?.uid ?? "",
                wizard: gardenDetails?.wizard ?? fallbackWizardDTO,
                gardenName: currentGardenName,
                thumbnailKey: gardenDetails?.thumbnailKey,
                existingGardenId: gardenId,
                mode: .reopen,
                boundaryPoints: [],
                area: 0,
                perimeter: 0,
                measurementWorldMapId: nil,
                onValidated: {
                    showARShareCapture = false
                    mapViewModel.loadGarden(gardenId: gardenId)
                }
            )
        }
        .sheet(isPresented: $showRoutineCreation) {
            if let plantForRoutine = plantForRoutine ?? placedPlants.first {
                CreateWateringRoutineView(
                    plantName: plantForRoutine.plantName,
                    waterInfo: nil,
                    gardenId: gardenId,
                    plantId: plantForRoutine.plantID,
                    availablePlants: placedPlants,
                    initialPlantId: plantForRoutine.plantID,
                    allowedActions: GardenRoutinePlanningKind.allPlanningCases
                )
                .environmentObject(themeManager)
            }
        }
        .onAppear {
            mapViewModel.loadGarden(gardenId: gardenId)
            wateringStore.reload()
            loadPurchaseCart()
            loadPurchaseCatalogIfNeeded()
            currentGardenName = gardenDetails?.name ?? gardenName
            Task { await loadMapTextureKind() }
        }
        // Recompute ciblé : recherche catalogue et plantes du jardin changent →
        // on régénère les listes d'achat en cache (au lieu d'à chaque render).
        .onChange(of: purchaseSearchText) { _, _ in
            recomputePurchaseData()
        }
        .onChange(of: mapViewModel.displayPlants.map(\.id)) { _, _ in
            recomputePurchaseData()
        }
    }
    
    // MARK: - Subviews UI

    private var gardenDetailHeader: some View {
        HStack(spacing: ArboreDesign.Spacing.md) {
            if showsBackButton {
                Button { dismiss() } label: {
                    headerIcon("arrow.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("COMMON_BACK"))
            } else if let onOpenGardenList {
                Button(action: onOpenGardenList) {
                    headerIcon("line.3.horizontal")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("GARDEN_VIEW_MY_GARDENS"))
            } else {
                Color.clear
                    .frame(width: 42, height: 42)
            }

            Text(L10n.displayGardenName(currentGardenName))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(ArboreDesign.Colors.textPrimary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)

            Menu {
                Button(action: { showARShareCapture = true }) {
                    Label(L10n.t("GARDEN_SHARE_3D"), systemImage: "camera.viewfinder")
                }

                Button(action: openRenameAlert) {
                    Label(L10n.t("GARDEN_RENAME"), systemImage: "pencil")
                }
            } label: {
                if isRenamingGarden {
                    ProgressView()
                        .tint(ArboreDesign.Colors.primaryGreen)
                        .frame(width: 42, height: 42)
                        .background(ArboreDesign.Colors.card)
                        .clipShape(Circle())
                } else {
                    headerIcon("ellipsis")
                }
            }
            .buttonStyle(.plain)
            .disabled(isRenamingGarden)
            .accessibilityLabel(L10n.t("GARDEN_ACTIONS_ACCESSIBILITY"))
        }
        .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
        .padding(.top, ArboreDesign.Spacing.md)
        .padding(.bottom, ArboreDesign.Spacing.sm)
        .background(ArboreDesign.Colors.background)
    }

    private var planContent: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.lg) {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
                SectionTitle(title: L10n.t("GARDEN_PLAN_SECTION_TITLE"))

                Text(L10n.f("GARDEN_PLAN_DESCRIPTION_FORMAT", L10n.displayGardenName(currentGardenName)))
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let renameError {
                    Text(renameError)
                        .font(ArboreDesign.Typography.caption)
                        .foregroundColor(ArboreDesign.Colors.danger)
                }
            }

            ZStack(alignment: .bottom) {
                Group {
                    if hasMeasuredSpace {
                        GardenPlanInteractiveMap(viewModel: mapViewModel, textureKind: mapTextureKind)
                    } else {
                        GardenMeasurementPromptCard {
                            showMeasurementApp = true
                        }
                    }
                }
                .frame(height: 468)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 10)

                if hasMeasuredSpace, mapViewModel.selectedPlant != nil {
                    PlantMinimapDetailPanel(viewModel: mapViewModel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, ArboreDesign.Spacing.sm)
                        .padding(.bottom, ArboreDesign.Spacing.sm)
                }
            }

            GardenStatsGrid(
                area: mapViewModel.area,
                perimeter: mapViewModel.perimeter,
                plantCount: mapViewModel.displayPlants.count,
                taskCount: pendingTaskCount
            )

            if !hasMeasuredSpace {
                GardenInlineMessage(
                    systemImage: "ruler",
                    text: L10n.t("GARDEN_PLAN_MEASURE_FIRST")
                )
            } else if mapViewModel.displayPlants.isEmpty {
                GardenInlineMessage(
                    systemImage: "leaf",
                    text: L10n.t("GARDEN_PLAN_NO_PLANTS")
                )
            } else if mapViewModel.selectedPlant == nil {
                GardenInlineMessage(
                    systemImage: "hand.tap",
                    text: L10n.f("GARDEN_PLAN_MARKER_HINT_FORMAT", mapViewModel.displayPlants.count)
                )
            }
        }
    }

    private var pendingTaskCount: Int {
        dueCareItems.count
    }

    private var hasMeasuredSpace: Bool {
        mapViewModel.boundaryPoints.count > 2
    }

    private var careContent: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xl) {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
                HStack {
                    SectionTitle(title: L10n.t("CARE_TODAY_SECTION"))

                    Spacer()

                    if !placedPlants.isEmpty {
                        Button(action: { openRoutineCreation() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .bold))
                                Text(L10n.t("CARE_PLAN"))
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(ArboreDesign.Colors.primaryGreen)
                            .padding(.horizontal, ArboreDesign.Spacing.sm)
                            .frame(height: 30)
                            .background(ArboreDesign.Colors.softSurface)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(L10n.t("CARE_ROUTINES_DESCRIPTION"))
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
            }

            if placedPlants.isEmpty {
                GardenInlineMessage(
                    systemImage: "leaf",
                    text: L10n.t("CARE_ADD_PLANTS_FIRST")
                )
            } else {
                if careItems.isEmpty {
                    CareEmptyRoutineCard(
                        plantName: placedPlants.first?.plantName ?? L10n.t("CARE_FIRST_PLANT_FALLBACK"),
                        onCreate: { openRoutineCreation() }
                    )
                } else if dueCareItems.isEmpty {
                    GardenInlineMessage(
                        systemImage: "checkmark.circle",
                        text: L10n.t("CARE_NO_ACTION_TODAY")
                    )
                } else {
                    VStack(spacing: ArboreDesign.Spacing.md) {
                        ForEach(Array(dueCareItems.prefix(5))) { item in
                            CareTaskCard(
                                systemImage: item.icon,
                                title: item.title,
                                subtitle: item.subtitle,
                                detail: statusText(for: item.date).text,
                                tint: statusText(for: item.date).color,
                                completionTitle: item.completionTitle,
                                onComplete: {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        completeCareItem(item)
                                    }
                                },
                                onSkip: {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        deferCareItem(item)
                                    }
                                }
                            )
                        }
                    }
                }

                CareMonthCalendar(
                    items: careItems,
                    selectedDate: $selectedCareDate,
                    visibleMonth: $visibleCareMonth
                )

                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                    SectionTitle(title: selectedDateSectionTitle)

                    AppCard {
                        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
                            if selectedDateCareItems.isEmpty {
                                CareHistoryRow(text: L10n.t("CARE_NO_ACTION_ON_SELECTED_DAY"))
                            } else {
                                ForEach(selectedDateCareItems) { item in
                                    CareCalendarAgendaRow(
                                        item: item,
                                        status: statusText(for: item.date),
                                        onComplete: {
                                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                                completeCareItem(item)
                                            }
                                        },
                                        onSkip: {
                                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                                deferCareItem(item)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                }

                if !upcomingCareItems.isEmpty {
                    VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                        SectionTitle(title: L10n.t("CARE_UPCOMING_SECTION"))

                        VStack(spacing: ArboreDesign.Spacing.sm) {
                            ForEach(Array(upcomingCareItems.prefix(5))) { item in
                                CareUpcomingRow(
                                    systemImage: item.icon,
                                    plantName: item.plantName,
                                    title: item.title,
                                    subtitle: item.subtitle,
                                    status: statusText(for: item.date).text,
                                    tint: statusText(for: item.date).color
                                )
                            }
                        }
                    }
                }

                if !plantsWithoutRoutine.isEmpty {
                    VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                        SectionTitle(title: L10n.t("CARE_ROUTINES_TO_CREATE_SECTION"))

                        AppCard {
                            VStack(spacing: ArboreDesign.Spacing.sm) {
                                ForEach(Array(plantsWithoutRoutine.prefix(4)), id: \.plantID) { plant in
                                    CareRoutineSetupRow(
                                        plantName: plant.plantName,
                                        onCreate: { openRoutineCreation(for: plant) }
                                    )
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                    SectionTitle(title: L10n.t("CARE_PLANT_STATUS_SECTION"))

                    VStack(spacing: ArboreDesign.Spacing.sm) {
                        ForEach(Array(placedPlants.prefix(6)), id: \.plantID) { plant in
                            let status = plantCareStatus(for: plant)
                            CarePlantStatusRow(
                                name: plant.plantName,
                                status: status.text,
                                tint: status.color
                            )
                        }
                    }
                }

                CareRecommendationCard(
                    message: recommendationMessage
                )

                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                    SectionTitle(title: L10n.t("CARE_LAST_ACTIONS_SECTION"))

                    AppCard {
                        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
                            if careActions.isEmpty {
                                CareHistoryRow(text: L10n.t("CARE_NO_ACTION_HISTORY"))
                            } else {
                                ForEach(Array(careActions.prefix(5))) { action in
                                    CareHistoryRow(text: historyText(for: action))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var placedPlants: [PersistedPlant] {
        mapViewModel.displayPlants.map { $0.data }
    }

    private var careItems: [GardenCareScheduleItem] {
        let wateringItems = gardenWateringRoutines.map { routine in
            GardenCareScheduleItem(
                source: .watering(routine.id),
                plantId: routine.plantId,
                plantName: routine.plantName,
                title: L10n.t("ROUTINE_ACTION_WATERING"),
                subtitle: wateringSubtitle(for: routine),
                date: routine.nextWateringDate,
                icon: "drop.fill",
                tint: Color(hex: "#3A93B8"),
                completionTitle: L10n.t("CARE_WATERED_DONE")
            )
        }

        let careRoutineItems = gardenPlantCareRoutines.map { routine in
            GardenCareScheduleItem(
                source: .care(routine.id),
                plantId: routine.plantId,
                plantName: routine.plantName,
                title: routine.title,
                subtitle: careRoutineSubtitle(for: routine),
                date: routine.nextCareDate,
                icon: routine.kind.icon,
                tint: Color(hex: routine.kind.tintHex),
                completionTitle: routine.kind.completionLabel
            )
        }

        return (wateringItems + careRoutineItems).sorted { $0.date < $1.date }
    }

    private var dueCareItems: [GardenCareScheduleItem] {
        careItems.filter { daysUntil($0.date) <= 0 }
    }

    private var upcomingCareItems: [GardenCareScheduleItem] {
        careItems.filter { daysUntil($0.date) > 0 }
    }

    private var selectedDateCareItems: [GardenCareScheduleItem] {
        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: selectedCareDate)
        let today = calendar.startOfDay(for: Date())

        return careItems.filter { item in
            let itemDay = calendar.startOfDay(for: item.date)
            if selectedDay == today {
                return itemDay <= today
            }
            return itemDay == selectedDay
        }
    }

    private var gardenWateringRoutines: [WateringRoutine] {
        let plantIds = Set(placedPlants.map { $0.plantID })
        let plantNames = Set(placedPlants.map { normalizedPlantName($0.plantName) })
        let gardenRoutineNames = Set(wateringStore.routines.compactMap { routine -> String? in
            routine.gardenId == gardenId ? normalizedPlantName(routine.plantName) : nil
        })

        return wateringStore.routines
            .filter { routine in
                guard routine.isActive else { return false }

                if routine.gardenId == gardenId {
                    if let plantId = routine.plantId {
                        return plantIds.contains(plantId)
                    }
                    return plantNames.contains(normalizedPlantName(routine.plantName))
                }

                if let routineGardenId = routine.gardenId, routineGardenId != gardenId {
                    return false
                }

                if let plantId = routine.plantId, plantIds.contains(plantId) {
                    return !gardenRoutineNames.contains(normalizedPlantName(routine.plantName))
                }

                let routineName = normalizedPlantName(routine.plantName)
                return plantNames.contains(routineName) && !gardenRoutineNames.contains(routineName)
            }
            .sorted { $0.nextWateringDate < $1.nextWateringDate }
    }

    private var gardenPlantCareRoutines: [PlantCareRoutine] {
        let plantIds = Set(placedPlants.map { $0.plantID })
        let plantNames = Set(placedPlants.map { normalizedPlantName($0.plantName) })
        let gardenRoutineNames = Set(wateringStore.careRoutines.compactMap { routine -> String? in
            routine.gardenId == gardenId ? normalizedPlantName(routine.plantName) : nil
        })

        return wateringStore.careRoutines
            .filter { routine in
                guard routine.isActive else { return false }

                if routine.gardenId == gardenId {
                    if let plantId = routine.plantId {
                        return plantIds.contains(plantId)
                    }
                    return plantNames.contains(normalizedPlantName(routine.plantName))
                }

                if let routineGardenId = routine.gardenId, routineGardenId != gardenId {
                    return false
                }

                if let plantId = routine.plantId, plantIds.contains(plantId) {
                    return !gardenRoutineNames.contains(normalizedPlantName(routine.plantName))
                }

                let routineName = normalizedPlantName(routine.plantName)
                return plantNames.contains(routineName) && !gardenRoutineNames.contains(routineName)
            }
            .sorted { $0.nextCareDate < $1.nextCareDate }
    }

    private var plantsWithoutRoutine: [PersistedPlant] {
        let routinePlantIds = Set(gardenWateringRoutines.compactMap { $0.plantId } + gardenPlantCareRoutines.compactMap { $0.plantId })
        let routineNames = Set(
            gardenWateringRoutines.map { normalizedPlantName($0.plantName) }
            + gardenPlantCareRoutines.map { normalizedPlantName($0.plantName) }
        )
        return placedPlants.filter { plant in
            !routinePlantIds.contains(plant.plantID)
            && !routineNames.contains(normalizedPlantName(plant.plantName))
        }
    }

    private var careActions: [GardenCareAction] {
        let plantIds = Set(placedPlants.map { $0.plantID })
        let plantNames = Set(placedPlants.map { normalizedPlantName($0.plantName) })

        return wateringStore.actions
            .filter { action in
                if action.gardenId == gardenId { return true }
                if let actionGardenId = action.gardenId, actionGardenId != gardenId { return false }
                if let plantId = action.plantId, plantIds.contains(plantId) { return true }
                return plantNames.contains(normalizedPlantName(action.plantName))
            }
            .sorted { $0.date > $1.date }
    }

    private var recommendationMessage: String {
        if let item = dueCareItems.first {
            return L10n.f("CARE_RECOMMENDATION_DUE_FORMAT", item.plantName, item.title)
        }

        if let item = upcomingCareItems.first {
            return L10n.f("CARE_RECOMMENDATION_UPCOMING_FORMAT", item.plantName, item.title, statusText(for: item.date).text.lowercased())
        }

        return L10n.t("CARE_RECOMMENDATION_EMPTY")
    }

    private var selectedDateSectionTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "d MMMM"
        return L10n.f("CARE_AGENDA_DATE_FORMAT", formatter.string(from: selectedCareDate))
    }

    private var floatingActionIcon: String {
        selectedTab == .tasks ? "calendar.badge.plus" : "plus"
    }

    private func handleFloatingAction() {
        if selectedTab == .tasks {
            openRoutineCreation()
        }
    }

    private func openRoutineCreation(for plant: PersistedPlant? = nil) {
        guard let plant = plant ?? placedPlants.first else { return }
        plantForRoutine = plant
        showRoutineCreation = true
    }

    private func careItem(for plant: PersistedPlant) -> GardenCareScheduleItem? {
        careItems.first { item in
            if let plantId = item.plantId {
                return plantId == plant.plantID
            }
            return normalizedPlantName(item.plantName) == normalizedPlantName(plant.plantName)
        }
    }

    private func plantCareStatus(for plant: PersistedPlant) -> (text: String, color: Color) {
        guard let item = careItem(for: plant) else {
            return (L10n.t("CARE_STATUS_TO_PLAN"), ArboreDesign.Colors.textSecondary)
        }
        return statusText(for: item.date)
    }

    private func completeCareItem(_ item: GardenCareScheduleItem) {
        switch item.source {
        case .watering(let routineId):
            wateringStore.markWatered(routineId: routineId)
        case .care(let routineId):
            wateringStore.completeCareRoutine(routineId: routineId)
        }
    }

    private func deferCareItem(_ item: GardenCareScheduleItem) {
        switch item.source {
        case .watering(let routineId):
            wateringStore.deferWatering(routineId: routineId)
        case .care(let routineId):
            wateringStore.deferCareRoutine(routineId: routineId)
        }
    }

    private func statusText(for date: Date) -> (text: String, color: Color) {
        let days = daysUntil(date)

        if days < 0 {
            return (L10n.t("CARE_STATUS_OVERDUE"), ArboreDesign.Colors.danger)
        }
        if days == 0 {
            return (L10n.t("CARE_STATUS_TODAY"), Color(hex: "#3A93B8"))
        }
        if days == 1 {
            return (L10n.t("CARE_STATUS_TOMORROW"), Color(hex: "#3A93B8"))
        }
        return (L10n.f("CARE_STATUS_IN_DAYS_FORMAT", days), ArboreDesign.Colors.success)
    }

    private func wateringSubtitle(for routine: WateringRoutine) -> String {
        let amount = routine.amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let time = formattedTime(routine.reminderTime)

        if amount.isEmpty {
            return "\(routine.frequencySummary) • \(time)"
        }
        return "\(amount) • \(routine.frequencySummary) • \(time)"
    }

    private func careRoutineSubtitle(for routine: PlantCareRoutine) -> String {
        let detail = (routine.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = routine.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = "\(routine.plantName) • \(routine.frequencySummary) • \(formattedTime(routine.reminderTime))"
        let withDetail = detail.isEmpty ? base : "\(base) • \(detail)"
        return notes.isEmpty ? withDetail : "\(withDetail) • \(notes)"
    }

    private func daysUntil(_ date: Date) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func historyText(for action: GardenCareAction) -> String {
        let dateText = relativeDateText(action.date)

        switch action.type {
        case .watered:
            return L10n.f("CARE_HISTORY_WATERED_FORMAT", action.plantName, dateText)
        case .skipped:
            return L10n.f("CARE_HISTORY_DEFERRED_FORMAT", action.plantName, dateText)
        case .routineCreated:
            return L10n.f("CARE_HISTORY_ROUTINE_CREATED_FORMAT", action.plantName, dateText)
        case .careCompleted:
            return L10n.f("CARE_HISTORY_CARE_DONE_FORMAT", careActionTitle(for: action), action.plantName, dateText)
        case .careSkipped:
            return L10n.f("CARE_HISTORY_CARE_DEFERRED_FORMAT", careActionTitle(for: action), action.plantName, dateText)
        case .careRoutineCreated:
            return L10n.f("CARE_HISTORY_CARE_ROUTINE_CREATED_FORMAT", careActionTitle(for: action), action.plantName, dateText)
        }
    }

    private func careActionTitle(for action: GardenCareAction) -> String {
        if let kind = action.careKind, kind != .custom {
            return kind.displayName
        }

        let customTitle = action.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !customTitle.isEmpty {
            return customTitle
        }

        return action.careKind?.displayName ?? L10n.t("CARE_KIND_GENERIC")
    }

    private func relativeDateText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L10n.t("CARE_RELATIVE_TODAY") }
        if calendar.isDateInYesterday(date) { return L10n.t("CARE_RELATIVE_YESTERDAY") }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return L10n.f("CARE_RELATIVE_DATE_FORMAT", formatter.string(from: date))
    }

    private func normalizedPlantName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private var purchaseContent: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xl) {
            GardenShopHeroCard(
                gardenName: L10n.displayGardenName(currentGardenName),
                plantCount: placedPlants.count,
                cartCount: cartItemCount,
                total: formattedPrice(cartTotal)
            )

            if !cartItems.isEmpty {
                GardenCartSummaryCard(
                    entries: cartItems,
                    total: formattedPrice(cartTotal),
                    onIncrement: { item in addItemToCart(item) },
                    onDecrement: { item in decrementCartItem(item) },
                    onRemove: { item in removeCartItem(item) },
                    onClear: clearCart,
                    onCheckout: { showCheckoutSummary = true }
                )
            }

            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                HStack(alignment: .center) {
                    SectionTitle(title: L10n.t("SHOP_GARDEN_PLANTS_SECTION"))

                    Spacer()

                    if !cachedPurchaseGroups.isEmpty {
                        Button(action: addAllGardenPlantsToCart) {
                            HStack(spacing: 5) {
                                Image(systemName: "cart.badge.plus")
                                    .font(.system(size: 11, weight: .bold))
                                Text(L10n.t("SHOP_ADD_ALL"))
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(ArboreDesign.Colors.primaryGreen)
                            .padding(.horizontal, ArboreDesign.Spacing.sm)
                            .frame(height: 30)
                            .background(ArboreDesign.Colors.softSurface)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if cachedPurchaseGroups.isEmpty {
                    GardenInlineMessage(
                        systemImage: "leaf",
                        text: L10n.t("SHOP_NO_GARDEN_PLANTS")
                    )
                } else {
                    VStack(spacing: ArboreDesign.Spacing.sm) {
                        ForEach(cachedPurchaseGroups) { group in
                            let item = gardenPlantShopItem(for: group)
                            GardenShopItemRow(
                                item: item,
                                quantityText: group.count > 1 ? L10n.f("SHOP_QUANTITY_IN_GARDEN_FORMAT", group.count) : L10n.t("SHOP_IN_THIS_GARDEN"),
                                cartQuantity: cartQuantity(for: item),
                                actionTitle: L10n.t("COMMON_ADD"),
                                onAdd: { addItemToCart(item) }
                            )
                        }
                    }
                }
            }

            if !cachedRecommendations.isEmpty {
                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                    SectionTitle(title: L10n.t("SHOP_RECOMMENDATIONS_SECTION"))

                    VStack(spacing: ArboreDesign.Spacing.sm) {
                        ForEach(cachedRecommendations) { item in
                            GardenShopRecommendationRow(
                                item: item,
                                cartQuantity: cartQuantity(for: item),
                                onAdd: { addItemToCart(item) }
                            )
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                SectionTitle(title: L10n.t("SHOP_ADD_FROM_CATALOG_SECTION"))

                PurchaseSearchBar(text: $purchaseSearchText)

                if isLoadingPurchaseCatalog {
                    GardenInlineMessage(systemImage: "hourglass", text: L10n.t("SHOP_LOADING_CATALOG"))
                } else if let purchaseCatalogError {
                    PurchaseCatalogErrorCard(message: purchaseCatalogError) {
                        loadPurchaseCatalogIfNeeded(force: true)
                    }
                } else if cachedCatalogueItems.isEmpty {
                    GardenInlineMessage(systemImage: "magnifyingglass", text: L10n.t("SHOP_NO_CATALOG_PLANTS"))
                } else {
                    VStack(spacing: ArboreDesign.Spacing.sm) {
                        ForEach(cachedCatalogueItems) { item in
                            GardenShopItemRow(
                                item: item,
                                quantityText: item.recommendation ?? L10n.t("SHOP_ARBORE_CATALOG"),
                                cartQuantity: cartQuantity(for: item),
                                actionTitle: L10n.t("COMMON_ADD"),
                                onAdd: { addItemToCart(item) }
                            )
                        }
                    }
                }
            }

            GardenShopTrustCard()
        }
    }

    private func computePurchaseGroups() -> [GardenPlantPurchaseGroup] {
        var groups: [GardenPlantPurchaseGroup] = []
        var indexes: [String: Int] = [:]

        for plant in placedPlants {
            let key = "\(plant.plantID)-\(normalizedPlantName(plant.plantName))"
            if let index = indexes[key] {
                groups[index] = GardenPlantPurchaseGroup(
                    plant: groups[index].plant,
                    count: groups[index].count + 1
                )
            } else {
                indexes[key] = groups.count
                groups.append(GardenPlantPurchaseGroup(plant: plant, count: 1))
            }
        }

        return groups.sorted { $0.plant.plantName.localizedCaseInsensitiveCompare($1.plant.plantName) == .orderedAscending }
    }

    private var cartItemCount: Int {
        cartItems.reduce(0) { $0 + $1.quantity }
    }

    private var cartTotal: Double {
        cartItems.reduce(0) { $0 + $1.total }
    }

    private var checkoutSummaryText: String {
        L10n.f("SHOP_CHECKOUT_SUMMARY_FORMAT", cartItemCount, formattedPrice(cartTotal))
    }

    private func computeCatalogueItems() -> [GardenShopItem] {
        let gardenPlantIds = Set(cachedPurchaseGroups.map { $0.plant.plantID })
        let gardenPlantNames = Set(cachedPurchaseGroups.map { normalizedPlantName($0.plant.plantName) })
        let query = purchaseSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let wizardFilter = gardenDetails.map { WizardPlantFilter(wizard: $0.wizard) }

        var plants = cataloguePlants.filter { plant in
            !gardenPlantIds.contains(plant.id) && !gardenPlantNames.contains(normalizedPlantName(plant.name))
        }

        if !query.isEmpty {
            plants = plants.filter {
                $0.name.lowercased().contains(query)
                || $0.type.lowercased().contains(query)
                || preferredTranslation(for: $0)?.plantType.lowercased().contains(query) == true
            }
        }

        // Fix perf : on évalue le matching wizard UNE seule fois par plante
        // (O(N)) au lieu de l'appeler deux fois par comparaison dans le tri
        // (O(N·log N) appels lourds). Le comparateur se réduit à un lookup O(1).
        let matchedIDs: Set<String> = wizardFilter.map { filter in
            Set(plants.filter { filter.matches(plant: $0, locale: "fr") }.map { $0.id })
        } ?? []

        plants = plants.sorted { lhs, rhs in
            let leftMatches = matchedIDs.contains(lhs.id)
            let rightMatches = matchedIDs.contains(rhs.id)
            if leftMatches != rightMatches { return leftMatches }

            let leftHasModel = lhs.modelURL?.isEmpty == false
            let rightHasModel = rhs.modelURL?.isEmpty == false
            if leftHasModel != rightHasModel { return leftHasModel }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return plants.prefix(query.isEmpty ? 8 : 16).map { plant in
            catalogShopItem(for: plant, isRecommended: matchedIDs.contains(plant.id))
        }
    }

    private func computeRecommendations() -> [GardenShopItem] {
        var items: [GardenShopItem] = []

        for group in cachedPurchaseGroups.prefix(6) {
            if let soilItem = soilRecommendation(for: group.plant) {
                items.append(soilItem)
            }
        }

        if items.isEmpty && !placedPlants.isEmpty {
            items.append(
                GardenShopItem(
                    id: "soil-universal-\(gardenId)",
                    name: L10n.t("SHOP_ITEM_UNIVERSAL_SOIL_NAME"),
                    subtitle: L10n.t("SHOP_ITEM_UNIVERSAL_SOIL_SUBTITLE"),
                    priceRange: "8,90 € - 14,90 €",
                    estimatedPrice: 11.90,
                    category: .soil,
                    recommendation: L10n.t("SHOP_REC_FALLBACK_SOIL"),
                    priority: 2
                )
            )
        }

        if !placedPlants.isEmpty {
            items.append(
                GardenShopItem(
                    id: "tool-watering-can-\(gardenId)",
                    name: L10n.t("SHOP_ITEM_WATERING_CAN_NAME"),
                    subtitle: L10n.t("SHOP_ITEM_WATERING_CAN_SUBTITLE"),
                    priceRange: "12,90 € - 19,90 €",
                    estimatedPrice: 16.90,
                    category: .watering,
                    systemIcon: "drop.fill",
                    recommendation: L10n.f("SHOP_REC_USEFUL_FOR_PLANTS_FORMAT", placedPlants.count),
                    priority: 3
                )
            )

            items.append(
                GardenShopItem(
                    id: "tool-moisture-meter-\(gardenId)",
                    name: L10n.t("SHOP_ITEM_MOISTURE_METER_NAME"),
                    subtitle: L10n.t("SHOP_ITEM_MOISTURE_METER_SUBTITLE"),
                    priceRange: "9,90 € - 16,90 €",
                    estimatedPrice: 12.90,
                    category: .watering,
                    systemIcon: "gauge.with.dots.needle.67percent",
                    recommendation: L10n.t("SHOP_REC_MULTIPLE_NEEDS"),
                    priority: 3
                )
            )

            items.append(
                GardenShopItem(
                    id: "tool-pruner-\(gardenId)",
                    name: L10n.t("SHOP_ITEM_PRUNER_NAME"),
                    subtitle: L10n.t("SHOP_ITEM_PRUNER_SUBTITLE"),
                    priceRange: "10,90 € - 24,90 €",
                    estimatedPrice: 17.90,
                    category: .care,
                    systemIcon: "scissors",
                    recommendation: L10n.t("SHOP_REC_CARE_ROUTINES"),
                    priority: 4
                )
            )
        }

        if gardenPlantCareRoutines.contains(where: { $0.kind == .fertilize }) || placedPlants.count >= 3 {
            items.append(
                GardenShopItem(
                    id: "care-fertilizer-\(gardenId)",
                    name: L10n.t("SHOP_ITEM_FERTILIZER_NAME"),
                    subtitle: L10n.t("SHOP_ITEM_FERTILIZER_SUBTITLE"),
                    priceRange: "7,90 € - 13,90 €",
                    estimatedPrice: 9.90,
                    category: .care,
                    systemIcon: "leaf.arrow.circlepath",
                    recommendation: L10n.t("SHOP_REC_FERTILIZER_ROUTINES"),
                    priority: 4
                )
            )
        }

        if gardenPlantCareRoutines.contains(where: { $0.kind == .repot }) || gardenNeedsRepotSupport {
            items.append(
                GardenShopItem(
                    id: "accessory-pot-\(gardenId)",
                    name: L10n.t("SHOP_ITEM_DRAINAGE_POT_NAME"),
                    subtitle: L10n.t("SHOP_ITEM_DRAINAGE_POT_SUBTITLE"),
                    priceRange: "8,90 € - 29,90 €",
                    estimatedPrice: 18.90,
                    category: .accessory,
                    systemIcon: "circle.hexagongrid.fill",
                    recommendation: L10n.t("SHOP_REC_REPOT_SUPPORT"),
                    priority: 5
                )
            )
        }

        return uniqueShopItems(items)
            .sorted { $0.priority < $1.priority }
            .prefix(8)
            .map { $0 }
    }

    private var gardenNeedsRepotSupport: Bool {
        cachedPurchaseGroups.contains { group in
            guard let plant = cataloguePlant(for: group.plant),
                  let translation = preferredTranslation(for: plant) else { return false }
            return firstNonEmpty(translation.soilAndPot?.potSize, translation.soilAndPot?.repotFrequency) != nil
        }
    }

    private func gardenPlantShopItem(for group: GardenPlantPurchaseGroup) -> GardenShopItem {
        let plantDetail = cataloguePlant(for: group.plant)
        let type = preferredTranslation(for: plantDetail)?.plantType ?? plantDetail?.type ?? L10n.t("SHOP_GARDEN_PLANT_FALLBACK")
        let price = estimatedPlantPrice(for: plantDetail, fallbackName: group.plant.plantName)

        return GardenShopItem(
            id: "garden-plant-\(group.id)",
            name: group.plant.plantName,
            subtitle: type,
            priceRange: priceRange(around: price),
            estimatedPrice: price,
            category: .plant,
            systemIcon: "leaf.fill",
            sourcePlantId: group.plant.plantID,
            sourcePlantName: group.plant.plantName,
            recommendation: group.count > 1 ? L10n.f("SHOP_REC_COPIES_IN_PLAN_FORMAT", group.count) : L10n.t("SHOP_REC_ALREADY_IN_GARDEN"),
            priority: 1
        )
    }

    private func catalogShopItem(for plant: Plant, isRecommended: Bool) -> GardenShopItem {
        let translation = preferredTranslation(for: plant)
        let price = estimatedPlantPrice(for: plant, fallbackName: plant.name)
        let subtitle = firstNonEmpty(translation?.plantType, plant.type) ?? L10n.t("SHOP_CATALOG_PLANT_FALLBACK")

        return GardenShopItem(
            id: "catalog-plant-\(plant.id)",
            name: plant.name,
            subtitle: subtitle,
            priceRange: priceRange(around: price),
            estimatedPrice: price,
            category: .plant,
            systemIcon: "leaf.fill",
            sourcePlantId: plant.id,
            sourcePlantName: plant.name,
            recommendation: isRecommended ? L10n.t("SHOP_REC_COMPATIBLE_WITH_GARDEN") : L10n.t("SHOP_REC_AVAILABLE_IN_CATALOG"),
            priority: isRecommended ? 1 : 2
        )
    }

    private func soilRecommendation(for plant: PersistedPlant) -> GardenShopItem? {
        let plantDetail = cataloguePlant(for: plant)
        let translation = preferredTranslation(for: plantDetail)
        let substrate = firstNonEmpty(
            translation?.soilAndPot?.substrate,
            gardenDetails?.wizard.soil
        )
        let drainage = firstNonEmpty(translation?.soilAndPot?.drainage)

        guard let substrate else { return nil }

        let subtitle: String
        if let drainage {
            subtitle = "\(substrate) • \(drainage)"
        } else {
            subtitle = substrate
        }

        return GardenShopItem(
            id: "soil-\(plant.plantID)-\(normalizedForIdentifier(substrate))",
            name: L10n.f("SHOP_ITEM_SUBSTRATE_FOR_FORMAT", plant.plantName),
            subtitle: subtitle,
            priceRange: "8,90 € - 18,90 €",
            estimatedPrice: 12.90,
            category: .soil,
            systemIcon: "shippingbox.fill",
            sourcePlantId: plant.plantID,
            sourcePlantName: plant.plantName,
            recommendation: L10n.t("SHOP_REC_BASED_ON_SOIL_INFO"),
            priority: 2
        )
    }

    private func addAllGardenPlantsToCart() {
        for group in cachedPurchaseGroups {
            addItemToCart(gardenPlantShopItem(for: group), quantity: group.count)
        }
    }

    /// Recalcule les listes d'achat dérivées et les stocke en cache. Appelée
    /// quand une entrée change (catalogue chargé, plantes du jardin, recherche,
    /// wizard) — PAS à chaque render. Ordre important : les groupes d'abord,
    /// car le catalogue et les recommandations lisent `cachedPurchaseGroups`.
    private func recomputePurchaseData() {
        cachedPurchaseGroups = computePurchaseGroups()
        cachedCatalogueItems = computeCatalogueItems()
        cachedRecommendations = computeRecommendations()
    }

    private func addItemToCart(_ item: GardenShopItem, quantity: Int = 1) {
        guard quantity > 0 else { return }
        if let index = cartItems.firstIndex(where: { $0.item.id == item.id }) {
            cartItems[index].quantity += quantity
        } else {
            cartItems.append(GardenCartEntry(item: item, quantity: quantity))
        }
        cartItems.sort { $0.item.category.rawValue < $1.item.category.rawValue }
        persistPurchaseCart()
    }

    private func decrementCartItem(_ item: GardenShopItem) {
        guard let index = cartItems.firstIndex(where: { $0.item.id == item.id }) else { return }
        if cartItems[index].quantity <= 1 {
            cartItems.remove(at: index)
        } else {
            cartItems[index].quantity -= 1
        }
        persistPurchaseCart()
    }

    private func removeCartItem(_ item: GardenShopItem) {
        cartItems.removeAll { $0.item.id == item.id }
        persistPurchaseCart()
    }

    private func clearCart() {
        cartItems = []
        persistPurchaseCart()
    }

    private func cartQuantity(for item: GardenShopItem) -> Int {
        cartItems.first(where: { $0.item.id == item.id })?.quantity ?? 0
    }

    private var purchaseCartStorageKey: String {
        "gardenPurchaseCart.\(gardenId)"
    }

    private func loadPurchaseCart() {
        guard let data = UserDefaults.standard.data(forKey: purchaseCartStorageKey),
              let decoded = try? JSONDecoder().decode([GardenCartEntry].self, from: data) else {
            cartItems = []
            return
        }
        cartItems = decoded
    }

    private func persistPurchaseCart() {
        guard let data = try? JSONEncoder().encode(cartItems) else { return }
        UserDefaults.standard.set(data, forKey: purchaseCartStorageKey)
    }

    private func loadPurchaseCatalogIfNeeded(force: Bool = false) {
        guard force || !hasLoadedPurchaseCatalog else { return }
        hasLoadedPurchaseCatalog = true
        isLoadingPurchaseCatalog = true
        purchaseCatalogError = nil

        Task {
            do {
                let plants: [Plant] = try await NetworkManager.shared.request(
                    endpoint: "/plants",
                    method: .GET
                )
                await MainActor.run {
                    cataloguePlants = plants
                    isLoadingPurchaseCatalog = false
                    purchaseCatalogError = nil
                    recomputePurchaseData()
                }
            } catch {
                await MainActor.run {
                    isLoadingPurchaseCatalog = false
                    purchaseCatalogError = L10n.t("SHOP_CATALOG_LOAD_ERROR")
                }
            }
        }
    }

    private func cataloguePlant(for persistedPlant: PersistedPlant) -> Plant? {
        cataloguePlants.first { plant in
            plant.id == persistedPlant.plantID
            || normalizedPlantName(plant.name) == normalizedPlantName(persistedPlant.plantName)
        }
    }

    private func preferredTranslation(for plant: Plant?) -> PlantTranslation? {
        guard let plant else { return nil }
        let locale = Locale.current.language.languageCode?.identifier ?? "fr"
        return plant.translations[locale]
            ?? plant.translations["fr"]
            ?? plant.translations["en"]
            ?? plant.translations.values.first
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func uniqueShopItems(_ items: [GardenShopItem]) -> [GardenShopItem] {
        var seen = Set<String>()
        var unique: [GardenShopItem] = []

        for item in items {
            if seen.insert(item.id).inserted {
                unique.append(item)
            }
        }

        return unique
    }

    private func estimatedPlantPrice(for plant: Plant?, fallbackName: String) -> Double {
        let text = "\(plant?.type ?? "") \(plant?.name ?? fallbackName)".lowercased()
        if text.contains("tree") || text.contains("arbre") || text.contains("palm") || text.contains("palmier") {
            return 34.90
        }
        if text.contains("succulent") || text.contains("cactus") {
            return 9.90
        }
        if text.contains("flower") || text.contains("fleur") || text.contains("orchid") {
            return 18.90
        }
        return 16.90
    }

    private func priceRange(around price: Double) -> String {
        let low = max(4.90, price - 4)
        let high = price + 6
        return "\(formattedPrice(low)) - \(formattedPrice(high))"
    }

    private func formattedPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f €", value)
    }

    private func normalizedForIdentifier(_ value: String) -> String {
        normalizedPlantName(value)
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }

    private func loadMapTextureKind() async {
        do {
            let garden = try await GardenAPI.shared.getGarden(id: gardenId)
            await MainActor.run {
                gardenDetails = garden
                currentGardenName = garden.name
                mapTextureKind = MapTextureKind(spaceType: garden.wizard.spaceType)
                mapViewModel.applyRemoteMeasurementsIfNeeded(from: garden)
                recomputePurchaseData()
            }
        } catch {
            await MainActor.run {
                mapTextureKind = .garden
            }
            print("❌ loadMapTextureKind failed:", error)
        }
    }

    private func openRenameAlert() {
        renameText = currentGardenName
        renameError = nil
        showRenameAlert = true
    }

    @MainActor
    private func renameGarden() async {
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != currentGardenName else { return }

        isRenamingGarden = true
        renameError = nil

        do {
            try await GardenAPI.shared.updateGarden(
                id: gardenId,
                patch: GardenAPI.GardenPatch(name: newName)
            )
            currentGardenName = newName
            if var details = gardenDetails {
                details.name = newName
                gardenDetails = details
            }
            onGardenRenamed?(newName)
        } catch {
            renameError = L10n.t("GARDEN_RENAME_ERROR")
            print("❌ renameGarden failed:", error)
        }

        isRenamingGarden = false
    }

    private var fallbackWizardDTO: GardenWizardDTO {
        GardenWizardDTO(
            style: "",
            spaceType: "",
            exposure: nil,
            maintenance: nil,
            safety: [],
            soil: nil,
            scanMethod: nil
        )
    }

    private var gardenTabs: some View {
        HStack(spacing: ArboreDesign.Spacing.xs) {
            tabButton(.plan2D)
            tabButton(.tasks)
            tabButton(.purchase)
        }
        .padding(ArboreDesign.Spacing.xs)
        .background(ArboreDesign.Colors.softSurface)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
        )
        .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
    }

    private func headerIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(ArboreDesign.Colors.textPrimary)
            .frame(width: 42, height: 42)
            .background(ArboreDesign.Colors.card)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(ArboreDesign.Colors.border, lineWidth: 1)
            )
    }

    private func tabButton(_ tab: Tab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = tab
            }
        } label: {
            Text(tab.title)
                .font(.system(size: 13, weight: tab == selectedTab ? .bold : .semibold))
                .foregroundStyle(tab == selectedTab ? Color.white : ArboreDesign.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(tab == selectedTab ? primary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func placeholder(title: String, subtitle: String) -> some View {
        AppCard {
            VStack(spacing: ArboreDesign.Spacing.xs) {
                Text(title)
                    .font(ArboreDesign.Typography.sectionTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                Text(subtitle)
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ArboreDesign.Spacing.lg)
        }
    }
}

// MARK: - 6. SUBVIEWS & HELPERS

private struct PartnerHeroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
                    Text(L10n.t("SHOP_PARTNER_MARKETPLACE"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ArboreDesign.Colors.accentGold)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    Text(L10n.t("SHOP_PARTNER_TITLE"))
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: ArboreDesign.Spacing.md)

                Image(systemName: "bag.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Color(hex: "#162016"))
                    .frame(width: 44, height: 44)
                    .background(ArboreDesign.Colors.accentGold)
                    .clipShape(Circle())
            }

            Text(L10n.t("SHOP_PARTNER_SUBTITLE"))
                .font(ArboreDesign.Typography.bodySmall)
                .foregroundColor(.white.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)

            Button {
            } label: {
                HStack(spacing: ArboreDesign.Spacing.xs) {
                    Text(L10n.t("SHOP_PARTNER_CTA"))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(hex: "#162016"))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(ArboreDesign.Colors.accentGold)
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(ArboreDesign.Spacing.lg)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "#202922"),
                    Color(hex: "#111512")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 16, x: 0, y: 8)
    }
}

private struct GardenShopHeroCard: View {
    let gardenName: String
    let plantCount: Int
    let cartCount: Int
    let total: String

    var body: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.lg) {
            HStack(alignment: .top, spacing: ArboreDesign.Spacing.md) {
                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
                    Text(L10n.t("SHOP_GARDEN_SHOP_TITLE"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ArboreDesign.Colors.accentGold)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    Text(L10n.displayGardenName(gardenName))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L10n.t("SHOP_GARDEN_SHOP_SUBTITLE"))
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(.white.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "cart.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Color(hex: "#162016"))
                    .frame(width: 44, height: 44)
                    .background(ArboreDesign.Colors.accentGold)
                    .clipShape(Circle())
            }

            HStack(spacing: ArboreDesign.Spacing.sm) {
                GardenShopMetricPill(systemImage: "leaf.fill", title: L10n.t("SHOP_CATEGORY_PLANTS"), value: "\(plantCount)")
                GardenShopMetricPill(systemImage: "cart.fill", title: L10n.t("SHOP_CART"), value: "\(cartCount)")
                GardenShopMetricPill(systemImage: "creditcard.fill", title: L10n.t("SHOP_TOTAL"), value: total)
            }
        }
        .padding(ArboreDesign.Spacing.lg)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "#202922"),
                    Color(hex: "#111512")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 16, x: 0, y: 8)
    }
}

private struct GardenShopMetricPill: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ArboreDesign.Colors.accentGold)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.56))

                Text(value)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
    }
}

private struct GardenMeasurementPromptCard: View {
    let onMeasure: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#172019"),
                    Color(hex: "#0D120F")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GridPattern(spacing: 42)
                .stroke(Color.white.opacity(0.055), lineWidth: 1)

            VStack(spacing: ArboreDesign.Spacing.lg) {
                SettingsIconBadge(systemImage: "ruler.fill", tint: ArboreDesign.Colors.primaryGreen, size: 56)

                VStack(spacing: ArboreDesign.Spacing.xs) {
                    Text(L10n.t("GARDEN_MEASURE_SPACE_TITLE"))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(L10n.t("GARDEN_MEASURE_SPACE_SUBTITLE"))
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(Color.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, ArboreDesign.Spacing.lg)
                }

                Button(action: onMeasure) {
                    HStack(spacing: ArboreDesign.Spacing.xs) {
                        Image(systemName: "camera.viewfinder")
                        Text(L10n.t("GARDEN_MEASURE_SPACE_CTA"))
                    }
                    .font(ArboreDesign.Typography.button)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(ArboreDesign.Colors.primaryButton)
                    .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, ArboreDesign.Spacing.lg)
            }
            .padding(ArboreDesign.Spacing.lg)
        }
    }
}

private struct GardenCartSummaryCard: View {
    let entries: [GardenCartEntry]
    let total: String
    let onIncrement: (GardenShopItem) -> Void
    let onDecrement: (GardenShopItem) -> Void
    let onRemove: (GardenShopItem) -> Void
    let onClear: () -> Void
    let onCheckout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
            HStack(alignment: .center) {
                SectionTitle(title: L10n.t("SHOP_CART"))

                Spacer()

                Button(action: onClear) {
                    Text(L10n.t("COMMON_CLEAR"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .padding(.horizontal, ArboreDesign.Spacing.sm)
                        .frame(height: 30)
                        .background(ArboreDesign.Colors.softSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            AppCard {
                VStack(spacing: ArboreDesign.Spacing.sm) {
                    ForEach(entries) { entry in
                        GardenCartEntryRow(
                            entry: entry,
                            onIncrement: { onIncrement(entry.item) },
                            onDecrement: { onDecrement(entry.item) },
                            onRemove: { onRemove(entry.item) }
                        )
                    }

                    Divider()
                        .background(ArboreDesign.Colors.border)

                    HStack {
                        Text(L10n.t("SHOP_ESTIMATED_TOTAL"))
                            .font(ArboreDesign.Typography.body)
                            .foregroundColor(ArboreDesign.Colors.textPrimary)

                        Spacer()

                        Text(total)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(ArboreDesign.Colors.primaryGreen)
                    }

                    Button(action: onCheckout) {
                        HStack(spacing: ArboreDesign.Spacing.xs) {
                            Image(systemName: "bag.fill")
                            Text(L10n.t("SHOP_PREPARE_ORDER"))
                        }
                        .font(ArboreDesign.Typography.button)
                        .foregroundColor(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(ArboreDesign.Colors.primaryButton)
                        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct GardenCartEntryRow: View {
    let entry: GardenCartEntry
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: ArboreDesign.Spacing.sm) {
            Image(systemName: entry.item.systemIcon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(entry.item.category.tint)
                .frame(width: 30, height: 30)
                .background(entry.item.category.tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.item.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                    .lineLimit(1)

                Text(entry.item.priceRange)
                    .font(ArboreDesign.Typography.caption)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: ArboreDesign.Spacing.sm)

            HStack(spacing: 7) {
                Button(action: onDecrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 26, height: 26)
                }

                Text("\(entry.quantity)")
                    .font(.system(size: 13, weight: .bold))
                    .frame(minWidth: 18)

                Button(action: onIncrement) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 26, height: 26)
                }
            }
            .foregroundColor(ArboreDesign.Colors.primaryGreen)
            .background(ArboreDesign.Colors.softSurface)
            .clipShape(Capsule())

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
        .buttonStyle(.plain)
    }
}

private struct GardenShopItemRow: View {
    let item: GardenShopItem
    let quantityText: String
    let cartQuantity: Int
    let actionTitle: String
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.systemIcon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(item.category.tint)
                .frame(width: 56, height: 56)
                .background(item.category.tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(ArboreDesign.Typography.cardTitle)
                        .foregroundColor(ArboreDesign.Colors.textPrimary)
                        .lineLimit(1)

                    if cartQuantity > 0 {
                        Text("x\(cartQuantity)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.white)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(ArboreDesign.Colors.primaryGreen)
                            .clipShape(Capsule())
                    }
                }

                Text(item.subtitle)
                    .font(ArboreDesign.Typography.caption)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(item.priceRange)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(ArboreDesign.Colors.primaryGreen)

                    Text(quantityText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: ArboreDesign.Spacing.sm)

            Button(action: onAdd) {
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .background(ArboreDesign.Colors.primaryButton)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actionTitle)
        }
        .padding(ArboreDesign.Spacing.md)
        .background(CardContainer(cornerRadius: ArboreDesign.Radius.large))
        .shadow(color: ArboreDesign.Colors.shadow, radius: 10, x: 0, y: 4)
    }
}

private struct GardenShopRecommendationRow: View {
    let item: GardenShopItem
    let cartQuantity: Int
    let onAdd: () -> Void

    var body: some View {
        GardenShopItemRow(
            item: item,
            quantityText: item.recommendation ?? item.category.title,
            cartQuantity: cartQuantity,
            actionTitle: L10n.t("COMMON_ADD"),
            onAdd: onAdd
        )
    }
}

private struct PurchaseSearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: ArboreDesign.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(ArboreDesign.Colors.textSecondary)

            TextField(L10n.t("SHOP_SEARCH_PLACEHOLDER"), text: $text)
                .font(ArboreDesign.Typography.body)
                .foregroundColor(ArboreDesign.Colors.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, ArboreDesign.Spacing.md)
        .frame(height: 48)
        .background(ArboreDesign.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
        )
    }
}

private struct PurchaseCatalogErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: ArboreDesign.Spacing.sm) {
            SettingsIconBadge(systemImage: "wifi.exclamationmark", tint: ArboreDesign.Colors.danger, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(message)
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onRetry) {
                    Text(L10n.t("COMMON_RETRY"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ArboreDesign.Colors.primaryGreen)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(ArboreDesign.Spacing.md)
        .background(ArboreDesign.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
        )
    }
}

private struct GardenShopTrustCard: View {
    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                HStack(spacing: ArboreDesign.Spacing.sm) {
                    SettingsIconBadge(systemImage: "checkmark.seal.fill", tint: ArboreDesign.Colors.success, size: 40)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("SHOP_LINKED_LIST_TITLE"))
                            .font(ArboreDesign.Typography.cardTitle)
                            .foregroundColor(ArboreDesign.Colors.textPrimary)

                        Text(L10n.t("SHOP_LINKED_LIST_SUBTITLE"))
                            .font(ArboreDesign.Typography.bodySmall)
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()
                    .background(ArboreDesign.Colors.border)

                HStack(spacing: ArboreDesign.Spacing.sm) {
                    PartnerTrustPill(systemImage: "leaf.fill", text: L10n.t("SHOP_PLAN_PLANTS"))
                    PartnerTrustPill(systemImage: "sparkles", text: L10n.t("SHOP_ARBORE_RECOMMENDATIONS"))
                }
            }
        }
    }
}

private struct PartnerCategoryCard: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                .frame(width: 38, height: 38)
                .background(ArboreDesign.Colors.softSurface)
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ArboreDesign.Colors.textPrimary)

                Text(subtitle)
                    .font(ArboreDesign.Typography.caption)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(ArboreDesign.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .background(ArboreDesign.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
        )
    }
}

private struct PartnerTrustCard: View {
    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                HStack(spacing: ArboreDesign.Spacing.sm) {
                    SettingsIconBadge(systemImage: "checkmark.seal.fill", tint: ArboreDesign.Colors.success, size: 40)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("SHOP_CURATED_SELECTION_TITLE"))
                            .font(ArboreDesign.Typography.cardTitle)
                            .foregroundColor(ArboreDesign.Colors.textPrimary)

                        Text(L10n.t("SHOP_CURATED_SELECTION_SUBTITLE"))
                            .font(ArboreDesign.Typography.bodySmall)
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()
                    .background(ArboreDesign.Colors.border)

                HStack(spacing: ArboreDesign.Spacing.sm) {
                    PartnerTrustPill(systemImage: "lock.fill", text: L10n.t("SHOP_SECURE_REDIRECT"))
                    PartnerTrustPill(systemImage: "sparkles", text: L10n.t("SHOP_ARBORE_RECOMMENDATIONS"))
                }
            }
        }
    }
}

private struct PartnerTrustPill: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(ArboreDesign.Colors.textSecondary)
        .padding(.horizontal, ArboreDesign.Spacing.sm)
        .frame(height: 30)
        .background(ArboreDesign.Colors.softSurface)
        .clipShape(Capsule())
    }
}

private struct GardenStatBadge: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: ArboreDesign.Spacing.sm) {
            SettingsIconBadge(systemImage: systemImage, tint: ArboreDesign.Colors.primaryGreen, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ArboreDesign.Typography.caption)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)

                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
            }

            Spacer(minLength: 0)
        }
        .padding(ArboreDesign.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(ArboreDesign.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
        )
    }
}

private struct GardenStatsGrid: View {
    let area: Float
    let perimeter: Float
    let plantCount: Int
    let taskCount: Int

    private let columns = [
        GridItem(.flexible(), spacing: ArboreDesign.Spacing.sm),
        GridItem(.flexible(), spacing: ArboreDesign.Spacing.sm)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: ArboreDesign.Spacing.sm) {
            GardenDarkStatCard(
                systemImage: "square.dashed",
                title: L10n.t("GARDEN_STAT_SURFACE"),
                value: area > 0 ? "\(String(format: "%.2f", area)) m²" : "—"
            )

            GardenDarkStatCard(
                systemImage: "arrow.triangle.turn.up.right.diamond",
                title: L10n.t("GARDEN_STAT_PERIMETER"),
                value: perimeter > 0 ? "\(String(format: "%.2f", perimeter)) m" : "—"
            )

            GardenDarkStatCard(
                systemImage: "leaf.fill",
                title: L10n.t("SHOP_CATEGORY_PLANTS"),
                value: "\(plantCount)"
            )

            GardenDarkStatCard(
                systemImage: "checklist",
                title: L10n.t("GARDEN_STAT_TODO"),
                value: "\(taskCount)"
            )
        }
    }
}

private struct GardenDarkStatCard: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: ArboreDesign.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(ArboreDesign.Colors.primaryGreenDark)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.62))
                    .lineLimit(1)

                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(ArboreDesign.Spacing.md)
        .frame(minHeight: 72)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "#20231F"),
                    Color(hex: "#171A16")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 5)
    }
}

private struct GardenInlineMessage: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: ArboreDesign.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                .frame(width: 28, height: 28)
                .background(ArboreDesign.Colors.softSurface)
                .clipShape(Circle())

            Text(text)
                .font(ArboreDesign.Typography.bodySmall)
                .foregroundColor(ArboreDesign.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(ArboreDesign.Spacing.md)
        .background(ArboreDesign.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
        )
    }
}

private enum GardenCareScheduleSource {
    case watering(String)
    case care(String)
}

private struct GardenCareScheduleItem: Identifiable {
    let source: GardenCareScheduleSource
    let plantId: String?
    let plantName: String
    let title: String
    let subtitle: String
    let date: Date
    let icon: String
    let tint: Color
    let completionTitle: String

    var id: String {
        switch source {
        case .watering(let routineId):
            return "watering-\(routineId)"
        case .care(let routineId):
            return "care-\(routineId)"
        }
    }
}

private struct CareMonthCalendar: View {
    let items: [GardenCareScheduleItem]
    @Binding var selectedDate: Date
    @Binding var visibleMonth: Date

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
            SectionTitle(title: L10n.t("CARE_CALENDAR_SECTION"))

            AppCard {
                VStack(spacing: ArboreDesign.Spacing.md) {
                    HStack(spacing: ArboreDesign.Spacing.sm) {
                        Button(action: previousMonth) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(ArboreDesign.Colors.textPrimary)
                                .frame(width: 34, height: 34)
                                .background(ArboreDesign.Colors.softSurface)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.t("CARE_PREVIOUS_MONTH"))

                        Text(monthTitle)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(ArboreDesign.Colors.textPrimary)
                            .frame(maxWidth: .infinity)

                        Button(action: nextMonth) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(ArboreDesign.Colors.textPrimary)
                                .frame(width: 34, height: 34)
                                .background(ArboreDesign.Colors.softSurface)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.t("CARE_NEXT_MONTH"))
                    }

                    Button(action: jumpToToday) {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11, weight: .bold))
                            Text(L10n.t("CARE_STATUS_TODAY"))
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(ArboreDesign.Colors.primaryGreen)
                        .padding(.horizontal, ArboreDesign.Spacing.sm)
                        .frame(height: 30)
                        .background(ArboreDesign.Colors.softSurface)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(weekdaySymbols, id: \.self) { day in
                            Text(day)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(ArboreDesign.Colors.textSecondary)
                                .frame(maxWidth: .infinity)
                        }

                        ForEach(monthDates, id: \.self) { date in
                            calendarDay(date)
                        }
                    }
                }
            }
        }
    }

    private func calendarDay(_ date: Date) -> some View {
        let dayItems = itemsForDay(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let isCurrentMonth = calendar.isDate(date, equalTo: visibleMonth, toGranularity: .month)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedDate = date
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 13, weight: isSelected || isToday ? .bold : .semibold))
                    .foregroundColor(isSelected ? .white : (isCurrentMonth ? ArboreDesign.Colors.textPrimary : ArboreDesign.Colors.textSecondary.opacity(0.55)))
                    .frame(width: 30, height: 30)
                    .background(isSelected ? ArboreDesign.Colors.primaryGreen : (isToday ? ArboreDesign.Colors.softSurface : Color.clear))
                    .clipShape(Circle())

                HStack(spacing: 2) {
                    ForEach(Array(dayItems.prefix(3))) { item in
                        Circle()
                            .fill(item.tint)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .opacity(isCurrentMonth ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.f("CARE_DAY_ACTIONS_ACCESSIBILITY_FORMAT", calendar.component(.day, from: date), dayItems.count))
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: visibleMonth).capitalized
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (Array(symbols[first...]) + Array(symbols[..<first])).map { $0.replacingOccurrences(of: ".", with: "").capitalized }
    }

    private var monthDates: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth) else { return [] }
        let firstOfMonth = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: firstOfMonth) ?? firstOfMonth

        return (0..<42).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: gridStart)
        }
    }

    private func itemsForDay(_ date: Date) -> [GardenCareScheduleItem] {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())

        return items.filter { item in
            let itemDay = calendar.startOfDay(for: item.date)
            if day == today {
                return itemDay <= today
            }
            return itemDay == day
        }
    }

    private func previousMonth() {
        visibleMonth = calendar.date(byAdding: .month, value: -1, to: visibleMonth) ?? visibleMonth
    }

    private func nextMonth() {
        visibleMonth = calendar.date(byAdding: .month, value: 1, to: visibleMonth) ?? visibleMonth
    }

    private func jumpToToday() {
        let today = Date()
        visibleMonth = today
        selectedDate = today
    }
}

private struct CareCalendarAgendaRow: View {
    let item: GardenCareScheduleItem
    let status: (text: String, color: Color)
    let onComplete: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: ArboreDesign.Spacing.sm) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(item.tint)
                .frame(width: 32, height: 32)
                .background(item.tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: ArboreDesign.Spacing.xs) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(ArboreDesign.Colors.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(status.text)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(status.color)
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(status.color.opacity(0.12))
                        .clipShape(Capsule())
                        .lineLimit(1)
                }

                Text("\(item.plantName) • \(item.subtitle)")
                    .font(ArboreDesign.Typography.caption)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .lineLimit(2)

                HStack(spacing: ArboreDesign.Spacing.sm) {
                    Button(action: onComplete) {
                        Label(item.completionTitle, systemImage: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(ArboreDesign.Colors.primaryGreen)
                            .padding(.horizontal, ArboreDesign.Spacing.sm)
                            .frame(height: 30)
                            .background(ArboreDesign.Colors.softSurface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onSkip) {
                        Text(L10n.t("CARE_DEFER"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                            .padding(.horizontal, ArboreDesign.Spacing.sm)
                            .frame(height: 30)
                            .background(ArboreDesign.Colors.softSurface.opacity(0.7))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
    }
}

private struct CareTaskCard: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let detail: String
    let tint: Color
    let completionTitle: String
    let onComplete: () -> Void
    let onSkip: () -> Void

    var body: some View {
        AppCard {
            HStack(alignment: .top, spacing: ArboreDesign.Spacing.md) {
                SettingsIconBadge(systemImage: systemImage, tint: tint, size: 44)

                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: ArboreDesign.Spacing.sm) {
                        Text(title)
                            .font(ArboreDesign.Typography.cardTitle)
                            .foregroundColor(ArboreDesign.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)

                        Text(detail)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(tint)
                            .padding(.horizontal, ArboreDesign.Spacing.sm)
                            .frame(height: 26)
                            .background(tint.opacity(0.12))
                            .clipShape(Capsule())
                            .lineLimit(1)
                    }

                    Text(subtitle)
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: ArboreDesign.Spacing.sm) {
                        Button(action: onComplete) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                Text(completionTitle)
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(Color.white)
                            .padding(.horizontal, ArboreDesign.Spacing.md)
                            .frame(height: 34)
                            .background(ArboreDesign.Colors.primaryButton)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(action: onSkip) {
                            Text(L10n.t("CARE_DEFER"))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(ArboreDesign.Colors.textSecondary)
                                .padding(.horizontal, ArboreDesign.Spacing.md)
                                .frame(height: 34)
                                .background(ArboreDesign.Colors.softSurface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct CareEmptyRoutineCard: View {
    let plantName: String
    let onCreate: () -> Void

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                HStack(alignment: .top, spacing: ArboreDesign.Spacing.md) {
                    SettingsIconBadge(systemImage: "calendar.badge.plus", tint: ArboreDesign.Colors.primaryGreen, size: 44)

                    VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
                        Text(L10n.t("CARE_NO_ACTIVE_ROUTINE"))
                            .font(ArboreDesign.Typography.cardTitle)
                            .foregroundColor(ArboreDesign.Colors.textPrimary)

                        Text(L10n.f("CARE_EMPTY_ROUTINE_FORMAT", plantName))
                            .font(ArboreDesign.Typography.bodySmall)
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button(action: onCreate) {
                    HStack(spacing: ArboreDesign.Spacing.xs) {
                        Image(systemName: "calendar.badge.plus")
                        Text(L10n.t("CARE_PLAN_ACTION"))
                    }
                    .font(ArboreDesign.Typography.button)
                    .foregroundColor(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(ArboreDesign.Colors.primaryButton)
                    .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CareWeekTimeline: View {
    let routines: [WateringRoutine]

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
            SectionTitle(title: L10n.t("CARE_CALENDAR_SECTION"))

            AppCard {
                HStack(spacing: ArboreDesign.Spacing.xs) {
                    ForEach(days.indices, id: \.self) { index in
                        let date = days[index]
                        let count = dueCount(on: date)

                        VStack(spacing: ArboreDesign.Spacing.xs) {
                            Text(dayLabel(for: date))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(ArboreDesign.Colors.textSecondary)

                            ZStack {
                                Circle()
                                    .fill(count == 0 ? ArboreDesign.Colors.softSurface.opacity(0.55) : ArboreDesign.Colors.softSurface)
                                    .frame(width: 34, height: 34)

                                if count > 0 {
                                    Image(systemName: "drop.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(Color(hex: "#3A93B8"))
                                }
                            }

                            Text(count > 1 ? "\(count)" : " ")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(ArboreDesign.Colors.textSecondary)
                                .frame(height: 10)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func dueCount(on date: Date) -> Int {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())

        return routines.filter { routine in
            let routineDay = calendar.startOfDay(for: routine.nextWateringDate)
            if day == today {
                return routineDay <= today
            }
            return routineDay == day
        }.count
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).replacingOccurrences(of: ".", with: "").capitalized
    }
}

private struct CareUpcomingRow: View {
    let systemImage: String
    let plantName: String
    let title: String
    let subtitle: String
    let status: String
    let tint: Color

    var body: some View {
        HStack(spacing: ArboreDesign.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ArboreDesign.Typography.body)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                    .lineLimit(1)

                Text("\(plantName) • \(subtitle)")
                    .font(ArboreDesign.Typography.caption)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: ArboreDesign.Spacing.sm)

            Text(status)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
                .padding(.horizontal, ArboreDesign.Spacing.sm)
                .frame(height: 28)
                .background(tint.opacity(0.12))
                .clipShape(Capsule())
                .lineLimit(1)
        }
        .padding(ArboreDesign.Spacing.md)
        .background(ArboreDesign.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
        )
    }
}

private struct CareRoutineSetupRow: View {
    let plantName: String
    let onCreate: () -> Void

    var body: some View {
        HStack(spacing: ArboreDesign.Spacing.sm) {
            Image(systemName: "leaf")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                .frame(width: 30, height: 30)
                .background(ArboreDesign.Colors.softSurface)
                .clipShape(Circle())

            Text(plantName)
                .font(ArboreDesign.Typography.body)
                .foregroundColor(ArboreDesign.Colors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: ArboreDesign.Spacing.sm)

            Button(action: onCreate) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text(L10n.t("CARE_PLAN"))
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                .padding(.horizontal, ArboreDesign.Spacing.sm)
                .frame(height: 30)
                .background(ArboreDesign.Colors.softSurface)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CarePlantStatusRow: View {
    let name: String
    let status: String
    let tint: Color

    var body: some View {
        HStack(spacing: ArboreDesign.Spacing.sm) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)

            Text(name)
                .font(ArboreDesign.Typography.body)
                .foregroundColor(ArboreDesign.Colors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: ArboreDesign.Spacing.sm)

            Text(status)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
                .padding(.horizontal, ArboreDesign.Spacing.sm)
                .frame(height: 28)
                .background(tint.opacity(0.12))
                .clipShape(Capsule())
                .lineLimit(1)
        }
        .padding(ArboreDesign.Spacing.md)
        .background(ArboreDesign.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
        )
    }
}

private struct CareRecommendationCard: View {
    let message: String

    var body: some View {
        AppCard {
            HStack(alignment: .top, spacing: ArboreDesign.Spacing.md) {
                SettingsIconBadge(systemImage: "sparkles", tint: ArboreDesign.Colors.accentGold, size: 44)

                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
                    Text(L10n.t("CARE_TIP_OF_DAY"))
                        .font(ArboreDesign.Typography.cardTitle)
                        .foregroundColor(ArboreDesign.Colors.textPrimary)

                    Text(message)
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct CareHistoryRow: View {
    let text: String

    var body: some View {
        HStack(spacing: ArboreDesign.Spacing.sm) {
            Circle()
                .fill(ArboreDesign.Colors.primaryGreen.opacity(0.22))
                .frame(width: 8, height: 8)

            Text(text)
                .font(ArboreDesign.Typography.bodySmall)
                .foregroundColor(ArboreDesign.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

private struct CardContainer: View {
    let cornerRadius: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(ArboreDesign.Colors.card)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ArboreDesign.Colors.border, lineWidth: 1)
            )
    }
}

// MARK: - 7. LOGIQUE MAP 2D & CARTE INTERACTIVE

class Garden2DViewModel: ObservableObject {
    @Published var displayPlants: [DisplayPlant] = []
    @Published var selectedPlant: DisplayPlant? = nil
    @Published var selectedPlantDetail: Plant? = nil
    @Published var isLoadingPlantDetail: Bool = false
    
    // 🆕 Données des bordures du jardin
    @Published var boundaryPoints: [[Float]] = []
    @Published var area: Float = 0
    @Published var perimeter: Float = 0
    
    // 🆕 Centroïd des bordures (pour normalisation)
    private var boundaryCentroid: (x: Float, z: Float) = (0, 0)
    
    func selectPlant(_ plant: DisplayPlant) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedPlant = plant
        }
        fetchPlantDetail(id: plant.data.plantID)
    }
    
    func deselectPlant() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            selectedPlant = nil
            selectedPlantDetail = nil
        }
    }
    
    private func fetchPlantDetail(id: String) {
        isLoadingPlantDetail = true
        selectedPlantDetail = nil
        Task {
            do {
                let plant: Plant = try await NetworkManager.shared.request(
                    endpoint: "/plants/\(id)",
                    method: .GET
                )
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.25)) {
                        self.selectedPlantDetail = plant
                        self.isLoadingPlantDetail = false
                    }
                }
            } catch {
                await MainActor.run { self.isLoadingPlantDetail = false }
                print("⚠️ Plant detail not found for id \(id): \(error)")
            }
        }
    }
    
    func loadGarden(gardenId: String) {
        let url = GardenLocalStore.sceneURL(for: gardenId)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let scene = try JSONDecoder().decode(PersistedARScene.self, from: data).normalizedToWorldFrame()
                DispatchQueue.main.async {
                    self.displayPlants = scene.plants.map { DisplayPlant(data: $0) }
                    
                    // 🆕 Charger les bordures du jardin si disponibles
                    self.area = scene.area ?? 0
                    self.perimeter = scene.perimeter ?? 0
                    self.boundaryPoints = Self.resolvedBoundaryPoints(
                        scene.boundaryPoints,
                        area: self.area,
                        perimeter: self.perimeter
                    )
                    
                    self.refreshBoundaryCentroid()
                    
                    print("🗺️ Jardin chargé: \(self.displayPlants.count) plantes, \(self.boundaryPoints.count) points de bordure")
                    print("📍 Centroïd bordures: x=\(self.boundaryCentroid.x), z=\(self.boundaryCentroid.z)")
                    
                    // 🐛 Debug: Afficher les coordonnées
                    if !self.displayPlants.isEmpty {
                        let firstPlant = self.displayPlants[0].data
                        print("🌱 Première plante: x=\(firstPlant.position[0]), z=\(firstPlant.position[2])")
                    }
                    if !self.boundaryPoints.isEmpty {
                        print("📐 Bordures:")
                        for (i, point) in self.boundaryPoints.enumerated() {
                            print("   Point \(i): x=\(point[0]), z=\(point[2])")
                        }
                    }
                }
            } catch {
                clearGarden()
                print("Error loading JSON: \(error)")
            }
        } else {
            DispatchQueue.main.async {
                self.clearGarden()
            }
        }
    }

    @MainActor
    func applyRemoteMeasurementsIfNeeded(from garden: GardenDTO) {
        guard boundaryPoints.count < 3, let measurements = garden.measurements else { return }

        area = measurements.area ?? area
        perimeter = measurements.perimeter ?? perimeter
        boundaryPoints = Self.resolvedBoundaryPoints(
            measurements.boundaryPoints,
            area: area,
            perimeter: perimeter
        )
        refreshBoundaryCentroid()
    }

    private func clearGarden() {
        displayPlants = []
        selectedPlant = nil
        selectedPlantDetail = nil
        isLoadingPlantDetail = false
        boundaryPoints = []
        area = 0
        perimeter = 0
        boundaryCentroid = (0, 0)
    }

    private func refreshBoundaryCentroid() {
        let validPoints = Self.sanitizedBoundaryPoints(boundaryPoints)
        boundaryPoints = validPoints

        guard !validPoints.isEmpty else {
            boundaryCentroid = (0, 0)
            return
        }

        let sumX = validPoints.reduce(Float(0)) { $0 + $1[0] }
        let sumZ = validPoints.reduce(Float(0)) { $0 + $1[2] }
        boundaryCentroid = (
            x: sumX / Float(validPoints.count),
            z: sumZ / Float(validPoints.count)
        )
    }

    private static func resolvedBoundaryPoints(_ points: [[Float]]?, area: Float, perimeter: Float) -> [[Float]] {
        let valid = sanitizedBoundaryPoints(points ?? [])
        if valid.count >= 3 { return valid }
        guard area > 0 || perimeter > 0 else { return [] }
        return fallbackBoundary(area: area, perimeter: perimeter)
    }

    private static func sanitizedBoundaryPoints(_ points: [[Float]]) -> [[Float]] {
        points.filter { $0.count >= 3 }
    }

    private static func fallbackBoundary(area: Float, perimeter: Float) -> [[Float]] {
        let safeArea = max(Double(area), 1.0)
        let halfPerimeter = max(Double(perimeter) / 2.0, 4.0)
        let discriminant = halfPerimeter * halfPerimeter - 4.0 * safeArea

        let width: Double
        let depth: Double
        if discriminant >= 0 {
            width = max((halfPerimeter + discriminant.squareRoot()) / 2.0, 1.0)
            depth = max(safeArea / width, 1.0)
        } else {
            width = safeArea.squareRoot()
            depth = width
        }

        let halfW = Float(width / 2.0)
        let halfD = Float(depth / 2.0)
        return [
            [-halfW, 0, -halfD],
            [halfW, 0, -halfD],
            [halfW, 0, halfD],
            [-halfW, 0, halfD]
        ]
    }
}

enum MapTextureKind {
    case home
    case garden

    init(spaceType: String) {
        let normalized = spaceType
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        if normalized.contains("interieur") || normalized.contains("appartement") {
            self = .home
        } else {
            self = .garden
        }
    }

    var insideResourceName: String {
        switch self {
        case .home: return "inside_home"
        case .garden: return "inside_garden"
        }
    }

    var outsideResourceName: String {
        switch self {
        case .home: return "outside_home"
        case .garden: return "outside_garden"
        }
    }
}

struct GardenPlanInteractiveMap: View {
    @ObservedObject var viewModel: Garden2DViewModel
    let textureKind: MapTextureKind
    @State private var scale: CGFloat = 80.0
    @State private var lastScale: CGFloat = 80.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: "#111510"),
                        Color(hex: "#1A211C"),
                        Color(hex: "#0D120F")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                MapTextureImage(resourceName: textureKind.outsideResourceName)
                    .opacity(0.92)
                
                OrganicMapTexture()
                    .stroke(Color.white.opacity(0.035), lineWidth: 1)
                    .blendMode(.screen)
                
                GridPattern(spacing: scale)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    .offset(x: offset.width, y: offset.height)
                
                // 🎯 SOLUTION DÉFINITIVE : Tout dessiner avec GeometryReader en coordonnées absolues
                GeometryReader { innerGeo in
                    let centerX = innerGeo.size.width / 2
                    let centerY = innerGeo.size.height / 2
                    
                    ZStack {
                        if viewModel.boundaryPoints.count > 2 {
                            gardenBoundaryPath(centerX: centerX, centerY: centerY)
                                .stroke(
                                    Color.white.opacity(0.78),
                                    style: StrokeStyle(lineWidth: 8.2, lineCap: .round, lineJoin: .round)
                                )
                        }

                        if viewModel.boundaryPoints.count > 2 {
                            MapTextureImage(resourceName: textureKind.insideResourceName)
                                .mask(
                                    MapBoundaryMask(
                                        points: viewModel.boundaryPoints,
                                        scale: scale,
                                        offset: offset
                                    )
                                )
                                .overlay(
                                    MapBoundaryMask(
                                        points: viewModel.boundaryPoints,
                                        scale: scale,
                                        offset: offset
                                    )
                                    .fill(Color.white.opacity(0.03))
                                )
                        } else {
                            MapTextureImage(resourceName: textureKind.insideResourceName)
                                .opacity(0.35)
                        }

                        // Bordures du jardin
                        if !viewModel.boundaryPoints.isEmpty {
                            gardenBoundaryPath(centerX: centerX, centerY: centerY)
                            .fill(ArboreDesign.Colors.primaryGreen.opacity(0.14))

                            gardenBoundaryPath(centerX: centerX, centerY: centerY)
                                .stroke(
                                    Color(hex: "#2F332E").opacity(0.96),
                                    style: StrokeStyle(lineWidth: 7.4, lineCap: .round, lineJoin: .round)
                                )

                            gardenBoundaryPath(centerX: centerX, centerY: centerY)
                            .stroke(
                                Color(hex: "#171A16").opacity(0.78),
                                style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
                            )
                        }
                        
                        // Plantes - EXACTEMENT la même formule que les bordures
                        ForEach(Array(viewModel.displayPlants.enumerated()), id: \.element.id) { index, plantWrapper in
                            let p = plantWrapper.data
                            let x = centerX + CGFloat(p.position[0]) * scale + offset.width
                            let y = centerY + CGFloat(p.position[2]) * scale + offset.height
                            let isSelected = viewModel.selectedPlant?.id == plantWrapper.id
                            let markerColor = plantStatusColor(index: index)
                            
                            VStack(spacing: 0) {
                                PlantMapMarker(
                                    variant: PlantMapMarkerVariant(index: index, plantName: p.plantName),
                                    statusColor: markerColor,
                                    isSelected: isSelected
                                )
                                if scale > 60 || isSelected {
                                    Text(p.plantName)
                                        .font(.system(size: isSelected ? 11 : 9, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(isSelected ? 0.72 : 0.52))
                                        .clipShape(Capsule())
                                        .offset(y: 5)
                                }
                            }
                            .position(x: x, y: y)
                            .onTapGesture { viewModel.selectPlant(plantWrapper) }
                        }
                    }
                }
                
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Button(action: { withAnimation { fitContent(geo: geo) } }) { IconBtn(icon: "arrow.up.left.and.arrow.down.right") }
                            Button(action: { withAnimation { scale *= 1.2 } }) { IconBtn(icon: "plus.magnifyingglass") }
                            Button(action: { withAnimation { scale /= 1.2 } }) { IconBtn(icon: "minus.magnifyingglass") }
                        }
                        .padding()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.image, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture().onChanged { val in offset = CGSize(width: lastOffset.width + val.translation.width, height: lastOffset.height + val.translation.height) }.onEnded { _ in lastOffset = offset })
            .gesture(MagnificationGesture().onChanged { val in scale = lastScale * val }.onEnded { _ in lastScale = scale })
            .onChange(of: viewModel.displayPlants.count) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation { fitContent(geo: geo) }
                }
            }
        }
    }

    private func plantStatusColor(index: Int) -> Color {
        switch index % 5 {
        case 3:
            return ArboreDesign.Colors.accentGold
        case 4:
            return Color(hex: "#D98B4A")
        default:
            return ArboreDesign.Colors.primaryGreen
        }
    }

    private func gardenBoundaryPath(centerX: CGFloat, centerY: CGFloat) -> Path {
        Path { path in
            for (index, point) in viewModel.boundaryPoints.enumerated() {
                let x = centerX + CGFloat(point[0]) * scale + offset.width
                let z = centerY + CGFloat(point[2]) * scale + offset.height

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: z))
                } else {
                    path.addLine(to: CGPoint(x: x, y: z))
                }
            }
            path.closeSubpath()
        }
    }
    
    private func fitContent(geo: GeometryProxy) {
        // Collecter toutes les coordonnées (plantes ET bordures) pour calculer la taille
        var allX: [CGFloat] = []
        var allZ: [CGFloat] = []
        
        // Ajouter les plantes
        if !viewModel.displayPlants.isEmpty {
            allX += viewModel.displayPlants.map { CGFloat($0.data.position[0]) }
            allZ += viewModel.displayPlants.map { CGFloat($0.data.position[2]) }
        }
        
        // Ajouter les bordures
        if !viewModel.boundaryPoints.isEmpty {
            allX += viewModel.boundaryPoints.map { CGFloat($0[0]) }
            allZ += viewModel.boundaryPoints.map { CGFloat($0[2]) }
        }
        
        // Si aucune donnée, ne rien faire
        guard !allX.isEmpty && !allZ.isEmpty else { return }
        
        let minX = allX.min() ?? 0
        let maxX = allX.max() ?? 0
        let minZ = allZ.min() ?? 0
        let maxZ = allZ.max() ?? 0
        
        // 🔧 CORRECTION : Puisque les données sont normalisées par le centroïd,
        // le centre devrait TOUJOURS être (0, 0) !
        // On ne calcule plus (min+max)/2 qui peut être décalé si la distribution n'est pas uniforme
        let centerX: CGFloat = 0  // 🆕 Centre sur l'origine
        let centerZ: CGFloat = 0  // 🆕 Centre sur l'origine
        
        let spanX = max(maxX - minX, 1.0)
        let spanZ = max(maxZ - minZ, 1.0)
        let scaleX = (geo.size.width - 100) / spanX
        let scaleZ = (geo.size.height - 100) / spanZ
        let newScale = min(scaleX, scaleZ, 150.0)
        self.scale = newScale
        self.lastScale = newScale
        self.offset = CGSize(width: -centerX * newScale, height: -centerZ * newScale)  // = (0, 0)
        self.lastOffset = self.offset
        
        print("📏 FitContent: scale=\(newScale), centerX=\(centerX), centerZ=\(centerZ)")
        print("📏 BBox: X[\(minX)...\(maxX)], Z[\(minZ)...\(maxZ)]")
    }
}

// Helpers
struct IconBtn: View {
    let icon: String
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 42, height: 42)
            .background(Color.black.opacity(0.34))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
    }
}

enum PlantMapMarkerVariant {
    case rosette
    case palm
    case fern
    case succulent
    case cactus

    init(index: Int, plantName: String) {
        let normalized = plantName
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        if normalized.contains("cactus") || normalized.contains("succulent") {
            self = .cactus
            return
        }

        switch index % 5 {
        case 0: self = .rosette
        case 1: self = .palm
        case 2: self = .fern
        case 3: self = .succulent
        default: self = .rosette
        }
    }
}

struct PlantMapMarker: View {
    let variant: PlantMapMarkerVariant
    let statusColor: Color
    let isSelected: Bool

    private var size: CGFloat { isSelected ? 46 : 36 }
    private var plantSize: CGFloat { isSelected ? 34 : 27 }

    var body: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(isSelected ? 0.26 : 0.16))
                .frame(width: size + 14, height: size + 14)
                .blur(radius: 2.2)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "#2C3A25"),
                            Color(hex: "#151A14")
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: size / 1.7
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(isSelected ? ArboreDesign.Colors.accentGold : Color.white.opacity(0.18), lineWidth: isSelected ? 2.2 : 1)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 8, x: 0, y: 4)

            plantShape
                .frame(width: plantSize, height: plantSize)
                .shadow(color: Color.black.opacity(0.20), radius: 3, x: 0, y: 2)

            Circle()
                .stroke(statusColor.opacity(0.65), lineWidth: isSelected ? 2 : 1.3)
                .frame(width: size + 3, height: size + 3)
        }
        .scaleEffect(isSelected ? 1.05 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
    }

    @ViewBuilder
    private var plantShape: some View {
        switch variant {
        case .rosette:
            RosettePlantSymbol()
        case .palm:
            PalmPlantSymbol()
        case .fern:
            FernPlantSymbol()
        case .succulent:
            SucculentPlantSymbol()
        case .cactus:
            CactusPlantSymbol()
        }
    }
}

private struct RosettePlantSymbol: View {
    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { index in
                LeafPetal(
                    width: index.isMultiple(of: 2) ? 8 : 6,
                    height: index.isMultiple(of: 2) ? 18 : 14,
                    colorA: Color(hex: "#7BC55B"),
                    colorB: Color(hex: "#265F2F")
                )
                .offset(y: -6)
                .rotationEffect(.degrees(Double(index) * 36))
            }

            Circle()
                .fill(Color(hex: "#A6D66B"))
                .frame(width: 6, height: 6)
        }
    }
}

private struct PalmPlantSymbol: View {
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                PalmFrond()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#9AD76A"), Color(hex: "#2E7137")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 10, height: 22)
                    .offset(y: -7)
                    .rotationEffect(.degrees(Double(index) * 45 + 8))
            }

            Circle()
                .fill(Color(hex: "#3C7A38"))
                .frame(width: 7, height: 7)
        }
    }
}

private struct FernPlantSymbol: View {
    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                FernStem()
                    .stroke(Color(hex: "#B2DF7B"), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: 24, height: 7)
                    .offset(x: 6)
                    .rotationEffect(.degrees(Double(index) * 60))
            }

            Circle()
                .fill(Color(hex: "#477D35"))
                .frame(width: 5, height: 5)
        }
    }
}

private struct SucculentPlantSymbol: View {
    var body: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { index in
                LeafPetal(
                    width: 9,
                    height: 16,
                    colorA: Color(hex: "#B5D88F"),
                    colorB: Color(hex: "#5E8F53")
                )
                .offset(y: -5)
                .rotationEffect(.degrees(Double(index) * 51.4))
            }

            ForEach(0..<5, id: \.self) { index in
                LeafPetal(
                    width: 7,
                    height: 12,
                    colorA: Color(hex: "#D7E8AA"),
                    colorB: Color(hex: "#78A55A")
                )
                .offset(y: -2.5)
                .rotationEffect(.degrees(Double(index) * 72 + 18))
            }
        }
    }
}

private struct CactusPlantSymbol: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [Color(hex: "#78B957"), Color(hex: "#2E7137")], startPoint: .top, endPoint: .bottom))
                .frame(width: 8, height: 24)

            Capsule()
                .fill(LinearGradient(colors: [Color(hex: "#8DCB62"), Color(hex: "#356F35")], startPoint: .top, endPoint: .bottom))
                .frame(width: 7, height: 17)
                .offset(x: -7, y: 3)
                .rotationEffect(.degrees(-22))

            Capsule()
                .fill(LinearGradient(colors: [Color(hex: "#96D06A"), Color(hex: "#356F35")], startPoint: .top, endPoint: .bottom))
                .frame(width: 7, height: 16)
                .offset(x: 7, y: 4)
                .rotationEffect(.degrees(24))
        }
    }
}

private struct LeafPetal: View {
    let width: CGFloat
    let height: CGFloat
    let colorA: Color
    let colorB: Color

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [colorA, colorB],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: width, height: height)
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
            )
    }
}

private struct PalmFrond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX - rect.width * 0.15, y: rect.midY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX + rect.width * 0.2, y: rect.midY)
        )
        path.closeSubpath()
        return path
    }
}

private struct FernStem: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))

        for index in 1...4 {
            let x = rect.minX + rect.width * CGFloat(index) / 5
            path.move(to: CGPoint(x: x, y: rect.midY))
            path.addLine(to: CGPoint(x: x + 2, y: rect.minY))
            path.move(to: CGPoint(x: x, y: rect.midY))
            path.addLine(to: CGPoint(x: x + 2, y: rect.maxY))
        }
        return path
    }
}

struct GridPattern: Shape {
    let spacing: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let safeSpacing = max(20, spacing)
        let centerX = rect.width / 2
        let centerY = rect.height / 2
        var i: CGFloat = 0
        while centerX + i < rect.width || centerX - i > 0 {
            path.move(to: CGPoint(x: centerX + i, y: 0)); path.addLine(to: CGPoint(x: centerX + i, y: rect.height))
            path.move(to: CGPoint(x: centerX - i, y: 0)); path.addLine(to: CGPoint(x: centerX - i, y: rect.height))
            i += safeSpacing
        }
        i = 0
        while centerY + i < rect.height || centerY - i > 0 {
            path.move(to: CGPoint(x: 0, y: centerY + i)); path.addLine(to: CGPoint(x: rect.width, y: centerY + i))
            path.move(to: CGPoint(x: 0, y: centerY - i)); path.addLine(to: CGPoint(x: rect.width, y: centerY - i))
            i += safeSpacing
        }
        return path
    }
}

struct OrganicMapTexture: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rows = 7
        for row in 0..<rows {
            let y = rect.height * CGFloat(row + 1) / CGFloat(rows + 1)
            path.move(to: CGPoint(x: rect.minX - 20, y: y))

            for step in 0...5 {
                let x = rect.width * CGFloat(step) / 5
                let controlY = y + CGFloat(row.isMultiple(of: 2) ? 18 : -18)
                path.addQuadCurve(
                    to: CGPoint(x: x, y: y + CGFloat(step.isMultiple(of: 2) ? 8 : -8)),
                    control: CGPoint(x: x - rect.width / 10, y: controlY)
                )
            }
        }
        return path
    }
}

struct MapTextureImage: View {
    let resourceName: String

    var body: some View {
        GeometryReader { proxy in
            if let image = loadImage(named: resourceName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else {
                fallbackColor
            }
        }
        .allowsHitTesting(false)
    }

    private var fallbackColor: Color {
        resourceName.contains("home") ? Color(hex: "#24231F") : Color(hex: "#182017")
    }

    private func loadImage(named name: String) -> UIImage? {
        let candidates: [(String?, String)] = [
            ("Assets/Map_2D", name),
            ("Map_2D", name),
            (nil, name)
        ]

        for candidate in candidates {
            if let url = Bundle.main.url(
                forResource: candidate.1,
                withExtension: "png",
                subdirectory: candidate.0
            ),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }

        return UIImage(named: name)
    }
}

struct MapBoundaryMask: Shape {
    let points: [[Float]]
    let scale: CGFloat
    let offset: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }

        let centerX = rect.width / 2
        let centerY = rect.height / 2

        for (index, point) in points.enumerated() {
            let x = centerX + CGFloat(point[0]) * scale + offset.width
            let y = centerY + CGFloat(point[2]) * scale + offset.height

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        path.closeSubpath()
        return path
    }
}

// 🆕 Shape pour dessiner les bordures du jardin
struct BoundaryShape: Shape {
    let points: [[Float]]  // Points [x, y, z]
    let scale: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        
        // Utiliser X et Z (on ignore Y qui est l'altitude)
        // Les coordonnées sont déjà multipliées par le scale dans l'offset du parent
        // On dessine juste les points relatifs à l'origine (0,0)
        
        // Premier point - coordonnées directes scalées
        let firstX = CGFloat(points[0][0]) * scale
        let firstZ = CGFloat(points[0][2]) * scale
        path.move(to: CGPoint(x: firstX, y: firstZ))
        
        // Tracer les lignes vers chaque point suivant
        for i in 1..<points.count {
            let x = CGFloat(points[i][0]) * scale
            let z = CGFloat(points[i][2]) * scale
            path.addLine(to: CGPoint(x: x, y: z))
        }
        
        // Fermer le polygone
        path.closeSubpath()
        
        return path
    }
}

// 🆕 Vue pour dessiner le remplissage du polygone dans le même système que les plantes
struct BoundaryPolygonFill: View {
    let points: [[Float]]
    let scale: CGFloat
    
    var body: some View {
        if points.count > 2 {
            Path { path in
                let firstX = CGFloat(points[0][0]) * scale
                let firstZ = CGFloat(points[0][2]) * scale
                path.move(to: CGPoint(x: firstX, y: firstZ))
                
                for i in 1..<points.count {
                    let x = CGFloat(points[i][0]) * scale
                    let z = CGFloat(points[i][2]) * scale
                    path.addLine(to: CGPoint(x: x, y: z))
                }
                path.closeSubpath()
            }
            .fill(ArboreDesign.Colors.primaryGreen.opacity(0.16))
        }
    }
}

// 🆕 Vue pour dessiner le contour du polygone dans le même système que les plantes
struct BoundaryPolygonStroke: View {
    let points: [[Float]]
    let scale: CGFloat
    
    var body: some View {
        if points.count > 1 {
            Path { path in
                let firstX = CGFloat(points[0][0]) * scale
                let firstZ = CGFloat(points[0][2]) * scale
                path.move(to: CGPoint(x: firstX, y: firstZ))
                
                for i in 1..<points.count {
                    let x = CGFloat(points[i][0]) * scale
                    let z = CGFloat(points[i][2]) * scale
                    path.addLine(to: CGPoint(x: x, y: z))
                }
                path.closeSubpath()
            }
            .stroke(ArboreDesign.Colors.primaryGreen, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Plant Minimap Detail Panel

struct PlantMinimapDetailPanel: View {
    @ObservedObject var viewModel: Garden2DViewModel

    private let accent = ArboreDesign.Colors.primaryGreen

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: "#151914").opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.32), radius: 20, x: 0, y: 10)

            if viewModel.isLoadingPlantDetail {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 60, height: 60)
                        .overlay(ProgressView().tint(.white))
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.2)).frame(width: 120, height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.12)).frame(width: 80, height: 10)
                    }
                    Spacer()
                }
                .padding(14)

            } else if let plant = viewModel.selectedPlantDetail {
                let locale = Locale.current.language.languageCode?.identifier ?? "fr"
                let translation = plant.translations[locale] ?? plant.translations["fr"]

                HStack(alignment: .top, spacing: 14) {
                    AsyncImage(url: URL(string: plant.imageURLs.first ?? "")) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default:
                            ZStack {
                                Color.white.opacity(0.08)
                                Image(systemName: "leaf.fill").font(.system(size: 22)).foregroundColor(accent)
                            }
                        }
                    }
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plant.name)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Text(compactDescription(for: plant, translation: translation))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.68))
                                .lineLimit(2)
                        }

                        HStack(spacing: 6) {
                            if let sun = translation?.sun?.lightType {
                                MiniPill(icon: "sun.max.fill", text: sun, color: ArboreDesign.Colors.accentGold)
                            }
                            if let water = translation?.water?.frequency {
                                MiniPill(icon: "drop.fill", text: water, color: Color(hex: "#8FB7C9"))
                            }
                            MiniPill(icon: "checkmark.seal.fill", text: L10n.t("CARE_HEALTHY_STATUS"), color: accent)
                        }

                        Button {
                        } label: {
                            HStack(spacing: 6) {
                                Text(L10n.t("COMMON_SEE_DETAILS"))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(accent)
                            .padding(.top, 2)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 20)
                }
                .padding(14)

            } else if let selected = viewModel.selectedPlant {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(accent.opacity(0.16)).frame(width: 60, height: 60)
                        Image(systemName: "leaf.fill").font(.system(size: 22)).foregroundColor(accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selected.data.plantName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        Text("x: \(String(format: "%.1f", selected.data.position[0]))m  z: \(String(format: "%.1f", selected.data.position[2]))m")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                }
                .padding(14)
            }

            // Close button
            Button { viewModel.deselectPlant() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.selectedPlantDetail?.id)
        .animation(.easeOut(duration: 0.2), value: viewModel.isLoadingPlantDetail)
    }

    private func compactDescription(for plant: Plant, translation: PlantTranslation?) -> String {
        if let description = translation?.description, !description.isEmpty {
            return description
        }

        if let plantType = translation?.plantType, !plantType.isEmpty {
            return plantType
        }

        return plant.type
    }
}

// Small info row used in expanded section
private struct PlantInfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

struct MiniPill: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
    }
}

#Preview {
    ManageGardenView()
        .environmentObject(ThemeManager())
}
