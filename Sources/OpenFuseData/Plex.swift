import CryptoKit
import Foundation

public struct PlexSource: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var baseURL: URL

    public init(id: String? = nil, name: String, baseURL: URL) {
        self.baseURL = baseURL
        self.name = name
        self.id = id ?? Self.makeID(baseURL: baseURL)
    }

    public static func makeID(baseURL: URL) -> String {
        let material = "plex|\(baseURL.absoluteString)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public var normalizedBaseURL: URL {
        var value = baseURL
        if value.path.hasSuffix("/") { value.deleteLastPathComponent() }
        return value
    }
}

public struct PlexSection: Codable, Hashable, Identifiable, Sendable {
    public var key: String
    public var type: String
    public var title: String
    public var id: String { key }
}

public struct PlexPart: Codable, Hashable, Sendable {
    public var key: String
    public var file: String?
    public var size: Int64?
}

public struct PlexMedia: Codable, Hashable, Sendable {
    public var videoResolution: String?
    public var container: String?
    public var parts: [PlexPart]?

    enum CodingKeys: String, CodingKey {
        case videoResolution, container
        case parts = "Part"
    }
}

public struct PlexMetadata: Codable, Hashable, Sendable {
    public var ratingKey: String
    public var key: String?
    public var type: String?
    public var title: String
    public var year: Int?
    public var summary: String?
    public var thumb: String?
    public var addedAt: Int64?
    public var duration: Int64?
    public var parentIndex: Int?
    public var index: Int?
    public var grandparentTitle: String?
    public var media: [PlexMedia]?

    enum CodingKeys: String, CodingKey {
        case ratingKey, key, type, title, year, summary, thumb, addedAt, duration
        case parentIndex, index, grandparentTitle
        case media = "Media"
    }
}

public enum PlexError: LocalizedError, Sendable {
    case invalidURL(String)
    case httpStatus(Int)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let value): return "Plex 地址无效：\(value)"
        case .httpStatus(let code): return "Plex 返回 HTTP \(code)"
        case .invalidResponse(let message): return "Plex 响应错误：\(message)"
        }
    }
}

