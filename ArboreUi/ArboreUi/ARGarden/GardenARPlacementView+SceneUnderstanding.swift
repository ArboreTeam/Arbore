//
//  GardenARPlacementView+SceneUnderstanding.swift
//  ArboreUi
//
//  Extracted from GardenARPlacementView.swift (#188 P3.1).
//
//  This file holds the wiring between the AR Coordinator and the Phase-3
//  ML scene-understanding pipeline (issue #187) — both directions :
//   - `syncSceneUnderstanding` is called from `updateUIView` whenever a
//     debug-overlay toggle changes ; it lazily starts/stops the
//     controller and attaches/detaches the relevant 2D + 3D overlays.
//   - `applySceneSnapshot` is the controller's `onSnapshot` callback ;
//     it fans the snapshot out to whichever overlays are active.
//
//  The Coordinator stores the controller, the overlays and the voxel
//  grid as internal-access stored properties (declared in the main
//  file's `Coordinator` body) so extensions in other files can reach
//  them.
//

import ARKit
import Foundation
import SceneKit

extension GardenARPlacementContainerView.Coordinator {

    /// Issue #187 — sync the Phase-3 ML overlays + voxel scan toggles.
    /// Lazy-creates the underlying `SceneUnderstandingController` the
    /// first time any overlay is enabled, releases it when ALL go off
    /// (so the ~134 MB of CoreML weights are freed).
    func syncSceneUnderstanding(
        semSegEnabled: Bool,
        depthEnabled: Bool,
        fusedEnabled: Bool,
        voxelScanEnabled: Bool,
        scanViewEnabled: Bool,
        sceneView: ARSCNView
    ) {
        let anyOn = semSegEnabled || depthEnabled || fusedEnabled || voxelScanEnabled
        if anyOn && sceneCtl == nil {
            // start() is now async — `isAvailable` won't be true until
            // the models finish loading on a background task. We wire
            // everything up immediately ; tick() exits early with
            // gate=unavailable until the loader publishes.
            let ctl = SceneUnderstandingController()
            ctl.onSnapshot = { [weak self] snap in
                self?.applySceneSnapshot(snap)
            }
            ctl.start()
            sceneCtl = ctl
        }

        if anyOn {
            if semSegEnabled { semSegOverlay.attach(to: sceneView) } else { semSegOverlay.detach() }
            if depthEnabled { depthOverlay.attach(to: sceneView) } else { depthOverlay.detach() }
            if fusedEnabled { fusedOverlay.attach(to: sceneView.scene) } else { fusedOverlay.detach() }

            // Voxel scan : accumulator + cloud overlay.
            // Fresh scan on every OFF→ON edge — wipes the previous
            // cloud. ON→OFF only pauses : grid + overlay stay alive
            // so the user can admire the result without the live
            // model running.
            if voxelScanEnabled && !voxelScanWasOn {
                voxelGrid = VoxelGrid()
                voxelOverlay.attachVoxels(to: sceneView.scene)
            }
            if voxelScanEnabled {
                sceneCtl?.voxelGrid = voxelGrid
            } else {
                sceneCtl?.voxelGrid = nil
            }

            // Scan view : hide the AR camera background.
            if scanViewEnabled, voxelScanEnabled, let cam = sceneView.pointOfView {
                voxelOverlay.hideCamera(cameraNode: cam)
            } else {
                voxelOverlay.showCamera()
            }
        } else {
            semSegOverlay.detach()
            depthOverlay.detach()
            fusedOverlay.detach()
            // Voxel cloud is intentionally NOT torn down here — user
            // wants to keep viewing their scan after toggling everything
            // off. It only goes away on dismantle.
            voxelOverlay.showCamera()
            sceneCtl?.stop()
            sceneCtl = nil
        }
        voxelScanWasOn = voxelScanEnabled
    }

    /// Called on the main queue every ~1s (the controller throttle)
    /// when a fresh SemSeg+Depth pass completes. Fans out to the
    /// currently-attached overlays.
    func applySceneSnapshot(_ snap: SceneUnderstandingSnapshot) {
        if semSegOverlay.isActive, let map = snap.semanticMap {
            semSegOverlay.update(with: map)
        }
        if depthOverlay.isActive, let dmap = snap.depthMap {
            depthOverlay.update(with: dmap, fit: snap.depthFit)
        }
        if fusedOverlay.isActive {
            fusedOverlay.update(regions: snap.regions)
        }
        if voxelOverlay.isVoxelRootAttached, let grid = voxelGrid {
            voxelOverlay.refresh(grid: grid)
        }
    }
}
