//
//  ContentView.swift
//  measure app
//
//  Created by hugo rath on 05/12/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = ARMeasureModel()
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ZStack {
                    ARViewContainerMesure(model: model)
                        .edgesIgnoringSafeArea(.all)
                    
                    // Overlay instructions + buttons
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
                                Label(model.isFinished ? "Modifier" : "Terminer", systemImage: model.isFinished ? "pencil" : "checkmark")
                                    .padding(10)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(8)
                            }
                        }
                        .padding()
                        Spacer()
                        Text("Tap sur l'écran pour placer les points (périmètre)")
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                            .padding(.bottom, 20)
                    }.foregroundColor(.white)
                }
                .frame(maxHeight: .infinity)
                
                // Plan top-down with interactions
                PlanTopDownView(points3D: model.points3D, isFinished: model.isFinished, previewPoint: model.previewPoint, model: model)
                    .frame(height: 320)
                    .background(Color(white: 0.97))
            }
            
            // Gallery button (bottom right)
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
            
            // Sheet for saved plans
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
    }
}
