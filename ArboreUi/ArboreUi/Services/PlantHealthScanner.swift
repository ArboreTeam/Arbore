//
//  PlantHealthScanner.swift
//  ArboreUi
//
//  Pipeline de scan de santé de plante.
//  Architecture en 4 étapes :
//    1. Validation qualité (luminosité + flou)
//    2. Détection de plante (Vision Framework)
//    3. Analyse colorimétrique (HSL segmentation)
//    4. Diagnostic Gemini (identification espèce + pathologie)
//

import Foundation
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation

// MARK: - Résultat du scan

/// Résultat complet d'un scan de santé de plante.
struct PlantHealthScanResult {
    /// Score de santé globale (0…1, 1 = parfaite santé)
    let overallHealth: Double
    /// Indice de confiance global du diagnostic (0…1)
    let confidence: Double
    /// Espèce identifiée par Gemini (nil si inconnue)
    let species: String?
    /// Maladies détectées avec sévérité et confiance
    let diseases: [DetectedDisease]
    /// Données brutes de l'analyse colorimétrique
    let metrics: ColorimetricResult
    /// Conseils ciblés pour l'utilisateur
    let recommendations: [String]
    /// Avertissements qualité image (luminosité, flou…)
    let qualityWarnings: [String]
    /// `true` si le diagnostic ne peut pas être fiable (confiance < 60%)
    let isUncertain: Bool
    /// Source du diagnostic (Gemini ou colorimétrie seule)
    let source: DiagnosticSource

    enum DiagnosticSource {
        case gemini          // diagnostic complet via Gemini
        case colorimetryOnly // fallback sans réseau / Gemini échoué
    }
}

/// Maladie détectée par le pipeline.
struct DetectedDisease: Identifiable {
    let id = UUID()
    let name: String
    /// Sévérité estimée (0…1 → pourcentage de surface touchée)
    let severity: Double
    /// Confiance de la détection (0…1)
    let confidence: Double
}

/// Résultat de l'analyse colorimétrique sur la photo.
struct ColorimetricResult {
    /// Ratio de pixels verts sains (0…1)
    let greenRatio: Double
    /// Ratio de pixels jaunes (chlorose) (0…1)
    let yellowRatio: Double
    /// Ratio de pixels bruns (nécrose) (0…1)
    let brownRatio: Double
    /// Ratio de pixels blancs cotonneux (parasites potentiels) (0…1)
    let whiteSpotRatio: Double
    /// Écart-type luminance (uniformité du feuillage)
    let luminanceStdDev: Double
    /// Score de santé déduit de la colorimétrie seule (0…1)
    let healthScore: Double
}

// MARK: - Erreurs du scanner

enum PlantScanError: Error, LocalizedError {
    case lowBrightness(luminance: Double)
    case blurryImage(variance: Double)
    case noPlantDetected(bestLabel: String?, bestConfidence: Double)
    case cameraUnavailable
    case analysisTimeout
    case geminiError(String)

    var errorDescription: String? {
        switch self {
        case .lowBrightness:
            return NSLocalizedString("SCAN_ERROR_LOW_BRIGHTNESS", value: "Éclairage insuffisant. Rapprochez-vous d'une source de lumière.", comment: "")
        case .blurryImage:
            return NSLocalizedString("SCAN_ERROR_BLURRY", value: "Image trop floue. Stabilisez l'appareil et réessayez.", comment: "")
        case .noPlantDetected:
            return NSLocalizedString("SCAN_ERROR_NO_PLANT", value: "Aucune plante détectée. Cadrez bien le feuillage.", comment: "")
        case .cameraUnavailable:
            return NSLocalizedString("SCAN_ERROR_CAMERA", value: "Caméra indisponible.", comment: "")
        case .analysisTimeout:
            return NSLocalizedString("SCAN_ERROR_TIMEOUT", value: "L'analyse a pris trop de temps. Réessayez.", comment: "")
        case .geminiError(let msg):
            return String(format: NSLocalizedString("SCAN_ERROR_GEMINI_FORMAT", value: "Erreur d'analyse IA : %@", comment: ""), msg)
        }
    }

