import CoreML
import Foundation
import UIKit

/// 2D camera-aligned overlay that draws the SemSeg mask on top of the
/// ARSCNView (cf #187). A `UIImageView` is added as a **subview** (not
/// a CALayer sublayer) so the Metal-backed ARSCNView composes it
/// correctly in its view hierarchy and the layout auto-resizes with
/// the host.
///
/// Rendering is CPU-side : we walk the seg-map and emit one RGBA byte
/// quad per pixel into a CGImage. Apple's sample uses a Metal compute
/// shader for the same job — we keep the CPU path until we hit thermal
/// limits ; at 0.5 Hz the cost is ~10ms / refresh, negligible.
final class SemSegOverlay {
    private let imageView = UIImageView()
    private weak var host: UIView?

    var alpha: CGFloat = 0.55 {
        didSet { imageView.alpha = alpha }
    }

    var isActive: Bool { imageView.superview != nil }

    init() {
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.alpha = alpha
        imageView.isUserInteractionEnabled = false
        // Auto-resize with the host so the overlay always matches the
        // camera feed extent.
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    /// Attach the image view to a host (ARSCNView). Idempotent.
    func attach(to host: UIView) {
        if imageView.superview === host { return }
        imageView.frame = host.bounds
        host.addSubview(imageView)
        self.host = host
        AppLog.sceneML.notice("SemSegOverlay attached frame=\(NSCoder.string(for: host.bounds), privacy: .public)")
    }

    func detach() {
        imageView.image = nil
        imageView.removeFromSuperview()
        host = nil
    }

    /// Refresh contents with a new SemanticMap. Safe to call from main.
    func update(with semanticMap: SemanticMap) {
        guard isActive else { return }
        if let cg = Self.renderImage(from: semanticMap) {
            // Same orientation correction as DepthOverlay — ARFrame is
            // landscape natively, ARSCNView rotates for display, we have
            // to rotate the model output to match.
            imageView.image = UIImage(cgImage: cg, scale: 1, orientation: .right)
        }
    }

    // MARK: - CPU rasterizer

    private static var didLogPaletteOnce = false

    private static func renderImage(from map: SemanticMap) -> CGImage? {
        let w = map.width
        let h = map.height
        guard w > 0, h > 0 else { return nil }

        // Build a per-id RGBA table once per inference. Categories that
        // map to `.other` are rendered transparent — most of the COCO
        // panoptic vocabulary that isn't Arbore-relevant disappears so
        // we keep the visual signal-to-noise high.
        var palette: [Int32: (UInt8, UInt8, UInt8, UInt8)] = [:]
        for (id, label) in map.labels {
            let category = COCOPanopticCategory.category(for: label)
            if category == .other { continue }
            let c = category.debugColor
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            palette[Int32(id)] = (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255), 230)
        }
        if !didLogPaletteOnce {
            didLogPaletteOnce = true
            AppLog.sceneML.notice("SemSeg palette size=\(palette.count, privacy: .public) (out of \(map.labels.count, privacy: .public) labels)")
        }

        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let pixels = map.pixels
        for r in 0..<h {
            for c in 0..<w {
                let id = pixels[scalarAt: [r, c]]
                guard let rgba = palette[id] else { continue }
                let offset = (r * w + c) * 4
                bytes[offset]     = rgba.0
                bytes[offset + 1] = rgba.1
                bytes[offset + 2] = rgba.2
                bytes[offset + 3] = rgba.3
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
