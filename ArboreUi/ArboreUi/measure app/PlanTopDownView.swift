//
//  PlanTopDownView.swift
//  measure app
//
//  Created by hugo rath on 05/12/2025.
//

import SwiftUI
import simd

struct PlanTopDownView: View {
    let points3D: [SIMD3<Float>]
    var isFinished: Bool
    var previewPoint: SIMD3<Float>? = nil
    
    @ObservedObject var model: ARMeasureModel
    
    private var lines2D: [CGPoint] {
        points3D.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.z)) }
    }
    
    private var previewPoint2D: CGPoint? {
        previewPoint.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.z)) }
    }
    
    @State private var lastZoom: CGFloat = 1.0
    @State private var lastRotation: Angle = .zero
    
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
        guard points3D.count > 2 else { return 0 }
        var total: Float = 0
        for i in 0..<points3D.count {
            let p1 = points3D[i]
            let p2 = points3D[(i + 1) % points3D.count]
            total += distanceMeters(p1, p2)
        }
        return total
    }
    
    private func calculateArea() -> Float {
        guard points3D.count > 2 else { return 0 }
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
            // Stats bar
            if isFinished && !points3D.isEmpty {
                HStack(spacing: 20) {
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
                    Button(action: {
                        model.savePlan()
                    }) {
                        Label("Sauvegarder", systemImage: "square.and.arrow.down")
                            .font(.caption)
                            .padding(8)
                            .background(.blue)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                }
                .padding(12)
                .background(Color(white: 0.95))
                .borderTop(width: 1, color: .gray)
            }
            
            // Interactive canvas
            GeometryReader { geo in
                ZStack {
                    if points3D.isEmpty {
                        Text("Aucun point mesuré")
                            .foregroundColor(.secondary)
                    } else {
                        Canvas { context, size in
                            let pts = lines2D
                            guard !pts.isEmpty else { return }
                            
                            let bb = boundingBox(of: pts)
                            let padding: CGFloat = 24
                            let scaleX = (size.width - padding*2) / max(bb.width, 0.0001)
                            let scaleY = (size.height - padding*2) / max(bb.height, 0.0001)
                            var scale = min(scaleX, scaleY)
                            
                            // Apply zoom
                            scale *= model.planScale
                            
                            let centerX = (size.width) / 2 + model.planOffset.width
                            let centerY = (size.height) / 2 + model.planOffset.height
                            let worldCenter = CGPoint(x: bb.midX, y: bb.midY)
                            
                            func worldToView(_ p: CGPoint) -> CGPoint {
                                let dx = (p.x - worldCenter.x) * scale
                                let dy = (p.y - worldCenter.y) * scale
                                
                                // Apply rotation
                                let angle = CGFloat(model.planRotation)
                                let rotX = dx * cos(angle) - dy * sin(angle)
                                let rotY = dx * sin(angle) + dy * cos(angle)
                                
                                return CGPoint(x: centerX + rotX, y: centerY - rotY)
                            }
                            
                            // draw polygon lines
                            var path = Path()
                            if pts.count == 1 {
                                let v = worldToView(pts[0])
                                path.addEllipse(in: CGRect(x: v.x-3, y: v.y-3, width: 6, height: 6))
                            } else {
                                path.move(to: worldToView(pts[0]))
                                for i in 1..<pts.count {
                                    path.addLine(to: worldToView(pts[i]))
                                }
                                if isFinished && pts.count > 2 {
                                    path.addLine(to: worldToView(pts[0]))
                                }
                            }
                            
                            context.stroke(path, with: .color(.blue), lineWidth: 3)
                            
                            // draw preview line
                            if let previewPt = previewPoint2D, !pts.isEmpty && !isFinished {
                                let lastPt = worldToView(pts[pts.count - 1])
                                let previewView = worldToView(previewPt)
                                var previewPath = Path()
                                previewPath.move(to: lastPt)
                                previewPath.addLine(to: previewView)
                                context.stroke(previewPath, with: .color(.green), lineWidth: 2)
                            }
                            
                            // draw points and distances
                            for i in 0..<pts.count {
                                let v = worldToView(pts[i])
                                let r = CGRect(x: v.x - 4, y: v.y - 4, width: 8, height: 8)
                                context.fill(Path(ellipseIn: r), with: .color(.black))
                                
                                if i < points3D.count - 1 {
                                    let p1 = points3D[i], p2 = points3D[i+1]
                                    let midWorld = CGPoint(x: (pts[i].x + pts[i+1].x) / 2, y: (pts[i].y + pts[i+1].y) / 2)
                                    let midView = worldToView(midWorld)
                                    let dist = distanceMeters(p1, p2)
                                    let text = String(format: "%.2fm", dist)
                                    let resolved = context.resolve(Text(text).font(.system(size: 12)).foregroundColor(.black))
                                    context.draw(resolved, at: midView, anchor: .center)
                                } else if isFinished && pts.count > 1 {
                                    let p1 = points3D[i], p2 = points3D[0]
                                    let midWorld = CGPoint(x: (pts[i].x + pts[0].x) / 2, y: (pts[i].y + pts[0].y) / 2)
                                    let midView = worldToView(midWorld)
                                    let dist = distanceMeters(p1, p2)
                                    let text = String(format: "%.2fm", dist)
                                    let resolved = context.resolve(Text(text).font(.system(size: 12)).foregroundColor(.black))
                                    context.draw(resolved, at: midView, anchor: .center)
                                }
                            }
                        }
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    model.planScale = lastZoom * value
                                }
                                .onEnded { _ in
                                    lastZoom = model.planScale
                                }
                        )
                        .gesture(
                            RotationGesture()
                                .onChanged { angle in
                                    model.planRotation = lastRotation.radians + angle.radians
                                }
                                .onEnded { angle in
                                    lastRotation = Angle(radians: model.planRotation)
                                }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    model.planOffset = value.translation
                                }
                                .onEnded { _ in
                                    // Keep offset
                                }
                        )
                    }
                }
            }
        }
    }
}

extension View {
    func borderTop(width: CGFloat, color: Color) -> some View {
        VStack(spacing: 0) {
            Divider()
            self
        }
    }
}
