import Foundation

final class FurnitureAPIClient {
    static let shared = FurnitureAPIClient()

    private static let userDefaults = UserDefaults.standard
    private static let generatedUserIDKey = "FurnitureGeneratedUserID"

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        baseURL: URL? = nil,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.baseURL = baseURL ?? Self.defaultBaseURL
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
    }

    func searchFurniture(query: String, limit: Int = 10) async throws -> [Furniture] {
        var components = URLComponents(
            url: baseURL.appending(path: "/furniture/search"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components?.url else {
            throw FurnitureAPIClientError.invalidRequest
        }

        return try await sendRequest(url: url)
    }

    func fetchDesignObjects(designID: String? = nil) async throws -> [PlacedFurnitureObject] {
        let resolvedDesignID = designID ?? Self.defaultDesignID()
        let url = baseURL
            .appending(path: "/designs")
            .appending(path: resolvedDesignID)
            .appending(path: "objects")

        return try await sendRequest(url: url)
    }

    func addObjectToDesign(
        _ object: PlacedFurnitureObject,
        designID: String? = nil,
        designName: String,
        preferenceProfileID: String? = nil
    ) async throws {
        let resolvedDesignID = designID ?? Self.defaultDesignID()
        let payload = DesignPatchRequest(
            name: designName,
            preferenceProfileID: preferenceProfileID ?? Self.defaultPreferenceProfileID(),
            addItems: [object],
            updateItems: [],
            deleteInstanceIDs: []
        )

        let url = baseURL
            .appending(path: "/designs")
            .appending(path: resolvedDesignID)
        try await sendRequest(url: url, method: "PATCH", body: payload)
    }

    func updateObjectsInDesign(
        _ objects: [PlacedFurnitureObject],
        designID: String? = nil,
        designName: String,
        preferenceProfileID: String? = nil
    ) async throws {
        let resolvedDesignID = designID ?? Self.defaultDesignID()
        let payload = DesignPatchRequest(
            name: designName,
            preferenceProfileID: preferenceProfileID ?? Self.defaultPreferenceProfileID(),
            addItems: [],
            updateItems: objects,
            deleteInstanceIDs: []
        )

        let url = baseURL
            .appending(path: "/designs")
            .appending(path: resolvedDesignID)
        try await sendRequest(url: url, method: "PATCH", body: payload)
    }

    func agentChat(
        message: String,
        sessionID: String?,
        designID: String? = nil,
        userID: String? = nil
    ) async throws -> AgentChatResponse {
        let payload = AgentChatRequest(
            userID: userID ?? Self.defaultUserID(),
            designID: designID ?? Self.defaultDesignID(),
            message: message,
            sessionID: sessionID ?? ""
        )
        let url = baseURL.appending(path: "/agent/chat")
        return try await sendRequest(url: url, method: "POST", body: payload)
    }

    private func sendRequest<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw FurnitureAPIClientError.transportError(url: url, underlying: error)
        }

        try validate(response: response, data: data)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw FurnitureAPIClientError.decodingError(decodeErrorMessage(from: error))
        }
    }

    private func sendRequest<T: Encodable>(url: URL, method: String, body: T) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw FurnitureAPIClientError.encodingError(error.localizedDescription)
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw FurnitureAPIClientError.transportError(url: url, underlying: error)
        }

        try validate(response: response, data: data)
    }

    private func sendRequest<TResponse: Decodable, TBody: Encodable>(
        url: URL,
        method: String,
        body: TBody
    ) async throws -> TResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw FurnitureAPIClientError.encodingError(error.localizedDescription)
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw FurnitureAPIClientError.transportError(url: url, underlying: error)
        }

        try validate(response: response, data: data)
        do {
            return try decoder.decode(TResponse.self, from: data)
        } catch {
            throw FurnitureAPIClientError.decodingError(decodeErrorMessage(from: error))
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FurnitureAPIClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw FurnitureAPIClientError.fromHTTPError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    private static var defaultBaseURL: URL {
        if
            let configuredBaseURL = Bundle.main.object(forInfoDictionaryKey: "FurnitureAPIBaseURL") as? String,
            let url = URL(string: configuredBaseURL),
            url.scheme != nil,
            url.host != nil
        {
            return url
        }

        return URL(string: "http://127.0.0.1:8000")!
    }

    private static func defaultDesignID() -> String {
        if let configuredDesignID = Bundle.main.object(forInfoDictionaryKey: "FurnitureDesignID") as? String,
           !configuredDesignID.isEmpty {
            return configuredDesignID
        }

        return "90e1a836-bdeb-4862-bc82-3c8f21f18e0c"
    }

    private static func defaultPreferenceProfileID() -> String {
        (Bundle.main.object(forInfoDictionaryKey: "FurniturePreferenceProfileID") as? String) ?? ""
    }

    private static func defaultUserID() -> String {
        if let configuredUserID = Bundle.main.object(forInfoDictionaryKey: "FurnitureUserID") as? String,
           !configuredUserID.isEmpty {
            return configuredUserID
        }

        if let persistedUserID = userDefaults.string(forKey: generatedUserIDKey),
           !persistedUserID.isEmpty {
            return persistedUserID
        }

        let generatedUserID = UUID().uuidString
        userDefaults.set(generatedUserID, forKey: generatedUserIDKey)
        return generatedUserID
    }
}