public actor PlexClient {
    public let source: PlexSource
    private let token: String
    private let session: URLSession

    public init(source: PlexSource, token: String) {
        self.source = source
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    public nonisolated func streamURL(partKey: String) -> URL? {
        var components = URLComponents(
            url: URL(string: partKey, relativeTo: source.normalizedBaseURL)?.absoluteURL ?? source.normalizedBaseURL,
            resolvingAgainstBaseURL: false
        )
        var query = components?.queryItems ?? []
        query.append(URLQueryItem(name: "X-Plex-Token", value: token))
        components?.queryItems = query
        return components?.url
    }

    public nonisolated func imageURL(thumb: String) -> URL? {
        streamURL(partKey: thumb)
    }

    public func sections() async throws -> [PlexSection] {
        let response: PlexEnvelope<PlexDirectoryContainer> = try await get("library/sections")
        return response.mediaContainer.directory ?? []
    }

    public func items(sectionKey: String) async throws -> [PlexMetadata] {
        let response: PlexEnvelope<PlexMetadataContainer> = try await get("library/sections/\(sectionKey)/all")
        return response.mediaContainer.metadata ?? []
    }

    public func children(ratingKey: String) async throws -> [PlexMetadata] {
        let response: PlexEnvelope<PlexMetadataContainer> = try await get("library/metadata/\(ratingKey)/children")
        return response.mediaContainer.metadata ?? []
    }

    public func reportTimeline(
        ratingKey: String,
        partKey: String,
        state: String,
        time: Double,
        duration: Double
    ) async {
        let milliseconds = Int(max(0, time) * 1000)
        let durationMS = Int(max(0, duration) * 1000)
        var components = URLComponents(
            url: source.normalizedBaseURL.appendingPathComponent(":/timeline"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "ratingKey", value: ratingKey),
            URLQueryItem(name: "key", value: partKey),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "time", value: String(milliseconds)),
            URLQueryItem(name: "duration", value: String(durationMS)),
            URLQueryItem(name: "X-Plex-Token", value: token),
        ]
        guard let url = components?.url else { return }
        _ = try? await session.data(from: url)
    }

    public func scrobble(ratingKey: String) async {
        var components = URLComponents(
            url: source.normalizedBaseURL.appendingPathComponent(":/scrobble"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "key", value: ratingKey),
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
            URLQueryItem(name: "X-Plex-Token", value: token),
        ]
        guard let url = components?.url else { return }
        _ = try? await session.data(from: url)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var components = URLComponents(
            url: source.normalizedBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        guard let url = components?.url else { throw PlexError.invalidURL(path) }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OpenFuse", forHTTPHeaderField: "X-Plex-Product")
        request.setValue("OpenFuse", forHTTPHeaderField: "X-Plex-Client-Identifier")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlexError.invalidResponse("非 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PlexError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct PlexEnvelope<T: Decodable>: Decodable {
    var mediaContainer: T
    enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" }
}

private struct PlexDirectoryContainer: Decodable {
    var directory: [PlexSection]?
    enum CodingKeys: String, CodingKey { case directory = "Directory" }
}

private struct PlexMetadataContainer: Decodable {
    var metadata: [PlexMetadata]?
    enum CodingKeys: String, CodingKey { case metadata = "Metadata" }
}

public final class PlexSourceStore: @unchecked Sendable {
    private struct Snapshot: Codable {
        var version: Int = 1
        var sources: [PlexSource] = []
    }

    private let fileURL: URL
    private var snapshot: Snapshot
    private let lock = NSLock()

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("plex-sources.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.openFuse.decode(Snapshot.self, from: data) {
            self.snapshot = decoded
        } else {
            self.snapshot = Snapshot()
        }
    }

    public var sources: [PlexSource] {
        lock.lock(); defer { lock.unlock() }
        return snapshot.sources
    }

    public func upsert(_ source: PlexSource) throws {
        lock.lock(); defer { lock.unlock() }
        if let index = snapshot.sources.firstIndex(where: { $0.id == source.id }) {
            snapshot.sources[index] = source
        } else {
            snapshot.sources.append(source)
        }
        try flushLocked()
    }

    public func remove(id: String) throws {
        lock.lock(); defer { lock.unlock() }
        snapshot.sources.removeAll { $0.id == id }
        try flushLocked()
    }

    private func flushLocked() throws {
        let data = try JSONEncoder.openFuse.encode(snapshot)
        let temporary = fileURL.appendingPathExtension("tmp")
        try data.write(to: temporary, options: .atomic)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
    }
}

public enum PlexLibraryScanner {
    public static func scan(source: PlexSource, client: PlexClient) async throws -> ScannedLibrary {
        let sections = try await client.sections()
        var works: [ScannedWork] = []
        for section in sections {
            switch section.type {
            case "movie":
                let movies = try await client.items(sectionKey: section.key)
                for movie in movies where (movie.type ?? "movie") == "movie" {
                    guard let work = buildMovie(movie: movie, source: source, client: client) else { continue }
                    works.append(work)
                }
            case "show":
                let shows = try await client.items(sectionKey: section.key)
                for show in shows where (show.type ?? "show") == "show" {
                    if let work = await buildShow(show, source: source, client: client) {
                        works.append(work)
                    }
                }
            default:
                continue
            }
        }
        return ScannedLibrary(
            sourceKind: "plex",
            sourceID: source.id,
            sourceName: source.name,
            works: works.sorted { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending }
        )
    }

    private static func buildMovie(movie: PlexMetadata, source: PlexSource, client: PlexClient) -> ScannedWork? {
        guard let part = movie.media?.first?.parts?.first else { return nil }
        let id = "plex:\(source.id):\(movie.ratingKey)"
        let media = movie.media?.first
        let resolution = resolutionLabel(media?.videoResolution)
        let version = ScannedVersion(
            id: id + "-v0",
            name: resolution ?? media?.container?.uppercased() ?? "Plex",
            mediaSourceID: nil,
            container: media?.container,
            resolution: resolution,
            remotePath: part.key,
            fileURL: nil
        )
        let episode = ScannedEpisode(
            id: id + "-main",
            seasonNumber: 0,
            episodeNumber: 1,
            title: movie.title,
            overview: movie.summary,
            runtime: Double(movie.duration ?? 0) / 1000,
            poster: nil,
            serverID: movie.ratingKey,
            remotePath: part.key,
            remoteVariant: nil,
            fileURL: nil,
            versions: [version]
        )
        let poster = PosterRef.plex(itemID: movie.ratingKey)
        return ScannedWork(
            id: id,
            kind: .movie,
            title: movie.title,
            sortTitle: movie.title,
            year: movie.year,
            overview: movie.summary,
            poster: poster,
            sourceKind: "plex",
            sourceID: source.id,
            serverID: movie.ratingKey,
            addedAt: movie.addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            seasons: [],
            movie: episode
        )
    }

    private static func buildShow(_ show: PlexMetadata, source: PlexSource, client: PlexClient) async -> ScannedWork? {
        guard let seasonsMetadata = try? await client.children(ratingKey: show.ratingKey) else { return nil }
        var seasons: [ScannedSeason] = []
        for seasonMeta in seasonsMetadata where (seasonMeta.type ?? "") == "season" {
            guard let episodesMetadata = try? await client.children(ratingKey: seasonMeta.ratingKey) else { continue }
            var episodes: [ScannedEpisode] = []
            for episodeMeta in episodesMetadata where (episodeMeta.type ?? "") == "episode" {
                guard let part = episodeMeta.media?.first?.parts?.first else { continue }
                let season = episodeMeta.parentIndex ?? seasonMeta.index ?? 1
                let number = episodeMeta.index ?? 0
                let media = episodeMeta.media?.first
                let episodeID = "plex:\(source.id):\(episodeMeta.ratingKey)"
                let version = ScannedVersion(
                    id: episodeID + "-v0",
                    name: resolutionLabel(media?.videoResolution) ?? "Plex",
                    mediaSourceID: nil,
                    container: media?.container,
                    resolution: resolutionLabel(media?.videoResolution),
                    remotePath: part.key,
                    fileURL: nil
                )
                episodes.append(
                    ScannedEpisode(
                        id: episodeID,
                        seasonNumber: season,
                        episodeNumber: number,
                        title: episodeMeta.title,
                        overview: episodeMeta.summary,
                        runtime: Double(episodeMeta.duration ?? 0) / 1000,
                        poster: nil,
                        serverID: episodeMeta.ratingKey,
                        remotePath: part.key,
                        remoteVariant: nil,
                        fileURL: nil,
                        versions: [version]
                    )
                )
            }
            if !episodes.isEmpty {
                seasons.append(
                    ScannedSeason(
                        id: "plex:\(source.id):\(seasonMeta.ratingKey)",
                        number: seasonMeta.index ?? 1,
                        title: seasonMeta.title,
                        poster: PosterRef.plex(itemID: seasonMeta.ratingKey),
                        episodes: episodes
                    )
                )
            }
        }
        guard !seasons.isEmpty else { return nil }
        let id = "plex:\(source.id):\(show.ratingKey)"
        let poster = PosterRef.plex(itemID: show.ratingKey)
        return ScannedWork(
            id: id,
            kind: .series,
            title: show.title,
            sortTitle: show.title,
            year: show.year,
            overview: show.summary,
            poster: poster,
            sourceKind: "plex",
            sourceID: source.id,
            serverID: show.ratingKey,
            addedAt: show.addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            seasons: seasons,
            movie: nil
        )
    }

    private static func resolutionLabel(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if value.lowercased() == "4k" { return "2160p" }
        if value.lowercased().contains("1080") { return "1080p" }
        if value.lowercased().contains("720") { return "720p" }
        return value
    }
}
