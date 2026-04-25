//
//  RoomJSONSanitizer.swift
//  FurnitureRoomPlacement
//
//  Created by Codex on 4/24/26.
//

import Foundation

final class RoomJSONSanitizer {
    static func sanitizedRoom(from data: Data) throws -> SanitizedRoomPayload {
        let decoder = JSONDecoder()
        let room = try decoder.decode(RawCapturedRoom.self, from: data)
        return sanitizedRoom(from: room)
    }

    static func sanitizedJSONData(from data: Data, prettyPrinted: Bool = true) throws -> Data {
        let sanitizedRoom = try sanitizedRoom(from: data)
        return try sanitizedJSONData(from: sanitizedRoom, prettyPrinted: prettyPrinted)
    }

    static func sanitizedJSONData(from room: SanitizedRoomPayload, prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(room)
    }

    static func sanitizedRoom(from room: RawCapturedRoom) -> SanitizedRoomPayload {
        let sanitizedWalls = room.walls.enumerated().map { index, wall in
            sanitizedWall(from: wall, fallbackID: "wall_\(index + 1)")
        }

        let wallIDMap = Dictionary(uniqueKeysWithValues: zip(room.walls.map(\.identifier), sanitizedWalls.map(\.id)))

        let sanitizedOpenings =
            room.doors.enumerated().map { index, door in
                sanitizedOpening(from: door, fallbackID: "door_\(index + 1)", wallIDMap: wallIDMap)
            }
            + room.windows.enumerated().map { index, window in
                sanitizedOpening(from: window, fallbackID: "window_\(index + 1)", wallIDMap: wallIDMap)
            }
            + room.openings.enumerated().map { index, opening in
                sanitizedOpening(from: opening, fallbackID: "opening_\(index + 1)", wallIDMap: wallIDMap)
            }

        let floor = room.floors.first
        let roomType = room.sections.first?.label
        let floorPolygon = floor.map(floorPolygon(from:)) ?? []
        let floorDimensions = floor.map { dimensions(for: $0) } ?? Dimensions(width: 0, height: 0, depth: 0)
        let ceilingHeight = sanitizedWalls.map(\.height).max() ?? 0

        return SanitizedRoomPayload(
            schemaVersion: "1.0",
            units: "meters",
            room: SanitizedRoom(
                id: room.identifier,
                type: roomType,
                story: room.story,
                boundingBox: SanitizedBoundingBox(
                    width: rounded(floorDimensions.width),
                    depth: rounded(floorDimensions.depth > 0 ? floorDimensions.depth : floorDimensions.height)
                ),
                floorPolygon: floorPolygon,
                ceilingHeight: rounded(ceilingHeight)
            ),
            walls: sanitizedWalls,
            openings: sanitizedOpenings,
            metadata: SanitizedMetadata(
                sourceVersion: room.version,
                generatedAt: ISO8601DateFormatter().string(from: Date())
            )
        )
    }

    private static func sanitizedWall(from surface: RawSurface, fallbackID: String) -> SanitizedWall {
        let dimensions = dimensions(for: surface)
        let center = translation(from: surface.transform)
        let segment = wallSegment(from: surface)

        return SanitizedWall(
            id: fallbackID,
            width: rounded(dimensions.width),
            height: rounded(dimensions.height),
            center: rounded(center),
            rotationRadians: rounded(yaw(from: surface.transform)),
            start: rounded(segment.start),
            end: rounded(segment.end),
            confidence: rounded(surface.confidence.numericValue)
        )
    }

    private static func sanitizedOpening(
        from surface: RawSurface,
        fallbackID: String,
        wallIDMap: [String: String]
    ) -> SanitizedOpening {
        let dimensions = dimensions(for: surface)
        let center = translation(from: surface.transform)
        let bottomHeight = center[1] - (dimensions.height / 2)

        return SanitizedOpening(
            id: fallbackID,
            type: surface.category.surfaceType.rawValue,
            wallID: surface.parentIdentifier.flatMap { wallIDMap[$0] },
            width: rounded(dimensions.width),
            height: rounded(dimensions.height),
            center: rounded(center),
            rotationRadians: rounded(yaw(from: surface.transform)),
            bottomHeight: rounded(max(bottomHeight, 0)),
            isOpen: surface.category.door?.isOpen,
            confidence: rounded(surface.confidence.numericValue)
        )
    }

