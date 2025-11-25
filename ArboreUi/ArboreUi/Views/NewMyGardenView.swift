//
//  NewMyGardenView.swift
//  ArboreUi
//
//  Created on November 25, 2025.
//

import SwiftUI

struct NewMyGardenView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var projectService = GardenProjectService()
    @State private var showingNewProjectSheet = false
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.backgroundColor.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    headerSection
                    
                    if projectService.projects.isEmpty {
                        emptyStateView
                    } else {
                        projectsListView
                    }
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .sheet(isPresented: $showingNewProjectSheet) {
                NewProjectSheet(projectService: projectService)
                    .environmentObject(themeManager)
            }
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mon Jardin")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(themeManager.textColor)
                    
                    Text("Créez et gérez vos projets de jardin")
                        .font(.subheadline)
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                
                Spacer()
                
                Button(action: {
                    showingNewProjectSheet = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // Stats rapides
            if !projectService.projects.isEmpty {
                HStack(spacing: 12) {
                    QuickStatCard(
                        title: "Projets",
                        value: "\(projectService.projects.count)",
                        icon: "leaf.fill",
                        color: .green
                    )
                    
                    QuickStatCard(
                        title: "En cours",
                        value: "\(projectService.projects.filter { $0.status == .inProgress }.count)",
                        icon: "clock.fill",
                        color: .orange
                    )
                    
                    QuickStatCard(
                        title: "Terminés",
                        value: "\(projectService.projects.filter { $0.status == .completed }.count)",
                        icon: "checkmark.circle.fill",
                        color: .blue
                    )
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 16)
        .background(themeManager.backgroundColor)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green.opacity(0.7))
            
            VStack(spacing: 12) {
                Text("Aucun projet de jardin")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(themeManager.textColor)
                
                Text("Commencez par créer votre premier projet\net laissez l'IA vous guider")
                    .font(.body)
                    .foregroundColor(themeManager.secondaryTextColor)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: {
                showingNewProjectSheet = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Créer mon premier projet")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.green, .green.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: .green.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Projects List
    private var projectsListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(projectService.projects) { project in
                    NavigationLink(destination: GardenProjectDetailView(project: project)
                        .environmentObject(projectService)
                        .environmentObject(themeManager)) {
                        ProjectCard(project: project)
                            .environmentObject(themeManager)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }
}

// MARK: - Quick Stat Card
struct QuickStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(themeManager.textColor)
            
            Text(title)
                .font(.caption)
                .foregroundColor(themeManager.secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(themeManager.cardBackgroundColor)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Project Card
struct ProjectCard: View {
    let project: GardenProject
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                        .foregroundColor(themeManager.textColor)
                    
                    Text("Créé le \(project.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                
                Spacer()
                
                StatusBadge(status: project.status)
            }
            
            // Barre de progression
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Progression")
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryTextColor)
                    
                    Spacer()
                    
                    Text("\(Int(project.completionPercentage))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(themeManager.textColor)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                            .cornerRadius(4)
                        
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.green, .green.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * (project.completionPercentage / 100), height: 8)
                            .cornerRadius(4)
                    }
                }
                .frame(height: 8)
            }
            
            // Étapes complétées
            HStack(spacing: 12) {
                StepIndicator(completed: project.scanData != nil, icon: "viewfinder.circle.fill", title: "Scan")
                StepIndicator(completed: !project.mediaFiles.isEmpty, icon: "photo.fill", title: "Médias")
                StepIndicator(completed: project.gardenInfo != nil, icon: "info.circle.fill", title: "Infos")
                StepIndicator(completed: project.location != nil, icon: "location.fill", title: "Lieu")
                StepIndicator(completed: project.preferences != nil, icon: "slider.horizontal.3", title: "Préfs")
                StepIndicator(completed: !project.plantingZones.isEmpty, icon: "map.fill", title: "Zones")
            }
        }
        .padding(16)
        .background(themeManager.cardBackgroundColor)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let status: ProjectStatus
    
    var statusColor: Color {
        switch status {
        case .inProgress: return .orange
        case .completed: return .green
        case .analyzing: return .blue
        case .ready: return .purple
        }
    }
    
    var body: some View {
        Text(status.rawValue)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(statusColor)
            .cornerRadius(8)
    }
}

// MARK: - Step Indicator
struct StepIndicator: View {
    let completed: Bool
    let icon: String
    let title: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(completed ? .green : .gray.opacity(0.5))
            
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(completed ? .green : .gray.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - New Project Sheet
struct NewProjectSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var projectService: GardenProjectService
    
    @State private var projectName = ""
    @State private var showError = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "leaf.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("Nouveau projet de jardin")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(themeManager.textColor)
                    
                    Text("Donnez un nom à votre projet")
                        .font(.subheadline)
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                .padding(.top, 32)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nom du projet")
                        .font(.headline)
                        .foregroundColor(themeManager.textColor)
                    
                    TextField("Ex: Jardin principal, Balcon, Terrasse...", text: $projectName)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        .foregroundColor(themeManager.textColor)
                }
                .padding(.horizontal)
                
                if showError {
                    Text("Veuillez entrer un nom pour le projet")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                Button(action: createProject) {
                    Text("Créer le projet")
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
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(themeManager.backgroundColor)
            .navigationBarItems(
                trailing: Button("Annuler") {
                    dismiss()
                }
                .foregroundColor(themeManager.textColor)
            )
        }
    }
    
    private func createProject() {
        guard !projectName.trimmingCharacters(in: .whitespaces).isEmpty else {
            showError = true
            return
        }
        
        projectService.createNewProject(name: projectName)
        dismiss()
    }
}

#Preview {
    NewMyGardenView()
        .environmentObject(ThemeManager())
}
