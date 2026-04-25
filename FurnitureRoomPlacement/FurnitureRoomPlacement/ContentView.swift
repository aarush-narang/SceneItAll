//
//  ContentView.swift
//  FurnitureRoomPlacement
//
//  Created by Kelvin Jou on 4/24/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {

//        OnboardingView()
        Button(action: {
            do {
                let sanitizedJSON = try loadSanitizedRoomPayload(fromJSONFilePath: "/Users/kelvinjou/Documents/GitHub/LAHacks2026/FurnitureRoomPlacement/FurnitureRoomPlacement/JSON_testfiles/southwest_corner.json")
                let jsonData = try RoomJSONSanitizer.sanitizedJSONData(from: sanitizedJSON)

                let byteCountFormatter = ByteCountFormatter()
                byteCountFormatter.countStyle = .file
                print("sanitizedJson size: \(byteCountFormatter.string(fromByteCount: Int64(jsonData.count)))")
            } catch {
                print(error.localizedDescription)
            }
        }) {
            Text("Sanitize")
        }
    }
}
