//
//  LuxAnalyzerApp.swift
//  LuxAnalyzer
//
//  Created by hugo rath on 14/12/2025.
//

import SwiftUI
import AVFoundation
import Vision
import CoreImage.CIFilterBuiltins
import Combine

// MARK: - MODELS

enum LightZone {
    case shadow, diffuse, directSun
    
    var color: Color {
        switch self {
        case .shadow: return .blue
        case .diffuse: return .green
        case .directSun: return .orange
        }
    }
    
    var label: String {
        switch self {
        case .shadow: return "Ombre"
        case .diffuse: return "Lumière Diffuse"
        case .directSun: return "Soleil Direct"
        }
    }
}

func getScoreColor(_ score: Int) -> Color {
    switch score {
    case 0..<40: return Color.red // Mauvais
    case 40..<75: return Color.yellow // Moyen
    case 75...100: return Color.green // Excellent
    default: return Color.gray
    }
}

struct DiagnosticResult {
    let averageLux: Int
    let score: Int
    let recommendation: String
    let sunDuration: Double // Durée en heures
    
    // NOUVEAUX CHAMPS
    let sunrise: Date
    let sunset: Date
}

enum AnalysisState {
    case idle
    case analyzing
    case completed(DiagnosticResult)
    case error(String)
}

// MARK: - SERVICES

/// Service gérant la caméra et l'extraction brute de la luminosité (Lux)
class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var currentLux: Double = 0
    @Published var pixelBuffer: CVPixelBuffer? // Pour l'analyse Vision
    
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.queue")
    
    override init() {
        super.init()
        setupCamera()
    }
    
    private func setupCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        
        session.commitConfiguration()
    }
    
    func start() {
        queue.async { [weak self] in self?.session.startRunning() }
    }
    
    func stop() {
        queue.async { [weak self] in self?.session.stopRunning() }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 1. Calcul du Lux approximatif basé sur les métadonnées EXIF (ISO, Exposure)
        if let metadata = CMCopyDictionaryOfAttachments(allocator: nil, target: sampleBuffer, attachmentMode: kCMAttachmentMode_ShouldPropagate) as? [String: Any],
           let exif = metadata["{Exif}"] as? [String: Any],
           let fNumber = exif["FNumber"] as? Double,
           let exposureTime = exif["ExposureTime"] as? Double,
           let iso = exif["ISOSpeedRatings"] as? [Any], let isoVal = iso.first as? Double {
            
            // Formule standard d'estimation EV -> Lux
            // Lux = 50 * (N^2) / (t * ISO)  (Calibration approximative)
            let lux = (50.0 * pow(fNumber, 2)) / (exposureTime * (isoVal / 100.0))
            
            DispatchQueue.main.async {
                withAnimation(.linear(duration: 0.2)) {
                    self.currentLux = lux
                }
            }
        }
        
        // 2. Envoi du buffer pour analyse d'image (Vision)
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        DispatchQueue.main.async {
            self.pixelBuffer = buffer
        }
    }
}

/// Service d'analyse d'image (Détection zones claires/sombres)
class VisionAnalyzer: ObservableObject {
    @Published var heatmapImage: UIImage?
    @Published var dominantZone: LightZone = .diffuse
    
    private let context = CIContext()
    
    func analyze(buffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        
        // 1. Réduire la taille pour la perf
        let scaleFilter = CIFilter.lanczosScaleTransform()
        scaleFilter.inputImage = ciImage
        scaleFilter.scale = 0.2
        scaleFilter.aspectRatio = 1.0
        
        guard let smallImage = scaleFilter.outputImage else { return }
        
        // 2. Créer une heatmap basique (Exemple simple: Seuillage)
        // En prod: Utiliser VNGenerateAttentionBasedSaliencyImageRequest
        
        // Simuler un diagnostic visuel simple
        _ = smallImage.extent
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(smallImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        
        let brightness = Int(bitmap[0]) + Int(bitmap[1]) + Int(bitmap[2])
        
        DispatchQueue.main.async {
            if brightness > 600 { self.dominantZone = .directSun }
            else if brightness < 100 { self.dominantZone = .shadow }
            else { self.dominantZone = .diffuse }
        }
    }
}

/// Calculateur solaire (Mocké pour l'exemple sans GPS complexe)
class SolarEngine {
    
    struct SolarDay {
        let sunrise: Date
        let sunset: Date
        let dayLengthHours: Double
    }
    
