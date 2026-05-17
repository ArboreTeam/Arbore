import Foundation
import os
import simd

/// Sparse 3D voxel grid that accumulates back-projected depth points over
/// time. Each cell snaps the world-space point onto a regular `voxelSize`
/// lattice ; duplicates that fall in the same cell are merged. Each cell
/// records a per-category vote histogram so the final colour is resolved
/// by majority vote at render time (cf #189 post-processing #3).
///
/// Use case : Phase 3 "scan mode" — point the phone around the room for
/// a few seconds, and the user gets a colored 3D point cloud of every
/// surface the depth model saw, anchored to the ARKit world (so when they
/// turn the camera off they can still pan their phone and see the cloud
/// move correctly in 3D).
///
/// **Noise filtering** (cf #189) :
///  - Each cell counts total observations across all categories
///    (`observationCount`). The overlay only renders cells that pass
///    `minObservations` — single-frame back-projection noise is dropped.
///  - The overlay further requires `minNeighbors` confirmed neighbouring
///    cells in the 3×3×3 grid — kills isolated voxels floating in empty
///    space (typical depth-model outliers).
///  - The cell's colour is the **majority-voted** SemSeg category, not the
///    last one seen — reduces flickering when the same surface gets two
///    competing labels from frame to frame.
///
/// Capped at `maxVoxels` (~100k by default) to keep SceneKit responsive.
/// Once full, the oldest cells are dropped FIFO via a head-index ring
/// buffer (true O(1) eviction).
///
/// Thread-safety : reads happen on the SceneKit render thread (via
/// `snapshot()` / `confirmedKeys()` from `VoxelOverlay.refresh`) while
/// writes come from the ML worker thread (via `insert()` from
/// `SceneUnderstandingController`). All mutating + reading entrypoints
/// go through `lock` to keep the underlying `Dictionary` safe.
final class VoxelGrid {
    /// 4cm edges = good detail for indoor scenes, ~25 voxels / m of wall.
    let voxelSize: Float

    /// Hard cap on stored voxels — beyond this we start dropping the
    /// oldest cells to keep SceneKit's point-cloud render under control.
    let maxVoxels: Int

    /// Render-time filters (cf #189 #1 + #2). Tunable from outside without
    /// rebuilding the grid.
    var minObservations: Int = 3
    var minNeighbors: Int = 2

    /// Compact integer index in 3D — derived from quantizing a world XYZ
    /// by `voxelSize`. Cheap Hashable.
    struct Key: Hashable {
        let x: Int32; let y: Int32; let z: Int32
    }

    struct Cell {
        /// Per-category vote count. Key = `COCOPanopticCategory.allCases`
        /// index (≤ 30 categories, Int8 is plenty). Resolved to a single
        /// winning category at render time.
        var votes: [Int8: UInt16]
        /// Total observations across all categories — drives the
        /// minObservations filter.
        var observationCount: UInt32
        var lastTouchedAt: TimeInterval

        /// Returns the category index with the most votes, or nil if
        /// the cell has never been touched (shouldn't happen in practice).
        var winningCategory: Int8? {
            return votes.max(by: { $0.value < $1.value })?.key
        }
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
    func insert(point: SIMD3<Float>, categoryIndex: Int8, now: TimeInterval) -> Bool {
        let key = quantize(point)
        return lock.withLock {
            if var existing = self._cells[key] {
                existing.votes[categoryIndex, default: 0] += 1
                existing.observationCount += 1
                existing.lastTouchedAt = now
                self._cells[key] = existing
                return false
            }
            self._cells[key] = Cell(
                votes: [categoryIndex: 1],
                observationCount: 1,
                lastTouchedAt: now
            )
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

    /// Thread-safe count of currently stored voxels (raw — includes
    /// noise). Use `confirmedKeys().count` for the rendered count.
    var count: Int { lock.withLock { self._cells.count } }

    /// Atomically copy the cell dictionary under the lock so a caller
    /// (typically the SceneKit overlay) can iterate it without racing
    /// against an in-flight `insert`. The copy is a value type so the
    /// reader sees a stable snapshot.
    func snapshot() -> [Key: Cell] {
        lock.withLock { self._cells }
    }

    /// Returns the set of keys that pass both noise filters :
    ///  1. Cell has been observed at least `minObservations` times
    ///     (single-frame back-projection blips don't survive)
    ///  2. Cell has at least `minNeighbors` populated neighbours in the
    ///     26-neighbourhood (isolated outliers don't survive)
    ///
    /// Computed in one shot under the lock so the result is consistent.
    /// O(n × 26) where n is the cell count after step 1.
    func confirmedKeys() -> Set<Key> {
        return lock.withLock {
            let observed: Set<Key> = Set(
                self._cells
                    .lazy
                    .filter { $0.value.observationCount >= UInt32(self.minObservations) }
                    .map { $0.key }
            )
            guard self.minNeighbors > 0 else { return observed }

            var confirmed = Set<Key>()
            confirmed.reserveCapacity(observed.count)
            for key in observed {
                var neighbors = 0
                outer: for dx in Int32(-1)...1 {
                    for dy in Int32(-1)...1 {
                        for dz in Int32(-1)...1 {
                            if dx == 0 && dy == 0 && dz == 0 { continue }
                            if observed.contains(Key(x: key.x + dx,
                                                     y: key.y + dy,
                                                     z: key.z + dz)) {
                                neighbors += 1
                                if neighbors >= self.minNeighbors {
                                    confirmed.insert(key)
                                    break outer
                                }
                            }
                        }
                    }
                }
            }
            return confirmed
        }
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
