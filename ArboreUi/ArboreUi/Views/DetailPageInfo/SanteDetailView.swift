import SwiftUI
import Vision
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - MOTEUR D'ANALYSE RÉEL

class PlantHealthAnalyzer: NSObject, ObservableObject {

    // MARK: - États publiés
    @Published var phase: AnalysisPhase = .waiting
    @Published var overallHealth: Double = 0.5       // 0…1 lissé
    @Published var metrics: [HealthMetric] = []
    @Published var diagnosis: String = ""
    @Published var advice: String = ""
    @Published var timeRemaining: Double = 1.0

    enum AnalysisPhase { case waiting, scanning, done }

    struct HealthMetric: Identifiable {
        let id    = UUID()
        let icon  : String
        let label : String
        let value : Double   // 0…1
        let color : Color
    }

    // MARK: - Constantes d'analyse
    private let downsampleSize  = CGSize(width: 160, height: 160)
    private let frameThrottle   = 8          // analyser 1 image sur 8
    private let warmupFrames    = 15         // images avant résultat final
    private let windowSize      = 20         // échantillons pour moyenne glissante

    // Compteurs
    private var frameCount = 0
    private var validSamples = 0
    private var sessionStart = Date()

    // Fenêtre glissante – on stocke les ratios bruts
    private var greenWindow:  [Double] = []
    private var yellowWindow: [Double] = []
    private var brownWindow:  [Double] = []
    private var varWindow:    [Double] = []

    // Thread safety
    private let procQueue = DispatchQueue(label: "health.analysis.queue", qos: .userInitiated)
    private let lock = NSLock()
    private let ciCtx = CIContext(options: [.priorityRequestLow: true])

    override init() {
        super.init()
        phase = .waiting
        diagnosis = "Prêt à analyser"
    }

    // MARK: - Réinitialisation
    func resetAnalysis() {
        frameCount = 0
        validSamples = 0
        greenWindow.removeAll()
        yellowWindow.removeAll()
        brownWindow.removeAll()
        varWindow.removeAll()
        DispatchQueue.main.async {
            self.phase = .waiting
            self.overallHealth = 0.5
            self.metrics = []
            self.diagnosis = ""
            self.advice = ""
            self.timeRemaining = 1.0
        }
    }

    // MARK: - Point d'entrée appelé par la caméra
    func analyzePixelBuffer(buffer: CVPixelBuffer) {
        frameCount += 1
        guard frameCount % frameThrottle == 0 else { return }

        if phase == .waiting {
            DispatchQueue.main.async { [weak self] in self?.phase = .scanning }
        }

        let ciImage = CIImage(cvPixelBuffer: buffer)

        procQueue.async { [weak self] in
            self?.processFrame(ciImage)
        }
    }

    // MARK: - Traitement d'une frame
    private func processFrame(_ ciImage: CIImage) {
        // 1. Réduire la résolution
        guard let small = downscale(ciImage) else { return }
        // 2. Lire les pixels RGBA
        guard let pixels = readRGBA(small) else { return }

        // 3. Classifier chaque pixel dans l'espace HSL
        var g = 0, y = 0, b = 0, o = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Float(pixels[i])   / 255.0
            let gr = Float(pixels[i+1]) / 255.0
            let bl = Float(pixels[i+2]) / 255.0

            let (h, s, l) = rgbToHSL(r: r, g: gr, b: bl)

            if l < 0.12 { o += 1; continue }         // ombre / fond
            if s < 0.08 { o += 1; continue }          // quasi-gris

            if (h >= 80 && h <= 160) && s > 0.15 && l > 0.15 {
                g += 1
            } else if (h >= 45 && h < 80) && s > 0.20 && l > 0.25 {
                y += 1
            } else if (h >= 10 && h < 45) && s > 0.15 && l < 0.50 {
                b += 1
            } else {
                o += 1
            }
        }

        let total = Float(g + y + b + o)
        guard total > 0 else { return }

        let greenRatio  = Double(g) / Double(total)
        let yellowRatio = Double(y) / Double(total)
        let brownRatio  = Double(b) / Double(total)

        // Variance locale approximative (indicateur de taches)
        let variance = computeLocalVariance(pixels, stride: 8)