    // Algorithme simplifié NOAA pour calculer le lever/coucher
    func calculateSolarDay(date: Date, location: CLLocation) -> SolarDay? {
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude
        
        let calendar = Calendar.current
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        
        // Calculs approximatifs (suffisants pour jardinage)
        let zenith = 90.833
        let D2R = Double.pi / 180.0
        let R2D = 180.0 / Double.pi
        
        // Heure lever/coucher UTC approximative
        let lngHour = lng / 15.0
        let t_rise = dayOfYear + ((6.0 - lngHour) / 24.0)
        let t_set = dayOfYear + ((18.0 - lngHour) / 24.0)
        
        func calculateTime(t: Double) -> Double? {
            let M = (0.9856 * t) - 3.289
            let L = M + (1.916 * sin(M * D2R)) + (0.020 * sin(2 * M * D2R)) + 282.634
            var RA = atan(0.91764 * tan(L * D2R)) * R2D
            
            let Lquadrant = (floor(L / 90)) * 90
            let RAquadrant = (floor(RA / 90)) * 90
            RA = RA + (Lquadrant - RAquadrant)
            RA = RA / 15
            
            let sinDec = 0.39782 * sin(L * D2R)
            let cosDec = cos(asin(sinDec))
            let cosH = (cos(zenith * D2R) - (sinDec * sin(lat * D2R))) / (cosDec * cos(lat * D2R))
            
            if cosH > 1 || cosH < -1 { return nil }
            
            let H = (t < dayOfYear + 0.5) ? (360 - acos(cosH) * R2D) / 15 : (acos(cosH) * R2D) / 15
            let T = H + RA - (0.06571 * t) - 6.622
            var UT = T - lngHour
            if UT < 0 { UT += 24 } else if UT > 24 { UT -= 24 }
            return UT
        }
        
        guard let sunriseUTC = calculateTime(t: t_rise),
              let sunsetUTC = calculateTime(t: t_set) else { return nil }
        
        // Conversion en Date object
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.timeZone = TimeZone(identifier: "UTC")
        
        components.hour = Int(sunriseUTC)
        components.minute = Int((sunriseUTC.truncatingRemainder(dividingBy: 1)) * 60)
        let sunriseDate = calendar.date(from: components) ?? date
        
        components.hour = Int(sunsetUTC)
        components.minute = Int((sunsetUTC.truncatingRemainder(dividingBy: 1)) * 60)
        let sunsetDate = calendar.date(from: components) ?? date
        
        let duration = sunsetDate.timeIntervalSince(sunriseDate) / 3600.0
        
        return SolarDay(sunrise: sunriseDate, sunset: sunsetDate, dayLengthHours: duration)
    }
}

class ExpertScoringEngine {
    
    /// Calcule un score de 0 à 100 basé sur plusieurs facteurs
    static func computeScore(avgLux: Int, heading: Double?, dayLength: Double) -> Int {
        
        // 1. Score de Luminosité (Base) - 60% du poids
        // 500 lux = minable, 2000 lux = bon, 20000+ = excellent
        let luxScore: Double
        if avgLux < 200 { luxScore = 10 }
        else if avgLux < 1000 { luxScore = 30 + (Double(avgLux - 200) / 800.0) * 20 } // 30-50
        else if avgLux < 5000 { luxScore = 50 + (Double(avgLux - 1000) / 4000.0) * 30 } // 50-80
        else { luxScore = 80 + min(20, (Double(avgLux - 5000) / 15000.0) * 20) } // 80-100
        
        // 2. Score d'Orientation (Si disponible) - 25% du poids
        // Sud (180°) = Top, Nord (0°) = Bof
        var orientationScore: Double = 50 // Neutre par défaut
        if let h = heading {
            // Écart par rapport au Sud (180°)
            let distFromSouth = abs(180 - h)
            // Plus on est proche de 0 (Sud), plus le score est haut (100). Plus on s'éloigne (Nord), plus ça baisse.
            orientationScore = 100 - (distFromSouth / 180.0 * 80) // Min 20, Max 100
        }
        
        // 3. Score de Saison (Durée du jour) - 15% du poids
        // Hiver (8h) vs Été (15h)
        let seasonScore = min(100, max(0, (dayLength - 8.0) / (16.0 - 8.0) * 100))
        
        // Calcul Final Pondéré
        let finalScore = (luxScore * 0.60) + (orientationScore * 0.25) + (seasonScore * 0.15)
        return Int(finalScore)
    }
    
