import Foundation
import CryptoKit

public struct JellyfinSource: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var baseURL: URL
    public var username: String
    public var userID: String?
    public var serverID: String?
    /// "jellyfin" (default) or "emby". Emby exposes the same HTTP API.
    public var serverKind: String?

    public init(
        id: String? = nil,
        name: String,
        baseURL: URL,
        username: String,
        userID: String? = nil,
        serverID: String? = nil,
        serverKind: String? = nil
    ) {
        self.id = id ?? Self.makeID(baseURL: baseURL, username: username, serverKind: serverKind)
        self.name = name
        self.baseURL = baseURL
        self.username = username
        self.userID = userID
        self.serverID = serverID
        self.serverKind = serverKind
    }

    public var kind: String { serverKind ?? "jellyfin" }

    public static func makeID(baseURL: URL, username: String, serverKind: String? = nil) -> String {
        let material = "\(serverKind ?? "jellyfin")|\(username)@\(baseURL.absoluteString)"
        let digest = SHA256.hash(data: Data(material.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    public var normalizedBaseURL: URL {
        var value = baseURL.absoluteString
        if !value.hasSuffix("/") { value += "/" }
        return URL(string: value) ?? baseURL
    }

    public var deviceID: String { "openfuse-" + id }
}

public struct JellyfinSession: Codable, Sendable {
    public var accessToken: String
    public var userID: String
    public var serverID: String?
    public var userName: String?
}

public struct JellyfinUserData: Codable, Hashable, Sendable {
    public var playbackPositionTicks: Int64?
    public var played: Bool?
    public var playCount: Int?

    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case played = "Played"
        case playCount = "PlayCount"
    }
}

public struct JellyfinItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var itemType: String?
    public var collectionType: String?
    public var parentID: String?
    public var seriesID: String?
    public var seriesName: String?
    public var seasonID: String?
    public var indexNumber: Int?
    public var parentIndexNumber: Int?
    public var productionYear: Int?
    public var overview: String?
    public var runTimeTicks: Int64?
    public var imageTags: [String: String]?
    public var userData: JellyfinUserData?
    public var dateCreated: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case itemType = "Type"
        case collectionType = "CollectionType"
        case parentID = "ParentId"
        case seriesID = "SeriesId"
        case seriesName = "SeriesName"
        case seasonID = "SeasonId"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case productionYear = "ProductionYear"
        case overview = "Overview"
        case runTimeTicks = "RunTimeTicks"
        case imageTags = "ImageTags"
        case userData = "UserData"
        case dateCreated = "DateCreated"
    }

    public var isPlayable: Bool {
        ["Movie", "Episode", "Video"].contains(itemType ?? "")
    }

    public var isFolder: Bool {
        ["Series", "Season", "Folder", "CollectionFolder", "BoxSet"].contains(itemType ?? "")
    }

    public var primaryImageTag: String? { imageTags?["Primary"] }

    public var episodeLabel: String? {
        guard itemType == "Episode", let index = indexNumber else { return nil }
        let season = parentIndexNumber ?? 1
        return String(format: "S%02dE%02d", season, index)
    }

    public var subtitle: String {
        switch itemType {
        case "Episode":
            return [episodeLabel, seriesName].compactMap { $0 }.joined(separator: " · ")
        case "Movie":
            return ["电影", productionYear.map(String.init)].compactMap { $0 }.joined(separator: " · ")
        case "Series":
            return "电视剧"
        case "Season":
            return ["第 \(indexNumber ?? 1) 季", seriesName].compactMap { $0 }.joined(separator: " · ")
        case "CollectionFolder":
            switch collectionType {
            case "movies": return "电影库"
            case "tvshows": return "电视剧库"
            default: return "媒体库"
            }
        default:
            return itemType ?? "条目"
        }
    }
}

