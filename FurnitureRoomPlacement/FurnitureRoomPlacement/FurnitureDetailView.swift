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

    @State private var furnitureItems: [Furniture] = []
    @State private var selectedFurniture: Furniture?
    @State private var loadErrorMessage = ""
    @State private var isShowingLoadError = false

    var body: some View {
        List(furnitureItems, id: \.id) { furniture in
            Button {
                selectedFurniture = furniture
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(furniture.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(furniture.formattedPrice)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if furnitureItems.isEmpty {
                ContentUnavailableView(
                    "No Furniture",
                    systemImage: "shippingbox",
                    description: Text("The sample backend furniture file could not be loaded.")
                )
            }
        }
        .navigationTitle("Furniture Catalog")
        .task {
            await loadFurnitureIfNeeded()
        }
        .sheet(item: $selectedFurniture) { furniture in
            FurnitureDetailView(furniture: furniture) { localUSDZURL in
                let addSuccess = BarebonesRoomSceneBuilder.overlayExternalUSDZ(on: scene, fileURL: localUSDZURL)
                if addSuccess {
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

    @MainActor
    private func loadFurnitureIfNeeded() async {
        guard furnitureItems.isEmpty else {
            return
        }

        do {
            furnitureItems = try FurnitureCatalogLoader.loadFromBackendSample()
        } catch {
            loadErrorMessage = error.localizedDescription
            isShowingLoadError = true
        }
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

            Text(furniture.description)
                .font(.body)
                .foregroundStyle(.secondary)

            Label(furniture.formattedPrice, systemImage: "dollarsign.circle")
                .foregroundStyle(.secondary)

            Label("Material: \(furniture.attributes.materialPrimary)", systemImage: "square.stack.3d.down.right")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Style Tags")
                    .font(.headline)

                TagBubbleGrid(tags: furniture.attributes.styleTags)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func loadPreview() async {
        previewState = .loading
        previewScene = makePreviewScene()

        do {
            guard let remoteURL = furniture.remoteUSDZURL else {
                throw FurnitureDetailError.invalidUSDZURL
            }

            let localURL = try await RemoteUSDZCache.shared.localFileURL(for: remoteURL)
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
            guard let remoteURL = furniture.remoteUSDZURL else {
                throw FurnitureDetailError.invalidUSDZURL
            }

            isAddingToRoom = true
            let localURL = try await RemoteUSDZCache.shared.localFileURL(for: remoteURL)
            onAdd(localURL)
            dismiss()
        } catch {
            actionErrorMessage = error.localizedDescription
            isShowingActionError = true
        }

        isAddingToRoom = false
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

    containerNode.addChildNode(modelNode)
    containerNode.position.y = 0.2
    return containerNode
}