    private static func floorPolygon(from surface: RawSurface) -> [[Double]] {
        let corners = surface.polygonCorners

        if !corners.isEmpty {
            return corners.map { corner in
                [rounded(corner.x), rounded(corner.z)]
            }
        }

        let dimensions = dimensions(for: surface)
        let center = translation(from: surface.transform)
        let xAxis = normalizedXAxis(from: surface.transform)
        let zAxis = normalizedZAxis(from: surface.transform)
        let halfWidth = dimensions.width / 2
        let halfDepth = (dimensions.depth > 0 ? dimensions.depth : dimensions.height) / 2

        let localCorners: [(Double, Double)] = [
            (-halfWidth, -halfDepth),
            (-halfWidth, halfDepth),
            (halfWidth, halfDepth),
            (halfWidth, -halfDepth)
        ]

        return localCorners.map { localX, localZ in
            let worldX = center[0] + (xAxis.x * localX) + (zAxis.x * localZ)
            let worldZ = center[2] + (xAxis.z * localX) + (zAxis.z * localZ)
            return [rounded(worldX), rounded(worldZ)]
        }
    }

    private static func wallSegment(from surface: RawSurface) -> (start: [Double], end: [Double]) {
        let dimensions = dimensions(for: surface)
        let center = translation(from: surface.transform)
        let xAxis = normalizedXAxis(from: surface.transform)
        let halfWidth = dimensions.width / 2

        let start = [
            center[0] - (xAxis.x * halfWidth),
            center[2] - (xAxis.z * halfWidth)
        ]
        let end = [
            center[0] + (xAxis.x * halfWidth),
            center[2] + (xAxis.z * halfWidth)
        ]

        return (start, end)
    }

    private static func dimensions(for surface: RawSurface) -> Dimensions {
        let width = surface.dimensions[safe: 0] ?? 0
        let secondValue = surface.dimensions[safe: 1] ?? 0
        let depth = surface.dimensions[safe: 2] ?? 0

        if surface.category.surfaceType == .floor {
            return Dimensions(width: width, height: 0, depth: secondValue)
        }

        return Dimensions(width: width, height: secondValue, depth: depth)
    }

    private static func translation(from transform: [Double]) -> [Double] {
        [
            rounded(transform[safe: 12] ?? 0),
            rounded(transform[safe: 13] ?? 0),
            rounded(transform[safe: 14] ?? 0)
        ]
    }

    private static func yaw(from transform: [Double]) -> Double {
        let x = transform[safe: 0] ?? 1
        let z = transform[safe: 8] ?? 0
        return atan2(z, x)
    }

    private static func normalizedXAxis(from transform: [Double]) -> Vector2D {
        normalize(
            Vector2D(
                x: transform[safe: 0] ?? 1,
                z: transform[safe: 2] ?? 0
            )
        )
    }

    private static func normalizedZAxis(from transform: [Double]) -> Vector2D {
        normalize(
            Vector2D(
                x: transform[safe: 8] ?? 0,
                z: transform[safe: 10] ?? 1
            )
        )
    }

    private static func normalize(_ vector: Vector2D) -> Vector2D {
        let length = sqrt((vector.x * vector.x) + (vector.z * vector.z))
        guard length > 0.0001 else {
            return Vector2D(x: 1, z: 0)
        }

        return Vector2D(x: vector.x / length, z: vector.z / length)
    }

    private static func rounded(_ value: Double, decimals: Int = 3) -> Double {
        let factor = pow(10, Double(decimals))
        return (value * factor).rounded() / factor
    }

    private static func rounded(_ values: [Double], decimals: Int = 3) -> [Double] {
        values.map { rounded($0, decimals: decimals) }
    }
}

struct RawCapturedRoom: Codable {
    let doors: [RawSurface]
    let floors: [RawSurface]
    let identifier: String
    let openings: [RawSurface]
    let sections: [RawSection]
    let story: Int
    let version: Int
    let walls: [RawSurface]
    let windows: [RawSurface]
}

struct RawSurface: Codable {
    let category: RawCategory
    let confidence: RawConfidence
    let dimensions: [Double]
    let identifier: String
    let parentIdentifier: String?
    let polygonCorners: [RawVector3]
    let story: Int
    let transform: [Double]

