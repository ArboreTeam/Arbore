import SwiftUI
import Vision
import AVFoundation

// MARK: - PARTIE 1 : MOTEUR D'ANALYSE STABILISÉ

class PlantHealthAnalyzer: NSObject, ObservableObject {
    // Variables publiées pour l'UI
    @Published var diagnosedIssue: String = L10n.t("HEALTH_SCAN_CALIBRATING")
    @Published var confidenceLevel: Double = 0.0 // Valeur lissée pour l'affichage
    @Published var isHealthy: Bool = true
    @Published var scientificName: String = L10n.t("HEALTH_SCAN_INITIALIZING")
    
    // Variables internes pour la logique
    private var targetConfidence: Double = 0.0
    private var stabilizationTimer: Timer?
    
    // MODE DÉMO / TEST
    // Permet de forcer un état pour tester sans plante réelle
    enum ForceMode {
        case auto // Comportement aléatoire simulant l'IA
        case forceHealthy // Force le résultat sain
        case forceSick // Force le résultat malade
    }
    var currentMode: ForceMode = .auto
    
    override init() {
        super.init()
        startStabilizationLoop()
    }
    
    // Cette boucle tourne 60 fois par seconde pour animer la jauge de manière fluide
    private func startStabilizationLoop() {
        stabilizationTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // FORMULE DE LISSAGE (Linear Interpolation)
            // On déplace la valeur actuelle vers la cible de 5% à chaque frame
            // Cela empêche la barre de "sauter", elle glisse.
            let step = 0.05
            self.confidenceLevel = self.confidenceLevel + (self.targetConfidence - self.confidenceLevel) * step
        }
    }
    
    // Appelé à chaque frame de la caméra
    func analyzePixelBuffer(buffer: CVPixelBuffer) {
        // On ne fait le calcul "lourd" (simulation) que de temps en temps pour ne pas surcharger
        // Ici on simule juste la mise à jour de la cible
        
        DispatchQueue.main.async {
            switch self.currentMode {
            case .forceHealthy:
                self.setResult(healthy: true, confidence: 0.95)
                
            case .forceSick:
                self.setResult(healthy: false, confidence: 0.92)
                
            case .auto:
                // Simulation d'une fluctuation naturelle (comme si l'IA cherchait)
                // Change légèrement la cible aléatoirement
                let randomFluctuation = Double.random(in: 0.4...0.7) // Valeurs basses par défaut (incertitude)
                self.targetConfidence = randomFluctuation
                
                if self.confidenceLevel < 0.6 {
                    self.diagnosedIssue = L10n.t("HEALTH_SCAN_ANALYZING_SURFACE")
                    self.scientificName = L10n.t("HEALTH_SCAN_IN_PROGRESS")
                    self.isHealthy = true
                }
            }
        }
    }
    
    // Helper pour définir les résultats proprement
    private func setResult(healthy: Bool, confidence: Double) {
        self.targetConfidence = confidence
        self.isHealthy = healthy
        
        if healthy {
            self.diagnosedIssue = L10n.t("HEALTH_SCAN_HEALTHY_DETECTED")
            self.scientificName = "Plantae Sanus"
        } else {
            self.diagnosedIssue = L10n.t("HEALTH_SCAN_MILDEW_DETECTED")
            self.scientificName = "Plasmopara viticola"
        }
    }
    
    // Fonctions pour les boutons de test
    func forceHealthyState() {
        currentMode = .forceHealthy
    }
    
    func forceSickState() {
        currentMode = .forceSick
    }
    
    func resetAuto() {
        currentMode = .auto
        targetConfidence = 0.0
    }
}

// MARK: - PARTIE 2 : VUE CAMÉRA (Technique)

struct PlantARCameraPreview: UIViewRepresentable {
    @ObservedObject var analyzer: PlantHealthAnalyzer
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black
        
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .hd1920x1080
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return view }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch { return view }
        
        if (captureSession.canAddInput(videoInput)) { captureSession.addInput(videoInput) }
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(context.coordinator, queue: DispatchQueue(label: "videoQueue"))
        if (captureSession.canAddOutput(videoOutput)) { captureSession.addOutput(videoOutput) }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        DispatchQueue.global(qos: .userInitiated).async { captureSession.startRunning() }
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(analyzer: analyzer) }
    
    class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        var analyzer: PlantHealthAnalyzer
        init(analyzer: PlantHealthAnalyzer) { self.analyzer = analyzer }
        
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            analyzer.analyzePixelBuffer(buffer: pixelBuffer)
        }
    }
}

// MARK: - PARTIE 3 : INTERFACE AR AVEC MODE TEST

struct HealthARScannerView: View {
    @StateObject private var analyzer = PlantHealthAnalyzer()
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            // 1. Caméra
            PlantARCameraPreview(analyzer: analyzer)
                .edgesIgnoringSafeArea(.all)
            
