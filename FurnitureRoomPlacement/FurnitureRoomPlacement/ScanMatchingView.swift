import SwiftUI
import SceneKit
import RoomPlan
import Combine

struct ScanMatchingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ScanMatchingViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if let session = viewModel.editorSession {
                    RoomEditorView(
                        scene: session.scene,
                        title: session.title,
                        baseRoomData: session.baseRoomData,
                        initialPlacedObjects: session.initialPlacedObjects,
                        designID: session.designID
                    )
                } else {
                    matchingProgressView
                }
            }
            .alert("Matching Failed", isPresented: $viewModel.isShowingError) {
                Button("Dismiss", role: .cancel) { dismiss() }
            } message: {
                Text(viewModel.errorMessage)
            }
        }
        .interactiveDismissDisabled(viewModel.editorSession == nil)
        .task {
            await viewModel.run()
        }
    }

    private var matchingProgressView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)

            Text(viewModel.statusMessage)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(viewModel.detailMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

@MainActor
final class ScanMatchingViewModel: ObservableObject {
    @Published var statusMessage = "Uploading scan…"
    @Published var detailMessage = "Sending room data to the matcher"
    @Published var isShowingError = false
    @Published var errorMessage = ""
    @Published var editorSession: RoomEditorSession?

    private let uploadClient: ScanUploadClient = {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "FurnitureAPIBaseURL") as? String,
           let url = URL(string: configured) {
            return ScanUploadClient(baseURL: url)
        }
        return ScanUploadClient(baseURL: URL(string: "http://127.0.0.1:8000")!)
    }()

    func run() async {
        guard let room = ScanResultHolder.shared.room else {
            errorMessage = "No scan data available."
            isShowingError = true
            return
        }
        let frames = ScanResultHolder.shared.frames

        do {
            statusMessage = "Uploading scan…"
            detailMessage = "Sending room data to the matcher"
            let matchedScene = try await uploadClient.upload(room: room, frames: frames)

            statusMessage = "Building room…"
            detailMessage = "Downloading furniture models"
            let session = try await buildEditorSession(room: room, matchedScene: matchedScene)

            editorSession = session
            ScanResultHolder.shared.clear()
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }

    private func buildEditorSession(
        room: CapturedRoom,
        matchedScene: MatchedScene
    ) async throws -> RoomEditorSession {
        let roomScene = BarebonesRoomSceneBuilder.scene(for: room)
        let roomData = try encodeBarebonesRoomData(for: room)
        var placedObjects: [PlacedFurnitureObject] = []
        let dateString = ISO8601DateFormatter().string(from: Date())

        for obj in matchedScene.objects {
            let placement = FurniturePlacement(
                position: obj.transform.position,
                eulerAngles: obj.transform.rotationEuler,
                scale: obj.transform.scale
            )

            if obj.isMatched,
               let productId = obj.matchedProductId,
               let productName = obj.matchedProductName,
               let usdzURLString = obj.matchedUSDZURL {

                let snapshot = SavedFurnitureSnapshot(
                    id: productId,
                    name: productName,
                    familyKey: obj.refinedCategory,
                    dimensionsBbox: DimensionsBbox(
                        widthM: Double(obj.originalBBox.dimensions[safe: 0] ?? 0.5),
                        heightM: Double(obj.originalBBox.dimensions[safe: 1] ?? 0.5),
                        depthM: Double(obj.originalBBox.dimensions[safe: 2] ?? 0.5)
                    ),
                    files: SavedFurnitureFiles(usdzURL: usdzURLString)
                )
                let furniture = Furniture(savedSnapshot: snapshot)

                let placed = PlacedFurnitureObject(
                    id: obj.detectedId,
                    furniture: furniture,
                    placement: placement,
                    addedAt: dateString,
                    placedBy: "agent",
                    rationale: "Matched from LiDAR scan"
                )
                placedObjects.append(placed)

                if let remoteURL = URL(string: usdzURLString) {
                    do {
                        let localURL = try await RemoteUSDZCache.shared.localFileURL(for: remoteURL)
                        let overlayID = placed.id
                        BarebonesRoomSceneBuilder.overlayExternalUSDZ(
                            on: roomScene,
                            fileURL: localURL,
                            overlayIdentifier: overlayID
                        )
                        applyPlacement(placement, toNodeNamed: BarebonesRoomSceneBuilder.overlayNodeName(for: overlayID), in: roomScene)
                    } catch {
                        addWhiteBox(for: obj, to: roomScene)
                    }
                } else {
                    addWhiteBox(for: obj, to: roomScene)
                }
            } else {
                addWhiteBox(for: obj, to: roomScene)
            }
        }

        statusMessage = "Saving design…"
        detailMessage = "Creating your new design"

        let designName = "Scan \(DateFormatter.shortDateFormatter.string(from: Date()))"
        let createdDesign = try await FurnitureAPIClient.shared.createDesign(
            name: designName,
            barebonesJSONData: roomData,
            objects: placedObjects,
            userID: UserSession.shared.userID
        )

        return RoomEditorSession(
            designID: createdDesign.id,
            scene: roomScene,
            title: designName,
            baseRoomData: roomData,
            initialPlacedObjects: placedObjects
        )
    }

    private func encodeBarebonesRoomData(for room: CapturedRoom) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if #available(iOS 17.0, *) {
            let barebones = BarebonesCapturedRoom(
                identifier: room.identifier,
                story: room.story,
                version: room.version,
                walls: room.walls,
                doors: room.doors,
                windows: room.windows,
                openings: room.openings,
                floors: room.floors,
                sections: room.sections
            )
            return try encoder.encode(barebones)
        } else {
            let legacy = LegacyBarebonesCapturedRoom(
                identifier: room.identifier,
                walls: room.walls,
                doors: room.doors,
                windows: room.windows,
                openings: room.openings
            )
            return try encoder.encode(legacy)
        }
    }

    private func applyPlacement(_ placement: FurniturePlacement, toNodeNamed name: String, in scene: SCNScene) {
        guard let node = scene.rootNode.childNode(withName: name, recursively: true) else { return }
        if placement.position.count >= 3 {
            node.position = SCNVector3(placement.position[0], placement.position[1], placement.position[2])
        }
        if placement.eulerAngles.count >= 3 {
            node.eulerAngles = SCNVector3(placement.eulerAngles[0], placement.eulerAngles[1], placement.eulerAngles[2])
        }
        if placement.scale.count >= 3 {
            node.scale = SCNVector3(placement.scale[0], placement.scale[1], placement.scale[2])
        }
    }

    private func addWhiteBox(for obj: MatchedObject, to scene: SCNScene) {
        let dims = obj.originalBBox.dimensions
        let w = CGFloat(dims[safe: 0] ?? 0.5)
        let h = CGFloat(dims[safe: 1] ?? 0.5)
        let d = CGFloat(dims[safe: 2] ?? 0.5)

        let box = SCNBox(width: w, height: h, length: d, chamferRadius: 0)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white.withAlphaComponent(0.3)
        material.fillMode = .lines
        box.materials = [material]

        let boxNode = SCNNode(geometry: box)
        boxNode.name = "whitebox-\(obj.detectedId)"

        let pos = obj.transform.position
        if pos.count >= 3 {
            boxNode.position = SCNVector3(pos[0], pos[1], pos[2])
        }
        let rot = obj.transform.rotationEuler
        if rot.count >= 3 {
            boxNode.eulerAngles = SCNVector3(rot[0], rot[1], rot[2])
        }

        let textGeo = SCNText(string: obj.refinedCategory, extrusionDepth: 0.005)
        textGeo.font = UIFont.systemFont(ofSize: 0.06, weight: .medium)
        textGeo.firstMaterial?.diffuse.contents = UIColor.white
        let textNode = SCNNode(geometry: textGeo)
        let (textMin, textMax) = textNode.boundingBox
        let textWidth = textMax.x - textMin.x
        textNode.position = SCNVector3(-textWidth / 2, Float(h / 2) + 0.05, 0)
        textNode.constraints = [SCNBillboardConstraint()]
        boxNode.addChildNode(textNode)

        scene.rootNode.addChildNode(boxNode)
    }
}

private extension DateFormatter {
    static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