    /// Icône SF Symbol associée à l'erreur.
    var systemImage: String {
        switch self {
        case .lowBrightness: return "sun.min.fill"
        case .blurryImage: return "camera.metering.unknown"
        case .noPlantDetected: return "leaf.fill"
        case .cameraUnavailable: return "camera.fill"
        case .analysisTimeout: return "clock.fill"
        case .geminiError: return "exclamationmark.icloud.fill"
        }
    }
}

// MARK: - ═══════════════════════════════════════════════════════
// MARK: 1 — IMAGE QUALITY VALIDATOR
// MARK: ═══════════════════════════════════════════════════════

/// Valide la qualité d'une image avant analyse.
/// Vérifie la luminosité (CIAreaAverage) et la netteté (Laplacien).
struct ImageQualityValidator {

    /// Seuil minimum de luminance moyenne (0…1). Sous 0.15 → trop sombre.
    private static let minBrightness: Double = 0.15
    /// Seuil minimum de variance du Laplacien. Sous 100 → flou.
    private static let minLaplacianVariance: Double = 100.0

    private static let ciContext = CIContext(options: [.priorityRequestLow: true])

    /// Valide la qualité d'une image capturée.
    /// - Returns: `.success` si la qualité est acceptable, `.failure` sinon.
    static func validate(_ image: CIImage) -> Result<Void, PlantScanError> {
        // 1. Vérifier la luminosité
        let brightness = computeAverageBrightness(image)
        if brightness < minBrightness {
            return .failure(.lowBrightness(luminance: brightness))
        }

        // 2. Vérifier la netteté (Laplacien)
        let sharpness = computeLaplacianVariance(image)
        if sharpness < minLaplacianVariance {
            return .failure(.blurryImage(variance: sharpness))
        }

        return .success(())
    }

    /// Luminance moyenne de l'image via CIAreaAverage.
    private static func computeAverageBrightness(_ image: CIImage) -> Double {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent

        guard let output = filter.outputImage else { return 0.5 }

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )

        // Luminance pondérée ITU-R BT.601
        let r = Double(pixel[0]) / 255.0
        let g = Double(pixel[1]) / 255.0
        let b = Double(pixel[2]) / 255.0
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// Variance du Laplacien pour mesurer la netteté.
    /// Plus la variance est élevée, plus l'image est nette.
    private static func computeLaplacianVariance(_ image: CIImage) -> Double {
        // Réduire la résolution pour accélérer le calcul
        let scale = min(200.0 / image.extent.width, 200.0 / image.extent.height, 1.0)
        var workImage = image
        if scale < 1.0 {
            let scaleFilter = CIFilter.lanczosScaleTransform()
            scaleFilter.inputImage = image
            scaleFilter.scale = Float(scale)
            scaleFilter.aspectRatio = 1.0
            workImage = scaleFilter.outputImage ?? image
        }

        // Convertir en niveaux de gris
        let grayscale = workImage.applyingFilter("CIPhotoEffectMono")

        // Appliquer le noyau Laplacien [0, 1, 0, 1, -4, 1, 0, 1, 0]
        let laplacian = CIFilter.convolution3X3()
        laplacian.inputImage = grayscale
        laplacian.weights = CIVector(values: [0, 1, 0, 1, -4, 1, 0, 1, 0], count: 9)
        laplacian.bias = 0.5 // shift pour éviter les valeurs négatives clippées

        guard let laplacianOutput = laplacian.outputImage else { return 200 } // safe default

        // Lire les pixels et calculer la variance
        let extent = laplacianOutput.extent
        guard !extent.isInfinite, !extent.isNull else { return 200 }
        let w = Int(extent.width)
        let h = Int(extent.height)
        guard w > 0, h > 0 else { return 200 }

        let byteCount = w * h * 4
        var data = [UInt8](repeating: 0, count: byteCount)
        ciContext.render(
            laplacianOutput,
            toBitmap: &data,
            rowBytes: w * 4,
            bounds: extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )

        // Calculer la variance sur le canal R (grayscale → R=G=B)
        var sum: Double = 0
        var sumSq: Double = 0
        let pixelCount = w * h
        for i in stride(from: 0, to: byteCount, by: 4) {
            let val = Double(data[i]) / 255.0
            sum += val
            sumSq += val * val
        }

        let mean = sum / Double(pixelCount)
        let variance = (sumSq / Double(pixelCount)) - (mean * mean)
        // Multiplier pour ramener dans un range exploitable (~0…500+)
        return variance * 10000.0
    }
}