public struct JellyfinMediaStream: Codable, Hashable, Sendable {
    public var type: String
    public var index: Int
    public var codec: String?
    public var language: String?
    public var displayTitle: String?
    public var channels: Int?
    public var isDefault: Bool?
    public var isForced: Bool?
    public var isExternal: Bool?
    public var deliveryURL: String?
    public var width: Int?
    public var height: Int?
    public var profile: String?

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case index = "Index"
        case codec = "Codec"
        case language = "Language"
        case displayTitle = "DisplayTitle"
        case channels = "Channels"
        case isDefault = "IsDefault"
        case isForced = "IsForced"
        case isExternal = "IsExternal"
        case deliveryURL = "DeliveryUrl"
        case width = "Width"
        case height = "Height"
        case profile = "Profile"
    }
}

public struct JellyfinMediaSource: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var container: String?
    public var runTimeTicks: Int64?
    public var supportsDirectPlay: Bool?
    public var supportsDirectStream: Bool?
    public var directStreamURL: String?
    public var transcodingURL: String?
    public var mediaStreams: [JellyfinMediaStream]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case container = "Container"
        case runTimeTicks = "RunTimeTicks"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case directStreamURL = "DirectStreamUrl"
        case transcodingURL = "TranscodingUrl"
        case mediaStreams = "MediaStreams"
    }
}

public struct JellyfinPlaybackInfo: Codable, Sendable {
    public var playSessionID: String?
    public var mediaSources: [JellyfinMediaSource]

    enum CodingKeys: String, CodingKey {
        case playSessionID = "PlaySessionId"
        case mediaSources = "MediaSources"
    }
}

struct JellyfinItemsResponse: Codable {
    var items: [JellyfinItem]
    var totalRecordCount: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

struct JellyfinAuthResponse: Codable {
    var user: JellyfinItem
    var accessToken: String
    var serverID: String?

    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
        case serverID = "ServerId"
    }
}

public enum JellyfinError: LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case notFound
    case httpStatus(Int)
    case invalidResponse(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Jellyfin 地址无效"
        case .unauthorized: return "Jellyfin 用户名或密码不正确"
        case .notFound: return "Jellyfin 条目不存在"
        case .httpStatus(let code): return "Jellyfin 返回 HTTP \(code)"
        case .invalidResponse(let message): return "Jellyfin 响应无法解析：\(message)"
        case .network(let message): return "网络错误：\(message)"
        }
    }
}

public enum JellyfinTicks {
    public static let perSecond: Int64 = 10_000_000
    public static func seconds(_ ticks: Int64?) -> Double {
        guard let ticks, ticks > 0 else { return 0 }
        return Double(ticks) / Double(perSecond)
    }
    public static func from(seconds: Double) -> Int64 {
        Int64(max(0, seconds) * Double(perSecond))
    }
}

