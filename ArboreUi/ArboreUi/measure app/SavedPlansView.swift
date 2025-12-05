//
//  SavedPlansView.swift
//  measure app
//
//  Created by hugo rath on 05/12/2025.
//

import SwiftUI
import simd

struct SavedPlansView: View {
    @ObservedObject var model: ARMeasureModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                if model.savedPlans.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "tray")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("Aucun plan sauvegardé")
                            .font(.headline)
                        Text("Terminez un plan et appuyez sur \"Sauvegarder\"")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(model.savedPlans) { plan in
                            NavigationLink(destination: SavedPlanDetailView(plan: plan, model: model)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(plan.name)
                                        .font(.headline)
                                    HStack(spacing: 20) {
                                        VStack(alignment: .leading) {
                                            Text("Points")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("\(plan.points.count)")
                                                .font(.caption2)
                                        }
                                        VStack(alignment: .leading) {
                                            Text("Périmètre")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(String(format: "%.2f m", calculatePerimeter(plan.points)))
                                                .font(.caption2)
                                        }
                                        Spacer()
                                        Text(plan.timestamp.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { indexSet in
                            indexSet.forEach { index in
                                model.deletePlan(model.savedPlans[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plans Sauvegardés")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            model.loadSavedPlans()
        }
    }
    
    private func calculatePerimeter(_ points: [SIMD3<Float>]) -> Float {
        guard points.count > 2 else { return 0 }
        var total: Float = 0
        for i in 0..<points.count {
            let p1 = points[i]
            let p2 = points[(i + 1) % points.count]
            total += simd_length(p2 - p1)
        }
        return total
    }
}

struct SavedPlanDetailView: View {
    let plan: SavedPlan
    @ObservedObject var model: ARMeasureModel
    @Environment(\.dismiss) var dismiss
    
    @State private var scale: CGFloat = 1.0
    @State private var rotation: Double = 0.0
    @State private var offset: CGSize = .zero
    @State private var lastZoom: CGFloat = 1.0
    @State private var lastRotation: Angle = .zero
    
    private var lines2D: [CGPoint] {
        plan.points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.z)) }
    }
    
    private func boundingBox(of pts: [CGPoint]) -> CGRect {
        guard !pts.isEmpty else { return .zero }
        var minX = pts[0].x, maxX = pts[0].x, minY = pts[0].y, maxY = pts[0].y
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    private func distanceMeters(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        simd_length(b - a)
    }
    
    private func calculatePerimeter() -> Float {
        guard plan.points.count > 2 else { return 0 }
        var total: Float = 0
        for i in 0..<plan.points.count {
            let p1 = plan.points[i]
            let p2 = plan.points[(i + 1) % plan.points.count]
            total += distanceMeters(p1, p2)
        }
        return total
    }
    
    private func calculateArea() -> Float {
        guard plan.points.count > 2 else { return 0 }
        let pts2D = lines2D
        var area: CGFloat = 0
        for i in 0..<pts2D.count {
            let p1 = pts2D[i]
            let p2 = pts2D[(i + 1) % pts2D.count]
            area += (p1.x * p2.y - p2.x * p1.y)
        }
        return Float(abs(area) / 2)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Stats
            VStack(spacing: 12) {
                HStack {
                    Text(plan.name)
                        .font(.headline)
                    Spacer()
                    Text(plan.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("Points")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(plan.points.count)")
                            .font(.headline)
                    }
                    VStack(alignment: .leading) {
                        Text("Périmètre")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.2f m", calculatePerimeter()))
                            .font(.headline)
                    }
                    VStack(alignment: .leading) {
                        Text("Superficie")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.2f m²", calculateArea()))
                            .font(.headline)
                    }
                    Spacer()
                }
            }
            .padding()
            .background(Color(white: 0.95))
            
            // Plan view
            GeometryReader { geo in
                Canvas { context, size in
                    let pts = lines2D
                    guard !pts.isEmpty else { return }
                    
                    let bb = boundingBox(of: pts)
                    let padding: CGFloat = 24
                    let scaleX = (size.width - padding*2) / max(bb.width, 0.0001)
                    let scaleY = (size.height - padding*2) / max(bb.height, 0.0001)
                    var canvasScale = min(scaleX, scaleY) * scale
                    
                    let centerX = (size.width) / 2 + offset.width
                    let centerY = (size.height) / 2 + offset.height
                    let worldCenter = CGPoint(x: bb.midX, y: bb.midY)
                    
                    func worldToView(_ p: CGPoint) -> CGPoint {
                        let dx = (p.x - worldCenter.x) * canvasScale
                        let dy = (p.y - worldCenter.y) * canvasScale
                        
                        let angle = CGFloat(rotation)
                        let rotX = dx * cos(angle) - dy * sin(angle)
                        let rotY = dx * sin(angle) + dy * cos(angle)
                        
                        return CGPoint(x: centerX + rotX, y: centerY - rotY)
                    }
                    
                    // Draw polygon
                    var path = Path()
                    if pts.count == 1 {
                        let v = worldToView(pts[0])
                        path.addEllipse(in: CGRect(x: v.x-3, y: v.y-3, width: 6, height: 6))
                    } else {
                        path.move(to: worldToView(pts[0]))
                        for i in 1..<pts.count {
                            path.addLine(to: worldToView(pts[i]))
                        }
                        path.addLine(to: worldToView(pts[0]))
                    }
                    
                    context.stroke(path, with: .color(.blue), lineWidth: 3)
                    
                    // Draw points and distances
                    for i in 0..<pts.count {
                        let v = worldToView(pts[i])
                        let r = CGRect(x: v.x - 4, y: v.y - 4, width: 8, height: 8)
                        context.fill(Path(ellipseIn: r), with: .color(.black))
                        
                        let p1 = plan.points[i]
                        let p2 = plan.points[(i + 1) % plan.points.count]
                        let midWorld = CGPoint(x: (pts[i].x + pts[(i+1) % pts.count].x) / 2,
                                              y: (pts[i].y + pts[(i+1) % pts.count].y) / 2)
                        let midView = worldToView(midWorld)
                        let dist = distanceMeters(p1, p2)
                        let text = String(format: "%.2fm", dist)
                        let resolved = context.resolve(Text(text).font(.system(size: 12)).foregroundColor(.black))
                        context.draw(resolved, at: midView, anchor: .center)
                    }
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastZoom * value
                        }
                        .onEnded { _ in
                            lastZoom = scale
                        }
                )
                .gesture(
                    RotationGesture()
                        .onChanged { angle in
                            rotation = lastRotation.radians + angle.radians
                        }
                        .onEnded { angle in
                            lastRotation = Angle(radians: rotation)
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = value.translation
                        }
                        .onEnded { _ in }
                )
            }
            
            // Bottom buttons
            HStack(spacing: 12) {
                Button(action: {
                    scale = 1.0
                    rotation = 0.0
                    offset = .zero
                    lastZoom = 1.0
                    lastRotation = .zero
                }) {
                    Label("Réinitialiser", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    dismiss()
                }) {
                    Label("Fermer", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("Détail du Plan")
        .navigationBarTitleDisplayMode(.inline)
    }
}
