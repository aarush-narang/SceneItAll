/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
SwiftUI onboarding and unsupported-device screens.
*/

import SwiftUI
import RoomPlan
import SceneKit
import UniformTypeIdentifiers
import UIKit

private struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private enum FurnitureInteractionMode {
    case view
    case move
}

struct OnboardingView: View {
    private struct ScanResult {
        let scene: SCNScene
        let roomData: Data
        let capturedRoom: CapturedRoom
        let capturedFrames: [CapturedFrame]
    }

    @State private var isShowingCaptureView = false
    @State private var isShowingUnsupportedDeviceSheet = false
    @State private var isShowingImporter = false
    @State private var importedScene: SCNScene?
    @State private var importedRoomData: Data?
    @State private var importedPlacedObjects: [PlacedFurnitureObject] = []
    @State private var importedFileName = ""
    @State private var importErrorMessage = ""
    @State private var isShowingImportError = false
    @State private var pendingScanResult: ScanResult?
    @State private var scanCapturedRoom: CapturedRoom?
    @State private var scanCapturedFrames: [CapturedFrame] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            Text("Create a 3D model of a room")
                .font(.largeTitle.weight(.bold))

            VStack(alignment: .leading, spacing: 12) {
                Label("Move slowly and keep walls, windows, and doors in view.", systemImage: "camera.viewfinder")
                Label("Walk the perimeter of the room before capturing details.", systemImage: "square.dashed")
                Label("Finish scanning when the room outline looks complete.", systemImage: "checkmark.circle")
            }
            .font(.headline)
            .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 12) {
                Button("Start Scan") {
                    if RoomCaptureSession.isSupported {
                        isShowingCaptureView = true
                    } else {
                        isShowingUnsupportedDeviceSheet = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .center)

                Button("Import Existing Design JSON") {
                    isShowingImporter = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .fullScreenCover(isPresented: $isShowingCaptureView, onDismiss: handleScanDismiss) {
            RoomCaptureContainerView { scene, data, room, frames in
                pendingScanResult = ScanResult(scene: scene, roomData: data, capturedRoom: room, capturedFrames: frames)
            }
        }
        .sheet(isPresented: $isShowingUnsupportedDeviceSheet) {
            NavigationStack {
                UnsupportedDeviceView()
                    .navigationTitle("Unavailable")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") {
                                isShowingUnsupportedDeviceSheet = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .fullScreenCover(item: $importedScene) { scene in
            ImportedRoomShellView(
                scene: scene,
                title: importedFileName,
                baseRoomData: importedRoomData ?? Data(),
                initialPlacedObjects: importedPlacedObjects,
                capturedRoom: scanCapturedRoom,
                capturedFrames: scanCapturedFrames
            )
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Import Failed", isPresented: $isShowingImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importErrorMessage)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let fileURL = try result.get().first else { return }
            let didAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: fileURL)
            let scene: SCNScene
            let roomData: Data
            let objects: [PlacedFurnitureObject]

            if let payload = try? JSONDecoder().decode(SanitizedRoomPayload.self, from: data) {
                scene = BarebonesRoomSceneBuilder.scene(for: payload)
                roomData = data
                objects = payload.objects
            } else {
                let normalizedData = try BarebonesRoomJSONSanitizer.normalizedRoomData(from: data)
                scene = try BarebonesRoomImportLoader.loadScene(from: normalizedData)
                roomData = normalizedData
                objects = (try? BarebonesRoomImportLoader.loadPlacedObjects(from: normalizedData)) ?? []
            }

            scanCapturedRoom = nil
            scanCapturedFrames = []
            importedRoomData = roomData
            importedPlacedObjects = objects
            importedFileName = fileURL.deletingPathExtension().lastPathComponent
            importedScene = scene
        } catch {
            importErrorMessage = error.localizedDescription
            isShowingImportError = true
        }
    }

    private func handleScanDismiss() {
        guard let result = pendingScanResult else { return }
        pendingScanResult = nil

        scanCapturedRoom = result.capturedRoom
        scanCapturedFrames = result.capturedFrames
        importedRoomData = result.roomData
        importedPlacedObjects = []
        importedFileName = "Scanned Room"
        importedScene = result.scene
    }
}

struct UnsupportedDeviceView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("RoomPlan is unavailable on this device.")
                .font(.title3.weight(.semibold))

            Text("Run the app on a LiDAR-enabled iPhone or iPad to capture a room.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

struct ImportedRoomShellView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingOverlayError = false
    @State private var hasOverlayedExternalUSDZ = false
    @State private var areWallsDimmed = false
    @State private var showFurnitureCatalog: Bool = false
    @State private var furnitureInteractionMode: FurnitureInteractionMode = .view
    @State private var placedObjects: [PlacedFurnitureObject] = []
    @State private var exportDocument: JSONExportDocument?
    @State private var isShowingSaveExporter = false
    @State private var exportErrorMessage = ""
    @State private var isShowingExportError = false
    @State private var hasRestoredSavedFurniture = false
    @State private var isShowingAssistant = false
    @State private var assistantDraft = ""
    @State private var assistantMessages: [ImportedRoomAssistantMessage] = [
        ImportedRoomAssistantMessage(
            role: .assistant,
            text: "Ask about the current room layout. The latest sanitized JSON will be prepared when you send."
        )
    ]
    @State private var isMatchingFurniture = false
    @State private var matchingStatus = ""
    @State private var showMatchingFailure = false
    @State private var matchingErrorMessage = ""

    let scene: SCNScene
    let title: String
    let baseRoomData: Data
    let initialPlacedObjects: [PlacedFurnitureObject]
    let capturedRoom: CapturedRoom?
    let capturedFrames: [CapturedFrame]

    init(
        scene: SCNScene,
        title: String,
        baseRoomData: Data,
        initialPlacedObjects: [PlacedFurnitureObject],
        capturedRoom: CapturedRoom? = nil,
        capturedFrames: [CapturedFrame] = []
    ) {
        self.scene = scene
        self.title = title
        self.baseRoomData = baseRoomData
        self.initialPlacedObjects = initialPlacedObjects
        self.capturedRoom = capturedRoom
        self.capturedFrames = capturedFrames
        _placedObjects = State(initialValue: initialPlacedObjects)
        _hasOverlayedExternalUSDZ = State(initialValue: !initialPlacedObjects.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomLeading) {
                ImportedRoomSceneView(
                    scene: scene,
                    interactionMode: furnitureInteractionMode
                )
                .background(Color(white: 0.72))
                .ignoresSafeArea()

                if isMatchingFurniture {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(matchingStatus)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 32)
                }

                ImportedRoomAssistantOverlay(
                    isPresented: $isShowingAssistant,
                    draft: $assistantDraft,
                    messages: assistantMessages,
                    onSend: handleAssistantSend
                )
            }
            .navigationTitle(title.isEmpty ? "Imported Room" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
//                    Button(hasOverlayedExternalUSDZ ? "USDZ Added" : "Overlay USDZ") {
//                        let didAddOverlay = BarebonesRoomSceneBuilder.overlayExternalUSDZ(on: scene)
//                        hasOverlayedExternalUSDZ = didAddOverlay || hasOverlayedExternalUSDZ
//                        isShowingOverlayError = !didAddOverlay
//                    }
//                    .disabled(hasOverlayedExternalUSDZ)
                    Button("Add Furniture") {
                        showFurnitureCatalog.toggle()
                    }

                    Button(
                        furnitureInteractionMode == .move ? "Done Moving" : "Move Furniture"
                    ) {
                        furnitureInteractionMode = furnitureInteractionMode == .move ? .view : .move
                    }
                    .disabled(!hasOverlayedExternalUSDZ)

                    Button(areWallsDimmed ? "Walls 100%" : "Walls 50%") {
                        areWallsDimmed.toggle()
                        updateWallOpacity(in: scene, opacity: areWallsDimmed ? 0.5 : 1.0)
                        updateShellDepth(in: scene, writesToDepthBuffer: !areWallsDimmed)
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !placedObjects.isEmpty {
                        Button("Export") {
                            saveRoomJSON()
                        }
                    }

                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Unable to Overlay USDZ", isPresented: $isShowingOverlayError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The app could not load the external USDZ asset.")
            }
            .alert("Save Failed", isPresented: $isShowingExportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(exportErrorMessage)
            }
            .alert("Furniture Matching Failed", isPresented: $showMatchingFailure) {
                Button("Retry") {
                    Task { await matchFurniture() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(matchingErrorMessage)
            }
            .onChange(of: hasOverlayedExternalUSDZ) { _, hasOverlay in
                if !hasOverlay {
                    furnitureInteractionMode = .view
                }
            }
            .task {
                await restoreSavedFurnitureIfNeeded()
                if capturedRoom != nil {
                    await matchFurniture()
                }
            }
            .fileExporter(
                isPresented: $isShowingSaveExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: defaultExportFileName
            ) { result in
                if case .failure(let error) = result {
                    exportErrorMessage = error.localizedDescription
                    isShowingExportError = true
                }
            }
            .sheet(isPresented: $showFurnitureCatalog) {
                NavigationStack {
                    FurnitureCatalogListView(
                        showFurnitureCatalog: $showFurnitureCatalog,
                        hasOverlayedExternalUSDZ: $hasOverlayedExternalUSDZ,
                        scene: scene,
                        onFurnitureAdded: { placedObject in
                            placedObjects.append(placedObject)
                        }
                    )
                }
                .presentationDetents([.fraction(0.92), .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func updateWallOpacity(in scene: SCNScene, opacity: CGFloat) {
        let wallNodes = scene.rootNode.childNodes(passingTest: { node, _ in
            node.name?.hasPrefix("wall-") == true
        })

        for wallNode in wallNodes {
            updateOpacityRecursively(for: wallNode, opacity: opacity)
        }
    }

    private func updateShellDepth(in scene: SCNScene, writesToDepthBuffer: Bool) {
        let shellNodes = scene.rootNode.childNodes(passingTest: { node, _ in
            guard let name = node.name else {
                return false
            }

            return name.hasPrefix("wall-")
                || name.hasPrefix("door-")
                || name.hasPrefix("window-")
                || name.hasPrefix("opening-")
        })

        for shellNode in shellNodes {
            updateDepthRecursively(for: shellNode, writesToDepthBuffer: writesToDepthBuffer)
        }
    }

    private func updateOpacityRecursively(for node: SCNNode, opacity: CGFloat) {
        node.opacity = opacity

        if let geometry = node.geometry {
            for material in geometry.materials {
                material.transparency = opacity
            }
        }

        for childNode in node.childNodes {
            updateOpacityRecursively(for: childNode, opacity: opacity)
        }
    }

    private func updateDepthRecursively(for node: SCNNode, writesToDepthBuffer: Bool) {
        if let geometry = node.geometry {
            for material in geometry.materials {
                material.writesToDepthBuffer = writesToDepthBuffer
            }
        }

        for childNode in node.childNodes {
            updateDepthRecursively(for: childNode, writesToDepthBuffer: writesToDepthBuffer)
        }
    }

    private var defaultExportFileName: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "BarebonesRoom" : "\(trimmedTitle)_furnished"
    }

    private func saveRoomJSON() {
        do {
            let updatedObjects = placedObjects.map(currentPlacement(for:))
            let updatedData = try exportableJSONData(with: updatedObjects)
            exportDocument = JSONExportDocument(data: updatedData)
            isShowingSaveExporter = true
        } catch {
            exportErrorMessage = error.localizedDescription
            isShowingExportError = true
        }
    }

    private func exportableJSONData(with objects: [PlacedFurnitureObject]) throws -> Data {
        if let payload = try? JSONDecoder().decode(SanitizedRoomPayload.self, from: baseRoomData) {
            let updated = SanitizedRoomPayload(
                schemaVersion: payload.schemaVersion,
                units: payload.units,
                room: payload.room,
                walls: payload.walls,
                openings: payload.openings,
                objects: objects,
                metadata: SanitizedMetadata(
                    sourceVersion: payload.metadata.sourceVersion,
                    generatedAt: ISO8601DateFormatter().string(from: Date())
                )
            )
            return try RoomJSONSanitizer.sanitizedJSONData(from: updated)
        }
        return try RoomJSONSanitizer.sanitizedJSONData(from: baseRoomData, appending: objects)
    }

    private func handleAssistantSend() {
        let trimmedPrompt = assistantDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return
        }

        assistantMessages.append(
            ImportedRoomAssistantMessage(role: .user, text: trimmedPrompt)
        )
        assistantDraft = ""

        do {
            let request = try makeAssistantRequest(prompt: trimmedPrompt)
            assistantMessages.append(
                ImportedRoomAssistantMessage(
                    role: .assistant,
                    text: """
                    Stubbed assistant payload prepared.
                    Prompt: \(request.prompt)
                    Sanitized JSON size: \(request.sanitizedJSONString.count) characters.
                    Replace this branch with your LLM call when the agent endpoint is ready.
                    """
                )
            )
        } catch {
            assistantMessages.append(
                ImportedRoomAssistantMessage(
                    role: .assistant,
                    text: "I couldn’t prepare the room context: \(error.localizedDescription)"
                )
            )
        }
    }

    private func makeAssistantRequest(prompt: String) throws -> ImportedRoomAssistantRequest {
        let updatedObjects = placedObjects.map(currentPlacement(for:))
        let sanitizedData = try exportableJSONData(with: updatedObjects)
        let sanitizedJSONString = String(decoding: sanitizedData, as: UTF8.self)

        return ImportedRoomAssistantRequest(
            prompt: prompt,
            sanitizedJSONString: sanitizedJSONString
        )
    }

    private func currentPlacement(for object: PlacedFurnitureObject) -> PlacedFurnitureObject {
        let nodeName = BarebonesRoomSceneBuilder.overlayNodeName(for: object.id)
        guard let placedNode = scene.rootNode.childNode(withName: nodeName, recursively: true) else {
            return object
        }

        var updatedObject = object
        updatedObject.placement = FurniturePlacement(from: placedNode)
        return updatedObject
    }

    private func restoreSavedFurnitureIfNeeded() async {
        guard !hasRestoredSavedFurniture else {
            return
        }

        hasRestoredSavedFurniture = true

        for object in initialPlacedObjects {
            let nodeName = BarebonesRoomSceneBuilder.overlayNodeName(for: object.id)
            let alreadyLoaded = await MainActor.run {
                scene.rootNode.childNode(withName: nodeName, recursively: true) != nil
            }

            if alreadyLoaded {
                continue
            }

            do {
                guard let remoteURL = object.furniture.remoteUSDZURL else {
                    continue
                }

                let localURL = try await RemoteUSDZCache.shared.localFileURL(for: remoteURL)
                let didAddOverlay = await MainActor.run {
                    BarebonesRoomSceneBuilder.overlayExternalUSDZ(
                        on: scene,
                        fileURL: localURL,
                        overlayIdentifier: object.id
                    )
                }

                guard didAddOverlay else {
                    continue
                }

                await MainActor.run {
                    if let restoredNode = scene.rootNode.childNode(withName: nodeName, recursively: true) {
                        object.placement.apply(to: restoredNode)
                    }
                    hasOverlayedExternalUSDZ = true
                }
            } catch {
                await MainActor.run {
                    isShowingOverlayError = true
                }
            }
        }
    }

    // MARK: - Furniture Matching

    private func matchFurniture() async {
        guard let capturedRoom, !capturedFrames.isEmpty else { return }

        isMatchingFurniture = true
        matchingStatus = "Matching furniture…"

        let uploadClient = ScanUploadClient(
            baseURL: URL(string: "https://poison-groundwater-states-excess.trycloudflare.com")!
        )

        let matchedScene: MatchedScene
        do {
            matchedScene = try await uploadClient.upload(
                room: capturedRoom,
                frames: capturedFrames
            )
        } catch {
            isMatchingFurniture = false
            matchingErrorMessage = error.localizedDescription
            showMatchingFailure = true
            return
        }

        let total = matchedScene.objects.count
        var loaded = 0

        for obj in matchedScene.objects {
            if obj.isMatched, let urlString = obj.matchedUSDZURL, let url = URL(string: urlString) {
                matchingStatus = "Loading \(obj.matchedProductName ?? obj.refinedCategory)… (\(loaded + 1)/\(total))"

                do {
                    let localURL = try await RemoteUSDZCache.shared.localFileURL(for: url)
                    let didAdd = BarebonesRoomSceneBuilder.overlayExternalUSDZ(
                        on: scene,
                        fileURL: localURL,
                        overlayIdentifier: obj.detectedId
                    )
                    if didAdd {
                        let nodeName = BarebonesRoomSceneBuilder.overlayNodeName(for: obj.detectedId)
                        if let node = scene.rootNode.childNode(withName: nodeName, recursively: true) {
                            applyMatchedTransform(obj.transform, to: node)
                        }
                        hasOverlayedExternalUSDZ = true
                    }
                    if let placed = makePlacedObject(from: obj) {
                        placedObjects.append(placed)
                    }
                } catch {
                    print("Failed to load USDZ for \(obj.detectedId): \(error)")
                    addPlaceholderBox(for: obj)
                }
            } else {
                addPlaceholderBox(for: obj)
            }

            loaded += 1
        }

        isMatchingFurniture = false
    }

    private func applyMatchedTransform(_ t: ObjectTransform, to node: SCNNode) {
        node.position = SCNVector3(
            t.position.count > 0 ? t.position[0] : 0,
            t.position.count > 1 ? t.position[1] : 0,
            t.position.count > 2 ? t.position[2] : 0
        )
        node.eulerAngles = SCNVector3(
            t.rotationEuler.count > 0 ? t.rotationEuler[0] : 0,
            t.rotationEuler.count > 1 ? t.rotationEuler[1] : 0,
            t.rotationEuler.count > 2 ? t.rotationEuler[2] : 0
        )
        if t.scale.count >= 3 {
            node.scale = SCNVector3(t.scale[0], t.scale[1], t.scale[2])
        }
    }

    private func addPlaceholderBox(for obj: MatchedObject) {
        let dims = obj.originalBBox.dimensions
        guard dims.count >= 3 else { return }
        let w = CGFloat(dims[0])
        let h = CGFloat(dims[1])
        let d = CGFloat(dims[2])

        let box = SCNBox(width: w, height: h, length: d, chamferRadius: 0)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.15)
        material.isDoubleSided = true
        material.fillMode = .fill
        box.materials = [material]

        let boxNode = SCNNode(geometry: box)

        let wireframe = SCNBox(width: w, height: h, length: d, chamferRadius: 0)
        let wireMaterial = SCNMaterial()
        wireMaterial.diffuse.contents = UIColor.white
        wireMaterial.fillMode = .lines
        wireMaterial.isDoubleSided = true
        wireframe.materials = [wireMaterial]
        let wireNode = SCNNode(geometry: wireframe)
        boxNode.addChildNode(wireNode)

        let text = SCNText(string: obj.refinedCategory, extrusionDepth: 0.005)
        text.font = UIFont.systemFont(ofSize: 0.08, weight: .semibold)
        text.firstMaterial?.diffuse.contents = UIColor.white
        text.firstMaterial?.isDoubleSided = true
        text.flatness = 0.3
        let textNode = SCNNode(geometry: text)
        let (textMin, textMax) = textNode.boundingBox
        let textWidth = textMax.x - textMin.x
        textNode.position = SCNVector3(-textWidth / 2, Float(h) / 2 + 0.05, 0)
        boxNode.addChildNode(textNode)

        let containerNode = SCNNode()
        containerNode.addChildNode(boxNode)
        containerNode.name = "whitebox-\(obj.detectedId)"

        let t = obj.transform
        containerNode.position = SCNVector3(
            t.position.count > 0 ? t.position[0] : 0,
            (t.position.count > 1 ? t.position[1] : 0) + Float(h) / 2,
            t.position.count > 2 ? t.position[2] : 0
        )
        if t.rotationEuler.count >= 2 {
            containerNode.eulerAngles.y = t.rotationEuler[1]
        }

        containerNode.renderingOrder = 900
        scene.rootNode.addChildNode(containerNode)
    }

    private func makePlacedObject(from obj: MatchedObject) -> PlacedFurnitureObject? {
        guard obj.isMatched,
              let productId = obj.matchedProductId,
              let productName = obj.matchedProductName,
              let usdzURL = obj.matchedUSDZURL else { return nil }

        let dims = obj.originalBBox.dimensions
        let snapshot = SavedFurnitureSnapshot(
            id: productId,
            name: productName,
            familyKey: productId,
            dimensionsBbox: DimensionsBbox(
                widthM: Double(dims.count > 0 ? dims[0] : 0),
                heightM: Double(dims.count > 1 ? dims[1] : 0),
                depthM: Double(dims.count > 2 ? dims[2] : 0)
            ),
            files: SavedFurnitureFiles(usdzURL: usdzURL)
        )

        return PlacedFurnitureObject(
            id: obj.detectedId,
            furniture: Furniture(savedSnapshot: snapshot),
            placement: FurniturePlacement(
                position: obj.transform.position,
                eulerAngles: obj.transform.rotationEuler,
                scale: obj.transform.scale
            ),
            addedAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}

private struct ImportedRoomSceneView: UIViewRepresentable {
    let scene: SCNScene
    let interactionMode: FurnitureInteractionMode

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.scene = scene
        scnView.backgroundColor = UIColor(white: 0.72, alpha: 1.0)
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = interactionMode == .view
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        scnView.isPlaying = true

        let panGestureRecognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePanGesture(_:))
        )
        panGestureRecognizer.maximumNumberOfTouches = 1
        scnView.addGestureRecognizer(panGestureRecognizer)

        let rotationGestureRecognizer = UIRotationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRotationGesture(_:))
        )
        scnView.addGestureRecognizer(rotationGestureRecognizer)

        context.coordinator.panGestureRecognizer = panGestureRecognizer
        context.coordinator.rotationGestureRecognizer = rotationGestureRecognizer
        context.coordinator.sceneView = scnView
        context.coordinator.interactionMode = interactionMode
        panGestureRecognizer.delegate = context.coordinator
        rotationGestureRecognizer.delegate = context.coordinator

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        scnView.scene = scene
        scnView.allowsCameraControl = interactionMode == .view
        context.coordinator.sceneView = scnView
        context.coordinator.interactionMode = interactionMode
        context.coordinator.panGestureRecognizer?.isEnabled = interactionMode != .view
        context.coordinator.rotationGestureRecognizer?.isEnabled = interactionMode != .view

        if interactionMode == .view {
            context.coordinator.cancelDragging()
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var sceneView: SCNView?
        weak var draggedNode: SCNNode?
        weak var panGestureRecognizer: UIPanGestureRecognizer?
        weak var rotationGestureRecognizer: UIRotationGestureRecognizer?
        var interactionMode: FurnitureInteractionMode = .view
        var movementPlaneY: Float = 0

        @objc func handlePanGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
            guard interactionMode != .view, let sceneView else {
                cancelDragging()
                return
            }

            let location = gestureRecognizer.location(in: sceneView)

            switch gestureRecognizer.state {
            case .began:
                beginDragging(at: location, in: sceneView)
            case .changed:
                updateDragging(at: location, in: sceneView)
            case .ended, .cancelled, .failed:
                cancelDragging()
            default:
                break
            }
        }

        @objc func handleRotationGesture(_ gestureRecognizer: UIRotationGestureRecognizer) {
            guard interactionMode == .move, let sceneView else {
                cancelDragging()
                return
            }

            let location = gestureRecognizer.location(in: sceneView)

            switch gestureRecognizer.state {
            case .began:
                beginDragging(at: location, in: sceneView)
            case .changed:
                updateRotation(with: gestureRecognizer.rotation)
                gestureRecognizer.rotation = 0
            case .ended, .cancelled, .failed:
                cancelDragging()
            default:
                break
            }
        }

        func cancelDragging() {
            draggedNode = nil
        }

        private func beginDragging(at location: CGPoint, in sceneView: SCNView) {
            let hitResults = sceneView.hitTest(location, options: nil)

            for result in hitResults {
                if let overlayNode = overlayAncestor(for: result.node) {
                    draggedNode = overlayNode
                    movementPlaneY = overlayNode.presentation.worldPosition.y
                    return
                }
            }

            draggedNode = nil
        }

        private func updateDragging(at location: CGPoint, in sceneView: SCNView) {
            guard let draggedNode,
                  let intersection = worldPointOnMovementPlane(for: location, in: sceneView, planeY: movementPlaneY) else {
                return
            }

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            draggedNode.worldPosition = SCNVector3(intersection.x, movementPlaneY, intersection.z)
            SCNTransaction.commit()
        }

        private func updateRotation(with rotation: CGFloat) {
            guard let draggedNode else {
                return
            }

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            draggedNode.eulerAngles.x -= Float(rotation)
            SCNTransaction.commit()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        private func overlayAncestor(for node: SCNNode) -> SCNNode? {
            var currentNode: SCNNode? = node

            while let candidate = currentNode {
                if candidate.name?.hasPrefix("external-usdz-overlay") == true {
                    return candidate
                }
                currentNode = candidate.parent
            }

            return nil
        }

        private func worldPointOnMovementPlane(
            for location: CGPoint,
            in sceneView: SCNView,
            planeY: Float
        ) -> SCNVector3? {
            let nearPoint = sceneView.unprojectPoint(SCNVector3(Float(location.x), Float(location.y), 0))
            let farPoint = sceneView.unprojectPoint(SCNVector3(Float(location.x), Float(location.y), 1))
            let direction = farPoint - nearPoint

            guard abs(direction.y) > 0.0001 else {
                return nil
            }

            let distance = (planeY - nearPoint.y) / direction.y
            guard distance.isFinite else {
                return nil
            }

            return nearPoint + (direction * distance)
        }
    }
}

private func +(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
    SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
}

private func -(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
    SCNVector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
}

private func *(vector: SCNVector3, scalar: Float) -> SCNVector3 {
    SCNVector3(vector.x * scalar, vector.y * scalar, vector.z * scalar)
}

extension SCNScene: @retroactive Identifiable {
    public var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }
}
