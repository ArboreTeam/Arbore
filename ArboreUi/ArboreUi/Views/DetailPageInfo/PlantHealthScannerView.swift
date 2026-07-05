//
//  PlantHealthScannerView.swift
//  ArboreUi
//
//  Scanner de santé de plante avec design Liquid Glass.
//  Gère la caméra (y compris simulateur), l'UI de capture,
//  l'état de chargement, et l'affichage riche des résultats.
//

import SwiftUI
import AVFoundation
import CoreImage

// MARK: - ═══════════════════════════════════════════════════════
// MARK: CAMERA MANAGER
// MARK: ═══════════════════════════════════════════════════════

final class ScannerCameraManager: NSObject, ObservableObject {
    @Published var isCameraReady = false
    @Published var capturedImage: UIImage?
    @Published var permissionDenied = false

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "scanner.camera.session", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "scanner.camera.video", qos: .userInitiated)

    var onFrame: ((CVPixelBuffer) -> Void)?
    private var frameCounter = 0
    private let frameSkip = 12

    func start() {
        #if targetEnvironment(simulator)
        DispatchQueue.main.async {
            self.isCameraReady = true
        }
        #else
        checkPermissionAndSetup()
        #endif
    }

    func stop() {
        #if !targetEnvironment(simulator)
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
        #endif
    }

    func capturePhoto() {
        #if targetEnvironment(simulator)
        // Image factice pour le simulateur
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let rect = CGRect(x: 0, y: 0, width: 800, height: 800)
            UIGraphicsBeginImageContextWithOptions(rect.size, false, 1.0)
            UIColor(hex: "#4ADE80").setFill()
            UIRectFill(rect)
            let img = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            self?.capturedImage = img
        }
        #else
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .auto
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
        #endif
    }

    private func checkPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.setupSession() }
                else { DispatchQueue.main.async { self?.permissionDenied = true } }
            }
        default: DispatchQueue.main.async { [weak self] in self?.permissionDenied = true }
        }
    }

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.session.isRunning else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                self.session.commitConfiguration()
                return
            }

            if self.session.canAddInput(input) { self.session.addInput(input) }
            if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }

            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            if self.session.canAddOutput(self.videoOutput) { self.session.addOutput(self.videoOutput) }

            if let conn = self.videoOutput.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
                } else {
                    if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
                }
            }

            self.session.commitConfiguration()
            self.session.startRunning()

            DispatchQueue.main.async { self.isCameraReady = true }
        }
    }
}

extension ScannerCameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        let croppedImage = cropToCenterSquare(image)
        DispatchQueue.main.async { [weak self] in self?.capturedImage = croppedImage }
    }
    
    private func cropToCenterSquare(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let cropSide = min(width, height) * 0.65 // Le carré central
        let cropRect = CGRect(x: (width - cropSide) / 2, y: (height - cropSide) / 2, width: cropSide, height: cropSide)
        if let cropped = cgImage.cropping(to: cropRect) {
            return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
        }
        return image
    }
}

extension ScannerCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCounter += 1
        guard frameCounter % frameSkip == 0, let buf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(buf)
    }
}

// MARK: - ═══════════════════════════════════════════════════════
// MARK: CAMERA PREVIEW
// MARK: ═══════════════════════════════════════════════════════

struct ScannerCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}

    class CameraPreviewUIView: UIView {
        var session: AVCaptureSession? {
            didSet {
                #if !targetEnvironment(simulator)
                if let session = session { previewLayer.session = session }
                #endif
            }
        }

        private let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            #if targetEnvironment(simulator)
            backgroundColor = UIColor(white: 0.12, alpha: 1.0)
            let label = UILabel()
            label.text = "Simulateur\n(Appuyez pour simuler une capture)"
            label.textColor = .white
            label.numberOfLines = 0
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
            #else
            backgroundColor = .black
            previewLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(previewLayer)
            #endif
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            #if !targetEnvironment(simulator)
            previewLayer.frame = bounds
            #endif
        }
    }
}

// MARK: - ═══════════════════════════════════════════════════════
// MARK: LIQUID GLASS MODIFIER
// MARK: ═══════════════════════════════════════════════════════

struct LiquidGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.05), .clear, .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 12)
    }
}

