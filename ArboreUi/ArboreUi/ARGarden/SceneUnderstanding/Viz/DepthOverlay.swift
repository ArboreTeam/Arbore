import CoreVideo
import Foundation
import UIKit

/// 2D camera-aligned overlay that draws the depth map as a heatmap
/// (cf #187). Blue = far, red = close.
///
/// **Calibration-aware** : when we have a fitted `inverseScale`
/// (= we know how to convert the model's relative-depth output to
/// metric meters), the colour bands map to absolute meters in
/// [minMeters, maxMeters]. When the scale isn't fitted yet (no floor
/// anchor detected), we fall back to **relative depth** — the
/// near→far range of the current frame mapped to red→blue. That way
/// the overlay always renders something, even before metric calibration.
final class DepthOverlay {
    private let imageView = UIImageView()
    private weak var host: UIView?

    var alpha: CGFloat = 0.55 {
        didSet { imageView.alpha = alpha }
    }

    /// Metric range mapped when calibration is available.
    var minMeters: Float = 0.3
    var maxMeters: Float = 6.0

    var isActive: Bool { imageView.superview != nil }

    init() {
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.alpha = alpha
        imageView.isUserInteractionEnabled = false
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    func attach(to host: UIView) {
        if imageView.superview === host { return }
        imageView.frame = host.bounds
        host.addSubview(imageView)
        self.host = host
        AppLog.sceneML.notice("DepthOverlay attached frame=\(NSCoder.string(for: host.bounds), privacy: .public)")
    }

    func detach() {
        imageView.image = nil
        imageView.removeFromSuperview()
        host = nil
    }

    /// Refresh contents. If `inverseScale` is nil we render the raw
    /// inverse-depth normalised to [0,1] across the frame's actual
    /// min/max — handy for debugging before the floor is detected.
    func update(with depthMap: CVPixelBuffer, inverseScale: Float?) {
        guard isActive else { return }
        // Sync frame in case the host was resized (or attached pre-layout
        // with bounds = .zero, which is the common case on first toggle).
        if let host = host {
            imageView.frame = host.bounds
        }
        if let cg = Self.renderImage(depthMap: depthMap,
                                      inverseScale: inverseScale,
                                      minMeters: minMeters,
                                      maxMeters: maxMeters) {
            // ARFrame.capturedImage is always landscape (1920×1440 typically)
            // even when the phone is held portrait — ARSCNView rotates the
            // camera feed internally for display. The depth model output
            // inherits that landscape orientation, so we must rotate the
            // overlay 90° CW (UIImage.Orientation.right) to match what the
            // user sees on screen.
            imageView.image = UIImage(cgImage: cg, scale: 1, orientation: .right)
        }
    }

    private static func renderImage(
        depthMap: CVPixelBuffer,
        inverseScale: Float?,
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

        // Pass 1 : if no metric scale, find the raw min/max so we can
        // colour by relative position in the frame's depth range.
        var rawMin: Float = .greatestFiniteMagnitude
        var rawMax: Float = -.greatestFiniteMagnitude
        if inverseScale == nil {
            // Sample every 4 pixels for speed — we just need a range.
            for y in stride(from: 0, to: h, by: 4) {
                for x in stride(from: 0, to: w, by: 4) {
                    let v = DepthPixelBufferAccess.sampleRaw(
                        x: x, y: y, base: base,
                        bytesPerRow: bpr, format: fmt,
                        width: w, height: h
                    )
                    guard v > 0.0001, v.isFinite else { continue }
                    if v < rawMin { rawMin = v }
                    if v > rawMax { rawMax = v }
                }
            }
            // If the depth output is degenerate (uniform), bail.
            if !(rawMax > rawMin) { return nil }
        }

        let span = max(maxMeters - minMeters, 0.01)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let raw = DepthPixelBufferAccess.sampleRaw(
                    x: x, y: y, base: base,
                    bytesPerRow: bpr, format: fmt,
                    width: w, height: h
                )
                guard raw > 0.0001 else { continue }

                let t: Float
                if let scale = inverseScale {
                    // Metric : map [minMeters, maxMeters] to [0, 1].
                    let metric = scale / raw
                    t = max(0, min(1, (metric - minMeters) / span))
                } else {
                    // Relative : map this frame's raw range to [0, 1].
                    // raw is inverse-depth, so SMALL raw = far, big raw = close.
                    // We want t=0 close, t=1 far → invert.
                    t = max(0, min(1, 1 - (raw - rawMin) / (rawMax - rawMin)))
                }
                let hue = CGFloat(t) * 0.66    // 0 = red (close), 0.66 = blue (far)
                let (r, g, b) = hsvToRgb(h: hue, s: 0.85, v: 1.0)
                let offset = (y * w + x) * 4
                // Clamp before UInt8 conversion — float rounding around
                // the case boundaries of hsvToRgb can yield 1.0 + epsilon.
                bytes[offset]     = Self.clampByte(r)
                bytes[offset + 1] = Self.clampByte(g)
                bytes[offset + 2] = Self.clampByte(b)
                bytes[offset + 3] = 230
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

    /// Safe float-to-byte conversion. The HSV→RGB conversion can yield
    /// values like 1.0 + epsilon at case boundaries ; the raw cast traps.
    private static func clampByte(_ x: CGFloat) -> UInt8 {
        UInt8(max(0, min(255, x * 255)))
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
