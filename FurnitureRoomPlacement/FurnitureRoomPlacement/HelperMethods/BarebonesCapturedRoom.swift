//
//  BarebonesCapturedRoom.swift
//  FurnitureRoomPlacement
//
//  Created by Kelvin Jou on 4/24/26.
//


/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Supporting barebones room models, import/export helpers, and SceneKit builders.
*/

import Foundation
import RoomPlan
import SceneKit
import UIKit

struct SavedFurnitureSnapshot: Codable {
    let id: String
    let name: String
    let familyKey: String
    let dimensionsBbox: DimensionsBbox
    let files: SavedFurnitureFiles

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
        case familyKey = "family_key"
        case dimensionsBbox = "dimensions_bbox"
        case files
    }
}

struct SavedFurnitureFiles: Codable {
    let usdzURL: String

    enum CodingKeys: String, CodingKey {
        case usdzURL = "usdz_url"
    }
}

struct PlacedFurnitureObject: Codable, Identifiable {
    let id: String
    let furniture: Furniture
    var placement: FurniturePlacement
    let addedAt: String
    let placedBy: String?
    let rationale: String?

    enum CodingKeys: String, CodingKey {
        case id
        case furniture
        case placement
        case addedAt
        case placedBy = "placed_by"
        case rationale
    }

    init(
        id: String,
        furniture: Furniture,
        placement: FurniturePlacement,
        addedAt: String,
        placedBy: String? = nil,
        rationale: String? = nil
    ) {
        self.id = id
        self.furniture = furniture
        self.placement = placement
        self.addedAt = addedAt
        self.placedBy = placedBy
        self.rationale = rationale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        placement = try container.decode(FurniturePlacement.self, forKey: .placement)
        addedAt = try container.decode(String.self, forKey: .addedAt)
        placedBy = try container.decodeIfPresent(String.self, forKey: .placedBy)
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale)

        if let savedFurniture = try? container.decode(SavedFurnitureSnapshot.self, forKey: .furniture) {
            furniture = Furniture(savedSnapshot: savedFurniture)
        } else {
            furniture = try container.decode(Furniture.self, forKey: .furniture)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(furniture.savedSnapshot, forKey: .furniture)
        try container.encode(placement, forKey: .placement)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encodeIfPresent(placedBy, forKey: .placedBy)
        try container.encodeIfPresent(rationale, forKey: .rationale)
    }
}

struct FurniturePlacement: Codable {
    var position: [Float]
    var eulerAngles: [Float]
    var scale: [Float]
}

enum RemoteUSDZModelOrientation {
    static let previewAlignedCorrection = SCNVector3(
        Float(-Double.pi / 2),
        0,
        0
    )
}

extension FurniturePlacement {
    static let defaultPlacement = FurniturePlacement(
        position: [0, 0, 0],
        eulerAngles: [0, 0, 0],
        scale: [1, 1, 1]
    )

    @MainActor
    init(from node: SCNNode) {
        self = FurniturePlacement(
            position: [node.position.x, node.position.y, node.position.z],
            eulerAngles: [node.eulerAngles.x, node.eulerAngles.y, node.eulerAngles.z],
            scale: [node.scale.x, node.scale.y, node.scale.z]
        )
    }

    @MainActor
    func apply(to node: SCNNode) {
        node.position = SCNVector3(
            position.count > 0 ? position[0] : 0,
            position.count > 1 ? position[1] : 0,
            position.count > 2 ? position[2] : 0
        )
        node.eulerAngles = SCNVector3(
            eulerAngles.count > 0 ? eulerAngles[0] : 0,
            eulerAngles.count > 1 ? eulerAngles[1] : 0,
            eulerAngles.count > 2 ? eulerAngles[2] : 0
        )
        node.scale = SCNVector3(
            scale.count > 0 ? scale[0] : 1,
            scale.count > 1 ? scale[1] : 1,
            scale.count > 2 ? scale[2] : 1
        )
    }
}

@available(iOS 17.0, *)
struct BarebonesCapturedRoom: Codable {
    let identifier: UUID
    let story: Int
    let version: Int
    let walls: [CapturedRoom.Surface]
    let doors: [CapturedRoom.Surface]
    let windows: [CapturedRoom.Surface]
    let openings: [CapturedRoom.Surface]
    let floors: [CapturedRoom.Surface]
    let sections: [CapturedRoom.Section]
    let objects: [PlacedFurnitureObject]