    static func getRecommendation(score: Int, orientation: String) -> String {
        if score > 85 { return "Parfait pour: Cactus, Agrumes, Olivier (Plein Soleil)" }
        if score > 65 { return "Idéal pour: Monstera, Ficus, Pothos (Lumière vive)" }
        if score > 40 { return "Bien pour: Calathea, Philodendron (Mi-ombre)" }
        return "Attention: Sansevieria ou Zamioculcas uniquement (Ombre)"
    }
}

import SwiftUI
import Combine

class LightAnalysisViewModel: ObservableObject {
    // Services
    private let cameraManager = CameraManager()
    private let visionAnalyzer = VisionAnalyzer()
    private let locationService = LocationService() // Nouveau
    private let solarEngine = SolarEngine() // Nouveau
    
    private var cancellables = Set<AnyCancellable>()
    
    // UI State
    @Published var luxValue: Int = 0
    @Published var lightScore: Double = 0.0
    @Published var analysisState: AnalysisState = .idle
    @Published var currentZone: LightZone = .diffuse
    @Published var orientation: String = "--" // Vrai orientation
    @Published var solarProfile: String = "Calcul..." // Vrai lever/coucher
    
    private var analysisTimer: Timer?
    private var samples: [Double] = []
    
    // Pour stocker les données calculées
    private var currentSolarDay: SolarEngine.SolarDay?
    
    init() {
        setupBindings()
        locationService.requestPermission() // Demande GPS au lancement
    }
    
    private func setupBindings() {
        // Camera Lux
        cameraManager.$currentLux
            .sink { [weak self] rawLux in
                self?.luxValue = Int(rawLux)
                // Score "Live" simplifié pour l'UI temps réel
                self?.lightScore = min(100, log10(rawLux + 1) * 22)
            }
            .store(in: &cancellables)
            
        // Vision
        cameraManager.$pixelBuffer
            .compactMap { $0 }
            .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] buffer in
                self?.visionAnalyzer.analyze(buffer: buffer)
            }
            .store(in: &cancellables)
            
        visionAnalyzer.$dominantZone
            .assign(to: \.currentZone, on: self)
            .store(in: &cancellables)
        
        // Location & Orientation
        locationService.$cardinalDirection
            .assign(to: \.orientation, on: self)
            .store(in: &cancellables)
            
