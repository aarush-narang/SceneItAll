//
//  SanitizedRoomPayloadLoader.swift
//  FurnitureRoomPlacement
//
//  Created by Codex on 4/24/26.
//

import Foundation

func loadSanitizedRoomPayload(fromJSONFilePath filePath: String) throws -> SanitizedRoomPayload {
    let fileURL = URL(fileURLWithPath: filePath)
    let jsonData = try Data(contentsOf: fileURL)
    let sanitizedRoom = try RoomJSONSanitizer.sanitizedRoom(from: jsonData)
    let sanitizedJSONData = try RoomJSONSanitizer.sanitizedJSONData(from: sanitizedRoom)

    let outputDirectoryURL = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("output", isDirectory: true)
    let outputFileURL = outputDirectoryURL
        .appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent + "_sanitized")
        .appendingPathExtension("json")

    try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)
    try sanitizedJSONData.write(to: outputFileURL, options: .atomic)

    return sanitizedRoom
}
