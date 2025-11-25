//
//  InfoStepView.swift
//  ArboreUi
//
//  Created on November 25, 2025.
//

import SwiftUI

struct InfoStepView: View {
    let project: GardenProject
    @EnvironmentObject var projectService: GardenProjectService
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var isIndoor = false
    @State private var isOutdoor = true
    @State private var selectedSunExposure: GardenInfo.SunExposure = .partialSun
    @State private var selectedSoilType: GardenInfo.SoilType = .unknown
    @State private var hasWaterAccess = true
    @State private var hasAutomaticIrrigation = false
    
    var body: some View {
        VStack(spacing: 24) {
            // En-tête
            StepHeader(
                icon: "info.circle.fill",
                title: "Informations du jardin",
                description: "Décrivez les caractéristiques de votre espace"
            )
            
            // Type d'espace
            VStack(alignment: .leading, spacing: 12) {
                Label("Type d'espace", systemImage: "house.fill")
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                VStack(spacing: 12) {
                    ToggleOption(
                        title: "Intérieur",
                        icon: "house.fill",
                        description: "Appartement, maison, véranda...",
                        isOn: $isIndoor
                    )
                    
                    ToggleOption(
                        title: "Extérieur",
                        icon: "sun.max.fill",
                        description: "Jardin, terrasse, balcon...",
                        isOn: $isOutdoor
                    )
                }
            }
            
            // Ensoleillement
            VStack(alignment: .leading, spacing: 12) {
                Label("Ensoleillement", systemImage: "sun.max.fill")
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                Text("Combien d'heures de soleil direct par jour ?")
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
                
                VStack(spacing: 8) {
                    ForEach(GardenInfo.SunExposure.allCases, id: \.self) { exposure in
                        SelectableCard(
                            title: exposure.rawValue,
                            icon: sunIcon(for: exposure),
                            isSelected: selectedSunExposure == exposure,
                            action: { selectedSunExposure = exposure }
                        )
                    }
                }
            }
            
            // Type de sol (si extérieur)
            if isOutdoor {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Type de sol", systemImage: "leaf.fill")
                        .font(.headline)
                        .foregroundColor(themeManager.textColor)
                    
                    Text("Quel type de sol avez-vous ?")
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryTextColor)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(GardenInfo.SoilType.allCases, id: \.self) { soilType in
                                SoilTypeChip(
                                    type: soilType,
                                    isSelected: selectedSoilType == soilType,
                                    action: { selectedSoilType = soilType }
                                )
                            }
                        }
                    }
                }
            }
            
            // Accès à l'eau
            VStack(alignment: .leading, spacing: 12) {
                Label("Irrigation", systemImage: "drop.fill")
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                VStack(spacing: 12) {
                    ToggleOption(
                        title: "Accès à l'eau",
                        icon: "drop.fill",
                        description: "Robinet ou arrosoir à proximité",
                        isOn: $hasWaterAccess
                    )
                    
                    ToggleOption(
                        title: "Irrigation automatique",
                        icon: "sprinkler.fill",
                        description: "Système d'arrosage automatique",
                        isOn: $hasAutomaticIrrigation
                    )
                }
            }
            
            // Bouton sauvegarder
            Button(action: saveInfo) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Sauvegarder les informations")
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
            
            Spacer()
        }
        .onAppear {
            loadExistingInfo()
        }
    }
    
    // MARK: - Helper Methods
    private func sunIcon(for exposure: GardenInfo.SunExposure) -> String {
        switch exposure {
        case .fullSun: return "sun.max.fill"
        case .partialSun: return "cloud.sun.fill"
        case .shade: return "cloud.fill"
        case .mixed: return "sun.haze.fill"
        }
    }
    
    private func loadExistingInfo() {
        if let info = project.gardenInfo {
            isIndoor = info.isIndoor
            isOutdoor = info.isOutdoor
            selectedSunExposure = info.sunExposure
            selectedSoilType = info.soilType ?? .unknown
            hasWaterAccess = info.hasWaterAccess
            hasAutomaticIrrigation = info.hasAutomaticIrrigation
        }
    }
    
    private func saveInfo() {
        let info = GardenInfo(
            isIndoor: isIndoor,
            isOutdoor: isOutdoor,
            sunExposure: selectedSunExposure,
            soilType: isOutdoor ? selectedSoilType : nil,
            hasWaterAccess: hasWaterAccess,
            hasAutomaticIrrigation: hasAutomaticIrrigation
        )
        
        projectService.saveGardenInfo(for: project.id, info: info)
    }
}

// MARK: - Toggle Option
struct ToggleOption: View {
    let title: String
    let icon: String
    let description: String
    @Binding var isOn: Bool
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(isOn ? .green : .gray)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.textColor)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.green)
        }
        .padding()
        .background(themeManager.cardBackgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Selectable Card
struct SelectableCard: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(isSelected ? .white : themeManager.textColor)
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(isSelected ? .white : themeManager.textColor)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(isSelected ? Color.green : themeManager.cardBackgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

// MARK: - Soil Type Chip
struct SoilTypeChip: View {
    let type: GardenInfo.SoilType
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Button(action: action) {
            Text(type.rawValue)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : themeManager.textColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? Color.green : themeManager.cardBackgroundColor)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? Color.clear : Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
    }
}

#Preview {
    InfoStepView(project: GardenProject(name: "Test"))
        .environmentObject(GardenProjectService())
        .environmentObject(ThemeManager())
}
