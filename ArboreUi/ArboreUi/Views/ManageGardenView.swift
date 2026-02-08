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
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.backgroundColor.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Text("Mes Jardins")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.black)
                        Spacer()
                        Button(action: { showingNewProjectSheet = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(themeManager.accentColor)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    
                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        TextField("Rechercher...", text: $searchText)
                    }
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 5)
                    .padding(.horizontal)
                    
                    // Liste
                    ScrollView {
                        if projectService.projects.isEmpty {
                            VStack(spacing: 20) {
                                Spacer(minLength: 50)
                                Image(systemName: "camera.macro")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray.opacity(0.5))
                                Text("Aucun jardin détecté")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                Text("Créez un jardin en AR pour le voir ici.")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        } else {
                            LazyVStack(spacing: 15) {
                                ForEach(projectService.projects) { garden in
                                    // Navigation vers la page détaillée fusionnée
                                    NavigationLink(destination: GardenDetailsPage(gardenId: garden.id, gardenName: garden.name)) {
                                        GardenProjectCard(garden: garden, accentColor: themeManager.accentColor)
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingNewProjectSheet) {
                Text("Nouveau projet (Wizard)")
            }
            .onAppear {
                projectService.refreshProjects()
            }
        }
    }
}

// MARK: - 4. COMPOSANT CARTE PROJET (Liste)
struct GardenProjectCard: View {
    let garden: GardenModel
    let accentColor: Color
    
    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 70, height: 70)
                Image(systemName: garden.thumbnail)
                    .font(.title)
                    .foregroundColor(accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(garden.name)
                    .font(.headline)
                    .foregroundColor(.black)
                Text("Modifié: \(garden.lastModified.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.gray.opacity(0.5))
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 5. VUE DÉTAIL FUSIONNÉE (Tabs + Map + Purchase)
struct GardenDetailsPage: View {
    let gardenId: String
    let gardenName: String
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    
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
    
    private let primary = Color(red: 0.05, green: 0.95, blue: 0.27) // #0df246
    private var isDark: Bool { colorScheme == .dark }
    
    // Données Mock pour la liste d'achats
    @State private var purchaseItems: [PurchaseItem] = [
        .init(name: "Monstera Deliciosa", subtitle: "Garden Center • In Stock", priceRange: "$25 - $40", imageName: "monstera", systemIcon: nil, priority: 1),
        .init(name: "Snake Plant", subtitle: "Home Depot", priceRange: "$15 - $30", imageName: nil, systemIcon: "leaf.fill", priority: 2),
        .init(name: "Organic Potting Mix", subtitle: "Any Garden Center", priceRange: "$8 - $12", imageName: nil, systemIcon: "bag.fill", priority: 2)
    ]
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            themeManager.backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header (Back button + Title)
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "arrow.left")
                            .foregroundColor(.black)
                            .padding(10)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                    }
                    Spacer()
                    Text(gardenName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    // Bouton invisible pour équilibrer
                    Image(systemName: "arrow.left").opacity(0).padding(10)
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
                
                // Tabs Bar (Ton style)
                HStack(spacing: 0) {
                    tabButton(.plan2D)
                    tabButton(.tasks)
                    tabButton(.purchase)
                }
                .padding(.horizontal, 16)
                
                // Contenu
                ScrollView {
                    VStack(spacing: 12) {
                        
                        switch selectedTab {
                        case .plan2D:
                            // --- LA CARTE 2D ---
                            VStack(alignment: .leading) {
                                Text("VUE DU JARDIN")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 16)
                                
                                GardenPlanInteractiveMap(viewModel: mapViewModel)
                                    .frame(height: 450)
                                    .cornerRadius(24)
                                    .shadow(radius: 5)
                                
                                // Info sélection plante
                                if let selected = mapViewModel.selectedPlant {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(Color.green.opacity(0.1))
                                                .frame(width: 64, height: 64)
                                            Image(systemName: "leaf.fill")
                                                .font(.system(size: 24))
                                                .foregroundColor(.green)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(selected.data.plantName)
                                                .font(.system(size: 16, weight: .semibold))
                                            Text("X: \(String(format: "%.2f", selected.data.position[0]))m, Z: \(String(format: "%.2f", selected.data.position[2]))m")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(14)
                                    .background(CardContainer(isDark: isDark, cornerRadius: 18))
                                    .padding(.top, 10)
                                } else {
                                    Text("\(mapViewModel.displayPlants.count) plantes détectées. Touchez pour voir.")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding(.top, 8)
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
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96) // Espace pour le FAB
                }
            }
            
            // FAB (Floating Action Button)
            Button {
                // Action ajouter
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isDark ? Color.black : Color.white)
                    .frame(width: 56, height: 56)
                    .background(isDark ? Color.white : Color.black)
                    .clipShape(Circle())
                    .shadow(radius: 10, x: 0, y: 6)
            }
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
        .navigationBarHidden(true)
        .onAppear {
            mapViewModel.loadGarden(gardenId: gardenId)
        }
    }
    
    // MARK: - Subviews UI
    
    private func tabButton(_ tab: Tab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 10) {
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: tab == selectedTab ? .bold : .semibold))
                    .foregroundStyle(tab == selectedTab ? themeManager.textColor : .secondary)
                
                Rectangle()
                    .fill(tab == selectedTab ? primary : .clear)
                    .frame(height: 3)
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
    }
    
    private var sectionHeader: some View {
        HStack {
            Text("TO BUY (\(purchaseItems.count))")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1.1)
            Spacer()
            Button { sortByPriority.toggle() } label: {
                Text("Sort by Priority")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(primary)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var purchaseList: some View {
        VStack(spacing: 12) {
            ForEach(purchaseItems) { item in
                PurchaseRow(item: item, primary: primary, isDark: isDark) {}
            }
        }
    }
    
    private func placeholder(title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 18, weight: .bold))
            Text(subtitle).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(CardContainer(isDark: isDark, cornerRadius: 16))
    }
}