// MARK: - ═══════════════════════════════════════════════════════
// MARK: 2 — PLANT DETECTOR (Vision Framework)
// MARK: ═══════════════════════════════════════════════════════

/// Résultat de la détection de plante dans l'image.
struct PlantDetectionResult {
    /// Label Vision le plus pertinent (ex: "plant", "flower")
    let label: String
    /// Score de confiance (0…1)
    let confidence: Double
}

/// Détecte la présence d'une plante dans l'image via VNClassifyImageRequest.
struct PlantDetector {

    /// Confidence minimale pour considérer qu'une plante est détectée.
    private static let minConfidence: Double = 0.50

    /// Identifiants Vision liés aux plantes (anglais, classi Apple).
    private static let plantIdentifiers: Set<String> = [
        "plant", "flower", "tree", "leaf", "herb", "succulent",
        "houseplant", "cactus", "fern", "moss", "shrub", "vine",
        "grass", "vegetable", "fruit", "foliage", "garden",
        "flora", "petal", "blossom", "seedling", "sprout",
        "potted plant", "floral", "botanical"
    ]

    /// Détecte si l'image contient une plante.
    /// - Returns: `PlantDetectionResult` si une plante est détectée avec confiance suffisante.
    /// - Throws: `PlantScanError.noPlantDetected` si aucune plante n'est trouvée.
    static func detect(in image: CIImage) async throws -> PlantDetectionResult {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        let request = VNClassifyImageRequest()

        try handler.perform([request])

        guard let results = request.results else {
            throw PlantScanError.noPlantDetected(bestLabel: nil, bestConfidence: 0)
        }

        // Chercher la meilleure classification liée à une plante
        var bestPlant: VNClassificationObservation?
        var bestNonPlant: VNClassificationObservation?

        for observation in results {
            let label = observation.identifier.lowercased()
            let isPlant = plantIdentifiers.contains(where: { label.contains($0) })

            if isPlant {
                if bestPlant == nil || observation.confidence > bestPlant!.confidence {
                    bestPlant = observation
                }
            } else if bestNonPlant == nil {
                bestNonPlant = observation
            }
        }

        if let plant = bestPlant, Double(plant.confidence) >= minConfidence {
            return PlantDetectionResult(
                label: plant.identifier,
                confidence: Double(plant.confidence)
            )
        }

        // Pas de plante détectée avec confiance suffisante
        let best = bestPlant ?? bestNonPlant
        throw PlantScanError.noPlantDetected(
            bestLabel: best?.identifier,
            bestConfidence: Double(best?.confidence ?? 0)
        )
    }
}

// MARK: - ═══════════════════════════════════════════════════════
// MARK: 3 — COLORIMETRIC ANALYZER
// MARK: ═══════════════════════════════════════════════════════

/// Analyse colorimétrique d'une image de plante.
/// Segmente les pixels en catégories (vert sain, jaune chlorose,
/// brun nécrose, blanc parasites) via l'espace HSL.
struct ColorimetricAnalyzer {

    private static let analysisSize = CGSize(width: 200, height: 200)
    private static let ciContext = CIContext(options: [.priorityRequestLow: true])

