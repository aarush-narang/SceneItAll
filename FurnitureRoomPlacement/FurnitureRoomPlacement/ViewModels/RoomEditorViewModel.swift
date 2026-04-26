import SwiftUI
import SceneKit
import Combine

enum FurnitureInteractionMode {
    case view
    case move
}

@MainActor
final class RoomEditorViewModel: ObservableObject {
    let scene: SCNScene
    let title: String
    let baseRoomData: Data
    let designID: String

    @Published var placedObjects: [PlacedFurnitureObject]
    @Published var hasOverlayedExternalUSDZ: Bool
    @Published var areWallsDimmed = false
    @Published var furnitureInteractionMode: FurnitureInteractionMode = .view
    @Published var showFurnitureCatalog = false

    @Published var exportDocument: JSONExportDocument?
    @Published var isShowingSaveExporter = false
    @Published var exportErrorMessage = ""
    @Published var isShowingExportError = false

    @Published var syncErrorMessage = ""
    @Published var isShowingSyncError = false
    @Published var isShowingOverlayError = false

    @Published var isShowingAssistant = false
    @Published var isAssistantLoading = false
    @Published var isPlacementCleanupLoading = false
    @Published var assistantDraft = ""
    @Published var assistantMessages: [ImportedRoomAssistantMessage] = [
        ImportedRoomAssistantMessage(
            role: .assistant,
            text: "Ask about the current room layout. Your message and the latest blueprint JSON will be sent to the agent."
        )
    ]
    @Published var pendingPlacementPreview: [String: FurniturePlacement] = [:]
    @Published var selectedObject: PlacedFurnitureObject?

    private var agentSessionID: String?
    private var previewOriginalPlacements: [String: FurniturePlacement] = [:]
    private let initialPlacedObjects: [PlacedFurnitureObject]
    private var hasRestoredSavedFurniture = false

    var hasPendingPlacementPreview: Bool { !pendingPlacementPreview.isEmpty }
    var isBusy: Bool { isAssistantLoading || isPlacementCleanupLoading }

