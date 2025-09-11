//
//  MongoDBService.swift
//  ArboreUi
//
//  Created by Hugo Rath on 18/03/2025.
//

import Foundation
import FirebaseFirestore
import Firebase

struct FirebaseService {
    static var db: Firestore?

    static func connect() async throws {
        print("Connexion à Firebase...")
        
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        
        do {
            db = Firestore.firestore()
            print("Connexion réussie à Firebase")
        } catch {
            print("Erreur de connexion à Firebase : \(error)")
            throw error
        }
    }

    @MainActor
    static func testConnection() async -> String {
        do {
            try await connect()
            return "Connexion à Firebase réussie !"
        } catch {
            return "Erreur inattendue : \(error.localizedDescription)"
        }
    }
    
    static func addData() async {
        guard let db = db else { return }
        
        do {
            let _ = try await db.collection("users").addDocument(data: [
                "name": "Hugo",
                "age": 20
            ])
            print("Donnée ajoutée avec succès à Firebase Firestore !")
        } catch {
            print("Erreur d'ajout de données : \(error.localizedDescription)")
        }
    }
    
    static func fetchData() async {
        guard let db = db else { return }
        
        do {
            let snapshot = try await db.collection("users").getDocuments()
            for document in snapshot.documents {
                print("Document ID: \(document.documentID), Data: \(document.data())")
            }
        } catch {
            print("Erreur de récupération des données : \(error.localizedDescription)")
        }
    }
}