        locationService.$location
            .compactMap { $0 }
            .first() // Calculer une seule fois quand on a la loc
            .sink { [weak self] loc in
                self?.calculateSolarData(location: loc)
            }
            .store(in: &cancellables)
    }
    
    private func calculateSolarData(location: CLLocation) {
        if let solarDay = solarEngine.calculateSolarDay(date: Date(), location: location) {
            self.currentSolarDay = solarDay
            
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let rise = formatter.string(from: solarDay.sunrise)
            let set = formatter.string(from: solarDay.sunset)
            self.solarProfile = "☀️ \(rise) - 🌙 \(set)"
        }
    }
    
    // MARK: - Actions
    
    func startCamera() {
        cameraManager.start()
        locationService.start()
    }
    
    func startAnalysis() {
        guard case .idle = analysisState else { return }
        analysisState = .analyzing
        samples.removeAll()
        
        analysisTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.samples.append(Double(self.luxValue))
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.completeAnalysis()
        }
    }
    
    func resetAnalysis() {
        analysisTimer?.invalidate()
        samples.removeAll()
        analysisState = .idle
        lightScore = 0
    }
    
    private func completeAnalysis() {
            analysisTimer?.invalidate()
            
            // 1. Calcul de la moyenne des Lux capturés
            let avgLux = samples.isEmpty ? 0 : Int(samples.reduce(0, +) / Double(samples.count))
            
            // 2. Récupération des données géographiques & solaires
            let headingVal = locationService.heading?.magneticHeading
            let dayLen = currentSolarDay?.dayLengthHours ?? 12.0 // Fallback à 12h si pas de GPS
            
            // 3. Gestion des dates de lever/coucher (Fallback si GPS non dispo)
            // Par défaut: 07h00 - 19h00 si l'app n'a pas la loc
            let defaultSunrise = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
            let defaultSunset = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date())!
            
            let finalSunrise = currentSolarDay?.sunrise ?? defaultSunrise
            let finalSunset = currentSolarDay?.sunset ?? defaultSunset
            
            // 4. Calcul du Score Expert (Lux + Orientation + Saison)
            let finalScore = ExpertScoringEngine.computeScore(avgLux: avgLux, heading: headingVal, dayLength: dayLen)
            
            // 5. Génération de la recommandation textuelle
            let recommendation = ExpertScoringEngine.getRecommendation(score: finalScore, orientation: orientation)
            
            // 6. Création de l'objet Résultat
            let result = DiagnosticResult(
                averageLux: avgLux,
                score: finalScore,
                recommendation: recommendation,
                sunDuration: dayLen,
                sunrise: finalSunrise, // ✅ Vraie date passée ici
                sunset: finalSunset    // ✅ Vraie date passée ici
            )
            
            // 7. Mise à jour de l'UI
            withAnimation {
                self.analysisState = .completed(result)
            }
        }
    
    var session: AVCaptureSession { cameraManager.session }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.frame
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct LightHUDView: View {
    @ObservedObject var vm: LightAnalysisViewModel
    let onDismiss: () -> Void
    
    var body: some View {
        VStack {
            // --- LIQUID GLASS PANEL (En HAUT) avec bouton retour intégré ---
            VStack(spacing: 12) {
                
                // Bouton Retour intégré en haut à droite de la barre
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
                
                // 1. Info Bar (Orientation & Zone)
                HStack {
                    Label(L10n.f("LUX_ORIENTATION_FACING_FORMAT", vm.orientation), systemImage: "safari")
                        .font(.caption2.bold())
                    
                    Spacer()
                    
                    Label(vm.currentZone.label, systemImage: vm.currentZone == .directSun ? "sun.max.fill" : "cloud.sun.fill")
                        .font(.caption2.bold())
                        .foregroundColor(vm.currentZone.color)
                }
                .foregroundColor(.secondary)
                
                Divider().background(Color.black.opacity(0.1))
                
                // 2. Gros Affichage LUX & Score Live
                HStack(alignment: .center, spacing: 20) {
                    
                    // LUX (Gauche)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(vm.luxValue)")
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .contentTransition(.numericText(value: Double(vm.luxValue)))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        
                        Text(L10n.t("LUX_INSTANT"))
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Live Gauge (Droite)
                    ZStack {
                        Circle()
                            .stroke(Color.black.opacity(0.1), lineWidth: 5)
                            .frame(width: 45, height: 45)
                        
                        Circle()
                            .trim(from: 0, to: vm.lightScore / 100)
                            .stroke(
                                getScoreColor(Int(vm.lightScore)),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 45, height: 45)
                            .animation(.easeOut, value: vm.lightScore)
                        
                        Text("\(Int(vm.lightScore))")
                            .font(.caption.bold())
                            .foregroundColor(getScoreColor(Int(vm.lightScore)))
                    }
                }
            }
            .padding(16)
            // ✨ EFFET LIQUID GLASS ✨
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
            .padding(.horizontal)
            .padding(.top, 8)
            
            Spacer()
            
            // --- RETICULE DE VISÉE (Au centre) ---
            if case .analyzing = vm.analysisState {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(Double(Date().timeIntervalSince1970) * 360))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: UUID())
                }
                .offset(y: -50)
            }
            
            Spacer()
        }
    }
}

struct SunTimelineView: View {
    let sunrise: Date
    let sunset: Date
    