        // 4. Mettre à jour la fenêtre glissante
        lock.lock()
        greenWindow.append(greenRatio);  if greenWindow.count  > windowSize { greenWindow.removeFirst()  }
        yellowWindow.append(yellowRatio); if yellowWindow.count > windowSize { yellowWindow.removeFirst() }
        brownWindow.append(brownRatio);  if brownWindow.count  > windowSize { brownWindow.removeFirst()  }
        varWindow.append(variance);      if varWindow.count    > windowSize { varWindow.removeFirst()    }

        let avgG  = greenWindow.reduce(0,+)  / Double(greenWindow.count)
        let avgY  = yellowWindow.reduce(0,+) / Double(yellowWindow.count)
        let avgB  = brownWindow.reduce(0,+)  / Double(brownWindow.count)
        let avgV  = varWindow.reduce(0,+)    / Double(varWindow.count)
        lock.unlock()

        validSamples += 1

        // 5. Calculer le score de santé
        //    Idéal : beaucoup de vert, peu de jaune/brun, variance modérée
        let greenScore  = min(avgG / 0.45, 1.0)      // 45% de vert = max
        let yellowPen   = min(avgY * 3.0, 1.0)       // pénalité jaune
        let brownPen    = min(avgB * 4.0, 1.0)        // pénalité brune
        let varScore    = 1.0 - min(avgV * 3.0, 1.0) // variance trop forte → pénalité

        let rawScore = greenScore * 0.50
                     + varScore * 0.15
                     + (1.0 - yellowPen) * 0.20
                     + (1.0 - brownPen)  * 0.15

        let health = min(max(rawScore, 0.0), 1.0)

        // 6. Publier les résultats
        let progress = min(Double(validSamples) / Double(warmupFrames), 1.0)
        let willBeDone = validSamples >= warmupFrames
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.overallHealth = health
            self.timeRemaining = 1.0 - progress

            if willBeDone && self.phase != .done {
                self.phase = .done
            }

            self.metrics = [
                HealthMetric(icon: "leaf.fill",       label: "Feuillage",   value: min(avgG / 0.5, 1.0), color: .green),
                HealthMetric(icon: "exclamationmark.triangle.fill", label: "Jaunissement", value: min(avgY * 3, 1.0), color: .yellow),
                HealthMetric(icon: "drop.fill",        label: "Taches",     value: min(avgB * 3, 1.0),   color: .orange),
                HealthMetric(icon: "sparkle.magnifyingglass", label: "Uniformité", value: varScore,        color: .blue),
            ]

            self.diagnosis = self.makeDiagnosis(health: health, green: avgG, yellow: avgY, brown: avgB, variance: avgV)
            self.advice    = self.makeAdvice(health: health, yellow: avgY, brown: avgB)
        }
    }

    // MARK: - Diagnostic textuel
    private func makeDiagnosis(health: Double, green: Double, yellow: Double, brown: Double, variance: Double) -> String {
        switch health {
        case 0.80...1.0:  return "Plante en excellente santé"
        case 0.65..<0.80: return "Plante en bonne santé"
        case 0.50..<0.65: return "Signes de faiblesse légers"
        case 0.30..<0.50: return "Plante stressée — intervention conseillée"
        default:          return "Plante en mauvais état — agir rapidement"
        }
    }

    private func makeAdvice(health: Double, yellow: Double, brown: Double) -> String {
        var tips: [String] = []
        if yellow > 0.08 { tips.append("Jaunissement détecté → vérifier l'arrosage et les nutriments (azote).") }
        if brown > 0.05  { tips.append("Taches brunes → surveiller les maladies cryptogamiques ou les brûlures.") }
        if tips.isEmpty {
            switch health {
            case 0.80...: tips.append("Continuez vos soins, la plante est épanouie.")
            case 0.50..<0.80: tips.append("Ajustez les soins : lumière, eau, engrais.")
            default: tips.append("Taillez les parties abîmées et traitez avec un produit adapté.")
            }
        }
        return tips.joined(separator: "\n")
    }

    // MARK: - Outils image
    private func downscale(_ image: CIImage) -> CIImage? {
        let scaleX = downsampleSize.width  / image.extent.width
        let scaleY = downsampleSize.height / image.extent.height
        let scale = min(scaleX, scaleY)
        guard scale < 1.0 else { return image }
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(scale)
        filter.aspectRatio = 1.0
        return filter.outputImage
    }

    private func readRGBA(_ image: CIImage) -> [UInt8]? {
        let extent = image.extent
        let w = Int(extent.width), h = Int(extent.height)
        guard w > 0, h > 0 else { return nil }
        let bufSize = w * h * 4
        var data = [UInt8](repeating: 0, count: bufSize)
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        ciCtx.render(image,
                     toBitmap: &data,
                     rowBytes: w * 4,
                     bounds: extent,
                     format: .RGBA8,
                     colorSpace: colorSpace)
        return data
    }

    /// Variance locale approx : écart-type des luminosités sur un échantillon
    private func computeLocalVariance(_ pixels: [UInt8], stride s: Int) -> Double {
        var vals: [Double] = []
        var i = 0
        while i < pixels.count {
            // Luminance pondérée 0.299R + 0.587G + 0.114B
            let r = Double(pixels[i])   / 255.0
            let g = Double(pixels[i+1]) / 255.0
            let b = Double(pixels[i+2]) / 255.0
            vals.append(0.299*r + 0.587*g + 0.114*b)
            i += s * 4
        }
        guard !vals.isEmpty else { return 0 }
        let mean = vals.reduce(0,+) / Double(vals.count)
        let variance = vals.map { ($0 - mean) * ($0 - mean) }.reduce(0,+) / Double(vals.count)
        return sqrt(variance) // écart-type
    }

    // MARK: - Color space util
    private func rgbToHSL(r: Float, g: Float, b: Float) -> (h: Float, s: Float, l: Float) {
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
}

