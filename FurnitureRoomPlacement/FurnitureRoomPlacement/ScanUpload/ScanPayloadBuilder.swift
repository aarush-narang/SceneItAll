//
//  ScanPayloadBuilder.swift
//  FurnitureRoomPlacement
//
//  Turns a `CapturedRoom` into the `scan_json` body the backend's
//  `POST /v1/scans` endpoint expects (see `app/models/scan.py:ScanPayload`).
//

import Foundation
import RoomPlan
import simd

/// Conversion helpers that produce the multipart parts:
///   * `scan_json`        — room geometry + detected furniture + categories
///   * `frames_metadata`  — array of FrameMetadata (one entry per CapturedFrame)
enum ScanPayloadBuilder {

    /// Encode the scan body. `objects` from RoomPlan are mapped to the backend's
    /// `DetectedObject` shape (column-major flat-16 transform).
    static func encodeScanJSON(_ room: CapturedRoom) throws -> Data {
        let payload = ScanPayloadJSON(
            identifier: room.identifier.uuidString,
            story: storyValue(of: room),
            version: versionValue(of: room),
            walls: surfaceJSON(room.walls),
            doors: surfaceJSON(room.doors),
            windows: surfaceJSON(room.windows),
            openings: surfaceJSON(room.openings),
            floors: floorJSON(room),
            sections: sectionJSON(room),
            detectedObjects: room.objects.map(detectedObjectJSON(from:))
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    /// Encode the frame-metadata sidecar. Frame ids must match the multipart
    /// part keys (`frame_<id>`), which `FrameSampler` already guarantees.
    static func encodeFramesMetadata(_ frames: [CapturedFrame]) throws -> Data {
        let metadata = frames.map { f -> FrameMetadataJSON in
            FrameMetadataJSON(
                frameId: f.frameId,
                timestamp: f.timestamp,
                imageFilename: "\(f.frameId).jpg",
                cameraTransform: rowMajor(f.cameraTransform),
                cameraIntrinsics: rowMajor(f.cameraIntrinsics),
                imageWidth: f.imageWidth,
                imageHeight: f.imageHeight
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(metadata)
    }

    // MARK: - JSON shapes (private; mirror `app/models/scan.py`)

    private struct ScanPayloadJSON: Encodable {
        let identifier: String
        let story: Int
        let version: Int
        let walls: [SurfaceJSON]
        let doors: [SurfaceJSON]
        let windows: [SurfaceJSON]
        let openings: [SurfaceJSON]
        let floors: [SurfaceJSON]
        let sections: [SectionJSON]
        let detectedObjects: [DetectedObjectJSON]
    }

    private struct SurfaceJSON: Encodable {
        let identifier: String
        let category: String
        let dimensions: [Float]
        let transform: [Float]   // column-major flat-16
        let confidence: String
    }

    private struct SectionJSON: Encodable {
        let identifier: String
        let label: String
        let center: [Float]
    }

    private struct DetectedObjectJSON: Encodable {
        let identifier: String
        let category: String
        let dimensions: [Float]
        let transform: [Float]   // column-major flat-16
        let confidence: String
    }

    private struct FrameMetadataJSON: Encodable {
        let frameId: String
        let timestamp: TimeInterval
        let imageFilename: String
        let cameraTransform: [[Float]]
        let cameraIntrinsics: [[Float]]
        let imageWidth: Int
        let imageHeight: Int

        enum CodingKeys: String, CodingKey {
            case frameId = "frame_id"
            case timestamp
            case imageFilename = "image_filename"
            case cameraTransform = "camera_transform"
            case cameraIntrinsics = "camera_intrinsics"
            case imageWidth = "image_width"
            case imageHeight = "image_height"
        }
    }

    // MARK: - mappers

    private static func surfaceJSON(_ surfaces: [CapturedRoom.Surface]) -> [SurfaceJSON] {
        surfaces.map { s in
            SurfaceJSON(
                identifier: s.identifier.uuidString,
                category: surfaceCategoryString(s.category),
                dimensions: [s.dimensions.x, s.dimensions.y, s.dimensions.z],
                transform: columnMajorFlat16(s.transform),
                confidence: confidenceString(s.confidence)
            )
        }
    }

    private static func detectedObjectJSON(from o: CapturedRoom.Object) -> DetectedObjectJSON {
        DetectedObjectJSON(
            identifier: o.identifier.uuidString,
            category: objectCategoryString(o.category),
            dimensions: [o.dimensions.x, o.dimensions.y, o.dimensions.z],
            transform: columnMajorFlat16(o.transform),
            confidence: confidenceString(o.confidence)
        )
    }

    private static func floorJSON(_ room: CapturedRoom) -> [SurfaceJSON] {
        if #available(iOS 17.0, *) {
            return surfaceJSON(room.floors)
        }
        return []
    }

    private static func sectionJSON(_ room: CapturedRoom) -> [SectionJSON] {
        if #available(iOS 17.0, *) {
            return room.sections.map { s in
                SectionJSON(
                    identifier: UUID().uuidString,
                    label: String(describing: s.label),
                    center: [s.center.x, s.center.y, s.center.z]
                )
            }
        }
        return []
    }

    private static func storyValue(of room: CapturedRoom) -> Int {
        if #available(iOS 17.0, *) {
            return room.story
        }
        return 0
    }

    private static func versionValue(of room: CapturedRoom) -> Int {
        if #available(iOS 17.0, *) {
            return room.version
        }
        return 1
    }

    // MARK: - matrix layout

    /// simd_float4x4 is stored column-major; emit `[col0.x, col0.y, col0.z, col0.w, col1.x, ...]`
    /// to match the backend's `DetectedObject.transform: list[float]` (16-float column-major flat).
    private static func columnMajorFlat16(_ m: simd_float4x4) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(16)
        for col in 0..<4 {
            let v = m[col]
            out.append(v.x); out.append(v.y); out.append(v.z); out.append(v.w)
        }
        return out
    }

    /// Row-major nested 4x4 — backend reads `camera_transform` as a list of rows.
    private static func rowMajor(_ m: simd_float4x4) -> [[Float]] {
        return (0..<4).map { row in
            [m[0][row], m[1][row], m[2][row], m[3][row]]
        }
    }

    /// Row-major nested 3x3.
    private static func rowMajor(_ k: simd_float3x3) -> [[Float]] {
        return (0..<3).map { row in
            [k[0][row], k[1][row], k[2][row]]
        }
    }

    // MARK: - enum → string

    private static func objectCategoryString(_ c: CapturedRoom.Object.Category) -> String {
        switch c {
        case .bathtub: return "bathtub"
        case .bed: return "bed"
        case .chair: return "chair"
        case .dishwasher: return "dishwasher"
        case .fireplace: return "fireplace"
        case .oven: return "oven"
        case .refrigerator: return "refrigerator"
        case .sink: return "sink"
        case .sofa: return "sofa"
        case .stairs: return "stairs"
        case .storage: return "storage"
        case .stove: return "stove"
        case .table: return "table"
        case .television: return "television"
        case .toilet: return "toilet"
        case .washerDryer: return "washer_dryer"
        @unknown default: return "unknown"
        }
    }

    private static func surfaceCategoryString(_ c: CapturedRoom.Surface.Category) -> String {
        switch c {
        case .wall: return "wall"
        case .opening: return "opening"
        case .window: return "window"
        case .door: return "door"
        case .floor: return "floor"
        @unknown default: return "unknown"
        }
    }

    private static func confidenceString(_ c: CapturedRoom.Confidence) -> String {
        switch c {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        @unknown default: return "high"
        }
    }
}
