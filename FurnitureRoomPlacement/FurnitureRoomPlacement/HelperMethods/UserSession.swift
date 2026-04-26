import Combine
import Foundation
import Security
import UIKit

final class UserSession: ObservableObject {
    static let shared = UserSession()

    @Published private(set) var userID: String

    private let keychainStore = KeychainUserIDStore()

    private init() {
        self.userID = keychainStore.loadUserID() ?? UserSession.makeSeededUserID()
        keychainStore.saveUserID(userID)
    }

    func refreshUserID() {
        if let storedUserID = keychainStore.loadUserID(), !storedUserID.isEmpty {
            userID = storedUserID
            return
        }

        let generatedUserID = UserSession.makeSeededUserID()
        keychainStore.saveUserID(generatedUserID)
        userID = generatedUserID
    }

    private static func makeSeededUserID() -> String {
        if let vendorID = UIDevice.current.identifierForVendor?.uuidString,
           !vendorID.isEmpty {
            return "ios-\(vendorID.lowercased())"
        }

        return "ios-\(UUID().uuidString.lowercased())"
    }
}

private struct KeychainUserIDStore {
    private let service = Bundle.main.bundleIdentifier ?? "FurnitureRoomPlacement"
    private let account = "globalUserID"

    func loadUserID() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let userID = String(data: data, encoding: .utf8),
              !userID.isEmpty else {
            return nil
        }

        return userID
    }

    func saveUserID(_ userID: String) {
        guard let data = userID.data(using: .utf8) else { return }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
