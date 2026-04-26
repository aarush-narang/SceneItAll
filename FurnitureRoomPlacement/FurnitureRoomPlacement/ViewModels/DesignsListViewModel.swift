import SwiftUI
import SceneKit
import Combine

struct DesignSummary: Identifiable {
    let id: String
    let name: String
    let roomType: String
    let furnitureCount: Int
    let updatedAt: Date
    let accentColor: Color

    static let samples: [DesignSummary] = [
        .init(id: "1", name: "Living Room", roomType: "living", furnitureCount: 6, updatedAt: .now.addingTimeInterval(-3600), accentColor: .blue),
        .init(id: "2", name: "Master Bedroom", roomType: "bedroom", furnitureCount: 4, updatedAt: .now.addingTimeInterval(-86400), accentColor: .purple),
        .init(id: "3", name: "Home Office", roomType: "office", furnitureCount: 3, updatedAt: .now.addingTimeInterval(-172800), accentColor: .green),
        .init(id: "4", name: "Guest Room", roomType: "bedroom", furnitureCount: 2, updatedAt: .now.addingTimeInterval(-604800), accentColor: .orange),
    ]
}

enum RoomImportMode {
    case barebones
    case stripFurniture
}

final class DesignsListViewModel: ObservableObject {
    @Published var designs: [DesignSummary] = DesignSummary.samples
    @Published var searchText = ""
    @Published var isShowingNewDesignSheet = false
    @Published var isShowingScan = false
    @Published var isShowingImporter = false
    @Published var isShowingUnsupportedDeviceSheet = false
    @Published var isShowingStyleQuiz = false

    @Published var importMode: RoomImportMode = .barebones
    @Published var importedScene: SCNScene?
    @Published var importedRoomData = Data()
    @Published var importedPlacedObjects: [PlacedFurnitureObject] = []
    @Published var importedFileName = ""
    @Published var importErrorMessage = ""
    @Published var isShowingImportError = false

    var filteredDesigns: [DesignSummary] {
        if searchText.isEmpty { return designs }
        return designs.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    @MainActor
    func handleImport(_ result: Result<[URL], Error>) async {
        do {
            guard let fileURL = try result.get().first else { return }
            let didAccess = fileURL.startAccessingSecurityScopedResource()
            defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: fileURL)
            let scene: SCNScene

            switch importMode {
            case .barebones:
                let fetchedObjects = try await FurnitureAPIClient.shared.fetchDesignObjects()
                let fetchedObjectsData = try JSONEncoder().encode(fetchedObjects)
                let mergedRoom = try BarebonesRoomJSONSanitizer.roomData(
                    byMergingObjectsFromDesignObjectsData: fetchedObjectsData,
                    intoRoomData: data
                )
                scene = try BarebonesRoomImportLoader.loadScene(from: mergedRoom.roomData)
                importedRoomData = mergedRoom.roomData
                importedPlacedObjects = mergedRoom.objects
            case .stripFurniture:
                let strippedData = try BarebonesRoomJSONSanitizer.stripToEssentialSurfaces(from: data)
                scene = try BarebonesRoomImportLoader.loadScene(from: strippedData)
                importedRoomData = strippedData
                importedPlacedObjects = []
            }

            importedFileName = fileURL.deletingPathExtension().lastPathComponent
            importedScene = scene
        } catch {
            importErrorMessage = error.localizedDescription
            isShowingImportError = true
        }
    }
}
