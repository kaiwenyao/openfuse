import Foundation

public struct TraktConfig: Sendable {
    public var baseURL: URL
    public var clientID: String
    public var clientSecret: String

    public init(baseURL: URL, clientID: String, clientSecret: String = "") {
        self.baseURL = baseURL
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

public struct TraktDeviceCode: Codable, Sendable {
    public var deviceCode: String
    public var userCode: String
    public var verificationURL: String
    public var expiresIn: Int
    public var interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURL = "verification_url"
        case expiresIn = "expires_in"
        case interval
    }
}

public struct TraktToken: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

public struct TraktIDs: Codable, Hashable, Sendable {
    public var trakt: Int?
    public var slug: String?
    public var imdb: String?
    public var tmdb: Int?
}

public enum TraktError: LocalizedError, Sendable {
    case unauthorized
    case http(Int)
    case invalidResponse(String)
    case pending

    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "Trakt 未授权"
        case .http(let code): return "Trakt 返回 HTTP \(code)"
        case .invalidResponse(let message): return "Trakt 响应错误：\(message)"
        case .pending: return "Trakt 设备码尚未确认"
        }
    }
}

public actor TraktClient {
    public let config: TraktConfig
    private var token: String?
    private let session: URLSession

    public init(config: TraktConfig, token: String? = nil) {
        self.config = config
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: configuration)
    }

    public func setToken(_ token: String?) { self.token = token }

    public func deviceCode() async throws -> TraktDeviceCode {
        var request = try makeRequest(path: "oauth/device/code", method: "POST", authorized: false)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": config.clientID])
        let (data, status) = try await send(request)
        guard (200..<300).contains(status) else { throw TraktError.http(status) }
        return try JSONDecoder().decode(TraktDeviceCode.self, from: data)
    }

    public func pollToken(deviceCode: String) async throws -> TraktToken {
        var request = try makeRequest(path: "oauth/device/token", method: "POST", authorized: false)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": deviceCode,
            "client_id": config.clientID,
            "client_secret": config.clientSecret,
        ])
        let (data, status) = try await send(request)
        if status == 400 { throw TraktError.pending }
        guard (200..<300).contains(status) else { throw TraktError.http(status) }
        let decoded = try JSONDecoder().decode(TraktToken.self, from: data)
        token = decoded.accessToken
        return decoded
    }

    public func search(title: String, type: String = "movie") async throws -> (TraktIDs, String)? {
        guard token != nil else { throw TraktError.unauthorized }
        guard var components = URLComponents(
            url: config.baseURL.appendingPathComponent("search/\(type)"),
            resolvingAgainstBaseURL: false
        ) else { throw TraktError.invalidResponse("search URL") }
        components.queryItems = [URLQueryItem(name: "query", value: title)]
        guard let url = components.url else { throw TraktError.invalidResponse("search URL") }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(config.clientID, forHTTPHeaderField: "trakt-api-key")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, status) = try await send(request)
        guard (200..<300).contains(status) else { throw TraktError.http(status) }
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first else { return nil }
        let key = type == "show" ? "show" : "movie"
        guard let object = first[key] as? [String: Any],
              let idsObject = object["ids"] as? [String: Any] else { return nil }
        let ids = TraktIDs(
            trakt: idsObject["trakt"] as? Int,
            slug: idsObject["slug"] as? String,
            imdb: idsObject["imdb"] as? String,
            tmdb: idsObject["tmdb"] as? Int
        )
        return (ids, key)
    }

    public func scrobble(action: String, ids: TraktIDs, type: String, progress: Double) async throws {
        guard token != nil else { throw TraktError.unauthorized }
        var request = try makeRequest(path: "scrobble/\(action)", method: "POST", authorized: true)
        let key = type == "show" ? "show" : "movie"
        let idsJSON: [String: Any] = [
            "trakt": ids.trakt as Any,
            "imdb": ids.imdb as Any,
            "tmdb": ids.tmdb as Any,
        ].compactMapValues { $0 is NSNull ? nil : $0 }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            key: ["ids": idsJSON],
            "progress": min(100, max(0, progress)),
        ])
        let (_, status) = try await send(request)
        guard (200..<300).contains(status) else { throw TraktError.http(status) }
    }

    private func makeRequest(path: String, method: String, authorized: Bool) throws -> URLRequest {
        var request = URLRequest(url: config.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(config.clientID, forHTTPHeaderField: "trakt-api-key")
        if authorized, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TraktError.invalidResponse("non-HTTP")
        }
        return (data, http.statusCode)
    }
}
