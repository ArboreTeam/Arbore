import CoreML
import CoreVideo
import Foundation
import simd

/// Per-pixel fusion of a `SemanticMap` and a (calibrated) depth map into
/// a list of labelled 3D `SceneRegion`s (cf #187).
///
/// Algorithm (downsampled flood-fill) :
///
///   1. We sample the SemanticMap at a step S (default 4) so we
///      iterate on a coarse grid (~112 × 112 cells for a 448×448 input).
///   2. Each cell pulls (a) its COCO label string (b) the depth value
///      at the corresponding pixel of the depth map (resized internally
///      so the two grids align in [0,1]² UV space) (c) the back-
///      projected world XYZ.
///   3. We flood-fill the grid using 4-connected neighbour with the
///      contiguity predicate `same label && depth jump < threshold` —
///      this separates two desks at the same height that happen to
///      share the same label.
///   4. Each connected component becomes a `SceneRegion` with its
///      world-space bounding box + centroid + pixel count.
///   5. Components smaller than `minClusterPixels` are dropped as
///      noise (mostly edges where DETR is unsure).
///
/// The fusion is pure-functional given the inputs. Caller wraps the
/// inference + calibration upstream.
enum SceneFusion {

    /// Stride at which we sample the SemanticMap. Stride 4 on a 448×448
    /// input = 112×112 cells = 12,544 candidate pixels — light enough for
    /// flood-fill in a couple of ms.
    static let defaultStride = 4

    /// Two adjacent cells with the same label but a metric depth
    /// difference greater than this threshold are considered distinct
    /// clusters (e.g. two chairs separated by 30cm of background).
    static let depthBreakMeters: Float = 0.30

    /// Drop any cluster smaller than this many pixels (after
    /// downsampling). 30 cells ≈ 2.5% of the frame area.
    static let minClusterPixels = 30

    /// Reject metric depth values outside this range.
    static let validMetricRange: ClosedRange<Float> = 0.15 ... 8.0

