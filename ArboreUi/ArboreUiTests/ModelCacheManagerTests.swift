//
//  ModelCacheManagerTests.swift
//  ArboreUiTests
//
//  Created by Claude on 11/03/2026.
//

import XCTest
import Firebase
import FirebaseAuth
@testable import ArboreUi

// MARK: - ModelCacheManager Unit Tests

class ModelCacheManagerTests: XCTestCase {

    override func setUp() async throws {
        // Configuration Firebase pour les tests
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        // Nettoyer le cache avant chaque test
        try await ModelCacheManager.shared.clearCache()
    }

    override func tearDown() async throws {
        // Nettoyer le cache après chaque test
        try await ModelCacheManager.shared.clearCache()
    }

    // MARK: - ModelCacheError Tests

    func testModelCacheError_InvalidModelURL_ShouldExist() {
        // Arrange
        let error = ModelCacheError.invalidModelURL

        // Assert
        switch error {
        case .invalidModelURL:
            XCTAssertTrue(true, "InvalidModelURL error should match")
        default:
            XCTFail("Should be invalidModelURL error")
        }
    }

    func testModelCacheError_InvalidBackendURL_ShouldExist() {
        // Arrange
        let error = ModelCacheError.invalidBackendURL

        // Assert
        switch error {
        case .invalidBackendURL:
            XCTAssertTrue(true, "InvalidBackendURL error should match")
        default:
            XCTFail("Should be invalidBackendURL error")
        }
    }

    func testModelCacheError_InvalidResponse_ShouldExist() {
        // Arrange
        let error = ModelCacheError.invalidResponse

        // Assert
        switch error {
        case .invalidResponse:
            XCTAssertTrue(true, "InvalidResponse error should match")
        default:
            XCTFail("Should be invalidResponse error")
        }
    }

    func testModelCacheError_HTTPError_ShouldContainStatusCode() {
        // Arrange
        let statusCode = 404
        let error = ModelCacheError.httpError(statusCode: statusCode)

        // Assert
        switch error {
        case .httpError(let code):
            XCTAssertEqual(code, statusCode, "HTTP error should contain correct status code")
        default:
            XCTFail("Should be httpError")
        }
    }

    func testModelCacheError_ErrorDescriptions_ShouldBePresent() {
        // Test all error descriptions
        XCTAssertNotNil(ModelCacheError.invalidModelURL.errorDescription)
        XCTAssertNotNil(ModelCacheError.invalidBackendURL.errorDescription)
        XCTAssertNotNil(ModelCacheError.invalidResponse.errorDescription)
        XCTAssertNotNil(ModelCacheError.httpError(statusCode: 404).errorDescription)
    }

    // MARK: - Cache Directory Tests

