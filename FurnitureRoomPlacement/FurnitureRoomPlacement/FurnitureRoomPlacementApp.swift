//
//  FurnitureRoomPlacementApp.swift
//  FurnitureRoomPlacement
//
//  Created by Kelvin Jou on 4/24/26.
//

import SwiftUI

@main
struct FurnitureRoomPlacementApp: App {
    @StateObject private var userSession = UserSession.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(userSession)
        }
    }
}