// MARK: - VUE CAMÉRA AVFoundation

struct PlantARCameraPreview: UIViewRepresentable {
    @ObservedObject var analyzer: PlantHealthAnalyzer

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black

        let session = AVCaptureSession()
        session.sessionPreset = .hd1920x1080

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return view }
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(context.coordinator, queue: DispatchQueue(label: "camera.health.queue", qos: .userInitiated))
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) { session.addOutput(output) }

        if let conn = output.connection(with: .video), conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)

        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        return view
    }

    func updateUIView(_: UIView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(analyzer: analyzer) }

    class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        let analyzer: PlantHealthAnalyzer
        init(analyzer: PlantHealthAnalyzer) { self.analyzer = analyzer }

        func captureOutput(_ output: AVCaptureOutput,
                           didOutput sampleBuffer: CMSampleBuffer,
                           from connection: AVCaptureConnection) {
            guard let buf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            analyzer.analyzePixelBuffer(buffer: buf)
        }
    }
}

// MARK: - SCANNER AVEC ANALYSE RÉELLE

struct HealthARScannerView: View {
    @StateObject private var analyzer = PlantHealthAnalyzer()
    @Environment(\.presentationMode) var presentationMode
    @State private var countdown: Double = 1.0

    var body: some View {
        ZStack {
            // Caméra pleine surface
            PlantARCameraPreview(analyzer: analyzer)
                .edgesIgnoringSafeArea(.all)

            // Viseur
            viewfinderOverlay

            // UI superposée
            VStack(spacing: 0) {
                headerBar
                Spacer()
                resultPanel
                    .padding(.bottom, 40)
            }
        }
        .onReceive(analyzer.$timeRemaining) { self.countdown = $0 }
    }

    // MARK: - Header
    private var headerBar: some View {
        HStack {
            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            Spacer()
            statusBadge
        }
        .padding(.top, 54)
        .padding(.horizontal, 20)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(analyzer.phase == .done
                 ? "Analyse terminée"
                 : "Analyse... \(Int((1.0 - countdown) * 100))%")
                .font(.caption).fontWeight(.semibold).foregroundColor(.white)
        }
        .padding(.vertical, 6).padding(.horizontal, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch analyzer.phase {
        case .waiting:  return .gray
        case .scanning: return .yellow
        case .done:     return .green
        }
    }

