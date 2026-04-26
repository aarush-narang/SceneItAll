//
//  FurnitureRoomPlacementTests.swift
//  FurnitureRoomPlacementTests
//
//  Created by Kelvin Jou on 4/24/26.
//

import Testing
@testable import FurnitureRoomPlacement

struct FurnitureRoomPlacementTests {

    @Test func designPatchRequestEncodesBackendObjectShape() throws {
        let object = PlacedFurnitureObject(
            id: "instance-1",
            furniture: Furniture(
                savedSnapshot: SavedFurnitureSnapshot(
                    id: "chair-1",
                    name: "Chair",
                    familyKey: "chair-family",
                    dimensionsBbox: DimensionsBbox(widthM: 0.5, heightM: 0.8, depthM: 0.6),
                    files: SavedFurnitureFiles(usdzURL: "https://example.com/chair.usdz")
                )
            ),
            placement: FurniturePlacement(
                position: [1, 2, 3],
                eulerAngles: [0, 0.5, 0],
                scale: [1, 1, 1]
            ),
            addedAt: "2026-04-26T01:05:22.651Z",
            placedBy: "user",
            rationale: "Placed by the user."
        )
        let request = DesignPatchRequest(
            name: "Living Room",
            preferenceProfileID: "pref-1",
            addItems: [object],
            updateItems: [],
            deleteInstanceIDs: []
        )

        let data = try JSONEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let addItems = try #require(json["add_items"] as? [[String: Any]])
        let firstItem = try #require(addItems.first)
        let furniture = try #require(firstItem["furniture"] as? [String: Any])
        let files = try #require(furniture["files"] as? [String: Any])

        #expect(json["name"] as? String == "Living Room")
        #expect(json["preference_profile_id"] as? String == "pref-1")
        #expect(json["update_items"] as? [Any] == [])
        #expect(json["delete_instance_ids"] as? [Any] == [])
        #expect(firstItem["placed_by"] as? String == "user")
        #expect(firstItem["rationale"] as? String == "Placed by the user.")
        #expect(furniture["_id"] as? String == "chair-1")
        #expect(furniture["family_key"] as? String == "chair-family")
        #expect(files["usdz_url"] as? String == "https://example.com/chair.usdz")
    }

}
