import SwiftUI
import RealityKit
import ARKit
import Combine
import PhotosUI

// MARK: - 1. LE CERVEAU (ViewModel)
class GardenManager: ObservableObject {
    @Published var points: [SIMD3<Float>] = []
    @Published var area: Float = 0.0
    @Published var perimeter: Float = 0.0
    
    let resetSignal = PassthroughSubject<Void, Never>()
    
    func addPoint(_ point: SIMD3<Float>) {
        DispatchQueue.main.async {
            self.points.append(point)
            self.calculateStats()
        }
    }
    
    func reset() {
        points.removeAll()
        area = 0.0
        perimeter = 0.0
        resetSignal.send()
    }
    
    private func calculateStats() {
        guard points.count > 1 else { return }
        
        // Périmètre
        var tempPerimeter: Float = 0
        for i in 0..<points.count-1 {
            tempPerimeter += distance(points[i], points[i+1])
        }
        if points.count > 2 {
            tempPerimeter += distance(points.last!, points.first!)
        }
        self.perimeter = tempPerimeter
        
        // Surface (Shoelace)
        guard points.count > 2 else { self.area = 0; return }
        var tempArea: Float = 0.0
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            tempArea += (points[i].x * points[j].z)
            tempArea -= (points[i].z * points[j].x)
        }
        self.area = abs(tempArea) / 2.0
    }
}

// MARK: - 2. LE MOTEUR AR (Fix Écran Noir)

class GardenARView: ARView {
    required init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
    }
    @MainActor required dynamic init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    // Force la mise à jour du layout vidéo
    override func layoutSubviews() {
        super.layoutSubviews()
    }
}

struct ARViewContainerGarden: UIViewRepresentable {
    @ObservedObject var manager: GardenManager
    
    func makeUIView(context: Context) -> ARView {
        // --- CORRECTION CRITIQUE ---
        // On force la taille de l'écran dès l'initialisation.
        // Si on laisse .zero, la couche vidéo Metal ne s'initialise pas.
        let arView = GardenARView(frame: UIScreen.main.bounds)
        
        // Configuration
        arView.cameraMode = .ar
        arView.automaticallyConfigureSession = false
        // Désactiver le flou de mouvement aide parfois le démarrage
        arView.renderOptions = [.disableMotionBlur, .disableCameraGrain]
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        
        // Gestion du Tap
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        context.coordinator.arView = arView
        context.coordinator.setupSubscription()
        
        // Petit délai de sécurité pour laisser l'animation de transition finir
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager)
    }
    
    class Coordinator: NSObject {
        var arView: ARView?
        var manager: GardenManager
        var cancellable: AnyCancellable?
        
        init(manager: GardenManager) {
            self.manager = manager
        }
        
        func setupSubscription() {
            cancellable = manager.resetSignal.sink { [weak self] in
                self?.arView?.scene.anchors.removeAll()
            }
        }
        
        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView = self.arView else { return }
            let location = sender.location(in: arView)
            
            let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal)
            
            if let firstResult = results.first {
                // Création du point visuel
                let anchor = AnchorEntity(world: firstResult.worldTransform)
                let material = SimpleMaterial(color: .green, isMetallic: false)
                let sphere = ModelEntity(mesh: .generateSphere(radius: 0.05), materials: [material])
                sphere.position.y = 0.05
                anchor.addChild(sphere)
                arView.scene.addAnchor(anchor)
                
                // Enregistrement
                let position = SIMD3<Float>(firstResult.worldTransform.columns.3.x,
                                            firstResult.worldTransform.columns.3.y,
                                            firstResult.worldTransform.columns.3.z)
                manager.addPoint(position)
            }
        }
    }
}

// MARK: - 3. VISUELS (Shapes)
struct GardenShape: Shape {
    var points: [SIMD3<Float>]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        let xs = points.map { CGFloat($0.x) }
        let zs = points.map { CGFloat($0.z) }
        let minX = xs.min() ?? 0; let maxX = xs.max() ?? 1
        let minZ = zs.min() ?? 0; let maxZ = zs.max() ?? 1
        let width = maxX - minX; let height = maxZ - minZ
        let scale = min(rect.width / (width == 0 ? 1 : width), rect.height / (height == 0 ? 1 : height)) * 0.8
        let offsetX = (rect.width - width * scale) / 2
        let offsetY = (rect.height - height * scale) / 2
        
        func point(at i: Int) -> CGPoint {
            return CGPoint(x: (CGFloat(points[i].x) - minX) * scale + offsetX, y: (CGFloat(points[i].z) - minZ) * scale + offsetY)
        }
        path.move(to: point(at: 0))
        for i in 1..<points.count { path.addLine(to: point(at: i)) }
        path.closeSubpath()
        return path
    }
}

