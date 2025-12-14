//
//  ContentView.swift
//  LuxAnalyzer
//
//  Created by hugo rath on 14/12/2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        // ➡️ C'est ici que vous appelez la vue principale de votre feature.
        // On englobe l'analyseur dans une NavigationView pour avoir la barre de titre et le bouton "Analyser".
        LightDiagnosticScreen()
    }
}

#Preview {
    ContentView()
}
