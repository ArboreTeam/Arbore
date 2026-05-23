import Foundation
import os
import simd

/// Truncated Signed Distance Field grid (KinectFusion-style — cf #189).
///
/// Where `VoxelGrid` stores a sparse colored point cloud (one entry per
/// back-projected pixel), `TSDFGrid` stores a sparse SDF volume : each
/// cell holds the **signed distance** from its centre to the nearest
/// observed surface, weighted by the number of times that voxel has
/// been seen.
///
///   - `tsdf > 0` — voxel is in front of the surface (empty space)
///   - `tsdf < 0` — voxel is behind the surface (occluded)
///   - `tsdf ≈ 0` — voxel lies ON the surface (the iso-surface we extract)
///
/// Values outside `[-truncationDistance, +truncationDistance]` are
/// clamped — we have no reliable signal at large distance from the
/// observed surface, and KinectFusion's volumetric integration relies
/// on the bounded range.
///
/// The mesh comes from running `MarchingCubes.extractMesh(from:)` on
/// the snapshot at any iso-value (default 0).
///
/// Thread-safety follows the same pattern as `VoxelGrid` — all reads
/// and writes go through an `OSAllocatedUnfairLock`.
final class TSDFGrid {
    /// Side length of each voxel, in metres. 4cm matches `VoxelGrid` so
    /// the two overlays stay visually comparable.
    let voxelSize: Float

    /// Truncation distance, in metres. Standard KinectFusion uses
    /// 4 × voxelSize. Observations farther than this are not integrated.
    let truncationDistance: Float

    /// Per-voxel weight cap. Past this value the running average becomes
    /// effectively immutable — preserves stability when the user pans
    /// back over the same surface for the 1000th time, but means a
    /// genuinely changing scene takes longer to converge.
    let maxWeight: Float

    /// Same Key shape as `VoxelGrid` so we can share `quantize()` math
    /// and worldCenter convention.
    struct Key: Hashable {
        let x: Int32; let y: Int32; let z: Int32
    }

    struct Cell {
        /// Signed distance to nearest observed surface, in metres,
        /// clamped to [-truncationDistance, +truncationDistance].
        var tsdf: Float
        /// Accumulated observation weight (capped at `maxWeight`).
        var weight: Float
        /// Weighted running average of camera RGB at observation time,
        /// in [0, 1]. Used by the integrator's photometric gate
        /// (#189 follow-up C) : when a carve-band observation arrives
        /// and the camera RGB at that pixel matches the cell's
        /// accumulated colour, the voxel is plausibly a real surface
        /// the current depth missed, and the carve is skipped.
        var color: SIMD3<Float>
        /// Per-category vote count — same scheme as `VoxelGrid` so
        /// the mesh can be coloured by majority-voted SemSeg class.
        var votes: [Int8: UInt16]
        var lastTouchedAt: TimeInterval

        /// Index of the category with the most votes, or nil if none.
        var winningCategory: Int8? {
            return votes.max(by: { $0.value < $1.value })?.key
        }
    }

    private let lock = OSAllocatedUnfairLock()
    private var _cells: [Key: Cell] = [:]

    init(voxelSize: Float = 0.04, truncationDistance: Float = 0.16, maxWeight: Float = 100) {
        self.voxelSize = voxelSize
        self.truncationDistance = truncationDistance
        self.maxWeight = maxWeight
    }

    /// Quantize a world-space point onto the grid lattice.
    func quantize(_ p: SIMD3<Float>) -> Key {
        Key(
            x: Int32(floor(p.x / voxelSize)),
            y: Int32(floor(p.y / voxelSize)),
            z: Int32(floor(p.z / voxelSize))
        )
    }

    /// World-space centre of a voxel given its key (half-voxel offset).
    func worldCenter(of key: Key) -> SIMD3<Float> {
        let half = voxelSize * 0.5
        return SIMD3<Float>(
            Float(key.x) * voxelSize + half,
            Float(key.y) * voxelSize + half,
            Float(key.z) * voxelSize + half
        )
    }

    /// Integrate one observation `(sdf, categoryIndex)` into a cell.
    /// The TSDF update is a weight-pondered running average :
    ///     new_tsdf = (w_old·tsdf_old + w_new·sdf) / (w_old + w_new)
    /// with the cumulative weight capped at `maxWeight`.
    ///
    /// - Parameter weight: observation strength. Defaults to 1.0 for
    ///   on-surface observations from the integrator. Pass smaller
    ///   values (e.g. 0.3) for "low-confidence" observations like
    ///   free-space carving — a single on-surface observation will
    ///   then outweigh many carve observations, so real surfaces
    ///   don't get eroded by noisy neighbouring rays.
    /// - Parameter color: camera RGB at the pixel that produced this
    ///   observation, in [0, 1]. Accumulated as a weight-averaged
    ///   running mean alongside `tsdf`. Pass nil to leave the existing
    ///   colour untouched (typical for carve-band observations — they
    ///   say "this voxel should be empty", not "this voxel looks
    ///   like X"). For new cells, nil falls back to a neutral grey
    ///   placeholder that converges as surface obs arrive.
    func integrate(key: Key,
                   sdf: Float,
                   weight: Float = 1.0,
                   color: SIMD3<Float>? = nil,
                   categoryIndex: Int8?,
                   now: TimeInterval) {
        // Clamp the observed SDF before integrating.
        let clamped = max(-truncationDistance, min(truncationDistance, sdf))
        let w = max(0, weight)
        guard w > 0 else { return }
        lock.withLock {
            if var existing = self._cells[key] {
                let newWeight = min(existing.weight + w, self.maxWeight)
                existing.tsdf = (existing.weight * existing.tsdf + w * clamped) / (existing.weight + w)
                if let observed = color {
                    existing.color = (existing.weight * existing.color + w * observed) / (existing.weight + w)
                }
                existing.weight = newWeight
                if let cat = categoryIndex {
                    existing.votes[cat, default: 0] += 1
                }
                existing.lastTouchedAt = now
                self._cells[key] = existing
            } else {
                var votes: [Int8: UInt16] = [:]
                if let cat = categoryIndex {
                    votes[cat] = 1
                }
                self._cells[key] = Cell(
                    tsdf: clamped,
                    weight: w,
                    color: color ?? SIMD3<Float>(repeating: 0.5),
                    votes: votes,
                    lastTouchedAt: now
                )
            }
        }
    }

    /// Look up a cell, returning nil if unobserved.
    func cell(at key: Key) -> Cell? {
        lock.withLock { self._cells[key] }
    }

    /// Atomically copy the cell dictionary so the mesh-extraction
    /// stage can iterate it without racing against an in-flight
    /// `integrate` from the ML worker thread.
    func snapshot() -> [Key: Cell] {
        lock.withLock { self._cells }
    }

    /// Drop everything (toggle off or session reset).
    func clear() {
        lock.withLock {
            self._cells.removeAll(keepingCapacity: true)
        }
    }

    /// Thread-safe count of observed cells.
    var count: Int { lock.withLock { self._cells.count } }
}
