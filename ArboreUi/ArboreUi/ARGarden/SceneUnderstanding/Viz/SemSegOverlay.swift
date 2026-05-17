import CoreML
import Foundation
import QuartzCore
import UIKit

/// 2D camera-aligned overlay that draws the SemSeg mask on top of the
/// ARSCNView (cf #187). One CALayer is added as a sibling of the scene
/// renderer ; its `contents` is refreshed on each new
/// `SceneUnderstandingSnapshot`.
///
/// Rendering is CPU-side : we walk the 448×448 SemanticMap and emit one
/// RGBA byte quad per pixel. Apple's sample uses a Metal compute shader
/// for the same job — we keep the CPU path for simplicity until we hit
/// thermal limits ; at 0.5 Hz the CPU cost is ~10ms / refresh, negligible.
final class SemSegOverlay {
    private let layer = CALayer()
    private weak var host: UIView?

    var alpha: CGFloat = 0.5 {
        didSet { layer.opacity = Float(alpha) }
    }

    var isActive: Bool { layer.superlayer != nil }

    /// Attach the layer to a host view (the ARSCNView). Idempotent.
    func attach(to host: UIView) {
        if layer.superlayer === host.layer { return }
        layer.frame = host.bounds
        layer.contentsGravity = .resizeAspectFill
        layer.opacity = Float(alpha)
        layer.isOpaque = false
        host.layer.addSublayer(layer)
        self.host = host
    }

    /// Detach and clear the cached image.
    func detach() {
        layer.contents = nil
        layer.removeFromSuperlayer()
        host = nil
    }

    /// Resize layer to host bounds — call from layoutSubviews.
    func updateLayout() {
        guard let host = host else { return }
        layer.frame = host.bounds
    }

    /// Refresh contents with a new SemanticMap. Safe to call from main
    /// thread (the conversion is done synchronously).
    func update(with semanticMap: SemanticMap) {
        guard isActive else { return }
        if let image = Self.renderImage(from: semanticMap) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contents = image
            CATransaction.commit()
        }
    }

    // MARK: - CPU rasterizer

    /// Render the SemanticMap as an RGBA8 CGImage where each pixel is
    /// coloured by its `COCOPanopticCategory.debugColor`.
    private static func renderImage(from map: SemanticMap) -> CGImage? {
        let w = map.width
        let h = map.height
        guard w > 0, h > 0 else { return nil }

        // Pre-compute colour bytes per known category id so the inner
        // loop only does a dictionary lookup.
        var palette: [Int32: (UInt8, UInt8, UInt8, UInt8)] = [:]
        for (id, label) in map.labels {
            let category = COCOPanopticCategory.category(for: label)
            // Skip `.other` — render as transparent so the camera shows through.
            if category == .other { continue }
            let c = category.debugColor
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            palette[Int32(id)] = (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255), 255)
        }

        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let pixels = map.pixels
        for r in 0..<h {
            for c in 0..<w {
                let id = pixels[scalarAt: [r, c]]
                guard let rgba = palette[id] else { continue }
                let offset = (r * w + c) * 4
                bytes[offset] = rgba.0     // R
                bytes[offset + 1] = rgba.1 // G
                bytes[offset + 2] = rgba.2 // B
                bytes[offset + 3] = rgba.3 // A
            }
        }

        guard let provider = CGDataProvider(data: NSData(bytes: bytes, length: bytes.count)) else {
            return nil
        }
        let bitmapInfo: CGBitmapInfo = [
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        ]
        return CGImage(
            width: w, height: h,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
