import Foundation
import simd

/// Sparse 3D voxel grid that accumulates back-projected depth points over
/// time. Each cell snaps the world-space point onto a regular `voxelSize`
/// lattice ; duplicates that fall in the same cell are merged. Colour is
/// the most-recent semantic colour we saw for that cell.
///
/// Use case : Phase 3 "scan mode" — point the phone around the room for
/// a few seconds, and the user gets a colored 3D point cloud of every
/// surface the depth model saw, anchored to the ARKit world (so when they
/// turn the camera off they can still pan their phone and see the cloud
/// move correctly in 3D).
///
/// Capped at `maxVoxels` (~100k by default) to keep SceneKit responsive.
/// Once full, the oldest cells are dropped FIFO via a `Deque` of keys.
final class VoxelGrid {
    /// 4cm edges = good detail for indoor scenes, ~25 voxels / m of wall.
    let voxelSize: Float

    /// Hard cap on stored voxels — beyond this we start dropping the
    /// oldest cells to keep SceneKit's point-cloud render under control.
    let maxVoxels: Int

    /// Compact integer index in 3D — derived from quantizing a world XYZ
    /// by `voxelSize`. Cheap Hashable.
    struct Key: Hashable {
        let x: Int32; let y: Int32; let z: Int32
    }

    struct Cell {
        var color: SIMD3<Float>     // RGB in [0, 1]
        var lastTouchedAt: TimeInterval
    }

    private(set) var cells: [Key: Cell] = [:]
    /// Insertion-order queue used to evict oldest when over `maxVoxels`.
    /// Use a simple array as a circular buffer — for 100k voxels the
    /// O(n) `removeFirst` cost is amortised across hundreds of inserts.
    private var insertionOrder: [Key] = []

    init(voxelSize: Float = 0.04, maxVoxels: Int = 100_000) {
        self.voxelSize = voxelSize
        self.maxVoxels = maxVoxels
    }

    func quantize(_ p: SIMD3<Float>) -> Key {
        Key(
            x: Int32(floor(p.x / voxelSize)),
            y: Int32(floor(p.y / voxelSize)),
            z: Int32(floor(p.z / voxelSize))
        )
    }

    /// Insert or refresh a voxel. O(1) amortized. Returns true if the
    /// cell was new (so a re-render can be triggered on insertion deltas).
    @discardableResult
    func insert(point: SIMD3<Float>, color: SIMD3<Float>, now: TimeInterval) -> Bool {
        let key = quantize(point)
        if var existing = cells[key] {
            existing.color = color           // last-write-wins
            existing.lastTouchedAt = now
            cells[key] = existing
            return false
        }
        cells[key] = Cell(color: color, lastTouchedAt: now)
        insertionOrder.append(key)
        if cells.count > maxVoxels {
            let evict = insertionOrder.removeFirst()
            cells.removeValue(forKey: evict)
        }
        return true
    }

    /// Drop every cell. Use this when the user dismisses the toggle or
    /// switches gardens — voxels are tied to the current ARKit world
    /// origin and become stale across sessions.
    func clear() {
        cells.removeAll(keepingCapacity: true)
        insertionOrder.removeAll(keepingCapacity: true)
    }

    /// World-space centre of a voxel given its key. Adds half-voxel
    /// offset so the rendered point sits in the middle of the cell.
    func worldCenter(of key: Key) -> SIMD3<Float> {
        let half = voxelSize * 0.5
        return SIMD3<Float>(
            Float(key.x) * voxelSize + half,
            Float(key.y) * voxelSize + half,
            Float(key.z) * voxelSize + half
        )
    }

    var count: Int { cells.count }
}
