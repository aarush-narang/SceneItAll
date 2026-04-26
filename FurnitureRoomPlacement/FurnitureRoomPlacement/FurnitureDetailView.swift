import SwiftUI
import SceneKit

// MARK: - Furniture Catalog List

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
                    on: scene, fileURL: localUSDZURL, overlayIdentifier: objectID
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
        if let index = furnitureItems.firstIndex(where: { $0.id == furniture.id }) {
            var updated = furnitureItems
            updated[index] = furniture
            return updated
        }
        return furnitureItems + [furniture]
    }
}

// MARK: - Furniture Detail View

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
                heroSection
                addButton

                if hasDetailedMetadata {
                    detailedSections
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .task(id: furniture.id) { await loadPreview() }
        .alert("Unable to Load Furniture", isPresented: $isShowingActionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(actionErrorMessage)
        }
    }

    // MARK: - 3D Preview

    private var previewSection: some View {
        SceneView(
            scene: previewScene,
            pointOfView: nil,
            options: [.autoenablesDefaultLighting]
        )
        .frame(height: 220)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                .foregroundStyle(.white)
            case .loaded:
                EmptyView()
            }
        }
        .overlay(alignment: .bottom) {
            Text("3D USDZ Preview")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(.bottom, 12)
        }
    }

    // MARK: - Hero Info

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(furniture.name)
                .font(.system(size: 24, weight: .bold))

            Text("\(furniture.formattedPrice) \u{00B7} \(furniture.attributes.materialPrimary)")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            if furniture.rating.value > 0 {
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { index in
                        Image(systemName: index < Int(furniture.rating.value) ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundStyle(index < Int(furniture.rating.value) ? Color(red: 1, green: 0.72, blue: 0) : .gray.opacity(0.3))
                    }
                    Text(furniture.rating.value.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }

            if !furniture.designSummary.isEmpty {
                Text(furniture.designSummary)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            if !furniture.attributes.styleTags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(furniture.attributes.styleTags, id: \.self) { tag in
                        Text(tag.replacingOccurrences(of: "_", with: " "))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            Task { await addToRoom() }
        } label: {
            Group {
                if isAddingToRoom {
                    ProgressView().tint(.white)
                } else {
                    Text("Add To Room")
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(isAddingToRoom || furniture.remoteUSDZURL == nil)
    }

    // MARK: - Detailed Metadata Sections

    private var hasDetailedMetadata: Bool {
        !furniture.description.isEmpty || furniture.price.value > 0
    }

    private var detailedSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !furniture.description.isEmpty {
                DetailSection("Overview") {
                    Text(furniture.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            DetailSection("Pricing & Rating") {
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

            DetailSection("Materials & Styling") {
                DetailFactRow(label: "Primary Material", value: furniture.attributes.materialPrimary)
                DetailFactRow(label: "Texture / Finish", value: furniture.attributes.textureAndFinish)
                DetailFactRow(label: "Primary Color", value: furniture.attributes.colorPrimary)
                DetailFactRow(label: "Formality", value: furniture.attributes.formality)
                DetailFactRow(label: "Visual Weight", value: furniture.attributes.visualWeight)
            }

            if !furniture.attributes.placementHints.isEmpty {
                DetailSection("Placement Hints") {
                    ForEach(furniture.attributes.placementHints, id: \.self) { hint in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\u{2022}")
                            Text(hint).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !furniture.attributes.pairsWellWith.isEmpty {
                DetailSection("Pairs Well With") {
                    ForEach(furniture.attributes.pairsWellWith, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\u{2022}")
                            Text(item).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

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
        guard !isAddingToRoom else { return }
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

// MARK: - Detail Sub-components

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
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
        "The furniture item is missing a valid USDZ URL."
    }
}

// MARK: - Preview Scene Helpers

private func makePreviewScene() -> SCNScene {
    let scene = SCNScene()
    scene.background.contents = UIColor.black

    let camera = SCNNode()
    camera.camera = SCNCamera()
    camera.camera?.fieldOfView = 40
    camera.position = SCNVector3(0, 0.6, 4.2)
    scene.rootNode.addChildNode(camera)

    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.intensity = 500
    scene.rootNode.addChildNode(ambient)

    let key = SCNNode()
    key.light = SCNLight()
    key.light?.type = .omni
    key.light?.intensity = 1200
    key.position = SCNVector3(2.5, 4, 4)
    scene.rootNode.addChildNode(key)

    let fill = SCNNode()
    fill.light = SCNLight()
    fill.light?.type = .omni
    fill.light?.intensity = 700
    fill.position = SCNVector3(-3, 2, -1)
    scene.rootNode.addChildNode(fill)

    return scene
}

private func configurePreviewScene(scene: SCNScene, fileURL: URL) {
    scene.rootNode.childNodes
        .filter { $0.camera == nil && $0.light == nil }
        .forEach { $0.removeFromParentNode() }

    guard let modelNode = loadPreviewNode(fileURL: fileURL) else { return }
    let spinNode = SCNNode()
    spinNode.addChildNode(modelNode)
    spinNode.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 18)))
    scene.rootNode.addChildNode(spinNode)
}

private func loadPreviewNode(fileURL: URL) -> SCNNode? {
    guard let scene = try? SCNScene(url: fileURL, options: nil),
          let node = importedContentNode(from: scene) else { return nil }
    return normalizedPreviewNode(from: node)
}

private func importedContentNode(from scene: SCNScene) -> SCNNode? {
    let container = SCNNode()
    if scene.rootNode.geometry != nil {
        container.addChildNode(scene.rootNode.flattenedClone())
    }
    for child in scene.rootNode.childNodes where containsRenderable(child) {
        container.addChildNode(child.clone())
    }
    return container.childNodes.isEmpty ? nil : container
}

private func containsRenderable(_ node: SCNNode) -> Bool {
    if node.geometry != nil || node.morpher != nil || node.skinner != nil { return true }
    return node.childNodes.contains(where: containsRenderable)
}

private func normalizedPreviewNode(from node: SCNNode) -> SCNNode {
    let container = SCNNode()
    let model = node.clone()
    let (minBounds, maxBounds) = node.boundingBox
    let cx = (minBounds.x + maxBounds.x) / 2
    let cz = (minBounds.z + maxBounds.z) / 2
    let largest = max(maxBounds.x - minBounds.x, maxBounds.y - minBounds.y, maxBounds.z - minBounds.z)

    model.position.x -= cx
    model.position.y -= minBounds.y
    model.position.z -= cz

    if largest > 0 {
        let scale = Float(1.8) / largest
        model.scale = SCNVector3(scale, scale, scale)
    }

    model.eulerAngles.x += RemoteUSDZModelOrientation.previewAlignedCorrection.x
    model.eulerAngles.y += RemoteUSDZModelOrientation.previewAlignedCorrection.y
    model.eulerAngles.z += RemoteUSDZModelOrientation.previewAlignedCorrection.z

    container.addChildNode(model)
    container.position.y = 0.2
    return container
}