    init(
        identifier: UUID,
        story: Int,
        version: Int,
        walls: [CapturedRoom.Surface],
        doors: [CapturedRoom.Surface],
        windows: [CapturedRoom.Surface],
        openings: [CapturedRoom.Surface],
        floors: [CapturedRoom.Surface],
        sections: [CapturedRoom.Section],
        objects: [PlacedFurnitureObject] = []
    ) {
        self.identifier = identifier
        self.story = story
        self.version = version
        self.walls = walls
        self.doors = doors
        self.windows = windows
        self.openings = openings
        self.floors = floors
        self.sections = sections
        self.objects = objects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(UUID.self, forKey: .identifier)
        story = try container.decode(Int.self, forKey: .story)
        version = try container.decode(Int.self, forKey: .version)
        walls = try container.decode([CapturedRoom.Surface].self, forKey: .walls)
        doors = try container.decode([CapturedRoom.Surface].self, forKey: .doors)
        windows = try container.decode([CapturedRoom.Surface].self, forKey: .windows)
        openings = try container.decode([CapturedRoom.Surface].self, forKey: .openings)
        floors = try container.decode([CapturedRoom.Surface].self, forKey: .floors)
        sections = try container.decode([CapturedRoom.Section].self, forKey: .sections)
        objects = try container.decodeIfPresent([PlacedFurnitureObject].self, forKey: .objects) ?? []
    }
}

struct LegacyBarebonesCapturedRoom: Codable {
    let identifier: UUID
    let walls: [CapturedRoom.Surface]
    let doors: [CapturedRoom.Surface]
    let windows: [CapturedRoom.Surface]
    let openings: [CapturedRoom.Surface]
    let objects: [PlacedFurnitureObject]

    init(
        identifier: UUID,
        walls: [CapturedRoom.Surface],
        doors: [CapturedRoom.Surface],
        windows: [CapturedRoom.Surface],
        openings: [CapturedRoom.Surface],
        objects: [PlacedFurnitureObject] = []
    ) {
        self.identifier = identifier
        self.walls = walls
        self.doors = doors
        self.windows = windows
        self.openings = openings
        self.objects = objects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(UUID.self, forKey: .identifier)
        walls = try container.decode([CapturedRoom.Surface].self, forKey: .walls)
        doors = try container.decode([CapturedRoom.Surface].self, forKey: .doors)
        windows = try container.decode([CapturedRoom.Surface].self, forKey: .windows)
        openings = try container.decode([CapturedRoom.Surface].self, forKey: .openings)
        objects = try container.decodeIfPresent([PlacedFurnitureObject].self, forKey: .objects) ?? []
    }
}

