//
//  ZonesStepView.swift
//  ArboreUi
//
//  Created on November 25, 2025.
//

import SwiftUI

struct ZonesStepView: View {
    let project: GardenProject
    @EnvironmentObject var projectService: GardenProjectService
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var showingDrawingView = false
    @State private var selectedZone: PlantingZone?
    @State private var showingZoneEditor = false
    
    var body: some View {
        VStack(spacing: 24) {
            // En-tête
            StepHeader(
                icon: "map.fill",
                title: "Zones de plantation",
                description: "Dessinez sur le scan les endroits où vous souhaitez placer des plantes"
            )
            
            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                Label("Comment ça marche ?", systemImage: "questionmark.circle.fill")
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                VStack(spacing: 8) {
                    InstructionRow(
                        number: 1,
                        text: "Ouvrez le scan de votre espace"
                    )
                    
                    InstructionRow(
                        number: 2,
                        text: "Dessinez les zones avec votre doigt"
                    )
                    
                    InstructionRow(
                        number: 3,
                        text: "Définissez le type de plantes pour chaque zone"
                    )
                    
                    InstructionRow(
                        number: 4,
                        text: "L'IA suggérera les meilleures plantes"
                    )
                }
            }
            .padding()
            .background(Color.purple.opacity(0.1))
            .cornerRadius(12)
            
            // Zones existantes
            if !project.plantingZones.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Zones définies (\(project.plantingZones.count))")
                            .font(.headline)
                            .foregroundColor(themeManager.textColor)
                        
                        Spacer()
                        
                        Button(action: {
                            showingDrawingView = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Ajouter")
                            }
                            .font(.caption)
                            .foregroundColor(.green)
                        }
                    }
                    
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(project.plantingZones) { zone in
                                ZoneCard(zone: zone, onTap: {
                                    selectedZone = zone
                                    showingZoneEditor = true
                                }, onDelete: {
                                    projectService.removePlantingZone(from: project.id, zoneId: zone.id)
                                })
                            }
                        }
                    }
                }
            } else {
                // Bouton pour commencer à dessiner
                Button(action: {
                    if project.scanData != nil {
                        showingDrawingView = true
                    }
                }) {
                    VStack(spacing: 16) {
                        Image(systemName: "pencil.and.scribble")
                            .font(.system(size: 50))
                            .foregroundColor(project.scanData != nil ? .purple : .gray)
                        
                        Text(project.scanData != nil ? "Dessiner les zones" : "Scan requis")
                            .font(.headline)
                            .foregroundColor(themeManager.textColor)
                        
                        Text(project.scanData != nil ?
                             "Commencez à dessiner les zones où vous voulez planter" :
                             "Vous devez d'abord scanner votre espace")
                            .font(.caption)
                            .foregroundColor(themeManager.secondaryTextColor)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(themeManager.cardBackgroundColor)
                    .cornerRadius(12)
                }
                .disabled(project.scanData == nil)
            }
            
            // Conseils
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    
                    Text("Conseils")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(themeManager.textColor)
                }
                
                Text("• Créez plusieurs zones pour varier les types de plantes\n• Pensez à l'ensoleillement de chaque zone\n• Gardez de l'espace pour circuler")
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
            }
            .padding()
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
        }
        .sheet(isPresented: $showingDrawingView) {
            DrawingCanvasView(project: project, onSave: { zone in
                projectService.addPlantingZone(to: project.id, zone: zone)
            })
            .environmentObject(themeManager)
        }
        .sheet(item: $selectedZone) { zone in
            ZoneEditorSheet(project: project, zone: zone)
                .environmentObject(projectService)
                .environmentObject(themeManager)
        }
    }
}