    /// Analyse la distribution colorimétrique d'une image de plante.
    static func analyze(_ image: CIImage) -> ColorimetricResult {
        // 1. Réduire la résolution
        let small = downscale(image)
        guard let pixels = readRGBA(small) else {
            return ColorimetricResult(greenRatio: 0, yellowRatio: 0, brownRatio: 0,
                                      whiteSpotRatio: 0, luminanceStdDev: 0, healthScore: 0.5)
        }

        // 2. Classifier chaque pixel en HSL
        var green = 0, yellow = 0, brown = 0, white = 0, other = 0
        var luminances: [Double] = []

        for i in stride(from: 0, to: pixels.count - 3, by: 4) {
            let r = Float(pixels[i])   / 255.0
            let g = Float(pixels[i+1]) / 255.0
            let b = Float(pixels[i+2]) / 255.0

            let (h, s, l) = rgbToHSL(r: r, g: g, b: b)
            let lum = Double(0.299 * r + 0.587 * g + 0.114 * b)
            luminances.append(lum)

            // Fond / ombres → ignorer
            if l < 0.12 || s < 0.08 { other += 1; continue }

            // Vert sain (H: 80°–160°, saturation > 15%, pas trop sombre)
            if h >= 80 && h <= 160 && s > 0.15 && l > 0.15 {
                green += 1
            }
            // Jaune – chlorose (H: 45°–80°, saturé, lumineux)
            else if h >= 45 && h < 80 && s > 0.20 && l > 0.25 {
                yellow += 1
            }
            // Brun – nécrose (H: 10°–45°, pas trop saturé, sombre)
            else if h >= 10 && h < 45 && s > 0.15 && l < 0.50 {
                brown += 1
            }
            // Blanc cotonneux – parasites potentiels (très lumineux, désaturé)
            else if l > 0.85 && s < 0.15 {
                white += 1
            }
            else {
                other += 1
            }
        }

        let total = Double(green + yellow + brown + white + other)
        guard total > 0 else {
            return ColorimetricResult(greenRatio: 0, yellowRatio: 0, brownRatio: 0,
                                      whiteSpotRatio: 0, luminanceStdDev: 0, healthScore: 0.5)
        }

        let greenR  = Double(green)  / total
        let yellowR = Double(yellow) / total
        let brownR  = Double(brown)  / total
        let whiteR  = Double(white)  / total

        // Écart-type luminance
        let stdDev = standardDeviation(luminances)

        // Score de santé colorimétrique
        let greenScore = min(greenR / 0.45, 1.0)
        let yellowPen  = min(yellowR * 3.0, 1.0)
        let brownPen   = min(brownR * 4.0, 1.0)
        let whitePen   = min(whiteR * 5.0, 1.0)
        let varScore   = 1.0 - min(stdDev * 3.0, 1.0)

        let rawScore = greenScore * 0.45
                     + varScore * 0.10
                     + (1.0 - yellowPen) * 0.20
                     + (1.0 - brownPen)  * 0.15
                     + (1.0 - whitePen)  * 0.10

        let healthScore = min(max(rawScore, 0.0), 1.0)

        return ColorimetricResult(
            greenRatio: greenR,
            yellowRatio: yellowR,
            brownRatio: brownR,
            whiteSpotRatio: whiteR,
            luminanceStdDev: stdDev,
            healthScore: healthScore
        )
    }

    // MARK: - Utilitaires privés

    private static func downscale(_ image: CIImage) -> CIImage {
        let scaleX = analysisSize.width  / image.extent.width
        let scaleY = analysisSize.height / image.extent.height
        let scale = min(scaleX, scaleY)
        guard scale < 1.0 else { return image }
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(scale)
        filter.aspectRatio = 1.0
        return filter.outputImage ?? image
    }

    private static func readRGBA(_ image: CIImage) -> [UInt8]? {
        let extent = image.extent
        guard !extent.isInfinite, !extent.isNull else { return nil }
        let w = Int(extent.width), h = Int(extent.height)
        guard w > 0, h > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        ciContext.render(image, toBitmap: &data, rowBytes: w * 4,
                         bounds: extent, format: .RGBA8, colorSpace: colorSpace)
        return data
    }

    private static func rgbToHSL(r: Float, g: Float, b: Float) -> (h: Float, s: Float, l: Float) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let l = (mx + mn) / 2.0
        guard mx != mn else { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2.0 - mx - mn) : d / (mx + mn)
        var h: Float = 0
        if mx == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if mx == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h /= 6.0
        return (h * 360, s, l)
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return sqrt(max(0.0, variance))
    }
}

