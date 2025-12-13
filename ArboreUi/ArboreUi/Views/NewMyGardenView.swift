//
//  NewMyGardenView.swift
//  ArboreUi
//
//  Created on November 25, 2025.
//

// Changer ce fichier pour la vue en 2D et les paramètres du jardin

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
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .sheet(isPresented: $showingNewProjectSheet) {
            }
        }
    }
}

#Preview {
    NewMyGardenView()
        .environmentObject(ThemeManager())
}