// MARK: - Zone Card
struct ZoneCard: View {
    let zone: PlantingZone
    let onTap: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icône de la zone
                ZStack {
                    Circle()
                        .fill(zoneColor.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: zone.plantType != nil ? plantTypeIcon : "map.fill")
                        .foregroundColor(zoneColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(zone.name)
                        .font(.headline)
                        .foregroundColor(themeManager.textColor)
                    
                    if let plantType = zone.plantType {
                        Text(plantType.rawValue)
                            .font(.caption)
                            .foregroundColor(themeManager.secondaryTextColor)
                    } else {
                        Text("Type non défini")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    if zone.area > 0 {
                        Text("~\(Int(zone.area)) m²")
                            .font(.caption2)
                            .foregroundColor(themeManager.secondaryTextColor)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
            .background(themeManager.cardBackgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(zoneColor.opacity(0.3), lineWidth: 2)
            )
        }
    }
    
    private var zoneColor: Color {
        guard let plantType = zone.plantType else { return .gray }
        
        switch plantType {
        case .flowers: return .pink
        case .shrubs: return .green
        case .trees: return .brown
        case .vegetables: return .orange
        case .herbs: return .mint
        case .succulents: return .teal
        case .grasses: return .yellow
        case .climbers: return .purple
        }
    }
    
    private var plantTypeIcon: String {
        guard let plantType = zone.plantType else { return "map.fill" }
        
        switch plantType {
        case .flowers: return "aqi.high"
        case .shrubs: return "leaf.fill"
        case .trees: return "tree.fill"
        case .vegetables: return "carrot.fill"
        case .herbs: return "leaf.arrow.circlepath"
        case .succulents: return "cloud.drizzle.fill"
        case .grasses: return "wind"
        case .climbers: return "arrow.up.right"
        }
    }
}

// MARK: - Drawing Canvas View
struct DrawingCanvasView: View {
    let project: GardenProject
    let onSave: (PlantingZone) -> Void
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var drawnZones: [DrawnZone] = []
    @State private var currentPoints: [CGPoint] = []
    @State private var isDrawing = false
    @State private var selectedColor: Color = .green
    @State private var zoneName = ""
    @State private var showingNameAlert = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Toujours utiliser TopDownView pour le dessin
                TopDownView(
                    drawnZones: $drawnZones,
                    currentPoints: $currentPoints,
                    isDrawing: $isDrawing,
                    selectedColor: selectedColor
                )
                
                // Badge d'info du scan en haut
                if let scanData = project.scanData {
                    VStack {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("📐 \(scanData.scanType.rawValue)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text("Surface: ~\(Int(scanData.area)) m²")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.green.opacity(0.8))
                            )
                            
                            Spacer()
                        }
                        .padding()
                        
                        Spacer()
                    }
                }
                
                // Instructions
                if drawnZones.isEmpty && !isDrawing {
                    VStack {
                        Spacer()
                        Text("✏️ Dessinez avec votre doigt pour créer une zone")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.black.opacity(0.75))
                            )
                        Spacer()
                    }
                }
                
                // Contrôles de dessin en bas
                VStack {
                    Spacer()
                    
                    HStack(spacing: 10) {
                        // Palette de couleurs
                        ForEach([Color.green, .blue, .orange, .purple, .pink, .red, .yellow, .cyan], id: \.self) { color in
                            Button(action: {
                                selectedColor = color
                            }) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white, lineWidth: selectedColor == color ? 4 : 0)
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 3)
                            }
                        }
                        
                        Spacer()
                        
                        // Bouton Annuler
                        if !drawnZones.isEmpty {
                            Button(action: {
                                drawnZones.removeLast()
                            }) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.title3)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.orange)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 3)
                            }
                        }
                        
                        // Bouton Effacer tout
                        if !drawnZones.isEmpty {
                            Button(action: {
                                drawnZones.removeAll()
                            }) {
                                Image(systemName: "trash")
                                    .font(.title3)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 3)
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.8))
                            .shadow(color: .black.opacity(0.4), radius: 10)
                    )
                    .padding()
                }
            }
            .navigationTitle("Dessiner les zones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Valider") {
                        if !drawnZones.isEmpty {
                            showingNameAlert = true
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(drawnZones.isEmpty)
                }
            }
            .alert("Nom de la zone", isPresented: $showingNameAlert) {
                TextField("Ex: Parterre principal...", text: $zoneName)
                Button("Annuler", role: .cancel) { }
                Button("Créer") {
                    if !zoneName.isEmpty && !drawnZones.isEmpty {
                        if let lastZone = drawnZones.last {
                            let zone = PlantingZone(
                                name: zoneName,
                                drawnPath: lastZone.points
                            )
                            onSave(zone)
                            drawnZones.removeLast()
                            zoneName = ""
                            if drawnZones.isEmpty {
                                dismiss()
                            }
                        }
                    }
                }
            } message: {
                Text("Donnez un nom à la zone que vous venez de dessiner")
            }
        }
    }
}

// MARK: - Zone Editor Sheet
struct ZoneEditorSheet: View {
    let project: GardenProject
    @State var zone: PlantingZone
    
    @EnvironmentObject var projectService: GardenProjectService
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Informations") {
                    TextField("Nom de la zone", text: $zone.name)
                    
                    Picker("Type de plantes", selection: $zone.plantType) {
                        Text("Non défini").tag(nil as GardenPreferences.PlantType?)
                        ForEach(GardenPreferences.PlantType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type as GardenPreferences.PlantType?)
                        }
                    }
                }
                
                Section("Notes") {
                    TextEditor(text: Binding(
                        get: { zone.notes ?? "" },
                        set: { zone.notes = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(height: 100)
                }
                
                if !zone.suggestedPlants.isEmpty {
                    Section("Plantes suggérées par l'IA") {
                        ForEach(zone.suggestedPlants, id: \.self) { plantId in
                            Text(plantId)
                        }
                    }
                }
            }
            .navigationTitle("Modifier la zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Enregistrer") {
                        projectService.updatePlantingZone(in: project.id, zone: zone)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    ZonesStepView(project: GardenProject(name: "Test"))
        .environmentObject(GardenProjectService())
        .environmentObject(ThemeManager())
}