struct GridShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 30
        for x in stride(from: 0, to: rect.width, by: step) {
            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        for y in stride(from: 0, to: rect.height, by: step) {
            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}

struct ExportableView: View {
    @ObservedObject var manager: GardenManager
    var body: some View {
        ZStack {
            Color.white
            VStack(spacing: 20) {
                Text("PLAN DU JARDIN").font(.headline).tracking(4).foregroundColor(.black).padding(.top, 40)
                VStack {
                    Text("\(String(format: "%.2f", manager.area)) m²").font(.system(size: 60, weight: .bold)).foregroundColor(.black)
                    Text("Périmètre: \(String(format: "%.2f", manager.perimeter)) m").font(.subheadline).foregroundColor(.gray)
                }
                Divider().padding(.horizontal)
                ZStack {
                    GridShape().stroke(Color.gray.opacity(0.1))
                    GardenShape(points: manager.points).stroke(Color.black, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 400).padding()
                Spacer()
                Text("Généré via GardenAR").font(.caption2).foregroundColor(.gray).padding(.bottom, 20)
            }
        }.frame(width: 500, height: 700)
    }
}

// MARK: - 4. UI PRINCIPALE (Avec Correctifs)
struct ARViewContainerMesure: View {
    @StateObject var gardenManager = GardenManager()
    @State private var showFullScreenPlan = false
    @State private var saveSuccess = false
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            // --- MODIF 1 : Pas de fond noir ---
            // On met du gris clair. Si tu vois du gris, c'est que la caméra charge (ou a planté).
            // Si c'était noir, tu ne savais pas si c'était l'écran éteint ou un bug.
            Color(UIColor.systemGray6).edgesIgnoringSafeArea(.all)
            
            // --- AR VIEW ---
            ARViewContainerGarden(manager: gardenManager)
                .edgesIgnoringSafeArea(.all)
            
            // --- INTERFACE UI ---
            VStack {
                // Header
                HStack(alignment: .top) {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("SURFACE TOTALE")
                            .font(.system(size: 10, weight: .bold)).tracking(1.5)
                            .foregroundStyle(.white.opacity(0.6))
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.2f", gardenManager.area))
                                .font(.system(size: 42, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            Text("m²")
                                .font(.headline).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { gardenManager.reset() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                
                Spacer()
                
                // Footer
                HStack(spacing: 0) {
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: "ruler").font(.caption).foregroundColor(.green)
                            Text("Relevés").font(.caption).fontWeight(.bold).textCase(.uppercase).foregroundColor(.white.opacity(0.6))
                        }.padding(.bottom, 5)
                        
                        if gardenManager.points.count < 2 {
                            Text("Placez des points...")
                                .font(.caption).italic().foregroundColor(.white.opacity(0.4))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                        } else {
                            ScrollView(showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(1..<gardenManager.points.count, id: \.self) { i in
                                        HStack {
                                            Circle().fill(Color.green).frame(width: 6, height: 6)
                                            Text("P\(i) → P\(i+1)").font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.9))
                                            Spacer()
                                            Text(String(format: "%.2f m", distance(gardenManager.points[i], gardenManager.points[i-1])))
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, .white.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom))
                        .frame(width: 1)
                        .padding(.vertical, 20)
                    
                    Button(action: { showFullScreenPlan = true }) {
                        VStack {
                            ZStack {
                                if gardenManager.points.isEmpty {
                                    Image(systemName: "square.dashed").font(.largeTitle).foregroundColor(.white.opacity(0.3))
                                } else {
                                    GardenShape(points: gardenManager.points)
                                        .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                        .padding(10)
                                        .shadow(color: .green.opacity(0.6), radius: 8)
                                }
                            }.frame(height: 80)
                            Text("VOIR PLAN")
                                .font(.system(size: 10, weight: .bold)).tracking(1)
                                .foregroundColor(.white.opacity(0.8)).padding(.top, 5)
                        }
                        .frame(width: 110).contentShape(Rectangle())
                    }
                }
                .frame(height: 160)
                .background(.ultraThinMaterial)
                .cornerRadius(30)
                .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        // --- MODIF 2 : Options de navigation ---
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .statusBar(hidden: true) // Cacher la status bar aide à l'immersion
        .sheet(isPresented: $showFullScreenPlan) {
            VStack {
                HStack {
                    Text("Plan Vue du Dessus").font(.title2).bold()
                    Spacer()
                    Button(action: { showFullScreenPlan = false }) {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.gray.opacity(0.5))
                    }
                }.padding()
                
                Spacer()
                
                ZStack {
                    GridShape().stroke(Color.gray.opacity(0.1))
                    GardenShape(points: gardenManager.points)
                        .stroke(Color.black, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        .padding(40)
                }
                .background(Color.white)
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.1), radius: 10)
                .padding()
                .frame(maxHeight: 500)
                
                Spacer()
                
                Button(action: { saveToGallery() }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Sauvegarder dans Photos")
                    }
                    .font(.headline).foregroundColor(.white).padding().frame(maxWidth: .infinity).background(Color.blue).cornerRadius(15)
                }.padding()
                
                if saveSuccess {
                    Text("✅ Image sauvegardée !").font(.caption).bold().foregroundColor(.green).transition(.opacity)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
    
    @MainActor
    private func saveToGallery() {
        let renderer = ImageRenderer(content: ExportableView(manager: gardenManager))
        renderer.scale = 3.0
        if let image = renderer.uiImage {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            withAnimation { saveSuccess = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { saveSuccess = false }
            }
        }
    }
}