// MARK: - ═══════════════════════════════════════════════════════
// MARK: 4 — GEMINI DIAGNOSTIC SERVICE
// MARK: ═══════════════════════════════════════════════════════

/// Service de diagnostic phytopathologique via Gemini multimodal.
/// Envoie la photo de la plante + contexte colorimétrique + nom d'espèce (si connu)
/// et reçoit un diagnostic structuré en JSON.
actor GeminiDiagnosticService {

    /// Réponse JSON parsée de Gemini.
    struct GeminiDiagnosticResponse: Decodable {
        let species: String?
        let overallHealth: Double?
        let diseases: [GeminiDisease]?
        let recommendations: [String]?
        let isUncertain: Bool?

        struct GeminiDisease: Decodable {
            let name: String
            let severity: Double?
            let confidence: Double?
        }
    }

    /// Envoie une photo de plante au backend pour diagnostic via Gemini.
    /// - Parameters:
    ///   - imageData: Photo JPEG de la plante.
    ///   - plantName: Nom de la plante (si connu) pour contextualiser.
    ///   - colorimetry: Résultat colorimétrique pour enrichir le prompt.
    /// - Returns: Réponse structurée de Gemini.
    func diagnose(
        imageData: Data,
        plantName: String?,
        colorimetry: ColorimetricResult
    ) async throws -> GeminiDiagnosticResponse {

        let base64Image = imageData.base64EncodedString()
        
        struct DiagnoseRequestPayload: Encodable {
            let imageData: String
            let plantName: String?
            let colorimetry: ColorimetryPayload
        }
        
        struct ColorimetryPayload: Encodable {
            let greenRatio: Double
            let yellowRatio: Double
            let brownRatio: Double
            let whiteSpotRatio: Double
        }
        
        let colorimetryPayload = ColorimetryPayload(
            greenRatio: colorimetry.greenRatio,
            yellowRatio: colorimetry.yellowRatio,
            brownRatio: colorimetry.brownRatio,
            whiteSpotRatio: colorimetry.whiteSpotRatio
        )
        
        let payload = DiagnoseRequestPayload(
            imageData: base64Image,
            plantName: plantName,
            colorimetry: colorimetryPayload
        )
        
        guard let payloadData = try? JSONEncoder().encode(payload),
              let payloadDict = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            throw PlantScanError.geminiError("Impossible de sérialiser les données d'analyse")
        }
        
        do {
            let response: GeminiDiagnosticResponse = try await NetworkManager.shared.request(
                endpoint: "/diagnose",
                method: .POST,
                body: payloadDict
            )
            return response
        } catch {
            throw PlantScanError.geminiError(error.localizedDescription)
        }
    }
}

// MARK: - ═══════════════════════════════════════════════════════
// MARK: ORCHESTRATEUR — PlantHealthScanner
// MARK: ═══════════════════════════════════════════════════════

/// Orchestrateur principal du pipeline de scan de santé.
/// Coordonne les 4 étapes dans l'ordre et gère les fallbacks.
@MainActor
final class PlantHealthScanner: ObservableObject {

    /// Phase courante du scan, publiée pour l'UI.
    @Published var phase: ScanPhase = .preview
    /// Résultat du scan, disponible une fois terminé.
    @Published var result: PlantHealthScanResult?
    /// Erreur du scan, si applicable.
    @Published var error: PlantScanError?

    /// Indicateurs temps réel pour l'overlay caméra.
    @Published var brightnessOK: Bool = true
    @Published var plantDetected: Bool = false

    enum ScanPhase: Equatable {
        case preview     // caméra active, en attente de capture
        case capturing   // photo en cours de capture
        case analyzing   // pipeline en cours
        case result      // résultat prêt
        case error       // erreur détectée
    }

    private let geminiService = GeminiDiagnosticService()
    private let ciContext = CIContext(options: [.priorityRequestLow: true])

    /// Nom de la plante (passé depuis PlantDetailView) pour contextualiser.
    var plantName: String?