public actor JellyfinClient {
    public let source: JellyfinSource
    private let token: String
    private let session: URLSession

    public init(source: JellyfinSource, token: String) {
        self.source = source
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    public nonisolated func url(path: String) -> URL {
        var base = source.normalizedBaseURL
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            base.appendPathComponent(String(component))
        }
        return base
    }

    private func request(_ url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw JellyfinError.invalidResponse("非 HTTP 响应")
            }
            guard (200..<300).contains(http.statusCode) else {
                switch http.statusCode {
                case 401, 403: throw JellyfinError.unauthorized
                case 404: throw JellyfinError.notFound
                default: throw JellyfinError.httpStatus(http.statusCode)
                }
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as JellyfinError {
            throw error
        } catch let error as DecodingError {
            throw JellyfinError.invalidResponse(String(describing: error))
        } catch {
            throw JellyfinError.network(error.localizedDescription)
        }
    }

    private func performEmpty(_ request: URLRequest) async throws {
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            guard (200..<300).contains(http.statusCode) else {
                throw JellyfinError.httpStatus(http.statusCode)
            }
        } catch let error as JellyfinError {
            throw error
        } catch {
            throw JellyfinError.network(error.localizedDescription)
        }
    }

    public static func authenticate(source: JellyfinSource, password: String) async throws -> JellyfinSession {
        var request = URLRequest(url: source.normalizedBaseURL.appendingPathComponent("Users/AuthenticateByName"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "MediaBrowser Client=\"OpenFuse\", Device=\"Mac\", DeviceId=\"\(source.deviceID)\", Version=\"0.1.0\"",
            forHTTPHeaderField: "X-Emby-Authorization"
        )
        request.httpBody = try JSONEncoder().encode(["Username": source.username, "Pw": password])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw JellyfinError.invalidResponse("非 HTTP 响应")
            }
            guard (200..<300).contains(http.statusCode) else {
                switch http.statusCode {
                case 401, 403: throw JellyfinError.unauthorized
                default: throw JellyfinError.httpStatus(http.statusCode)
                }
            }
            let decoded = try JSONDecoder().decode(JellyfinAuthResponse.self, from: data)
            return JellyfinSession(
                accessToken: decoded.accessToken,
                userID: decoded.user.id,
                serverID: decoded.serverID,
                userName: decoded.user.name
            )
        } catch let error as JellyfinError {
            throw error
        } catch {
            throw JellyfinError.network(error.localizedDescription)
        }
    }

    public func views() async throws -> [JellyfinItem] {
        guard let userID = source.userID else { throw JellyfinError.unauthorized }
        let response = try await perform(
            request(url(path: "Users/\(userID)/Views")),
            as: JellyfinItemsResponse.self
        )
        return response.items
    }

    public func items(parentID: String?) async throws -> [JellyfinItem] {
        guard let userID = source.userID else { throw JellyfinError.unauthorized }
        var components = URLComponents(url: url(path: "Users/\(userID)/Items"), resolvingAgainstBaseURL: false)
        var query = [
            URLQueryItem(name: "Fields", value: "Overview,Genres,MediaSources,MediaStreams,ParentId,SeriesName,IndexNumber,ParentIndexNumber,RunTimeTicks,ProductionYear"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
            URLQueryItem(name: "ImageTypeLimit", value: "1"),
            URLQueryItem(name: "EnableImageTypes", value: "Primary"),
            URLQueryItem(name: "Limit", value: "500"),
        ]
        if let parentID { query.append(URLQueryItem(name: "ParentId", value: parentID)) }
        components?.queryItems = query
        guard let requestURL = components?.url else { throw JellyfinError.invalidURL }
        let response = try await perform(request(requestURL), as: JellyfinItemsResponse.self)
        return response.items
    }

    public func libraryItems(parentID: String) async throws -> [JellyfinItem] {
        guard let userID = source.userID else { throw JellyfinError.unauthorized }
        var components = URLComponents(url: url(path: "Users/\(userID)/Items"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "ParentId", value: parentID),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "IncludeItemTypes", value: "Movie,Series,Season,Episode"),
            URLQueryItem(name: "Fields", value: "Overview,Genres,ParentId,SeriesName,IndexNumber,ParentIndexNumber,RunTimeTicks,ProductionYear,SeriesId,SeasonId"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
            URLQueryItem(name: "ImageTypeLimit", value: "1"),
            URLQueryItem(name: "EnableImageTypes", value: "Primary"),
            URLQueryItem(name: "Limit", value: "5000"),
        ]
        guard let requestURL = components?.url else { throw JellyfinError.invalidURL }
        let response = try await perform(request(requestURL), as: JellyfinItemsResponse.self)
        return response.items
    }

    public func item(id: String) async throws -> JellyfinItem {
        guard let userID = source.userID else { throw JellyfinError.unauthorized }
        return try await perform(
            request(url(path: "Users/\(userID)/Items/\(id)")),
            as: JellyfinItem.self
        )
    }

    public func playbackInfo(itemID: String) async throws -> JellyfinPlaybackInfo {
        guard let userID = source.userID else { throw JellyfinError.unauthorized }
        var components = URLComponents(url: url(path: "Items/\(itemID)/PlaybackInfo"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "UserId", value: userID)]
        guard let requestURL = components?.url else { throw JellyfinError.invalidURL }
        let body = try JSONSerialization.data(withJSONObject: [
            "UserId": userID,
            "StartTimeTicks": 0,
            "IsPlayback": true,
            "AutoOpenLiveStream": true,
            "MaxStreamingBitrate": 120_000_000,
        ])
        return try await perform(request(requestURL, method: "POST", body: body), as: JellyfinPlaybackInfo.self)
    }

    public nonisolated func streamURL(itemID: String, mediaSource: JellyfinMediaSource) -> URL? {
        let fallback = "/Videos/\(itemID)/stream?Static=true&MediaSourceId=\(mediaSource.id)"
        let path: String?
        if mediaSource.supportsDirectPlay == true {
            path = mediaSource.directStreamURL ?? fallback
        } else if mediaSource.supportsDirectStream == true {
            path = mediaSource.directStreamURL ?? fallback
        } else {
            path = mediaSource.transcodingURL ?? mediaSource.directStreamURL ?? fallback
        }
        guard let path else { return nil }
        guard let relative = URL(string: path, relativeTo: source.normalizedBaseURL) else { return nil }
        let absolute = relative.absoluteURL
        guard let components = URLComponents(url: absolute, resolvingAgainstBaseURL: false) else { return nil }
        // The token header is used by mpv; keep the URL free of credentials.
        return components.url
    }

    public nonisolated func hlsURL(itemID: String, mediaSourceID: String, token: String) -> URL? {
        var components = URLComponents(url: url(path: "Videos/\(itemID)/master.m3u8"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "MediaSourceId", value: mediaSourceID),
            URLQueryItem(name: "VideoCodec", value: "h264"),
            URLQueryItem(name: "AudioCodec", value: "aac"),
            URLQueryItem(name: "TranscodingContainer", value: "ts"),
            URLQueryItem(name: "TranscodingProtocol", value: "hls"),
            URLQueryItem(name: "SegmentContainer", value: "ts"),
            URLQueryItem(name: "DeviceId", value: source.deviceID),
            URLQueryItem(name: "api_key", value: token),
        ]
        return components?.url
    }

    public nonisolated func imageURL(itemID: String, tag: String?, maxWidth: Int = 480) -> URL? {
        var components = URLComponents(url: url(path: "Items/\(itemID)/Images/Primary"), resolvingAgainstBaseURL: false)
        var query = [
            URLQueryItem(name: "maxWidth", value: String(maxWidth)),
            URLQueryItem(name: "quality", value: "90"),
            URLQueryItem(name: "api_key", value: token),
        ]
        if let tag { query.append(URLQueryItem(name: "tag", value: tag)) }
        components?.queryItems = query
        return components?.url
    }

    public func reportStart(
        itemID: String,
        mediaSourceID: String,
        playSessionID: String?,
        position: Double,
        isPaused: Bool
    ) async {
        await report(
            path: "Sessions/Playing",
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playSessionID: playSessionID,
            position: position,
            isPaused: isPaused,
            playMethod: "DirectPlay"
        )
    }

    public func reportProgress(
        itemID: String,
        mediaSourceID: String,
        playSessionID: String?,
        position: Double,
        isPaused: Bool
    ) async {
        await report(
            path: "Sessions/Playing/Progress",
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playSessionID: playSessionID,
            position: position,
            isPaused: isPaused,
            playMethod: "DirectPlay"
        )
    }

    public func reportStopped(
        itemID: String,
        mediaSourceID: String,
        playSessionID: String?,
        position: Double
    ) async {
        await report(
            path: "Sessions/Playing/Stopped",
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playSessionID: playSessionID,
            position: position,
            isPaused: true,
            playMethod: "DirectPlay"
        )
    }

    private func report(
        path: String,
        itemID: String,
        mediaSourceID: String,
        playSessionID: String?,
        position: Double,
        isPaused: Bool,
        playMethod: String
    ) async {
        var payload: [String: Any] = [
            "ItemId": itemID,
            "MediaSourceId": mediaSourceID,
            "PositionTicks": JellyfinTicks.from(seconds: position),
            "CanSeek": true,
            "IsPaused": isPaused,
            "IsMuted": false,
            "PlayMethod": playMethod,
            "RepeatMode": "RepeatNone",
        ]
        if let playSessionID { payload["PlaySessionId"] = playSessionID }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let request = request(url(path: path), method: "POST", body: body)
        _ = try? await performEmpty(request)
    }
}
