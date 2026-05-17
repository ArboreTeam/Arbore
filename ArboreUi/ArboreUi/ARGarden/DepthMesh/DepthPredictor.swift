import CoreImage
import CoreML
import CoreVideo
import Foundation
import os

/// Wraps Apple's pre-converted Depth Anything V2 Small CoreML package.
///
/// The model accepts a 686×518 ARGB pixel buffer (key `image`) and returns
/// a same-sized one-channel depth pixel buffer (key `depth`) representing
/// **relative inverse depth** : larger pixel value = closer to camera.
/// To convert to metric meters, call `DepthCalibration.scale(...)` with an
/// ARKit-detected floor plane elsewhere in the pipeline.
///
/// The model isn't bundled in the repo (50MB, gitignored). Run
/// `scripts/fetch-depth-model.sh` once, then add the resulting
/// `.mlpackage` to the Xcode target manually. If the model isn't found,
/// `init()` throws — the caller is expected to disable the feature
/// gracefully rather than crash.
final class DepthPredictor {
    enum PredictorError: Error, CustomStringConvertible {
        case modelMissing
        case invalidPixelBuffer
        case modelDidNotReturnDepth

        var description: String {
            switch self {
            case .modelMissing:
                return "DepthAnythingV2SmallF16.mlmodelc not in bundle — run scripts/fetch-depth-model.sh and add the .mlpackage to the Xcode target."
            case .invalidPixelBuffer:
                return "Failed to resize/convert ARFrame buffer to the model's expected 686×518 ARGB format."
            case .modelDidNotReturnDepth:
                return "Prediction succeeded but 'depth' feature was missing from the output."
            }
        }
    }

    /// Apple-published model expects this exact extent (W×H, in pixels).
    /// Derived from huggingface/coreml-examples DepthCLI/MainCommand.swift.
    static let inputSize = CGSize(width: 686, height: 518)

    private let model: MLModel
    private let context: CIContext

    init() throws {
        guard let url = Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlpackage")
        else {
            AppLog.depthMesh.error("Depth model not found in main bundle — feature disabled.")
            throw PredictorError.modelMissing
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all   // Prefer ANE on A17+/M-series, fall back to GPU/CPU.

        let compiled: URL
        if url.pathExtension == "mlmodelc" {
            compiled = url
        } else {
            compiled = try MLModel.compileModel(at: url)
        }
        self.model = try MLModel(contentsOf: compiled, configuration: config)
        self.context = CIContext()
        AppLog.depthMesh.notice("DepthPredictor ready (computeUnits=\(config.computeUnits.rawValue, privacy: .public))")
    }

    /// Predicts depth for a single ARFrame buffer.
    ///
    /// - Parameter pixelBuffer: typically `ARFrame.capturedImage` (YpCbCr).
    ///   We rebuild it as ARGB at the model's expected resolution before
    ///   inference. The output buffer is mono Float16/Float32 depending
    ///   on the model's output type.
    func predict(_ pixelBuffer: CVPixelBuffer) async throws -> CVPixelBuffer {
        let inputBuffer = try resizeToModelInput(pixelBuffer)
        let provider = try MLDictionaryFeatureProvider(dictionary: ["image": inputBuffer])
        let prediction = try await model.prediction(from: provider)
        guard let depth = prediction.featureValue(for: "depth")?.imageBufferValue else {
            throw PredictorError.modelDidNotReturnDepth
        }
        return depth
    }

    /// CIContext-based resize that converts whatever ARKit hands us (BGRA,
    /// YpCbCr…) into a 686×518 ARGB buffer — the exact format Apple's
    /// CLI sample feeds the model.
    private func resizeToModelInput(_ source: CVPixelBuffer) throws -> CVPixelBuffer {
        let ci = CIImage(cvPixelBuffer: source)
        let scaleX = DepthPredictor.inputSize.width / ci.extent.width
        let scaleY = DepthPredictor.inputSize.height / ci.extent.height
        var resized = ci.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        resized = resized.transformed(by: CGAffineTransform(
            translationX: -resized.extent.origin.x,
            y: -resized.extent.origin.y
        ))

        var buf: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(DepthPredictor.inputSize.width),
            Int(DepthPredictor.inputSize.height),
            kCVPixelFormatType_32ARGB,
            nil,
            &buf
        )
        guard status == kCVReturnSuccess, let out = buf else {
            throw PredictorError.invalidPixelBuffer
        }
        context.render(resized, to: out)
        return out
    }
}

/// Maps Depth Anything's **relative inverse depth** to absolute metric
/// depth using a known floor plane.
///
/// The model outputs values in an arbitrary range where bigger = closer.
/// If we know the camera height above the floor (h, in meters, from
/// `ARFrame.camera.transform.columns.3.y - floorAnchor.transform.columns.3.y`),
/// then for the depth value `dCenter` at the image centre — assuming the
/// camera points roughly forward and the centre pixel hits the floor — we
/// can fit a single scale so that `dCenter` → `h`.
///
/// Real-world calibration is messier (centre pixel may not hit floor),
/// but this gives a good-enough starting point for the debug viz. The
/// renderer caches the scale and only re-fits when the user re-toggles.
enum DepthCalibration {
    /// Returns a multiplicative scale `s` such that `metricDepth = s / rawDepth`
    /// (inverse-depth convention). Returns `nil` if the floor sample is
    /// degenerate (raw depth ~0).
    static func fitInverseScale(
        rawDepthAtFloorSamplePoint: Float,
        cameraHeightMeters: Float
    ) -> Float? {
        guard rawDepthAtFloorSamplePoint > 0.001 else { return nil }
        // metricDepth = s / rawDepth ⇒ s = h * rawDepth
        let s = cameraHeightMeters * rawDepthAtFloorSamplePoint
        return s.isFinite ? s : nil
    }
}
