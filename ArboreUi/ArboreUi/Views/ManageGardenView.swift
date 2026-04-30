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

// Modèle pour la liste d'achats (Ton code)
struct PurchaseItem: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let priceRange: String
    let imageName: String?
    let systemIcon: String?
    let priority: Int
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
                Text("Nouveau projet (Wizard)")
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
        LoadingView(title: "Chargement du jardin...")
    }

    private var emptyGardenContent: some View {
        VStack(spacing: ArboreDesign.Spacing.lg) {
            EmptyStateView(
                systemImage: "leaf",
                title: "Aucun jardin sélectionné",
                message: "Vos jardins restent disponibles depuis la liste.",
                buttonTitle: "Voir vos jardins",
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
    
    @Environment(\.dismiss) var dismiss
    
    // ViewModel pour la Map
    @StateObject private var mapViewModel = Garden2DViewModel()
    @State private var mapTextureKind: MapTextureKind = .garden
    
    // États pour l'interface "Purchase"
    enum Tab: String, CaseIterable {
        case plan2D = "Plan"
        case tasks = "Soins"
        case purchase = "Achats"
    }
    
    @State private var selectedTab: Tab = .plan2D
    @State private var sortByPriority = true
    
    private var primary: Color { ArboreDesign.Colors.primaryGreen }
    
    init(
        gardenId: String,
        gardenName: String,
        showsBackButton: Bool = true,
        onOpenGardenList: (() -> Void)? = nil
    ) {
        self.gardenId = gardenId
        self.gardenName = gardenName
        self.showsBackButton = showsBackButton
        self.onOpenGardenList = onOpenGardenList
    }
    
    // Données Mock pour la liste d'achats
    @State private var purchaseItems: [PurchaseItem] = [
        .init(name: "Monstera Deliciosa", subtitle: "Garden Center • In Stock", priceRange: "$25 - $40", imageName: "monstera", systemIcon: nil, priority: 1),
        .init(name: "Snake Plant", subtitle: "Home Depot", priceRange: "$15 - $30", imageName: nil, systemIcon: "leaf.fill", priority: 2),
        .init(name: "Organic Potting Mix", subtitle: "Any Garden Center", priceRange: "$8 - $12", imageName: nil, systemIcon: "bag.fill", priority: 2)
    ]
    
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
                            // --- LISTE D'ACHATS ---
                            sectionHeader
                            purchaseList
                            
                        case .tasks:
                            placeholder(title: "Soins", subtitle: "Les rappels d’entretien de votre jardin apparaîtront ici.")
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
                // Action ajouter
            } label: {
                Image(systemName: "plus")
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
        .onAppear {
            mapViewModel.loadGarden(gardenId: gardenId)
            Task { await loadMapTextureKind() }
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
                .accessibilityLabel("Retour")
            } else if let onOpenGardenList {
                Button(action: onOpenGardenList) {
                    headerIcon("line.3.horizontal")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voir mes jardins")
            } else {
                Color.clear
                    .frame(width: 42, height: 42)
            }

            Text("Mon jardin")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(ArboreDesign.Colors.textPrimary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)

            Color.clear
                .frame(width: 42, height: 42)
        }
        .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
        .padding(.top, ArboreDesign.Spacing.md)
        .padding(.bottom, ArboreDesign.Spacing.sm)
        .background(ArboreDesign.Colors.background)
    }

    private var planContent: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.lg) {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
                SectionTitle(title: "Vue du jardin")

                Text("Visualisez l’emplacement de vos plantes et touchez un marqueur pour afficher ses besoins.")
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ZStack(alignment: .bottom) {
                GardenPlanInteractiveMap(viewModel: mapViewModel, textureKind: mapTextureKind)
                    .frame(height: 468)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 10)

                if mapViewModel.selectedPlant != nil {
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

            if mapViewModel.displayPlants.isEmpty {
                GardenInlineMessage(
                    systemImage: "leaf",
                    text: "Aucune plante placée. Ouvrez le jardin en AR pour en ajouter."
                )
            } else if mapViewModel.selectedPlant == nil {
                GardenInlineMessage(
                    systemImage: "hand.tap",
                    text: "\(mapViewModel.displayPlants.count) plante\(mapViewModel.displayPlants.count > 1 ? "s" : "") placée\(mapViewModel.displayPlants.count > 1 ? "s" : "") • Touchez un marqueur pour voir les détails"
                )
            }
        }
    }

    private var pendingTaskCount: Int {
        min(2, max(mapViewModel.displayPlants.count, 0))
    }

    private func loadMapTextureKind() async {
        do {
            let garden = try await GardenAPI.shared.getGarden(id: gardenId)
            await MainActor.run {
                mapTextureKind = MapTextureKind(spaceType: garden.wizard.spaceType)
            }
        } catch {
            await MainActor.run {
                mapTextureKind = .garden
            }
            print("❌ loadMapTextureKind failed:", error)
        }
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
            Text(tab.rawValue)
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
    
    private var sectionHeader: some View {
        HStack {
            Text("À ACHETER (\(purchaseItems.count))")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ArboreDesign.Colors.textSecondary)
                .tracking(1.1)
            Spacer()
            Button { sortByPriority.toggle() } label: {
                Text("Priorité")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var purchaseList: some View {
        VStack(spacing: 12) {
            ForEach(purchaseItems) { item in
                PurchaseRow(item: item, primary: primary) {}
            }
        }
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

private struct PurchaseRow: View {
    let item: PurchaseItem
    let primary: Color
    let onBuy: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                    .fill(ArboreDesign.Colors.softSurface)
                    .frame(width: 64, height: 64)
                if let icon = item.systemIcon {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(primary)
                } else {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(primary)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(ArboreDesign.Typography.cardTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                Text(item.subtitle)
                    .font(ArboreDesign.Typography.caption)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                Text(item.priceRange)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
            }
            Spacer()
            Button(action: onBuy) {
                Text("Buy")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(ArboreDesign.Colors.primaryButton)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(ArboreDesign.Spacing.md)
        .background(CardContainer(cornerRadius: ArboreDesign.Radius.large))
        .shadow(color: ArboreDesign.Colors.shadow, radius: 10, x: 0, y: 4)
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
                title: "Surface",
                value: area > 0 ? "\(String(format: "%.2f", area)) m²" : "—"
            )

            GardenDarkStatCard(
                systemImage: "arrow.triangle.turn.up.right.diamond",
                title: "Périmètre",
                value: perimeter > 0 ? "\(String(format: "%.2f", perimeter)) m" : "—"
            )

            GardenDarkStatCard(
                systemImage: "leaf.fill",
                title: "Plantes",
                value: "\(plantCount)"
            )

            GardenDarkStatCard(
                systemImage: "checklist",
                title: "À faire",
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
                let scene = try JSONDecoder().decode(PersistedARScene.self, from: data)
                DispatchQueue.main.async {
                    self.displayPlants = scene.plants.map { DisplayPlant(data: $0) }
                    
                    // 🆕 Charger les bordures du jardin si disponibles
                    self.boundaryPoints = scene.boundaryPoints ?? []
                    self.area = scene.area ?? 0
                    self.perimeter = scene.perimeter ?? 0
                    
                    // 🔧 Calculer le centroïd des bordures pour normalisation
                    if !self.boundaryPoints.isEmpty {
                        let sumX = self.boundaryPoints.reduce(0.0) { $0 + $1[0] }
                        let sumZ = self.boundaryPoints.reduce(0.0) { $0 + $1[2] }
                        self.boundaryCentroid = (
                            x: sumX / Float(self.boundaryPoints.count),
                            z: sumZ / Float(self.boundaryPoints.count)
                        )
                    }
                    
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
            } catch { print("Error loading JSON: \(error)") }
        }
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
                                ZStack {
                                    Circle()
                                        .fill(markerColor.opacity(isSelected ? 0.28 : 0.16))
                                        .frame(width: isSelected ? 48 : 38, height: isSelected ? 48 : 38)
                                        .blur(radius: 1.5)

                                    Circle()
                                        .stroke(isSelected ? ArboreDesign.Colors.accentGold : Color.white.opacity(0.16), lineWidth: isSelected ? 2 : 1)
                                        .frame(width: isSelected ? 38 : 30, height: isSelected ? 38 : 30)

                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [markerColor.opacity(0.98), markerColor.opacity(0.72)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: isSelected ? 28 : 22, height: isSelected ? 28 : 22)
                                        .overlay(
                                            Image(systemName: "leaf.fill")
                                                .font(.system(size: isSelected ? 12 : 10, weight: .bold))
                                                .foregroundColor(.white)
                                        )
                                        .shadow(color: markerColor.opacity(0.45), radius: isSelected ? 12 : 8, x: 0, y: 4)
                                }
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
                            MiniPill(icon: "checkmark.seal.fill", text: "En bonne santé", color: accent)
                        }

                        Button {
                        } label: {
                            HStack(spacing: 6) {
                                Text("Voir détails")
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