// MARK: - 6. SUBVIEWS & HELPERS

private struct PurchaseRow: View {
    let item: PurchaseItem
    let primary: Color
    let isDark: Bool
    let onBuy: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    .frame(width: 64, height: 64)
                if let icon = item.systemIcon {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(primary.opacity(0.6))
                } else {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(primary.opacity(0.6))
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(item.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(item.priceRange)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(primary)
            }
            Spacer()
            Button(action: onBuy) {
                Text("Buy")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.06, green: 0.13, blue: 0.08))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(14)
        .background(CardContainer(isDark: isDark, cornerRadius: 18))
        .shadow(color: isDark ? Color.black.opacity(0.22) : Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

private struct CardContainer: View {
    let isDark: Bool
    let cornerRadius: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(isDark ? Color.white.opacity(0.06) : Color.white)
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.04), lineWidth: 1))
    }
}

// MARK: - 7. LOGIQUE MAP 2D & CARTE INTERACTIVE

class Garden2DViewModel: ObservableObject {
    @Published var displayPlants: [DisplayPlant] = []
    @Published var selectedPlant: DisplayPlant? = nil
    
    func loadGarden(gardenId: String) {
        let url = GardenLocalStore.sceneURL(for: gardenId)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let scene = try JSONDecoder().decode(PersistedARScene.self, from: data)
                DispatchQueue.main.async {
                    self.displayPlants = scene.plants.map { DisplayPlant(data: $0) }
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
                Color(red: 26/255, green: 37/255, blue: 21/255)
                GridPattern(spacing: scale)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    .offset(x: offset.width, y: offset.height)
                
                ZStack {
                    Circle().fill(Color.white.opacity(0.2)).frame(width: 8, height: 8)
                    ForEach(viewModel.displayPlants) { plantWrapper in
                        let p = plantWrapper.data
                        let x = CGFloat(p.position[0]) * scale
                        let y = CGFloat(p.position[2]) * scale
                        
                        VStack(spacing: 0) {
                            ZStack {
                                if viewModel.selectedPlant?.id == plantWrapper.id {
                                    Circle().stroke(Color.white, lineWidth: 2)
                                        .frame(width: 36, height: 36)
                                        .background(Circle().fill(Color.white.opacity(0.2)))
                                }
                                Circle().fill(Color(red: 43/255, green: 238/255, blue: 121/255))
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
                        .offset(x: x, y: y)
                        .onTapGesture { withAnimation { viewModel.selectedPlant = plantWrapper } }
                    }
                }
                .offset(x: geo.size.width / 2 + offset.width, y: geo.size.height / 2 + offset.height)
                
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
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .contentShape(Rectangle())
            .gesture(DragGesture().onChanged { val in offset = CGSize(width: lastOffset.width + val.translation.width, height: lastOffset.height + val.translation.height) }.onEnded { _ in lastOffset = offset })
            .gesture(MagnificationGesture().onChanged { val in scale = lastScale * val }.onEnded { _ in lastScale = scale })
            .onChange(of: viewModel.displayPlants.count) { _ in DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation { fitContent(geo: geo) } } }
        }
    }
    
    private func fitContent(geo: GeometryProxy) {
        guard !viewModel.displayPlants.isEmpty else { return }
        let positionsX = viewModel.displayPlants.map { CGFloat($0.data.position[0]) }
        let positionsY = viewModel.displayPlants.map { CGFloat($0.data.position[2]) }
        let minX = positionsX.min() ?? 0
        let maxX = positionsX.max() ?? 0
        let minY = positionsY.min() ?? 0
        let maxY = positionsY.max() ?? 0
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let spanX = max(maxX - minX, 1.0)
        let spanY = max(maxY - minY, 1.0)
        let scaleX = (geo.size.width - 100) / spanX
        let scaleY = (geo.size.height - 100) / spanY
        let newScale = min(scaleX, scaleY, 150.0)
        self.scale = newScale
        self.lastScale = newScale
        self.offset = CGSize(width: -centerX * newScale, height: -centerY * newScale)
        self.lastOffset = self.offset
    }
}

// Helpers
struct IconBtn: View {
    let icon: String
    var body: some View {
        Image(systemName: icon).foregroundColor(.white).padding(10).background(.ultraThinMaterial).clipShape(Circle()).shadow(radius: 2)
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

#Preview {
    ManageGardenView()
        .environmentObject(ThemeManager())
}
