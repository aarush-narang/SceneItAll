import SwiftUI
import SceneKit
import Combine

struct DesignSummary: Identifiable {
    let id: String
    let name: String
    let roomType: String
    let furnitureCount: Int
    let createdAt: Date
    let accentColor: Color
    let shell: SanitizedRoomPayload
}

struct RoomEditorSession: Identifiable {
    let id = UUID()
    let designID: String
    let scene: SCNScene
    let title: String
    let baseRoomData: Data
    let initialPlacedObjects: [PlacedFurnitureObject]
}

enum RoomImportMode {
    case barebones
    case stripFurniture
}

final class DesignsListViewModel: ObservableObject {
    @Published var designs: [DesignSummary] = []
    @Published var searchText = ""
    @Published var isLoadingDesigns = false
    @Published var isShowingNewDesignSheet = false
    @Published var isShowingScan = false
    @Published var isShowingImporter = false
    @Published var isShowingUnsupportedDeviceSheet = false
    @Published var isShowingStyleQuiz = false

    @Published var importMode: RoomImportMode = .barebones
    @Published var activeEditorSession: RoomEditorSession?
    @Published var importErrorMessage = ""
    @Published var isShowingImportError = false
    @Published var designsLoadErrorMessage = ""
    @Published var isShowingDesignsLoadError = false
    @Published var isLoadingDesignID: String?
    @Published var designOpenErrorMessage = ""
    @Published var isShowingDesignOpenError = false
    @Published var isSavingStylePreferences = false
    @Published var stylePreferencesErrorMessage = ""
    @Published var isShowingStylePreferencesError = false
    @Published var deleteDesignErrorMessage = ""
    @Published var isShowingDeleteDesignError = false

    private var hasLoadedDesigns = false

    var filteredDesigns: [DesignSummary] {
        if searchText.isEmpty { return designs }
        return designs.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var currentStyleQuizResult: StyleQuizResult {
        StyleQuizResult.fromUserDefaults()
    }

    @MainActor
    func loadDesignsIfNeeded() async {
        guard !hasLoadedDesigns else { return }
        await loadDesigns()
    }

    @MainActor
    func loadDesigns() async {
        isLoadingDesigns = true
        isShowingDesignsLoadError = false
        designsLoadErrorMessage = ""

        do {
            let remoteDesigns = try await FurnitureAPIClient.shared.listDesigns(userID: UserSession.shared.userID)
            designs = remoteDesigns.map(DesignSummary.init(remoteDesign:))
            hasLoadedDesigns = true
            isLoadingDesigns = false
        } catch {
            if error.isCancellationError {
                isLoadingDesigns = false
                return
            }

            designs = []
            isLoadingDesigns = false
            designsLoadErrorMessage = error.localizedDescription
            isShowingDesignsLoadError = true
        }
    }

    @MainActor
    func handleStyleQuizCompletion(_ result: StyleQuizResult) async {
        isSavingStylePreferences = true
        isShowingStylePreferencesError = false
        stylePreferencesErrorMessage = ""

        UserDefaults.standard.set(result.styleTags, forKey: "pref_styleTags")
        UserDefaults.standard.set(result.colorPalette, forKey: "pref_colorPalette")
        UserDefaults.standard.set(result.materialPreferences, forKey: "pref_materials")
        UserDefaults.standard.set(result.spatialDensity, forKey: "pref_density")
        UserDefaults.standard.set(result.philosophies, forKey: "pref_philosophies")

        let preferences = PreferenceProfileUpsert(
            styleTags: result.styleTags,
            colorPalette: result.colorPalette,
            materialPreferences: result.materialPreferences,
            spatialDensity: result.spatialDensity,
            philosophies: result.philosophies,
            hardRequirements: [:]
        )

        do {
            try await FurnitureAPIClient.shared.upsertPreferences(
                preferences,
                userID: UserSession.shared.userID
            )
            isSavingStylePreferences = false
            isShowingStyleQuiz = false
        } catch {
            isSavingStylePreferences = false
            stylePreferencesErrorMessage = error.localizedDescription
            isShowingStylePreferencesError = true
        }
    }

    @MainActor
    func deleteDesign(_ design: DesignSummary) async {
        isShowingDeleteDesignError = false
        deleteDesignErrorMessage = ""

        do {
            try await FurnitureAPIClient.shared.deleteDesign(id: design.id)
            designs.removeAll { $0.id == design.id }
        } catch {
            if error.isCancellationError {
                return
            }

            deleteDesignErrorMessage = error.localizedDescription
            isShowingDeleteDesignError = true
        }
    }

    @MainActor
    func handleImport(_ result: Result<[URL], Error>) async {
        do {
            guard let fileURL = try result.get().first else { return }
            let didAccess = fileURL.startAccessingSecurityScopedResource()
            defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: fileURL)
            let importedName = fileURL.deletingPathExtension().lastPathComponent
            let scene: SCNScene

            switch importMode {
            case .barebones:
                let importedObjects = try BarebonesRoomImportLoader.loadPlacedObjects(from: data)
                let createdDesign = try await FurnitureAPIClient.shared.createDesign(
                    name: importedName,
                    barebonesJSONData: data,
                    objects: importedObjects,
                    userID: UserSession.shared.userID
                )
                designs.insert(DesignSummary(remoteDesign: createdDesign), at: 0)
                hasLoadedDesigns = true

                scene = try BarebonesRoomImportLoader.loadScene(from: data)
                activeEditorSession = RoomEditorSession(
                    designID: createdDesign.id,
                    scene: scene,
                    title: importedName,
                    baseRoomData: data,
                    initialPlacedObjects: importedObjects
                )
            case .stripFurniture: // This will never happen since we removed the third option in the list when + button is clicked
                let strippedData = try BarebonesRoomJSONSanitizer.stripToEssentialSurfaces(from: data)
                scene = try BarebonesRoomImportLoader.loadScene(from: strippedData)
                activeEditorSession = RoomEditorSession(
                    designID: UUID().uuidString,
                    scene: scene,
                    title: importedName,
                    baseRoomData: strippedData,
                    initialPlacedObjects: []
                )
            }
        } catch {
            importErrorMessage = error.localizedDescription
            isShowingImportError = true
        }
    }