enum BarebonesRoomSceneBuilder {
    static func scene(for room: CapturedRoom) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.6, alpha: 1.0)
        let rootNode = scene.rootNode

        addSurfaces(room.walls, kind: .wall, to: rootNode)
        addSurfaces(room.doors, kind: .door, to: rootNode)
        addSurfaces(room.windows, kind: .window, to: rootNode)
        addSurfaces(room.openings, kind: .opening, to: rootNode)

        if #available(iOS 17.0, *) {
            addSurfaces(room.floors, kind: .floor, to: rootNode)
        }

        return scene
    }

    static func scene(for room: BarebonesCapturedRoom) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.6, alpha: 1.0)
        let rootNode = scene.rootNode

        addSurfaces(room.walls, kind: .wall, to: rootNode)
        addSurfaces(room.doors, kind: .door, to: rootNode)
        addSurfaces(room.windows, kind: .window, to: rootNode)
        addSurfaces(room.openings, kind: .opening, to: rootNode)
        addSurfaces(room.floors, kind: .floor, to: rootNode)
        addCameraAndLights(to: rootNode)

        return scene
    }

    static func scene(for room: LegacyBarebonesCapturedRoom) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.6, alpha: 1.0)
        let rootNode = scene.rootNode

        addSurfaces(room.walls, kind: .wall, to: rootNode)
        addSurfaces(room.doors, kind: .door, to: rootNode)
        addSurfaces(room.windows, kind: .window, to: rootNode)
        addSurfaces(room.openings, kind: .opening, to: rootNode)
        addCameraAndLights(to: rootNode)

        return scene
    }

    static func scene(for room: SanitizedRoomPayload) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.6, alpha: 1.0)
        let rootNode = scene.rootNode

        addSanitizedFloor(from: room, to: rootNode)
        addSanitizedWalls(room.walls, to: rootNode)
        addSanitizedOpenings(room.openings, to: rootNode)
        addCameraAndLights(to: rootNode)

        return scene
    }

    @discardableResult
    static func overlayExternalUSDZ(
        on scene: SCNScene,
        add USDZFileName: String,
        overlayIdentifier: String = UUID().uuidString
    ) -> Bool {
        addExternalUSDZ(
            to: scene.rootNode,
            USDZFileName: USDZFileName,
            overlayIdentifier: overlayIdentifier
        )
    }

    @discardableResult
    static func overlayExternalUSDZ(
        on scene: SCNScene,
        fileURL: URL,
        overlayIdentifier: String = UUID().uuidString
    ) -> Bool {
        addExternalUSDZ(
            to: scene.rootNode,
            fileURL: fileURL,
            overlayIdentifier: overlayIdentifier
        )
    }

    private static func addSurfaces(
        _ surfaces: [CapturedRoom.Surface],
        kind: SurfaceKind,
        to rootNode: SCNNode
    ) {
        for surface in surfaces {
            let surfaceNode = SCNNode()
            surfaceNode.simdTransform = surface.transform
            surfaceNode.name = "\(kind.nodeName)-\(surface.identifier.uuidString)"

            if let geometry = makeGeometry(for: surface, kind: kind) {
                let geometryNode = SCNNode(geometry: geometry)
                geometryNode.position.z += surfaceDepthOffset(for: kind)
                geometryNode.renderingOrder = renderingOrder(for: kind)
                surfaceNode.addChildNode(geometryNode)
            }

            if let outlineNode = makeOutlineNode(for: surface, kind: kind) {
                surfaceNode.addChildNode(outlineNode)
            }

            rootNode.addChildNode(surfaceNode)
        }
    }

    private static func addSanitizedWalls(_ walls: [SanitizedWall], to rootNode: SCNNode) {
        for wall in walls {
            addSanitizedPlane(
                identifier: wall.id,
                kind: .wall,
                width: wall.width,
                height: wall.height,
                center: wall.center,
                rotationRadians: wall.rotationRadians,
                to: rootNode
            )
        }
    }

    private static func addSanitizedOpenings(_ openings: [SanitizedOpening], to rootNode: SCNNode) {
        for opening in openings {
            addSanitizedPlane(
                identifier: opening.id,
                kind: sanitizedSurfaceKind(for: opening.type),
                width: opening.width,
                height: opening.height,
                center: opening.center,
                rotationRadians: opening.rotationRadians,
                to: rootNode
            )
        }
    }

    private static func addSanitizedFloor(from payload: SanitizedRoomPayload, to rootNode: SCNNode) {
        let floorNode = SCNNode()
        floorNode.name = "\(SurfaceKind.floor.nodeName)-\(payload.room.id)"
        floorNode.position.y = floorElevation(from: payload)

        if let geometry = makeSanitizedFloorGeometry(from: payload) {
            let geometryNode = SCNNode(geometry: geometry)
            geometryNode.position.y += surfaceDepthOffset(for: .floor)
            geometryNode.renderingOrder = renderingOrder(for: .floor)
            floorNode.addChildNode(geometryNode)
        }

        if let outlineNode = makeSanitizedFloorOutlineNode(from: payload) {
            floorNode.addChildNode(outlineNode)
        }

        rootNode.addChildNode(floorNode)
    }

    private static func floorElevation(from payload: SanitizedRoomPayload) -> Float {
        let wallBottoms = payload.walls.compactMap { wall -> Double? in
            guard wall.center.count >= 2 else { return nil }
            return wall.center[1] - (wall.height / 2)
        }

        guard let lowestWallBottom = wallBottoms.min() else {
            return 0
        }

        return Float(lowestWallBottom)
    }

    private static func addSanitizedPlane(
        identifier: String,
        kind: SurfaceKind,
        width: Double,
        height: Double,
        center: [Double],
        rotationRadians: Double,
        to rootNode: SCNNode
    ) {
        let surfaceNode = SCNNode()
        surfaceNode.name = "\(kind.nodeName)-\(identifier)"
        surfaceNode.position = SCNVector3(
            center.count > 0 ? center[0] : 0,
            center.count > 1 ? center[1] : 0,
            center.count > 2 ? center[2] : 0
        )
        surfaceNode.eulerAngles.y = Float(rotationRadians)

        let plane = SCNPlane(
            width: CGFloat(max(width, 0.01)),
            height: CGFloat(max(height, 0.01))
        )
        plane.materials = [kind.material]

        let geometryNode = SCNNode(geometry: plane)
        geometryNode.position.z += surfaceDepthOffset(for: kind)
        geometryNode.renderingOrder = renderingOrder(for: kind)
        surfaceNode.addChildNode(geometryNode)

        let halfWidth = Float(max(width, 0.01) / 2)
        let halfHeight = Float(max(height, 0.01) / 2)
        let outlineVertices = [
            SCNVector3(-halfWidth, -halfHeight, 0),
            SCNVector3(halfWidth, -halfHeight, 0),
            SCNVector3(halfWidth, halfHeight, 0),
            SCNVector3(-halfWidth, halfHeight, 0)
        ]
        if let outlineNode = makeOutlineNode(from: outlineVertices, kind: kind) {
            surfaceNode.addChildNode(outlineNode)
        }

        rootNode.addChildNode(surfaceNode)
    }

    private static func makeSanitizedFloorGeometry(from payload: SanitizedRoomPayload) -> SCNGeometry? {
        let polygon = sanitizedFloorVertices(from: payload)
        guard polygon.count >= 3 else { return nil }
        return polygonGeometry(from: polygon, kind: .floor)
    }

    private static func makeSanitizedFloorOutlineNode(from payload: SanitizedRoomPayload) -> SCNNode? {
        let vertices = sanitizedFloorVertices(from: payload).map { SCNVector3($0.x, $0.y, $0.z) }
        return makeOutlineNode(from: vertices, kind: .floor)
    }

    private static func sanitizedFloorVertices(from payload: SanitizedRoomPayload) -> [simd_float3] {
        let polygonFromShell: [simd_float3] = payload.room.floorPolygon.compactMap { point -> simd_float3? in
            guard point.count >= 2 else { return nil }
            return simd_float3(Float(point[0]), 0, Float(point[1]))
        }
        if isValidFloorPolygon(polygonFromShell) {
            return polygonFromShell
        }

        let polygonFromWalls = floorPolygon(from: payload.walls)
        if isValidFloorPolygon(polygonFromWalls) {
            return polygonFromWalls
        }

        let room = payload.room
        return [
            simd_float3(-Float(max(room.boundingBox.width, 0.01) / 2), 0, -Float(max(room.boundingBox.depth, 0.01) / 2)),
            simd_float3(Float(max(room.boundingBox.width, 0.01) / 2), 0, -Float(max(room.boundingBox.depth, 0.01) / 2)),
            simd_float3(Float(max(room.boundingBox.width, 0.01) / 2), 0, Float(max(room.boundingBox.depth, 0.01) / 2)),
            simd_float3(-Float(max(room.boundingBox.width, 0.01) / 2), 0, Float(max(room.boundingBox.depth, 0.01) / 2))
        ]
    }

    private static func floorPolygon(from walls: [SanitizedWall]) -> [simd_float3] {
        let points = walls.flatMap { wall in
            let startX = wall.start.indices.contains(0) ? wall.start[0] : 0
            let startZ = wall.start.indices.contains(1) ? wall.start[1] : 0
            let endX = wall.end.indices.contains(0) ? wall.end[0] : 0
            let endZ = wall.end.indices.contains(1) ? wall.end[1] : 0
            return [
                simd_float2(Float(startX), Float(startZ)),
                simd_float2(Float(endX), Float(endZ))
            ]
        }
        let uniquePoints = deduplicatedFloorPoints(points)
        let hull = convexHull(uniquePoints)
        return hull.map { simd_float3($0.x, 0, $0.y) }
    }

    private static func isValidFloorPolygon(_ polygon: [simd_float3]) -> Bool {
        guard polygon.count >= 3 else { return false }
        return abs(polygonArea(polygon)) > 0.01
    }

    private static func polygonArea(_ polygon: [simd_float3]) -> Float {
        guard polygon.count >= 3 else { return 0 }
        var area: Float = 0
        for index in polygon.indices {
            let current = polygon[index]
            let next = polygon[(index + 1) % polygon.count]
            area += (current.x * next.z) - (next.x * current.z)
        }
        return area * 0.5
    }

    private static func deduplicatedFloorPoints(_ points: [simd_float2], tolerance: Float = 0.02) -> [simd_float2] {
        var unique: [simd_float2] = []
        for point in points {
            if unique.contains(where: { simd_distance($0, point) <= tolerance }) {
                continue
            }
            unique.append(point)
        }
        return unique
    }

    private static func convexHull(_ points: [simd_float2]) -> [simd_float2] {
        guard points.count > 3 else { return points }
        let sorted = points.sorted {
            if $0.x == $1.x { return $0.y < $1.y }
            return $0.x < $1.x
        }

        func cross(_ origin: simd_float2, _ a: simd_float2, _ b: simd_float2) -> Float {
            let oa = a - origin
            let ob = b - origin
            return (oa.x * ob.y) - (oa.y * ob.x)
        }

        var lower: [simd_float2] = []
        for point in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }

        var upper: [simd_float2] = []
        for point in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }

        return Array((lower.dropLast() + upper.dropLast()))
    }

    private static func sanitizedSurfaceKind(for type: String) -> SurfaceKind {
        switch type.lowercased() {
        case "door":
            return .door
        case "window":
            return .window
        default:
            return .opening
        }
    }

    @discardableResult
    private static func addExternalUSDZ(
        to rootNode: SCNNode,
        USDZFileName: String,
        overlayIdentifier: String
    ) -> Bool {
        guard let importedNode = loadExternalUSDZNode(named: USDZFileName) else {
            return false
        }

        let placedNode = normalizedImportedNode(from: importedNode)
        placedNode.position = placementPosition(in: rootNode)
        applyRenderingOrder(1000, to: placedNode)
        placedNode.name = overlayNodeName(for: overlayIdentifier)
        rootNode.addChildNode(placedNode)
        return true
    }

    @discardableResult
    private static func addExternalUSDZ(
        to rootNode: SCNNode,
        fileURL: URL,
        overlayIdentifier: String
    ) -> Bool {
        guard let importedNode = loadExternalUSDZNode(fileURL: fileURL) else {
            return false
        }

        let placedNode = normalizedImportedNode(from: importedNode)
        placedNode.position = placementPosition(in: rootNode)
        applyRenderingOrder(1000, to: placedNode)
        placedNode.name = overlayNodeName(for: overlayIdentifier)
        rootNode.addChildNode(placedNode)
        return true
    }

    static func overlayNodeName(for identifier: String) -> String {
        "external-usdz-overlay-\(identifier)"
    }

    private static func loadExternalUSDZNode(named assetName: String) -> SCNNode? {
        if let url = Bundle.main.url(forResource: assetName, withExtension: "usdz"),
           let scene = try? SCNScene(url: url, options: nil),
           let node = importedContentNode(from: scene) {
            return node
        }

        if let url = bundledUSDZURL(fromDataAssetNamed: assetName),
           let scene = try? SCNScene(url: url, options: nil),
           let node = importedContentNode(from: scene) {
            return node
        }

        return nil
    }

    private static func loadExternalUSDZNode(fileURL: URL) -> SCNNode? {
        guard let scene = try? SCNScene(url: fileURL, options: nil) else {
            return nil
        }

        return importedContentNode(from: scene)
    }

    private static func bundledUSDZURL(fromDataAssetNamed assetName: String) -> URL? {
        guard let dataAsset = NSDataAsset(name: assetName, bundle: .main) else {
            return nil
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: assetName)
            .appendingPathExtension("usdz")

        do {
            try dataAsset.data.write(to: temporaryURL, options: .atomic)
            return temporaryURL
        } catch {
            return nil
        }
    }

    private static func importedContentNode(from scene: SCNScene) -> SCNNode? {
        let containerNode = SCNNode()

        if scene.rootNode.geometry != nil {
            containerNode.addChildNode(scene.rootNode.flattenedClone())
        }

        for childNode in scene.rootNode.childNodes where containsRenderableContent(childNode) {
            containerNode.addChildNode(childNode.clone())
        }

        return containerNode.childNodes.isEmpty ? nil : containerNode
    }

    private static func containsRenderableContent(_ node: SCNNode) -> Bool {
        if node.geometry != nil || node.morpher != nil || node.skinner != nil {
            return true
        }

        for childNode in node.childNodes {
            if containsRenderableContent(childNode) {
                return true
            }
        }

        return false
    }

    private static func normalizedImportedNode(from node: SCNNode) -> SCNNode {
        let containerNode = SCNNode()
        let modelNode = node.clone()
        modelNode.eulerAngles.x += RemoteUSDZModelOrientation.previewAlignedCorrection.x
        modelNode.eulerAngles.y += RemoteUSDZModelOrientation.previewAlignedCorrection.y
        modelNode.eulerAngles.z += RemoteUSDZModelOrientation.previewAlignedCorrection.z
        containerNode.addChildNode(modelNode)

        var (minimumBounds, maximumBounds) = containerNode.boundingBox
        let largestDimension = max(
            maximumBounds.x - minimumBounds.x,
            maximumBounds.y - minimumBounds.y,
            maximumBounds.z - minimumBounds.z
        )

        if largestDimension > 5 {
            let scale = 1 / largestDimension
            modelNode.scale = SCNVector3(scale, scale, scale)
        } else if largestDimension > 0, largestDimension < 0.05 {
            let scale = 0.5 / largestDimension
            modelNode.scale = SCNVector3(scale, scale, scale)
        }

        (minimumBounds, maximumBounds) = containerNode.boundingBox
        let centerX = (minimumBounds.x + maximumBounds.x) / 2
        let centerZ = (minimumBounds.z + maximumBounds.z) / 2
        modelNode.position.x -= centerX
        modelNode.position.y -= minimumBounds.y
        modelNode.position.z -= centerZ

        return containerNode
    }

    private static func placementPosition(in rootNode: SCNNode) -> SCNVector3 {
        let (minimumBounds, maximumBounds) = rootNode.boundingBox
        let centerX = (minimumBounds.x + maximumBounds.x) / 2
        let centerZ = (minimumBounds.z + maximumBounds.z) / 2
        return SCNVector3(centerX, minimumBounds.y, centerZ)
    }

    private static func applyRenderingOrder(_ renderingOrder: Int, to node: SCNNode) {
        node.renderingOrder = renderingOrder
        for childNode in node.childNodes {
            applyRenderingOrder(renderingOrder, to: childNode)
        }
    }

    private static func addCameraAndLights(to rootNode: SCNNode) {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 2.2, 6.0)
        rootNode.addChildNode(cameraNode)

        let ambientNode = SCNNode()
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 800
        rootNode.addChildNode(ambientNode)

        let omniNode = SCNNode()
        omniNode.light = SCNLight()
        omniNode.light?.type = .omni
        omniNode.light?.intensity = 900
        omniNode.position = SCNVector3(2.5, 4.0, 4.5)
        rootNode.addChildNode(omniNode)
    }

    private static func makeGeometry(
        for surface: CapturedRoom.Surface,
        kind: SurfaceKind
    ) -> SCNGeometry? {
        let corners = surface.polygonCorners

        if corners.count >= 3, let geometry = polygonGeometry(from: corners, kind: kind) {
            return geometry
        }

        return fallbackGeometry(for: surface, kind: kind)
    }

    private static func polygonGeometry(
        from corners: [simd_float3],
        kind: SurfaceKind
    ) -> SCNGeometry? {
        guard corners.count >= 3 else { return nil }

        let vertices = corners.map { SCNVector3($0.x, $0.y, $0.z) }
        let source = SCNGeometrySource(vertices: vertices)

        var indices: [UInt32] = []
        for index in 1..<(corners.count - 1) {
            indices.append(0)
            indices.append(UInt32(index))
            indices.append(UInt32(index + 1))
        }

        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.materials = [kind.material]
        return geometry
    }

    private static func fallbackGeometry(
        for surface: CapturedRoom.Surface,
        kind: SurfaceKind
    ) -> SCNGeometry {
        switch kind {
        case .floor:
            let width = CGFloat(max(surface.dimensions.x, 0.01))
            let length = CGFloat(max(surface.dimensions.z, 0.01))
            let plane = SCNPlane(width: width, height: length)
            plane.materials = [kind.material]
            return plane
        case .wall, .door, .window, .opening:
            let width = CGFloat(max(surface.dimensions.x, 0.01))
            let height = CGFloat(max(surface.dimensions.y, 0.01))
            let plane = SCNPlane(width: width, height: height)
            plane.materials = [kind.material]
            return plane
        }
    }

    private static func makeOutlineNode(
        for surface: CapturedRoom.Surface,
        kind: SurfaceKind
    ) -> SCNNode? {
        let corners = surface.polygonCorners
        let outlineVertices: [SCNVector3]

        if corners.count >= 2 {
            outlineVertices = corners.map { SCNVector3($0.x, $0.y, $0.z) }
        } else {
            outlineVertices = fallbackOutlineVertices(for: surface, kind: kind)
        }

        return makeOutlineNode(from: outlineVertices, kind: kind)
    }

    private static func fallbackOutlineVertices(
        for surface: CapturedRoom.Surface,
        kind: SurfaceKind
    ) -> [SCNVector3] {
        switch kind {
        case .floor:
            let halfWidth = Float(max(surface.dimensions.x, 0.01) / 2)
            let halfLength = Float(max(surface.dimensions.z, 0.01) / 2)
            return [
                SCNVector3(-halfWidth, -halfLength, 0),
                SCNVector3(halfWidth, -halfLength, 0),
                SCNVector3(halfWidth, halfLength, 0),
                SCNVector3(-halfWidth, halfLength, 0)
            ]
        case .wall, .door, .window, .opening:
            let halfWidth = Float(max(surface.dimensions.x, 0.01) / 2)
            let halfHeight = Float(max(surface.dimensions.y, 0.01) / 2)
            return [
                SCNVector3(-halfWidth, -halfHeight, 0),
                SCNVector3(halfWidth, -halfHeight, 0),
                SCNVector3(halfWidth, halfHeight, 0),
                SCNVector3(-halfWidth, halfHeight, 0)
            ]
        }
    }

    private static func makeOutlineNode(
        from vertices: [SCNVector3],
        kind: SurfaceKind
    ) -> SCNNode? {
        guard vertices.count >= 2 else { return nil }

        let outlineNode = SCNNode()
        let thickness = outlineThickness(for: kind)
        let zOffset = outlineOffset(for: kind)

        for index in vertices.indices {
            let start = vertices[index]
            let end = vertices[(index + 1) % vertices.count]

            guard let edgeNode = makeEdgeNode(from: start, to: end, thickness: thickness) else {
                continue
            }

            edgeNode.position.z += zOffset
            outlineNode.addChildNode(edgeNode)
        }

        return outlineNode.childNodes.isEmpty ? nil : outlineNode
    }

    private static func makeEdgeNode(
        from start: SCNVector3,
        to end: SCNVector3,
        thickness: CGFloat
    ) -> SCNNode? {
        let startVector = simd_float3(start)
        let endVector = simd_float3(end)
        let segment = endVector - startVector
        let length = simd_length(segment)

        guard length > 0.0001 else { return nil }

        let box = SCNBox(width: thickness, height: thickness, length: CGFloat(length), chamferRadius: 0)
        box.materials = [SurfaceKind.outlineMaterial]

        let edgeNode = SCNNode(geometry: box)
        edgeNode.simdPosition = (startVector + endVector) / 2
        edgeNode.simdOrientation = simd_quatf(from: simd_float3(0, 0, 1), to: simd_normalize(segment))
        return edgeNode
    }

    private static func outlineThickness(for kind: SurfaceKind) -> CGFloat {
        switch kind {
        case .floor:
            return 0.025
        case .wall, .door, .window, .opening:
            return 0.02
        }
    }

    private static func outlineOffset(for kind: SurfaceKind) -> Float {
        switch kind {
        case .floor:
            return 0.006
        case .wall, .door, .window, .opening:
            return 0.004
        }
    }

    private static func surfaceDepthOffset(for kind: SurfaceKind) -> Float {
        switch kind {
        case .floor, .wall:
            return 0
        case .door:
            return 0.008
        case .window:
            return 0.012
        case .opening:
            return 0.016
        }
    }

    private static func renderingOrder(for kind: SurfaceKind) -> Int {
        switch kind {
        case .floor:
            return 0
        case .wall:
            return 1
        case .door:
            return 2
        case .window:
            return 3
        case .opening:
            return 4
        }
    }
}

