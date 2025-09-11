//
//  TEST_DATABASE.swift
//  ArboreUi
//
//  Created by Hugo Rath on 18/03/2025.
//

import SwiftUI
import Firebase

struct TestConnectionView: View {
    @State private var connectionStatus: String = "Cliquez pour tester la connexion"
    
    var body: some View {
        VStack {
            Text(connectionStatus)
                .padding()
            
            Button("Tester la connexion") {
                Task {
                    connectionStatus = await FirebaseService.testConnection()
                }
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
    }
}