    // Pour formater l'heure (ex: 14:30)
    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }
    
    // Calcul de la progression actuelle (0.0 à 1.0) entre lever et coucher
    private var currentProgress: Double {
        let now = Date()
        let totalDay = sunset.timeIntervalSince(sunrise)
        let elapsed = now.timeIntervalSince(sunrise)
        
        if totalDay == 0 { return 0.5 }
        return min(1.0, max(0.0, elapsed / totalDay))
    }
    
    // Vérifie si c'est la nuit (avant lever ou après coucher)
    private var isNight: Bool {
        let now = Date()
        return now < sunrise || now > sunset
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Titre dynamique selon la saison
            HStack {
                Image(systemName: isNight ? "moon.stars.fill" : "sun.max.fill")
                    .foregroundColor(isNight ? .blue : .yellow)
                Text(isNight ? L10n.t("LUX_NIGHT_CYCLE") : L10n.t("LUX_DAYLIGHT"))
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            // La Barre de progression solaire
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Fond (Trajectoire complète)
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 12)
                    
                    // Progression du soleil (Dégradé Jaune -> Orange)
                    if !isNight {
                        Capsule()
                            .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * currentProgress, height: 12)
                    }
                    
                    // Curseur "Maintenant"
                    if !isNight {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 16, height: 16)
                            .shadow(radius: 2)
                            .offset(x: (geo.size.width * currentProgress) - 8)
                    }
                }
            }
            .frame(height: 16)
            
            // Les Heures (Réelles)
            HStack {
                VStack(alignment: .leading) {
                    Text(L10n.t("LUX_SUNRISE"))
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(timeFormatter.string(from: sunrise))
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Durée totale (Info Saisonnière)
                Text(L10n.f("LUX_SUNLIGHT_HOURS_FORMAT", sunset.timeIntervalSince(sunrise) / 3600))
                    .font(.caption2)
                    .foregroundColor(.yellow.opacity(0.8))
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(L10n.t("LUX_SUNSET"))
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(timeFormatter.string(from: sunset))
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.6))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct LightDiagnosticScreen: View {
    @StateObject private var vm = LightAnalysisViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // 1. Layer Caméra
            CameraPreviewView(session: vm.session)
                .edgesIgnoringSafeArea(.all)
                .opacity(vm.analysisState.isCompleted ? 0.4 : 1.0)
            
            // 2. Layer Overlay Visuel (Heatmap simplifiée)
            if vm.currentZone == .directSun {
                Color.yellow.opacity(0.1).edgesIgnoringSafeArea(.all).blendMode(.overlay)
            } else if vm.currentZone == .shadow {
                Color.blue.opacity(0.1).edgesIgnoringSafeArea(.all).blendMode(.overlay)
            }
            
            // 3. Layer HUD (Live)
            if !vm.analysisState.isCompleted {
                LightHUDView(vm: vm, onDismiss: { dismiss() })
                
                // Bouton Start
                VStack {
                    Spacer()
                    if case .idle = vm.analysisState {
                        Button(action: { vm.startAnalysis() }) {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 70, height: 70)
                                .overlay(
                                    Circle().fill(Color.white).padding(6)
                                )
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            
            // 4. Layer Résultat (Modal-like)
            if case let .completed(result) = vm.analysisState {
                DiagnosticResultView(result: result) {
                    withAnimation {
                        vm.resetAnalysis()
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            vm.startCamera()
        }
    }
}

// Extension utilitaire pour l'état
extension AnalysisState {
    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
}



struct DiagnosticResultView: View {
    let result: DiagnosticResult
    let onReset: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Text(L10n.t("LUX_ANALYSIS_COMPLETE"))
                .font(.title2.bold())
                .foregroundColor(.white)
            
            // Score Global avec Couleur Dynamique
            VStack(spacing: 8) {
                Text("\(result.score)")
                    .font(.system(size: 80, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        // Dégradé subtil basé sur la couleur du score
                        LinearGradient(
                            colors: [
                                getScoreColor(result.score).opacity(0.8),
                                getScoreColor(result.score)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: getScoreColor(result.score).opacity(0.5), radius: 20, x: 0, y: 0)
                
                Text(L10n.t("LUX_GLOBAL_SCORE"))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
                    .textCase(.uppercase)
            }
            
            Divider().background(Color.white.opacity(0.2))
            
            // Grille d'informations
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(icon: "sun.max", title: L10n.t("LUX_AVERAGE"), value: "\(result.averageLux) lx")
                InfoRow(icon: "leaf", title: L10n.t("LUX_PLANTS"), value: result.recommendation)
                InfoRow(icon: "clock", title: L10n.t("LUX_DAY_DURATION"), value: L10n.f("LUX_HOURS_VALUE_FORMAT", result.sunDuration))
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(16)
            
            // Timeline
            SunTimelineView(sunrise: result.sunrise, sunset: result.sunset)
                .frame(height: 100)
            
            // Bouton Reset
            Button(action: onReset) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text(L10n.t("LUX_NEW_ANALYSIS"))
                }
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white.opacity(0.2))
                .foregroundColor(.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
            }
            .padding(.top)
        }
        .padding(30)
        .background(.ultraThinMaterial) // Effet glass aussi pour le fond
        .background(Color.black.opacity(0.8)) // Assombri pour la lisibilité
        .cornerRadius(30)
        .shadow(radius: 20)
        .padding()
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 30)
                .foregroundColor(.yellow)
            Text(title).foregroundStyle(.gray)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(.white)
        }
    }
}

import CoreLocation

class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var location: CLLocation?
    @Published var heading: CLHeading?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    // Pour l'affichage UI (ex: "Sud-Est 135°")
    @Published var cardinalDirection: String = "--"
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    func start() {
        manager.startUpdatingLocation()
        manager.startUpdatingHeading() // Active la boussole
    }
    
    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }
    
    // MARK: - Delegates
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            start()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        self.location = loc
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        self.heading = newHeading
        self.cardinalDirection = calculateCardinal(degrees: newHeading.magneticHeading)
    }
    
    private func calculateCardinal(degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
        let index = Int((degrees + 22.5) / 45.0) & 7
        return directions[index]
    }
}

// MARK: - App Entry Point

struct LuxAnalyzerApp: App {
    var body: some Scene {
        WindowGroup {
            LightDiagnosticScreen()
        }
    }
}

#Preview {
    LightDiagnosticScreen()
}