enum BarebonesRoomImportLoader {
    static func loadScene(from data: Data) throws -> SCNScene {
        let decoder = JSONDecoder()

        if let room = try? decoder.decode(SanitizedRoomPayload.self, from: data) {
            return BarebonesRoomSceneBuilder.scene(for: room)
        }

        if #available(iOS 17.0, *), let room = try? decoder.decode(BarebonesCapturedRoom.self, from: data) {
            return BarebonesRoomSceneBuilder.scene(for: room)
        }

        if let room = try? decoder.decode(LegacyBarebonesCapturedRoom.self, from: data) {
            return BarebonesRoomSceneBuilder.scene(for: room)
        }

        throw BarebonesImportError.unsupportedFile
    }

    static func loadPlacedObjects(from data: Data) throws -> [PlacedFurnitureObject] {
        let decoder = JSONDecoder()

        if let room = try? decoder.decode(SanitizedRoomPayload.self, from: data) {
            return room.objects
        }

        if #available(iOS 17.0, *), let room = try? decoder.decode(BarebonesCapturedRoom.self, from: data) {
            return room.objects
        }

        if let room = try? decoder.decode(LegacyBarebonesCapturedRoom.self, from: data) {
            return room.objects
        }

        throw BarebonesImportError.unsupportedFile
    }
}

