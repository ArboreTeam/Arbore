//
//  ScanStepView.swift
//  ArboreUi
//
//  Created on November 25, 2025.
//

import SwiftUI

struct ScanStepView: View {
    let project: GardenProject
    @EnvironmentObject var projectService: GardenProjectService
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var showingScanView = false
    @State private var showingScanSelection = false
    @State private var selectedScanType: ScanData.ScanType = .outdoor
    @State private var availableScans: [SavedScan] = []
    @State private var showScanConfirmation = false
    
    var body: some View {
        VStack(spacing: 24) {
            // En-tête de l'étape
            StepHeader(
                icon: "viewfinder.circle.fill",
                title: "Scannez votre espace",
                description: "Utilisez l'appareil photo pour scanner votre jardin ou votre pièce en 3D"
            )
            
            // Type de scan
            VStack(alignment: .leading, spacing: 12) {
                Text("Type d'espace")
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                VStack(spacing: 12) {
                    ScanTypeButton(
                        type: .outdoor,
                        isSelected: selectedScanType == .outdoor,
                        action: { selectedScanType = .outdoor }
                    )
                    
                    ScanTypeButton(
                        type: .room,
                        isSelected: selectedScanType == .room,
                        action: { selectedScanType = .room }
                    )
                    
                    ScanTypeButton(
                        type: .both,
                        isSelected: selectedScanType == .both,
                        action: { selectedScanType = .both }
                    )
                }
            }
            
            // Affichage du scan existant
            if let scanData = project.scanData {
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scan effectué")
                                .font(.headline)
                                .foregroundColor(themeManager.textColor)
                            
                            Text("Le \(scanData.scanDate.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(Int(scanData.area)) m²")
                                .font(.headline)
                                .foregroundColor(themeManager.textColor)
                            
                            Text(scanData.scanType.rawValue)
                                .font(.caption)
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    
                    Button(action: {
                        showingScanView = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refaire le scan")
                        }
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
            } else {
                // Instructions
                VStack(spacing: 16) {
                    InstructionRow(
                        number: 1,
                        text: "Assurez-vous d'avoir un bon éclairage"
                    )
                    
                    InstructionRow(
                        number: 2,
                        text: "Déplacez-vous lentement autour de l'espace"
                    )
                    
                    InstructionRow(
                        number: 3,
                        text: "Capturez tous les angles et détails"
                    )
                    
                    InstructionRow(
                        number: 4,
                        text: "Le scan prend environ 2-5 minutes"
                    )
                }
                .padding()
                .background(themeManager.cardBackgroundColor)
                .cornerRadius(12)
                
                // Boutons pour choisir un scan
                VStack(spacing: 12) {
                    // Choisir un scan existant
                    if !availableScans.isEmpty {
                        Button(action: {
                            showingScanSelection = true
                        }) {
                            HStack {
                                Image(systemName: "folder.fill")
                                Text("Choisir un scan existant (\(availableScans.count))")
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
                    
                    // Créer un nouveau scan
                    Button(action: {
                        showingScanView = true
                    }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Créer un nouveau scan")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                        .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                }
            }
            
            Spacer()
        }
        .onAppear {
            loadAvailableScans()
        }
        .sheet(isPresented: $showingScanView) {
            ScanCreationView(
                selectedScanType: $selectedScanType,
                onScanCompleted: { scanURL, area in
                    projectService.saveScanData(
                        for: project.id,
                        scanURL: scanURL,
                        area: area,
                        scanType: selectedScanType
                    )
                    showScanConfirmation = true
                }
            )
            .environmentObject(themeManager)
        }
        .sheet(isPresented: $showingScanSelection) {
            ScanSelectionView(
                availableScans: availableScans,
                onScanSelected: { scan in
                    projectService.saveScanData(
                        for: project.id,
                        scanURL: scan.url,
                        area: scan.area,
                        scanType: scan.scanType
                    )
                    showingScanSelection = false
                    showScanConfirmation = true
                }
            )
            .environmentObject(themeManager)
        }
        .alert("Scan enregistré !", isPresented: $showScanConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Le scan a été associé à votre projet avec succès.")
        }
    }
    
    private func loadAvailableScans() {
        availableScans = SavedScan.loadSavedScans()
    }
}

// MARK: - Scan Type Button
struct ScanTypeButton: View {
    let type: ScanData.ScanType
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    var icon: String {
        switch type {
        case .outdoor: return "sun.max.fill"
        case .room: return "house.fill"
        case .both: return "arrow.left.arrow.right"
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? .white : themeManager.textColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.rawValue)
                        .font(.headline)
                        .foregroundColor(isSelected ? .white : themeManager.textColor)
                    
                    Text(typeDescription)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : themeManager.secondaryTextColor)
                }
                
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
    
    private var typeDescription: String {
        switch type {
        case .outdoor: return "Jardin, terrasse, balcon..."
        case .room: return "Appartement, maison..."
        case .both: return "Combinaison des deux"
        }
    }
}

// MARK: - Instruction Row
struct InstructionRow: View {
    let number: Int
    let text: String
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Text("\(number)")
                    .font(.headline)
                    .foregroundColor(.green)
            }
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(themeManager.textColor)
            
            Spacer()
        }
    }
}

// MARK: - Step Header (composant réutilisable)
struct StepHeader: View {
    let icon: String
    let title: String
    let description: String
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(.green)
            
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(themeManager.textColor)
            
            Text(description)
                .font(.subheadline)
                .foregroundColor(themeManager.secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(themeManager.cardBackgroundColor)
        .cornerRadius(16)
    }
}

// MARK: - Saved Scan Model
struct SavedScan: Identifiable {
    let id: String
    let name: String
    let url: String
    let area: Double
    let scanType: ScanData.ScanType
    let createdAt: Date
    let thumbnailURL: String?
    
    static func loadSavedScans() -> [SavedScan] {
        // Charger depuis UserDefaults ou fichier
        // Pour l'instant, retournons des exemples
        return [
            SavedScan(
                id: UUID().uuidString,
                name: "Scan Jardin Principal",
                url: "scan_1.usdz",
                area: 45.0,
                scanType: .outdoor,
                createdAt: Date().addingTimeInterval(-86400 * 7),
                thumbnailURL: nil
            ),
            SavedScan(
                id: UUID().uuidString,
                name: "Scan Balcon",
                url: "scan_2.usdz",
                area: 12.0,
                scanType: .outdoor,
                createdAt: Date().addingTimeInterval(-86400 * 3),
                thumbnailURL: nil
            ),
            SavedScan(
                id: UUID().uuidString,
                name: "Scan Salon",
                url: "scan_3.usdz",
                area: 25.0,
                scanType: .room,
                createdAt: Date().addingTimeInterval(-86400),
                thumbnailURL: nil
            )
        ]
    }
}

// MARK: - Scan Creation View
struct ScanCreationView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedScanType: ScanData.ScanType
    let onScanCompleted: (String, Double) -> Void
    
    @State private var showingScanner = false
    @State private var scanName = ""
    @State private var estimatedArea: Double = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if !showingScanner {
                    VStack(spacing: 20) {
                        Image(systemName: "viewfinder.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                        
                        Text("Préparez-vous à scanner")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Assurez-vous d'avoir un bon éclairage et de l'espace pour vous déplacer")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Nom du scan (optionnel)")
                                .font(.headline)
                            
                            TextField("Ex: Jardin principal, Balcon sud...", text: $scanName)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.horizontal)
                        
                        Button(action: {
                            showingScanner = true
                        }) {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text("Commencer le scan")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                } else {
                    RoomScanWrapper()
                        .onDisappear {
                            // Scan terminé
                            let scanURL = "scan_\(UUID().uuidString).usdz"
                            let area = Double.random(in: 10...100) // Simulé
                            estimatedArea = area
                            
                            // Sauvegarder le scan
                            onScanCompleted(scanURL, area)
                            
                            dismiss()
                        }
                }
                
                Spacer()
            }
            .navigationTitle("Nouveau Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Scan Selection View
struct ScanSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    let availableScans: [SavedScan]
    let onScanSelected: (SavedScan) -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(availableScans) { scan in
                        Button(action: {
                            onScanSelected(scan)
                        }) {
                            SavedScanCard(scan: scan)
                        }
                    }
                }
                .padding()
            }
            .background(themeManager.backgroundColor)
            .navigationTitle("Choisir un scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Saved Scan Card
struct SavedScanCard: View {
    let scan: SavedScan
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail ou icône
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: scanTypeIcon)
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(scan.name)
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                HStack {
                    Image(systemName: "ruler")
                        .font(.caption)
                    Text("\(Int(scan.area)) m²")
                        .font(.subheadline)
                }
                .foregroundColor(themeManager.secondaryTextColor)
                
                HStack {
                    Image(systemName: "calendar")
                        .font(.caption)
                    Text(scan.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                }
                .foregroundColor(themeManager.tertiaryTextColor)
                
                Text(scan.scanType.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(themeManager.cardBackgroundColor)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var scanTypeIcon: String {
        switch scan.scanType {
        case .outdoor: return "sun.max.fill"
        case .room: return "house.fill"
        case .both: return "arrow.left.arrow.right"
        }
    }
}

#Preview {
    ScanStepView(project: GardenProject(name: "Test"))
        .environmentObject(GardenProjectService())
        .environmentObject(ThemeManager())
}
