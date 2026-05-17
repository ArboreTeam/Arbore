import Foundation
import os
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
/// Once full, the oldest cells are dropped FIFO via a circular buffer of
/// keys (true O(1) eviction — see `evict()` below).
///
/// Thread-safety : reads happen on the SceneKit render thread (via
/// `snapshot()` from `VoxelOverlay.refresh`) while writes come from the
/// ML worker thread (via `insert()` from `SceneUnderstandingController`).
/// All mutating + reading entrypoints go through `lock` to keep the
/// underlying `Dictionary` safe — Swift Dictionary is NOT thread-safe and
/// concurrent access is UB.
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

    private let lock = OSAllocatedUnfairLock()
    /// Underlying storage — only ever accessed under `lock`.
    private var _cells: [Key: Cell] = [:]
    /// Ring buffer of insertion order — `_orderHead` is the index of the
    /// oldest element ; appends go to the end ; eviction increments head
    /// rather than shifting (true O(1) instead of `Array.removeFirst`).
    private var _order: [Key] = []
    private var _orderHead: Int = 0

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

    /// Insert or refresh a voxel. O(1) — true O(1) eviction via ring head.
    /// Returns true if the cell was new (so a re-render can be triggered
    /// on insertion deltas).
    @discardableResult
    func insert(point: SIMD3<Float>, color: SIMD3<Float>, now: TimeInterval) -> Bool {
        let key = quantize(point)
        return lock.withLock {
            if var existing = self._cells[key] {
                existing.color = color           // last-write-wins
                existing.lastTouchedAt = now
                self._cells[key] = existing
                return false
            }
            self._cells[key] = Cell(color: color, lastTouchedAt: now)
            self._order.append(key)
            if self._cells.count > self.maxVoxels {
                self.evictOldestLocked()
            }
            return true
        }
    }

    /// Drop every cell. Use this when the user dismisses the toggle or
    /// switches gardens — voxels are tied to the current ARKit world
    /// origin and become stale across sessions.
    func clear() {
        lock.withLock {
            self._cells.removeAll(keepingCapacity: true)
            self._order.removeAll(keepingCapacity: true)
            self._orderHead = 0
        }
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

    /// Thread-safe count of currently stored voxels.
    var count: Int { lock.withLock { self._cells.count } }

    /// Atomically copy the cell dictionary under the lock so a caller
    /// (typically the SceneKit overlay) can iterate it without racing
    /// against an in-flight `insert`. The copy is a value type so the
    /// reader sees a stable snapshot.
    func snapshot() -> [Key: Cell] {
        lock.withLock { self._cells }
    }

    // MARK: - Private

    /// Caller must hold `lock`. Walks the ring head forward past tombstones
    /// (keys that were already overwritten by a more recent insert into the
    /// same cell — `_cells.removeValue` returns nil) until it finds a live
    /// key, then evicts it. Compacts the array if the head drifts too far.
    private func evictOldestLocked() {
        while _orderHead < _order.count {
            let candidate = _order[_orderHead]
            _orderHead += 1
            if _cells.removeValue(forKey: candidate) != nil {
                break
            }
            // Tombstone — already replaced ; keep walking.
        }
        // Compact when the dead-prefix gets too large (avoids unbounded
        // memory growth for the ring buffer itself).
        if _orderHead > 4096 && _orderHead > _order.count / 2 {
            _order.removeFirst(_orderHead)
            _orderHead = 0
        }
    }
}