            // 2. Grille HUD (Visée)
            VStack {
                HStack {
                    PlantScannerCorner(rotation: 0); Spacer(); PlantScannerCorner(rotation: 90)
                }
                Spacer()
                Image(systemName: "plus").font(.system(size: 24, weight: .thin)).foregroundColor(.white.opacity(0.5))
                Spacer()
                HStack {
                    PlantScannerCorner(rotation: -90); Spacer(); PlantScannerCorner(rotation: 180)
                }
            }
            .padding(50)
            .opacity(0.6)
            
            // 3. UI Principale
            VStack {
                // Header
                HStack {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Circle().fill(.ultraThinMaterial).frame(width: 44, height: 44)
                            .overlay(Image(systemName: "xmark").foregroundColor(.white))
                    }
                    Spacer()
                    Text(L10n.t("HEALTH_SCAN_TITLE"))
                        .font(.caption2).fontWeight(.heavy)
                        .padding(8).background(.ultraThinMaterial).cornerRadius(8).foregroundColor(.white)
                }
                .padding(.top, 50).padding(.horizontal)
                
                Spacer()
                
                // PANEL DE RÉSULTAT
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Image(systemName: analyzer.isHealthy ? "leaf.fill" : "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundColor(analyzer.isHealthy ? .green : .orange)
                            .padding(10)
                            .background(Circle().fill(Color.white.opacity(0.2)))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(analyzer.diagnosedIssue)
                                .font(.headline).foregroundColor(.white).lineLimit(2)
                            Text(analyzer.scientificName)
                                .font(.caption).italic().foregroundColor(.white.opacity(0.7))
                        }
                    }
                    
                    Divider().background(Color.white.opacity(0.3))
                    
                    HStack {
                        Text(L10n.t("HEALTH_SCAN_CONFIDENCE")).font(.caption).foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(Int(analyzer.confidenceLevel * 100))%")
                            .font(.caption).bold().foregroundColor(colorForConfidence(analyzer.confidenceLevel))
                    }
                    
                    // Jauge personnalisée fluide
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.3)).frame(height: 6)
                            Capsule().fill(
                                LinearGradient(colors: [.orange, .green], startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: geo.size.width * analyzer.confidenceLevel, height: 6)
                            // L'animation est gérée par le Timer dans l'analyzer pour la fluidité
                        }
                    }
                    .frame(height: 6)
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .cornerRadius(24)
                .padding(.horizontal)
                
                // 4. BOUTONS DE TEST (DEBUG MODE)
                // C'est ici que tu peux forcer le résultat
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Text(L10n.t("HEALTH_SCAN_TEST_MODE"))
                            .font(.caption).fontWeight(.bold).foregroundColor(.white)
                            .padding(.leading)
                        
                        Button(action: { analyzer.forceHealthyState() }) {
                            Text(L10n.t("HEALTH_SCAN_FORCE_HEALTHY"))
                                .font(.caption).bold()
                                .padding(.vertical, 8).padding(.horizontal, 12)
                                .background(Color.green.opacity(0.8)).cornerRadius(20).foregroundColor(.white)
                        }
                        
                        Button(action: { analyzer.forceSickState() }) {
                            Text(L10n.t("HEALTH_SCAN_FORCE_SICK"))
                                .font(.caption).bold()
                                .padding(.vertical, 8).padding(.horizontal, 12)
                                .background(Color.orange.opacity(0.8)).cornerRadius(20).foregroundColor(.white)
                        }
                        
                        Button(action: { analyzer.resetAuto() }) {
                            Text(L10n.t("HEALTH_SCAN_RESET_AUTO"))
                                .font(.caption).bold()
                                .padding(.vertical, 8).padding(.horizontal, 12)
                                .background(Color.gray.opacity(0.8)).cornerRadius(20).foregroundColor(.white)
                        }
                    }
                    .padding(.vertical, 20)
                }
                .background(Color.black.opacity(0.5))
            }
        }
    }
    
    func colorForConfidence(_ level: Double) -> Color {
        if level > 0.8 { return .green }
        if level > 0.5 { return .yellow }
        return .red
    }
}

struct PlantScannerCorner: View {
    let rotation: Double
    var body: some View {
        Image(systemName: "viewfinder")
            .font(.system(size: 32, weight: .ultraLight))
            .foregroundColor(.white)
            .rotationEffect(.degrees(rotation))
    }
}

// MARK: - PARTIE 4 : VUE PRINCIPALE INTÉGRÉE (Inchangée mais nécessaire)

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
            HealthARScannerView() // Ouvre la nouvelle vue avec Debug Buttons
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(NSLocalizedString("HEALTHDETAIL_NAV_TITLE", comment: ""))
    }

    // --- Helpers de la vue principale ---
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

// Subviews minimales
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
