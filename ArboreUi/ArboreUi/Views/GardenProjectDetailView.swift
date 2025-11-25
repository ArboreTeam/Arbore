//
//  GardenProjectDetailView.swift
//  ArboreUi
//
//  Created on November 25, 2025.
//

import SwiftUI

struct GardenProjectDetailView: View {
    let project: GardenProject
    @EnvironmentObject var projectService: GardenProjectService
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    
    @State private var currentStep: ProjectStep = .scan
    @State private var showingDeleteAlert = false
    
    enum ProjectStep: Int, CaseIterable {
        case scan = 0
        case media = 1
        case info = 2
        case location = 3
        case preferences = 4
        case zones = 5
        case summary = 6
        
        var title: String {
            switch self {
            case .scan: return "Scan du jardin"
            case .media: return "Photos & Vidéos"
            case .info: return "Informations"
            case .location: return "Localisation"
            case .preferences: return "Préférences"
            case .zones: return "Zones de plantation"
            case .summary: return "Résumé"
            }
        }
        
        var icon: String {
            switch self {
            case .scan: return "viewfinder.circle.fill"
            case .media: return "photo.on.rectangle.angled"
            case .info: return "info.circle.fill"
            case .location: return "location.fill"
            case .preferences: return "slider.horizontal.3"
            case .zones: return "map.fill"
            case .summary: return "checkmark.seal.fill"
            }
        }
        
        var description: String {
            switch self {
            case .scan: return "Scannez votre espace avec l'appareil photo"
            case .media: return "Ajoutez des photos et vidéos de votre espace"
            case .info: return "Décrivez votre jardin (intérieur/extérieur, ensoleillement...)"
            case .location: return "Partagez votre localisation pour le climat"
            case .preferences: return "Définissez vos préférences de style et entretien"
            case .zones: return "Dessinez les zones où planter"
            case .summary: return "Vérifiez et envoyez à l'IA"
            }
        }
    }
    
    var body: some View {
        ZStack {
            themeManager.backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header avec progression
                headerSection
                
                // Stepper horizontal
                stepperSection
                
                // Contenu de l'étape actuelle
                ScrollView {
                    VStack(spacing: 20) {
                        currentStepView
                    }
                    .padding()
                }
                
                // Boutons de navigation
                navigationButtons
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { /* Partager */ }) {
                        Label("Partager", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(role: .destructive, action: {
                        showingDeleteAlert = true
                    }) {
                        Label("Supprimer", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(themeManager.textColor)
                }
            }
        }
        .alert("Supprimer le projet", isPresented: $showingDeleteAlert) {
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                projectService.deleteProject(project)
                dismiss()
            }
        } message: {
            Text("Êtes-vous sûr de vouloir supprimer ce projet ? Cette action est irréversible.")
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(themeManager.textColor)
                    
                    Text("Étape \(currentStep.rawValue + 1) sur \(ProjectStep.allCases.count)")
                        .font(.subheadline)
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                
                Spacer()
                
                StatusBadge(status: project.status)
            }
            
            // Barre de progression globale
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.green, .green.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * (project.completionPercentage / 100), height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
        }
        .padding()
        .background(themeManager.cardBackgroundColor)
    }
    
    // MARK: - Stepper
    private var stepperSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ProjectStep.allCases, id: \.self) { step in
                    StepButton(
                        step: step,
                        isActive: currentStep == step,
                        isCompleted: isStepCompleted(step),
                        action: { currentStep = step }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(themeManager.backgroundColor)
    }
    
    // MARK: - Current Step View
    @ViewBuilder
    private var currentStepView: some View {
        switch currentStep {
        case .scan:
            ScanStepView(project: project)
                .environmentObject(projectService)
                .environmentObject(themeManager)
        case .media:
            MediaStepView(project: project)
                .environmentObject(projectService)
                .environmentObject(themeManager)
        case .info:
            InfoStepView(project: project)
                .environmentObject(projectService)
                .environmentObject(themeManager)
        case .location:
            LocationStepView(project: project)
                .environmentObject(projectService)
                .environmentObject(themeManager)
        case .preferences:
            PreferencesStepView(project: project)
                .environmentObject(projectService)
                .environmentObject(themeManager)
        case .zones:
            ZonesStepView(project: project)
                .environmentObject(projectService)
                .environmentObject(themeManager)
        case .summary:
            SummaryStepView(project: project)
                .environmentObject(projectService)
                .environmentObject(themeManager)
        }
    }
    
    // MARK: - Navigation Buttons
    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentStep.rawValue > 0 {
                Button(action: previousStep) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Précédent")
                    }
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(12)
                }
            }
            
            if currentStep.rawValue < ProjectStep.allCases.count - 1 {
                Button(action: nextStep) {
                    HStack {
                        Text("Suivant")
                        Image(systemName: "chevron.right")
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
            } else {
                Button(action: submitProject) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Analyser avec l'IA")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(themeManager.cardBackgroundColor)
    }
    
    // MARK: - Helper Methods
    private func isStepCompleted(_ step: ProjectStep) -> Bool {
        switch step {
        case .scan: return project.scanData != nil
        case .media: return !project.mediaFiles.isEmpty
        case .info: return project.gardenInfo != nil
        case .location: return project.location != nil
        case .preferences: return project.preferences != nil
        case .zones: return !project.plantingZones.isEmpty
        case .summary: return project.status == .completed || project.status == .ready
        }
    }
    
    private func nextStep() {
        if currentStep.rawValue < ProjectStep.allCases.count - 1 {
            withAnimation {
                currentStep = ProjectStep(rawValue: currentStep.rawValue + 1) ?? currentStep
            }
        }
    }
    
    private func previousStep() {
        if currentStep.rawValue > 0 {
            withAnimation {
                currentStep = ProjectStep(rawValue: currentStep.rawValue - 1) ?? currentStep
            }
        }
    }
    
    private func submitProject() {
        projectService.submitForAIAnalysis(projectId: project.id)
    }
}

// MARK: - Step Button
struct StepButton: View {
    let step: GardenProjectDetailView.ProjectStep
    let isActive: Bool
    let isCompleted: Bool
    let action: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(backgroundColor)
                        .frame(width: 50, height: 50)
                    
                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: step.icon)
                            .font(.title3)
                            .foregroundColor(iconColor)
                    }
                }
                
                Text(step.title)
                    .font(.caption)
                    .foregroundColor(isActive ? themeManager.textColor : themeManager.secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
            }
        }
    }
    
    private var backgroundColor: Color {
        if isCompleted {
            return .green
        } else if isActive {
            return .green.opacity(0.2)
        } else {
            return Color.gray.opacity(0.1)
        }
    }
    
    private var iconColor: Color {
        if isActive {
            return .green
        } else {
            return .gray
        }
    }
}

#Preview {
    NavigationStack {
        GardenProjectDetailView(project: GardenProject(name: "Mon jardin"))
            .environmentObject(GardenProjectService())
            .environmentObject(ThemeManager())
    }
}