    // MARK: - Viseur
    private var viewfinderOverlay: some View {
        ZStack {
            // coins
            VStack {
                HStack {
                    cornerPiece(rotation: 0); Spacer(); cornerPiece(rotation: 90)
                }
                Spacer()
                HStack {
                    cornerPiece(rotation: -90); Spacer(); cornerPiece(rotation: 180)
                }
            }
            .padding(40)

            if analyzer.phase == .scanning {
                // Anneau de progression
                Circle()
                    .trim(from: 0, to: CGFloat(1.0 - analyzer.timeRemaining))
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 60, height: 60)
                    .animation(.easeInOut(duration: 0.3), value: analyzer.timeRemaining)
            }

            Image(systemName: analyzer.phase == .done ? "checkmark" : "plus")
                .font(.system(size: 22, weight: .thin))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private func cornerPiece(rotation: Double) -> some View {
        Image(systemName: "viewfinder")
            .font(.system(size: 32, weight: .ultraLight))
            .foregroundColor(.white)
            .rotationEffect(.degrees(rotation))
    }

    // MARK: - Panneau de résultat
    private var resultPanel: some View {
        VStack(spacing: 16) {
            // Mini graphique de santé
            healthGauge

            if analyzer.phase == .done {
                // Détails
                metricsGrid

                // Diagnostic + conseil
                VStack(spacing: 8) {
                    Label(analyzer.diagnosis, systemImage: analyzer.overallHealth > 0.65
                          ? "leaf.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(analyzer.overallHealth > 0.65 ? .green : .orange)

                    if !analyzer.advice.isEmpty {
                        Text(analyzer.advice)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                }
                .padding(.horizontal, 8)

                // Bouton refaire
                Button(action: analyzer.resetAnalysis) {
                    Text("Refaire l'analyse")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, 10).padding(.horizontal, 24)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .cornerRadius(28)
        .padding(.horizontal, 20)
    }

    // MARK: - Jauge de santé
    private var healthGauge: some View {
        VStack(spacing: 6) {
            Text("\(Int(analyzer.overallHealth * 100))%")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(healthColor)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2)).frame(height: 8)
                Capsule()
                    .fill(LinearGradient(colors: [.red, .orange, .yellow, .green],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, 280 * analyzer.overallHealth), height: 8)
                    .animation(.easeOut(duration: 0.5), value: analyzer.overallHealth)
            }
            .frame(width: 280)
        }
    }

    private var healthColor: Color {
        if analyzer.overallHealth > 0.80 { return .green }
        if analyzer.overallHealth > 0.60 { return Color(hex: "#84CC16") }
        if analyzer.overallHealth > 0.40 { return .orange }
        return .red
    }

    // MARK: - Grille de métriques
    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(analyzer.metrics) { metric in
                metricCell(metric)
            }
        }
    }

    private func metricCell(_ m: PlantHealthAnalyzer.HealthMetric) -> some View {
        HStack(spacing: 8) {
            Image(systemName: m.icon)
                .font(.system(size: 14))
                .foregroundColor(m.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.label).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.7))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15)).frame(height: 4)
                        Capsule().fill(m.color).frame(width: geo.size.width * m.value, height: 4)
                    }
                }.frame(height: 4)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .cornerRadius(10)
    }
}

// MARK: - Pièces détachées

struct PlantScannerCorner: View {
    let rotation: Double
    var body: some View {
        Image(systemName: "viewfinder")
            .font(.system(size: 32, weight: .ultraLight))
            .foregroundColor(.white)
            .rotationEffect(.degrees(rotation))
    }
}

// MARK: - VUE SANTÉ PRINCIPALE (inchangée)

