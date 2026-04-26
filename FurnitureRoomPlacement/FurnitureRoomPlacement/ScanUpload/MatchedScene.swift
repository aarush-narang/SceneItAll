//
//  MatchedScene.swift
//  FurnitureRoomPlacement
//
//  Codable types that mirror the backend's `ScanResponse`
//  (see `app/models/scan.py` and the response schema in the implementation plan).
//

import Foundation

struct MatchedScene: Decodable {
    let scanId: String
    let room: AnyCodable                // pass-through; existing scene builder will keep using BarebonesCapturedRoom JSON instead
    let objects: [MatchedObject]

    enum CodingKeys: String, CodingKey {
        case scanId = "scan_id"
        case room
        case objects
    }
}

struct MatchedObject: Decodable {
    let detectedId: String
    let matchedProductId: String?
    let matchedProductName: String?
    let matchedUSDZURL: String?
    let refinedCategory: String
    let transform: ObjectTransform
    let originalBBox: OriginalBBox

    enum CodingKeys: String, CodingKey {
        case detectedId = "detected_id"
        case matchedProductId = "matched_product_id"
        case matchedProductName = "matched_product_name"
        case matchedUSDZURL = "matched_usdz_url"
        case refinedCategory = "refined_category"
        case transform
        case originalBBox = "original_bbox"
    }

    /// True when the matcher returned a real catalog item; false → render a white-box placeholder.
    var isMatched: Bool { matchedProductId != nil && matchedUSDZURL != nil }
}

struct ObjectTransform: Decodable {
    let position: [Float]        // (x, y, z) — meters, world space
    let rotationEuler: [Float]   // (rx, ry, rz) — radians; only y is non-zero in v1
    let scale: [Float]           // always (1, 1, 1) in v1

    enum CodingKeys: String, CodingKey {
        case position
        case rotationEuler = "rotation_euler"
        case scale
    }
}

struct OriginalBBox: Decodable {
    let dimensions: [Float]      // (width, height, depth) meters
    let transform: [Float]       // 16 floats, column-major
}

/// Minimal type-erased decoder so we can pass through the room blob untouched.
/// We don't need to introspect it on iOS (the existing scene builder reads
/// `BarebonesCapturedRoom` JSON which the backend returns verbatim).
struct AnyCodable: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode([String: AnyCodable].self) { value = v.mapValues { $0.value }; return }
        if let v = try? container.decode([AnyCodable].self) { value = v.map { $0.value }; return }
        if let v = try? container.decode(Bool.self) { value = v; return }
        if let v = try? container.decode(Int.self) { value = v; return }
        if let v = try? container.decode(Double.self) { value = v; return }
        if let v = try? container.decode(String.self) { value = v; return }
        if container.decodeNil() { value = NSNull(); return }
        throw DecodingError.typeMismatch(
            AnyCodable.self,
            .init(codingPath: container.codingPath, debugDescription: "Unsupported JSON value")
        )
    }
}