    /// Run the full pipeline.
    ///
    /// - Parameter semanticMap: output of `SemSegPredictor`.
    /// - Parameter depthMap: output of `DepthPredictor` (raw inverse depth).
    /// - Parameter inverseScale: fitted scale s such that metric = s / raw.
    /// - Parameter intrinsics: ARKit camera intrinsics, in capture coords.
    /// - Parameter cameraTransform: ARKit camera transform (camera-to-world).
    /// - Parameter captureSize: original `ARFrame.camera.imageResolution`.
    /// - Parameter step: pixel step along the SemanticMap grid.
    static func fuse(
        semanticMap: SemanticMap,
        depthMap: CVPixelBuffer,
        inverseScale: Float,
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        captureSize: CGSize,
        step: Int = defaultStride
    ) -> [SceneRegion] {

        let segW = semanticMap.width
        let segH = semanticMap.height
        guard segW > 0, segH > 0, step > 0 else { return [] }

        // Rescale intrinsics into the SemanticMap's pixel space, so we
        // can back-project directly from (col, row) of the seg grid.
        let segIntrinsics = BackProjector.scaledIntrinsics(
            intrinsics,
            from: captureSize,
            to: CGSize(width: segW, height: segH)
        )

        let depthW = CVPixelBufferGetWidth(depthMap)
        let depthH = CVPixelBufferGetHeight(depthMap)
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else { return [] }
        let depthBpr = CVPixelBufferGetBytesPerRow(depthMap)
        let depthFmt = CVPixelBufferGetPixelFormatType(depthMap)

        // Downsampled grid dimensions.
        let cols = (segW + step - 1) / step
        let rows = (segH + step - 1) / step

        // Pre-compute per-cell : category index, world XYZ, metric depth.
        // categoryByCell[-1] means "rejected" (no valid depth, or out of range).
        var categoryByCell = [Int](repeating: -1, count: cols * rows)
        var labelStringByCell = [String](repeating: "", count: cols * rows)
        var worldByCell = [SIMD3<Float>](repeating: .zero, count: cols * rows)
        var depthByCell = [Float](repeating: 0, count: cols * rows)

        for r in 0..<rows {
            let segRow = min(r * step, segH - 1)
            let dRow = min(Int(Float(segRow) / Float(segH) * Float(depthH)), depthH - 1)
            for c in 0..<cols {
                let segCol = min(c * step, segW - 1)
                let dCol = min(Int(Float(segCol) / Float(segW) * Float(depthW)), depthW - 1)

                let raw = DepthPixelBufferAccess.sampleRaw(
                    x: dCol, y: dRow,
                    base: depthBase, bytesPerRow: depthBpr,
                    format: depthFmt, width: depthW, height: depthH
                )
                let metric = DepthCalibration.metric(raw: raw, inverseScale: inverseScale)
                guard validMetricRange.contains(metric) else { continue }

                let idx = r * cols + c
                let rawId = Int(semanticMap.pixels[scalarAt: [segRow, segCol]])
                let label = semanticMap.labels[rawId] ?? ""
                let cat = COCOPanopticCategory.category(for: label)
                guard cat != .other else { continue }

                categoryByCell[idx] = cat.indexInAllCases
                labelStringByCell[idx] = label
                depthByCell[idx] = metric
                worldByCell[idx] = BackProjector.worldPosition(
                    u: Float(segCol), v: Float(segRow),
                    dMetric: metric,
                    intrinsics: segIntrinsics,
                    cameraTransform: cameraTransform
                )
            }
        }

        // Flood-fill 4-connected, breaking on (a) different category,
        // (b) depth jump > threshold. Each component → SceneRegion.
        var visited = [Bool](repeating: false, count: cols * rows)
        var regions: [SceneRegion] = []
        var stack: [Int] = []
        stack.reserveCapacity(cols * rows)

        for seed in 0..<(cols * rows) {
            if visited[seed] { continue }
            let cat = categoryByCell[seed]
            if cat < 0 { visited[seed] = true; continue }

            visited[seed] = true
            stack.removeAll(keepingCapacity: true)
            stack.append(seed)

            var bboxMin = worldByCell[seed]
            var bboxMax = worldByCell[seed]
            var centroidSum = SIMD3<Float>.zero
            var count = 0
            var representativeLabel = labelStringByCell[seed]

            while let cell = stack.popLast() {
                let r = cell / cols
                let c = cell % cols
                let world = worldByCell[cell]
                bboxMin = simd_min(bboxMin, world)
                bboxMax = simd_max(bboxMax, world)
                centroidSum += world
                count += 1
                if representativeLabel.isEmpty {
                    representativeLabel = labelStringByCell[cell]
                }

                for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nr = r + dr, nc = c + dc
                    if nr < 0 || nr >= rows || nc < 0 || nc >= cols { continue }
                    let nidx = nr * cols + nc
                    if visited[nidx] { continue }
                    if categoryByCell[nidx] != cat { continue }
                    if abs(depthByCell[nidx] - depthByCell[cell]) > depthBreakMeters { continue }
                    visited[nidx] = true
                    stack.append(nidx)
                }
            }

            if count >= minClusterPixels {
                let centroid = centroidSum / Float(count)
                let allCases = COCOPanopticCategory.allCases
                let resolvedCategory: COCOPanopticCategory = (cat >= 0 && cat < allCases.count)
                    ? allCases[cat]
                    : .other
                regions.append(SceneRegion(
                    id: UUID(),
                    label: representativeLabel,
                    category: resolvedCategory,
                    bboxMin: bboxMin,
                    bboxMax: bboxMax,
                    centroid: centroid,
                    pixelCount: count
                ))
            }
        }

        return regions
    }
}

private extension COCOPanopticCategory {
    /// Stable integer index for fast equality checks during flood-fill
    /// (string comparison would be the hot path bottleneck).
    var indexInAllCases: Int {
        Self.allCases.firstIndex(of: self) ?? -1
    }
}