enum BarebonesRoomJSONSanitizer {
    private static let essentialKeys = [
        "identifier",
        "story",
        "version",
        "walls",
        "doors",
        "windows",
        "openings",
        "floors",
        "sections",
        "objects"
    ]

    static func stripToEssentialSurfaces(from data: Data) throws -> Data {
        let jsonObject = try JSONSerialization.jsonObject(with: data)

        guard let roomDictionary = jsonObject as? [String: Any] else {
            throw BarebonesImportError.unsupportedFile
        }

        let strippedRoom = essentialKeys.reduce(into: [String: Any]()) { result, key in
            if let value = roomDictionary[key] {
                result[key] = value
            }
        }

        guard roomDictionary["walls"] != nil
            || roomDictionary["doors"] != nil
            || roomDictionary["windows"] != nil
            || roomDictionary["openings"] != nil
            || roomDictionary["floors"] != nil else {
            throw BarebonesImportError.unsupportedFile
        }

        var normalizedRoom = strippedRoom
        normalizedRoom["identifier"] = strippedRoom["identifier"] ?? UUID().uuidString
        normalizedRoom["story"] = strippedRoom["story"] ?? 0
        normalizedRoom["version"] = strippedRoom["version"] ?? 1
        normalizedRoom["walls"] = strippedRoom["walls"] ?? []
        normalizedRoom["doors"] = strippedRoom["doors"] ?? []
        normalizedRoom["windows"] = strippedRoom["windows"] ?? []
        normalizedRoom["openings"] = strippedRoom["openings"] ?? []
        normalizedRoom["floors"] = strippedRoom["floors"] ?? []
        normalizedRoom["sections"] = strippedRoom["sections"] ?? []
        normalizedRoom["objects"] = []

        return try JSONSerialization.data(
            withJSONObject: normalizedRoom,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    static func normalizedRoomData(from data: Data) throws -> Data {
        if let sanitizedRoom = try? JSONDecoder().decode(SanitizedRoomPayload.self, from: data) {
            return try JSONEncoder.prettyPrintedSorted.encode(sanitizedRoom)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data)

        guard var roomDictionary = jsonObject as? [String: Any] else {
            throw BarebonesImportError.unsupportedFile
        }

        guard roomDictionary["walls"] != nil
            || roomDictionary["doors"] != nil
            || roomDictionary["windows"] != nil
            || roomDictionary["openings"] != nil
            || roomDictionary["floors"] != nil else {
            throw BarebonesImportError.unsupportedFile
        }

        roomDictionary["identifier"] = roomDictionary["identifier"] ?? UUID().uuidString
        roomDictionary["story"] = roomDictionary["story"] ?? 0
        roomDictionary["version"] = roomDictionary["version"] ?? 1
        roomDictionary["walls"] = roomDictionary["walls"] ?? []
        roomDictionary["doors"] = roomDictionary["doors"] ?? []
        roomDictionary["windows"] = roomDictionary["windows"] ?? []
        roomDictionary["openings"] = roomDictionary["openings"] ?? []
        roomDictionary["floors"] = roomDictionary["floors"] ?? []
        roomDictionary["sections"] = roomDictionary["sections"] ?? []
        roomDictionary["objects"] = roomDictionary["objects"] ?? []

        return try JSONSerialization.data(
            withJSONObject: roomDictionary,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    static func roomData(byUpdatingObjects objects: [PlacedFurnitureObject], in data: Data) throws -> Data {
        if let sanitizedRoom = try? JSONDecoder().decode(SanitizedRoomPayload.self, from: data) {
            return try JSONEncoder.prettyPrintedSorted.encode(
                sanitizedRoom.replacingObjects(with: objects)
            )
        }

        let normalizedData = try normalizedRoomData(from: data)
        let jsonObject = try JSONSerialization.jsonObject(with: normalizedData)

        guard var roomDictionary = jsonObject as? [String: Any] else {
            throw BarebonesImportError.unsupportedFile
        }

        let objectsData = try JSONEncoder().encode(objects)
        let encodedObjects = try JSONSerialization.jsonObject(with: objectsData)
        roomDictionary["objects"] = encodedObjects

        return try JSONSerialization.data(
            withJSONObject: roomDictionary,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    static func placedObjects(fromDesignObjectsData data: Data) throws -> [PlacedFurnitureObject] {
        try JSONDecoder().decode([PlacedFurnitureObject].self, from: data)
    }

    static func roomData(
        byMergingObjectsFromDesignObjectsData designObjectsData: Data,
        intoRoomData baseRoomData: Data
    ) throws -> (roomData: Data, objects: [PlacedFurnitureObject]) {
        let normalizedData = try normalizedRoomData(from: baseRoomData)
        let existingObjects = try BarebonesRoomImportLoader.loadPlacedObjects(from: normalizedData)
        let fetchedObjects = try placedObjects(fromDesignObjectsData: designObjectsData)
        let mergedObjects = mergePlacedObjects(existing: existingObjects, fetched: fetchedObjects)
        let updatedRoomData = try roomData(byUpdatingObjects: mergedObjects, in: normalizedData)
        return (updatedRoomData, mergedObjects)
    }

    private static func mergePlacedObjects(
        existing: [PlacedFurnitureObject],
        fetched: [PlacedFurnitureObject]
    ) -> [PlacedFurnitureObject] {
        let existingIDs = Set(existing.map(\.id))
        let newFetchedObjects = fetched.filter { !existingIDs.contains($0.id) }
        return existing + newFetchedObjects
    }
}

enum BarebonesImportError: LocalizedError {
    case unsupportedFile

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "The selected file is not a supported barebones room JSON export."
        }
    }
}

enum BarebonesExportError: LocalizedError {
    case usdzExportFailed

    var errorDescription: String? {
        switch self {
        case .usdzExportFailed:
            return "The app could not generate the shell-only USDZ file."
        }
    }
}

private extension JSONEncoder {
    static var prettyPrintedSorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private enum SurfaceKind {
    case floor
    case wall
    case door
    case window
    case opening

    var nodeName: String {
        switch self {
        case .floor:
            return "floor"
        case .wall:
            return "wall"
        case .door:
            return "door"
        case .window:
            return "window"
        case .opening:
            return "opening"
        }
    }

    var material: SCNMaterial {
        let material = SCNMaterial()
        material.isDoubleSided = true
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.9
        material.metalness.contents = 0.0

        switch self {
        case .floor:
            material.diffuse.contents = UIColor(white: 0.82, alpha: 1.0)
        case .wall:
            material.diffuse.contents = UIColor(white: 0.93, alpha: 1.0)
        case .door:
            material.diffuse.contents = UIColor(red: 0.67, green: 0.49, blue: 0.32, alpha: 1.0)
        case .window:
            material.diffuse.contents = UIColor(red: 0.72, green: 0.86, blue: 0.98, alpha: 0.35)
            material.transparency = 0.35
        case .opening:
            material.diffuse.contents = UIColor(red: 0.92, green: 0.78, blue: 0.56, alpha: 0.2)
            material.transparency = 0.2
        }

        return material
    }

    static var outlineMaterial: SCNMaterial {
        let material = SCNMaterial()
        material.isDoubleSided = true
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.black
        return material
    }
}
