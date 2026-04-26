//
//  FurnitureDetailView.swift
//  FurnitureRoomPlacement
//
//  Created by Kelvin Jou on 4/24/26.
//
import SwiftUI
import SceneKit

struct FurnitureCatalogListView: View {
    @Binding var showFurnitureCatalog: Bool
    @Binding var hasOverlayedExternalUSDZ: Bool
    let scene: SCNScene
    let onFurnitureAdded: (PlacedFurnitureObject) -> Void

    @State private var furnitureItems: [Furniture] = []
    @State private var selectedFurniture: Furniture?
    @State private var loadErrorMessage = ""
    @State private var isShowingLoadError = false

    var body: some View {
        FurnitureSearchView(
            onFurnitureSelected: { furniture in
                furnitureItems = updateStoredFurnitureItems(with: furniture)
                selectedFurniture = furniture
            },
            onError: { message in
                loadErrorMessage = message
                isShowingLoadError = true
            }
        )
        .navigationTitle("Furniture Catalog")
        .sheet(item: $selectedFurniture) { furniture in
            FurnitureDetailView(furniture: furniture) { localUSDZURL in
                let objectID = UUID().uuidString
                let addSuccess = BarebonesRoomSceneBuilder.overlayExternalUSDZ(
                    on: scene,
                    fileURL: localUSDZURL,
                    overlayIdentifier: objectID
                )
                if addSuccess {
                    let nodeName = BarebonesRoomSceneBuilder.overlayNodeName(for: objectID)
                    let placedNode = scene.rootNode.childNode(withName: nodeName, recursively: true)
                    let placement = placedNode.map(FurniturePlacement.init(from:)) ?? .defaultPlacement
                    let addedObject = PlacedFurnitureObject(
                        id: objectID,
                        furniture: furniture,
                        placement: placement,
                        addedAt: ISO8601DateFormatter().string(from: Date()),
                        placedBy: "user"
                    )
                    onFurnitureAdded(addedObject)
                    hasOverlayedExternalUSDZ = true
                    showFurnitureCatalog = false
                }
                selectedFurniture = nil
            }
            .presentationDetents([.fraction(0.96), .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Unable to Load Catalog", isPresented: $isShowingLoadError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(loadErrorMessage)
        }
    }

    private func updateStoredFurnitureItems(with furniture: Furniture) -> [Furniture] {
        if let existingIndex = furnitureItems.firstIndex(where: { $0.id == furniture.id }) {
            var updatedItems = furnitureItems
            updatedItems[existingIndex] = furniture
            return updatedItems
        }

        return furnitureItems + [furniture]
    }
}

struct FurnitureDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let furniture: Furniture
    let onAdd: (URL) -> Void

    @State private var previewScene = makePreviewScene()
    @State private var previewState: PreviewState = .loading
    @State private var isAddingToRoom = false
    @State private var actionErrorMessage = ""
    @State private var isShowingActionError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                previewSection
                metadataSection

                Button {
                    Task {
                        await addToRoom()
                    }
                } label: {
                    if isAddingToRoom {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Add To Room")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isAddingToRoom || furniture.remoteUSDZURL == nil)
            }
            .padding(24)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(.secondarySystemBackground).opacity(0.9),
                    Color(.systemBackground),
                    Color(.secondarySystemBackground).opacity(0.7)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .task(id: furniture.id) {
            await loadPreview()
        }
        .alert("Unable to Load Furniture", isPresented: $isShowingActionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(actionErrorMessage)
        }
    }

    private var previewSection: some View {
        SceneView(
            scene: previewScene,
            pointOfView: nil,
            options: [.autoenablesDefaultLighting]
        )
        .frame(height: 360)
        .background(
            Color.black,
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.75)
        }
        .overlay {
            switch previewState {
            case .loading:
                ProgressView("Loading 3D Preview")
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
            case .failed(let message):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                    Text("Preview Unavailable")
                        .font(.headline)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            case .loaded:
                EmptyView()
            }
        }
        .shadow(color: Color.black.opacity(0.08), radius: 24, y: 10)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(furniture.name)
                .font(.title2.weight(.bold))

            DetailSection("Overview") {
                DetailTextBlock(text: furniture.designSummary)
                DetailTextBlock(text: furniture.description)
            }

            DetailSection("Pricing And Rating") {
                DetailFactRow(label: "Price", value: furniture.formattedPrice)
                DetailFactRow(
                    label: "Rating",
                    value: "\(furniture.rating.value.formatted(.number.precision(.fractionLength(1)))) / 5 (\(furniture.rating.count) reviews)"
                )
            }

            DetailSection("Classification") {
                DetailFactRow(label: "Family Key", value: furniture.familyKey)
                DetailFactRow(label: "Source", value: furniture.source.name)
                DetailFactRow(label: "Category", value: furniture.taxonomyInferred.category)
                DetailFactRow(label: "Subcategory", value: furniture.taxonomyInferred.subcategory)
                DetailFactRow(label: "IKEA Leaf", value: furniture.taxonomyIkea.categoryLeaf)
                DetailFactRow(label: "Top Department", value: furniture.taxonomyIkea.topDepartment)
                DetailFactRow(label: "Segment", value: furniture.taxonomyIkea.segment)
                DetailFactRow(label: "Source URL", value: furniture.source.url)
                DetailFactRow(
                    label: "Category Path",
                    value: furniture.taxonomyIkea.categoryPath.joined(separator: " > ")
                )
            }

            DetailSection("Dimensions") {
                DetailFactRow(
                    label: "IKEA Size",
                    value: "\(formattedInches(furniture.dimensionsIkea.widthIn)) W x \(formattedInches(furniture.dimensionsIkea.depthIn)) D x \(formattedInches(furniture.dimensionsIkea.heightIn)) H"
                )
                DetailFactRow(
                    label: "3D Bounding Box",
                    value: "\(formattedMeters(furniture.dimensionsBbox.widthM)) W x \(formattedMeters(furniture.dimensionsBbox.depthM)) D x \(formattedMeters(furniture.dimensionsBbox.heightM)) H"
                )
            }

            DetailSection("Materials And Styling") {
                DetailFactRow(label: "Primary Material", value: furniture.attributes.materialPrimary)
                DetailFactRow(label: "Texture / Finish", value: furniture.attributes.textureAndFinish)
                DetailFactRow(label: "Primary Color", value: furniture.attributes.colorPrimary)
                DetailFactRow(label: "Era", value: furniture.attributes.era)
                DetailFactRow(label: "Design Lineage", value: furniture.attributes.designLineage)
                DetailFactRow(label: "Formality", value: furniture.attributes.formality)
                DetailFactRow(label: "Visual Weight", value: furniture.attributes.visualWeight)
                DetailFactRow(label: "Scale", value: furniture.attributes.scale)
            }

            DetailSection("Placement") {
                DetailFactRow(label: "Room Role", value: furniture.attributes.roomRole)
                DetailFactRow(label: "Space Requirements", value: furniture.attributes.spaceRequirements)
                DetailBoolRow(label: "Has Arms", value: furniture.attributes.hasArms)
                DetailBoolRow(label: "Has Legs", value: furniture.attributes.hasLegs)
                DetailBoolRow(label: "Stackable", value: furniture.attributes.stackable)
            }

            DetailSection("Style Tags") {
                TagBubbleGrid(tags: furniture.attributes.styleTags)
            }

            DetailSection("Ambient Mood") {
                TagBubbleGrid(tags: furniture.attributes.ambientMood)
            }

            DetailSection("Suitable Rooms") {
                TagBubbleGrid(tags: furniture.attributes.suitableRooms)
            }

            DetailSection("Placement Hints") {
                DetailBulletList(items: furniture.attributes.placementHints)
            }

            DetailSection("Pairs Well With") {
                DetailBulletList(items: furniture.attributes.pairsWellWith)
            }

            DetailSection("Use Scenarios") {
                DetailBulletList(items: furniture.attributes.useScenarios)
            }

//            DetailSection("Files") {
//                DetailFactRow(label: "USDZ", value: furniture.files.usdzURL)
//                if !furniture.files.thumbURLs.isEmpty {
//                    DetailFactRow(label: "Thumbnails", value: furniture.files.thumbURLs.joined(separator: "\n"))
//                }
//            }

            DetailSection("Embedding Text") {
                DetailTextBlock(text: furniture.embeddingText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func loadPreview() async {
        previewState = .loading
        previewScene = makePreviewScene()

        do {
            let localURL = try await resolvedUSDZURL()
            configurePreviewScene(scene: previewScene, fileURL: localURL)
            previewState = .loaded
        } catch {
            previewState = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func addToRoom() async {
        guard !isAddingToRoom else {
            return
        }

        do {
            isAddingToRoom = true
            let localURL = try await resolvedUSDZURL()
            onAdd(localURL)
            dismiss()
        } catch {
            actionErrorMessage = error.localizedDescription
            isShowingActionError = true
        }

        isAddingToRoom = false
    }

    private func resolvedUSDZURL() async throws -> URL {
        guard let remoteURL = furniture.remoteUSDZURL else {
            throw FurnitureDetailError.invalidUSDZURL
        }

        return try await RemoteUSDZCache.shared.localFileURL(for: remoteURL)
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground).opacity(0.9))
        )
    }
}

private struct DetailFactRow: View {
    let label: String
    let value: String

    var body: some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct DetailBoolRow: View {
    let label: String
    let value: Bool

    var body: some View {
        DetailFactRow(label: label, value: value ? "Yes" : "No")
    }
}

private struct DetailTextBlock: View {
    let text: String

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

private struct DetailBulletList: View {
    let items: [String]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        Text(item)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct TagBubbleGrid: View {
    let tags: [String]

    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag.replacingOccurrences(of: "_", with: " "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )
            }
        }
    }
}

private func formattedInches(_ value: Double) -> String {
    "\(value.formatted(.number.precision(.fractionLength(0...1)))) in"
}

private func formattedMeters(_ value: Double) -> String {
    "\(value.formatted(.number.precision(.fractionLength(0...3)))) m"
}

private enum PreviewState {
    case loading
    case loaded
    case failed(String)
}

private enum FurnitureDetailError: LocalizedError {
    case invalidUSDZURL

    var errorDescription: String? {
        switch self {
        case .invalidUSDZURL:
            return "The furniture item is missing a valid USDZ URL."
        }
    }
}

private func makePreviewScene() -> SCNScene {
    let scene = SCNScene()
    scene.background.contents = UIColor.black

    let cameraNode = SCNNode()
    cameraNode.camera = SCNCamera()
    cameraNode.camera?.fieldOfView = 40
    cameraNode.position = SCNVector3(0, 0.6, 4.2)
    scene.rootNode.addChildNode(cameraNode)

    let ambientLight = SCNNode()
    ambientLight.light = SCNLight()
    ambientLight.light?.type = .ambient
    ambientLight.light?.intensity = 500
    scene.rootNode.addChildNode(ambientLight)

    let keyLight = SCNNode()
    keyLight.light = SCNLight()
    keyLight.light?.type = .omni
    keyLight.light?.intensity = 1200
    keyLight.position = SCNVector3(2.5, 4, 4)
    scene.rootNode.addChildNode(keyLight)

    let fillLight = SCNNode()
    fillLight.light = SCNLight()
    fillLight.light?.type = .omni
    fillLight.light?.intensity = 700
    fillLight.position = SCNVector3(-3, 2, -1)
    scene.rootNode.addChildNode(fillLight)

    return scene
}

private func configurePreviewScene(scene: SCNScene, fileURL: URL) {
    scene.rootNode.childNodes
        .filter { $0.camera == nil && $0.light == nil }
        .forEach { $0.removeFromParentNode() }

    guard let modelNode = loadPreviewNode(fileURL: fileURL) else {
        return
    }

    let spinNode = SCNNode()
    spinNode.addChildNode(modelNode)
    spinNode.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 18)))
    scene.rootNode.addChildNode(spinNode)
}

