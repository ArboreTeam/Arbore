//
//  GardenMeasureView.swift
//  measure app
//
//  Created by hugo rath on 05/12/2025.
//

import SwiftUI

struct GardenMeasureView: View {
    @StateObject private var model = ARMeasureModel()
    @State private var showIntermediate = false   // 👈 AJOUT
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ZStack {
                    ARViewContainerMesure(model: model)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack {
                        HStack {
                            Button(action: { model.clearPoints() }) {
                                Label("Effacer", systemImage: "trash")
                                    .padding(10)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(8)
                            }

                            Spacer()

                            Button(action: { model.toggleFinish() }) {
                                Label(
                                    model.isFinished ? "Modifier" : "Terminer",
                                    systemImage: model.isFinished ? "pencil" : "checkmark"
                                )
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                            }
                        }
                        .padding()

                        Spacer()

                        // 👇 Bouton visible UNIQUEMENT quand terminé
                        if model.isFinished {
                            Button(action: {
                                showIntermediate = true
                            }) {
                                Label("Créer mon jardin", systemImage: "leaf")
                                    .font(.headline)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .padding(.bottom, 12)
                        }

                        Text("Tap sur l'écran pour placer les points (périmètre)")
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                            .padding(.bottom, 20)
                    }
                    .foregroundColor(.white)
                }
                .frame(maxHeight: .infinity)

                PlanTopDownView(
                    points3D: model.points3D,
                    isFinished: model.isFinished,
                    previewPoint: model.previewPoint,
                    model: model
                )
                .frame(height: 320)
                .background(Color(white: 0.97))
            }

            // bouton galerie inchangé
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { model.showSavedPlans = true }) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Color.blue))
                    }
                    .padding()
                }
            }

            if model.showSavedPlans {
                SavedPlansView(model: model)
                    .onDisappear {
                        model.showSavedPlans = false
                    }
            }
        }
        .onAppear {
            model.loadSavedPlans()
        }
        // 👇 Navigation vers la page intermédiaire
        .fullScreenCover(isPresented: $showIntermediate) {
            IntermediateGardenView(
                selectedPlants: [] // tu pourras brancher ça plus tard
            )
        }
    }
}