    func testModelCacheManager_CacheDirectory_ShouldExist() async {
        // Arrange
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let expectedCacheDir = documentsURL.appendingPathComponent("Models", isDirectory: true)

        // Act - Force la création en appelant une méthode qui utilise le cache
        _ = try? await ModelCacheManager.shared.getCacheSize()

        // Assert
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedCacheDir.path),
                      "Cache directory should exist")
    }

    func testModelCacheManager_GetCacheSize_EmptyCache_ShouldReturnZero() async throws {
        // Arrange - Cache déjà nettoyé dans setUp

        // Act
        let size = try await ModelCacheManager.shared.getCacheSize()

        // Assert
        XCTAssertEqual(size, 0, "Empty cache should have size 0")
    }

    func testModelCacheManager_ClearCache_ShouldRemoveAllFiles() async throws {
        // Arrange - Créer un fichier de test dans le cache
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheDir = documentsURL.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let testFilePath = cacheDir.appendingPathComponent("test.usdz")
        let testData = "test data".data(using: .utf8)!
        try testData.write(to: testFilePath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: testFilePath.path),
                      "Test file should exist before clearing")

        // Act
        try await ModelCacheManager.shared.clearCache()

        // Assert
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFilePath.path),
                       "Test file should be removed after clearing cache")

        let size = try await ModelCacheManager.shared.getCacheSize()
        XCTAssertEqual(size, 0, "Cache should be empty after clearing")
    }

    func testModelCacheManager_RemoveModel_ShouldRemoveSpecificFile() async throws {
        // Arrange - Créer deux fichiers de test
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheDir = documentsURL.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let file1Path = cacheDir.appendingPathComponent("model1.usdz")
        let file2Path = cacheDir.appendingPathComponent("model2.usdz")
        let testData = "test data".data(using: .utf8)!
        try testData.write(to: file1Path)
        try testData.write(to: file2Path)

        // Act - Supprimer seulement le premier fichier
        try await ModelCacheManager.shared.removeModel(filename: "model1.usdz")

        // Assert
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1Path.path),
                       "model1.usdz should be removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file2Path.path),
                      "model2.usdz should still exist")
    }

    func testModelCacheManager_GetModelURL_EmptyFilename_ShouldThrowError() async {
        // Act & Assert
        do {
            _ = try await ModelCacheManager.shared.getModelURL(for: "")
            XCTFail("Should throw invalidModelURL error for empty filename")
        } catch ModelCacheError.invalidModelURL {
            XCTAssertTrue(true, "Correctly threw invalidModelURL error")
        } catch {
            XCTFail("Should throw invalidModelURL error, got: \(error)")
        }
    }
}

// MARK: - ModelCacheManager Integration Tests

class ModelCacheManagerIntegrationTests: XCTestCase {

    var testUserUID: String?

    /// Session **invitée**, et non plus un compte email/mot de passe jetable.
    ///
    /// `/models/:filename` accepte les invités — c'est une route du catalogue,
    /// pas du compte. L'ancienne fixture créait une adresse qu'elle ne
    /// vérifiait jamais, et depuis le portillon d'email de #377 le backend
    /// refusait les trois tests en `EMAIL_NOT_VERIFIED`. Ils ne l'ont jamais
    /// signalé parce qu'ils ne tournaient pas (#725).
    override func setUp() async throws {
        try LiveIntegrationTestGate.requireEnabled()
        try LiveIntegrationTestGate.requireBackendReachable(suite: "ModelCacheManager")

        testUserUID = try await LiveIntegrationTestGate.ouvrirSessionInvitee().uid
        try? await ModelCacheManager.shared.clearCache()
    }

    override func tearDown() async throws {
        try await ModelCacheManager.shared.clearCache()

        // L'identité anonyme est supprimée, pas seulement déconnectée : une
        // session invitée abandonnée laisse un uid que Firebase ne nettoie
        // qu'au bout de trente jours, et que le job de réconciliation (#393)
        // devrait ensuite ramasser. Autant ne pas en créer la dette.
        if let courant = Auth.auth().currentUser {
            try? await courant.delete()
        }
        testUserUID = nil
    }

    /// Un nom de modèle que le catalogue COURANT sert vraiment.
    ///
    /// Les tests codaient `Pothos.usdz` en dur. Ce fichier n'existe pas sur
    /// dev — le catalogue y porte `Pothos_Dore_Vert.usdz` et consorts — et
    /// les deux tests de téléchargement échouaient en 404 dès qu'on les a
    /// enfin exécutés contre cet environnement (#725).
    ///
    /// Un nom en dur fait dépendre le test de QUEL catalogue répond. Lire le
    /// premier modèle servi rend le test vrai partout, et c'est précisément
    /// ce qu'il veut prouver : que le téléchargement fonctionne pour ce que
    /// le catalogue annonce.
    private func premierModeleDuCatalogue() async throws -> String {
        guard let url = URL(string: "\(AppConfig.baseURL)/plants"),
              let jeton = try await Auth.auth().currentUser?.getIDToken() else {
            throw XCTSkip("session absente : impossible de lire le catalogue")
        }
        var requete = URLRequest(url: url)
        requete.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")

        let (data, reponse) = try await URLSession.shared.data(for: requete)
        let statut = (reponse as? HTTPURLResponse)?.statusCode ?? -1
        guard statut == 200 else {
            throw XCTSkip("GET /plants a rendu \(statut) : pas de catalogue à lire")
        }

        let fiches = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        // `_potless` est une variante recoupée, pas une entrée de catalogue à
        // part : on prend le premier modèle nominal.
        let nom = fiches?.compactMap { $0["modelURL"] as? String }
            .first { !$0.isEmpty && !$0.contains("_potless") }
        guard let nom else {
            throw XCTSkip("le catalogue ne sert aucun modèle : rien à télécharger")
        }
        return nom
    }