    /// Lance le pipeline complet d'analyse sur une image capturée.
    /// - Parameter pixelBuffer: Image capturée depuis AVCapturePhotoOutput.
    func analyze(image: UIImage) async {
        phase = .analyzing
        error = nil
        result = nil

        guard let ciImage = CIImage(image: image) else {
            self.error = .cameraUnavailable
            self.phase = .error
            return
        }

        // ── Étape 1 : Validation qualité ──
        let qualityResult = ImageQualityValidator.validate(ciImage)
        var warnings: [String] = []

        switch qualityResult {
        case .failure(let scanError):
            self.error = scanError
            self.phase = .error
            return
        case .success:
            break
        }

        // ── Étape 2 : Détection de plante ──
        #if targetEnvironment(simulator)
        self.plantDetected = true
        #else
        do {
            let detection = try await PlantDetector.detect(in: ciImage)
            self.plantDetected = true
            if detection.confidence < 0.75 {
                warnings.append(
                    String(format: NSLocalizedString("SCAN_WARNING_LOW_PLANT_CONFIDENCE_FORMAT",
                        value: "Détection plante incertaine (%d%%)", comment: ""),
                        Int(detection.confidence * 100))
                )
            }
        } catch {
            self.plantDetected = false
            warnings.append("Plante non détectée localement, analyse renforcée par l'IA en cours.")
        }
        #endif

        // ── Étape 3 : Analyse colorimétrique ──
        let colorimetry = ColorimetricAnalyzer.analyze(ciImage)

        // Récupérer et redimensionner l'image pour accélérer l'envoi
        let targetWidth: CGFloat = 800
        let scale = targetWidth / image.size.width
        let targetHeight = image.size.height * scale
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: targetWidth, height: targetHeight), false, 1.0)
        image.draw(in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        
        if let imageData = resizedImage.jpegData(compressionQuality: 0.6) {
            do {
                let geminiResult = try await geminiService.diagnose(
                    imageData: imageData,
                    plantName: plantName,
                    colorimetry: colorimetry
                )

                // Fusionner les résultats Gemini + colorimétrie
                let diseases = (geminiResult.diseases ?? []).map { d in
                    DetectedDisease(
                        name: d.name,
                        severity: d.severity ?? 0,
                        confidence: d.confidence ?? 0.5
                    )
                }

                // Score de santé : moyenne pondérée Gemini (70%) + colorimétrie (30%)
                let geminiHealth = geminiResult.overallHealth ?? colorimetry.healthScore
                let combinedHealth = geminiHealth * 0.70 + colorimetry.healthScore * 0.30

                // Confiance globale
                let diseaseConfidences = diseases.map(\.confidence)
                let avgDiseaseConf = diseaseConfidences.isEmpty ? 0.8 : diseaseConfidences.reduce(0, +) / Double(diseaseConfidences.count)
                let globalConfidence = avgDiseaseConf

                let isUncertain = geminiResult.isUncertain ?? (globalConfidence < 0.60)

                if isUncertain {
                    warnings.append(
                        NSLocalizedString("SCAN_WARNING_UNCERTAIN",
                            value: "Diagnostic incertain — les résultats sont indicatifs", comment: "")
                    )
                }

                self.result = PlantHealthScanResult(
                    overallHealth: combinedHealth,
                    confidence: globalConfidence,
                    species: geminiResult.species,
                    diseases: diseases,
                    metrics: colorimetry,
                    recommendations: geminiResult.recommendations ?? [],
                    qualityWarnings: warnings,
                    isUncertain: isUncertain,
                    source: .gemini
                )
                self.phase = .result

            } catch {
                // Gemini a échoué → fallback colorimétrie seule
                print("⚠️ Gemini diagnostic failed, falling back to colorimetry: \(error)")
                warnings.append(
                    NSLocalizedString("SCAN_WARNING_AI_UNAVAILABLE",
                        value: "Analyse IA indisponible — résultats basés sur la colorimétrie", comment: "")
                )
                self.result = buildColorimetryOnlyResult(colorimetry: colorimetry, warnings: warnings)
                self.phase = .result
            }
        } else {
            // Pas de JPEG → colorimétrie seule
            warnings.append(
                NSLocalizedString("SCAN_WARNING_NO_JPEG",
                    value: "Compression image échouée — résultats basés sur la colorimétrie", comment: "")
            )
            self.result = buildColorimetryOnlyResult(colorimetry: colorimetry, warnings: warnings)
            self.phase = .result
        }
    }

    /// Réinitialise le scanner pour une nouvelle capture.
    func reset() {
        phase = .preview
        result = nil
        error = nil
        plantDetected = false
        brightnessOK = true
    }

    /// Vérifie la qualité de la frame en temps réel (léger, pour l'overlay).
    /// Appelé depuis le delegate caméra, throttled côté appelant.
    func updateRealtimeIndicators(from pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        // Vérification légère de la luminosité uniquement
        let brightness = computeQuickBrightness(ciImage)
        brightnessOK = brightness >= 0.15
    }

    // MARK: - Helpers privés

    private func buildColorimetryOnlyResult(colorimetry: ColorimetricResult, warnings: [String]) -> PlantHealthScanResult {
        var diseases: [DetectedDisease] = []

        if colorimetry.yellowRatio > 0.08 {
            diseases.append(DetectedDisease(
                name: NSLocalizedString("SCAN_DISEASE_CHLOROSIS", value: "Chlorose (jaunissement)", comment: ""),
                severity: min(colorimetry.yellowRatio * 3, 1.0),
                confidence: 0.55
            ))
        }
        if colorimetry.brownRatio > 0.05 {
            diseases.append(DetectedDisease(
                name: NSLocalizedString("SCAN_DISEASE_NECROSIS", value: "Nécrose (taches brunes)", comment: ""),
                severity: min(colorimetry.brownRatio * 4, 1.0),
                confidence: 0.50
            ))
        }
        if colorimetry.whiteSpotRatio > 0.05 {
            diseases.append(DetectedDisease(
                name: NSLocalizedString("SCAN_DISEASE_PARASITES", value: "Parasites potentiels", comment: ""),
                severity: min(colorimetry.whiteSpotRatio * 5, 1.0),
                confidence: 0.40
            ))
        }

        var recommendations: [String] = []
        if colorimetry.yellowRatio > 0.08 {
            recommendations.append(NSLocalizedString("SCAN_ADVICE_CHLOROSIS",
                value: "Jaunissement détecté → vérifiez l'arrosage et l'apport en azote.", comment: ""))
        }
        if colorimetry.brownRatio > 0.05 {
            recommendations.append(NSLocalizedString("SCAN_ADVICE_NECROSIS",
                value: "Taches brunes → surveillez les maladies fongiques ou les brûlures.", comment: ""))
        }
        if recommendations.isEmpty {
            if colorimetry.healthScore > 0.75 {
                recommendations.append(NSLocalizedString("SCAN_ADVICE_HEALTHY",
                    value: "Votre plante semble en bonne santé. Continuez vos soins.", comment: ""))
            } else {
                recommendations.append(NSLocalizedString("SCAN_ADVICE_GENERAL",
                    value: "Ajustez les soins : lumière, arrosage, engrais.", comment: ""))
            }
        }

        return PlantHealthScanResult(
            overallHealth: colorimetry.healthScore,
            confidence: 0.50, // colorimétrie seule → confiance modérée
            species: nil,
            diseases: diseases,
            metrics: colorimetry,
            recommendations: recommendations,
            qualityWarnings: warnings,
            isUncertain: true,
            source: .colorimetryOnly
        )
    }

    /// Luminance rapide (CIAreaAverage) pour l'indicateur temps réel.
    private func computeQuickBrightness(_ image: CIImage) -> Double {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent
        guard let output = filter.outputImage else { return 0.5 }

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(output, toBitmap: &pixel, rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8,
                         colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)

        let r = Double(pixel[0]) / 255.0
        let g = Double(pixel[1]) / 255.0
        let b = Double(pixel[2]) / 255.0
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}
