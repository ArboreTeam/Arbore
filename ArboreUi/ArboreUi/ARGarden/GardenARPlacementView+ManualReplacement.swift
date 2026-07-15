//
//  GardenARPlacementView+ManualReplacement.swift
//  ArboreUi
//
//  Extracted from GardenARPlacementView.swift (#188 P3.1).
//
//  Implements the "manual replacement" flow (issue #111) — the user
//  retraces the garden boundary by hand, we morph saved plants onto the
//  new boundary via Mean-Value-Coordinates, render them as ghosts in a
//  preview phase, and finally drop real plant anchors when they confirm.
//
//  All state used here lives on the Coordinator (the dedicated stored
//  properties for the OLD garden snapshot and the MorphedPlant queue).
//  Methods shared with the rest of the AR flow (placeObject,
//  removeAllPlantAnchors, deselectAll, applyOutlinesToAllPlants,
//  resolveLocalModelURL) are reached via the Coordinator's internal
//  access — see the "Internal access" comments in the main file.
//

import ARKit
import Foundation
import SceneKit
import UIKit
import simd

extension GardenARPlacementContainerView.Coordinator {

    /// Loads scene_{id}.json off the main thread; stores boundary +
    /// plants for use in the manual replacement flow. Independent of
    /// WorldMap.
    func loadOldGardenData(gardenId: String) {
        guard !oldDataLoaded else { return }
        let sceneURL = GardenLocalStore.sceneURL(for: gardenId)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var boundary: [SIMD3<Float>] = []
            var plants: [PersistedPlant] = []
            if FileManager.default.fileExists(atPath: sceneURL.path),
               let data = try? Data(contentsOf: sceneURL),
               let scene = try? JSONDecoder().decode(PersistedARScene.self, from: data).normalizedToWorldFrame() {
                plants = scene.plants
                boundary = (scene.boundaryPoints ?? []).compactMap { arr in
                    guard arr.count >= 3 else { return nil }
                    return SIMD3<Float>(arr[0], arr[1], arr[2])
                }
            }
            DispatchQueue.main.async {
                self.oldBoundaryPoints = boundary
                self.oldPersistedPlants = plants
                self.oldDataLoaded = true
            }
        }
    }

    @objc func handleEnterManualReplacement() {
        guard let arView = arView else { return }
        // Stop relying on automatic relocalization.
        cancelPendingRestore()
        pendingRestoreGardenId = nil
        didRestoreGarden = true
        DispatchQueue.main.async {
            self.parentProps?.isRelocating = false
            self.parentProps?.relocationPhase = .tracingBoundary
            self.parentProps?.newBoundaryPoints = []
            self.parentProps?.newBoundaryArea = 0
        }
        // Clean any partially restored plants (anchors + legacy nodes).
        removeAllPlantAnchors()
        arView.scene.rootNode.childNodes
            .filter { $0.name?.starts(with: "plant_") == true }
            .forEach { $0.removeFromParentNode() }
        // Show the OLD boundary as a faint dashed grey outline (visual cue).
        if !oldBoundaryPoints.isEmpty {
            GhostRenderer.drawBoundary(
                points: oldBoundaryPoints,
                color: UIColor.lightGray,
                opacity: 0.3,
                in: arView.scene,
                name: "manual_replacement_old_boundary"
            )
        }
        clearNewBoundaryVisuals()
    }

    @objc func handleCancelManualReplacement() {
        guard let arView = arView else { return }
        let phase = parentProps?.relocationPhase ?? .scanning
        switch phase {
        case .tracingBoundary:
            // Wipe everything and return to scanning.
            clearNewBoundaryVisuals()
            GhostRenderer.removeBoundary(named: "manual_replacement_old_boundary", from: arView.scene)
            DispatchQueue.main.async {
                self.parentProps?.relocationPhase = .scanning
                self.parentProps?.isRelocating = true
                self.parentProps?.newBoundaryPoints = []
                self.parentProps?.newBoundaryArea = 0
            }
        case .morphingPreview:
            // Step back one phase: clear ghost plants, return to tracing.
            arView.scene.rootNode.childNodes
                .filter { $0.name?.starts(with: "ghost_morphed_") == true }
                .forEach { $0.removeFromParentNode() }
            DispatchQueue.main.async {
                self.parentProps?.relocationPhase = .tracingBoundary
                self.parentProps?.distortionWarnings = []
            }
        default:
            break
        }
    }

    func addBoundaryPoint(at transform: simd_float4x4) {
        let p = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        guard let arView = arView else { return }

        // Add a green sphere marker (same visual as the wizard's measurement view).
        let sphere = SCNSphere(radius: 0.025)
        sphere.firstMaterial?.diffuse.contents = UIColor(hex: "#2BEE79")
        sphere.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: sphere)
        node.simdPosition = p
        node.name = "manual_replacement_new_boundary_point"
        arView.scene.rootNode.addChildNode(node)

        DispatchQueue.main.async {
            self.parentProps?.newBoundaryPoints.append(p)
            self.refreshNewBoundaryArea()
            self.refreshNewBoundaryEdges()
        }
    }

    @objc func handleBoundaryUndoLast() {
        guard let arView = arView else { return }
        // Remove the most recent green sphere if any.
        let spheres = arView.scene.rootNode.childNodes
            .filter { $0.name == "manual_replacement_new_boundary_point" }
        if let last = spheres.last { last.removeFromParentNode() }

        DispatchQueue.main.async {
            if let _ = self.parentProps?.newBoundaryPoints.popLast() {
                self.refreshNewBoundaryArea()
                self.refreshNewBoundaryEdges()
            }
        }
    }

    @objc func handleValidateNewBoundary() {
        guard let props = parentProps, let arView = arView else { return }
        let newBoundary = props.newBoundaryPoints
        guard newBoundary.count >= 3 else { return }

        // Validate that the old garden's data finished loading from disk
        // (Issue #111 I1). Without it, GardenMorpher would silently
        // produce an empty result and the user would see nothing happen.
        guard oldDataLoaded else {
            AppLog.manualReplace.warning("validateNewBoundary blocked — old data not loaded yet")
            // Stay in tracingBoundary; the user can retry shortly.
            return
        }
        guard !oldPersistedPlants.isEmpty else {
            AppLog.manualReplace.warning("validateNewBoundary — old garden has no plants, nothing to morph")
            DispatchQueue.main.async {
                self.parentProps?.relocationPhase = .completed
            }
            return
        }
        guard !oldBoundaryPoints.isEmpty else {
            AppLog.manualReplace.warning("validateNewBoundary — old garden has no boundary, falling back to centroid placement")
            // Morpher's fallback path will place plants near the new
            // centroid; user can fine-tune in .adjusting.
            let result = GardenMorpher.morph(
                oldPlants: oldPersistedPlants,
                oldBoundary: [],
                newBoundary: newBoundary,
                floorY: averageY(of: newBoundary)
            )
            self.applyMorphResult(result, in: arView)
            return
        }

        // The old boundary may have a different vertex count than the new one;
        // if so, resample so MVC weights have matching arities.
        let resampled = resamplePolygon(oldBoundaryPoints, toCount: newBoundary.count)
        let result = GardenMorpher.morph(
            oldPlants: oldPersistedPlants,
            oldBoundary: resampled,
            newBoundary: newBoundary,
            floorY: averageY(of: newBoundary)
        )

        applyMorphResult(result, in: arView)
    }

    /// Renders morph result as ghost markers and transitions to
    /// `.morphingPreview`. Called from both the normal MVC path and
    /// the no-boundary fallback (Issue #111 I1).
    func applyMorphResult(_ result: MorphResult, in arView: ARSCNView) {
        arView.scene.rootNode.childNodes
            .filter { $0.name?.starts(with: "ghost_morphed_") == true }
            .forEach { $0.removeFromParentNode() }

        pendingMorphedPlants = result.morphedPlants
        for (idx, mp) in result.morphedPlants.enumerated() {
            drawGhostMarker(for: mp, instanceIndex: idx, in: arView.scene)
        }

        DispatchQueue.main.async {
            self.parentProps?.distortionWarnings = result.warnings
            self.parentProps?.relocationPhase = .morphingPreview
        }
    }

    @objc func handleConfirmMorphedPlacement() {
        guard let arView = arView else { return }

        // Take a snapshot of morphed transforms before any user adjustment.
        preMorphAdjustment.removeAll()

        // Hide old-boundary ghost outline and ghost markers.
        arView.scene.rootNode.childNodes
            .filter { $0.name?.starts(with: "ghost_morphed_") == true }
            .forEach { $0.removeFromParentNode() }
        GhostRenderer.removeBoundary(named: "manual_replacement_old_boundary", from: arView.scene)
        clearNewBoundaryVisuals()

        // Instantiate real plants concurrently using the existing placement
        // pipeline. Iterate the MorphedPlant list directly — multiple
        // instances of the same catalog plant must each survive (was a
        // dedup bug: 5 Arecas collapsed to 1 because the dict key was
        // the catalog plantId).
        let snapshot = pendingMorphedPlants
        Task {
            await withTaskGroup(of: Void.self) { group in
                for mp in snapshot {
                    let persisted = mp.originalPlant
                    let transform = mp.newTransform
                    let finalScale = SCNVector3(persisted.scale[0], persisted.scale[1], persisted.scale[2])
                    group.addTask {
                        do {
                            let url = try await ModelCacheManager.shared.getModelURL(for: persisted.modelURLString, forceDownload: false)
                            await MainActor.run {
                                // Propagate surface info so future
                                // restores can snap properly (Issue #111 B1).
                                self.placeObject(
                                    at: transform,
                                    modelURL: url,
                                    id: persisted.plantID,
                                    name: persisted.plantName,
                                    finalScale: finalScale,
                                    modelURLString: persisted.modelURLString,
                                    upAxis: persisted.upAxis,
                                    surfaceType: persisted.surfaceType,
                                    surfaceHeight: persisted.surfaceHeight,
                                    placementMode: ARPlacementMode.fromPersisted(persisted.placementMode),
                                    surfaceAnchor: persisted.surfaceAnchor,
                                    autoSelect: false,  // batch — entering .adjusting
                                    hasHeavy: persisted.hasHeavy == true
                                )
                            }
                        } catch {
                            if let fallback = await MainActor.run(body: { self.resolveLocalModelURL(persisted.modelURLString) }) {
                                await MainActor.run {
                                    self.placeObject(
                                        at: transform,
                                        modelURL: fallback,
                                        id: persisted.plantID,
                                        name: persisted.plantName,
                                        finalScale: finalScale,
                                        modelURLString: persisted.modelURLString,
                                        upAxis: persisted.upAxis,
                                        surfaceType: persisted.surfaceType,
                                        surfaceHeight: persisted.surfaceHeight,
                                        placementMode: ARPlacementMode.fromPersisted(persisted.placementMode),
                                        surfaceAnchor: persisted.surfaceAnchor,
                                        autoSelect: false,
                                        hasHeavy: persisted.hasHeavy == true
                                    )
                                }
                            }
                        }
                    }
                }
            }
            await MainActor.run {
                self.pendingMorphedPlants.removeAll()
                self.snapshotPreMorphAdjustment()
                self.parentProps?.relocationPhase = .adjusting
                self.applyOutlinesToAllPlants()
            }
        }
    }

    @objc func handleRevertToMorphed() {
        guard let arView = arView else { return }
        // Issue #113 — plants are anchor children; walk one level deeper
        // and revert their world transform (not local).
        let plantNodes: [SCNNode] = arView.scene.rootNode.childNodes.flatMap { rootChild -> [SCNNode] in
            if rootChild.name?.starts(with: "plant_") == true { return [rootChild] }
            return rootChild.childNodes.filter { $0.name?.starts(with: "plant_") == true }
        }
        for node in plantNodes {
            let id = plantIdLocal(of: node)
            if let snapshot = preMorphAdjustment[id] {
                node.simdWorldTransform = snapshot
            }
        }
        deselectAll()
    }

    // MARK: - Helpers

    func clearNewBoundaryVisuals() {
        guard let arView = arView else { return }
        arView.scene.rootNode.childNodes
            .filter { $0.name == "manual_replacement_new_boundary_point" || $0.name == "manual_replacement_new_boundary_edges" }
            .forEach { $0.removeFromParentNode() }
    }

    func refreshNewBoundaryArea() {
        let pts = parentProps?.newBoundaryPoints ?? []
        guard pts.count > 2 else {
            parentProps?.newBoundaryArea = 0
            return
        }
        var sum: Float = 0
        for i in 0..<pts.count {
            let j = (i + 1) % pts.count
            sum += (pts[i].x * pts[j].z) - (pts[i].z * pts[j].x)
        }
        parentProps?.newBoundaryArea = abs(sum) / 2
    }

    func refreshNewBoundaryEdges() {
        guard let arView = arView else { return }
        let pts = parentProps?.newBoundaryPoints ?? []
        arView.scene.rootNode.childNodes
            .filter { $0.name == "manual_replacement_new_boundary_edges" }
            .forEach { $0.removeFromParentNode() }
        guard pts.count >= 2 else { return }
        GhostRenderer.drawBoundary(
            points: pts,
            color: UIColor(hex: "#2BEE79"),
            opacity: 0.85,
            in: arView.scene,
            name: "manual_replacement_new_boundary_edges"
        )
    }

    func drawGhostMarker(for mp: MorphedPlant, instanceIndex: Int, in scene: SCNScene) {
        // Lightweight marker: small floating sphere at the morphed XZ
        // (we don't load USDZ here to keep preview cheap and snappy).
        // The name embeds the instance INDEX so multiple instances of
        // the same catalog plant get distinct, identifiable markers.
        let isWarn = mp.warning != nil
        let color: UIColor = isWarn ? UIColor.systemOrange : UIColor(hex: "#FFD86F")
        let sphere = SCNSphere(radius: 0.06)
        sphere.firstMaterial?.diffuse.contents = color
        sphere.firstMaterial?.emission.contents = color
        sphere.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: sphere)
        node.opacity = 0.7
        node.simdTransform = mp.newTransform
        node.name = "ghost_morphed_\(instanceIndex)_\(mp.plantId)"
        scene.rootNode.addChildNode(node)
    }

    func snapshotPreMorphAdjustment() {
        guard let arView = arView else { return }
        preMorphAdjustment.removeAll()
        // Walk anchor children too (Issue #113).
        let plantNodes: [SCNNode] = arView.scene.rootNode.childNodes.flatMap { rootChild -> [SCNNode] in
            if rootChild.name?.starts(with: "plant_") == true { return [rootChild] }
            return rootChild.childNodes.filter { $0.name?.starts(with: "plant_") == true }
        }
        for node in plantNodes {
            let id = plantIdLocal(of: node)
            preMorphAdjustment[id] = node.simdWorldTransform
        }
    }

    // Identity readers — prefer KVC values stashed on the node
    // (audit item 7). Legacy fallback parses the name for older nodes
    // that pre-date the KVC migration. Suffix `Local` to avoid colliding
    // with similarly-named helpers on the Coordinator elsewhere.
    private func plantIdLocal(of node: SCNNode) -> String {
        if let id = node.arborePlantId { return id }
        let parts = (node.name ?? "").components(separatedBy: "_")
        return parts.count >= 2 ? parts[1] : (node.name ?? "")
    }

    func averageY(of points: [SIMD3<Float>]) -> Float {
        guard !points.isEmpty else { return 0 }
        return points.reduce(Float(0)) { $0 + $1.y } / Float(points.count)
    }

    /// Resamples a polygon to a target vertex count by uniform arc-length
    /// interpolation along its edges. Required because the OLD boundary may
    /// have a different number of vertices than the user-traced new one.
    func resamplePolygon(_ poly: [SIMD3<Float>], toCount target: Int) -> [SIMD3<Float>] {
        guard poly.count >= 2, target >= 3 else { return poly }
        if poly.count == target { return poly }

        // Total perimeter (closed polygon).
        var perimeter: Float = 0
        let n = poly.count
        for i in 0..<n {
            perimeter += simd_length(poly[(i + 1) % n] - poly[i])
        }
        guard perimeter > 1e-5 else { return poly }

        let step = perimeter / Float(target)
        var result: [SIMD3<Float>] = []
        var edgeIdx = 0
        var distAlongEdge: Float = 0
        var edgeStart = poly[0]
        var edgeEnd = poly[1 % n]
        var edgeLen = simd_length(edgeEnd - edgeStart)

        for i in 0..<target {
            let target = Float(i) * step
            while distAlongEdge + edgeLen < target && edgeIdx < n - 1 {
                distAlongEdge += edgeLen
                edgeIdx += 1
                edgeStart = poly[edgeIdx]
                edgeEnd = poly[(edgeIdx + 1) % n]
                edgeLen = simd_length(edgeEnd - edgeStart)
            }
            let t = edgeLen > 1e-5 ? (target - distAlongEdge) / edgeLen : 0
            result.append(edgeStart + (edgeEnd - edgeStart) * simd_clamp(t, 0, 1))
        }
        return result
    }
}
