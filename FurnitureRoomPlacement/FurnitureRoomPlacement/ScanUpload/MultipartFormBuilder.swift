//
//  MultipartFormBuilder.swift
//  FurnitureRoomPlacement
//
//  Tiny multipart/form-data builder. Produces the body and Content-Type header
//  expected by the backend's `POST /v1/scans` endpoint.
//

import Foundation

struct MultipartFormBuilder {
    let boundary: String
    private(set) var body = Data()

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    /// Append a JSON / text part with explicit content type.
    mutating func appendField(name: String, data: Data, contentType: String) {
        body.append(boundaryHeader())
        body.append(disposition(name: name, filename: nil))
        body.append("Content-Type: \(contentType)\r\n\r\n".utf8Data)
        body.append(data)
        body.append("\r\n".utf8Data)
    }

    /// Append a binary file part (used for `frame_<id>` JPEGs).
    mutating func appendFile(name: String, filename: String, data: Data, contentType: String) {
        body.append(boundaryHeader())
        body.append(disposition(name: name, filename: filename))
        body.append("Content-Type: \(contentType)\r\n\r\n".utf8Data)
        body.append(data)
        body.append("\r\n".utf8Data)
    }

    /// Call once, after all fields are appended.
    mutating func finalize() -> Data {
        body.append("--\(boundary)--\r\n".utf8Data)
        return body
    }

    // MARK: - helpers

    private func boundaryHeader() -> Data { "--\(boundary)\r\n".utf8Data }

    private func disposition(name: String, filename: String?) -> Data {
        if let filename {
            return "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8Data
        }
        return "Content-Disposition: form-data; name=\"\(name)\"\r\n".utf8Data
    }
}

private extension String {
    var utf8Data: Data { data(using: .utf8) ?? Data() }
}
