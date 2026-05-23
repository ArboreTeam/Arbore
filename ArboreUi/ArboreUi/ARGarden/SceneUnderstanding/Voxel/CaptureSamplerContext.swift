import CoreVideo
import Foundation
import simd

/// Locks an ARFrame's `capturedImage` (YCbCr 4:2:0 biplanar) for the
/// duration of a TSDF integration tick and provides a fast
/// pixel-sampler that returns the BT.601 RGB value at a coordinate
/// expressed in **SemSeg space** (the integrator iterates the SemSeg
/// grid, so we want to map a SemSeg cell back to the capture image
/// without making the integrator know about resolutions twice).
///
/// Locking once per tick + indexed plane reads avoids the cost of
/// `CIImage` / `CIFilter` per-pixel conversion. The math is BT.601
/// full-range (matches `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`
/// which is what ARKit publishes on iPhone). For VideoRange the
/// luma offset would need to be subtracted, but `ARFrame` doesn't
/// emit that format so we don't branch.
///
/// Used by `TSDFIntegrator` for photometric-gated carving
/// (#189 follow-up C). The colour returned is **linear-clamped to
/// [0, 1]** so downstream Euclidean distance compares cleanly.
struct CaptureSamplerContext {
    private let buffer: CVPixelBuffer
    private let yBase: UnsafeMutableRawPointer
    private let cbcrBase: UnsafeMutableRawPointer
    private let yBpr: Int
    private let cbcrBpr: Int
    private let captureWidth: Int
    private let captureHeight: Int

    /// Lock the pixel buffer's planes for the lifetime of the returned
    /// context. Returns nil if locking fails or the format isn't the
    /// expected biplanar YCbCr. Caller must invoke `unlock()` on
    /// teardown (defer pattern in the integrator).
    static func lock(_ pixelBuffer: CVPixelBuffer) -> CaptureSamplerContext? {
        // Only biplanar YCbCr is supported. ARKit publishes this
        // format ; if someone wires up a different source, we'd
        // silently get wrong colours, so be defensive.
        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
              || fmt == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
            return nil
        }
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let cbcrBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return nil
        }
        return CaptureSamplerContext(
            buffer: pixelBuffer,
            yBase: yBase,
            cbcrBase: cbcrBase,
            yBpr: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0),
            cbcrBpr: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1),
            captureWidth: CVPixelBufferGetWidth(pixelBuffer),
            captureHeight: CVPixelBufferGetHeight(pixelBuffer)
        )
    }

    func unlock() {
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
    }

    /// Sample RGB at the capture pixel that corresponds to SemSeg cell
    /// `(segCol, segRow)`. We map proportionally — same convention as
    /// the depth-buffer sampling in `TSDFIntegrator`.
    func sampleRGB(segCol: Int, segRow: Int, segWidth: Int, segHeight: Int) -> SIMD3<Float> {
        let capX = min(max(Int(Float(segCol) / Float(segWidth) * Float(captureWidth)), 0),
                       captureWidth - 1)
        let capY = min(max(Int(Float(segRow) / Float(segHeight) * Float(captureHeight)), 0),
                       captureHeight - 1)
        let y = Float(yBase.load(fromByteOffset: capY * yBpr + capX, as: UInt8.self)) / 255.0
        // CbCr plane is half resolution + interleaved [Cb, Cr].
        let cx = capX / 2
        let cy = capY / 2
        let cbcrRowOffset = cy * cbcrBpr
        let cb = Float(cbcrBase.load(fromByteOffset: cbcrRowOffset + cx * 2, as: UInt8.self)) / 255.0 - 0.5
        let cr = Float(cbcrBase.load(fromByteOffset: cbcrRowOffset + cx * 2 + 1, as: UInt8.self)) / 255.0 - 0.5
        // BT.601 full-range YCbCr → RGB.
        let r = y + 1.402 * cr
        let g = y - 0.344136 * cb - 0.714136 * cr
        let b = y + 1.772 * cb
        return SIMD3<Float>(
            min(max(r, 0), 1),
            min(max(g, 0), 1),
            min(max(b, 0), 1)
        )
    }
}
