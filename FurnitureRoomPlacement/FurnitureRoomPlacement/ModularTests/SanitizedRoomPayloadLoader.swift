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
    return try RoomJSONSanitizer.sanitizedRoom(from: jsonData)
}
