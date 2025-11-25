//
//  GardenProjectService.swift
//  ArboreUi
//
//  Created on November 25, 2025.
//

import Foundation
import CoreLocation

class GardenProjectService: ObservableObject {
    @Published var projects: [GardenProject] = []
    @Published var currentProject: GardenProject?
    
    init() {
        loadProjects()
    }
    
    // MARK: - Project Management
    
    func createNewProject(name: String) {
        let project = GardenProject(name: name)
        projects.append(project)
        currentProject = project
        saveProjects()
    }
    
    func updateProject(_ project: GardenProject) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            var updatedProject = project
            updatedProject.updatedAt = Date()
            projects[index] = updatedProject
            
            if currentProject?.id == project.id {
                currentProject = updatedProject
            }
            saveProjects()
        }
    }
    
    func deleteProject(_ project: GardenProject) {
        projects.removeAll { $0.id == project.id }
        if currentProject?.id == project.id {
            currentProject = nil
        }
        saveProjects()
    }
    
    // MARK: - Scan Management
    
    func saveScanData(for projectId: String, scanURL: String, area: Double, scanType: ScanData.ScanType) {
        if let index = projects.firstIndex(where: { $0.id == projectId }) {
            let scanData = ScanData(scanURL: scanURL, scanDate: Date(), area: area, scanType: scanType)
            projects[index].scanData = scanData
            updateCurrentProject(projectId)
            saveProjects()
        }
    }
    
    // MARK: - Media Management
    
    func addMedia(to projectId: String, url: String, type: MediaFile.MediaType, caption: String? = nil) {
        if let index = projects.firstIndex(where: { $0.id == projectId }) {
            let media = MediaFile(url: url, type: type, caption: caption)
            projects[index].mediaFiles.append(media)
            updateCurrentProject(projectId)
            saveProjects()
        }
    }
    
    func removeMedia(from projectId: String, mediaId: String) {
        if let index = projects.firstIndex(where: { $0.id == projectId }) {
            projects[index].mediaFiles.removeAll { $0.id == mediaId }
            updateCurrentProject(projectId)
            saveProjects()
        }
    }
    
    // MARK: - Garden Info Management
    
    func saveGardenInfo(for projectId: String, info: GardenInfo) {
        if let index = projects.firstIndex(where: { $0.id == projectId }) {
            projects[index].gardenInfo = info
            updateCurrentProject(projectId)
            saveProjects()
        }
    }
    
    // MARK: - Location Management
    
    func saveLocation(for projectId: String, location: LocationData) {
        if let index = projects.firstIndex(where: { $0.id == projectId }) {
            projects[index].location = location
            updateCurrentProject(projectId)
            saveProjects()
        }
    }
    
    // MARK: - Preferences Management
    
    func savePreferences(for projectId: String, preferences: GardenPreferences) {
        if let index = projects.firstIndex(where: { $0.id == projectId }) {
            projects[index].preferences = preferences
            updateCurrentProject(projectId)
            saveProjects()
        }
    }
    
    // MARK: - Planting Zones Management
    
    func addPlantingZone(to projectId: String, zone: PlantingZone) {
        if let index = projects.firstIndex(where: { $0.id == projectId }) {
            projects[index].plantingZones.append(zone)
            updateCurrentProject(projectId)
            saveProjects()
        }
    }
    
    func updatePlantingZone(in projectId: String, zone: PlantingZone) {
        if let projectIndex = projects.firstIndex(where: { $0.id == projectId }),
           let zoneIndex = projects[projectIndex].plantingZones.firstIndex(where: { $0.id == zone.id }) {
            projects[projectIndex].plantingZones[zoneIndex] = zone
            updateCurrentProject(projectId)
            saveProjects()
        }
    }
    
    func removePlantingZone(from projectId: String, zoneId: String) {
        if let index = projects.firstIndex(where: { $0.id == projectId }) {
            projects[index].plantingZones.removeAll { $0.id == zoneId }
            updateCurrentProject(projectId)
            saveProjects()
        }
    }
    
    // MARK: - AI Analysis
    
    func submitForAIAnalysis(projectId: String) {
        if let index = projects.firstIndex(where: { $0.id == projectId }) {
            projects[index].status = .analyzing
            updateCurrentProject(projectId)
            saveProjects()
            
            // TODO: Appeler l'API d'analyse IA
            // Pour l'instant, simulation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.projects[index].status = .ready
                self.updateCurrentProject(projectId)
                self.saveProjects()
            }
        }
    }
    
    // MARK: - Persistence
    
    private func saveProjects() {
        if let encoded = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(encoded, forKey: "gardenProjects")
        }
    }
    
    private func loadProjects() {
        if let data = UserDefaults.standard.data(forKey: "gardenProjects"),
           let decoded = try? JSONDecoder().decode([GardenProject].self, from: data) {
            projects = decoded
        }
    }
    
    private func updateCurrentProject(_ projectId: String) {
        if currentProject?.id == projectId {
            currentProject = projects.first { $0.id == projectId }
        }
    }
}