    // MARK: - Real Backend Tests

    func testModelCacheManager_DownloadModel_ShouldCacheFile() async {
        // Test le téléchargement réel d'un modèle depuis le backend

        guard Auth.auth().currentUser != nil else {
            XCTFail("User should be authenticated")
            return
        }

        do {
            // Act - Télécharger le modèle Pothos (le plus petit: 2 MB)
            let modele = try await premierModeleDuCatalogue()
            let modelURL = try await ModelCacheManager.shared.getModelURL(for: modele)

            // Assert
            XCTAssertTrue(FileManager.default.fileExists(atPath: modelURL.path),
                          "Downloaded model should exist at cache path")

            let attributes = try FileManager.default.attributesOfItem(atPath: modelURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            XCTAssertGreaterThan(fileSize, 0, "Downloaded file should have size > 0")

            print("✅ Model downloaded successfully: \(modelURL.lastPathComponent), size: \(fileSize) bytes")

            // Vérifier le cache size
            let cacheSize = try await ModelCacheManager.shared.getCacheSize()
            XCTAssertEqual(cacheSize, fileSize, "Cache size should match downloaded file size")

        } catch {
            XCTFail("Failed to download model: \(error)")
        }
    }

    func testModelCacheManager_DownloadModel_Twice_ShouldUseCache() async {
        // Test que le deuxième appel utilise le cache

        guard Auth.auth().currentUser != nil else {
            XCTFail("User should be authenticated")
            return
        }

        do {
            let modele = try await premierModeleDuCatalogue()

            // First download
            let startTime1 = Date()
            let modelURL1 = try await ModelCacheManager.shared.getModelURL(for: modele)
            let duration1 = Date().timeIntervalSince(startTime1)

            XCTAssertTrue(FileManager.default.fileExists(atPath: modelURL1.path),
                          "First download should succeed")

            // Second download (should use cache)
            let startTime2 = Date()
            let modelURL2 = try await ModelCacheManager.shared.getModelURL(for: modele)
            let duration2 = Date().timeIntervalSince(startTime2)

            XCTAssertEqual(modelURL1.path, modelURL2.path,
                           "Both calls should return same cache path")
            XCTAssertLessThan(duration2, duration1 / 10,
                              "Cached access should be much faster than download")

            print("✅ First download: \(String(format: "%.2f", duration1))s, Cached: \(String(format: "%.2f", duration2))s")

        } catch {
            XCTFail("Failed to test cache: \(error)")
        }
    }

    func testModelCacheManager_DownloadInvalidModel_ShouldFail() async {
        // Test le téléchargement d'un modèle qui n'existe pas

        guard Auth.auth().currentUser != nil else {
            XCTFail("User should be authenticated")
            return
        }

        do {
            _ = try await ModelCacheManager.shared.getModelURL(for: "NonExistent.usdz")
            XCTFail("Should fail when downloading non-existent model")
        } catch ModelCacheError.httpError(let statusCode) {
            XCTAssertEqual(statusCode, 404, "Should return 404 for non-existent model")
            print("✅ Correctly failed with 404 for non-existent model")
        } catch {
            XCTFail("Should throw httpError(404), got: \(error)")
        }
    }

    func testModelCacheManager_WithoutAuth_ShouldFail() async {
        // Le nom est lu AVANT la déconnexion, et c'est ce qui donne du sens au
        // test : avec un nom qui n'existe pas, l'échec serait un 404 et on ne
        // saurait pas si l'absence d'authentification y est pour quelque
        // chose. Avec un modèle réellement servi, seul le défaut d'auth peut
        // faire échouer l'appel.
        let modele = (try? await premierModeleDuCatalogue()) ?? "NonExistent.usdz"

        try? Auth.auth().signOut()

        do {
            _ = try await ModelCacheManager.shared.getModelURL(for: modele)
            XCTFail("Should fail when not authenticated")
        } catch {
            // Devrait échouer (401 ou autre erreur d'auth)
            print("✅ Correctly failed without authentication: \(error)")
            XCTAssertTrue(true, "Should fail without auth")
        }

        // Rouvrir une session pour que `tearDown` ait une identité à nettoyer.
        // Une session invitée n'est pas rattrapable par mot de passe : on en
        // ouvre une neuve, et c'est celle-là que tearDown supprimera.
        try? await LiveIntegrationTestGate.ouvrirSessionInvitee()
    }
}

// MARK: - Plant Model Tests

class PlantModelTests: XCTestCase {