extension View {
    func liquidGlass() -> some View {
        modifier(LiquidGlassModifier())
    }
}

// MARK: - ═══════════════════════════════════════════════════════
// MARK: SCANNER VIEW
// MARK: ═══════════════════════════════════════════════════════

struct PlantHealthScannerView: View {
    var plantName: String?

    @StateObject private var scanner = PlantHealthScanner()
    @StateObject private var camera = ScannerCameraManager()
    @State private var loadingStep = 0
    @Environment(\.dismiss) private var dismiss
    @State private var showResultAnimation = false
    @State private var pulseCorners = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch scanner.phase {
            case .preview, .capturing:
                cameraPreviewPhase
            case .analyzing:
                analyzingPhase
            case .result:
                if let result = scanner.result { resultPhase(result) }
            case .error:
                if let error = scanner.error { errorPhase(error) }
            }
        }
        .onAppear {
            scanner.plantName = plantName
            camera.onFrame = { [weak scanner] buffer in
                scanner?.updateRealtimeIndicators(from: buffer)
            }
            // Forcer brightness OK sur simulateur
            #if targetEnvironment(simulator)
            scanner.brightnessOK = true
            #endif
            camera.start()
        }
        .onDisappear { camera.stop() }
        .onChange(of: camera.capturedImage) { _, newImage in
            if let image = newImage { Task { await scanner.analyze(image: image) } }
        }
        .statusBarHidden()
    }

    // MARK: ─── CAMERA PREVIEW PHASE ───

    private var cameraPreviewPhase: some View {
        ZStack {
            if camera.permissionDenied {
                permissionDeniedView
            } else {
                ScannerCameraPreview(session: camera.session).ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Barre supérieure
                glassTopBar
                    .padding(.top, 50)
                    .padding(.horizontal, 16)
                
                Spacer()

                // Viseur centré
                viewfinderFrame
                    .padding(.horizontal, 50)

                Spacer()

                // Panneau de contrôle du bas
                glassBottomPanel
                    .padding(.bottom, 40)
                    .padding(.horizontal, 20)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseCorners = true
            }
        }
    }

    private var glassTopBar: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            Spacer()
            if let name = plantName, !name.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill").font(.system(size: 12)).foregroundStyle(.green)
                    Text(name).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                }
                .padding(.vertical, 10).padding(.horizontal, 16)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            Spacer()
            Image(systemName: scanner.brightnessOK ? "sun.max.fill" : "sun.min.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(scanner.brightnessOK ? .green : .orange)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .animation(.easeInOut(duration: 0.3), value: scanner.brightnessOK)
        }
    }

    private var viewfinderFrame: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                cornerBrackets(size: size).opacity(pulseCorners ? 1.0 : 0.4)
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .ultraLight))
                    .foregroundColor(.white.opacity(0.4))
                VStack {
                    Spacer()
                    Text(scanner.brightnessOK
                         ? NSLocalizedString("SCAN_GUIDE_TEXT", value: "Cadrez le feuillage", comment: "")
                         : NSLocalizedString("SCAN_GUIDE_LIGHT", value: "Plus de lumière requise", comment: ""))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.vertical, 8).padding(.horizontal, 16)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .offset(y: 40)
                }
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }.aspectRatio(1, contentMode: .fit)
    }

    private func cornerBrackets(size: CGFloat) -> some View {
        let len: CGFloat = 36; let lw: CGFloat = 3
        let color = scanner.brightnessOK ? Color.white : Color.orange
        return ZStack {
            ForEach(0..<4, id: \.self) { i in
                CornerBracketShape(cornerLength: len)
                    .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
        }
    }

    private var glassBottomPanel: some View {
        VStack(spacing: 14) {
            Button(action: {
                guard scanner.phase == .preview else { return }
                scanner.phase = .capturing
                camera.capturePhoto()
            }) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.2)).frame(width: 80, height: 80)
                    Circle().stroke(Color.white.opacity(0.8), lineWidth: 4).frame(width: 80, height: 80)
                    Circle().fill(Color.white).frame(width: 64, height: 64)
                    Image(systemName: "camera.macro").font(.system(size: 26, weight: .semibold)).foregroundColor(.black.opacity(0.8))
                }
            }
            .disabled(scanner.phase == .capturing)
            .scaleEffect(scanner.phase == .capturing ? 0.9 : 1.0)
            .animation(.spring(response: 0.3), value: scanner.phase)

            Text(NSLocalizedString("SCAN_CAPTURE_HINT", value: "Appuyez pour scanner la plante", comment: ""))
                .font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.7))
        }
        .padding(.vertical, 24).padding(.horizontal, 40)
        .liquidGlass()
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.system(size: 44)).foregroundColor(.white.opacity(0.3))
            Text("Accès caméra requis").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
            Button("Ouvrir les Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }.padding().background(Color.white, in: Capsule()).foregroundColor(.black)
        }
    }

    // MARK: ─── ANALYZING PHASE ───

    private var analyzingPhase: some View {
        ZStack {
            if let image = camera.capturedImage {
                Image(uiImage: image).resizable().scaledToFill().ignoresSafeArea()
                    .blur(radius: 40).overlay(Color.black.opacity(0.4))
            }

            VStack(spacing: 32) {
                Spacer()

                ZStack {
                    if let image = camera.capturedImage {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Color.white.opacity(0.3), lineWidth: 2))
                            .shadow(color: .black.opacity(0.3), radius: 20)
                    }
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 4).frame(width: 160, height: 160)
                    Circle().trim(from: 0, to: 0.25).stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 160, height: 160).rotationEffect(.degrees(pulseCorners ? 360 : 0))
                        .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: pulseCorners)
                }

                VStack(spacing: 8) {
                    Text("Analyse en cours…").font(.system(size: 24, weight: .bold)).foregroundColor(.white)
                    Text("Intelligence Artificielle & Colorimétrie").font(.system(size: 15)).foregroundColor(.white.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 16) {
                    stepRow(icon: loadingStep >= 1 ? "checkmark.circle.fill" : "circle.dotted", text: "Qualité d'image validée", done: loadingStep >= 1)
                    stepRow(icon: loadingStep >= 2 ? "checkmark.circle.fill" : "circle.dotted", text: "Plante détectée", done: loadingStep >= 2)
                    stepRow(icon: loadingStep >= 3 ? "checkmark.circle.fill" : "circle.dotted", text: "Analyse colorimétrique…", done: loadingStep >= 3)
                    stepRow(icon: loadingStep >= 4 ? "checkmark.circle.fill" : "circle.dotted", text: "Diagnostic IA en cours…", done: loadingStep >= 4)
                }
                .padding(24)
                .liquidGlass()
                .padding(.horizontal, 32)
                .onAppear {
                    loadingStep = 0
                    withAnimation(.easeInOut(duration: 0.5).delay(0.5)) { loadingStep = 1 }
                    withAnimation(.easeInOut(duration: 0.5).delay(1.2)) { loadingStep = 2 }
                    withAnimation(.easeInOut(duration: 0.5).delay(2.5)) { loadingStep = 3 }
                }

                Spacer()
            }
        }
    }

    private func stepRow(icon: String, text: String, done: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium))
                .foregroundColor(done ? .green : .white.opacity(0.3)).frame(width: 24)
            Text(text).font(.system(size: 15, weight: done ? .semibold : .regular))
                .foregroundColor(done ? .white : .white.opacity(0.4))
        }
    }

    // MARK: ─── RESULT PHASE ───

    private func resultPhase(_ result: PlantHealthScanResult) -> some View {
        ZStack {
            if let image = camera.capturedImage {
                Image(uiImage: image).resizable().scaledToFill().ignoresSafeArea()
                    .blur(radius: 50).overlay(Color.black.opacity(0.5))
            }

            VStack(spacing: 0) {
                // Top bar fixe
                resultTopBar(result)
                    .padding(.top, 50).padding(.horizontal, 16).padding(.bottom, 10)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        scoreGlassCard(result)
                        if !result.qualityWarnings.isEmpty { warningsGlass(result.qualityWarnings) }
                        if let species = result.species, species.lowercased() != "null", species.lowercased() != "unknown" { speciesGlass(species) }
                        if !result.diseases.isEmpty { diseasesGlass(result.diseases) }
                        colorimetryGlass(result.metrics)
                        if !result.recommendations.isEmpty { recommendationsGlass(result.recommendations) }
                        Color.clear.frame(height: 100) // Espace pour boutons fixes
                    }
                    .padding(.horizontal, 16)
                    .frame(width: UIScreen.main.bounds.width) // Empêche le débordement horizontal
                }
            }

            // Boutons fixés en bas
            VStack {
                Spacer()
                actionButtonsGlass
                    .padding(.horizontal, 16)
                    .padding(.bottom, 34)
                    .frame(width: UIScreen.main.bounds.width)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.8).delay(0.2)) { showResultAnimation = true } }
    }

    private func resultTopBar(_ result: PlantHealthScanResult) -> some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(.white).frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle()).overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: result.isUncertain ? "questionmark.circle.fill" : "checkmark.seal.fill").font(.system(size: 12))
                Text(result.isUncertain ? "Incertain" : "Fiable").font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(result.isUncertain ? .orange : .green).padding(.vertical, 8).padding(.horizontal, 14)
            .background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
            Spacer()
            Image(systemName: result.source == .gemini ? "sparkles" : "eyedropper").font(.system(size: 14)).foregroundColor(.white.opacity(0.7))
                .frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle()).overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
        }
    }

    private func scoreGlassCard(_ result: PlantHealthScanResult) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.06), lineWidth: 14).frame(width: 150, height: 150)
                Circle().trim(from: 0, to: showResultAnimation ? result.overallHealth : 0)
                    .stroke(AngularGradient(colors: [healthColor(result.overallHealth).opacity(0.3), healthColor(result.overallHealth)], center: .center), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .frame(width: 150, height: 150).rotationEffect(.degrees(-90)).animation(.easeOut(duration: 1.2), value: showResultAnimation)
                VStack(spacing: 0) {
                    Text("\(Int(result.overallHealth.isNaN ? 0 : result.overallHealth * 100))").font(.system(size: 48, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Text("/ 100").font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.5))
                }
            }
            Text(diagnosisText(for: result.overallHealth)).font(.system(size: 20, weight: .bold)).foregroundColor(healthColor(result.overallHealth))
            HStack(spacing: 8) {
                Text("Indice de confiance IA").font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.5))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1)).frame(height: 6)
                        Capsule().fill(Color.white.opacity(0.7)).frame(width: max(6, geo.size.width * result.confidence), height: 6)
                    }
                }.frame(height: 6)
                Text("\(Int(result.confidence.isNaN ? 0 : result.confidence * 100))%").font(.system(size: 13, weight: .bold)).foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(24).liquidGlass()
    }

    private func warningsGlass(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).padding(.top, 2)
                    Text(warning)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.orange.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.orange.opacity(0.1)).overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.orange.opacity(0.3), lineWidth: 1)))
    }

    private func speciesGlass(_ species: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "leaf.fill").font(.system(size: 18)).foregroundColor(.green).frame(width: 44, height: 44).background(Color.green.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("Espèce identifiée").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.5))
                Text(species).font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
            }
            Spacer()
        }.padding(20).liquidGlass()
    }

    private func diseasesGlass(_ diseases: [DetectedDisease]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "microbe.fill").font(.system(size: 16)).foregroundColor(.orange)
                Text("Problèmes détectés").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Text("\(diseases.count)").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    .frame(width: 28, height: 28).background(Color.orange, in: Circle())
            }
            ForEach(diseases) { disease in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(disease.name).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        Spacer()
                        Text("\(Int(disease.confidence.isNaN ? 0 : disease.confidence * 100))%").font(.system(size: 12, weight: .bold)).foregroundColor(.white.opacity(0.5))
                    }
                    HStack(spacing: 10) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.1)).frame(height: 6)
                                Capsule().fill(severityGradient(disease.severity)).frame(width: max(6, geo.size.width * disease.severity), height: 6)
                            }
                        }.frame(height: 6)
                        Text("\(Int(disease.severity.isNaN ? 0 : disease.severity * 100))%").font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.5)).frame(width: 38, alignment: .trailing)
                    }
                }.padding(14).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
            }
        }.padding(20).liquidGlass()
    }

    private func colorimetryGlass(_ metrics: ColorimetricResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "paintpalette.fill").font(.system(size: 16)).foregroundColor(.cyan)
                Text("Analyse colorimétrique locale").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                metricPill(icon: "leaf.fill", label: "Sain", value: metrics.greenRatio, color: .green)
                metricPill(icon: "sun.min.fill", label: "Chlorose", value: metrics.yellowRatio, color: .yellow)
                metricPill(icon: "drop.fill", label: "Nécrose", value: metrics.brownRatio, color: .orange)
                metricPill(icon: "sparkles", label: "Uniformité", value: 1.0 - min(metrics.luminanceStdDev * 3, 1.0), color: .cyan)
            }
        }.padding(20).liquidGlass()
    }

    private func metricPill(icon: String, label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(color).frame(width: 32, height: 32).background(color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.6))
                Text("\(Int(value.isNaN ? 0 : value * 100))%").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white)
            }
            Spacer()
        }.padding(12).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func recommendationsGlass(_ recs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill").font(.system(size: 16)).foregroundColor(.yellow)
                Text("Recommandations").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
            }
            ForEach(Array(recs.enumerated()), id: \.offset) { _, rec in
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(Color.green).frame(width: 8, height: 8).padding(.top, 6)
                Text(rec)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(4)
                }
            }
        }.padding(20).liquidGlass()
    }

    private var actionButtonsGlass: some View {
        HStack(spacing: 12) {
            Button(action: {
                showResultAnimation = false
                scanner.reset()
                camera.capturedImage = nil
            }) {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 60, height: 60).liquidGlass()
            }
            Button(action: { dismiss() }) {
                Text("Terminer").font(.system(size: 17, weight: .bold)).foregroundColor(.black)
                    .frame(maxWidth: .infinity).frame(height: 60)
                    .background(LinearGradient(colors: [Color(hex: "#BBF7D0"), Color(hex: "#4ADE80")], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: Color(hex: "#4ADE80").opacity(0.3), radius: 15, y: 8)
            }
        }
    }

    // MARK: ─── ERROR PHASE ───

    private func errorPhase(_ error: PlantScanError) -> some View {
        ZStack {
            if let image = camera.capturedImage {
                Image(uiImage: image).resizable().scaledToFill().ignoresSafeArea().blur(radius: 50).overlay(Color.black.opacity(0.7))
            }
            VStack(spacing: 32) {
                Spacer()
                Image(systemName: error.systemImage).font(.system(size: 48)).foregroundColor(.orange).frame(width: 100, height: 100).background(.ultraThinMaterial, in: Circle()).overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                VStack(spacing: 12) {
                    Text("Analyse impossible").font(.system(size: 24, weight: .bold)).foregroundColor(.white)
                    Text(error.localizedDescription).font(.system(size: 16)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center).padding(.horizontal, 40)
                }
                VStack(spacing: 16) {
                    Button(action: { scanner.reset(); camera.capturedImage = nil }) {
                        HStack(spacing: 10) { Image(systemName: "arrow.counterclockwise"); Text("Réessayer") }
                            .font(.system(size: 17, weight: .semibold)).foregroundColor(.black).frame(maxWidth: .infinity).frame(height: 56)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    Button(action: { dismiss() }) {
                        Text("Fermer").font(.system(size: 17, weight: .semibold)).foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 56).liquidGlass()
                    }
                }.padding(.horizontal, 40)
                Spacer()
            }
        }
    }

    // MARK: ─── HELPERS ───
    private func healthColor(_ health: Double) -> Color {
        if health > 0.80 { return .green }
        if health > 0.60 { return Color(hex: "#84CC16") }
        if health > 0.40 { return .orange }
        return .red
    }
    private func severityGradient(_ severity: Double) -> LinearGradient {
        let color: Color = severity < 0.3 ? .yellow : (severity < 0.6 ? .orange : .red)
        return LinearGradient(colors: [color.opacity(0.5), color], startPoint: .leading, endPoint: .trailing)
    }
    private func diagnosisText(for health: Double) -> String {
        switch health {
        case 0.80...1.0: return "Excellente santé"
        case 0.65..<0.80: return "Bonne santé"
        case 0.50..<0.65: return "Signes de faiblesse"
        case 0.30..<0.50: return "Plante stressée"
        default: return "Plante en mauvais état"
        }
    }
}

// MARK: ─── CORNER BRACKET SHAPE ───
private struct CornerBracketShape: Shape {
    let cornerLength: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))
        return p
    }
}
