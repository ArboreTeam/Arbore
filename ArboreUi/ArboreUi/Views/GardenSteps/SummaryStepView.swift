//
//  SummaryStepView.swift
//  ArboreUi
//
//  Created on November 25, 2025.
//

import SwiftUI

struct SummaryStepView: View {
    let project: GardenProject
    @EnvironmentObject var projectService: GardenProjectService
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(spacing: 24) {
            // En-tête
            StepHeader(
                icon: "checkmark.seal.fill",
                title: "Résumé du projet",
                description: "Vérifiez vos informations avant l'analyse IA"
            )
            
            ScrollView {
                VStack(spacing: 20) {
                    // Score de complétude
                    completionScoreCard
                    
                    // Scan
                    if let scanData = project.scanData {
                        SummarySection(
                            title: "Scan",
                            icon: "viewfinder.circle.fill",
                            color: .blue,
                            isComplete: true
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                SummaryRow(label: "Type", value: scanData.scanType.rawValue)
                                SummaryRow(label: "Surface", value: "\(Int(scanData.area)) m²")
                                SummaryRow(label: "Date", value: scanData.scanDate.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                    } else {
                        incompleteSectionCard(title: "Scan", icon: "viewfinder.circle.fill")
                    }
                    
                    // Médias
                    SummarySection(
                        title: "Photos & Vidéos",
                        icon: "photo.fill",
                        color: .purple,
                        isComplete: !project.mediaFiles.isEmpty
                    ) {
                        if !project.mediaFiles.isEmpty {
                            HStack {
                                Text("\(project.mediaFiles.filter { $0.type == .photo }.count) photos")
                                Text("•")
                                Text("\(project.mediaFiles.filter { $0.type == .video }.count) vidéos")
                            }
                            .font(.subheadline)
                            .foregroundColor(themeManager.secondaryTextColor)
                        } else {
                            Text("Aucun média ajouté")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // Informations
                    if let info = project.gardenInfo {
                        SummarySection(
                            title: "Informations",
                            icon: "info.circle.fill",
                            color: .green,
                            isComplete: true
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                if info.isIndoor {
                                    SummaryRow(label: "Type", value: "Intérieur")
                                }
                                if info.isOutdoor {
                                    SummaryRow(label: "Type", value: "Extérieur")
                                }
                                SummaryRow(label: "Ensoleillement", value: info.sunExposure.rawValue)
                                if let soil = info.soilType {
                                    SummaryRow(label: "Sol", value: soil.rawValue)
                                }
                                SummaryRow(label: "Accès eau", value: info.hasWaterAccess ? "Oui" : "Non")
                            }
                        }
                    } else {
                        incompleteSectionCard(title: "Informations", icon: "info.circle.fill")
                    }
                    
                    // Localisation
                    if let location = project.location {
                        SummarySection(
                            title: "Localisation",
                            icon: "location.fill",
                            color: .red,
                            isComplete: true
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                if let city = location.city {
                                    SummaryRow(label: "Ville", value: city)
                                }
                                SummaryRow(label: "Coordonnées", value: String(format: "%.2f, %.2f", location.latitude, location.longitude))
                                if let climate = location.climateZone {
                                    SummaryRow(label: "Climat", value: climate)
                                }
                            }
                        }
                    } else {
                        incompleteSectionCard(title: "Localisation", icon: "location.fill")
                    }
                    
                    // Préférences
                    if let prefs = project.preferences {
                        SummarySection(
                            title: "Préférences",
                            icon: "slider.horizontal.3",
                            color: .orange,
                            isComplete: true
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                SummaryRow(label: "Style", value: prefs.gardenStyle.rawValue)
                                SummaryRow(label: "Entretien", value: prefs.maintenanceLevel.rawValue)
                                SummaryRow(label: "Complexité", value: prefs.plantComplexity.rawValue)
                                SummaryRow(label: "Densité", value: prefs.densityLevel.rawValue)
                                
                                if !prefs.plantTypes.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Types de plantes:")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(themeManager.textColor)
                                        
                                        Text(prefs.plantTypes.map { $0.rawValue }.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundColor(themeManager.secondaryTextColor)
                                    }
                                }
                            }
                        }
                    } else {
                        incompleteSectionCard(title: "Préférences", icon: "slider.horizontal.3")
                    }
                    
                    // Zones
                    SummarySection(
                        title: "Zones de plantation",
                        icon: "map.fill",
                        color: .teal,
                        isComplete: !project.plantingZones.isEmpty
                    ) {
                        if !project.plantingZones.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(project.plantingZones) { zone in
                                    HStack {
                                        Circle()
                                            .fill(Color.teal)
                                            .frame(width: 6, height: 6)
                                        
                                        Text(zone.name)
                                            .font(.caption)
                                            .foregroundColor(themeManager.textColor)
                                        
                                        if let type = zone.plantType {
                                            Text("• \(type.rawValue)")
                                                .font(.caption)
                                                .foregroundColor(themeManager.secondaryTextColor)
                                        }
                                    }
                                }
                            }
                        } else {
                            Text("Aucune zone définie")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // Avertissements si incomplet
                    if project.completionPercentage < 100 {
                        warningCard
                    }
                    
                    // Informations sur l'analyse IA
                    aiAnalysisInfoCard
                }
                .padding(.bottom, 20)
            }
        }
    }
    
    // MARK: - Completion Score Card
    private var completionScoreCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: project.completionPercentage / 100)
                    .stroke(
                        LinearGradient(
                            colors: [.green, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 4) {
                    Text("\(Int(project.completionPercentage))%")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(themeManager.textColor)
                    
                    Text("Complété")
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryTextColor)
                }
            }
            
            Text(completionMessage)
                .font(.subheadline)
                .foregroundColor(themeManager.secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(themeManager.cardBackgroundColor)
        .cornerRadius(16)
    }
    
    private var completionMessage: String {
        switch project.completionPercentage {
        case 100:
            return "Parfait ! Toutes les informations sont renseignées"
        case 80..<100:
            return "Presque terminé ! Quelques détails manquants"
        case 50..<80:
            return "Bon début, mais plus d'infos amélioreront les suggestions"
        default:
            return "Complétez plus d'étapes pour de meilleures recommandations"
        }
    }
    
    // MARK: - Warning Card
    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                
                Text("Informations manquantes")
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
            }
            
            Text("Vous pouvez soumettre le projet maintenant, mais l'ajout de plus d'informations permettra à l'IA de faire des recommandations plus précises et personnalisées.")
                .font(.caption)
                .foregroundColor(themeManager.secondaryTextColor)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - AI Analysis Info Card
    private var aiAnalysisInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                
                Text("Analyse IA")
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                AnalysisFeatureRow(text: "Suggestions de plantes adaptées à votre climat")
                AnalysisFeatureRow(text: "Plan d'aménagement optimal des zones")
                AnalysisFeatureRow(text: "Calendrier de plantation personnalisé")
                AnalysisFeatureRow(text: "Conseils d'entretien spécifiques")
                AnalysisFeatureRow(text: "Estimation du budget et du temps nécessaire")
            }
            
            Text("L'analyse prend généralement 1-2 minutes")
                .font(.caption)
                .foregroundColor(themeManager.secondaryTextColor)
                .italic()
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.purple.opacity(0.1), .blue.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
    }
    
    // MARK: - Helper Views
    private func incompleteSectionCard(title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.orange)
            
            Text(title)
                .font(.headline)
                .foregroundColor(themeManager.textColor)
            
            Spacer()
            
            Text("Non complété")
                .font(.caption)
                .foregroundColor(.orange)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Summary Section
struct SummarySection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    let isComplete: Bool
    @ViewBuilder let content: Content
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                Spacer()
                
                Image(systemName: isComplete ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isComplete ? .green : .orange)
            }
            
            content
                .padding(.leading, 28)
        }
        .padding()
        .background(themeManager.cardBackgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isComplete ? color.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 2)
        )
    }
}

// MARK: - Summary Row
struct SummaryRow: View {
    let label: String
    let value: String
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(themeManager.secondaryTextColor)
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(themeManager.textColor)
            
            Spacer()
        }
    }
}

// MARK: - Analysis Feature Row
struct AnalysisFeatureRow: View {
    let text: String
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.purple)
            
            Text(text)
                .font(.caption)
                .foregroundColor(themeManager.textColor)
            
            Spacer()
        }
    }
}

#Preview {
    SummaryStepView(project: GardenProject(name: "Test"))
        .environmentObject(GardenProjectService())
        .environmentObject(ThemeManager())
}
