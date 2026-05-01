//
//  Consts.swift
//  RoomPlanExampleApp
//
//  Created by Kelvin Jou on 4/24/26.
//  Copyright © 2026 Apple. All rights reserved.
//

import Foundation

let baseURL = "https://2eb4-47-146-74-95.ngrok-free.app"

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
        case id
        case legacyID = "_id"
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

    init(
        id: String,
        name: String,
        familyKey: String,
        source: Source,
        taxonomyIkea: TaxonomyIkea,
        taxonomyInferred: TaxonomyInferred,
        price: Price,
        rating: Rating,
        dimensionsIkea: DimensionsIkea,
        dimensionsBbox: DimensionsBbox,
        attributes: Attributes,
        designSummary: String,
        description: String,
        embeddingText: String,
        files: Files
    ) {
        self.id = id
        self.name = name
        self.familyKey = familyKey
        self.source = source
        self.taxonomyIkea = taxonomyIkea
        self.taxonomyInferred = taxonomyInferred
        self.price = price
        self.rating = rating
        self.dimensionsIkea = dimensionsIkea
        self.dimensionsBbox = dimensionsBbox
        self.attributes = attributes
        self.designSummary = designSummary
        self.description = description
        self.embeddingText = embeddingText
        self.files = files
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let id = try container.decodeIfPresent(String.self, forKey: .id) {
            self.id = id
        } else {
            self.id = try container.decodeIfPresent(String.self, forKey: .legacyID) ?? UUID().uuidString
        }

        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Furniture"
        familyKey = try container.decodeIfPresent(String.self, forKey: .familyKey) ?? name
        source = try container.decodeIfPresent(Source.self, forKey: .source) ?? .empty
        taxonomyIkea = try container.decodeIfPresent(TaxonomyIkea.self, forKey: .taxonomyIkea) ?? .empty
        taxonomyInferred = try container.decodeIfPresent(TaxonomyInferred.self, forKey: .taxonomyInferred) ?? .empty
        price = try container.decodeIfPresent(Price.self, forKey: .price) ?? .empty
        rating = try container.decodeIfPresent(Rating.self, forKey: .rating) ?? .empty
        dimensionsIkea = try container.decodeIfPresent(DimensionsIkea.self, forKey: .dimensionsIkea) ?? .empty
        dimensionsBbox = try container.decodeIfPresent(DimensionsBbox.self, forKey: .dimensionsBbox) ?? .empty
        attributes = try container.decodeIfPresent(Attributes.self, forKey: .attributes) ?? .empty
        designSummary = try container.decodeIfPresent(String.self, forKey: .designSummary) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        embeddingText = try container.decodeIfPresent(String.self, forKey: .embeddingText) ?? ""
        files = try container.decodeIfPresent(Files.self, forKey: .files) ?? .empty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(familyKey, forKey: .familyKey)
        try container.encode(source, forKey: .source)
        try container.encode(taxonomyIkea, forKey: .taxonomyIkea)
        try container.encode(taxonomyInferred, forKey: .taxonomyInferred)
        try container.encode(price, forKey: .price)
        try container.encode(rating, forKey: .rating)
        try container.encode(dimensionsIkea, forKey: .dimensionsIkea)
        try container.encode(dimensionsBbox, forKey: .dimensionsBbox)
        try container.encode(attributes, forKey: .attributes)
        try container.encode(designSummary, forKey: .designSummary)
        try container.encode(description, forKey: .description)
        try container.encode(embeddingText, forKey: .embeddingText)
        try container.encode(files, forKey: .files)
    }
}

struct Source: Codable {
    let name: String
    let url: String

    init(name: String, url: String) {
        self.name = name
        self.url = url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
    }

    static let empty = Source(name: "", url: "")

    private enum CodingKeys: String, CodingKey {
        case name
        case url
    }
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

    init(
        categoryLeaf: String,
        categoryPath: [String],
        segment: String,
        topDepartment: String,
        material: String,
        color: String
    ) {
        self.categoryLeaf = categoryLeaf
        self.categoryPath = categoryPath
        self.segment = segment
        self.topDepartment = topDepartment
        self.material = material
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categoryLeaf = try container.decodeIfPresent(String.self, forKey: .categoryLeaf) ?? ""
        categoryPath = try container.decodeIfPresent([String].self, forKey: .categoryPath) ?? []
        segment = try container.decodeIfPresent(String.self, forKey: .segment) ?? ""
        topDepartment = try container.decodeIfPresent(String.self, forKey: .topDepartment) ?? ""
        material = try container.decodeIfPresent(String.self, forKey: .material) ?? ""
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? ""
    }

    static let empty = TaxonomyIkea(
        categoryLeaf: "",
        categoryPath: [],
        segment: "",
        topDepartment: "",
        material: "",
        color: ""
    )
}

struct TaxonomyInferred: Codable {
    let category: String
    let subcategory: String

    init(category: String, subcategory: String) {
        self.category = category
        self.subcategory = subcategory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        subcategory = try container.decodeIfPresent(String.self, forKey: .subcategory) ?? ""
    }

    static let empty = TaxonomyInferred(category: "", subcategory: "")

    private enum CodingKeys: String, CodingKey {
        case category
        case subcategory
    }
}

struct Price: Codable {
    let value: Double
    let currency: String

    init(value: Double, currency: String) {
        self.value = value
        self.currency = currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decodeIfPresent(Double.self, forKey: .value) ?? 0
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
    }

