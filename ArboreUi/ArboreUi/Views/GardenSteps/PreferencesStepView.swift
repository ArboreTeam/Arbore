//
//  PreferencesStepView.swift
//  ArboreUi
//
//  Created on November 25, 2025.
//

import SwiftUI

struct PreferencesStepView: View {
    let project: GardenProject
    @EnvironmentObject var projectService: GardenProjectService
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var selectedPlantTypes: Set<GardenPreferences.PlantType> = []
    @State private var selectedStyle: GardenPreferences.GardenStyle = .modern
    @State private var densityLevel: GardenPreferences.DensityLevel = .moderate
    @State private var maintenanceLevel: GardenPreferences.MaintenanceLevel = .low
    @State private var complexityLevel: GardenPreferences.ComplexityLevel = .beginner
    @State private var budget: GardenPreferences.BudgetRange = .medium
    @State private var hasChildren = false
    @State private var hasPets = false
    @State private var wantsEdiblePlants = false
    @State private var wantsFlowers = true
    @State private var wantsEvergreen = false
    
    var body: some View {
        VStack(spacing: 24) {
            // En-tête
            StepHeader(
                icon: "slider.horizontal.3",
                title: "Vos préférences",
                description: "Personnalisez votre jardin selon vos goûts et contraintes"
            )
            
            ScrollView {
                VStack(spacing: 24) {
                    // Types de plantes
                    PreferenceSection(title: "Types de plantes souhaités", icon: "leaf.fill") {
                        FlowLayout(spacing: 8) {
                            ForEach(GardenPreferences.PlantType.allCases, id: \.self) { type in
                                MultiSelectChip(
                                    title: type.rawValue,
                                    isSelected: selectedPlantTypes.contains(type),
                                    action: {
                                        if selectedPlantTypes.contains(type) {
                                            selectedPlantTypes.remove(type)
                                        } else {
                                            selectedPlantTypes.insert(type)
                                        }
                                    }
                                )
                            }
                        }
                    }
                    
                    // Style de jardin
                    PreferenceSection(title: "Style de jardin", icon: "paintbrush.fill") {
                        VStack(spacing: 8) {
                            ForEach(GardenPreferences.GardenStyle.allCases, id: \.self) { style in
                                SelectableCard(
                                    title: style.rawValue,
                                    icon: styleIcon(for: style),
                                    isSelected: selectedStyle == style,
                                    action: { selectedStyle = style }
                                )
                            }
                        }
                    }
                    
                    // Densité
                    PreferenceSection(title: "Organisation", icon: "square.grid.3x3.fill") {
                        VStack(spacing: 8) {
                            ForEach(GardenPreferences.DensityLevel.allCases, id: \.self) { density in
                                SelectableCard(
                                    title: density.rawValue,
                                    icon: densityIcon(for: density),
                                    isSelected: densityLevel == density,
                                    action: { densityLevel = density }
                                )
                            }
                        }
                    }
                    
                    // Entretien
                    PreferenceSection(title: "Facilité d'entretien", icon: "wrench.fill") {
                        VStack(spacing: 8) {
                            ForEach(GardenPreferences.MaintenanceLevel.allCases, id: \.self) { maintenance in
                                MaintenanceCard(
                                    level: maintenance,
                                    isSelected: maintenanceLevel == maintenance,
                                    action: { maintenanceLevel = maintenance }
                                )
                            }
                        }
                    }
                    
                    // Complexité
                    PreferenceSection(title: "Complexité des plantes", icon: "chart.bar.fill") {
                        VStack(spacing: 8) {
                            ForEach(GardenPreferences.ComplexityLevel.allCases, id: \.self) { complexity in
                                SelectableCard(
                                    title: complexity.rawValue,
                                    icon: complexityIcon(for: complexity),
                                    isSelected: complexityLevel == complexity,
                                    action: { complexityLevel = complexity }
                                )
                            }
                        }
                    }
                    
                    // Budget
                    PreferenceSection(title: "Budget", icon: "banknote.fill") {
                        VStack(spacing: 8) {
                            ForEach(GardenPreferences.BudgetRange.allCases, id: \.self) { budgetRange in
                                SelectableCard(
                                    title: budgetRange.rawValue,
                                    icon: "eurosign.circle.fill",
                                    isSelected: budget == budgetRange,
                                    action: { budget = budgetRange }
                                )
                            }
                        }
                    }
                    
                    // Options supplémentaires
                    PreferenceSection(title: "Options supplémentaires", icon: "star.fill") {
                        VStack(spacing: 12) {
                            ToggleOption(
                                title: "J'ai des enfants",
                                icon: "figure.2.and.child.holdinghands",
                                description: "Plantes non toxiques prioritaires",
                                isOn: $hasChildren
                            )
                            
                            ToggleOption(
                                title: "J'ai des animaux",
                                icon: "pawprint.fill",
                                description: "Plantes sans danger pour les animaux",
                                isOn: $hasPets
                            )
                            
                            ToggleOption(
                                title: "Plantes comestibles",
                                icon: "carrot.fill",
                                description: "Fruits, légumes, herbes aromatiques",
                                isOn: $wantsEdiblePlants
                            )
                            
                            ToggleOption(
                                title: "Plantes à fleurs",
                                icon: "aqi.high",
                                description: "Pour un jardin coloré et vivant",
                                isOn: $wantsFlowers
                            )
                            
                            ToggleOption(
                                title: "Plantes persistantes",
                                icon: "tree.fill",
                                description: "Verdure toute l'année",
                                isOn: $wantsEvergreen
                            )
                        }
                    }
                    
                    // Bouton sauvegarder
                    Button(action: savePreferences) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Sauvegarder mes préférences")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.green, .green.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            loadExistingPreferences()
        }
    }
    
    // MARK: - Helper Methods
    private func styleIcon(for style: GardenPreferences.GardenStyle) -> String {
        switch style {
        case .modern: return "square.stack.3d.up.fill"
        case .traditional: return "house.fill"
        case .japanese: return "moon.fill"
        case .mediterranean: return "sun.max.fill"
        case .cottage: return "leaf.fill"
        case .tropical: return "palm.tree"
        case .minimalist: return "square.fill"
        case .wild: return "tree.fill"
        }
    }
    
    private func densityIcon(for density: GardenPreferences.DensityLevel) -> String {
        switch density {
        case .sparse: return "circle.grid.2x1.fill"
        case .moderate: return "circle.grid.3x3.fill"
        case .dense: return "square.grid.3x3.fill"
        }
    }
    
    private func complexityIcon(for complexity: GardenPreferences.ComplexityLevel) -> String {
        switch complexity {
        case .beginner: return "star.fill"
        case .intermediate: return "star.leadinghalf.filled"
        case .advanced: return "sparkles"
        case .mixed: return "star.circle.fill"
        }
    }
    
    private func loadExistingPreferences() {
        if let prefs = project.preferences {
            selectedPlantTypes = Set(prefs.plantTypes)
            selectedStyle = prefs.gardenStyle
            densityLevel = prefs.densityLevel
            maintenanceLevel = prefs.maintenanceLevel
            complexityLevel = prefs.plantComplexity
            budget = prefs.budget ?? .medium
            hasChildren = prefs.hasChildren
            hasPets = prefs.hasPets
            wantsEdiblePlants = prefs.wantsEdiblePlants
            wantsFlowers = prefs.wantsFlowers
            wantsEvergreen = prefs.wantsEvergreen
        }
    }
    
    private func savePreferences() {
        let preferences = GardenPreferences(
            plantTypes: Array(selectedPlantTypes),
            gardenStyle: selectedStyle,
            densityLevel: densityLevel,
            maintenanceLevel: maintenanceLevel,
            plantComplexity: complexityLevel,
            budget: budget,
            colorPreferences: [],
            hasChildren: hasChildren,
            hasPets: hasPets,
            wantsEdiblePlants: wantsEdiblePlants,
            wantsFlowers: wantsFlowers,
            wantsEvergreen: wantsEvergreen
        )
        
        projectService.savePreferences(for: project.id, preferences: preferences)
    }
}

// MARK: - Preference Section
struct PreferenceSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(themeManager.textColor)
            
            content
        }
        .padding()
        .background(themeManager.cardBackgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Multi Select Chip
struct MultiSelectChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
                Text(title)
                    .font(.caption)
            }
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundColor(isSelected ? .white : themeManager.textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.green : Color.gray.opacity(0.2))
            .cornerRadius(16)
        }
    }
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                     y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var positions: [CGPoint] = []
        var height: CGFloat = 0
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            height = y + lineHeight
        }
    }
}

// MARK: - Maintenance Card
struct MaintenanceCard: View {
    let level: GardenPreferences.MaintenanceLevel
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    var color: Color {
        switch level {
        case .veryLow: return .green
        case .low: return .blue
        case .moderate: return .orange
        case .high: return .red
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "drop.fill")
                    .foregroundColor(isSelected ? .white : color)
                
                Text(level.rawValue)
                    .font(.subheadline)
                    .foregroundColor(isSelected ? .white : themeManager.textColor)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(isSelected ? color : themeManager.cardBackgroundColor.opacity(0.5))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : color.opacity(0.3), lineWidth: 2)
            )
        }
    }
}

#Preview {
    PreferencesStepView(project: GardenProject(name: "Test"))
        .environmentObject(GardenProjectService())
        .environmentObject(ThemeManager())
}
