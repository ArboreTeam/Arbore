//
//  ManageGardenView.swift
//  ArboreUi
//
//  Created on November 25, 2025.
//

import SwiftUI
import Foundation

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
                if showingGardenList || (selectedProject == nil && !isResolvingInitialGarden) {
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
                } else {
                    loadingGardenContent
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingNewProjectSheet) {
                Text("Nouveau projet (Wizard)")
            }
            .onAppear {
                isResolvingInitialGarden = selectedProject == nil
                projectService.refreshProjects()
                DispatchQueue.main.async {
                    syncSelectedProject()
                    isResolvingInitialGarden = false
                }
            }
            .onChange(of: projectService.projects.map(\.id)) { _, _ in
                syncSelectedProject()
                isResolvingInitialGarden = false
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
            showingGardenList = true
        }

        projectService.refreshProjects()
    }
    
    private func syncSelectedProject() {
        guard !projectService.projects.isEmpty else {
            selectedProject = nil
            showingGardenList = true
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
    
    // États pour l'interface "Purchase"
    enum Tab: String, CaseIterable {
        case plan2D = "2D Plan"
        case tasks = "Tasks"
        case purchase = "Purchase"
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
                            // --- LA CARTE 2D ---
                            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                                SectionTitle(title: "Vue du jardin")
                                
                                // Map + panneau plante superposé
                                ZStack(alignment: .bottom) {
                                    GardenPlanInteractiveMap(viewModel: mapViewModel)
                                        .frame(height: 450)
                                        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.image, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: ArboreDesign.Radius.image, style: .continuous)
                                                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
                                        )
                                        .shadow(color: ArboreDesign.Colors.shadow, radius: 12, x: 0, y: 6)
                                    
                                    // Panneau infos plante (overlay en bas de la carte)
                                    if mapViewModel.selectedPlant != nil {
                                        PlantMinimapDetailPanel(viewModel: mapViewModel)
                                            .transition(.move(edge: .bottom).combined(with: .opacity))
                                            .padding(.horizontal, 10)
                                            .padding(.bottom, 10)
                                    }
                                }
                                
                                // Statistiques du jardin (surface et périmètre)
                                if mapViewModel.area > 0 {
                                    HStack(spacing: ArboreDesign.Spacing.sm) {
                                        GardenStatBadge(
                                            systemImage: "square.dashed",
                                            title: "Surface",
                                            value: "\(String(format: "%.2f", mapViewModel.area)) m²"
                                        )

                                        GardenStatBadge(
                                            systemImage: "arrow.triangle.turn.up.right.diamond",
                                            title: "Périmètre",
                                            value: "\(String(format: "%.2f", mapViewModel.perimeter)) m"
                                        )
                                    }
                                }
                                
                                if mapViewModel.displayPlants.isEmpty {
                                    GardenInlineMessage(
                                        systemImage: "leaf",
                                        text: "Aucune plante placée. Ouvrez le jardin en AR pour en ajouter."
                                    )
                                } else if mapViewModel.selectedPlant == nil {
                                    GardenInlineMessage(
                                        systemImage: "hand.tap",
                                        text: "\(mapViewModel.displayPlants.count) plante\(mapViewModel.displayPlants.count > 1 ? "s" : "") • Touchez un point pour les détails"
                                    )
                                }
                            }
                            
                        case .purchase:
                            // --- LISTE D'ACHATS ---
                            sectionHeader
                            purchaseList
                            
                        case .tasks:
                            placeholder(title: "Tasks", subtitle: "Gestion des tâches à venir")
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

            Text(gardenName)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(ArboreDesign.Colors.textPrimary)
                .lineLimit(2)
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
            Text("TO BUY (\(purchaseItems.count))")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ArboreDesign.Colors.textSecondary)
                .tracking(1.1)
            Spacer()
            Button { sortByPriority.toggle() } label: {
                Text("Sort by Priority")
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

struct GardenPlanInteractiveMap: View {
    @ObservedObject var viewModel: Garden2DViewModel
    @State private var scale: CGFloat = 80.0
    @State private var lastScale: CGFloat = 80.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: "#161814")
                GridPattern(spacing: scale)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .offset(x: offset.width, y: offset.height)
                
                // 🎯 SOLUTION DÉFINITIVE : Tout dessiner avec GeometryReader en coordonnées absolues
                GeometryReader { innerGeo in
                    let centerX = innerGeo.size.width / 2
                    let centerY = innerGeo.size.height / 2
                    
                    ZStack {
                        // Bordures du jardin
                        if !viewModel.boundaryPoints.isEmpty {
                            // Remplissage
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
                            .fill(ArboreDesign.Colors.primaryGreen.opacity(0.16))
                            
                            // Contour
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
                            .stroke(ArboreDesign.Colors.primaryGreen, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        }
                        
                        // Plantes - EXACTEMENT la même formule que les bordures
                        ForEach(viewModel.displayPlants) { plantWrapper in
                            let p = plantWrapper.data
                            let x = centerX + CGFloat(p.position[0]) * scale + offset.width
                            let y = centerY + CGFloat(p.position[2]) * scale + offset.height
                            
                            VStack(spacing: 0) {
                                ZStack {
                                    if viewModel.selectedPlant?.id == plantWrapper.id {
                                        Circle().stroke(ArboreDesign.Colors.accentGold, lineWidth: 2)
                                            .frame(width: 36, height: 36)
                                            .background(Circle().fill(Color.white.opacity(0.2)))
                                    }
                                    Circle().fill(ArboreDesign.Colors.primaryGreen)
                                        .frame(width: 20, height: 20)
                                        .shadow(radius: 2)
                                }
                                if scale > 60 || viewModel.selectedPlant?.id == plantWrapper.id {
                                    Text(p.plantName)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(3)
                                        .background(Color.black.opacity(0.5))
                                        .cornerRadius(4)
                                        .offset(y: 4)
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
    @State private var isExpanded: Bool = false

    private let accent = ArboreDesign.Colors.primaryGreen

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Glassmorphism background
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)

            if viewModel.isLoadingPlantDetail {
                // Loading skeleton
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

                VStack(alignment: .leading, spacing: 0) {
                    // ── Compact row (always visible) ──
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
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(accent.opacity(0.4), lineWidth: 1))

                        VStack(alignment: .leading, spacing: 5) {
                            Text(plant.name)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(translation?.plantType ?? plant.type)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(accent)

                            // Pills
                            HStack(spacing: 5) {
                                if let sun = translation?.sun?.lightType {
                                    MiniPill(icon: "sun.max.fill", text: sun, color: .yellow)
                                }
                                if let water = translation?.water?.frequency {
                                    MiniPill(icon: "drop.fill", text: water, color: .cyan)
                                }
                                if let diff = translation?.care?.difficulty {
                                    MiniPill(icon: "chart.bar.fill", text: diff, color: accent)
                                }
                            }
                        }

                        Spacer(minLength: 28)
                    }
                    .padding(.top, 14)
                    .padding(.horizontal, 14)
                    .padding(.bottom, isExpanded ? 10 : 14)

                    // ── Expanded section ──
                    if isExpanded {
                        VStack(alignment: .leading, spacing: 10) {
                            Divider().background(Color.white.opacity(0.12))

                            // Description complète
                            if let desc = translation?.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            // Extra care rows
                            VStack(spacing: 6) {
                                if let orientation = translation?.sun?.orientation {
                                    PlantInfoRow(icon: "safari.fill", label: "Orientation", value: orientation)
                                }
                                if let amount = translation?.water?.amount {
                                    PlantInfoRow(icon: "drop.halffull", label: "Quantité d'eau", value: amount)
                                }
                                if let substrate = translation?.soilAndPot?.substrate {
                                    PlantInfoRow(icon: "circle.hexagongrid.fill", label: "Substrat", value: substrate)
                                }
                                if let growth = translation?.lifeCycle?.growth {
                                    PlantInfoRow(icon: "arrow.up.forward.circle.fill", label: "Croissance", value: growth)
                                }
                                if let weekly = translation?.care?.weekly, !weekly.isEmpty {
                                    PlantInfoRow(icon: "checklist", label: "Soins hebdo", value: weekly.prefix(2).joined(separator: ", "))
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // ── "Voir plus / Voir moins" button ──
                    Button {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "Voir moins" : "Voir plus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(accent)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(accent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(accent.opacity(0.08))
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: isExpanded ? 0 : 0,
                                style: .continuous
                            )
                        )
                        // Round only bottom corners
                        .clipShape(
                            .rect(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 18,
                                bottomTrailingRadius: 18,
                                topTrailingRadius: 0
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }

            } else if let selected = viewModel.selectedPlant {
                // Fallback
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.15)).frame(width: 52, height: 52)
                        Image(systemName: "leaf.fill").font(.system(size: 20)).foregroundColor(accent)
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
        .onChange(of: viewModel.selectedPlant?.id) { _, _ in
            // Reset expanded state when plant changes
            withAnimation { isExpanded = false }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.selectedPlantDetail?.id)
        .animation(.easeOut(duration: 0.2), value: viewModel.isLoadingPlantDetail)
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
