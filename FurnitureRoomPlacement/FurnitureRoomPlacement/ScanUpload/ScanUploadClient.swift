//
//  ScanUploadClient.swift
//  FurnitureRoomPlacement
//
//  POSTs a CapturedRoom + sampled ARKit frames to the backend matcher and
//  returns the enriched scene response.
//

import Foundation
import RoomPlan

enum ScanUploadError: LocalizedError {
    case invalidBaseURL
    case requestFailed(URLError)
    case nonHTTPResponse
    case server(status: Int, body: String)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Backend URL is invalid."
        case .requestFailed(let err):
            return "Network request failed: \(err.localizedDescription)"
        case .nonHTTPResponse:
            return "Backend returned a non-HTTP response."
        case .server(let status, let body):
            return "Backend error \(status): \(body)"
        case .decodingFailed(let err):
            return "Could not decode backend response: \(err.localizedDescription)"
        }
    }
}

final class ScanUploadClient {
    let baseURL: URL
    let session: URLSession

    /// `baseURL` should point at the FastAPI host (e.g. `http://192.168.1.10:8000`).
    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Convenience initializer that throws when the string isn't a valid URL.
    convenience init(baseURLString: String, session: URLSession = .shared) throws {
        guard let url = URL(string: baseURLString) else { throw ScanUploadError.invalidBaseURL }
        self.init(baseURL: url, session: session)
    }

    /// Bundle the scan + frames into a multipart POST and return the matcher's response.
    ///
    /// - Parameter objectFrames: Per-object burst frames keyed by RoomPlan object UUID.
    ///   These are merged with `frames` (deduped by frameId) and their IDs are embedded
    ///   in each `DetectedObject` so the backend can skip its full-pool frame search.
    func upload(
        room: CapturedRoom,
        frames: [CapturedFrame],
        objectFrames: [String: [CapturedFrame]] = [:]
    ) async throws -> MatchedScene {
        // Build the objectFrameIds map (objectId → [frameId]) for the scan payload.
        var objectFrameIds: [String: [String]] = [:]
        for (objectId, objFrames) in objectFrames where !objFrames.isEmpty {
            objectFrameIds[objectId] = objFrames.map(\.frameId)
        }

        // Merge general + object frames, deduplicating by frameId.
        var allFramesById: [String: CapturedFrame] = Dictionary(
            uniqueKeysWithValues: frames.map { ($0.frameId, $0) }
        )
        for objFrames in objectFrames.values {
            for f in objFrames { allFramesById[f.frameId] = f }
        }
        let allFrames = Array(allFramesById.values)

        let scanJSON = try ScanPayloadBuilder.encodeScanJSON(room, objectFrameIds: objectFrameIds)
        let framesMetadata = try ScanPayloadBuilder.encodeFramesMetadata(allFrames)

        var form = MultipartFormBuilder()
        form.appendField(name: "scan_json", data: scanJSON, contentType: "application/json")
        form.appendField(name: "frames_metadata", data: framesMetadata, contentType: "application/json")
        for frame in allFrames {
            form.appendFile(
                name: frame.frameId,
                filename: "\(frame.frameId).jpg",
                data: frame.jpegData,
                contentType: "image/jpeg"
            )
        }
        let body = form.finalize()

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/scans"))
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: body)
        } catch let urlError as URLError {
            throw ScanUploadError.requestFailed(urlError)
        }

        guard let http = response as? HTTPURLResponse else { throw ScanUploadError.nonHTTPResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw ScanUploadError.server(status: http.statusCode, body: body)
        }

        do {
            return try JSONDecoder().decode(MatchedScene.self, from: data)
        } catch {
            throw ScanUploadError.decodingFailed(error)
        }
    }
}
