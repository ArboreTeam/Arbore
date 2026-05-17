import CoreVideo
import Foundation

/// Minimum surface the `SceneUnderstandingController` needs from a
/// semantic segmentation backend. The concrete `SemSegPredictor` wraps
/// Apple's DETR mlpackage ; tests can substitute a fake that returns
/// canned `SemanticMap` values.
protocol SemSegPredicting {
    func predict(_ pixelBuffer: CVPixelBuffer) async throws -> SemanticMap
}

/// Minimum surface the `SceneUnderstandingController` needs from a depth
/// backend. Returns raw inverse-depth as a CVPixelBuffer ; calibration
/// happens upstream via `DepthCalibration`.
protocol DepthPredicting {
    func predict(_ pixelBuffer: CVPixelBuffer) async throws -> CVPixelBuffer
}

/// Factory used by `SceneUnderstandingController` to construct its
/// predictors. The default uses the real CoreML-backed implementations ;
/// tests pass a factory that returns mocks.
///
/// Closure-based instead of protocol-based because we want lazy
/// construction (models are heavy ; we only load when the controller
/// actually starts), with the throwing init pattern of CoreML preserved.
struct PredictorFactory {
    let makeSemSeg: () throws -> any SemSegPredicting
    let makeDepth: () throws -> any DepthPredicting

    static let `default` = PredictorFactory(
        makeSemSeg: { try SemSegPredictor() },
        makeDepth: { try DepthPredictor() }
    )
}