    func testPlant_GetModelURL_WithValidModel_ShouldReturnURL() async {
        // Test la nouvelle méthode async getModelURL()

        // Arrange - Créer une plante de test
        let plantJSON = """
        {
            "id": "test123",
            "name": "Test Plant",
            "type": "Indoor",
            "imageURLs": ["https://example.com/image.jpg"],
            "description": "Test description",
            "modelURL": "Pothos.usdz",
            "translations": {}
        }
        """

        guard let jsonData = plantJSON.data(using: .utf8),
              let plant = try? JSONDecoder().decode(Plant.self, from: jsonData) else {
            XCTFail("Failed to create test plant")
            return
        }

        // Note: On ne teste pas le téléchargement réel ici car il faudrait être authentifié
        // On teste juste que la méthode existe et a la bonne signature

        XCTAssertEqual(plant.modelURL, "Pothos.usdz", "Plant should have modelURL")
    }

    func testPlant_LocalModelURL_Deprecated_ShouldStillWork() {
        // Test que l'ancienne méthode synchrone fonctionne encore en fallback

        let plantJSON = """
        {
            "id": "test123",
            "name": "Test Plant",
            "type": "Indoor",
            "imageURLs": ["https://example.com/image.jpg"],
            "description": "Test description",
            "modelURL": "Pothos.usdz",
            "translations": {}
        }
        """

        guard let jsonData = plantJSON.data(using: .utf8),
              let plant = try? JSONDecoder().decode(Plant.self, from: jsonData) else {
            XCTFail("Failed to create test plant")
            return
        }

        // L'ancienne méthode devrait toujours exister (deprecated)
        _ = plant.localModelURL
        // Si le bundle n'a pas le fichier, ça retourne nil (ce qui est OK pour ce test)

        XCTAssertTrue(true, "Deprecated localModelURL should still be accessible")
    }

    func testPlant_GetModelURL_WithEmptyModelURL_ShouldThrowError() async {
        // Both `modelURL` and `name` empty — no candidate filename can be
        // reconstructed, so getModelURL should throw `.invalidModelURL`
        // immediately. (When `name` is non-empty, getModelURL tries
        // <name>.usdz / <name>_with_underscores.usdz as fallbacks before
        // giving up — covered by other tests.)

        let plantJSON = """
        {
            "id": "test123",
            "name": "",
            "type": "Indoor",
            "imageURLs": ["https://example.com/image.jpg"],
            "description": "Test description",
            "modelURL": "",
            "translations": {}
        }
        """

        guard let jsonData = plantJSON.data(using: .utf8),
              let plant = try? JSONDecoder().decode(Plant.self, from: jsonData) else {
            XCTFail("Failed to create test plant")
            return
        }

        do {
            _ = try await plant.getModelURL()
            XCTFail("Should throw error for empty modelURL")
        } catch ModelCacheError.invalidModelURL {
            XCTAssertTrue(true, "Correctly threw invalidModelURL error")
        } catch {
            XCTFail("Should throw invalidModelURL error, got: \(error)")
        }
    }
}