struct SanteDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    let health: HealthInfo?
    @State private var showARScanner = false

    var body: some View {
        ZStack {
            themeManager.backgroundColor.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerHero

                    if let health = health {
                        if hasProblemInfo(health: health) { problemsSection(health: health) }
                        if hasPestInfo(health: health) { pestsSection(health: health) }
                        if hasPreventionInfo(health: health) { preventionSection(health: health) }
                        outilsUtilesSection
                        scanSanteCTA
                    } else {
                        HealthSectionCard(
                            icon: "cross.case.fill", iconColor: Color(hex: "#F97316"),
                            title: NSLocalizedString("HEALTHDETAIL_INFO_UNAVAILABLE_TITLE", comment: "")
                        ) {
                            Text(NSLocalizedString("HEALTHDETAIL_INFO_UNAVAILABLE_BODY", comment: ""))
                                .font(.system(size: 14)).foregroundColor(secondaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        outilsUtilesSection
                        scanSanteCTA
                    }
                }
                .padding(.top, 16).padding(.horizontal, 16).padding(.bottom, 32)
            }
        }
        .fullScreenCover(isPresented: $showARScanner) {
            HealthARScannerView()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(NSLocalizedString("HEALTHDETAIL_NAV_TITLE", comment: ""))
    }

    // --- Helpers ---
    private var primaryTextColor: Color { colorScheme == .dark ? .white : .black }
    private var secondaryTextColor: Color { colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7) }
    private var headerSubtitle: String {
        if let first = health?.commonProblems?.first, !first.isEmpty { return first }
        if let first = health?.pests?.first, !first.isEmpty { return first }
        return NSLocalizedString("HEALTHDETAIL_HEADER_DEFAULT_SUBTITLE", comment: "")
    }

    // HEADER
    private var headerHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#7F1D1D"), Color(hex: "#450A0A")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 10)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.10)).frame(width: 64, height: 64)
                        Image(systemName: "cross.case.fill").font(.system(size: 30)).foregroundColor(Color(hex: "#F97316"))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("HEALTHDETAIL_HEADER_TITLE", comment: "")).font(.system(size: 24, weight: .bold)).foregroundColor(.white)
                        Text(headerSubtitle).font(.system(size: 14, weight: .medium)).foregroundColor(.white.opacity(0.85)).lineLimit(1)
                    }
                    Spacer()
                }
                if let health = health, hasProblemInfo(health: health) || hasPestInfo(health: health) {
                    Divider().background(Color.white.opacity(0.15))
                    HStack(spacing: 10) {
                        if let count = health.commonProblems?.count, count > 0 {
                            let txt = String(format: NSLocalizedString("HEALTHDETAIL_HEADER_PROBLEMS_COUNT_FORMAT", comment: ""), count)
                            HealthHeaderPill(icon: "exclamationmark.triangle.fill", text: txt)
                        }
                        if let count = health.pests?.count, count > 0 {
                            let txt = String(format: NSLocalizedString("HEALTHDETAIL_HEADER_PESTS_COUNT_FORMAT", comment: ""), count)
                            HealthHeaderPill(icon: "ant.fill", text: txt)
                        }
                    }
                } else {
                    Text(NSLocalizedString("HEALTHDETAIL_HEADER_FALLBACK_TEXT", comment: "")).font(.system(size: 13)).foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
    }

    // SECTIONS
    private func hasProblemInfo(health: HealthInfo) -> Bool { (health.commonProblems?.count ?? 0) > 0 || (health.symptomsAndCauses?.count ?? 0) > 0 }
    private func problemsSection(health: HealthInfo) -> some View {
        HealthSectionCard(icon: "exclamationmark.triangle.fill", iconColor: Color(hex: "#F97316"), title: NSLocalizedString("HEALTHDETAIL_SECTION_PROBLEMS_TITLE", comment: "")) {
            VStack(alignment: .leading, spacing: 12) {
                if let problems = health.commonProblems {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("HEALTHDETAIL_SECTION_PROBLEMS_COMMON_TITLE", comment: "")).font(.system(size: 15, weight: .semibold)).foregroundColor(primaryTextColor)
                        ForEach(problems, id: \.self) { HealthBulletRow(text: $0) }
                    }
                }
                if let symptoms = health.symptomsAndCauses {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("HEALTHDETAIL_SECTION_PROBLEMS_SYMPTOMS_TITLE", comment: "")).font(.system(size: 15, weight: .semibold)).foregroundColor(primaryTextColor)
                        ForEach(symptoms, id: \.self) { HealthBulletRow(text: $0) }
                    }.padding(.top, 6)
                }
            }
        }
    }

    private func hasPestInfo(health: HealthInfo) -> Bool { (health.pests?.count ?? 0) > 0 || (health.treatments?.count ?? 0) > 0 }
    private func pestsSection(health: HealthInfo) -> some View {
        HealthSectionCard(icon: "ant.fill", iconColor: Color(hex: "#22C55E"), title: NSLocalizedString("HEALTHDETAIL_SECTION_PESTS_TITLE", comment: "")) {
            VStack(alignment: .leading, spacing: 12) {
                if let pests = health.pests {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("HEALTHDETAIL_SECTION_PESTS_COMMON_TITLE", comment: "")).font(.system(size: 15, weight: .semibold)).foregroundColor(primaryTextColor)
                        WrapTagCloud(items: pests)
                    }
                }
                if let treatments = health.treatments {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("HEALTHDETAIL_SECTION_PESTS_TREATMENTS_TITLE", comment: "")).font(.system(size: 15, weight: .semibold)).foregroundColor(primaryTextColor)
                        ForEach(treatments, id: \.self) { HealthBulletRow(text: $0) }
                    }.padding(.top, 8)
                }
            }
        }
    }

    private func hasPreventionInfo(health: HealthInfo) -> Bool { (health.prevention?.count ?? 0) > 0 }
    private func preventionSection(health: HealthInfo) -> some View {
        HealthSectionCard(icon: "shield.lefthalf.filled", iconColor: Color(hex: "#22C55E"), title: NSLocalizedString("HEALTHDETAIL_SECTION_PREVENTION_TITLE", comment: "")) {
            if let prevention = health.prevention { ForEach(prevention, id: \.self) { HealthBulletRow(text: $0) } }
        }
    }

    private var outilsUtilesSection: some View {
        HealthSectionCard(icon: "wrench.and.screwdriver.fill", iconColor: Color(hex: "#38BDF8"), title: NSLocalizedString("HEALTHDETAIL_TOOLS_TITLE", comment: "")) {
            VStack(alignment: .leading, spacing: 12) {
                HealthToolRow(systemIcon: "magnifyingglass", title: NSLocalizedString("HEALTHDETAIL_TOOLS_MAGNIFIER_TITLE", comment: ""), subtitle: NSLocalizedString("HEALTHDETAIL_TOOLS_MAGNIFIER_SUBTITLE", comment: ""))
                HealthToolRow(systemIcon: "camera.viewfinder", title: NSLocalizedString("HEALTHDETAIL_TOOLS_PHOTOS_TITLE", comment: ""), subtitle: NSLocalizedString("HEALTHDETAIL_TOOLS_PHOTOS_SUBTITLE", comment: ""))
            }
        }
    }

    private var scanSanteCTA: some View {
        Button(action: { showARScanner = true }) {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                Text(NSLocalizedString("HEALTHDETAIL_CTA_SCAN_TITLE", comment: ""))
            }
            .font(.system(size: 16, weight: .semibold)).foregroundColor(.black).padding(.vertical, 14).frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [Color(hex: "#BBF7D0"), Color(hex: "#4ADE80")], startPoint: .leading, endPoint: .trailing))
            .cornerRadius(22).shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 6)
        }.padding(.horizontal, 20)
    }
}