    var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Imported Room" : trimmed
    }

    var defaultExportFileName: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "BarebonesRoom" : "\(trimmed)_furnished"
    }

    nonisolated init(
        scene: SCNScene,
        title: String,
        baseRoomData: Data,
        initialPlacedObjects: [PlacedFurnitureObject],
        designID: String
    ) {
        self.scene = scene
        self.title = title
        self.baseRoomData = baseRoomData
        self.designID = designID
        self.initialPlacedObjects = initialPlacedObjects
        self._placedObjects = Published(initialValue: initialPlacedObjects)
        self._hasOverlayedExternalUSDZ = Published(initialValue: !initialPlacedObjects.isEmpty)
    }

    // MARK: - Wall Opacity

    func toggleWallDimming() {
        areWallsDimmed.toggle()
        let opacity: CGFloat = areWallsDimmed ? 0.5 : 1.0
        let writesToDepth = !areWallsDimmed
        for wallNode in scene.rootNode.childNodes(passingTest: { n, _ in n.name?.hasPrefix("wall-") == true }) {
            setOpacity(opacity, on: wallNode)
        }
        for shellNode in scene.rootNode.childNodes(passingTest: { n, _ in
            guard let name = n.name else { return false }
            return name.hasPrefix("wall-") || name.hasPrefix("door-") || name.hasPrefix("window-") || name.hasPrefix("opening-")
        }) {
            setDepthWrite(writesToDepth, on: shellNode)
        }
    }

    private func setOpacity(_ opacity: CGFloat, on node: SCNNode) {
        node.opacity = opacity
        node.geometry?.materials.forEach { $0.transparency = opacity }
        node.childNodes.forEach { setOpacity(opacity, on: $0) }
    }

    private func setDepthWrite(_ writes: Bool, on node: SCNNode) {
        node.geometry?.materials.forEach { $0.writesToDepthBuffer = writes }
        node.childNodes.forEach { setDepthWrite(writes, on: $0) }
    }

    // MARK: - Interaction Mode

    func toggleMoveMode() {
        furnitureInteractionMode = furnitureInteractionMode == .move ? .view : .move
    }

    // MARK: - Export

    func saveRoomJSON() {
        do {
            let updatedObjects = placedObjects.map { currentPlacement(for: $0) }
            let updatedData = try BarebonesRoomJSONSanitizer.roomData(byUpdatingObjects: updatedObjects, in: baseRoomData)
            exportDocument = JSONExportDocument(data: updatedData)
            isShowingSaveExporter = true
        } catch {
            exportErrorMessage = error.localizedDescription
            isShowingExportError = true
        }
    }

    // MARK: - Furniture Management

    func handleFurnitureAdded(_ placedObject: PlacedFurnitureObject) {
        placedObjects.append(placedObject)
        Task { await syncAddedFurnitureObject(placedObject) }
    }

    func handleObjectTapped(_ identifier: String) {
        guard let object = placedObjects.first(where: { $0.id == identifier }) else { return }
        selectedObject = currentPlacement(for: object)
    }

    func deleteSelectedObject() {
        guard let object = selectedObject else { return }
        let identifier = object.id

        let nodeName = BarebonesRoomSceneBuilder.overlayNodeName(for: identifier)
        scene.rootNode
            .childNode(withName: nodeName, recursively: true)?
            .removeFromParentNode()

        placedObjects.removeAll { $0.id == identifier }
        pendingPlacementPreview.removeValue(forKey: identifier)
        previewOriginalPlacements.removeValue(forKey: identifier)
        selectedObject = nil

        if placedObjects.isEmpty {
            hasOverlayedExternalUSDZ = false
            if furnitureInteractionMode == .move {
                furnitureInteractionMode = .view
            }
        }

        Task { await syncRemovedFurnitureObject(identifier) }
    }

    private func syncRemovedFurnitureObject(_ identifier: String) async {
        do {
            try await FurnitureAPIClient.shared.removeObjectFromDesign(
                instanceID: identifier,
                designID: designID,
                designName: resolvedTitle
            )
        } catch {
            syncErrorMessage = error.localizedDescription
            isShowingSyncError = true
        }
    }

    private func syncAddedFurnitureObject(_ object: PlacedFurnitureObject) async {
        do {
            try await FurnitureAPIClient.shared.addObjectToDesign(
                currentPlacement(for: object),
                designID: designID,
                designName: resolvedTitle
            )
        } catch {
            syncErrorMessage = error.localizedDescription
            isShowingSyncError = true
        }
    }

    // MARK: - Assistant

    func handleAssistantSend() {
        let trimmedPrompt = assistantDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, !isBusy else { return }
        assistantMessages.append(ImportedRoomAssistantMessage(role: .user, text: trimmedPrompt))
        assistantDraft = ""
        Task { await sendAssistantMessage(prompt: trimmedPrompt) }
    }

    func handlePlacementCleanup() {
        guard !placedObjects.isEmpty, !isBusy, pendingPlacementPreview.isEmpty else { return }
        Task { await requestPlacementCleanupSuggestions() }
    }

    func acceptPlacementCleanupPreview() {
        guard !pendingPlacementPreview.isEmpty else { return }
        let updatedObjects = placedObjects
        pendingPlacementPreview = [:]
        previewOriginalPlacements = [:]
        Task { await persistPlacementUpdates(updatedObjects) }
    }

    func declinePlacementCleanupPreview() {
        guard !previewOriginalPlacements.isEmpty else { return }
        applyPlacementsToScene(previewOriginalPlacements)
        placedObjects = applyingPlacements(previewOriginalPlacements, to: placedObjects)
        pendingPlacementPreview = [:]
        previewOriginalPlacements = [:]
    }

    // MARK: - Assistant Internals

    private func makeAssistantRequest(prompt: String) throws -> ImportedRoomAssistantRequest {
        let updatedObjects = placedObjects.map { currentPlacement(for: $0) }
        let sanitizedData = try RoomJSONSanitizer.sanitizedJSONData(from: baseRoomData, appending: updatedObjects)
        return ImportedRoomAssistantRequest(
            prompt: prompt,
            sanitizedJSONString: String(decoding: sanitizedData, as: UTF8.self)
        )
    }

    private func sendAssistantMessage(prompt: String) async {
        isAssistantLoading = true
        defer { isAssistantLoading = false }
        do {
            let request = try makeAssistantRequest(prompt: prompt)
            let response = try await FurnitureAPIClient.shared.agentChat(
                message: """
                User message:
                \(request.prompt)

                Current blueprint JSON:
                \(request.sanitizedJSONString)
                """,
                sessionID: agentSessionID,
                designID: designID
            )
            agentSessionID = response.sessionID
            if response.placements.isEmpty {
                appendMessage(response.assistantText)
                if !response.toolCalls.isEmpty {
                    await refreshSceneFromDesignObjects()
                }
            } else {
                applyPlacementResponse(response, fallbackMessage: "Updated the room layout using the returned placement suggestions.")
            }
        } catch {
            assistantMessages.append(ImportedRoomAssistantMessage(role: .assistant, text: "I couldn't reach the room assistant: \(error.localizedDescription)"))
        }
    }

    private func requestPlacementCleanupSuggestions() async {
        isPlacementCleanupLoading = true
        defer { isPlacementCleanupLoading = false }
        do {
            let cleanupPrompt = """
            Suggest improved placements for the furniture already in this room.
            Focus on fixing hovering objects, objects intersecting other geometry, and objects that should sit against a wall but are floating away from it.
            Return the revised placements in the structured `placements` field using the existing object ids and placement arrays, and summarize the reasoning briefly in `assistant_text`.
            """
            let request = try makeAssistantRequest(prompt: cleanupPrompt)
            let response = try await FurnitureAPIClient.shared.agentChat(
                message: """
                Placement cleanup task:
                \(request.prompt)

                Use the current object ids exactly as they appear in the JSON.
                Only suggest updates for objects that need repositioning or reorientation.
                Do not add or delete furniture.
                Put only the human-readable summary in `assistant_text`.
                Put all coordinate changes only in `placements`.

                Current blueprint JSON:
                \(request.sanitizedJSONString)
                """,
                sessionID: agentSessionID,
                designID: designID
            )
            agentSessionID = response.sessionID
            applyPlacementResponse(response, fallbackMessage: "Previewing updated furniture placements. Use Accept or Decline to confirm.")
        } catch {
            assistantMessages.append(ImportedRoomAssistantMessage(role: .assistant, text: "I couldn't generate cleanup suggestions: \(error.localizedDescription)"))
        }
    }

    private func applyPlacementResponse(_ response: AgentChatResponse, fallbackMessage: String) {
        let rawSuggested = response.placements.reduce(into: [String: FurniturePlacement]()) { $0[$1.objectID] = $1.placement }
        guard !rawSuggested.isEmpty else {
            appendMessage(response.assistantText)
            return
        }
        let suggested = correctedAgentPlacements(rawSuggested)
        let current = placedObjects.map { currentPlacement(for: $0) }
        previewOriginalPlacements = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0.placement) })
        pendingPlacementPreview = suggested
        placedObjects = applyingPlacements(suggested, to: current)
        applyPlacementsToScene(suggested)
        appendMessage(cleanSummary(from: response.assistantText) ?? fallbackMessage)
    }

    /// The agent's placement contract (`place_item.py`) sets `position.y` to the
    /// BOTTOM of the item — `position.y = floor_y`. Our SCN overlay containers
    /// pivot at the AABB CENTER, so applying that y verbatim sinks each model
    /// by `halfHeight` into the floor. Add the model's measured half-height to
    /// land the bottom on the floor and keep the stored placement consistent
    /// with manually-placed items (which already use center-Y).
    private func correctedAgentPlacements(
        _ raw: [String: FurniturePlacement]
    ) -> [String: FurniturePlacement] {
        var corrected: [String: FurniturePlacement] = [:]
        for (objectID, placement) in raw {
            let nodeName = BarebonesRoomSceneBuilder.overlayNodeName(for: objectID)
            guard let node = scene.rootNode.childNode(withName: nodeName, recursively: true) else {
                corrected[objectID] = placement
                continue
            }
            corrected[objectID] = liftedToCenterY(placement, halfHeight: BarebonesRoomSceneBuilder.placementHalfHeight(of: node))
        }
        return corrected
    }

    /// Apply a persisted placement (from MongoDB) to a freshly-loaded overlay
    /// node. Three backend paths feed into this, and they each need different
    /// handling because they don't agree on what `position.y` means:
    ///
    ///   - LLM agent (`place_item.py`): stores BOTTOM-Y (`position.y = floor_y`).
    ///     Lift by `halfHeight` so the AABB center matches the container pivot.
    ///   - LiDAR scanner (`pipeline/placement.py`): stores CENTER-Y derived
    ///     from the *detected* bbox bottom, which can sit a few cm above the
    ///     actual floor due to scan imprecision. Snap Y to `floor + halfHeight`
    ///     so items rest on the ground rather than hovering.
    ///   - User catalog (iOS `addObjectToDesign`): stores CENTER-Y read off
    ///     the SCN node directly. Apply as-is.
    ///
    /// LiDAR and LLM-agent items both use `placedBy == "agent"` (the backend's
    /// schema only allows "user" or "agent"), so we use the LiDAR-only
    /// `rationale == "Matched from LiDAR scan"` marker to tell them apart.
    private func applyPersistedPlacement(of object: PlacedFurnitureObject, to node: SCNNode) {
        let halfHeight = BarebonesRoomSceneBuilder.placementHalfHeight(of: node)

        if object.rationale == "Matched from LiDAR scan",
           let floor = BarebonesRoomSceneBuilder.floorY(in: scene.rootNode) {
            var snapped = object.placement
            while snapped.position.count < 3 {
                snapped.position.append(0)
            }
            snapped.position[1] = floor + halfHeight
            snapped.apply(to: node)
            return
        }

        guard object.placedBy == "agent" else {
            object.placement.apply(to: node)
            return
        }
        liftedToCenterY(object.placement, halfHeight: halfHeight).apply(to: node)
    }

    private func liftedToCenterY(_ placement: FurniturePlacement, halfHeight: Float) -> FurniturePlacement {
        var fixed = placement
        while fixed.position.count < 3 {
            fixed.position.append(0)
        }
        fixed.position[1] += halfHeight
        return fixed
    }

    private func appendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        assistantMessages.append(ImportedRoomAssistantMessage(role: .assistant, text: trimmed))
    }

    private func cleanSummary(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let blocked = ["\"placements\"", "\"assistant_text\"", "\"tool_calls\"", "```json", "```"]
        guard !blocked.contains(where: trimmed.localizedCaseInsensitiveContains) else { return nil }
        return trimmed
    }

    func currentPlacement(for object: PlacedFurnitureObject) -> PlacedFurnitureObject {
        let nodeName = BarebonesRoomSceneBuilder.overlayNodeName(for: object.id)
        guard let node = scene.rootNode.childNode(withName: nodeName, recursively: true) else { return object }
        var updated = object
        updated.placement = FurniturePlacement(from: node)
        return updated
    }

    private func applyingPlacements(_ placements: [String: FurniturePlacement], to objects: [PlacedFurnitureObject]) -> [PlacedFurnitureObject] {
        objects.map { obj in
            guard let p = placements[obj.id] else { return obj }
            var updated = obj
            updated.placement = p
            return updated
        }
    }

    private func applyPlacementsToScene(_ placements: [String: FurniturePlacement]) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.25
        for (objectID, placement) in placements {
            let nodeName = BarebonesRoomSceneBuilder.overlayNodeName(for: objectID)
            guard let node = scene.rootNode.childNode(withName: nodeName, recursively: true) else { continue }
            placement.apply(to: node)
        }
        SCNTransaction.commit()
    }

    private func persistPlacementUpdates(_ objects: [PlacedFurnitureObject]) async {
        do {
            try await FurnitureAPIClient.shared.updateObjectsInDesign(
                objects,
                designID: designID,
                designName: resolvedTitle
            )
        } catch {
            syncErrorMessage = error.localizedDescription
            isShowingSyncError = true
        }
    }

    private func refreshSceneFromDesignObjects() async {
        do {
            let fetchedObjects = try await FurnitureAPIClient.shared.fetchDesignObjects(designID: designID)
            await rebuildSceneOverlays(using: fetchedObjects)
        } catch {
            syncErrorMessage = error.localizedDescription
            isShowingSyncError = true
        }
    }

    private func rebuildSceneOverlays(using objects: [PlacedFurnitureObject]) async {
        removeExistingOverlayNodes()

        var restoredAnyObject = false
        for object in objects {
            guard let remoteURL = object.furniture.remoteUSDZURL else { continue }
            do {
                let localURL = try await RemoteUSDZCache.shared.localFileURL(for: remoteURL)
                let didAdd = BarebonesRoomSceneBuilder.overlayExternalUSDZ(
                    on: scene,
                    fileURL: localURL,
                    overlayIdentifier: object.id
                )
                guard didAdd else { continue }
                let nodeName = BarebonesRoomSceneBuilder.overlayNodeName(for: object.id)
                if let restoredNode = scene.rootNode.childNode(withName: nodeName, recursively: true) {
                    applyPersistedPlacement(of: object, to: restoredNode)
                    restoredAnyObject = true
                }
            } catch {
                isShowingOverlayError = true
            }
        }

        placedObjects = objects
        hasOverlayedExternalUSDZ = restoredAnyObject
    }

    private func removeExistingOverlayNodes() {
        scene.rootNode
            .childNodes(passingTest: { node, _ in
                node.name?.hasPrefix(BarebonesRoomSceneBuilder.overlayNodeNamePrefix) == true
            })
            .forEach { $0.removeFromParentNode() }
    }

    // MARK: - Restoration

    func restoreSavedFurnitureIfNeeded() async {
        guard !hasRestoredSavedFurniture else { return }
        hasRestoredSavedFurniture = true

        for object in initialPlacedObjects {
            let nodeName = BarebonesRoomSceneBuilder.overlayNodeName(for: object.id)
            if scene.rootNode.childNode(withName: nodeName, recursively: true) != nil { continue }
            do {
                guard let remoteURL = object.furniture.remoteUSDZURL else { continue }
                let localURL = try await RemoteUSDZCache.shared.localFileURL(for: remoteURL)
                let didAdd = BarebonesRoomSceneBuilder.overlayExternalUSDZ(on: scene, fileURL: localURL, overlayIdentifier: object.id)
                guard didAdd else { continue }
                if let restoredNode = scene.rootNode.childNode(withName: nodeName, recursively: true) {
                    applyPersistedPlacement(of: object, to: restoredNode)
                }
                hasOverlayedExternalUSDZ = true
            } catch {
                isShowingOverlayError = true
            }
        }
    }
}
