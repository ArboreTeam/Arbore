//
//  MediaStepView.swift
//  ArboreUi
//
//  Created on November 25, 2025.
//

import SwiftUI
import PhotosUI

struct MediaStepView: View {
    let project: GardenProject
    @EnvironmentObject var projectService: GardenProjectService
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingImagePicker = false
    @State private var showingVideoPicker = false
    
    var body: some View {
        VStack(spacing: 24) {
            // En-tête
            StepHeader(
                icon: "photo.on.rectangle.angled",
                title: "Photos & Vidéos",
                description: "Ajoutez des médias pour donner plus de contexte à l'IA sur votre espace"
            )
            
            // Boutons d'ajout
            HStack(spacing: 12) {
                Button(action: {
                    showingImagePicker = true
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.fill")
                            .font(.title2)
                        Text("Ajouter photos")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .background(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                
                Button(action: {
                    showingVideoPicker = true
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "video.fill")
                            .font(.title2)
                        Text("Ajouter vidéos")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .background(
                        LinearGradient(
                            colors: [.purple, .purple.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
            }
            
            // Suggestions
            VStack(alignment: .leading, spacing: 12) {
                Label("Suggestions", systemImage: "lightbulb.fill")
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                VStack(spacing: 8) {
                    SuggestionRow(text: "Photographiez les zones bien et mal exposées au soleil")
                    SuggestionRow(text: "Montrez les points d'eau et prises électriques")
                    SuggestionRow(text: "Capturez les vues depuis différents angles")
                    SuggestionRow(text: "Filmez un tour complet de l'espace (30-60 secondes)")
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
            
            // Grille de médias
            if !project.mediaFiles.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Médias ajoutés (\(project.mediaFiles.count))")
                            .font(.headline)
                            .foregroundColor(themeManager.textColor)
                        
                        Spacer()
                        
                        Button(action: {
                            // Tout supprimer
                        }) {
                            Text("Tout supprimer")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(project.mediaFiles) { media in
                            MediaThumbnail(media: media, onDelete: {
                                projectService.removeMedia(from: project.id, mediaId: media.id)
                            })
                        }
                    }
                }
            } else {
                // État vide
                VStack(spacing: 16) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 60))
                        .foregroundColor(.gray.opacity(0.5))
                    
                    Text("Aucun média ajouté")
                        .font(.headline)
                        .foregroundColor(themeManager.secondaryTextColor)
                    
                    Text("Les photos et vidéos aideront l'IA à mieux comprendre votre espace")
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryTextColor)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(themeManager.cardBackgroundColor)
                .cornerRadius(12)
            }
            
            Spacer()
        }
        .photosPicker(
            isPresented: $showingImagePicker,
            selection: $selectedItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: selectedItems) { oldValue, newValue in
            Task {
                for item in newValue {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        // Sauvegarder l'image et obtenir l'URL
                        let url = "photo_\(UUID().uuidString).jpg"
                        projectService.addMedia(to: project.id, url: url, type: .photo)
                    }
                }
                selectedItems = []
            }
        }
    }
}

// MARK: - Media Thumbnail
struct MediaThumbnail: View {
    let media: MediaFile
    let onDelete: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Image placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    VStack {
                        Image(systemName: media.type == .photo ? "photo.fill" : "video.fill")
                            .font(.title)
                            .foregroundColor(.gray)
                    }
                )
            
            // Bouton supprimer
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.red)
                    .background(Circle().fill(Color.white))
            }
            .offset(x: 4, y: -4)
        }
    }
}

// MARK: - Suggestion Row
struct SuggestionRow: View {
    let text: String
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.orange)
            
            Text(text)
                .font(.caption)
                .foregroundColor(themeManager.textColor)
            
            Spacer()
        }
    }
}

#Preview {
    MediaStepView(project: GardenProject(name: "Test"))
        .environmentObject(GardenProjectService())
        .environmentObject(ThemeManager())
}
