//
//  Consts.swift
//  RoomPlanExampleApp
//
//  Created by Kelvin Jou on 4/24/26.
//  Copyright © 2026 Apple. All rights reserved.
//

import Foundation

let furnitureAssets: [String: String] = [ // key: name, value: usdz file path
    "bedframe": "bedframe",
    "table": "table",
    "bookshelf": "bookshelf",
]

struct Furniture: Codable, Identifiable {
    let id: String
    let name: String
    let familyKey: String
    let source: Source
    let taxonomyIkea: TaxonomyIkea
    let taxonomyInferred: TaxonomyInferred
    let price: Price
    let rating: Rating
    let dimensionsIkea: DimensionsIkea
    let dimensionsBbox: DimensionsBbox
    let attributes: Attributes
    let designSummary: String
    let description: String
    let embeddingText: String
    let files: Files

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
        case familyKey = "family_key"
        case source
        case taxonomyIkea = "taxonomy_ikea"
        case taxonomyInferred = "taxonomy_inferred"
        case price
        case rating
        case dimensionsIkea = "dimensions_ikea"
        case dimensionsBbox = "dimensions_bbox"
        case attributes
        case designSummary = "design_summary"
        case description
        case embeddingText = "embedding_text"
        case files
    }
}

struct Source: Codable {
    let name: String
    let url: String
}

struct TaxonomyIkea: Codable {
    let categoryLeaf: String
    let categoryPath: [String]
    let segment: String
    let topDepartment: String
    let material: String
    let color: String

    enum CodingKeys: String, CodingKey {
        case categoryLeaf = "category_leaf"
        case categoryPath = "category_path"
        case segment
        case topDepartment = "top_department"
        case material
        case color
    }
}

struct TaxonomyInferred: Codable {
    let category: String
    let subcategory: String
}

struct Price: Codable {
    let value: Double
    let currency: String
}

struct Rating: Codable {
    let value: Double
    let count: Int
}

struct DimensionsIkea: Codable {
    let widthIn: Double
    let depthIn: Double
    let heightIn: Double

    enum CodingKeys: String, CodingKey {
        case widthIn = "width_in"
        case depthIn = "depth_in"
        case heightIn = "height_in"
    }
}

struct DimensionsBbox: Codable {
    let widthM: Double
    let heightM: Double
    let depthM: Double

    enum CodingKeys: String, CodingKey {
        case widthM = "width_m"
        case heightM = "height_m"
        case depthM = "depth_m"
    }
}

struct Attributes: Codable {
    let styleTags: [String]
    let designLineage: String
    let materialPrimary: String
    let textureAndFinish: String
    let colorPrimary: String
    let era: String
    let formality: String
    let ambientMood: [String]
    let visualWeight: String
    let scale: String
    let roomRole: String
    let suitableRooms: [String]
    let placementHints: [String]
    let pairsWellWith: [String]
    let useScenarios: [String]
    let spaceRequirements: String
    let hasArms: Bool
    let hasLegs: Bool
    let stackable: Bool

    enum CodingKeys: String, CodingKey {
        case styleTags = "style_tags"
        case designLineage = "design_lineage"
        case materialPrimary = "material_primary"
        case textureAndFinish = "texture_and_finish"
        case colorPrimary = "color_primary"
        case era
        case formality
        case ambientMood = "ambient_mood"
        case visualWeight = "visual_weight"
        case scale
        case roomRole = "room_role"
        case suitableRooms = "suitable_rooms"
        case placementHints = "placement_hints"
        case pairsWellWith = "pairs_well_with"
        case useScenarios = "use_scenarios"
        case spaceRequirements = "space_requirements"
        case hasArms = "has_arms"
        case hasLegs = "has_legs"
        case stackable
    }
}

struct Files: Codable {
    let usdzURL: String
    let thumbURLs: [String]