private func loadPreviewNode(fileURL: URL) -> SCNNode? {
    guard let scene = try? SCNScene(url: fileURL, options: nil),
          let node = importedContentNode(from: scene) else {
        return nil
    }

    return normalizedPreviewNode(from: node)
}

private func importedContentNode(from scene: SCNScene) -> SCNNode? {
    let containerNode = SCNNode()

    if scene.rootNode.geometry != nil {
        containerNode.addChildNode(scene.rootNode.flattenedClone())
    }

    for childNode in scene.rootNode.childNodes where containsRenderableContent(childNode) {
        containerNode.addChildNode(childNode.clone())
    }

    return containerNode.childNodes.isEmpty ? nil : containerNode
}

private func containsRenderableContent(_ node: SCNNode) -> Bool {
    if node.geometry != nil || node.morpher != nil || node.skinner != nil {
        return true
    }

    return node.childNodes.contains(where: containsRenderableContent)
}

private func normalizedPreviewNode(from node: SCNNode) -> SCNNode {
    let containerNode = SCNNode()
    let modelNode = node.clone()
    let (minimumBounds, maximumBounds) = node.boundingBox
    let centerX = (minimumBounds.x + maximumBounds.x) / 2
    let centerZ = (minimumBounds.z + maximumBounds.z) / 2
    let height = maximumBounds.y - minimumBounds.y
    let largestDimension = max(
        maximumBounds.x - minimumBounds.x,
        height,
        maximumBounds.z - minimumBounds.z
    )

    modelNode.position.x -= centerX
    modelNode.position.y -= minimumBounds.y
    modelNode.position.z -= centerZ

    if largestDimension > 0 {
        let targetDimension: Float = 1.8
        let scale = targetDimension / largestDimension
        modelNode.scale = SCNVector3(scale, scale, scale)
    }

    modelNode.eulerAngles.x += RemoteUSDZModelOrientation.previewAlignedCorrection.x
    modelNode.eulerAngles.y += RemoteUSDZModelOrientation.previewAlignedCorrection.y
    modelNode.eulerAngles.z += RemoteUSDZModelOrientation.previewAlignedCorrection.z

    containerNode.addChildNode(modelNode)
    containerNode.position.y = 0.2
    return containerNode
}