// MARK: - Subviews
private struct HealthSectionCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String; let iconColor: Color; let title: String; let content: Content
    init(icon: String, iconColor: Color, title: String, @ViewBuilder content: () -> Content) { self.icon = icon; self.iconColor = iconColor; self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack { Circle().fill(iconColor.opacity(0.18)).frame(width: 40, height: 40); Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundColor(iconColor) }
                Text(title).font(.system(size: 18, weight: .semibold)).foregroundColor(colorScheme == .dark ? .white : .black); Spacer()
            }
            content
        }.padding(16).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color(red: 0.95, green: 0.95, blue: 0.96)).overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1)))
    }
}
private struct HealthBulletRow: View {
    @Environment(\.colorScheme) private var cs; let text: String
    var body: some View { HStack(alignment: .top, spacing: 8) { Image(systemName: "circle.fill").font(.system(size: 6)).foregroundColor(Color(hex: "#F97316")).padding(.top, 5); Text(text).font(.system(size: 13)).foregroundColor(cs == .dark ? .white.opacity(0.8) : .black.opacity(0.8)).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 0) } }
}
private struct HealthToolRow: View {
    @Environment(\.colorScheme) private var cs; let systemIcon: String; let title: String; let subtitle: String
    var body: some View { HStack(alignment: .top, spacing: 12) { Image(systemName: systemIcon).font(.system(size: 18)).foregroundColor(Color(hex: "#38BDF8")).frame(width: 24); VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(cs == .dark ? .white : .black); Text(subtitle).font(.system(size: 13)).foregroundColor(cs == .dark ? .white.opacity(0.7) : .black.opacity(0.7)).fixedSize(horizontal: false, vertical: true) }; Spacer(minLength: 0) } }
}
private struct HealthHeaderPill: View { let icon: String; let text: String; var body: some View { HStack(spacing: 6) { Image(systemName: icon).font(.system(size: 13, weight: .semibold)); Text(text).font(.system(size: 13, weight: .medium)) }.foregroundColor(.white).padding(.vertical, 5).padding(.horizontal, 10).background(Color.white.opacity(0.12)).clipShape(Capsule()) } }
private struct WrapTagCloud: View {
    @Environment(\.colorScheme) private var cs; let items: [String]
    var body: some View { LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) { ForEach(items, id: \.self) { item in Text(item).font(.system(size: 12, weight: .medium)).foregroundColor(cs == .dark ? .white.opacity(0.8) : .black.opacity(0.8)).padding(.vertical, 5).padding(.horizontal, 10).background(Capsule().fill(Color.white.opacity(0.04))) } } }
}
