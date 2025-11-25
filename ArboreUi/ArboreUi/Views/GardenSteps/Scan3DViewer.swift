//
//  Scan3DViewer.swift
//  ArboreUi
//
//  Created on November 25, 2025.
//

import SwiftUI
import SceneKit
import QuickLook

// MARK: - 3D Scan Viewer for Zone Drawing
struct Scan3DViewer: View {
    let scanURL: String
    @Binding var drawnZones: [DrawnZone]
    @State private var currentDrawingPoints: [CGPoint] = []
    @State private var isDrawing = false
    @State private var selectedColor: Color = .green
    @State private var showingPreview = false
    
    var body: some View {
        ZStack {
            // Vue 3D du scan
            if let url = Bundle.main.url(forResource: scanURL, withExtension: nil) ?? getScanURL() {
                QuickLookPreview(url: url)
                    .overlay(
                        DrawingCanvas(
                            drawnZones: $drawnZones,
                            currentPoints: $currentDrawingPoints,
                            isDrawing: $isDrawing,
                            selectedColor: selectedColor
                        )
                    )
            } else {
                // Fallback si le scan n'est pas disponible
                TopDownView(
                    drawnZones: $drawnZones,
                    currentPoints: $currentDrawingPoints,
                    isDrawing: $isDrawing,
                    selectedColor: selectedColor
                )
            }
            
            // Contrôles
            VStack {
                Spacer()
                
                DrawingControls(
                    selectedColor: $selectedColor,
                    onUndo: undoLastZone,
                    onClear: clearAllZones
                )
                .padding()
            }
        }
    }
    
    private func getScanURL() -> URL? {
        // Récupérer l'URL du scan depuis le stockage
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return documentsPath?.appendingPathComponent(scanURL)
    }
    
    private func undoLastZone() {
        if !drawnZones.isEmpty {
            drawnZones.removeLast()
        }
    }
    
    private func clearAllZones() {
        drawnZones.removeAll()
    }
}

// MARK: - QuickLook Preview for USDZ
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        // Pas de mise à jour nécessaire
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        
        init(url: URL) {
            self.url = url
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return url as QLPreviewItem
        }
    }
}

// MARK: - Top Down View (Fallback)
struct TopDownView: View {
    @Binding var drawnZones: [DrawnZone]
    @Binding var currentPoints: [CGPoint]
    @Binding var isDrawing: Bool
    let selectedColor: Color
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Fond avec grille
                GridPattern()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                
                // Zones déjà dessinées
                ForEach(drawnZones) { zone in
                    ZonePath(points: zone.points, color: zone.color)
                        .fill(zone.color.opacity(0.3))
                    
                    ZonePath(points: zone.points, color: zone.color)
                        .stroke(zone.color, lineWidth: 3)
                    
                    // Label de la zone
                    if let center = calculateCenter(of: zone.points) {
                        Text(zone.name ?? "Zone")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(zone.color)
                            .cornerRadius(8)
                            .position(center)
                    }
                }
                
                // Zone en cours de dessin
                if currentPoints.count > 1 {
                    ZonePath(points: currentPoints, color: selectedColor)
                        .stroke(selectedColor, lineWidth: 3)
                        .opacity(0.7)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDrawing {
                            isDrawing = true
                            currentPoints = [value.location]
                        } else {
                            currentPoints.append(value.location)
                        }
                    }
                    .onEnded { _ in
                        if currentPoints.count > 2 {
                            let newZone = DrawnZone(
                                id: UUID().uuidString,
                                points: currentPoints,
                                color: selectedColor,
                                name: nil
                            )
                            drawnZones.append(newZone)
                        }
                        currentPoints = []
                        isDrawing = false
                    }
            )
        }
        .background(Color(uiColor: .systemGray6))
    }
    
    private func calculateCenter(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let sumX = points.reduce(0.0) { $0 + $1.x }
        let sumY = points.reduce(0.0) { $0 + $1.y }
        return CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))
    }
}

// MARK: - Grid Pattern
struct GridPattern: Shape {
    var spacing: CGFloat = 20
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Lignes verticales
        stride(from: 0, through: rect.width, by: spacing).forEach { x in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        
        // Lignes horizontales
        stride(from: 0, through: rect.height, by: spacing).forEach { y in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        
        return path
    }
}

// MARK: - Drawn Zone Model
struct DrawnZone: Identifiable {
    let id: String
    let points: [CGPoint]
    let color: Color
    var name: String?
}

// MARK: - Zone Path
struct ZonePath: Shape {
    let points: [CGPoint]
    let color: Color
    
    func path(in rect: CGRect) -> Path {
        guard points.count > 1 else { return Path() }
        
        var path = Path()
        path.move(to: points[0])
        
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        
        path.closeSubpath()
        return path
    }
}

// MARK: - Drawing Canvas Overlay
struct DrawingCanvas: View {
    @Binding var drawnZones: [DrawnZone]
    @Binding var currentPoints: [CGPoint]
    @Binding var isDrawing: Bool
    let selectedColor: Color
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Zones déjà dessinées
                ForEach(drawnZones) { zone in
                    ZonePath(points: zone.points, color: zone.color)
                        .fill(zone.color.opacity(0.3))
                    
                    ZonePath(points: zone.points, color: zone.color)
                        .stroke(zone.color, lineWidth: 3)
                }
                
                // Zone en cours
                if currentPoints.count > 1 {
                    ZonePath(points: currentPoints, color: selectedColor)
                        .stroke(selectedColor, lineWidth: 3)
                        .opacity(0.7)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDrawing {
                            isDrawing = true
                            currentPoints = [value.location]
                        } else {
                            currentPoints.append(value.location)
                        }
                    }
                    .onEnded { _ in
                        if currentPoints.count > 2 {
                            let newZone = DrawnZone(
                                id: UUID().uuidString,
                                points: currentPoints,
                                color: selectedColor,
                                name: nil
                            )
                            drawnZones.append(newZone)
                        }
                        currentPoints = []
                        isDrawing = false
                    }
            )
        }
    }
}

// MARK: - Drawing Controls
struct DrawingControls: View {
    @Binding var selectedColor: Color
    let onUndo: () -> Void
    let onClear: () -> Void
    
    let availableColors: [Color] = [.green, .blue, .orange, .purple, .red, .pink, .yellow, .cyan]
    
    var body: some View {
        HStack(spacing: 16) {
            // Sélecteur de couleur
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(availableColors, id: \.self) { color in
                        Button(action: {
                            selectedColor = color
                        }) {
                            Circle()
                                .fill(color)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: selectedColor == color ? 4 : 0)
                                )
                                .shadow(radius: 4)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
            
            // Bouton Annuler
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.orange)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            
            // Bouton Effacer tout
            Button(action: onClear) {
                Image(systemName: "trash")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.red)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.7))
                .shadow(radius: 10)
        )
    }
}

#Preview {
    Scan3DViewer(scanURL: "scan_example.usdz", drawnZones: .constant([]))
}