    static let empty = Price(value: 0, currency: "USD")

    private enum CodingKeys: String, CodingKey {
        case value
        case currency
    }
}

struct Rating: Codable {
    let value: Double
    let count: Int

    init(value: Double, count: Int) {
        self.value = value
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decodeIfPresent(Double.self, forKey: .value) ?? 0
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
    }

    static let empty = Rating(value: 0, count: 0)

    private enum CodingKeys: String, CodingKey {
        case value
        case count
    }
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

    init(widthIn: Double, depthIn: Double, heightIn: Double) {
        self.widthIn = widthIn
        self.depthIn = depthIn
        self.heightIn = heightIn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        widthIn = try container.decodeIfPresent(Double.self, forKey: .widthIn) ?? 0
        depthIn = try container.decodeIfPresent(Double.self, forKey: .depthIn) ?? 0
        heightIn = try container.decodeIfPresent(Double.self, forKey: .heightIn) ?? 0
    }

    static let empty = DimensionsIkea(widthIn: 0, depthIn: 0, heightIn: 0)
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

    init(widthM: Double, heightM: Double, depthM: Double) {
        self.widthM = widthM
        self.heightM = heightM
        self.depthM = depthM
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        widthM = try container.decodeIfPresent(Double.self, forKey: .widthM) ?? 0
        heightM = try container.decodeIfPresent(Double.self, forKey: .heightM) ?? 0
        depthM = try container.decodeIfPresent(Double.self, forKey: .depthM) ?? 0
    }

    static let empty = DimensionsBbox(widthM: 0, heightM: 0, depthM: 0)
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

    init(
        styleTags: [String],
        designLineage: String,
        materialPrimary: String,
        textureAndFinish: String,
        colorPrimary: String,
        era: String,
        formality: String,
        ambientMood: [String],
        visualWeight: String,
        scale: String,
        roomRole: String,
        suitableRooms: [String],
        placementHints: [String],
        pairsWellWith: [String],
        useScenarios: [String],
        spaceRequirements: String,
        hasArms: Bool,
        hasLegs: Bool,
        stackable: Bool
    ) {
        self.styleTags = styleTags
        self.designLineage = designLineage
        self.materialPrimary = materialPrimary
        self.textureAndFinish = textureAndFinish
        self.colorPrimary = colorPrimary
        self.era = era
        self.formality = formality
        self.ambientMood = ambientMood
        self.visualWeight = visualWeight
        self.scale = scale
        self.roomRole = roomRole
        self.suitableRooms = suitableRooms
        self.placementHints = placementHints
        self.pairsWellWith = pairsWellWith
        self.useScenarios = useScenarios
        self.spaceRequirements = spaceRequirements
        self.hasArms = hasArms
        self.hasLegs = hasLegs
        self.stackable = stackable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        styleTags = try container.decodeIfPresent([String].self, forKey: .styleTags) ?? []
        designLineage = try container.decodeIfPresent(String.self, forKey: .designLineage) ?? ""
        materialPrimary = try container.decodeIfPresent(String.self, forKey: .materialPrimary) ?? ""
        textureAndFinish = try container.decodeIfPresent(String.self, forKey: .textureAndFinish) ?? ""
        colorPrimary = try container.decodeIfPresent(String.self, forKey: .colorPrimary) ?? ""
        era = try container.decodeIfPresent(String.self, forKey: .era) ?? ""
        formality = try container.decodeIfPresent(String.self, forKey: .formality) ?? ""
        ambientMood = try container.decodeIfPresent([String].self, forKey: .ambientMood) ?? []
        visualWeight = try container.decodeIfPresent(String.self, forKey: .visualWeight) ?? ""
        scale = try container.decodeIfPresent(String.self, forKey: .scale) ?? ""
        roomRole = try container.decodeIfPresent(String.self, forKey: .roomRole) ?? ""
        suitableRooms = try container.decodeIfPresent([String].self, forKey: .suitableRooms) ?? []
        placementHints = try container.decodeIfPresent([String].self, forKey: .placementHints) ?? []
        pairsWellWith = try container.decodeIfPresent([String].self, forKey: .pairsWellWith) ?? []
        useScenarios = try container.decodeIfPresent([String].self, forKey: .useScenarios) ?? []
        spaceRequirements = try container.decodeIfPresent(String.self, forKey: .spaceRequirements) ?? ""
        hasArms = try container.decodeIfPresent(Bool.self, forKey: .hasArms) ?? false
        hasLegs = try container.decodeIfPresent(Bool.self, forKey: .hasLegs) ?? false
        stackable = try container.decodeIfPresent(Bool.self, forKey: .stackable) ?? false
    }

    static let empty = Attributes(
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
    )
}

struct Files: Codable {
    let usdzURL: String
    let thumbURLs: [String]

    enum CodingKeys: String, CodingKey {
        case usdzURL = "usdz_url"
        case thumbURLs = "thumb_urls"
    }

    init(usdzURL: String, thumbURLs: [String]) {
        self.usdzURL = usdzURL
        self.thumbURLs = thumbURLs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usdzURL = try container.decodeIfPresent(String.self, forKey: .usdzURL) ?? ""
        thumbURLs = try container.decodeIfPresent([String].self, forKey: .thumbURLs) ?? []
    }

    static let empty = Files(usdzURL: "", thumbURLs: [])
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
