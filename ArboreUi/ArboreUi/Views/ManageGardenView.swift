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
    
    @Environment(\.dismiss) var dismiss
    
    // ViewModel pour la Map
    @StateObject private var mapViewModel = Garden2DViewModel()
    @State private var mapTextureKind: MapTextureKind = .garden
    @State private var gardenDetails: GardenDTO?
    @State private var showMeasurementApp = false
    @State private var currentGardenName: String
    @State private var renameText = ""
    @State private var showRenameAlert = false
    @State private var isRenamingGarden = false
    @State private var renameError: String?
    @State private var showARShareCapture = false
    
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
    
    // Données Mock pour la liste d'achats
    @State private var purchaseItems: [PurchaseItem] = [
        .init(name: "Hydrangea macrophylla", subtitle: "Plante recommandée pour compléter votre composition", priceRange: "À partir de 24,90 €", imageName: nil, systemIcon: "leaf.fill", priority: 1),
        .init(name: "Terreau plantes fleuries", subtitle: "Substrat adapté aux besoins du jardin", priceRange: "8,90 € - 14,90 €", imageName: nil, systemIcon: "shippingbox.fill", priority: 2),
        .init(name: "Arrosoir précision", subtitle: "Pour un arrosage doux au pied des plantes", priceRange: "12,90 € - 19,90 €", imageName: nil, systemIcon: "drop.fill", priority: 2)
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
        .alert("Renommer le jardin", isPresented: $showRenameAlert) {
            TextField("Nom du jardin", text: $renameText)

            Button("Annuler", role: .cancel) {}
            Button("Enregistrer") {
                Task { await renameGarden() }
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Choisissez un nom facile à reconnaître.")
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
        .onAppear {
            mapViewModel.loadGarden(gardenId: gardenId)
            currentGardenName = gardenDetails?.name ?? gardenName
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

            Text(currentGardenName)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(ArboreDesign.Colors.textPrimary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)

            Menu {
                Button(action: { showARShareCapture = true }) {
                    Label("Partager en 3D", systemImage: "camera.viewfinder")
                }

                Button(action: openRenameAlert) {
                    Label("Renommer", systemImage: "pencil")
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
            .accessibilityLabel("Actions du jardin")
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

                Text("\(currentGardenName) • Visualisez l’emplacement de vos plantes et touchez un marqueur pour afficher ses besoins.")
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
                    text: "Mesurez d’abord les dimensions de votre espace pour afficher le plan 2D."
                )
            } else if mapViewModel.displayPlants.isEmpty {
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

    private var hasMeasuredSpace: Bool {
        mapViewModel.boundaryPoints.count > 2
    }

    private var careContent: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xl) {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
                SectionTitle(title: "Aujourd’hui")

                Text("Les gestes simples à faire pour garder votre jardin en forme.")
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
            }

            VStack(spacing: ArboreDesign.Spacing.md) {
                CareTaskCard(
                    systemImage: "drop.fill",
                    title: "Arroser \(carePlantName(at: 0, fallback: "Hydrangea macrophylla"))",
                    subtitle: "Sol à garder légèrement humide",
                    actionTitle: "Marquer comme fait",
                    tint: Color(hex: "#6EA7C8")
                )

                CareTaskCard(
                    systemImage: "leaf.arrow.circlepath",
                    title: "Nettoyer les feuilles",
                    subtitle: "\(carePlantName(at: 1, fallback: "Pothos")) profitera d’un feuillage dépoussiéré",
                    actionTitle: "Noter comme fait",
                    tint: ArboreDesign.Colors.primaryGreen
                )
            }

            CareWeekTimeline()

            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                SectionTitle(title: "État des plantes")

                VStack(spacing: ArboreDesign.Spacing.sm) {
                    CarePlantStatusRow(name: carePlantName(at: 0, fallback: "Hydrangea"), status: "OK", tint: ArboreDesign.Colors.success)
                    CarePlantStatusRow(name: carePlantName(at: 1, fallback: "Pothos"), status: "Arrosage demain", tint: Color(hex: "#6EA7C8"))
                    CarePlantStatusRow(name: carePlantName(at: 2, fallback: "Lavande"), status: "Besoin de taille", tint: ArboreDesign.Colors.accentGold)
                    CarePlantStatusRow(name: carePlantName(at: 3, fallback: "Monstera"), status: "À surveiller", tint: Color(hex: "#D98B4A"))
                }
            }

            CareRecommendationCard(plantName: carePlantName(at: 0, fallback: "Hydrangea"))

            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                SectionTitle(title: "Dernières actions")

                AppCard {
                    VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
                        CareHistoryRow(text: "\(carePlantName(at: 0, fallback: "Hydrangea")) arrosée hier")
                        CareHistoryRow(text: "\(carePlantName(at: 1, fallback: "Pothos")) ajouté il y a 3 jours")
                        CareHistoryRow(text: "\(carePlantName(at: 2, fallback: "Lavande")) taillée la semaine dernière")
                    }
                }
            }
        }
    }

    private func carePlantName(at index: Int, fallback: String) -> String {
        guard mapViewModel.displayPlants.indices.contains(index) else { return fallback }
        return mapViewModel.displayPlants[index].data.plantName
    }

    private var purchaseContent: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xl) {
            PartnerHeroCard()

            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                SectionTitle(title: "Liste recommandée")

                VStack(spacing: ArboreDesign.Spacing.md) {
                    ForEach(purchaseItems) { item in
                        PurchaseRow(item: item, primary: primary) {}
                    }
                }
            }

            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                SectionTitle(title: "Essentiels pour ce jardin")

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: ArboreDesign.Spacing.sm),
                    GridItem(.flexible(), spacing: ArboreDesign.Spacing.sm)
                ], spacing: ArboreDesign.Spacing.sm) {
                    PartnerCategoryCard(systemImage: "leaf.fill", title: "Plantes", subtitle: "Catalogue compatible")
                    PartnerCategoryCard(systemImage: "shippingbox.fill", title: "Terreau", subtitle: "Substrats adaptés")
                    PartnerCategoryCard(systemImage: "drop.fill", title: "Arrosage", subtitle: "Accessoires utiles")
                    PartnerCategoryCard(systemImage: "scissors", title: "Entretien", subtitle: "Outils & soins")
                }
            }

            PartnerTrustCard()
        }
    }

    private func loadMapTextureKind() async {
        do {
            let garden = try await GardenAPI.shared.getGarden(id: gardenId)
            await MainActor.run {
                gardenDetails = garden
                currentGardenName = garden.name
                mapTextureKind = MapTextureKind(spaceType: garden.wizard.spaceType)
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
            renameError = "Impossible de renommer ce jardin."
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
                    Text("Marketplace partenaire")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ArboreDesign.Colors.accentGold)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    Text("Trouvez les plantes et accessoires adaptés à votre jardin")
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

            Text("Bientôt, les recommandations ouvriront directement le site de notre partenaire avec une sélection prête à acheter.")
                .font(ArboreDesign.Typography.bodySmall)
                .foregroundColor(.white.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)

            Button {
            } label: {
                HStack(spacing: ArboreDesign.Spacing.xs) {
                    Text("Voir la sélection partenaire")
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
                    Text("Mesurer votre espace")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("Délimitez les contours de votre jardin pour générer le plan 2D et afficher les bonnes dimensions.")
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(Color.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, ArboreDesign.Spacing.lg)
                }

                Button(action: onMeasure) {
                    HStack(spacing: ArboreDesign.Spacing.xs) {
                        Image(systemName: "camera.viewfinder")
                        Text("Mesurer l’espace")
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

private struct PurchaseRow: View {
    let item: PurchaseItem
    let primary: Color
    let onBuy: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                    .fill(ArboreDesign.Colors.softSurface)
                    .frame(width: 58, height: 58)
                if let icon = item.systemIcon {
                    Image(systemName: icon)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(primary)
                } else {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 21, weight: .semibold))
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
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(ArboreDesign.Colors.primaryButton)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ouvrir chez le partenaire")
        }
        .padding(ArboreDesign.Spacing.md)
        .background(CardContainer(cornerRadius: ArboreDesign.Radius.large))
        .shadow(color: ArboreDesign.Colors.shadow, radius: 10, x: 0, y: 4)
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
                        Text("Sélection pensée pour votre jardin")
                            .font(ArboreDesign.Typography.cardTitle)
                            .foregroundColor(ArboreDesign.Colors.textPrimary)

                        Text("Les produits affichés ici seront reliés à votre plan, vos plantes et vos besoins d’entretien.")
                            .font(ArboreDesign.Typography.bodySmall)
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()
                    .background(ArboreDesign.Colors.border)

                HStack(spacing: ArboreDesign.Spacing.sm) {
                    PartnerTrustPill(systemImage: "lock.fill", text: "Redirection sécurisée")
                    PartnerTrustPill(systemImage: "sparkles", text: "Recommandations Arbore")
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

private struct CareTaskCard: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let actionTitle: String
    let tint: Color
    @State private var isDone = false

    var body: some View {
        AppCard {
            HStack(alignment: .top, spacing: ArboreDesign.Spacing.md) {
                SettingsIconBadge(systemImage: isDone ? "checkmark" : systemImage, tint: isDone ? ArboreDesign.Colors.success : tint, size: 44)

                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
                    Text(title)
                        .font(ArboreDesign.Typography.cardTitle)
                        .foregroundColor(ArboreDesign.Colors.textPrimary)
                        .strikethrough(isDone, color: ArboreDesign.Colors.textSecondary)

                    Text(isDone ? "Terminé pour aujourd’hui" : subtitle)
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isDone.toggle()
                        }
                    } label: {
                        Text(isDone ? "Annuler" : actionTitle)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isDone ? ArboreDesign.Colors.textSecondary : ArboreDesign.Colors.primaryGreen)
                            .padding(.horizontal, ArboreDesign.Spacing.md)
                            .frame(height: 34)
                            .background(isDone ? ArboreDesign.Colors.softSurface.opacity(0.65) : ArboreDesign.Colors.softSurface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, ArboreDesign.Spacing.xs)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct CareWeekTimeline: View {
    private let days = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
    private let symbols = ["drop.fill", nil, "scissors", nil, "drop.fill", "sparkles", nil]

    var body: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
            SectionTitle(title: "Calendrier d’entretien")

            AppCard {
                HStack(spacing: ArboreDesign.Spacing.xs) {
                    ForEach(days.indices, id: \.self) { index in
                        VStack(spacing: ArboreDesign.Spacing.xs) {
                            Text(days[index])
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(ArboreDesign.Colors.textSecondary)

                            ZStack {
                                Circle()
                                    .fill(symbols[index] == nil ? ArboreDesign.Colors.softSurface.opacity(0.55) : ArboreDesign.Colors.softSurface)
                                    .frame(width: 34, height: 34)

                                if let symbol = symbols[index] {
                                    Image(systemName: symbol)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(symbol == "scissors" ? ArboreDesign.Colors.accentGold : ArboreDesign.Colors.primaryGreen)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
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
    let plantName: String

    var body: some View {
        AppCard {
            HStack(alignment: .top, spacing: ArboreDesign.Spacing.md) {
                SettingsIconBadge(systemImage: "sparkles", tint: ArboreDesign.Colors.accentGold, size: 44)

                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
                    Text("Conseil du jour")
                        .font(ArboreDesign.Typography.cardTitle)
                        .foregroundColor(ArboreDesign.Colors.textPrimary)

                    Text("Votre \(plantName) est placée en zone lumineuse. Évitez le soleil direct l’après-midi et gardez le sol légèrement humide.")
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
