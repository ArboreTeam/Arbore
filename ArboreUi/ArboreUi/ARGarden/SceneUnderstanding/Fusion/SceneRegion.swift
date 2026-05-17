import Foundation
import simd

/// A 3D region of the scene that is both semantically labelled and
/// geometrically located. The output of `SceneFusion.fuse(...)`.
///
/// One `SceneRegion` corresponds to a connected component of pixels
/// sharing the same `COCOPanopticCategory` (after downsampling), with
/// every pixel projected to a world XYZ via depth + intrinsics.
struct SceneRegion: Identifiable {
    let id: UUID
    /// COCO label string, e.g. "couch" / "potted plant".
    let label: String
    /// Coarse category the label maps to.
    let category: COCOPanopticCategory
    /// Axis-aligned world-space bounding box (min/max corner).
    let bboxMin: SIMD3<Float>
    let bboxMax: SIMD3<Float>
    /// World-space centroid (mean of all projected pixels).
    let centroid: SIMD3<Float>
    /// Number of source pixels that voted for this region.
    /// Use to filter tiny clusters that are probably noise.
    let pixelCount: Int

    var size: SIMD3<Float> { bboxMax - bboxMin }

    /// Largest dimension across X / Y / Z — useful for picking a label
    /// font size or filtering large-vs-small regions.
    var maxExtent: Float { max(size.x, max(size.y, size.z)) }
}