    enum CodingKeys: String, CodingKey {
        case usdzURL = "usdz_url"
        case thumbURLs = "thumb_urls"
    }
}
extension Furniture {
    var savedSnapshot: SavedFurnitureSnapshot {
        SavedFurnitureSnapshot(
            id: id,
            name: name,
            familyKey: familyKey,
            dimensionsBbox: dimensionsBbox,
            files: SavedFurnitureFiles(usdzURL: files.usdzURL)
        )
    }

    init(savedSnapshot: SavedFurnitureSnapshot) {
        self.init(
            id: savedSnapshot.id,
            name: savedSnapshot.name,
            familyKey: savedSnapshot.familyKey,
            source: Source(name: "saved_snapshot", url: ""),
            taxonomyIkea: TaxonomyIkea(
                categoryLeaf: "",
                categoryPath: [],
                segment: "",
                topDepartment: "",
                material: "",
                color: ""
            ),
            taxonomyInferred: TaxonomyInferred(category: "", subcategory: ""),
            price: Price(value: 0, currency: "USD"),
            rating: Rating(value: 0, count: 0),
            dimensionsIkea: DimensionsIkea(widthIn: 0, depthIn: 0, heightIn: 0),
            dimensionsBbox: savedSnapshot.dimensionsBbox,
            attributes: Attributes(
                styleTags: [],
                designLineage: "",
                materialPrimary: "",
                textureAndFinish: "",
                colorPrimary: "",
                era: "",
                formality: "",
                ambientMood: [],
                visualWeight: "",
                scale: "",
                roomRole: "",
                suitableRooms: [],
                placementHints: [],
                pairsWellWith: [],
                useScenarios: [],
                spaceRequirements: "",
                hasArms: false,
                hasLegs: false,
                stackable: false
            ),
            designSummary: "",
            description: "",
            embeddingText: "",
            files: Files(usdzURL: savedSnapshot.files.usdzURL, thumbURLs: [])
        )
    }

    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = price.currency
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: price.value)) ?? "\(price.currency) \(price.value)"
    }

    var remoteUSDZURL: URL? {
        URL(string: files.usdzURL)
    }
}

enum FurnitureCatalogLoader {
    static func loadFromBackendSample() throws -> [Furniture] {
        let decoder = JSONDecoder()
        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: "fromBackend", withExtension: "json"),
            Bundle.main.url(forResource: "fromBackend", withExtension: "json", subdirectory: "JSON_testfiles")
        ]

        guard let url = candidateURLs.compactMap({ $0 }).first else {
            throw FurnitureCatalogLoaderError.sampleFileMissing
        }

        let data = try Data(contentsOf: url)
        return [try decoder.decode(Furniture.self, from: data)]
    }
}

enum FurnitureCatalogLoaderError: LocalizedError {
    case sampleFileMissing

    var errorDescription: String? {
        switch self {
        case .sampleFileMissing:
            return "The bundled sample file fromBackend.json could not be found."
        }
    }
}

actor RemoteUSDZCache {
    static let shared = RemoteUSDZCache()

    private let fileManager = FileManager.default

    func localFileURL(for remoteURL: URL) async throws -> URL {
        let cachedFileURL = cacheFileURL(for: remoteURL)

        if fileManager.fileExists(atPath: cachedFileURL.path()) {
            return cachedFileURL
        }

        let (temporaryURL, _) = try await URLSession.shared.download(from: remoteURL)
        try createCacheDirectoryIfNeeded()

        if fileManager.fileExists(atPath: cachedFileURL.path()) {
            try? fileManager.removeItem(at: cachedFileURL)
        }

        try fileManager.moveItem(at: temporaryURL, to: cachedFileURL)
        return cachedFileURL
    }

    private func createCacheDirectoryIfNeeded() throws {
        try fileManager.createDirectory(
            at: cacheDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func cacheFileURL(for remoteURL: URL) -> URL {
        let fileName = remoteURL.lastPathComponent.isEmpty ? UUID().uuidString : remoteURL.lastPathComponent
        return cacheDirectoryURL.appending(path: fileName)
    }

    private var cacheDirectoryURL: URL {
        fileManager.temporaryDirectory.appending(path: "RemoteUSDZCache", directoryHint: .isDirectory)
    }
}