enum FurnitureAPIClientError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case transportError(url: URL, underlying: URLError)
    case decodingError(String)
    case encodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "The furniture search request could not be created."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .httpError(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Request failed with status \(statusCode): \(message)"
            }
            return "Request failed with status \(statusCode)."
        case .transportError(let url, let underlying):
            switch underlying.code {
            case .notConnectedToInternet:
                return """
                The app could not reach \(url.absoluteString).
                If you are on a physical device, point FurnitureAPIBaseURL at a server your phone can actually reach, such as your Mac's LAN IP, and make sure the backend is listening on 0.0.0.0:8000.
                """
            case .cannotConnectToHost, .cannotFindHost, .timedOut:
                return """
                The app could not connect to \(url.host() ?? url.absoluteString).
                Verify the backend is running, reachable from the device, and bound to 0.0.0.0:8000 instead of only 127.0.0.1:8000.
                """
            default:
                return "Network request to \(url.absoluteString) failed: \(underlying.localizedDescription)"
            }
        case .decodingError(let message):
            return "The server returned data in an unexpected format: \(message)"
        case .encodingError(let message):
            return "The app could not encode the request payload: \(message)"
        }
    }
}

struct DesignPatchRequest: Encodable {
    let name: String
    let preferenceProfileID: String
    let addItems: [PlacedFurnitureObject]
    let updateItems: [PlacedFurnitureObject]
    let deleteInstanceIDs: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case preferenceProfileID = "preference_profile_id"
        case addItems = "add_items"
        case updateItems = "update_items"
        case deleteInstanceIDs = "delete_instance_ids"
    }
}

struct AgentChatRequest: Encodable {
    let userID: String
    let designID: String
    let message: String
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case designID = "design_id"
        case message
        case sessionID = "session_id"
    }
}

struct AgentChatResponse: Decodable {
    let sessionID: String
    let assistantText: String
    let placements: [AgentChatPlacement]
    let toolCalls: [AgentChatToolCall]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case assistantText = "assistant_text"
        case placements
        case misspelledPlacements = "placemnets"
        case toolCalls = "tool_calls"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
        assistantText = try container.decodeIfPresent(String.self, forKey: .assistantText) ?? ""
        let decodedPlacements = try container.decodeIfPresent([AgentChatPlacement].self, forKey: .placements)
        let decodedMisspelledPlacements = try container.decodeIfPresent(
            [AgentChatPlacement].self,
            forKey: .misspelledPlacements
        )
        placements = decodedPlacements ?? decodedMisspelledPlacements ?? []
        toolCalls = try container.decodeIfPresent([AgentChatToolCall].self, forKey: .toolCalls) ?? []
    }
}

struct AgentChatPlacement: Decodable {
    let objectID: String
    let placement: FurniturePlacement
    let rationale: String?

    enum CodingKeys: String, CodingKey {
        case objectID = "object_id"
        case instanceID = "instance_id"
        case id
        case placement
        case position
        case eulerAngles
        case scale
        case rationale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        objectID = try container.decodeIfPresent(String.self, forKey: .objectID)
            ?? container.decodeIfPresent(String.self, forKey: .instanceID)
            ?? container.decode(String.self, forKey: .id)

        if let nestedPlacement = try container.decodeIfPresent(FurniturePlacement.self, forKey: .placement) {
            placement = nestedPlacement
        } else {
            placement = FurniturePlacement(
                position: try container.decodeIfPresent([Float].self, forKey: .position) ?? [],
                eulerAngles: try container.decodeIfPresent([Float].self, forKey: .eulerAngles) ?? [],
                scale: try container.decodeIfPresent([Float].self, forKey: .scale) ?? []
            )
        }

        rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
    }
}

struct AgentChatToolCall: Decodable {}

extension FurnitureAPIClient {
    private func decodeErrorMessage(from error: Error) -> String {
        switch error {
        case let DecodingError.keyNotFound(key, context):
            return "Missing key '\(key.stringValue)' at \(codingPathDescription(context.codingPath))."
        case let DecodingError.valueNotFound(_, context):
            return "Missing value at \(codingPathDescription(context.codingPath))."
        case let DecodingError.typeMismatch(_, context):
            return "Type mismatch at \(codingPathDescription(context.codingPath))."
        case let DecodingError.dataCorrupted(context):
            return "Corrupted data near \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        default:
            return error.localizedDescription
        }
    }

    private func codingPathDescription(_ codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else {
            return "the root response"
        }

        return codingPath.map(\.stringValue).joined(separator: ".")
    }
}

extension FurnitureAPIClientError {
    static func fromHTTPError(statusCode: Int, data: Data?) -> FurnitureAPIClientError {
        if statusCode == 422,
           let data,
           let message = validationErrorMessage(from: data) {
            return .httpError(statusCode: statusCode, message: message)
        }

        let message = data.flatMap { String(data: $0, encoding: .utf8) }
        return .httpError(statusCode: statusCode, message: message)
    }
    
    private static func validationErrorMessage(from data: Data) -> String? {
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let detail = jsonObject["detail"] as? [[String: Any]]
        else {
            return nil
        }

        let messages = detail.compactMap { entry -> String? in
            let location = (entry["loc"] as? [Any])?
                .map { String(describing: $0) }
                .joined(separator: ".") ?? ""
            let message = entry["msg"] as? String ?? ""

            guard !message.isEmpty else {
                return nil
            }

            return location.isEmpty ? message : "\(location): \(message)"
        }

        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }
}