    enum CodingKeys: String, CodingKey {
        case category
        case confidence
        case dimensions
        case identifier
        case parentIdentifier
        case polygonCorners
        case story
        case transform
    }
}

struct RawSection: Codable {
    let center: [Double]
    let label: String
    let story: Int
}

struct RawCategory: Codable {
    let surfaceType: SurfaceType
    let door: RawDoorCategory?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        if container.contains(DynamicCodingKey("door")) {
            door = try container.decodeIfPresent(RawDoorCategory.self, forKey: DynamicCodingKey("door"))
            surfaceType = .door
        } else {
            door = nil

            if container.contains(DynamicCodingKey("wall")) {
                surfaceType = .wall
            } else if container.contains(DynamicCodingKey("window")) {
                surfaceType = .window
            } else if container.contains(DynamicCodingKey("opening")) {
                surfaceType = .opening
            } else if container.contains(DynamicCodingKey("floor")) {
                surfaceType = .floor
            } else {
                surfaceType = .unknown
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)

        switch surfaceType {
        case .door:
            try container.encode(door ?? RawDoorCategory(isOpen: nil), forKey: DynamicCodingKey("door"))
        case .wall:
            try container.encode(EmptyJSONObject(), forKey: DynamicCodingKey("wall"))
        case .window:
            try container.encode(EmptyJSONObject(), forKey: DynamicCodingKey("window"))
        case .opening:
            try container.encode(EmptyJSONObject(), forKey: DynamicCodingKey("opening"))
        case .floor:
            try container.encode(EmptyJSONObject(), forKey: DynamicCodingKey("floor"))
        case .unknown:
            try container.encode(EmptyJSONObject(), forKey: DynamicCodingKey("unknown"))
        }
    }
}

struct RawDoorCategory: Codable {
    let isOpen: Bool?
}

struct RawConfidence: Codable {
    let level: ConfidenceLevel

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        if container.contains(DynamicCodingKey("high")) {
            level = .high
        } else if container.contains(DynamicCodingKey("medium")) {
            level = .medium
        } else if container.contains(DynamicCodingKey("low")) {
            level = .low
        } else {
            level = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(EmptyJSONObject(), forKey: DynamicCodingKey(level.rawValue))
    }

    var numericValue: Double {
        switch level {
        case .high:
            return 0.9
        case .medium:
            return 0.6
        case .low:
            return 0.3
        case .unknown:
            return 0.0
        }
    }
}

struct RawVector3: Codable {
    let x: Double
    let y: Double
    let z: Double

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        x = try container.decode(Double.self)
        y = try container.decode(Double.self)
        z = try container.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(z)
    }
}

struct SanitizedRoomPayload: Codable {
    let schemaVersion: String
    let units: String
    let room: SanitizedRoom
    let walls: [SanitizedWall]
    let openings: [SanitizedOpening]
    let metadata: SanitizedMetadata
}

struct SanitizedRoom: Codable {
    let id: String
    let type: String?
    let story: Int
    let boundingBox: SanitizedBoundingBox
    let floorPolygon: [[Double]]
    let ceilingHeight: Double
}

struct SanitizedBoundingBox: Codable {
    let width: Double
    let depth: Double
}

struct SanitizedWall: Codable {
    let id: String
    let width: Double
    let height: Double
    let center: [Double]
    let rotationRadians: Double
    let start: [Double]
    let end: [Double]
    let confidence: Double
}

struct SanitizedOpening: Codable {
    let id: String
    let type: String
    let wallID: String?
    let width: Double
    let height: Double
    let center: [Double]
    let rotationRadians: Double
    let bottomHeight: Double
    let isOpen: Bool?
    let confidence: Double
}

struct SanitizedMetadata: Codable {
    let sourceVersion: Int
    let generatedAt: String
}

enum SurfaceType: String {
    case wall
    case door
    case window
    case opening
    case floor
    case unknown
}

enum ConfidenceLevel: String {
    case high
    case medium
    case low
    case unknown
}

private struct Dimensions {
    let width: Double
    let height: Double
    let depth: Double
}

private struct Vector2D {
    let x: Double
    let z: Double
}

private struct EmptyJSONObject: Codable {}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}