    @MainActor
    func openDesignForEditing(_ design: DesignSummary) async {
        guard isLoadingDesignID == nil else { return }
        isLoadingDesignID = design.id
        isShowingDesignOpenError = false
        designOpenErrorMessage = ""

        defer { isLoadingDesignID = nil }

        do {
            let fetchedObjects = try await FurnitureAPIClient.shared.fetchDesignObjects(designID: design.id)
            let roomPayload = design.shell.replacingObjects(with: fetchedObjects)
            let roomData = try RoomJSONSanitizer.sanitizedJSONData(from: roomPayload)
            let scene = try BarebonesRoomImportLoader.loadScene(from: roomData)
            activeEditorSession = RoomEditorSession(
                designID: design.id,
                scene: scene,
                title: design.name,
                baseRoomData: roomData,
                initialPlacedObjects: fetchedObjects
            )
        } catch {
            designOpenErrorMessage = error.localizedDescription
            isShowingDesignOpenError = true
        }
    }
}

private extension DesignSummary {
    init(remoteDesign: RemoteDesign) {
        id = remoteDesign.id
        name = remoteDesign.name
        roomType = remoteDesign.shell.room.type ?? "room"
        furnitureCount = remoteDesign.objects.count
        createdAt = remoteDesign.createdAt
        accentColor = Self.accentColor(for: remoteDesign)
        shell = remoteDesign.shell
    }

    static func accentColor(for remoteDesign: RemoteDesign) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .pink, .teal, .indigo]
        let index = abs(remoteDesign.id.hashValue) % colors.count
        return colors[index]
    }
}

private extension Error {
    var isCancellationError: Bool {
        if self is CancellationError {
            return true
        }

        if let urlError = self as? URLError, urlError.code == .cancelled {
            return true
        }

        if let clientError = self as? FurnitureAPIClientError,
           case let FurnitureAPIClientError.transportError(_, underlying) = clientError,
           underlying.code == .cancelled {
            return true
        }

        return false
    }
}
