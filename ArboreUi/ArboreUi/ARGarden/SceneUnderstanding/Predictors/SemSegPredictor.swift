import CoreImage
import CoreML
import CoreVideo
import Foundation

/// Wraps Apple's pre-converted `DETRResnet50SemanticSegmentationF16.mlpackage`
/// (cf #187). Input is a 448×448 ARGB pixel buffer ; output is a
/// `MLShapedArray<Int32>` of shape `[448, 448]` where each cell holds the
/// COCO panoptic class id for the corresponding pixel.
///
/// Class id ↔ label mapping is **stored inside the model's metadata** by
/// Apple (key `com.apple.coreml.model.preview.params`) ; we extract it on
/// init so callers can convert ids to strings without hardcoding a table
/// that could drift from the model packaging.
///
/// The model isn't committed (86 MB, too large) — `scripts/fetch-ml-models.sh`
/// downloads it once into the bundle. If absent, `init()` throws and the
/// caller is expected to disable the scene-understanding feature gracefully.
final class SemSegPredictor: SemSegPredicting {

    enum PredictorError: Error, CustomStringConvertible {
        case modelMissing
        case missingClassMetadata
        case invalidPixelBuffer
        case invalidOutput

        var description: String {
            switch self {
            case .modelMissing:
                return "DETRResnet50SemanticSegmentationF16 not in bundle — run scripts/fetch-ml-models.sh."
            case .missingClassMetadata:
                return "DETR model doesn't expose ids2Labels in com.apple.coreml.model.preview.params metadata."
            case .invalidPixelBuffer:
                return "Failed to resize/convert ARFrame buffer to 448×448 ARGB."
            case .invalidOutput:
                return "Prediction succeeded but 'semanticPredictions' was missing."
            }
        }
    }

    /// Fallback only — runtime size is queried from the model at init.
    static let fallbackInputSize = CGSize(width: 448, height: 448)

    /// Maps the raw class id (as it appears in the model's output array)
    /// to its human-readable COCO panoptic label. Built once at init from
    /// the model's metadata.
    let idsToLabels: [Int: String]

    /// Actual accepted input size, read from the model description.
    let runtimeInputSize: CGSize

    private let model: MLModel
    private let context: CIContext

    init() throws {
        guard let url = Bundle.main.url(forResource: "DETRResnet50SemanticSegmentationF16", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "DETRResnet50SemanticSegmentationF16", withExtension: "mlpackage")
        else {
            AppLog.sceneML.error("DETR model not found in main bundle — SemSeg disabled.")
            throw PredictorError.modelMissing
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all   // ANE preferred on A17+, GPU/CPU fallback.

        let compiled: URL
        if url.pathExtension == "mlmodelc" {
            compiled = url
        } else {
            compiled = try MLModel.compileModel(at: url)
        }
        let m = try MLModel(contentsOf: compiled, configuration: config)
        self.model = m
        self.context = CIContext()
        self.idsToLabels = try Self.extractLabels(from: m)
        if let img = m.modelDescription.inputDescriptionsByName["image"]?.imageConstraint {
            self.runtimeInputSize = CGSize(width: img.pixelsWide, height: img.pixelsHigh)
        } else {
            self.runtimeInputSize = Self.fallbackInputSize
        }
        AppLog.sceneML.notice("SemSegPredictor ready (classes=\(self.idsToLabels.count, privacy: .public) input=\(Int(self.runtimeInputSize.width), privacy: .public)×\(Int(self.runtimeInputSize.height), privacy: .public))")
    }

    /// Run a single inference. Returns the raw class-id array + the
    /// labels dict for caller convenience.
    func predict(_ pixelBuffer: CVPixelBuffer) async throws -> SemanticMap {
        let input = try resizeToModelInput(pixelBuffer)
        let provider = try MLDictionaryFeatureProvider(dictionary: ["image": input])
        let result = try await model.prediction(from: provider)
        guard let array = result.featureValue(for: "semanticPredictions")?
                .shapedArrayValue(of: Int32.self) else {
            throw PredictorError.invalidOutput
        }
        return SemanticMap(pixels: array, labels: idsToLabels)
    }

    // MARK: - Helpers

    /// Reads `{"labels": ["label0", "label1", …]}` from the model metadata,
    /// then drops any "--" placeholder rows (COCO panoptic has empty slots
    /// where ids are reserved but unused).
    private static func extractLabels(from model: MLModel) throws -> [Int: String] {
        guard let userFields = model.modelDescription.metadata[MLModelMetadataKey.creatorDefinedKey] as? [String: String],
              let params = userFields["com.apple.coreml.model.preview.params"],
              let data = params.data(using: .utf8) else {
            throw PredictorError.missingClassMetadata
        }
        struct ClassList: Codable { let labels: [String] }
        guard let parsed = try? JSONDecoder().decode(ClassList.self, from: data) else {
            throw PredictorError.missingClassMetadata
        }
        var dict: [Int: String] = [:]
        for (i, name) in parsed.labels.enumerated() where name != "--" {
            dict[i] = name
        }
        return dict
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

/// Output of one SemSeg inference. Carry both the raw per-pixel class
/// ids and the labels dict so callers don't have to thread two values
/// through every layer.
struct SemanticMap {
    /// `[H, W]` of int class ids (raw COCO panoptic ids as Apple packed them).
    let pixels: MLShapedArray<Int32>
    /// Id → human-readable label.
    let labels: [Int: String]

    var height: Int { pixels.shape[0] }
    var width: Int { pixels.shape[1] }

    /// Resolve the COCO label string at (row, col), or nil if out of bounds.
    func label(at row: Int, col: Int) -> String? {
        guard row >= 0, row < height, col >= 0, col < width else { return nil }
        let id = Int(pixels[scalarAt: [row, col]])
        return labels[id]
    }

    /// Resolve the Arbore-coarse category at (row, col), or `.other`.
    func category(at row: Int, col: Int) -> COCOPanopticCategory {
        guard let label = self.label(at: row, col: col) else { return .other }
        return COCOPanopticCategory.category(for: label)
    }
}
