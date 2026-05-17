import CoreImage
import CoreML
import CoreVideo
import Foundation

/// Wraps Apple's pre-converted `DepthAnythingV2SmallF16.mlpackage` (cf
/// #187). Input is a 686×518 ARGB pixel buffer, output a same-sized
/// one-channel CVPixelBuffer carrying **relative inverse depth** (bigger
/// pixel value = closer). Convert to metric meters via
/// `DepthCalibration` once we have a floor reference from ARKit.
///
/// Same gating contract as `SemSegPredictor` : `init()` throws if the
/// `.mlpackage` isn't bundled — caller disables the feature gracefully.
final class DepthPredictor {

    enum PredictorError: Error, CustomStringConvertible {
        case modelMissing
        case invalidPixelBuffer
        case invalidOutput

        var description: String {
            switch self {
            case .modelMissing:
                return "DepthAnythingV2SmallF16 not in bundle — run scripts/fetch-ml-models.sh."
            case .invalidPixelBuffer:
                return "Failed to resize/convert ARFrame buffer to 686×518 ARGB."
            case .invalidOutput:
                return "Prediction succeeded but 'depth' was missing."
            }
        }
    }

    /// Fallback used only if the runtime model description doesn't expose
    /// an `imageConstraint`. The Apple-published `.mlpackage` we ship does
    /// expose one, so this is rarely hit in practice — we query the model
    /// at init time and store the actual accepted size in `runtimeInputSize`.
    static let fallbackInputSize = CGSize(width: 518, height: 518)

    /// The actual input size the loaded model accepts. Read from
    /// `modelDescription.inputDescriptionsByName["image"]?.imageConstraint`
    /// at init time. Always preferred over `fallbackInputSize`.
    let runtimeInputSize: CGSize

    private let model: MLModel
    private let context: CIContext

    init() throws {
        guard let url = Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlpackage")
        else {
            AppLog.sceneML.error("Depth model not found in main bundle — Depth disabled.")
            throw PredictorError.modelMissing
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all

        let compiled: URL
        if url.pathExtension == "mlmodelc" {
            compiled = url
        } else {
            compiled = try MLModel.compileModel(at: url)
        }
        let m = try MLModel(contentsOf: compiled, configuration: config)
        self.model = m
        self.context = CIContext()

        // Read the actual accepted input size from the model description.
        // Apple's published `.mlpackage` updates the accepted size between
        // model revisions (it used to be 686×518 per the CLI sample, but
        // current builds reject anything other than 518×518). Querying the
        // constraint at init time future-proofs us.
        if let img = m.modelDescription.inputDescriptionsByName["image"]?.imageConstraint {
            self.runtimeInputSize = CGSize(width: img.pixelsWide, height: img.pixelsHigh)
        } else {
            self.runtimeInputSize = Self.fallbackInputSize
        }
        AppLog.sceneML.notice("DepthPredictor ready (input=\(Int(self.runtimeInputSize.width), privacy: .public)×\(Int(self.runtimeInputSize.height), privacy: .public))")
    }

    /// Run a single inference. Output is a CVPixelBuffer of shape
    /// 686×518, one channel, Float16 or Float32 depending on the model.
    func predict(_ pixelBuffer: CVPixelBuffer) async throws -> CVPixelBuffer {
        let input = try resizeToModelInput(pixelBuffer)
        let provider = try MLDictionaryFeatureProvider(dictionary: ["image": input])
        let result = try await model.prediction(from: provider)
        guard let depth = result.featureValue(for: "depth")?.imageBufferValue else {
            throw PredictorError.invalidOutput
        }
        return depth
    }

    private func resizeToModelInput(_ source: CVPixelBuffer) throws -> CVPixelBuffer {
        let target = runtimeInputSize
        let ci = CIImage(cvPixelBuffer: source)
        let sx = target.width / ci.extent.width
        let sy = target.height / ci.extent.height
        var resized = ci.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        resized = resized.transformed(by: CGAffineTransform(
            translationX: -resized.extent.origin.x,
            y: -resized.extent.origin.y
        ))

        var buf: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(target.width),
            Int(target.height),
            kCVPixelFormatType_32ARGB,
            nil, &buf
        )
        guard status == kCVReturnSuccess, let out = buf else {
            throw PredictorError.invalidPixelBuffer
        }
        context.render(resized, to: out)
        return out
    }
}

/// Helpers to read a single value out of the depth CVPixelBuffer
/// regardless of whether Apple's model emits Float16 or Float32.
enum DepthPixelBufferAccess {

    /// Sample one raw pixel. Returns 0 if (x, y) is out of bounds.
    /// **Caller must hold the base-address lock**.
    static func sampleRaw(
        x: Int, y: Int,
        base: UnsafeMutableRawPointer,
        bytesPerRow: Int,
        format: OSType,
        width: Int, height: Int
    ) -> Float {
        guard x >= 0, x < width, y >= 0, y < height else { return 0 }
        let row = base.advanced(by: y * bytesPerRow)
        switch format {
        case kCVPixelFormatType_OneComponent32Float,
             kCVPixelFormatType_DepthFloat32:
            return row.assumingMemoryBound(to: Float.self)[x]
        case kCVPixelFormatType_OneComponent16Half,
             kCVPixelFormatType_DepthFloat16:
            return Float(row.assumingMemoryBound(to: Float16.self)[x])
        default:
            // Unexpected format ; treat first byte as 0..1.
            return Float(row.assumingMemoryBound(to: UInt8.self)[x]) / 255.0
        }
    }
}
