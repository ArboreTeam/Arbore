//
//  RoomScanViews.swift
//  ForReal Demo
//
//  Created by Vatsal Patel  on 8/17/24.
//

import Foundation
import SwiftUI
import RoomPlan

struct CameraCaptureView: UIViewRepresentable {
    @Environment(RoomCaptureController.self) private var captureController

    func makeUIView(context: Context) -> some UIView {
        captureController.roomCaptureView
    }
  
    func updateUIView(_ uiView: UIViewType, context: Context) {}
}

struct RoomScanningView: View {
    @Environment(RoomCaptureController.self) private var captureController
    @Environment(\.dismiss) var dismiss
    @State private var showNameInputSheet = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            CameraCaptureView()
                .navigationBarBackButtonHidden(true)
                .navigationBarItems(leading: Button("Annuler") {
                    captureController.stopSession()
                    dismiss()
                })
                .navigationBarItems(trailing: Button("Terminé") {
                    captureController.stopSession()
                }.opacity(captureController.isScanComplete ? 0 : 1))
                .onAppear() {
                    captureController.showSaveButton = false
                    captureController.isScanComplete = false
                    captureController.startSession()
                }
                .onDisappear() {
                    captureController.stopSession()
                }
            
            if captureController.showSaveButton {
                Button(action: {
                    // Stop the session before showing the sheet
                    captureController.stopSession()
                    showNameInputSheet = true
                }, label: {
                    Text("Sauvegarder le scan").font(.title2)
                })
                .buttonStyle(.borderedProminent)
                .cornerRadius(40)
                .padding()
            }
        }
        .sheet(isPresented: $showNameInputSheet) {
            SaveScanView(captureController: captureController, dismiss: dismiss)
        }
    }
}

struct SaveScanView: View {
    var captureController: RoomCaptureController
    var dismiss: DismissAction
    @Environment(\.dismiss) private var dismissSheet
    @State private var fileName: String = ""
    @State private var isSaving: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom du scan", text: $fileName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                }
                
                if isSaving {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Text("Sauvegarde en cours...")
                                .foregroundColor(.secondary)
                                .padding(.leading, 8)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Nommer le scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        dismissSheet()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sauvegarder") {
                        saveAsync()
                    }
                    .disabled(fileName.isEmpty || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }
    
    private func saveAsync() {
        guard !fileName.isEmpty else { return }
        isSaving = true
        
        // Perform save on background thread
        Task.detached(priority: .userInitiated) {
            await MainActor.run {
                captureController.fileName = fileName
                captureController.saveScan()
            }

            // Return to main thread to dismiss
            await MainActor.run {
                isSaving = false
                dismissSheet()
                dismiss()
            }
        }
    }
}

struct ScanNewRoomView: View {
    @Environment(RoomCaptureController.self) private var captureController
    @Environment(\.dismiss) var dismiss
    @State private var savedScans: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header avec icône
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                        .padding(.top, 20)
                    
                    Text("Scanner mon jardin")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Assure-toi de scanner l'espace en pointant la caméra vers toutes les surfaces.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 30)
                    
                    // Bouton pour lancer le scan
                    NavigationLink(destination: RoomScanningView()) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Lancer le scan")
                        }
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    
                    // Section des scans sauvegardés
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Scans sauvegardés")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                        
                        if savedScans.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("Aucun scan sauvegardé")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                        } else {
                            ForEach(savedScans, id: \.self) { scanName in
                                NavigationLink(destination: FileDetailView(fileName: scanName)) {
                                    HStack {
                                        Image(systemName: "cube.fill")
                                            .foregroundColor(.blue)
                                        Text(scanName.replacingOccurrences(of: ".usdz", with: ""))
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                    .padding()
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(10)
                                    .padding(.horizontal, 24)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 100)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Retour")
                        }
                    }
                }
            }
            .onAppear {
                captureController.resetSession()
                loadSavedScans()
            }
        }
    }
    
    private func loadSavedScans() {
        savedScans = RoominatorFileManager.shared.listFiles()
    }
}
