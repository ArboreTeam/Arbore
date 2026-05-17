import CoreVideo
import Foundation
import QuartzCore
import UIKit

/// 2D camera-aligned overlay that draws the calibrated depth map as a
/// heatmap (cf #187). Blue = far (8m+), red = close (<50cm). Same
/// CALayer pattern as `SemSegOverlay`.
final class DepthOverlay {
    private let layer = CALayer()
    private weak var host: UIView?

    var alpha: CGFloat = 0.5 {
        didSet { layer.opacity = Float(alpha) }
    }

    /// Min / max metric depth mapped to red / blue respectively.
    var minMeters: Float = 0.5
    var maxMeters: Float = 8.0

    var isActive: Bool { layer.superlayer != nil }

    func attach(to host: UIView) {
        if layer.superlayer === host.layer { return }
        layer.frame = host.bounds
        layer.contentsGravity = .resizeAspectFill
        layer.opacity = Float(alpha)
        layer.isOpaque = false
        host.layer.addSublayer(layer)
        self.host = host
    }

    func detach() {
        layer.contents = nil
        layer.removeFromSuperlayer()
        host = nil
    }

    func updateLayout() {
        guard let host = host else { return }
        layer.frame = host.bounds
    }

    /// Refresh contents using the raw depth buffer + the fitted inverse
    /// scale. Skips if scale is nil (no metric calibration yet).
    func update(with depthMap: CVPixelBuffer, inverseScale: Float?) {
        guard isActive, let inverseScale = inverseScale else { return }
        if let image = Self.renderImage(depthMap: depthMap,
                                         inverseScale: inverseScale,
                                         minMeters: minMeters,
                                         maxMeters: maxMeters) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contents = image
            CATransaction.commit()
        }
    }

    private static func renderImage(
        depthMap: CVPixelBuffer,
        inverseScale: Float,
        minMeters: Float,
        maxMeters: Float
    ) -> CGImage? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let w = CVPixelBufferGetWidth(depthMap)
        let h = CVPixelBufferGetHeight(depthMap)
        let bpr = CVPixelBufferGetBytesPerRow(depthMap)
        let fmt = CVPixelBufferGetPixelFormatType(depthMap)
        let span = max(maxMeters - minMeters, 0.01)

        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let raw = DepthPixelBufferAccess.sampleRaw(
                    x: x, y: y,
                    base: base, bytesPerRow: bpr,
                    format: fmt, width: w, height: h
                )
                guard raw > 0.0001 else { continue }
                let metric = inverseScale / raw
                let t = max(0, min(1, (metric - minMeters) / span))
                // t=0 (close) → red, t=1 (far) → blue, midway through green.
                let hue: CGFloat = CGFloat(t) * 0.66
                let (r, g, b) = hsvToRgb(h: hue, s: 0.85, v: 1.0)
                let offset = (y * w + x) * 4
                bytes[offset]     = UInt8(r * 255)
                bytes[offset + 1] = UInt8(g * 255)
                bytes[offset + 2] = UInt8(b * 255)
                bytes[offset + 3] = 255
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

    private static func hsvToRgb(h: CGFloat, s: CGFloat, v: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let i = floor(h * 6)
        let f = h * 6 - i
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        switch Int(i) % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
